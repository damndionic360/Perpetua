-- Hide Olympus: hides chat from players in any guild with "Olympus" in its name (ns.OLYMPUS) and turns away their
-- whispers, guild invites and charters, group invites, trades and duels. It all happens in this client: nobody is
-- put on the ignore list, nothing is sent anywhere, and they can't tell.
--
-- The game only says which guild a player is in when it shows you that player (a nameplate, your target or
-- mouseover, your group, /who, a trade window, an invite), so the addon learns names as it goes and remembers them
-- in PerpetuaDB.olympus.known. Chat from someone it hasn't seen yet still shows until it does, except a whisper
-- from someone on screen, any whisper that says "Olympus" and, with "mentions" on, any chat that does.
local _, ns = ...
local try = ns.try

local O = { session = { learned = 0, counts = {} } }
ns.olympus = O

-- Each can be switched off on the Hide Olympus page; the switch in the sidebar turns them all on or off.
O.OPTIONS = {
  { key = "chat", label = "Hide their chat", hint = "Say, yell, emotes, every channel, and party and raid chat." },
  { key = "mentions", parent = "chat", label = "Hide any chat that says Olympus",
    hint = "From anyone, like trade asking for an Olympus layer." },
  { key = "whispers", label = "Hide their whispers", hint = "Also any whisper that says \"Olympus\", from anyone. They aren't told." },
  { key = "guild", label = "Turn down guild invites and charters", hint = "Invites to an Olympus guild, and Olympus charters to sign." },
  { key = "party", label = "Turn down group invites", hint = "" },
  { key = "trade", label = "Cancel trades", hint = "Including ones you open yourself." },
  { key = "duel", label = "Turn down duels", hint = "" },
}
O.COUNTED = { chat = "messages", mentions = "messages naming Olympus", whispers = "whispers", guild = "guild invites", party = "group invites", trade = "trades", duel = "duels" }

local FORGET_AFTER = 45 * 86400 -- forget anyone not seen in Olympus for this long
local byGuid = {}               -- GUID -> name, for chat lines that come with a GUID

function O.db()
  PerpetuaDB.olympus = PerpetuaDB.olympus or {}
  local db = PerpetuaDB.olympus
  db.opts = db.opts or {}
  db.known = db.known or {}
  for _, o in ipairs(O.OPTIONS) do if db.opts[o.key] == nil then db.opts[o.key] = true end end
  return db
end

function O.isOlympus(guild)
  guild = ns.text(guild)
  if not guild then return false end
  guild = guild:lower()
  for _, p in ipairs(ns.OLYMPUS) do if guild:find(p, 1, true) then return true end end
  return false
end

local PARENT = {}
for _, o in ipairs(O.OPTIONS) do PARENT[o.key] = o.parent end

-- Switched on (and, with a key, that part and the one it sits under). Members only, like the rest of the addon.
function O.active(key)
  local db = PerpetuaDB.olympus
  if not (db and db.on) or ns.locked() then return false end
  while key do
    if db.opts[key] == false then return false end
    key = PARENT[key]
  end
  return true
end

function O.knownCount()
  local n = 0
  for _ in pairs(O.db().known) do n = n + 1 end
  return n
end

-- What the game told us about a player: in an Olympus guild (remember them), in another guild (forget them), or
-- nil when it doesn't know (not in a guild, or not loaded yet), which changes nothing.
function O.note(name, guild, guid)
  if not name or name == ns.selfName then return end
  local known = O.db().known
  local e = known[name]
  if O.isOlympus(guild) then
    if not e then
      e = {}
      known[name] = e
      O.session.learned = O.session.learned + 1
    end
    e.g, e.t = ns.text(guild), ns.now()
    if guid then e.id = guid; byGuid[guid] = name end
  elseif e and type(guild) == "string" then
    known[name] = nil
  end
end

local function unitName(unit)
  local first, surname = try(UnitName, unit)
  first = ns.text(first)
  return first and ns.fullName(first, ns.FOREVER and ns.text(surname) or nil)
end

local function learnUnit(unit)
  if not try(UnitIsPlayer, unit) then return end
  local name = unitName(unit)
  if not name then return end
  local guild = ns.text(try(GetGuildInfo, unit))
  -- No guild name can also mean "not loaded yet", so only a guild name counts as an answer.
  O.note(name, guild or nil, ns.text(try(UnitGUID, unit)))
end

-- Whether this player is known to be in Olympus.
function O.match(name, guid)
  local known = O.db().known
  guid = ns.text(guid)
  if guid and byGuid[guid] and known[byGuid[guid]] then return true end
  name = ns.playerKey(ns.text(name))
  return name ~= nil and known[name] ~= nil
end

-- For invites and duels, which come with only a name: also look at the players on screen right now.
local function matchNow(name, guid)
  if O.match(name, guid) then return true end
  local key = ns.playerKey(ns.text(name))
  if not key then return false end
  local units = { "target", "mouseover", "focus" }
  for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
  for _, unit in ipairs(units) do
    if try(UnitIsPlayer, unit) and unitName(unit) == key then
      learnUnit(unit)
      return O.isOlympus(try(GetGuildInfo, unit))
    end
  end
  return false
end

local lastLine = {}
local function count(key, line, who)
  if line and lastLine[key] == line then return end -- the same line passes through every chat window
  lastLine[key] = line
  O.session.counts[key] = (O.session.counts[key] or 0) + 1
  if who and O.db().notify then
    print("|cffd4af37Perpetua|r: turned away " .. who .. ".")
  end
  ns.refreshUI()
end

local function hidePopup(...)
  for _, which in ipairs({ ... }) do try(StaticPopup_Hide, which) end
end

-- ---------- chat ----------

local CHAT = {
  chat = { "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE", "CHAT_MSG_CHANNEL",
    "CHAT_MSG_CHANNEL_JOIN", "CHAT_MSG_CHANNEL_LEAVE", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
  whispers = { "CHAT_MSG_WHISPER" },
}

-- A whisper that names Olympus ("<Olympus> is recruiting!"), from anyone. Unless it came from a guildmate or friend, its
-- sender is remembered like any other Olympus player, until the game shows them in another guild.
local function recruiting(msg, sender, guid)
  msg = ns.text(msg)
  if not (msg and O.isOlympus(msg)) then return false end
  local who = guid or sender
  if try(IsGuildMember, who) or (C_FriendList and try(C_FriendList.IsFriend, who)) then return true end
  local name = ns.playerKey(ns.text(sender))
  if name and name ~= ns.selfName and not O.db().known[name] then
    O.db().known[name] = { g = "Olympus (whispered)", t = ns.now(), id = guid }
    if guid then byGuid[guid] = name end
    O.session.learned = O.session.learned + 1
  end
  return true
end

-- Chat event arguments: message, sender, ..., lineID (11th), sender GUID (12th). Return true to hide the line.
local function chatFilter(key)
  return function(_, _, msg, sender, ...)
    if not O.active(key) then return false end
    local line, guid = select(9, ...), ns.text(select(10, ...))
    -- Recruiters whisper strangers, so a whisper also checks who's on screen and what it says.
    if O.match(sender, guid) or (key == "whispers" and (matchNow(sender, guid) or recruiting(msg, sender, guid))) then
      count(key, ns.readable(line))
      return true
    end
    -- Other chat that says "Olympus" doesn't make its sender one: in trade it's mostly people asking for their layer.
    if key == "chat" and O.active("mentions") and O.isOlympus(msg) then
      count("mentions", ns.readable(line))
      return true
    end
    return false
  end
end

local addFilter = ChatFrame_AddMessageEventFilter or (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter)
for key, list in pairs(CHAT) do
  local f = chatFilter(key)
  for _, e in ipairs(list) do try(addFilter, e, f) end
end

-- ---------- invites, trades, duels ----------

local function display(name, guild)
  return ns.safe(ns.playerKey(ns.text(name)) or "someone") .. (guild and (" <" .. ns.safe(guild) .. ">") or "")
end

local function knownGuild(name)
  local e = O.db().known[ns.playerKey(ns.text(name)) or ""]
  return e and e.g
end

function O.onEvent(event, ...)
  if not O.active() then return end
  if event == "NAME_PLATE_UNIT_ADDED" then
    learnUnit(...)
  elseif event == "UPDATE_MOUSEOVER_UNIT" then
    learnUnit("mouseover")
  elseif event == "PLAYER_TARGET_CHANGED" then
    learnUnit("target")
  elseif event == "PLAYER_FOCUS_CHANGED" then
    learnUnit("focus")
  elseif event == "GROUP_ROSTER_UPDATE" then
    local raid = try(IsInRaid)
    for i = 1, raid and 40 or 4 do learnUnit((raid and "raid" or "party") .. i) end
  elseif event == "WHO_LIST_UPDATE" then
    local who = C_FriendList
    for i = 1, (who and try(who.GetNumWhoResults)) or 0 do
      local info = try(who.GetWhoInfo, i)
      -- /who answers for certain: an empty guild means not in one.
      if info then O.note(ns.playerKey(ns.text(info.fullName)), ns.readable(info.fullGuildName) or nil) end
    end
  elseif event == "GUILD_INVITE_REQUEST" then
    local inviter, guild = ...
    O.note(ns.playerKey(ns.text(inviter)), ns.text(guild))
    if O.active("guild") and O.isOlympus(guild) then
      try(DeclineGuild)
      if GuildInviteFrame then try(GuildInviteFrame.Hide, GuildInviteFrame) end
      hidePopup("GUILD_INVITE")
      count("guild", nil, "a guild invite from " .. display(inviter, ns.text(guild)))
    end
  elseif event == "PETITION_SHOW" then
    local _, title, _, _, originator, isOriginator = try(GetPetitionInfo)
    if O.active("guild") and not isOriginator and (O.isOlympus(title) or O.match(originator)) then
      try(ClosePetition)
      count("guild", nil, "a guild charter for <" .. ns.safe(ns.text(title) or "?") .. "> from " .. display(originator))
    end
  elseif event == "PARTY_INVITE_REQUEST" then
    local name = ...
    local guid = select(7, ...)
    if O.active("party") and matchNow(name, guid) then
      try(DeclineGroup)
      hidePopup("PARTY_INVITE", "PARTY_INVITE_XREALM")
      count("party", nil, "a group invite from " .. display(name, knownGuild(name)))
    end
  elseif event == "TRADE_SHOW" then
    learnUnit("NPC") -- the other side of a trade is the "NPC" unit
    local name = unitName("NPC")
    if O.active("trade") and O.match(name, ns.text(try(UnitGUID, "NPC"))) then
      try(CancelTrade)
      count("trade", nil, "a trade with " .. display(name, knownGuild(name)))
    end
  elseif event == "DUEL_REQUESTED" then
    local name = ...
    if O.active("duel") and matchNow(name) then
      try(CancelDuel)
      hidePopup("DUEL_REQUESTED")
      count("duel", nil, "a duel from " .. display(name, knownGuild(name)))
    end
  end
end

local events = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "NAME_PLATE_UNIT_ADDED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
  "GROUP_ROSTER_UPDATE", "WHO_LIST_UPDATE", "GUILD_INVITE_REQUEST", "PETITION_SHOW", "PARTY_INVITE_REQUEST", "TRADE_SHOW", "DUEL_REQUESTED" }) do
  pcall(events.RegisterEvent, events, e) -- not every client has every event
end
events:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    -- Forget anyone not seen in Olympus for a while; index the rest by GUID.
    local cutoff = ns.now() - FORGET_AFTER
    for name, e in pairs(O.db().known) do
      if type(e) ~= "table" or (e.t or 0) < cutoff then O.db().known[name] = nil
      elseif e.id then byGuid[e.id] = name end
    end
    return
  end
  local ok, err = pcall(O.onEvent, event, ...)
  if not ok and ns.debug then print("Perpetua Olympus:", err) end
end)

-- ---------- switches ----------

function O.set(on)
  O.db().on = on and true or false
  print("|cffd4af37Perpetua|r: Hide Olympus is " .. (on and "|cff8fd18aon|r" or "off") .. ".")
  ns.refreshUI(true)
end

function O.setOption(key, on)
  O.db().opts[key] = on and true or false
  ns.refreshUI(true)
end

-- /who finds up to 50 players at a time, so the button works through level and class groups, one per click. The
-- game only allows /who from a click or key press, which is why it can't run by itself.
local WHO = {}
for _, levels in ipairs({ "60", "55-59", "50-54", "40-49", "30-39", "20-29", "10-19", "1-9" }) do
  for _, class in ipairs({ "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Mage", "Warlock", "Druid" }) do
    WHO[#WHO + 1] = levels .. ' c-"' .. class .. '"'
  end
end
O.WHO_TOTAL = #WHO

function O.lookUp()
  local db = O.db()
  db.whoNext = (db.whoNext or 0) % #WHO + 1
  local query = 'g-"' .. ns.OLYMPUS_WHO .. '" ' .. WHO[db.whoNext]
  if C_FriendList and C_FriendList.SendWho then try(C_FriendList.SendWho, query) else try(SendWho, query) end
  return db.whoNext
end
