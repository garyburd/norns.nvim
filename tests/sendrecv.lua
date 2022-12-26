local function expect(wevent, wvalue)
  local gevent, gvalue = coroutine.yield()
  if wevent ~= gevent then
    error(string.format('got event %s, want %s', gevent, wevent))
  end
  if wvalue then
    if wvalue ~= gvalue then
      error(string.format('got value length %d, want %d', #gvalue, #wvalue))
    end
  end
end

local c = require('norns.websocket').new('127.0.0.1', 8080, '/')

local function test()
  expect('open', nil)
  for i = 1, 100 do
    local msg = string.rep('0123456789', i)
    c:send(msg)
    expect('msg', msg)
  end
  c:close()
  expect('close')
  print('OK')
end

local co = coroutine.create(test)

local function resume(event, value)
  if not co then
    return
  end
  local ok, err = coroutine.resume(co, event, value)
  if not ok then
    vim.api.nvim_err_writeln(err)
    co = nil
    c:close()
  end
end

c.on_open = function()
  resume('open')
end

c.on_close = function(msg)
  resume('close', msg)
end

c.on_message = function(msg)
  resume('msg', msg)
end

resume()
