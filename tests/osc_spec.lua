describe('OSC navigation', function()
  local navigator, osc, writes, calls
  local original_has, original_send, original_system, original_mode
  local original_env

  local function drain()
    vim.wait(20, function()
      return false
    end)
  end

  local function reports()
    return table.concat(writes)
  end

  local function contains(text)
    return reports():find(text, 1, true) ~= nil
  end

  before_each(function()
    package.loaded['rex-navigator'] = nil
    navigator = require('rex-navigator')
    package.loaded['rex-navigator.osc'] = nil
    osc = require('rex-navigator.osc')
    original_env = {}
    for _, name in ipairs({ 'REX_SESSION', 'SSH_TTY', 'SSH_CONNECTION' }) do
      original_env[name] = vim.env[name] or false
      vim.env[name] = nil
    end
    vim.env.SSH_TTY = '/dev/pts/0'
    writes, calls = {}, {}
    original_has, original_send = vim.fn.has, vim.api.nvim_chan_send
    original_system, original_mode = vim.system, vim.api.nvim_get_mode
    vim.fn.has = function(feature)
      if feature == 'ttyout' then
        return 1
      end
      return original_has(feature)
    end
    vim.api.nvim_chan_send = function(channel, data)
      assert.are.equal(vim.v.stderr, channel)
      writes[#writes + 1] = data
    end
    vim.system = function(command)
      calls[#calls + 1] = command
    end
    vim.cmd('silent! only')
  end)

  after_each(function()
    if vim.fn.exists('#RexNavigatorOSC') == 1 then
      vim.api.nvim_exec_autocmds('VimLeavePre', { group = 'RexNavigatorOSC' })
      vim.api.nvim_del_augroup_by_name('RexNavigatorOSC')
    end
    drain()
    vim.fn.has, vim.api.nvim_chan_send = original_has, original_send
    vim.system, vim.api.nvim_get_mode = original_system, original_mode
    for name, value in pairs(original_env) do
      vim.env[name] = value or nil
    end
    vim.cmd('silent! only')
    for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
      pcall(vim.keymap.del, 'n', '<C-' .. key .. '>')
    end
  end)

  it('automatically enables OSC over SSH without Rex environment variables', function()
    navigator.setup()
    drain()
    assert.is_true(navigator.osc)
    assert.is_true(contains('\027]7501;state=idle:app=nvim:id=rex-navigator/v1\027\\'))
    assert.is_false(contains('id=rex-navigator/v1/left'))
    navigator.navigate('h')
    assert.are.same({}, calls)
  end)

  it('also detects SSH_CONNECTION when SSH_TTY is missing', function()
    vim.env.SSH_TTY = nil
    vim.env.SSH_CONNECTION = '192.0.2.1 1234 192.0.2.2 22'
    navigator.setup()
    assert.is_true(navigator.osc)
  end)

  it('keeps the CLI transport inside a local Rex session', function()
    vim.env.REX_SESSION = 'session:local'
    vim.env.SSH_CONNECTION = '192.0.2.1 1234 192.0.2.2 22'
    navigator.setup()
    drain()
    assert.is_false(navigator.osc)
    assert.are.same({}, writes)
    navigator.navigate('h')
    assert.are.equal(1, #calls)
  end)

  it('does not report outside SSH or Rex by default', function()
    vim.env.SSH_TTY = nil
    navigator.setup()
    drain()
    assert.is_false(navigator.osc)
    assert.are.same({}, writes)
  end)

  it('can explicitly enable OSC outside SSH or Rex', function()
    vim.env.SSH_TTY = nil
    navigator.setup({ osc = true })
    drain()
    assert.is_true(contains('state=idle:app=nvim:id=rex-navigator/v1'))
  end)

  it('can opt out of OSC reporting over SSH', function()
    navigator.setup({ osc = false })
    drain()
    assert.is_false(navigator.osc)
    assert.are.same({}, writes)
  end)

  it('never invokes the CLI when OSC is explicitly enabled', function()
    vim.env.REX_SESSION = 'session:forwarded'
    navigator.setup({ osc = true })
    navigator.navigate('h')
    assert.are.same({}, calls)
  end)

  it('reports neighbors and updates after moving between splits', function()
    navigator.setup()
    vim.cmd('vsplit')
    drain()
    assert.is_true(contains('id=rex-navigator/v1/right'))
    writes = {}
    navigator.navigate('l')
    assert.is_true(contains('id=rex-navigator/v1/left'))
    assert.is_false(contains('id=rex-navigator/v1/right'))
    assert.are.same({}, calls)
  end)

  it('reports vertical neighbors and clears reports after closing splits', function()
    navigator.setup()
    vim.cmd('split')
    drain()
    assert.is_true(contains('id=rex-navigator/v1/down'))
    writes = {}
    navigator.navigate('j')
    assert.is_true(contains('id=rex-navigator/v1/up'))
    writes = {}
    vim.cmd('only')
    drain()
    assert.is_true(contains('state=clear:id=rex-navigator'))
    assert.is_false(contains('id=rex-navigator/v1/up'))
    assert.is_false(contains('id=rex-navigator/v1/down'))
  end)

  it('forwards non-normal-mode keys instead of treating them as pane navigation', function()
    navigator.setup()
    drain()
    for _, mode in ipairs({ 'i', 'c', 't', 'v', 'no' }) do
      vim.api.nvim_get_mode = function()
        return { mode = mode, blocking = false }
      end
      writes = {}
      -- Force a new publication even when the navigation state is unchanged.
      osc.clear()
      vim.api.nvim_exec_autocmds('ModeChanged', {})
      drain()
      assert.is_true(contains('id=rex-navigator/v1/passthrough'))
    end
    vim.api.nvim_get_mode = original_mode
    writes = {}
    vim.api.nvim_exec_autocmds('ModeChanged', {})
    drain()
    assert.is_false(contains('id=rex-navigator/v1/passthrough'))
  end)

  it('keeps keys in floating windows', function()
    navigator.setup()
    drain()
    local window = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), true, {
      relative = 'editor',
      row = 1,
      col = 1,
      width = 10,
      height = 5,
    })
    drain()
    assert.is_true(contains('id=rex-navigator/v1/passthrough'))
    writes = {}
    vim.api.nvim_win_close(window, true)
    drain()
    assert.is_false(contains('id=rex-navigator/v1/passthrough'))
  end)

  it('avoids repeatedly writing unchanged state', function()
    navigator.setup()
    drain()
    writes = {}
    osc.update()
    osc.update()
    vim.api.nvim_exec_autocmds('WinEnter', {})
    drain()
    assert.are.same({}, writes)
  end)

  it('clears only its namespace on suspend and republishes on resume', function()
    navigator.setup()
    drain()
    writes = {}
    vim.api.nvim_exec_autocmds('WinEnter', {})
    vim.api.nvim_exec_autocmds('VimSuspend', {})
    drain()
    assert.are.same({ '\027]7501;state=clear:id=rex-navigator\027\\' }, writes)
    writes = {}
    vim.api.nvim_exec_autocmds('VimResume', {})
    drain()
    assert.is_true(contains('state=idle:app=nvim:id=rex-navigator/v1'))
  end)

  it('clears on exit and prevents queued updates from recreating records', function()
    navigator.setup()
    drain()
    writes = {}
    vim.api.nvim_exec_autocmds('WinEnter', {})
    vim.api.nvim_exec_autocmds('VimLeavePre', {})
    drain()
    assert.are.same({ '\027]7501;state=clear:id=rex-navigator\027\\' }, writes)
  end)

  it('clears previous reports and invalidates queued updates when set up again', function()
    navigator.setup()
    drain()
    writes = {}
    navigator.setup()
    assert.are.same({ '\027]7501;state=clear:id=rex-navigator\027\\' }, writes)
    navigator.setup()
    writes = {}
    drain()
    assert.are.equal(1, #writes)
  end)

  it('does not write escapes into a headless session or redirected stdout', function()
    vim.fn.has = original_has
    navigator.setup()
    drain()
    assert.are.same({}, writes)
  end)

  it('handles unavailable output channels without breaking navigation', function()
    vim.api.nvim_chan_send = function()
      error('closed channel')
    end
    navigator.setup()
    drain()
    assert.has_no.errors(function()
      navigator.navigate('h')
    end)
  end)
end)
