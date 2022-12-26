local M = {}
local api = vim.api
local config = {
  host = 'norns.local.',
  open = { -- command used to create window, see nvim_parse_cmd()
    cmd = nil, -- cmd is optional, defaults to 'new'
    range = { 10 },
    mods = nil,
  },
  dust = nil, -- The local dust diretory specified by string or function.
}
local buf = nil -- bufnr
local client = nil -- websocket client
local deferred_exec = nil -- nil or list of code to execute on open
local win = nil -- window
local prompt = 'matron> '
local qflist = {} -- quick fix list

local append_text

local function close(msg)
  if client then
    client.on_close = nil
    client:close()
    client = nil
    if msg then
      append_text(msg, 'Comment')
    end
  end
end

M.close = close

function M.setup(c)
  config = vim.tbl_extend('force', config, c)
end

-- local_dust gets the local dust directory with a trailing /. Return nil,
-- message on error.
local function local_dust()
  local d = config.dust
  if type(d) == 'function' then
    d = d()
  end
  if not d then
    return nil, 'Could not find local dust.'
  end
  if d:sub(-1) ~= '/' then
    d = d .. '/'
  end
  return d
end

function M.includeexpr(p)
  local m = p:match('/home/we/dust/(.*)')
  if m then
    local d = local_dust()
    if d then
      p = d .. m
    end
  end
  return p
end

local function ensure_buffer()
  if buf then
    return
  end
  buf = api.nvim_create_buf(true, true)
  api.nvim_buf_set_name(buf, '[norns]')
  api.nvim_create_autocmd('BufDelete', {
    group = api.nvim_create_augroup('norns', { clear = false }),
    buffer = buf,
    callback = function()
      close()
      buf = nil
    end,
    desc = 'norns: close connecton',
    once = true,
  })
  api.nvim_buf_set_option(buf, 'includeexpr', "v:lua.require'norns'.includeexpr(v:fname)")
end

function append_text(text, hl, qf)
  ensure_buffer()
  local lines = vim.split(text, '\n', { trimempty = true })

  if qf then
    -- scan for quick fix
    for _, line in ipairs(lines) do
      local filename, lnum, etext = line:match('^%s*/home/we/dust/([^:]+):(%d+):%s+(.*)')
      if filename then
        table.insert(qflist, { filename = filename, lnum = lnum, text = etext })
      end
    end
  end

  local i = api.nvim_buf_line_count(buf)
  api.nvim_buf_set_lines(buf, i, i, true, lines)
  local e = api.nvim_buf_line_count(buf)
  if hl then
    for j = i, e - 1 do
      api.nvim_buf_add_highlight(buf, -1, hl, j, 0, -1)
    end
  end
  local curw = api.nvim_get_current_win()
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(w) == buf and w ~= curw then
      api.nvim_win_set_cursor(w, { e, 1e9 })
    end
  end
end

local function exec(s)
  append_text(prompt .. s, 'Comment')
  client:send(s .. '\n')
end

local function ensure_client()
  if client then
    if client.host == config.host then
      return
    end
    close('Close because host changed.')
  end
  local port = 5555
  append_text(string.format('Connecting to %s:%s.', config.host, port), 'Comment')
  client = require('norns.websocket').new(config.host, port, '/', { 'bus.sp.nanomsg.org' })
  deferred_exec = {}
  client.on_message = function(msg)
    append_text(msg, nil, true)
  end
  client.on_close = function(reason)
    client = nil
    if reason then
      append_text(reason, 'WarningMsg')
    end
  end
  client.on_open = function()
    append_text('Connected.', 'Comment')
    if deferred_exec then
      local dc = deferred_exec
      deferred_exec = nil
      for _, code in ipairs(dc) do
        exec(code)
      end
    end
  end
end

function M.qflist()
  local d, err = local_dust()
  if not d then
    return d, err
  end
  local l = qflist
  qflist = {}
  for _, qf in ipairs(l) do
    qf.lnum = tonumber(qf.lnum)
    qf.filename = d .. qf.filename
  end
  return l
end

function M.exec(s)
  ensure_client()
  if deferred_exec then
    -- Defer execution until connected.
    table.insert(deferred_exec, s)
  else
    exec(s)
  end
end

function M.ensure_window()
  for _, w in ipairs(api.nvim_list_wins()) do
    if api.nvim_win_get_buf(w) == buf then
      return
    end
  end
  local w = api.nvim_get_current_win()
  local cmd = config.open or {}
  if not cmd.cmd then
    cmd.cmd = 'new'
  end
  api.nvim_cmd(cmd, {})
  win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)
  api.nvim_set_current_win(w)
end

function M.connect()
  close('Closing current connection.')
  ensure_client()
end

return M
