# rex-navigator.nvim

**rex-navigator.nvim** lets you move between Neovim splits and [Rex](https://www.superlogical.com/rex) panes with **Cmd-H/J/K/L**, locally and over SSH. Rex translates those shortcuts to Neovim's `<C-h/j/k/l>` mappings. It is [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) for Rex.

The plugin has two halves that work together:

- **Rex side:** `cmd-h/j/k/l` moves between Rex panes, or sends `ctrl-h/j/k/l` to the active editor. Rex does not bind the Ctrl shortcuts itself.
- **Neovim side:** the Ctrl mappings move between splits. Locally, Neovim hands navigation back to Rex at split edges. Over SSH, Neovim publishes its available directions and Rex handles edges directly.

## 📋 Requirements

- Neovim >= 0.10.0
- [Rex](https://www.superlogical.com/rex)
- For SSH: a Rex version with the terminal `program_status` method (OSC 7501), and the plugin installed and set up in the remote Neovim.

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
> Don't lazy load the plugin on a key or event. The keymaps and remote navigation reports need to be ready before the first shortcut arrives from Rex.

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
  keys = {
    left = '<C-h>',
    down = '<C-j>',
    up = '<C-k>',
    right = '<C-l>',
  },
  -- continue from the opposite edge when no Rex pane lies that way
  wrap = false,
  -- use OSC 7501 over SSH when REX_SESSION is not set
  osc = 'auto',
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
    left = 'cmd+[KeyH]',
    down = 'cmd+[KeyJ]',
    up = 'cmd+[KeyK]',
    right = 'cmd+[KeyL]',
  },
  -- keys sent to the editor, independently of the Rex shortcuts
  send_keys = {
    left = 'ctrl+h',
    down = 'ctrl+j',
    up = 'ctrl+k',
    right = 'ctrl+l',
  },
  -- Lua patterns matched against the focused program's name
  programs = { '^n?vim$', '^view$', '^n?vimdiff$' },
  -- continue from the opposite edge when no pane lies that way
  wrap = false,
})
```

`keys` on the Rex side uses Rex shortcut syntax. It can use Command, Ctrl, Alt, or a sequence such as `ctrl+b>h`. These shortcuts do not need to match the Neovim mappings: Rex's `send_keys` translates them. Each `send_keys` value can be a single key or a list such as `{ 'ctrl+b', 'h' }`.

The **sent** keys must match Neovim's mappings. For example, to use Alt-H in the editor, set Rex's `send_keys.left = 'alt+h'` and Neovim's `keys.left = '<M-h>'`. For a sequence, use Rex's `send_keys.left = { 'ctrl+b', 'h' }` and Neovim's `keys.left = '<C-b>h'`. You can leave all of these settings at their defaults to use Cmd shortcuts with Ctrl mappings.

On systems without a Command key, customize Rex's `keys` to use Ctrl or Alt. App-level shortcut overrides can take precedence over the configuration; remove conflicting overrides if a binding does not take effect.

## 💻 Usage

Press **Cmd-H/J/K/L** to move left, down, up, or right, whether the next split is a Neovim window or a Rex pane. Neovim still receives Ctrl-H/J/K/L, not the Command modifier.

Run `:checkhealth rex-navigator` to check the active transport. Local navigation requires the `rex` executable; SSH OSC navigation does not.

### SSH

Install the updated Rex-side file locally and the full Neovim plugin on the remote host. Run `setup()` on both sides, then `rex config reload` locally. SSH normally, start Neovim, and create splits. Cmd-H/J/K/L navigates both those splits and the local Rex panes at their edges.

With `osc = 'auto'`, remote reporting is enabled when `SSH_TTY` or `SSH_CONNECTION` is set and `REX_SESSION` is absent. No remote Rex CLI, forwarded environment variables, socket tunnel, or Remote Control setting is needed. If SSH detection is unavailable, explicitly enable it in remote Neovim:

```lua
require('rex-navigator').setup({ osc = true })
```

Set `osc = false` to disable reporting. A local Rex session keeps using the CLI by default, even if SSH environment variables are present. Do not forward a local `REX_SESSION` into ordinary SSH; if you already do, force `osc = true` remotely.

Over SSH, the Rex-side `wrap` setting controls wrapping at split edges. Reports keep non-normal-mode and floating-window keys in Neovim instead of navigating Rex panes. A terminal output connection is required; headless Neovim does not emit escape sequences. Terminal multiplexers such as tmux or screen may filter OSC 7501 and are not automatically supported.

To inspect reports, note the SSH pane's ID with `echo "$REX_BLOCK"` before connecting. While remote Neovim is open, run this from another local Rex pane:

```shell
rex block call -b <ssh-pane-id> program_status
```

Expect an `app=nvim` record with `id=rex-navigator/v1`, plus records for available directions. These namespaced `idle` status records are a plugin-specific convention, not a built-in Rex navigation protocol. They may appear in Rex's program activity UI. They are cleared on normal exit and suspend, without clearing other programs' reports. A killed editor can leave stale reports, especially over SSH without shell integration; you can clear just the plugin's records in that terminal with:

```shell
printf '\033]7501;state=clear:id=rex-navigator\007'
```

Reports travel asynchronously; very rapid input across split changes can race an update, especially on high-latency connections.

## 🔍 How It Works

Each Cmd-H/J/K/L binding runs a named Rex action. It checks the focused terminal's foreground process and OSC 7501 program status. When the editor can handle the direction, the action queues `pane.send_key` with the corresponding Ctrl key. Sending actual key events honors the terminal's keyboard protocol and avoids forwarding Command through SSH. Otherwise the action moves focus with the server's `session.focus_direction` method.

In Neovim, the key runs `wincmd`. If the window doesn't change, Neovim runs `rex do` with the same `session.focus_direction` call, using the `REX_SESSION` environment variable that Rex sets for programs it starts.

Over SSH, Neovim's `lua/rex-navigator/osc.lua` reports its identity and neighboring splits as namespaced OSC 7501 records. Rex reads those records on each shortcut, forwards only directions Neovim can handle, and focuses panes itself at split edges. Reports update on window, layout, and mode changes and are cleared on exit or suspend. Generic active editor reports can identify remote Neovim too, but only this plugin's directional records enable remote edge navigation. Completed and failed reports are ignored; owner metadata helps reject reports from exited SSH processes.

Pane focusing uses the server method rather than Rex's `pane.focus.*` actions, which always wrap. Key translation uses `pane.send_key` queued from the key-triggered action, rather than issuing a remote client-control command.

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
