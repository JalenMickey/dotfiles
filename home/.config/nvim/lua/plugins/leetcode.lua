return {
  {
    'kawre/leetcode.nvim',
    build = ':TSUpdate html',
    cmd = 'Leet',
    dependencies = {
      'nvim-lua/plenary.nvim',
      'MunifTanjim/nui.nvim',
      'nvim-treesitter/nvim-treesitter',
    },
    opts = {
      lang = 'python3',
      plugins = {
        non_standalone = true, -- lets `:Leet` open inside a session with other buffers; close with `:Leet exit`
      },
    },
  },
}
