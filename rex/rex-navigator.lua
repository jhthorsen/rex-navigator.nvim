--
-- rex-navigator.lua
--
-- The Rex side of rex-navigator.nvim. Load it from ~/.config/rex/init.lua:
--
--   require("rex-navigator").setup()
--
-- ctrl-h/j/k/l moves between Rex panes, except when Vim or Neovim is the
-- focused program. Then the key goes through to it, and the Neovim side of the
-- plugin moves between its own splits, handing back to Rex at the edge.
--

local M = {}

local defaults = {
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
}

local function merge(base, overrides)
  local result = {}
  for k, v in pairs(base) do
    result[k] = v
  end
  for k, v in pairs(overrides or {}) do
    if type(v) == 'table' and type(result[k]) == 'table' and #v == 0 then
      result[k] = merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

local function basename(path)
  return (path or ''):match('[^/]+$') or ''
end

local function terminal_call(method)
  local ok, result = pcall(rex.block.call, 'com.superlogical.terminal', method, {})
  if ok then
    return result
  end
end

local function matches_program(name, programs)
  for _, pattern in ipairs(programs) do
    if name:match(pattern) then
      return true
    end
  end
  return false
end

local function active_record(record, process)
  if record.state ~= 'idle' and record.state ~= 'working' and record.state ~= 'blocked' then
    return false
  end

  -- A report can survive a process exit. When Rex knows its owner, do not
  -- reuse reports from an SSH connection that is no longer in the foreground.
  local owner = record.owner
  local foreground = process and process.foreground
  if not owner or not foreground or not foreground.pid then
    return true
  end
  if owner.pid == foreground.pid and owner.name == foreground.name then
    return true
  end
  for _, ancestor in ipairs(process.ancestors or {}) do
    if owner.pid == ancestor.pid and owner.name == ancestor.name then
      return true
    end
  end
  return false
end

local function should_forward(programs, direction)
  local process = terminal_call('process')
  local status = terminal_call('program_status')
  local reported_vim, navigator, passthrough, split = false, false, false, false
  for _, record in ipairs(status and status.records or {}) do
    local app = record.effective_app or record.app
    if type(app) == 'string' and matches_program(app, programs) and active_record(record, process) then
      reported_vim = true
      if record.id == 'rex-navigator/v1' then
        navigator = true
      elseif record.id == 'rex-navigator/v1/passthrough' then
        passthrough = true
      elseif direction and record.id == 'rex-navigator/v1/' .. direction then
        split = true
      end
    end
  end

  if navigator then
    -- Neovim publishes the directions it can handle over OSC, so Rex can
    -- handle edges without a CLI or a control socket on the remote host.
    return direction == nil or passthrough or split
  end
  if reported_vim then
    return true
  end

  local foreground = process and process.foreground
  return foreground ~= nil
    and (matches_program(foreground.name or '', programs) or matches_program(basename(foreground.argv0), programs))
end

function M.is_vim(programs)
  return should_forward(programs)
end

function M.setup(opts)
  local config = merge(defaults, opts)

  for direction, key in pairs(config.keys) do
    rex.bind(key, function(ctx)
      if should_forward(config.programs, direction) then
        return false -- let the key through to Vim
      end

      -- the server method, the app's pane.focus.* actions always wrap
      rex.call('session.focus_direction', {
        session_id = ctx.session_id,
        direction = direction,
        wrap = config.wrap,
      })
      return true
    end)
  end
end

return M
