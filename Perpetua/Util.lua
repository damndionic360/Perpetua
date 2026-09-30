-- Shared helpers: safe API calls, JSON, base64 and the "PERP1" codec used both for the site export and for
-- profiles sent between guildmates.
local _, ns = ...

-- Forever can hand addons "secret" values they may display but not use; treat those as missing.
function ns.readable(v)
  if v == nil then return nil end
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

function ns.num(v)
  v = ns.readable(v)
  return type(v) == "number" and v or nil
end

function ns.text(v)
  v = ns.readable(v)
  return type(v) == "string" and v ~= "" and v or nil
end

-- Calls fn and returns its results, or nothing if it doesn't exist or errors.
function ns.try(fn, ...)
  if type(fn) ~= "function" then return end
  local r = { pcall(fn, ...) }
  if r[1] then return unpack(r, 2, table.maxn(r)) end
end

-- WoW: Forever characters have a first name and a surname. The client hands the surname over where Classic
-- had the realm (UnitName returns "Damndionic", "Dipndots"), and guild addon messages name the sender
-- "Damndionic Dipndots". Players are keyed by that full name everywhere in the addon.
do
  local toc = select(4, GetBuildInfo()) or 0
  ns.FOREVER = toc >= 16000 and toc < 20000
end

function ns.fullName(first, surname)
  if surname and surname ~= "" then return first .. " " .. surname end
  return first
end

-- A name as another API gives it ("First Surname", "First-Surname" or, outside Forever, "Name-Realm") in the
-- addon's form.
function ns.playerKey(s)
  if type(s) ~= "string" or s == "" then return nil end
  if ns.FOREVER then return (s:gsub("%-", " ", 1)) end
  return (ns.try(Ambiguate, s, "short")) or s:match("^([^%-]+)")
end

-- Whether version string a ("2.3.0") is newer than b.
function ns.newer(a, b)
  local x, y = {}, {}
  for n in tostring(a or ""):gmatch("%d+") do x[#x + 1] = tonumber(n) end
  for n in tostring(b or ""):gmatch("%d+") do y[#y + 1] = tonumber(n) end
  for i = 1, math.max(#x, #y) do
    if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) > (y[i] or 0) end
  end
  return false
end

function ns.itemIdFrom(link)
  return link and tonumber(link:match("item:(%d+)"))
end

-- Text from other players goes on screen through this: "|" starts a colour, link or texture code in WoW.
function ns.safe(s)
  return (tostring(s or ""):gsub("|", "||"))
end

function ns.now()
  return ns.try(GetServerTime) or time()
end

-- "3m ago", "2h ago", "5d ago"
function ns.ago(t)
  if not t then return "never" end
  local s = math.max(0, ns.now() - t)
  if s < 90 then return "just now" end
  if s < 5400 then return math.floor(s / 60 + 0.5) .. "m ago" end
  if s < 129600 then return math.floor(s / 3600 + 0.5) .. "h ago" end
  return math.floor(s / 86400 + 0.5) .. "d ago"
end

-- ---------- JSON ----------

local escapes = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  return n == #t
end

-- Object keys are written in sorted order so the same data always gives the same text (and the same hash).
local function encode(v, out)
  local kind = type(v)
  if kind == "table" then
    if isArray(v) then
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = "," end
        encode(v[i], out)
      end
      out[#out + 1] = "]"
    else
      local keys = {}
      for k in pairs(v) do keys[#keys + 1] = tostring(k) end
      table.sort(keys)
      out[#out + 1] = "{"
      for i, k in ipairs(keys) do
        if i > 1 then out[#out + 1] = "," end
        encode(k, out)
        out[#out + 1] = ":"
        local val = v[k]
        if val == nil then val = v[tonumber(k)] end
        encode(val, out)
      end
      out[#out + 1] = "}"
    end
  elseif kind == "string" then
    out[#out + 1] = '"' .. (v:gsub('[%c"\\]', function(c) return escapes[c] or string.format("\\u%04x", c:byte()) end)) .. '"'
  elseif kind == "number" then
    if v ~= v or v == math.huge or v == -math.huge then out[#out + 1] = "null"
    elseif v % 1 == 0 and math.abs(v) < 2 ^ 53 then out[#out + 1] = string.format("%d", v)
    else out[#out + 1] = string.format("%.6g", v) end
  elseif kind == "boolean" then
    out[#out + 1] = v and "true" or "false"
  else
    out[#out + 1] = "null"
  end
end

function ns.toJson(v)
  local out = {}
  encode(v, out)
  return table.concat(out)
end

local unescape = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }

local function utf8char(code)
  if code < 0x80 then return string.char(code) end
  if code < 0x800 then return string.char(0xC0 + math.floor(code / 64), 0x80 + code % 64) end
  return string.char(0xE0 + math.floor(code / 4096), 0x80 + math.floor(code / 64) % 64, 0x80 + code % 64)
end

-- Plain JSON parser for data from other players (never loadstring). Returns nil on anything malformed.
function ns.fromJson(s)
  if type(s) ~= "string" then return nil end
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local function str()
    local out, i = {}, pos + 1
    while true do
      local j = s:find('["\\]', i)
      if not j then error("string") end
      out[#out + 1] = s:sub(i, j - 1)
      if s:sub(j, j) == '"' then pos = j + 1; return table.concat(out) end
      local e = s:sub(j + 1, j + 1)
      if unescape[e] then
        out[#out + 1] = unescape[e]; i = j + 2
      elseif e == "u" then
        local code = tonumber(s:sub(j + 2, j + 5), 16)
        if not code then error("escape") end
        out[#out + 1] = (code >= 0xD800 and code <= 0xDFFF) and "?" or utf8char(code); i = j + 6
      else
        error("escape")
      end
    end
  end
  local value
  function value(depth)
    if depth > 24 then error("depth") end
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}
      pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws()
        if s:sub(pos, pos) ~= '"' then error("key") end
        local k = str(); ws()
        if s:sub(pos, pos) ~= ":" then error("colon") end
        pos = pos + 1
        t[k] = value(depth + 1); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return t elseif d ~= "," then error("comma") end
      end
    elseif c == "[" then
      local t, n = {}, 0
      pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        n = n + 1
        t[n] = value(depth + 1); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return t elseif d ~= "," then error("comma") end
      end
    elseif c == '"' then
      return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    end
    local numText = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
    if not numText or numText == "" then error("value") end
    pos = pos + #numText
    return tonumber(numText)
  end
  local ok, result = pcall(value, 0)
  if ok then return result end
end

-- ---------- base64 ----------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64INV = {}
for i = 1, 64 do B64INV[B64:byte(i)] = i - 1 end

local function base64(s)
  local out = {}
  for i = 1, #s, 3 do
    local a, b, c = s:byte(i, i + 2)
    local n = a * 65536 + (b or 0) * 256 + (c or 0)
    local c1, c2, c3, c4 = math.floor(n / 262144), math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
    out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
      .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
  end
  return table.concat(out)
end

local function unbase64(s)
  s = s:gsub("[^%w%+/=]", "")
  if #s % 4 ~= 0 then return nil end
  local out = {}
  for i = 1, #s, 4 do
    local a, b, c, d = s:byte(i, i + 3)
    a, b, c, d = B64INV[a], B64INV[b], B64INV[c], B64INV[d] -- "=" maps to nil
    if not a or not b then return nil end
    local n = a * 262144 + b * 4096 + (c or 0) * 64 + (d or 0)
    out[#out + 1] = string.char(math.floor(n / 65536)) .. (c and string.char(math.floor(n / 256) % 256) or "") .. (d and string.char(n % 256) or "")
  end
  return table.concat(out)
end

-- ---------- codec ----------

local function deflateMethod()
  return Enum and Enum.CompressionMethod and Enum.CompressionMethod.Deflate or 0
end

-- "PERP1Z:" + base64(deflate(JSON)) when the client can compress, "PERP1:" + base64(JSON) otherwise.
-- The site (worker/profile.js) reads both.
function ns.pack(data)
  local json = ns.toJson(data)
  local E = C_EncodingUtil
  if E and E.CompressString then
    local packed = ns.try(E.CompressString, json, deflateMethod())
    if type(packed) == "string" and #packed > 0 then
      return "PERP1Z:" .. (ns.try(E.EncodeBase64, packed) or base64(packed))
    end
  end
  return "PERP1:" .. base64(json)
end

function ns.unpack(s, maxBytes)
  if type(s) ~= "string" then return nil end
  local z, body = s:match("^PERP1(Z?):(.+)$")
  if not body then return nil end
  local E = C_EncodingUtil
  local bytes = (E and ns.try(E.DecodeBase64, body)) or unbase64(body)
  if not bytes then return nil end
  if z == "Z" then
    bytes = E and ns.try(E.DecompressString, bytes, deflateMethod())
    if type(bytes) ~= "string" then return nil end
  end
  if maxBytes and #bytes > maxBytes then return nil end
  return ns.fromJson(bytes)
end

-- Short fingerprint of some data, to tell whether a guildmate's copy is current.
function ns.hash(s)
  local h = 5381
  for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
  return string.format("%08x", h)
end
