{ pkgs, ... }:

let
  theme = import ./theme/onedark.nix;

  treesitterWithGrammars = pkgs.vimPlugins.nvim-treesitter.withPlugins (
    p: with p; [
      typescript
      tsx
      javascript
      json
      nix
      python
      rust
      go
      lua
      bash
      markdown
      markdown_inline
      html
      css
    ]
  );
in
{
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = false; # micro stays $EDITOR for now -- this is a parallel trial, not a switch

    extraPackages = [
      pkgs.ripgrep # telescope live_grep
      pkgs.fd # telescope find_files
    ];

    plugins = with pkgs.vimPlugins; [
      treesitterWithGrammars
      nvim-treesitter-textobjects

      nvim-lspconfig

      nvim-cmp
      cmp-nvim-lsp
      cmp-buffer
      cmp-path
      luasnip
      cmp_luasnip

      telescope-nvim
      plenary-nvim
      telescope-fzf-native-nvim
      nvim-web-devicons

      lualine-nvim
      nvim-autopairs
      indent-blankline-nvim
      gitsigns-nvim
      which-key-nvim
    ];

    initLua = ''
      -- ============================================================
      -- Basics
      -- ============================================================
      vim.g.mapleader = ' '
      vim.g.maplocalleader = ' '

      vim.opt.number = true
      vim.opt.relativenumber = false
      vim.opt.mouse = 'a'
      vim.opt.wrap = true
      vim.opt.linebreak = true          -- wrap on word boundaries, not mid-word
      vim.opt.breakindent = true        -- wrapped lines keep the original indent
      vim.opt.tabstop = 2
      vim.opt.shiftwidth = 2
      vim.opt.expandtab = true
      vim.opt.smartindent = true
      vim.opt.ignorecase = true
      vim.opt.smartcase = true
      vim.opt.termguicolors = true
      vim.opt.signcolumn = 'yes'
      vim.opt.updatetime = 250
      vim.opt.splitright = true
      vim.opt.splitbelow = true
      vim.opt.scrolloff = 8
      vim.opt.undofile = true

      -- System clipboard by default -- y/d/p use the real clipboard instead
      -- of vim's own registers, so copy/paste works the way every other
      -- app on this desktop already does. This is the single highest-value
      -- change for someone coming from a modeless editor.
      vim.opt.clipboard = 'unnamedplus'

      -- Basic navigation (arrows, Home/End, PageUp/Down, Backspace/Delete)
      -- already works identically to any other editor in both Normal and
      -- Insert mode -- nothing to configure there. hjkl is an addition on
      -- top of that, not a replacement for it.

      -- ============================================================
      -- Keymaps -- a few bridges from muscle memory, layered on top of
      -- real vim motions rather than replacing them. Comment says what it
      -- collides with, if anything, so you know the actual tradeoff.
      -- ============================================================
      local map = vim.keymap.set

      -- Save: works from Normal AND Insert mode without needing to leave
      -- insert mode first.
      map({ 'n', 'i', 'v' }, '<C-s>', '<Esc>:w<CR>', { desc = 'Save' })

      -- Quit (matches every other tool set up on this desktop this session).
      map('n', '<C-q>', ':q<CR>', { desc = 'Quit' })

      -- Undo/redo aliases alongside vim's own u / <C-r>.
      map({ 'n', 'i' }, '<C-z>', '<Esc>u', { desc = 'Undo' })
      map({ 'n', 'i' }, '<C-y>', '<Esc><C-r>', { desc = 'Redo' })

      -- Select all. Overrides vim's default <C-a> (increment number under
      -- cursor) -- a real tradeoff, but select-all is the far more common
      -- need early on; increment is still reachable as `+` if you want it.
      map('n', '<C-a>', 'ggVG', { desc = 'Select all' })
      -- '+' was a free key (not bound by anything else here), so increment
      -- moves there instead of being lost entirely.
      map('n', '+', '<C-a>', { desc = 'Increment number (moved off C-a)' })

      -- Paste over C-v in Insert mode only -- Normal-mode <C-v> (visual
      -- block select) is untouched, since that's a real vim feature worth
      -- keeping and rarely what someone reaches for mid-typing anyway.
      map('i', '<C-v>', '<C-r>+', { desc = 'Paste' })

      -- Comment toggle -- built into Neovim core since 0.10 (gc / gcc);
      -- this just adds the muscle-memory alias from everywhere else this
      -- session used Ctrl+/.
      map({ 'n', 'v' }, '<C-_>', 'gcc', { remap = true, desc = 'Toggle comment' })
      map('v', '<C-_>', 'gc', { remap = true, desc = 'Toggle comment (selection)' })

      -- Word wrap toggle, matching micro's own toggle.
      map('n', '<leader>tw', function()
        vim.opt.wrap = not vim.opt.wrap:get()
      end, { desc = 'Toggle word wrap' })

      -- Window/split navigation -- Ctrl+direction, same as most terminal
      -- multiplexers and editors.
      map('n', '<C-h>', '<C-w>h', { desc = 'Go to left split' })
      map('n', '<C-l>', '<C-w>l', { desc = 'Go to right split' })
      map('n', '<C-j>', '<C-w>j', { desc = 'Go to split below' })
      map('n', '<C-k>', '<C-w>k', { desc = 'Go to split above' })

      -- ============================================================
      -- Telescope -- fuzzy finder, doubles as the "how do I do X" escape
      -- hatch: <leader>fc searches every available command by name, so you
      -- never have to remember a binding, just what you're trying to do.
      -- ============================================================
      require('telescope').setup({})
      pcall(require('telescope').load_extension, 'fzf')
      local tb = require('telescope.builtin')
      map('n', '<leader>ff', tb.find_files, { desc = 'Find files' })
      map('n', '<leader>fg', tb.live_grep, { desc = 'Grep in project' })
      map('n', '<leader>fb', tb.buffers, { desc = 'Find buffers' })
      map('n', '<leader>fc', tb.commands, { desc = 'Find commands' })
      map('n', '<leader>fh', tb.help_tags, { desc = 'Find help' })
      map('n', '<C-p>', tb.find_files, { desc = 'Find files (VS Code-style)' })

      -- ============================================================
      -- Treesitter -- grammars are vendored via Nix (treesitterWithGrammars
      -- in the .nix file), not fetched at runtime via :TSInstall.
      -- ============================================================
      require('nvim-treesitter.configs').setup({
        highlight = { enable = true },
        indent = { enable = true },
      })

      -- ============================================================
      -- LSP -- native vim.lsp.enable() (Neovim 0.11+), not the older
      -- require('lspconfig').X.setup{} pattern. Server binaries are
      -- already on PATH system-wide (see home/micro.nix's home.packages +
      -- configuration.nix's environment.systemPackages), so nvim-lspconfig's
      -- bundled default cmd for each of these just works without
      -- per-server config here.
      -- ============================================================
      vim.lsp.enable({ 'ts_ls', 'nixd', 'pylsp', 'rust_analyzer', 'gopls', 'lua_ls', 'bashls' })

      vim.api.nvim_create_autocmd('LspAttach', {
        callback = function(ev)
          local opts = { buffer = ev.buf }
          map('n', 'gd', vim.lsp.buf.definition, opts)
          map('n', 'gr', vim.lsp.buf.references, opts)
          map('n', 'K', vim.lsp.buf.hover, opts)
          map('n', '<leader>rn', vim.lsp.buf.rename, opts)
          map('n', '<leader>ca', vim.lsp.buf.code_action, opts)
          map('n', '<leader>d', vim.diagnostic.open_float, opts)
          map('n', '[d', vim.diagnostic.goto_prev, opts)
          map('n', ']d', vim.diagnostic.goto_next, opts)
        end,
      })

      -- ============================================================
      -- Completion
      -- ============================================================
      local cmp = require('cmp')
      cmp.setup({
        snippet = {
          expand = function(args)
            require('luasnip').lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ['<C-Space>'] = cmp.mapping.complete(),
          ['<CR>'] = cmp.mapping.confirm({ select = true }),
          ['<Tab>'] = cmp.mapping.select_next_item(),
          ['<S-Tab>'] = cmp.mapping.select_prev_item(),
        }),
        sources = cmp.config.sources({
          { name = 'nvim_lsp' },
          { name = 'luasnip' },
        }, {
          { name = 'buffer' },
          { name = 'path' },
        }),
      })

      -- ============================================================
      -- Autopairs, indent guides, git signs, statusline, which-key
      -- ============================================================
      require('nvim-autopairs').setup({})
      require('ibl').setup({})
      require('gitsigns').setup({})
      require('which-key').setup({})
      require('lualine').setup({
        options = { theme = 'onedark-tal7aouy' },
      })

      -- ============================================================
      -- Theme
      -- ============================================================
      vim.cmd.colorscheme('onedark-tal7aouy')
    '';
  };

  # Every color is pulled from the real, installed tal7aouy.theme extension's
  # tokenColors (~/.vscode/extensions/tal7aouy.theme-3.1.0/themes/Theme.json),
  # matching the exact role mapping already established across every other
  # editor surface this session: keyword/statement -> purple, string ->
  # green, function -> blue, type/class -> yellow, variable/property/JSX
  # tag -> red, constant/number/JSX attribute -> orange, comment -> muted
  # grey, generic operator -> fg. Neovim's highlight system covers both
  # classic groups and real treesitter @-captures plus LSP semantic
  # @lsp.type.*/@lsp.mod.* groups, so this can be more precise than what
  # Fresh's 11-key theme schema allowed -- e.g. readonly (const) bindings
  # get their own semantic-token-driven color the same way eglot did for
  # Emacs, without needing a hand-rolled fallback query.
  xdg.configFile."nvim/colors/onedark-tal7aouy.lua".text = ''
    vim.cmd('hi clear')
    if vim.fn.exists('syntax_on') then
      vim.cmd('syntax reset')
    end
    vim.o.background = 'dark'
    vim.g.colors_name = 'onedark-tal7aouy'

    local hl = vim.api.nvim_set_hl

    -- Base UI
    hl(0, 'Normal', { fg = '${theme.fg}', bg = '${theme.bg}' })
    hl(0, 'NormalFloat', { fg = '${theme.fg}', bg = '${theme.surface}' })
    hl(0, 'Cursor', { fg = '${theme.bg}', bg = '${theme.blue}' })
    hl(0, 'CursorLine', { bg = '${theme.surface}' })
    hl(0, 'CursorLineNr', { fg = '${theme.fg}', bold = true })
    hl(0, 'LineNr', { fg = '${theme.comment}' })
    hl(0, 'Visual', { bg = '${theme.surface}' })
    hl(0, 'Search', { fg = '${theme.bg}', bg = '${theme.yellow}' })
    hl(0, 'IncSearch', { fg = '${theme.bg}', bg = '${theme.orange}' })
    hl(0, 'MatchParen', { fg = '${theme.purple}', bold = true })
    hl(0, 'Pmenu', { fg = '${theme.fg}', bg = '${theme.surface}' })
    hl(0, 'PmenuSel', { fg = '${theme.bg}', bg = '${theme.blue}' })
    hl(0, 'StatusLine', { fg = '${theme.fg}', bg = '${theme.surface}' })
    hl(0, 'VertSplit', { fg = '${theme.surface}' })
    hl(0, 'SignColumn', { bg = '${theme.bg}' })
    hl(0, 'Directory', { fg = '${theme.blue}' })

    -- Diagnostics
    hl(0, 'DiagnosticError', { fg = '${theme.error}' })
    hl(0, 'DiagnosticWarn', { fg = '${theme.yellow}' })
    hl(0, 'DiagnosticInfo', { fg = '${theme.blue}' })
    hl(0, 'DiagnosticHint', { fg = '${theme.cyan}' })

    -- Classic syntax groups (fallback for anything not covered by treesitter)
    hl(0, 'Comment', { fg = '${theme.comment}', italic = true })
    hl(0, 'String', { fg = '${theme.green}' })
    hl(0, 'Number', { fg = '${theme.orange}' })
    hl(0, 'Boolean', { fg = '${theme.orange}' })
    hl(0, 'Keyword', { fg = '${theme.purple}' })
    hl(0, 'Statement', { fg = '${theme.purple}' })
    hl(0, 'Conditional', { fg = '${theme.purple}' })
    hl(0, 'Repeat', { fg = '${theme.purple}' })
    hl(0, 'Operator', { fg = '${theme.fg}' })
    hl(0, 'Function', { fg = '${theme.blue}' })
    hl(0, 'Identifier', { fg = '${theme.red}' })
    hl(0, 'Type', { fg = '${theme.yellow}' })
    hl(0, 'Constant', { fg = '${theme.orange}' })
    hl(0, 'PreProc', { fg = '${theme.orange}' })
    hl(0, 'Special', { fg = '${theme.orange}' })
    hl(0, 'Delimiter', { fg = '${theme.fg}' })

    -- Treesitter captures -- @tag / @tag.attribute exist here (unlike
    -- Fresh, which drops @tag entirely), so JSX gets real coverage.
    hl(0, '@variable', { fg = '${theme.red}' })
    hl(0, '@variable.builtin', { fg = '${theme.purple}' })
    hl(0, '@variable.parameter', { fg = '${theme.fg}' })
    hl(0, '@property', { fg = '${theme.red}' })
    hl(0, '@field', { fg = '${theme.red}' })
    hl(0, '@constant', { fg = '${theme.orange}' })
    hl(0, '@constant.builtin', { fg = '${theme.orange}' })
    hl(0, '@string', { fg = '${theme.green}' })
    hl(0, '@string.regexp', { fg = '${theme.cyan}' })
    hl(0, '@string.escape', { fg = '${theme.yellow}' })
    hl(0, '@number', { fg = '${theme.orange}' })
    hl(0, '@boolean', { fg = '${theme.orange}' })
    hl(0, '@function', { fg = '${theme.blue}' })
    hl(0, '@function.call', { fg = '${theme.blue}' })
    hl(0, '@function.builtin', { fg = '${theme.cyan}' })
    hl(0, '@function.method', { fg = '${theme.blue}' })
    hl(0, '@function.method.call', { fg = '${theme.blue}' })
    hl(0, '@constructor', { fg = '${theme.yellow}' })
    hl(0, '@keyword', { fg = '${theme.purple}' })
    hl(0, '@keyword.operator', { fg = '${theme.fg}' })
    hl(0, '@keyword.import', { fg = '${theme.purple}' })
    hl(0, '@keyword.function', { fg = '${theme.purple}' })
    hl(0, '@keyword.return', { fg = '${theme.purple}' })
    hl(0, '@operator', { fg = '${theme.fg}' })
    hl(0, '@punctuation.bracket', { fg = '${theme.fg}' })
    hl(0, '@punctuation.delimiter', { fg = '${theme.fg}' })
    hl(0, '@punctuation.special', { fg = '${theme.purple}' })
    hl(0, '@type', { fg = '${theme.yellow}' })
    hl(0, '@type.builtin', { fg = '${theme.yellow}' })
    hl(0, '@comment', { fg = '${theme.comment}', italic = true })
    hl(0, '@tag', { fg = '${theme.red}' })
    hl(0, '@tag.attribute', { fg = '${theme.orange}' })
    hl(0, '@tag.delimiter', { fg = '${theme.fg}' })

    -- LSP semantic tokens -- real per-reference distinction, same
    -- mechanism as eglot for Emacs: a const-bound variable reads its
    -- @lsp.mod.readonly modifier here, so every *use* of it gets this
    -- color, not just its declaration.
    hl(0, '@lsp.type.class', { fg = '${theme.yellow}' })
    hl(0, '@lsp.type.parameter', { fg = '${theme.fg}' })
    hl(0, '@lsp.type.property', { fg = '${theme.red}' })
    hl(0, '@lsp.type.variable', { fg = '${theme.red}' })
    hl(0, '@lsp.mod.readonly', { fg = '${theme.yellow}' })
    hl(0, '@lsp.typemod.variable.readonly', { fg = '${theme.yellow}' })
    hl(0, '@lsp.typemod.property.readonly', { fg = '${theme.yellow}' })
  '';
}
