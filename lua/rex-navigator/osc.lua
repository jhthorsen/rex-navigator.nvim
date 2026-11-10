-- Navigation state carried over the existing terminal connection, including
-- SSH. These namespaced idle records never replace another program's status.
local M = {}

local namespace = 'rex-navigator'
local directions = { h = 'left', j = 'down', k = 'up', l = 'right' }
local paused = false
local last_report
local generation = 0

local function sequence(body)
  return '\027]7501;' .. body .. '\027\\'
end

local function send(data)
  if vim.fn.has('ttyout') ~= 1 then
    return false
  end
  return pcall(vim.api.nvim_chan_send, vim.v.stderr, data)
end

function M.clear()
  if last_report then
    send(sequence('state=clear:id=' .. namespace))
    last_report = nil
  end
end

function M.update()
  if paused then
    return
  end

  local records = { sequence('state=idle:app=nvim:id=' .. namespace .. '/v1') }
  local floating = vim.api.nvim_win_get_config(0).relative ~= ''
  if vim.api.nvim_get_mode().mode ~= 'n' or floating then
    -- Only normal-mode mappings implement split navigation. Keep insert,
    -- command-line, terminal, visual and operator-pending keys in Neovim.
    records[#records + 1] = sequence('state=idle:app=nvim:id=' .. namespace .. '/v1/passthrough')
  else
    for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
      if vim.fn.winnr(key) ~= vim.fn.winnr() then
        records[#records + 1] = sequence('state=idle:app=nvim:id=' .. namespace .. '/v1/' .. directions[key])
      end
    end
  end

  local report = table.concat(records)
  if report ~= last_report and send(sequence('state=clear:id=' .. namespace) .. report) then
    last_report = report
  end
end

function M.setup()
  generation = generation + 1
  local current_generation = generation

  M.clear()
  paused = false

  local function schedule_update()
    vim.schedule(function()
      if generation == current_generation then
        M.update()
      end
    end)
  end

  local group = vim.api.nvim_create_augroup('RexNavigatorOSC', { clear = true })
  vim.api.nvim_create_autocmd({
    'VimEnter',
    'UIEnter',
    'WinEnter',
    'WinNew',
    'WinClosed',
    'WinResized',
    'VimResized',
    'TabEnter',
    'ModeChanged',
    'FocusGained',
    'ShellCmdPost',
    'TermEnter',
    'TermLeave',
  }, { group = group, callback = schedule_update })

  vim.api.nvim_create_autocmd({ 'VimSuspend', 'VimLeavePre' }, {
    group = group,
    callback = function()
      paused = true
      M.clear()
    end,
  })

  vim.api.nvim_create_autocmd('VimResume', {
    group = group,
    callback = function()
      paused = false
      schedule_update()
    end,
  })

  schedule_update()

  return true
end

return M
