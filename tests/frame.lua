local ws = require('norns.websocket')
local decode_frame = ws.test_decode_frame
local encode_frame = ws.test_encode_frame

local mtype = 1

local function test_roundtrip(n)
  local c = {
    h = encode_frame(mtype, n),
    _wait_n = function(c, nwait)
      assert(nwait <= #c.h)
      return c.h
    end,
  }
  local gmtype, final, _, gn = decode_frame(c)
  if mtype ~= gmtype then
    error(string.format('got type %s, want type %s', gmtype, mtype))
  end
  if not final then
    error(string.format('got final %s, want final %d', final, true))
  end
  if gn ~= n then
    error(string.format('got length %d, want length %d', gn, n))
  end
end

local fail = false
for _, n in ipairs {
  0x01,
  0xEF,
  0xFF,
  0x100,
  0x1234,
  0xEFFF,
  0xFFFF,
  0x10000,
  0x12345678,
} do
  local ok, err = pcall(test_roundtrip, n)
  if not ok then
    fail = true
    print(string.format('roundtrip(%d) -> %s', n, err))
  end
end
print(fail and 'FAIL' or 'OK')
