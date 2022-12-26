--[[
Client for the WebSocket protocol (RFC 6455)

Although the client was written to support the norns plugin, the client should
be usable in other scenarios.

Client limitations:

- The client does not check for protocol errors from the server because. It is
assumed that the norns server correctly implements the protocol.

- The client bypasses some WebSocket security features because it is assumed
that the plugin is trusted on the network. Specifically, the client sends a
fixed security key, and does not mask outbound payloads.

- Message length is limited to 32 bit values.

Execution:

The Client:_run function resolves the host name to an address, connects to the
address and reads messages from the socket. The function is executed as a
coroutine created in M.new. IO callbacks from uv's start_read resume execution
of the coroutine. Errors raised within the method close the connection.

Write to the socket is fire and forget. Write callbacks close the client on
error.
]]

local M = {}

local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local uv = vim.loop

M.states = vim.tbl_add_reverse_lookup {
  Connecting = 0,
  Open = 1,
  Closed = 2,
}

-- Message types from RFC 6455.
local mtypes = vim.tbl_add_reverse_lookup {
  Continuation = 0,
  Text = 1,
  Binary = 2,
  Close = 8,
  Ping = 9,
  Pong = 10,
}

-- Close codes from RFC 6455.
local closecodes = vim.tbl_add_reverse_lookup {
  NormalClosure = 1000,
  GoingAway = 1001,
  ProtocolError = 1002,
  UnsupportedData = 1003,
  NoStatusReceived = 1005,
  AbnormalClosure = 1006,
  InvalidFramePayloadData = 1007,
  PolicyViolation = 1008,
  MessageTooBig = 1009,
  MandatoryExtension = 1010,
  InternalServerErr = 1011,
  ServiceRestart = 1012,
  TryAgainLater = 1013,
  TLSHandshake = 1015,
}

local Client = {
  -- Application supplied callback functions.
  -- Default to nop.
  on_message = function(msg)
    local _ = msg
  end,
  on_open = function() end,
  on_close = function(reason)
    local _ = reason
  end,

  state = M.states.Connecting,

  -- The reader appends to _buffer.
  _buffer = '',

  -- Fields set in new.
  _sock = nil, -- uv handle
  host = nil, -- string
  protocols = nil, -- nil or list of strings
  port = 80,
  path = '/',

  -- Fields set in _handshake.
  protocol = nil,
}
Client.__index = Client

-- new returns a new websocket client to an endpoint specified by host, port
-- and path. The port argument is optional with a default of 80. The path
-- argument is optional with a default of "/". The protocols argument is
-- optional and defaults to none.
function M.new(host, port, path, protocols)
  local c = setmetatable({
    _sock = uv.new_tcp(),
    host = host,
    port = port,
    path = path,
    protocols = protocols,
  }, Client)
  vim.schedule(function()
    c:_resume(coroutine.create(c._run), c)
  end)
  return c
end

-- close closes the connection and calls the on_close callback with the reason.
function Client:close(reason)
  if self.state == M.states.Closed then
    return
  end
  self.state = M.states.Closed
  self._sock:close()
  vim.schedule(function()
    self.on_close(reason)
  end)
end

-- _resume starts or resumes the coroutine co. If there is an error, then the
-- client is closed with the error as the reason.
function Client:_resume(co, ...)
  local ok, err = coroutine.resume(co, ...)
  if not ok then
    self:close(err)
  end
end

-- _start_read starts read on the socket. The callback adds data to self._buffer
-- and resumes the coroutine that is executing Client._run
function Client:_start_read()
  local co = coroutine.running()
  self._sock:read_start(function(err, chunk)
    if err then
      self:close(string.format('Connection read error: %s', err))
    elseif chunk then
      self._buffer = self._buffer .. chunk
      self:_resume(co)
    else
      self:close('Connection closed by peer.')
    end
  end)
end

-- _wait_n waits until the _buffer contains n bytes.
function Client:_wait_n(n)
  if self._sock:is_closing() then
    error('Connection closed.', 0)
  end
  while #self._buffer < n do
    coroutine.yield()
  end
  return self._buffer
end

-- _wait_pat waits until pat is found in the _buffer. Return the _buffer, start
-- index and end index of the match.
function Client:_wait_pat(pat)
  if self._sock:is_closing() then
    error('Connection closed.', 0)
  end
  local i, e = self._buffer:find(pat)
  while not i do
    coroutine.yield()
    i, e = self._buffer:find(pat)
  end
  return self._buffer, i, e
end

-- _connect resolves the host name to an address and connects to the server.
function Client:_connect()
  local co = coroutine.running()
  local callback = function(...)
    return self:_resume(co, ...)
  end

  uv.getaddrinfo(self.host, nil, nil, callback)
  local err, info = coroutine.yield()
  if err then
    error(string.format('Error resolving %s: %s', self.host, err), 0)
  end

  local addr = info[1].addr
  self._sock:connect(addr, self.port, callback)
  err = coroutine.yield()
  if err then
    error(string.format('Error connecting to %s:%d (%s): %s', self.host, self.port, addr, err), 0)
  end
end

local function addlower(s)
  return s:gsub('[A-Z]', function(u)
    return string.format('[%s%s]', u, u:lower())
  end)
end

-- Case insensitive patterns for finding response header values.
local protocolpat = addlower('\nSEC%-WEBSOCKET%-PROTOCOL:%s*([^\r\n\t ]+)')
local acceptpat = addlower('\nSEC%-WEBSOCKET%-ACCEPT:%s*([^\r\n\t ]+)')

-- _handshake executes the websocket opening handshake.
function Client:_handshake()
  local request = {
    string.format('GET %s HTTP/1.1', self.path),
    string.format('Host: %s%s', self.host, self.port == 80 and '' or ':' .. tostring(self.port)),
    'Upgrade: websocket',
    'Connection: Upgrade',
    'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==',
    'Sec-WebSocket-Version: 13',
  }
  if self.protocols then
    table.insert(
      request,
      string.format('Sec-WebSocket-Protocol: %s', table.concat(self.protocols, ', '))
    )
  end
  table.insert(request, '\r\n')
  self._sock:write(table.concat(request, '\r\n'), function(err)
    if err then
      self:close(string.format('Write error: %s', err))
    end
  end)
  local buf, _, e = self:_wait_pat('\r?\n\r?\n')
  local response = buf:sub(1, e)
  self._buffer = buf:sub(e + 1)
  _, e = response:find('^HTTP/1%.1 +101 +.-\n')
  if not e then
    error('Not a websocket response: ' .. response:match('^[^\r\n]*'), 0)
  end
  if response:match(acceptpat) ~= 's3pPLMBiTxaQ9kYGzzhZRbK+xOo=' then
    error('Not a websocket response: bad accept', 0)
  end

  self.protocol = response:match(protocolpat)
end

-- _deccode_frame decodes a frame header. The function returns the message type,
-- final flag, header size and payload size.
function Client:_deccode_frame()
  local buf = self:_wait_n(2)
  local b = buf:byte(1)
  local mtype = band(b, 0xf)
  local final = band(b, 0x80) ~= 0
  local i = 2
  local n = band(buf:byte(2), 0x7f)
  if n == 126 then
    buf = self:_wait_n(4)
    i = 4
    n = lshift(buf:byte(3), 8) + buf:byte(4)
  elseif n == 127 then
    buf = self:_wait_n(10)
    i = 10
    if buf:byte(3) ~= 0 or buf:byte(4) ~= 0 or buf:byte(5) ~= 0 or buf:byte(6) ~= 0 then
      -- Give up on values larger than what's supported by the bits module.
      error('Received message size not supported.', 0)
    end
    n =
      -- lshift(buf:byte(3), 56) + lshift(buf:byte(4), 48) +
      -- lshift(buf:byte(5), 40) + lshift(buf:byte(6), 32) +
      lshift(buf:byte(7), 24) + lshift(buf:byte(8), 16) + lshift(buf:byte(9), 8) + buf:byte(10)
  end
  return mtype, final, i, n
end

M.test_decode_frame = Client._deccode_frame

-- encode_frame returns a frame header given the message type and payload size.
local function encode_frame(mtype, n)
  local b0 = bor(0x80, mtype or mtypes.Text) -- final | type
  if n < 126 then
    return string.char(b0, bor(0x80, n)) -- mask bit | len
  elseif n < 65536 then
    return string.char(
      b0,
      bor(0x80, 126), -- mask bit | 126 (two byte length)
      band(rshift(n, 8), 0xff),
      band(n, 0xff)
    )
  elseif n > 0xffffffff then
    -- Give up on values larger than what's supported by the bits module.
    error('Sent message message size not supported.', 0)
  else
    return string.char(
      b0,
      bor(0x80, 127), -- mask bit | 127 (8 byte length)
      0, -- band(rshift(n, 56), 0xff),
      0, -- band(rshift(n, 48), 0xff),
      0, -- band(rshift(n, 40), 0xff),
      0, -- band(rshift(n, 32), 0xff),
      band(rshift(n, 24), 0xff),
      band(rshift(n, 16), 0xff),
      band(rshift(n, 8), 0xff),
      band(n, 0xff)
    )
  end
end

M.test_encode_frame = encode_frame

-- _read_frame reads a frame from the peer. Returns the frame type, the final
-- flag and the payload.
function Client:_read_frame()
  local mtype, final, i, n = self:_deccode_frame()
  local buf = self:_wait_n(i + n)
  local payload = buf:sub(i + 1, i + n)
  self._buffer = buf:sub(i + n + 1)
  return mtype, final, payload
end

-- send a message to the peer with given message type. The message type is
-- optional and defaults to text.
function Client:send(msg, mtype)
  local header = encode_frame(mtype or mtypes.Text, #msg)
  -- Skip masking by specifying a mask with zero bits.
  self._sock:write({ header, '\x00\x00\x00\x00', msg }, function(err)
    if err then
      self:close(string.format('Write error: %s', err))
    end
  end)
end

-- decode_close returns a text rendering of a close message.
local function decode_close(msg)
  local code, text = closecodes.NoStatusReceived, ''
  if #msg >= 2 then
    code = lshift(msg:byte(1), 8) + msg:byte(2)
    text = msg:sub(3)
  end
  return string.format('%s: %s', closecodes[code] or tostring(code), text)
end

-- _read_messages reads and handles messages read from the connection.
function Client:_read_messages()
  local frames
  while true do
    local mtype, final, payload = self:_read_frame()
    if mtype == mtypes.Text or mtype == mtypes.Binary then
      if final then
        vim.schedule(function()
          self.on_message(payload)
        end)
      else
        frames = { payload }
      end
    elseif mtype == mtypes.Continuation then
      table.insert(frames, payload)
      if final then
        local msg = table.concat(frames)
        frames = nil
        vim.schedule(function()
          self.on_message(msg)
        end)
      end
    elseif mtype == mtypes.Close then
      self:send(payload, mtypes.Close)
      error(string.format('Connection closed: %s', decode_close(payload)), 0)
    elseif mtype == mtypes.Ping then
      self:send(payload, mtypes.Pong)
    else
      error(string.format('Unknown message type %d', mtype), 0)
    end
  end
end

-- _run establishes the websocket connection and processes messages sent by the
-- peer.
function Client:_run()
  self:_connect()
  self:_start_read()
  self:_handshake()
  self.state = M.states.Open
  vim.schedule(function()
    self.on_open()
  end)
  self:_read_messages()
end

return M
