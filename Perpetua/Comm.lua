-- Guild sync: guildmates with the addon swap profiles over the hidden guild addon channel.
--
--   H  <profile version> <recipes version> <addon version>   "here's what I have" (login, change, every 10 min)
--   Q  <name> <part> <version>                              "please send name's part" (anyone who's behind)
--   D  <part> <version> <i> <n> <chunk>                     one piece of a part, sent to the whole guild
--   L / R                                                   a loot drop / a /roll seen in a raid (Loot.lua)
--
-- Parts: P = profile (gear, talents, stats, attunements, reps, raid sign-ups), R = recipes, C = the raid
-- calendar (Calendar.lua), F = the forums snapshot (Forums.lua). Only officers send C and F, versioned by when
-- the site made them. A version is a hash of the data,
-- so an unchanged character sends nothing. When several people are behind on the same thing they share one
-- broadcast: a request is skipped if someone else already asked or the data is already on its way.
--
-- Everyone only ever sends their own character, and a received profile is kept only if the name inside it
-- matches the sender the server reports, so nobody can post data under someone else's name.
local _, ns = ...
local PREFIX = "PERPETUA"
local CHUNK = 200            -- characters of data per message (the limit is 255 with the header)
local MAX_PAYLOAD = 150000   -- a part bigger than this isn't sent or accepted
local CPS, BURST = 800, 4000 -- bytes per second / burst, the same budget ChatThrottleLib uses

ns.session = { heard = {}, sent = 0, received = 0 }

-- ---------- storage ----------

-- Players are kept per guild, so an alt in another guild doesn't mix the lists.
function ns.guildName()
  return ns.text(ns.try(GetGuildInfo, "player"))
end

function ns.players(guild)
  PerpetuaDB.guilds = PerpetuaDB.guilds or {}
  guild = guild or ns.guildName() or "No guild"
  PerpetuaDB.guilds[guild] = PerpetuaDB.guilds[guild] or { players = {} }
  return PerpetuaDB.guilds[guild].players
end


function ns.me()
  return ns.players()[ns.selfName]
end

-- The addon only works inside Perpetua: anyone else gets the Welcome page and guild sync stays silent. Just after
-- login the guild's name may not have arrived yet; that doesn't count as locked.
function ns.locked()
  if not IsInGuild() then return true end
  local g = ns.guildName()
  return g ~= nil and g ~= ns.GUILD
end

-- ---------- this character ----------

local function recipesForHash()
  local out = {}
  for name, saved in pairs(PerpetuaCharDB.recipes or {}) do
    out[name] = { list = saved.list, r = saved.r, m = saved.m }
  end
  return out
end

-- The other characters that have logged in on this account in this guild, so the site can file them under the
-- same person. PerpetuaDB.account is account-wide: every character adds itself when it refreshes.
local function accountAlts(me, guild)
  local out = {}
  for full, a in pairs(PerpetuaDB.account or {}) do
    if full ~= me and a.g == guild and a.n then out[#out + 1] = { n = a.n, s = a.s, c = a.c, sp = a.sp, l = a.l } end
  end
  table.sort(out, function(x, y) return ns.fullName(x.n, x.s) < ns.fullName(y.n, y.s) end)
  while #out > 20 do table.remove(out) end
  return out
end

-- Re-reads this character and, if anything changed, tells the guild.
function ns.refreshSelf(quiet)
  if ns.locked() then return end
  local profile = ns.collectProfile()
  local c = profile.char
  if not (c and c.name) then return end
  local name = ns.fullName(c.name, c.surname)
  ns.selfName = name
  -- A character that isn't fully loaded (loading screens, logging out) reads as naked with no professions.
  -- Never let that replace a real profile.
  local old = ns.players()[name]
  if #(profile.gear or {}) == 0 and #(profile.profs or {}) == 0 and old and old.profile and #(old.profile.gear or {}) > 0 then return end
  PerpetuaDB.account = PerpetuaDB.account or {}
  PerpetuaDB.account[name] = { n = c.name, s = c.surname, c = c.classFile, sp = profile.spec and profile.spec.n, l = c.level, g = c.guild, t = ns.now() }
  profile.alts = accountAlts(name, c.guild)
  local signups = ns.mySignups and ns.mySignups() or {}
  if #signups > 0 then profile.signups = signups end
  -- A link code from /perpetua link: rides along until guild sync has used it (a week at most).
  local link = PerpetuaDB.link
  if link and link.code and ns.now() - (link.t or 0) < 7 * 86400 then profile.link = link.code else PerpetuaDB.link = nil end
  local players = ns.players()
  local me = players[name] or {}
  players[name] = me
  local changed = false
  local pv = ns.hash(ns.toJson(profile))
  if me.pv ~= pv then
    me.profile, me.pv, me.pt = profile, pv, ns.now()
    changed = true
  end
  local recipes = recipesForHash()
  local rv = next(recipes) and ns.hash(ns.toJson(recipes)) or nil
  if rv and me.rv ~= rv then
    me.recipes, me.rv, me.rt = PerpetuaCharDB.recipes, rv, ns.now()
    changed = true
  end
  me.heard, me.self, me.class, me.level, me.addon = ns.now(), true, profile.char.classFile, profile.char.level, ns.VERSION
  if changed and not quiet then ns.announce() end
  ns.fire()
end

local refreshTimer
function ns.scheduleRefresh(delay)
  if refreshTimer then refreshTimer:Cancel() end
  refreshTimer = C_Timer.NewTimer(delay or 15, function() refreshTimer = nil; ns.refreshSelf() end)
end
ns.onRecipesChanged = function() ns.scheduleRefresh(5) end

-- ---------- sending ----------

local queue, avail, lastPump = {}, BURST, 0
local lastAnnounce = 0

local function enqueue(msg)
  queue[#queue + 1] = { msg = msg, tries = 0 }
end

local THROTTLED = { [3] = true, [8] = true } -- Enum.SendAddonMessageResult AddonMessageThrottle / ChannelThrottle

local function pump()
  local now = GetTime()
  avail = math.min(BURST, avail + CPS * (now - lastPump))
  lastPump = now
  while queue[1] do
    local item = queue[1]
    if item.wait and item.wait > now then return end
    local size = #item.msg + 40
    if avail < size then return end
    if not IsInGuild() then wipe(queue); return end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, item.msg, "GUILD")
    if ok and (result == nil or result == true or result == 0) then
      table.remove(queue, 1)
      avail = avail - size
      ns.session.sent = ns.session.sent + 1
    elseif ok and THROTTLED[result] then
      item.wait = now + 1 -- the server's limit; try the same message again shortly
      return
    else
      -- Blocked (combat in an instance, not in a guild yet …): back off, give up after a while.
      item.tries = item.tries + 1
      if item.tries > 6 then table.remove(queue, 1) else item.wait = now + 5 * item.tries end
      return
    end
  end
end

function ns.announce()
  if not (IsInGuild() and ns.selfName) or ns.locked() then return end
  local me = ns.me()
  if not me then return end
  lastAnnounce = GetTime()
  enqueue(table.concat({ "H", me.pv or "-", me.rv or "-", ns.VERSION, ns.calendarVersion and ns.calendarVersion() or "-",
    ns.forumsVersion and ns.forumsVersion() or "-" }, "\t"))
end

-- A one-message update (loot, rolls) for the whole guild.
function ns.sendLine(fields)
  if IsInGuild() and not ns.locked() then enqueue(table.concat(fields, "\t")) end
end

local lastSent, sendPending = {}, {}

local function sendPart(part)
  local me = ns.me()
  if not me then return end
  local version = part == "P" and me.pv or part == "R" and me.rv or part == "C" and ns.calendarVersion()
    or part == "F" and ns.forumsVersion() or nil
  if not version or sendPending[part] then return end
  if (part == "C" or part == "F") and not ns.isOfficer(ns.selfName) then return end -- nobody would accept it
  local last = lastSent[part]
  if last and last.v == version and GetTime() - last.at < 30 then return end -- just sent it; they'll have it
  sendPending[part] = true
  -- A short wait gathers everyone's requests into one broadcast.
  C_Timer.After(2, function()
    sendPending[part] = nil
    me = ns.me()
    local payload
    if part == "P" then
      payload = {}
      for k, v in pairs(me.profile or {}) do payload[k] = v end
      payload.t = me.pt
    elseif part == "C" then
      payload = ns.calendar()
      if not payload then return end
    elseif part == "F" then
      payload = ns.forums()
      if not payload then return end
    else
      payload = { t = me.rt, r = me.recipes }
    end
    local s = ns.pack(payload)
    if #s > MAX_PAYLOAD then return end
    local n = math.ceil(#s / CHUNK)
    for i = 1, n do
      enqueue(table.concat({ "D", part, version, i, n, s:sub((i - 1) * CHUNK + 1, i * CHUNK) }, "\t"))
    end
    lastSent[part] = { v = version, at = GetTime() }
  end)
end

-- ---------- receiving ----------

local buffers = {}      -- sender .. part .. version -> { n, got, parts, at }
local asked = {}        -- name .. part .. version -> time someone (anyone) asked for it

local function request(name, part, version)
  local key = name .. part .. version
  if asked[key] and GetTime() - asked[key] < 60 then return end
  -- Random wait so one guildmate asks and the rest just listen for the broadcast.
  C_Timer.After(1 + math.random() * 3, function()
    local rec = ns.players()[name]
    local have = part == "C" and ns.calendarVersion() or part == "F" and ns.forumsVersion() or rec and (part == "P" and rec.pv or rec.rv)
    if have == version or buffers[name .. part .. version] then return end
    if asked[key] and GetTime() - asked[key] < 60 then return end
    asked[key] = GetTime()
    enqueue(table.concat({ "Q", name, part, version }, "\t"))
  end)
end

local function accept(from, part, version, s)
  local data = ns.unpack(s, 600000)
  if type(data) ~= "table" then return end
  local players = ns.players()
  if part == "P" then
    local c = data.char
    if type(c) ~= "table" or type(c.name) ~= "string" then return end
    -- Addon 2.1 and earlier sent the surname where Classic had the realm.
    if ns.FOREVER and type(c.surname) ~= "string" and type(c.realm) == "string" and not ns.newer(data.addon, "2.1.99") then
      c.surname = c.realm
    end
    if ns.fullName(c.name, type(c.surname) == "string" and c.surname or nil):lower() ~= from:lower() then return end
    local rec = players[from] or {}
    players[from] = rec
    rec.profile, rec.pv, rec.pt = data, version, tonumber(data.t)
    rec.class, rec.level = c.classFile, tonumber(c.level)
  elseif part == "C" then
    if ns.isOfficer(from) then ns.adoptCalendar(data) end
    return
  elseif part == "F" then
    if ns.isOfficer(from) then ns.adoptForums(data) end
    return
  elseif part == "R" then
    if type(data.r) ~= "table" then return end
    local rec = players[from] or {}
    players[from] = rec
    rec.recipes, rec.rv, rec.rt = data.r, version, tonumber(data.t)
  else
    return
  end
  players[from].heard = ns.now()
  ns.session.received = ns.session.received + 1
  ns.fire()
end

local function onMessage(text, channel, sender)
  if channel ~= "GUILD" or type(text) ~= "string" or ns.locked() then return end
  local from = ns.playerKey(sender)
  if not from or from == ns.selfName then return end
  local f = { strsplit("\t", text) }
  local kind = f[1]
  if kind == "H" then
    local players = ns.players()
    local rec = players[from] or {}
    players[from] = rec
    rec.heard, rec.addon = ns.now(), f[4]
    -- Someone has a newer addon than ours: say so once a session.
    if f[4] and ns.newer(f[4], ns.VERSION) and not ns.session.toldNewer then
      ns.session.toldNewer = true
      print("|cffd4af37Perpetua|r: " .. ns.safe(from) .. " has a newer version of the addon (" .. ns.safe(f[4]) .. "). Get it at " .. ns.SITE .. "/addon")
    end
    -- Someone new this session: answer with our own hello so they can catch up on us too.
    if not ns.session.heard[from] then
      ns.session.heard[from] = true
      if GetTime() - lastAnnounce > 20 then
        C_Timer.After(2 + math.random() * 6, function() if GetTime() - lastAnnounce > 20 then ns.announce() end end)
      end
    end
    if f[2] and f[2] ~= "-" and f[2] ~= rec.pv then request(from, "P", f[2]) end
    if f[3] and f[3] ~= "-" and f[3] ~= rec.rv then request(from, "R", f[3]) end
    -- A newer raid calendar, from an officer.
    local calT = tonumber(f[5])
    if calT and calT > (tonumber(ns.calendarVersion()) or 0) and ns.isOfficer(from) then request(from, "C", f[5]) end
    local forumT = tonumber(f[6])
    if ns.FORUMS and forumT and forumT > (tonumber(ns.forumsVersion()) or 0) and ns.isOfficer(from) then request(from, "F", f[6]) end
    ns.fire()
  elseif kind == "L" or kind == "R" then
    ns.onLootMessage(f, from)
  elseif kind == "Q" then
    if f[2] and f[3] and f[4] then asked[f[2] .. f[3] .. f[4]] = GetTime() end
    if f[2] == ns.selfName then sendPart(f[3]) end
  elseif kind == "D" then
    local part, version, i, n, chunk = f[2], f[3], tonumber(f[4]), tonumber(f[5]), f[6]
    if not (part and version and i and n and chunk) or n < 1 or n > MAX_PAYLOAD / CHUNK or i < 1 or i > n then return end
    local key = from .. part .. version
    local b = buffers[key]
    if not b or b.n ~= n then b = { n = n, got = 0, parts = {} }; buffers[key] = b end
    b.at = GetTime()
    if not b.parts[i] then b.parts[i] = chunk; b.got = b.got + 1 end
    if b.got == b.n then
      buffers[key] = nil
      accept(from, part, version, table.concat(b.parts))
    end
  end
end

-- ---------- start ----------

-- Addon 2.1 and earlier keyed your own characters by first name only; those entries are replaced by full names.
local function tidy()
  if not ns.FOREVER then return end
  for _, g in pairs(PerpetuaDB.guilds or {}) do
    for key, rec in pairs(g.players or {}) do
      local c = type(rec) == "table" and rec.profile and rec.profile.char
      if rec.self and c and not key:find(" ") and c.realm and c.realm ~= "" and not c.surname then g.players[key] = nil end
    end
  end
end

function ns.startComm()
  tidy()
  ns.try(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  C_Timer.NewTicker(0.2, pump)
  -- Re-announce every 10 minutes so anyone who missed a change catches up; drop stalled transfers.
  C_Timer.NewTicker(600, function() ns.announce() end)
  C_Timer.NewTicker(60, function()
    for key, b in pairs(buffers) do if GetTime() - b.at > 120 then buffers[key] = nil end end
  end)
end

ns.onAddonMessage = function(prefix, text, channel, sender)
  if prefix == PREFIX then pcall(onMessage, text, channel, sender) end
end
