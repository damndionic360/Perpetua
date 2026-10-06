-- The guild roster, saved for the site: every member's level and class, and when they were last online.
--
-- Guild sync only hears from guildmates who are online with the addon at the same time as you, so a character
-- levelled while you were away kept its old level on the site. The roster covers everyone, addon or not, online
-- or not. It's kept in PerpetuaDB.guilds[guild].roster (with rosterAt, when it was read), which the Perpetua app
-- uploads to the site; the site only ever raises a level from it, and only for characters already on its roster.
local _, ns = ...
local try = ns.try

local SCAN_EVERY = 60       -- seconds between reads of the roster at most (GUILD_ROSTER_UPDATE fires a lot)
local REQUEST_EVERY = 300   -- how often to ask the server for a fresh roster

local scanAt, scanQueued = 0, false

-- Seconds since a member was last online, from GetGuildRosterLastOnline's years/months/days/hours.
local function offlineFor(i)
  local y, mo, d, h = try(GetGuildRosterLastOnline, i)
  y, mo, d, h = ns.num(y), ns.num(mo), ns.num(d), ns.num(h)
  if not (y or mo or d or h) then return nil end
  return ((y or 0) * 365 + (mo or 0) * 30 + (d or 0)) * 86400 + (h or 0) * 3600
end

local function scan()
  scanQueued = false
  scanAt = GetTime()
  if ns.locked() then return end
  local guild = ns.guildName()
  local n = ns.num(try(GetNumGuildMembers)) or 0
  if not guild or n == 0 then return end
  local now = ns.now()
  local roster = {}
  for i = 1, n do
    local full, _, _, level, _, _, _, _, online, _, classFile = try(GetGuildRosterInfo, i)
    local name = ns.playerKey(ns.text(full))
    level = ns.num(level)
    if name and level then
      local away = not ns.readable(online) and offlineFor(i)
      roster[name] = { l = level, c = ns.text(classFile), s = away and now - away or now }
    end
  end
  if not next(roster) then return end
  ns.players() -- makes sure PerpetuaDB.guilds[guild] exists
  local g = PerpetuaDB.guilds[guild]
  g.roster, g.rosterAt = roster, now
  -- Raise the level on players we have a profile for (the profile itself is theirs and stays as sent).
  for name, rec in pairs(g.players or {}) do
    local r = roster[name]
    if type(rec) == "table" and r and r.l > (rec.level or 0) then rec.level = r.l end
  end
  try(ns.refreshUI)
end

-- A player's level for the window: the higher of the one we have (their last profile) and the roster's, which
-- keeps up while they play and you're offline.
function ns.levelOf(name, known)
  local g = name and PerpetuaDB.guilds and PerpetuaDB.guilds[ns.guildName() or "No guild"]
  local r = g and g.roster and g.roster[name]
  local l = type(r) == "table" and r.l or nil
  if l and (not known or l > known) then return l end
  return known
end

local function queueScan()
  if scanQueued then return end
  scanQueued = true
  C_Timer.After(math.max(1, SCAN_EVERY - (GetTime() - scanAt)), function() try(scan) end)
end

local function request()
  if IsInGuild() then try(C_GuildInfo and C_GuildInfo.GuildRoster or GuildRoster) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    C_Timer.After(10, request)
    C_Timer.NewTicker(REQUEST_EVERY, request)
  else
    queueScan()
  end
end)
