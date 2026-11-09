-- Loads rex/rex-navigator.lua against a fake `rex` global that records what it
-- binds and calls, so the Rex side can be tested without Rex

local function fake_rex(foreground, records)
  local fake = { bindings = {}, calls = {}, foreground = foreground, records = records or {} }

  fake.bind = function(key, fn)
    fake.bindings[key] = fn
  end

  fake.call = function(method, args)
    table.insert(fake.calls, { method = method, args = args })
  end

  fake.block = {
    call = function(creator, method)
      assert(creator == 'com.superlogical.terminal')
      if method == 'program_status' then
        if fake.status_error then
          return nil, 'method not found'
        end
        return { records = fake.records }
      end
      assert(method == 'process')
      if fake.foreground == 'error' then
        error('not a terminal')
      end
      return { foreground = fake.foreground, ancestors = fake.ancestors }
    end,
  }

  return fake
end

local function load_rex_side(foreground, opts, records)
  _G.rex = fake_rex(foreground, records)
  local navigator = dofile('rex/rex-navigator.lua')
  navigator.setup(opts)
  return _G.rex
end

describe('rex side', function()
  after_each(function()
    _G.rex = nil
  end)

  it('binds the physical h/j/k/l keys with ctrl', function()
    local fake = load_rex_side({ name = 'zsh' })

    for _, key in ipairs({ 'ctrl+[KeyH]', 'ctrl+[KeyJ]', 'ctrl+[KeyK]', 'ctrl+[KeyL]' }) do
      assert.is_function(fake.bindings[key])
    end
  end)

  it('focuses the pane in that direction outside of Vim', function()
    local fake = load_rex_side({ name = 'zsh', argv0 = '-zsh' })

    local handled = fake.bindings['ctrl+[KeyH]']({ session_id = 'session:test' })

    assert.is_true(handled)
    assert.are.same({
      method = 'session.focus_direction',
      args = { session_id = 'session:test', direction = 'left', wrap = false },
    }, fake.calls[1])
  end)

  it('lets the key through to Neovim', function()
    local fake = load_rex_side({ name = 'nvim', argv0 = 'nvim' })

    local handled = fake.bindings['ctrl+[KeyL]']({ session_id = 'session:test' })

    assert.is_false(handled)
    assert.are.same({}, fake.calls)
  end)

  it('recognizes Vim started by a full path', function()
    local fake = load_rex_side({ name = 'something', argv0 = '/usr/bin/vim' })

    assert.is_false(fake.bindings['ctrl+[KeyJ]']({ session_id = 'session:test' }))
  end)

  it('treats a block without a process as not Vim', function()
    local fake = load_rex_side('error')

    assert.is_true(fake.bindings['ctrl+[KeyK]']({ session_id = 'session:test' }))
  end)

  it('accepts custom keys, programs, and wrap', function()
    local fake = load_rex_side({ name = 'hx' }, {
      keys = { left = 'alt+h' },
      programs = { '^hx$' },
      wrap = true,
    })

    assert.is_function(fake.bindings['alt+h'])
    assert.is_function(fake.bindings['ctrl+[KeyJ]'])
    assert.is_false(fake.bindings['alt+h']({ session_id = 'session:test' }))
  end)

  it('passes wrap through to Rex', function()
    local fake = load_rex_side({ name = 'zsh' }, { wrap = true })

    fake.bindings['ctrl+[KeyH]']({ session_id = 'session:test' })

    assert.is_true(fake.calls[1].args.wrap)
  end)

  describe('SSH navigation reports', function()
    local function record(id, fields)
      return vim.tbl_extend('force', { id = id, app = 'nvim', state = 'idle' }, fields or {})
    end

    it('forwards directions with a remote split and handles split edges locally', function()
      local fake = load_rex_side({ name = 'ssh' }, nil, {
        record('rex-navigator/v1'),
        record('rex-navigator/v1/right'),
      })

      assert.is_false(fake.bindings['ctrl+[KeyL]']({ session_id = 'remote' }))
      assert.are.same({}, fake.calls)
      assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
      assert.are.same({
        method = 'session.focus_direction',
        args = { session_id = 'remote', direction = 'left', wrap = false },
      }, fake.calls[1])
    end)

    it('handles all four edges of a remote editor with no splits', function()
      local fake = load_rex_side({ name = 'ssh' }, { wrap = true }, { record('rex-navigator/v1') })
      for _, key in ipairs({ 'H', 'J', 'K', 'L' }) do
        assert.is_true(fake.bindings['ctrl+[Key' .. key .. ']']({ session_id = 'remote' }))
      end
      assert.are.equal(4, #fake.calls)
      for _, call in ipairs(fake.calls) do
        assert.is_true(call.args.wrap)
      end
    end)

    it('keeps non-normal-mode keys in the remote editor', function()
      local fake = load_rex_side({ name = 'ssh' }, nil, {
        record('rex-navigator/v1'),
        record('rex-navigator/v1/passthrough'),
      })
      for _, key in ipairs({ 'H', 'J', 'K', 'L' }) do
        assert.is_false(fake.bindings['ctrl+[Key' .. key .. ']']({ session_id = 'remote' }))
      end
      assert.are.same({}, fake.calls)
    end)

    it('recognizes a remote editor from a generic active app report', function()
      local fake = load_rex_side({ name = 'ssh' }, nil, { record(nil) })
      assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
    end)

    it('uses inherited app names', function()
      local fake = load_rex_side({ name = 'ssh' }, nil, {
        { id = 'rex-navigator/v1', effective_app = 'nvim', state = 'idle' },
      })
      assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
      assert.is_true(dofile('rex/rex-navigator.lua').is_vim({ '^nvim$' }))
    end)

    it('ignores completed, failed, cleared, and unknown status records', function()
      for _, state in ipairs({ 'done', 'error', 'clear', 'unknown' }) do
        local fake = load_rex_side({ name = 'ssh' }, nil, { record(nil, { state = state }) })
        assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
      end
    end)

    it('ignores unrelated apps and records without app identity', function()
      local fake = load_rex_side({ name = 'ssh' }, nil, {
        record('rex-navigator/v1', { app = 'cargo' }),
        { state = 'idle' },
      })
      assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
    end)

    it('forwards working and blocked editor reports', function()
      for _, state in ipairs({ 'working', 'blocked' }) do
        local fake = load_rex_side({ name = 'ssh' }, nil, { record(nil, { state = state }) })
        assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
      end
    end)

    it('recognizes status reports even when process discovery fails', function()
      local fake = load_rex_side('error', nil, { record(nil) })
      assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
    end)

    it('ignores reports owned by an exited SSH process', function()
      local fake = load_rex_side({ name = 'bash', pid = 10 }, nil, {
        record(nil, { owner = { name = 'ssh', pid = 20 } }),
      })
      assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
    end)

    it('accepts reports owned by the foreground process or an ancestor', function()
      local fake = load_rex_side({ name = 'ssh', pid = 20 }, nil, {
        record(nil, { owner = { name = 'ssh', pid = 20 } }),
      })
      assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
      fake.foreground = { name = 'helper', pid = 30 }
      fake.ancestors = { { name = 'ssh', pid = 20 } }
      assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
    end)

    it('does not mistake a reused PID for the report owner', function()
      local fake = load_rex_side({ name = 'bash', pid = 20 }, nil, {
        record(nil, { owner = { name = 'ssh', pid = 20 } }),
      })
      assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
    end)

    it('returns to ordinary pane navigation after reports are cleared', function()
      local fake = load_rex_side({ name = 'ssh' }, nil, { record(nil) })
      assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
      fake.records = {}
      assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'remote' }))
    end)

    it('retains local foreground detection on older Rex versions', function()
      local fake = load_rex_side({ name = 'nvim' })
      fake.status_error = true
      assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'local' }))
      fake.foreground = { name = 'bash' }
      assert.is_true(fake.bindings['ctrl+[KeyH]']({ session_id = 'local' }))
    end)

    it('falls back when program_status raises an error', function()
      local fake = load_rex_side({ name = 'nvim' })
      local original = fake.block.call
      fake.block.call = function(creator, method)
        if method == 'program_status' then
          error('method not found')
        end
        return original(creator, method)
      end
      assert.is_false(fake.bindings['ctrl+[KeyH]']({ session_id = 'local' }))
    end)
  end)
end)
