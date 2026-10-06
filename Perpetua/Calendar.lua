-- Raid calendar in game. The site is the source: an officer's Perpetua app writes it into SiteData.lua (loaded at
-- login and /reload), and the addon passes it around the guild as part "C" of guild sync. Only a calendar sent
-- by an officer (by guild rank) is accepted, so nobody can post fake raids.
--
-- Signing up in game stores the choice on this character (PerpetuaCharDB.signups) and sends it with the
-- character's profile; guild sync takes it to the site, where a newer sign-up made on the site wins.
local _, ns = ...

-- ---------- officers ----------

local rankCache, rankCacheAt = {}, 0

local function refreshRanks()
  wipe(rankCache)
  for i = 1, (ns.try(GetNumGuildMembers) or 0) do
    local full, rankName, rankIndex = ns.try(GetGuildRosterInfo, i)
    local key = ns.playerKey(ns.readable(full))
    if key then rankCache[key] = { index = ns.num(rankIndex), name = ns.text(rankName) } end
  end
  rankCacheAt = GetTime()
end

-- Guild Master and the rank below it, or any rank named like an officer rank.
function ns.isOfficer(name)
  if GetTime() - rankCacheAt > 60 then refreshRanks() end
  local r = rankCache[name]
  if not r then
    ns.try(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster) -- ask for the roster; next time it'll be there
    return false
  end
  if r.index and r.index <= 1 then return true end
  local n = (r.name or ""):lower()
  return n:find("officer") ~= nil or n:find("master") ~= nil or n:find("leader") ~= nil
end

-- ---------- the calendar ----------

local function store()
  local g = PerpetuaDB.guilds and PerpetuaDB.guilds[ns.guildName() or "No guild"]
  if not g then ns.players(); g = PerpetuaDB.guilds[ns.guildName() or "No guild"] end
  return g
end

-- { t = when the site made it, events = { { id, title, instance, t, dur, size, notes, cancelled, signups = {...} } } }
function ns.calendar()
  return store().calendar
end

-- Raids in the next week that aren't cancelled (the count on the Calendar button).
function ns.upcomingRaids()
  local c, now, n = ns.calendar(), ns.now(), 0
  for _, e in ipairs(c and c.events or {}) do
    local t = tonumber(e.t)
    if t and not e.cancelled and t > now - 3600 and t < now + 7 * 86400 then n = n + 1 end
  end
  return n
end

function ns.calendarVersion()
  local c = ns.calendar()
  return c and c.t and tostring(c.t) or nil
end

local function valid(cal)
  return type(cal) == "table" and tonumber(cal.t) and type(cal.events) == "table"
end

-- A calendar from SiteData.lua (this computer runs the Perpetua app) or from an officer in the guild.
function ns.adoptCalendar(cal)
  if not valid(cal) then return false end
  local cur = ns.calendar()
  if cur and (cur.t or 0) >= cal.t then return false end
  store().calendar = cal
  ns.fire()
  return true
end

function ns.loadSiteCalendar()
  if PerpetuaSiteData and ns.adoptCalendar(PerpetuaSiteData) then ns.announce() end
end

-- ---------- sign-ups ----------

local STATUSES = { coming = true, tentative = true, absent = true }

function ns.signUp(eventId, status, role)
  if not STATUSES[status] then return end
  local class = select(2, UnitClass("player"))
  if role and not ns.canTake(class, role) then role = ns.classRoles(class)[1] end
  PerpetuaCharDB.signups = PerpetuaCharDB.signups or {}
  PerpetuaCharDB.signups[eventId] = { s = status, r = role, t = ns.now() }
  ns.refreshSelf()
end

-- This character's sign-ups for raids that haven't finished, for its profile.
function ns.mySignups()
  local out, cal = {}, ns.calendar()
  local ends = {}
  for _, e in ipairs(cal and cal.events or {}) do ends[e.id] = (e.t or 0) + (e.dur or 180) * 60 end
  for id, s in pairs(PerpetuaCharDB.signups or {}) do
    local finish = ends[tonumber(id)]
    if finish and finish < ns.now() then PerpetuaCharDB.signups[id] = nil
    elseif not finish and ns.now() - (s.t or 0) > 30 * 86400 then PerpetuaCharDB.signups[id] = nil
    else out[#out + 1] = { e = tonumber(id), s = s.s, r = s.r, t = s.t } end
  end
  table.sort(out, function(a, b) return a.e < b.e end)
  return out
end

-- Who's coming to an event: the site's list, updated with sign-ups made in game since the calendar was made
-- (from guildmates' profiles, and this character's own).
function ns.eventSignups(e)
  local cal = ns.calendar()
  local byName = {}
  for _, s in ipairs(e.signups or {}) do byName[s.n] = { n = s.n, c = s.c, s = s.s, r = s.r, l = s.l } end
  for name, rec in pairs(ns.players()) do
    local p = type(rec) == "table" and rec.profile
    for _, s in ipairs(p and p.signups or {}) do
      if s.e == e.id and (s.t or 0) > (cal and cal.t or 0) then
        local cur = byName[name] or { n = name, c = rec.class }
        cur.s, cur.r, cur.game = s.s, s.r, true
        byName[name] = cur
      end
    end
  end
  local mine = PerpetuaCharDB.signups and PerpetuaCharDB.signups[e.id]
  if mine and ns.selfName and (mine.t or 0) > (cal and cal.t or 0) then
    local cur = byName[ns.selfName] or { n = ns.selfName, c = select(2, UnitClass("player")) }
    cur.s, cur.r, cur.game = mine.s, mine.r, true
    byName[ns.selfName] = cur
  end
  local list = {}
  for _, s in pairs(byName) do list[#list + 1] = s end
  table.sort(list, function(a, b) return a.n < b.n end)
  return list
end
