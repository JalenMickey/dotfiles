#!/usr/bin/env bash
#
# Benchmark local omlx models head-to-head.
#
#   ./docs/bench-models.sh                   # default slot models (oc / ou)
#   ./docs/bench-models.sh modelA modelB     # explicit model ids
#
# Mirrors the §5 / §5a methodology in agentic-workflow.md, with one correction:
# prefill and decode are measured SEPARATELY. omlx's `usage` block reports only
# `model_load_duration` and `total_time`, so a single non-streaming timing
# conflates prompt processing with token generation — on a 3k-token prompt that
# is dominated by prefill and badly understates decode throughput. This script
# streams instead, timing:
#
#   prefill  = time to first token (TTFT), and input_tokens / TTFT
#   decode   = (output_tokens - 1) / (last_token_time - first_token_time)
#
# Each model is warmed with a throwaway request first, so the reported numbers
# never include the cold MLX load (tens of GB memory-mapped, ~1min worst case).
#
# NOTE (§5 caveat): do NOT run this back-to-back with other heavy model loads.
# Each model evicts the previous one's pages; a rushed run measures
# cold-reload-under-contention rather than the model. SETTLE spaces them out.
#
# Env: OMLX_HOST, OMLX_PORT, SETTLE (seconds between models, default 20)

set -euo pipefail

export OMLX_HOST="${OMLX_HOST:-127.0.0.1}"
export OMLX_PORT="${OMLX_PORT:-8000}"
export SETTLE="${SETTLE:-20}"

if [ "$#" -gt 0 ]; then
  export BENCH_MODELS="$*"
else
  # The slots declared in home.nix. See §5a. Anything not currently served is
  # skipped with a note, so adding the next model here before downloading it is
  # harmless — useful when a new slot is planned but not yet pulled.
  export BENCH_MODELS="mlx-community--Qwen3-Coder-Next-8bit Qwen3.8-27B-Uncensored-8bit"
fi

command -v python3 >/dev/null || { echo "error: python3 not found on PATH" >&2; exit 1; }

python3 - <<'PY'
import json, os, sys, time, urllib.request, urllib.error

HOST = os.environ["OMLX_HOST"]
PORT = os.environ["OMLX_PORT"]
BASE = f"http://{HOST}:{PORT}/v1"
SETTLE = float(os.environ.get("SETTLE", "20"))
MODELS = os.environ["BENCH_MODELS"].split()

with open(os.path.expanduser("~/.omlx/settings.json")) as fh:
    KEY = json.load(fh)["auth"]["api_key"]

HEADERS = {"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"}


def post(path, payload, timeout=900):
    req = urllib.request.Request(
        BASE + path, data=json.dumps(payload).encode(), headers=HEADERS, method="POST"
    )
    return urllib.request.urlopen(req, timeout=timeout)


def get(path, timeout=30):
    req = urllib.request.Request(BASE + path, headers=HEADERS)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def stream_measure(model, prompt, max_tokens):
    """Stream a completion, timing prefill (TTFT) and decode separately."""
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "temperature": 0.0,
        "stream": True,
        "stream_options": {"include_usage": True},
    }
    t0 = time.perf_counter()
    first = None
    last = None
    n_chunks = 0
    usage = {}
    finish = None
    text = []

    with post("/chat/completions", payload) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except json.JSONDecodeError:
                continue
            if obj.get("usage"):
                usage = obj["usage"]
            for ch in obj.get("choices", []):
                if ch.get("finish_reason"):
                    finish = ch["finish_reason"]
                piece = (ch.get("delta") or {}).get("content")
                if piece:
                    now = time.perf_counter()
                    if first is None:
                        first = now
                    last = now
                    n_chunks += 1
                    text.append(piece)

    total = time.perf_counter() - t0
    out_tok = usage.get("output_tokens") or usage.get("completion_tokens") or n_chunks
    in_tok = usage.get("input_tokens") or usage.get("prompt_tokens") or 0

    ttft = (first - t0) if first is not None else float("nan")
    decode_span = (last - first) if (first is not None and last is not None and last > first) else 0.0
    # out_tok-1: the first token's cost lives in TTFT, not in the decode span.
    decode_tps = ((out_tok - 1) / decode_span) if decode_span > 0 and out_tok > 1 else float("nan")
    prefill_tps = (in_tok / ttft) if ttft and ttft == ttft and ttft > 0 and in_tok else float("nan")

    return {
        "in_tok": in_tok, "out_tok": out_tok, "ttft": ttft,
        "decode_tps": decode_tps, "prefill_tps": prefill_tps,
        "total": total, "finish": finish, "text": "".join(text),
    }


def fmt(v, suffix="", nd=1):
    return "n/a" if v != v else f"{v:.{nd}f}{suffix}"


def report(label, m, ceiling=None):
    e2e = m["out_tok"] / m["total"] if m["total"] > 0 else float("nan")
    # A single SSE chunk means the server buffered the whole response: TTFT then
    # equals wall clock and measures generation, not prompt processing. Both the
    # prefill and decode splits are meaningless in that case.
    unsplit = m["decode_tps"] != m["decode_tps"]
    print(f"  {label}")
    print(f"    tokens in/out : {m['in_tok']} / {m['out_tok']}")
    pre = f"    prefill TTFT  : {fmt(m['ttft'], 's', 3)}   ({fmt(m['prefill_tps'], ' tok/s')} prompt)"
    if unsplit:
        pre += "   << not real prefill, see below"
    print(pre)
    dec = f"    decode        : {fmt(m['decode_tps'], ' tok/s')}"
    if ceiling and m["decode_tps"] == m["decode_tps"] and m["decode_tps"] > ceiling * 1.1:
        dec += f"   << ABOVE {ceiling:.0f} tok/s CEILING - artifact, not real"
    print(dec)
    print(f"    end-to-end    : {fmt(e2e, ' tok/s')}   (out_tok / wall, most trustworthy)")
    print(f"    wall clock    : {fmt(m['total'], 's', 2)}")
    print(f"    finish_reason : {m['finish']}")
    if unsplit:
        print("    NOTE: whole response arrived in ONE SSE chunk (no incremental")
        print("          streaming on this model's serving path), so prefill/decode")
        print("          cannot be separated. Use end-to-end tok/s for this model.")
    elif m["out_tok"] < 60:
        print("    WARNING: <60 output tokens - decode rate is buffering noise, ignore it")


hr = "─" * 72

print(f"omlx @ {BASE}")
try:
    served = {m["id"]: m.get("max_model_len") for m in get("/models")["data"]}
except urllib.error.URLError as e:
    print(f"error: cannot reach omlx at {BASE} ({e}). Is the server up? `omlx restart`", file=sys.stderr)
    sys.exit(1)

print("available models:")
for mid, ctx in served.items():
    print(f"  - {mid} (ctx {ctx})")
print()

missing = [m for m in MODELS if m not in served]
if missing:
    print("NOT SERVED (skipping): " + ", ".join(missing))
    print("  HF-cache models need `hf download <repo>`; ~/.omlx/models entries need")
    print("  config.json + *.safetensors at the directory ROOT, then `omlx restart`.")
    print()
MODELS = [m for m in MODELS if m in served]
if not MODELS:
    print("nothing to benchmark.")
    sys.exit(0)

# Both prompts must force a LONG generation. omlx batches several tokens into
# one SSE chunk, so a short answer (~30 tokens) makes the decode span mostly
# buffering jitter and yields absurd rates. Hundreds of tokens amortize that.
ASK = ("Write a thorough, detailed explanation of how a B-tree differs from a "
       "B+ tree. Cover node structure, leaf linkage, range scans, fanout, and "
       "why databases favor one. Write at least 600 words of prose.")

# ~3k tokens of filler, to show how throughput holds up under context — where
# dense and MoE models diverge most sharply.
LONG = ("You are reviewing a large Python service. " * 400) + "\n\n" + ASK

MAX_OUT = 512

# Hard ceiling from memory bandwidth: a model must read its active weights once
# per token. Decode rates materially above this are measurement artifacts, not
# real throughput, so the report flags them instead of quietly printing them.
BANDWIDTH_GBPS = float(os.environ.get("BANDWIDTH_GBPS", "614"))  # M5 Max
ACTIVE_GB = {  # approximate bytes read per token, at the quant actually served
    "mlx-community--Qwen3-Coder-Next-8bit": 3.3,    # MoE, ~3B active @ 8bit
    "mlx-community--Qwen3.8-27B-8bit": 29.5,        # dense, all 27B active
    "Qwen3.8-27B-Uncensored-8bit": 29.5,            # dense, all 27B active
}

results = {}

for i, model in enumerate(MODELS):
    print(hr); print(f"MODEL: {model}"); print(hr)

    print("  [warmup] cold MLX load, not measured ...", end="", flush=True)
    w0 = time.perf_counter()
    try:
        stream_measure(model, "hi", 4)
    except Exception as e:
        print(f" FAILED: {e}\n")
        continue
    print(f" {time.perf_counter() - w0:.1f}s")
    print()

    # §5 diagnostic: a reasoning model burns its budget in a <think> stream and
    # never lands a clean tool call. A coder/instruct model returns OK / stop.
    d = stream_measure(model, "reply exactly OK", 32)
    content = d["text"].strip()
    ok = d["finish"] == "stop" and len(content) <= 8
    print(f"  [sanity] reply-exactly-OK: {content[:80]!r} finish={d['finish']}")
    print(f"           verdict: {'PASS - clean stop, safe for agentic loops' if ok else 'SUSPECT - reasoning stream? see §5 gotchas'}")
    print()

    ceiling = None
    if model in ACTIVE_GB:
        ceiling = BANDWIDTH_GBPS / ACTIVE_GB[model]
        print(f"  bandwidth ceiling: ~{ceiling:.1f} tok/s "
              f"({ACTIVE_GB[model]}GB active @ {BANDWIDTH_GBPS:.0f}GB/s)")
        print()

    short = stream_measure(model, ASK, MAX_OUT)
    report(f"[short]  ~40 token prompt, {MAX_OUT} max out", short, ceiling)
    print()

    long_ = stream_measure(model, LONG, MAX_OUT)
    report(f"[long]   ~3k token prompt, {MAX_OUT} max out", long_, ceiling)
    print()

    results[model] = (short, long_, ok, ceiling)

    if i < len(MODELS) - 1 and SETTLE > 0:
        print(f"  settling {SETTLE:.0f}s (page-cache hygiene, §5 caveat)")
        time.sleep(SETTLE)
        print()

if len(results) > 1:
    print(hr); print("SUMMARY"); print(hr)
    w = max(len(m) for m in results)
    print(f"  {'model'.ljust(w)}   e2e short   e2e long   decode long   ceiling   sanity")
    for model, (s, l, ok, ceiling) in results.items():
        e2e_s = s["out_tok"] / s["total"] if s["total"] else float("nan")
        e2e_l = l["out_tok"] / l["total"] if l["total"] else float("nan")
        print(f"  {model.ljust(w)}   {fmt(e2e_s):>9}   {fmt(e2e_l):>8}   "
              f"{fmt(l['decode_tps']):>11}   {fmt(ceiling) if ceiling else 'n/a':>7}   "
              f"{'PASS' if ok else 'SUSPECT'}")
    print()
    print("  e2e     = output tokens / wall clock. The honest headline number, and the")
    print("            only one comparable across every serving path.")
    print("  decode  = pure generation, timed between first and last streamed token.")
    print("            n/a means the server sent one chunk, so it cannot be isolated.")
    print("  ceiling = memory-bandwidth limit (active weight bytes read per token).")
    print()
    print("  CAVEAT: omlx packs several tokens per SSE chunk, and some serving paths")
    print("  (the VLM one) do not stream incrementally at all. TTFT then absorbs real")
    print("  generation, biasing decode high and prefill low. Rank models by e2e; any")
    print("  decode figure above the ceiling is an artifact.")
PY
