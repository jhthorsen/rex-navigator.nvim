describe('rex-navigator health', function()
  local navigator, reports, setup_calls
  local original_health, original_osc, original_navigator
  local original_env, original_executable, original_exepath

  before_each(function()
    original_health = vim.health
    reports = {}
    vim.health = {}
    for _, level in ipairs({ 'start', 'ok', 'warn', 'info', 'error' }) do
      vim.health[level] = function(message)
        reports[#reports + 1] = { level, message }
      end
    end

    original_env = {}
    for _, name in ipairs({ 'REX_SESSION', 'SSH_TTY', 'SSH_CONNECTION', 'REX_BIN_DIR' }) do
      original_env[name] = vim.env[name] or false
      vim.env[name] = nil
    end
    original_executable = vim.fn.executable
    original_exepath = vim.fn.exepath
    vim.fn.executable = function()
      return 1
    end
    vim.fn.exepath = function()
      return '/usr/bin/rex'
    end

    original_navigator = package.loaded['rex-navigator']
    original_osc = package.loaded['rex-navigator.osc']
    package.loaded['rex-navigator'] = nil
    setup_calls = 0
    package.loaded['rex-navigator.osc'] = {
      setup = function()
        setup_calls = setup_calls + 1
      end,
    }
    navigator = require('rex-navigator')
  end)

  after_each(function()
    for _, key in ipairs({ 'h', 'j', 'k', 'l' }) do
      pcall(vim.keymap.del, 'n', '<C-' .. key .. '>')
    end
    vim.health = original_health
    vim.fn.executable = original_executable
    vim.fn.exepath = original_exepath
    for name, value in pairs(original_env) do
      vim.env[name] = value or nil
    end
    package.loaded['rex-navigator'] = original_navigator
    package.loaded['rex-navigator.osc'] = original_osc
  end)

  local function check()
    require('rex-navigator.health').check()
  end

  it('initializes automatic OSC transport over SSH without checking for rex', function()
    vim.env.SSH_CONNECTION = '192.0.2.1 1234 192.0.2.2 22'
    vim.fn.executable = function()
      error('OSC does not need rex')
    end

    check()

    assert.is_true(navigator.initialized)
    assert.is_true(navigator.osc)
    assert.are.equal(1, setup_calls)
    assert.are.same({
      'info',
      'The local Rex configuration must load the updated rex/rex-navigator.lua',
    }, reports[3])
  end)

  it('does not initialize an already configured OSC transport again', function()
    navigator.setup({ osc = true })

    check()

    assert.are.equal(1, setup_calls)
  end)

  it('checks the CLI transport inside Rex when OSC is disabled', function()
    vim.env.REX_SESSION = 'session:test'
    vim.env.SSH_TTY = '/dev/pts/1'
    navigator.setup({ osc = false })

    check()

    assert.are.same({ 'ok', 'Running inside Rex (REX_SESSION is set)' }, reports[2])
    assert.are.same({ 'ok', 'rex executable found: /usr/bin/rex' }, reports[3])
    assert.are.equal(0, setup_calls)
  end)

  it('warns when neither Rex nor OSC transport is available', function()
    check()

    assert.are.same({
      'warn',
      'No local Rex context or SSH OSC transport; <C-h/j/k/l> only moves between splits',
    }, reports[2])
  end)
end)
