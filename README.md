# rex-navigator.nvim

**rex-navigator.nvim** lets you move between Neovim splits and [Rex](https://www.superlogical.com/rex) panes with the same keys, `<C-h>`, `<C-j>`, `<C-k>`, and `<C-l>`. It is [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) for Rex.

The plugin has two halves that work together:

- **Rex side:** `ctrl-h/j/k/l` moves between Rex panes, unless Neovim is the focused program. Then the key goes through to Neovim.
- **Neovim side:** the keys move between Neovim splits. At the last split in a direction, Neovim asks Rex to focus the next pane over.

## 📋 Requirements

- Neovim >= 0.10.0
- [Rex](https://www.superlogical.com/rex)

## 📦 Installation

### Neovim

Install **rex-navigator.nvim** with your preferred plugin manager. Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'wassimk/rex-navigator.nvim',
  version = '*',
  config = true,
}
```

> [!NOTE]
> Don't lazy load the plugin on a key or event. The keymaps need to exist when the first `ctrl-h/j/k/l` arrives from Rex.

### Rex

Rex has no plugin manager, but its configuration can `require` Lua files that sit beside `~/.config/rex/init.lua`. Link the Rex side of the plugin there, so it stays up to date with the Neovim plugin:

```shell
ln -s ~/.local/share/nvim/lazy/rex-navigator.nvim/rex/rex-navigator.lua ~/.config/rex/rex-navigator.lua
```

Then load it in `~/.config/rex/init.lua`:

```lua
require('rex-navigator').setup()
```

Apply the change with `rex config reload`.

## 🧰 Configuration

### Neovim

These are the defaults:

```lua
require('rex-navigator').setup({
  -- map <C-h/j/k/l> in normal mode
  keymaps = true,
  -- continue from the opposite edge when no Rex pane lies that way
  wrap = false,
})
```

With `keymaps = false`, map the keys yourself:

```lua
vim.keymap.set('n', '<C-h>', require('rex-navigator').left)
vim.keymap.set('n', '<C-j>', require('rex-navigator').down)
vim.keymap.set('n', '<C-k>', require('rex-navigator').up)
vim.keymap.set('n', '<C-l>', require('rex-navigator').right)
```

### Rex

These are the defaults:

```lua
require('rex-navigator').setup({
  -- physical keys, so the binding doesn't depend on the keyboard layout
  keys = {
    left = 'ctrl+[KeyH]',
    down = 'ctrl+[KeyJ]',
    up = 'ctrl+[KeyK]',
    right = 'ctrl+[KeyL]',
  },
  -- Lua patterns matched against the focused program's name
  programs = { '^n?vim$', '^view$', '^n?vimdiff$' },
  -- continue from the opposite edge when no pane lies that way
  wrap = false,
})
```

Keys you change on one side need to match on the other.

## 💻 Usage

Press `ctrl-h`, `ctrl-j`, `ctrl-k`, or `ctrl-l` to move left, down, up, or right, whether the next split is a Neovim window or a Rex pane.

Run `:checkhealth rex-navigator` to check that Neovim is running inside Rex and can find the `rex` executable.

## 🔍 How It Works

Each `ctrl-h/j/k/l` binding in Rex asks the focused terminal for its foreground process. When the process name matches one of `programs`, the binding returns `false` and Rex sends the key to the terminal, so Neovim gets it. Otherwise the binding moves focus with the server's `session.focus_direction` method.

In Neovim, the key runs `wincmd`. If the window doesn't change, Neovim runs `rex do` with the same `session.focus_direction` call, using the `REX_SESSION` environment variable that Rex sets for programs it starts.

Both sides call the server method rather than Rex's `pane.focus.*` actions. Those actions always wrap, and running them from the command line needs Rex's Remote Control setting turned on.

## 🔧 Development

Run tests and lint:

```shell
make test
make lint
```

The tests run the Rex side against a fake `rex` table, so they don't need Rex.

Enable the local git hooks (one-time setup):

```shell
git config core.hooksPath .githooks
```

This activates a pre-commit hook that checks staged Lua files with [stylua](https://github.com/JohnnyMorganz/StyLua).

Regenerate `doc/rex-navigator.nvim.txt` from this README with `make docs`. Requires [pandoc](https://pandoc.org/installing.html).
