--
-- health.lua
--

local M = {}

function M.check()
  vim.health.start('rex-navigator')

  local navigator = require('rex-navigator')
  if navigator.uses_osc() then
    if vim.fn.has('ttyout') == 1 then
      vim.health.ok('Using OSC 7501 navigation over the terminal connection; no remote rex executable is needed')
    else
      vim.health.warn('OSC navigation is enabled, but stdout is not a terminal')
    end
    vim.health.info('The local Rex configuration must load the updated rex/rex-navigator.lua')
    vim.health.info('The OSC reports cannot verify that the outer terminal supports Rex program_status')
    return
  end

  if vim.env.REX_SESSION and vim.env.REX_SESSION ~= '' then
    vim.health.ok('Running inside Rex (REX_SESSION is set)')
  else
    vim.health.warn('No local Rex context or SSH OSC transport; <C-h/j/k/l> only moves between splits', {
      'Use setup({ osc = true }) to enable OSC navigation explicitly',
    })
  end

  local command = navigator.focus_command('left')[1]
  if vim.fn.executable(command) == 1 then
    vim.health.ok('rex executable found: ' .. vim.fn.exepath(command))
  else
    vim.health.error('rex executable not found', {
      'Rex puts its bin directory on PATH and in REX_BIN_DIR for programs it starts',
      'Check that your shell startup files keep it on PATH',
    })
  end
end

return M
