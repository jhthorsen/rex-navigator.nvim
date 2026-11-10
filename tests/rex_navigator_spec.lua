describe('rex-navigator', function()
  local navigator
  local system_calls
  local original_system
  local original_session
  local original_ssh_tty, original_ssh_connection

  before_each(function()
    package.loaded['rex-navigator'] = nil
    navigator = require('rex-navigator')

    system_calls = {}
    original_system = vim.system
    vim.system = function(cmd)
      table.insert(system_calls, cmd)
    end

    original_session = vim.env.REX_SESSION
    vim.env.REX_SESSION = 'session:test'
    original_ssh_tty, original_ssh_connection = vim.env.SSH_TTY, vim.env.SSH_CONNECTION
    vim.env.SSH_TTY, vim.env.SSH_CONNECTION = nil, nil

    vim.cmd('silent! only')
  end)

  after_each(function()
    vim.system = original_system
    vim.env.REX_SESSION = original_session
    vim.env.SSH_TTY, vim.env.SSH_CONNECTION = original_ssh_tty, original_ssh_connection
    vim.cmd('silent! only')
    for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
      pcall(vim.keymap.del, 'n', '<C-' .. key .. '>')
    end
  end)

  describe('navigate', function()
    it('moves to the split in that direction without calling Rex', function()
      vim.cmd('vsplit')
      local left = vim.api.nvim_get_current_win()
      vim.cmd('wincmd l')
      vim.cmd('wincmd h')
      assert.are.equal(left, vim.api.nvim_get_current_win())

      navigator.navigate('l')

      assert.are_not.equal(left, vim.api.nvim_get_current_win())
      assert.are.same({}, system_calls)
    end)

    it('asks Rex to focus the next pane when there is no split that way', function()
      navigator.navigate('h')

      assert.are.equal(1, #system_calls)
      local cmd = system_calls[1]
      assert.are.equal('do', cmd[2])
      assert.are.equal('-e', cmd[3])
      assert.truthy(cmd[4]:find('session.focus_direction', 1, true))
      assert.truthy(cmd[4]:find('direction = "left"', 1, true))
      assert.truthy(cmd[4]:find('wrap = false', 1, true))
    end)

    it('maps each key to its direction', function()
      local expected = { h = 'left', j = 'down', k = 'up', l = 'right' }
      for key, direction in pairs(expected) do
        system_calls = {}
        navigator.navigate(key)
        assert.truthy(system_calls[1][4]:find(string.format('direction = %q', direction), 1, true))
      end
    end)

    it('does nothing at the edge outside of Rex', function()
      vim.env.REX_SESSION = nil

      navigator.navigate('h')

      assert.are.same({}, system_calls)
    end)

    it('errors on an unknown key', function()
      assert.has.errors(function()
        navigator.navigate('x')
      end)
      assert.is_false(navigator.initialized)
      assert.are.same({}, vim.fn.maparg('<C-h>', 'n', false, true))
    end)
  end)

  describe('setup', function()
    it('maps <C-h/j/k/l> in normal mode', function()
      navigator.setup()

      for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
        local map = vim.fn.maparg('<C-' .. key .. '>', 'n', false, true)
        assert.truthy(map.desc and map.desc:find('Rex pane', 1, true))
      end
    end)

    it('maps each key to navigation in its direction', function()
      navigator.setup()

      for key, direction in pairs({ h = 'left', j = 'down', k = 'up', l = 'right' }) do
        system_calls = {}
        local map = vim.fn.maparg('<C-' .. key .. '>', 'n', false, true)
        map.callback()
        assert.are.equal(1, #system_calls)
        assert.truthy(system_calls[1][4]:find(string.format('direction = %q', direction), 1, true))
      end
    end)

    it('passes wrap through to Rex', function()
      navigator.setup({ wrap = true })

      navigator.navigate('h')

      assert.truthy(system_calls[1][4]:find('wrap = true', 1, true))
    end)
  end)

  describe('focus_command', function()
    it('prefers the rex in REX_BIN_DIR', function()
      local original_bin_dir = vim.env.REX_BIN_DIR
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, 'p')
      vim.fn.writefile({ '#!/bin/sh' }, dir .. '/rex')
      vim.fn.setfperm(dir .. '/rex', 'rwxr-xr-x')
      vim.env.REX_BIN_DIR = dir

      assert.are.equal(dir .. '/rex', navigator.focus_command('left')[1])

      vim.env.REX_BIN_DIR = original_bin_dir
    end)

    it('falls back to rex on PATH', function()
      local original_bin_dir = vim.env.REX_BIN_DIR
      vim.env.REX_BIN_DIR = nil

      assert.are.equal('rex', navigator.focus_command('left')[1])

      vim.env.REX_BIN_DIR = original_bin_dir
    end)
  end)
end)
