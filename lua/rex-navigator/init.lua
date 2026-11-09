--
-- init.lua
--
-- Moves between Neovim splits with <C-h/j/k/l> and hands off to Rex once there
-- is no split left in that direction. The Rex side (rex/rex-navigator.lua)
-- forwards these keys to Neovim when it is the focused program.
--

local M = {}

local defaults = {
  -- map <C-h/j/k/l> in normal mode
  keymaps = true,
  -- continue from the opposite edge when no Rex pane lies that way
  wrap = false,
  -- publish split navigation over OSC 7501 when SSH has no local Rex context
  osc = 'auto',
}

local config = vim.deepcopy(defaults)

local directions = {
  h = 'left',
  j = 'down',
  k = 'up',
  l = 'right',
}

local function rex_executable()
  local bin_dir = vim.env.REX_BIN_DIR
  if bin_dir and bin_dir ~= '' and vim.fn.executable(bin_dir .. '/rex') == 1 then
    return bin_dir .. '/rex'
  end
  return 'rex'
end

-- The server's session.focus_direction, the app's pane.focus.* actions can't
-- be run from the CLI unless Remote Control is turned on
function M.focus_command(direction)
  return {
    rex_executable(),
    'do',
    '-e',
    string.format(
      'rex.call("session.focus_direction", { session_id = rex.session_id, direction = %q, wrap = %s })',
      direction,
      tostring(config.wrap)
    ),
  }
end

function M.in_rex()
  return vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ''
end

function M.uses_osc()
  if config.osc ~= 'auto' then
    return config.osc == true
  end
  return not M.in_rex()
    and ((vim.env.SSH_TTY or '') ~= '' or (vim.env.SSH_CONNECTION or '') ~= '')
end

function M.navigate(key)
  local direction = directions[key]
  if not direction then
    error(string.format('rex-navigator: unknown direction key %q', key))
  end

  local win = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(key)

  if vim.api.nvim_get_current_win() == win and M.in_rex() and not M.uses_osc() then
    vim.system(M.focus_command(direction))
  end

  require('rex-navigator.osc').update()
end

function M.left()
  M.navigate('h')
end

function M.down()
  M.navigate('j')
end

function M.up()
  M.navigate('k')
end

function M.right()
  M.navigate('l')
end

function M.setup(opts)
  config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  require('rex-navigator.osc').setup(M.uses_osc())

  if config.keymaps then
    for key, direction in pairs(directions) do
      vim.keymap.set('n', '<C-' .. key .. '>', function()
        M.navigate(key)
      end, { desc = 'Move to the split or Rex pane ' .. direction })
    end
  end
end

return M
