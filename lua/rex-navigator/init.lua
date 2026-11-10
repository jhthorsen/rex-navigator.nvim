--
-- init.lua
--
-- Moves between Neovim splits with <C-h/j/k/l> and hands off to Rex once there
-- is no split left in that direction. The Rex side (rex/rex-navigator.lua)
-- forwards these keys to Neovim when it is the focused program.
--

local M = {
  initialized = false,
  -- continue from the opposite edge when no Rex pane lies that way
  wrap = false,
  -- publish split navigation over OSC 7501 when SSH has no local Rex context
  osc = 'auto',
}

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
      tostring(M.wrap)
    ),
  }
end

function M.in_rex()
  return vim.env.REX_SESSION ~= nil and vim.env.REX_SESSION ~= ''
end

function M.navigate(key)
  local direction = directions[key]
  if not direction then
    error(string.format('rex-navigator: unknown direction key %q', key))
  end

  if M.initialized == false then
    M.setup()
  end

  local win = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(key)

  if M.osc == true then
    require('rex-navigator.osc').update()
  elseif vim.api.nvim_get_current_win() == win and M.in_rex() then
    vim.system(M.focus_command(direction))
  end
end

function M.setup(opts)
  opts = opts or {}
  if opts.wrap ~= nil then
    M.wrap = opts.wrap
  end
  if opts.osc ~= nil then
    M.osc = opts.osc
  end

  if M.osc == 'auto' then
    M.osc = not M.in_rex() and ((vim.env.SSH_TTY or '') ~= '' or (vim.env.SSH_CONNECTION or '') ~= '')
  end
  if M.osc == true then
    require('rex-navigator.osc').setup()
  end

  for key, direction in pairs(directions) do
    vim.keymap.set('n', '<C-' .. key .. '>', function()
      M.navigate(key)
    end, { desc = 'Move to the split or Rex pane ' .. direction })
  end

  M.initialized = true
end

return M
