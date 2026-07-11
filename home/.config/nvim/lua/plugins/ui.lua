return {
  {
    'folke/which-key.nvim',
    lazy = false,
    config = true,  -- popup that shows what my leader keys do
  },
  {
    'rose-pine/neovim',
    name = 'rose-pine',
    lazy = false,
    priority = 1000,  -- load the theme before everything else
    config = function()
      require('rose-pine').setup({
        variant = 'moon',                  -- matches the WezTerm rose-pine-moon scheme
        styles = { transparent = true },   -- let the WezTerm background + blur show through
      })
      vim.cmd('colorscheme rose-pine')
      -- Force the editor backgrounds to be see-through so the WezTerm blur shows
      -- through the whole pane, not just the border. Clears the groups rose-pine
      -- can still paint solid.
      for _, group in ipairs({ 'Normal', 'NormalNC', 'NormalFloat', 'SignColumn', 'EndOfBuffer' }) do
        vim.api.nvim_set_hl(0, group, { bg = 'none' })
      end
    end,
  },
}

