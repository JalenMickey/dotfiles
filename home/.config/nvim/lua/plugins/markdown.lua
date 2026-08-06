return {
  {
    'ellisonleao/glow.nvim',
    cmd = 'Glow',  -- lazy-load: only starts on first :Glow call
    opts = {},
    keys = { { '<leader>m', '<cmd>Glow<cr>', desc = 'Markdown Preview' } },
  },
}
