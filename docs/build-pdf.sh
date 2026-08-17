#!/usr/bin/env bash
#
# Regenerate the polished PDF snapshot from the Markdown source.
#
#   ./docs/build-pdf.sh                 # docs/agentic-workflow.md -> docs/agentic-workflow.pdf
#   ./docs/build-pdf.sh in.md out.pdf   # explicit paths
#
# Pipeline mirrors how the snapshot was first made: Markdown -> HTML (marked,
# GitHub-flavored so the tables render) -> headless-Chrome print-to-PDF
# (Skia/PDF). No LaTeX toolchain, no global installs - marked is fetched
# on-demand via npx, and any installed Chrome/Brave/Chromium does the print.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${1:-$here/agentic-workflow.md}"
out="${2:-$here/agentic-workflow.pdf}"

[ -f "$src" ] || { echo "error: source not found: $src" >&2; exit 1; }
command -v npx >/dev/null || { echo "error: npx (Node) not found on PATH" >&2; exit 1; }

# Locate a Chromium-family binary for --print-to-pdf.
chrome=""
for c in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser" \
  "/Applications/Chromium.app/Contents/MacOS/Chromium" \
  "$(command -v chromium 2>/dev/null || true)" \
  "$(command -v google-chrome 2>/dev/null || true)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then chrome="$c"; break; fi
done
[ -n "$chrome" ] || { echo "error: no Chrome/Brave/Chromium found for print-to-pdf" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. Markdown -> HTML fragment (GFM for the tables).
npx -y marked --gfm -i "$src" -o "$tmp/body.html"

# 2. Wrap in the print stylesheet. Quoted heredoc: nothing here is expanded.
cat > "$tmp/print.html" <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><style>
  @page { size: Letter; margin: 0.7in 0.72in; }
  * { box-sizing: border-box; }
  html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
  body {
    font-family: -apple-system, "Helvetica Neue", Arial, sans-serif;
    font-size: 10.5px; line-height: 1.5; color: #16181d; margin: 0; max-width: 100%;
  }
  h1, h2, h3, h4 { line-height: 1.2; font-weight: 700; break-after: avoid; }
  h1 { font-size: 22px; letter-spacing: -0.01em; margin: 0 0 4px; }
  h2 { font-size: 15px; margin: 22px 0 8px; padding-top: 10px; border-top: 1px solid #d8dee3; }
  h3 { font-size: 12.5px; margin: 16px 0 6px; color: #1c4f63; }
  p { margin: 6px 0; }
  a { color: #155469; text-decoration: none; }
  hr { border: none; border-top: 1px solid #d8dee3; margin: 16px 0; }
  ul, ol { margin: 6px 0; padding-left: 20px; }
  li { margin: 3px 0; }
  code {
    font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 9.2px;
    background: #eef1f4; border: 1px solid #e0e5ea; border-radius: 3px; padding: 0.5px 3px;
  }
  pre {
    background: #f6f8fa; border: 1px solid #e0e5ea; border-radius: 6px;
    padding: 9px 11px; overflow-x: auto; break-inside: avoid;
  }
  pre code { background: none; border: none; padding: 0; font-size: 9px; line-height: 1.5; }
  blockquote {
    margin: 9px 0; padding: 7px 12px; border-left: 3px solid #1c6c88;
    background: #f2f7f9; border-radius: 0 5px 5px 0; break-inside: avoid;
  }
  blockquote p { margin: 3px 0; }
  table { border-collapse: collapse; width: 100%; margin: 10px 0; font-size: 9.3px; }
  th, td { border: 1px solid #d3dae0; padding: 5px 8px; text-align: left; vertical-align: top; }
  th { background: #eaeef1; font-weight: 700; }
  tr { break-inside: avoid; }
  thead { display: table-header-group; }
  h1 + p { color: #4a5560; font-size: 9.5px; }
</style></head><body>
HTML
cat "$tmp/body.html" >> "$tmp/print.html"
printf '</body></html>' >> "$tmp/print.html"

# 3. Render to PDF. Chrome emits harmless task_policy warnings on stderr; drop them.
"$chrome" --headless=new --disable-gpu --no-pdf-header-footer \
  --print-to-pdf="$out" "file://$tmp/print.html" 2>/dev/null || true

[ -s "$out" ] || { echo "error: Chrome did not produce a PDF at $out" >&2; exit 1; }
echo "wrote $out ($(wc -c < "$out") bytes) via $(basename "$chrome")"
