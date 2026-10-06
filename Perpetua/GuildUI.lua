-- Everything Blizzard's guild window does, in the Perpetua window: the full roster (rank, zone, notes, last
-- online) with a member panel and a right-click menu (rank, notes, whisper, invite to group, remove, make leader),
-- inviting, and the Guild Info page (message of the day, guild information, the guild event log, leave and
-- disband). GuildTakeover.lua makes the guild key and button open it.
--
-- Every action goes through the same calls and permission checks as Blizzard's Communities guild UI
-- (Blizzard_Communities/GuildRoster.lua, GuildInfo.lua, StaticPopup GameDialogDefs.lua on the Forever client),
-- with our own dialogs in place of StaticPopups, which addon code would taint.
local _, ns = ...
local try, safe, T = ns.try, ns.safe, ns.T

local NOTE_MAX, MOTD_MAX, INFO_MAX = 31, 255, 500

local function color(hex, s) return "|cff" .. hex .. s .. "|r" end
local function say(msg) print("|cffd4af37Perpetua|r: " .. msg) end

-- Runs a guild action; some are refused in combat or instances on this client, so say so instead of erroring.
local function act(what, fn, ...)
  if type(fn) ~= "function" then say("can't " .. what .. " on this client.") return end
  local ok, err = pcall(fn, ...)
  if not ok then say("couldn't " .. what .. " (" .. tostring(err):gsub("^.-:%d+: ", "") .. ").") end
end

-- ---------- roster data ----------

local function myRankOrder()
  local _, _, rankIndex = try(GetGuildInfo, "player")
  return (ns.num(rankIndex) or 99) + 1
end

local function lastOnlineText(m)
  if m.online then return color(T.HEX.ok, "Online") end
  if m.mobile then return color(T.HEX.warm, "Mobile") end
  local y, mo, d, h = unpack(m.last)
  if not (y or mo or d or h) then return "" end
  local text = TimeUtil and TimeUtil.GetRecentTimeDate and try(TimeUtil.GetRecentTimeDate, y, mo, d, h)
  if text then return text end
  if (y or 0) > 0 then return y .. "y" elseif (mo or 0) > 0 then return mo .. "mo" elseif (d or 0) > 0 then return d .. "d" end
  return math.max(h or 0, 1) .. "h"
end

-- Every member, offline ones included: { full ("First-Surname", what the API wants), name ("First Surname"),
-- rank, rankOrder (1 = Guild Master), level, classFile, zone, note, officerNote, online, guid, ... }.
local function members()
  local list, me = {}, UnitGUID("player")
  for i = 1, (ns.num(try(GetNumGuildMembers)) or 0) do
    local full, rankName, rankIndex, level, className, zone, note, officerNote, online, _, classFile, _, _, isMobile,
      _, _, guid = try(GetGuildRosterInfo, i)
    full = ns.text(full)
    if full then
      local y, mo, d, h = try(GetGuildRosterLastOnline, i)
      local m = {
        index = i, full = full, name = ns.playerKey(full), rank = ns.text(rankName) or "?",
        rankOrder = (ns.num(rankIndex) or 0) + 1, level = ns.num(level), className = ns.text(className),
        classFile = ns.text(classFile), zone = ns.text(zone) or "", note = ns.text(note) or "",
        officerNote = ns.text(officerNote) or "", online = ns.readable(online) and true or false,
        mobile = ns.readable(isMobile) and true or false, guid = ns.text(guid),
        last = { ns.num(y), ns.num(mo), ns.num(d), ns.num(h) },
      }
      m.isSelf = m.guid ~= nil and m.guid == me
      m.away = m.online and 0 or ((m.last[1] or 0) * 8760 + (m.last[2] or 0) * 730 + (m.last[3] or 0) * 24 + (m.last[4] or 0) + (m.mobile and 0.5 or 1))
      list[#list + 1] = m
    end
  end
  return list
end
ns.guildMembers = members

-- What I may do to member m, by Blizzard's own rules (CommunitiesGuildMemberDetailMixin:DisplayMember).
local function rights(m)
  local mine, maxRank = myRankOrder(), ns.num(try(GuildControlGetNumRanks)) or 0
  local promote, demote = try(CanGuildPromote), try(CanGuildDemote)
  return {
    rank = not m.isSelf and ((promote and m.rankOrder > mine + 1) or (demote and m.rankOrder < maxRank and m.rankOrder > mine)),
    highest = promote and (mine + 1) or m.rankOrder,
    lowest = demote and maxRank or m.rankOrder,
    remove = not m.isSelf and try(CanGuildRemove) and m.rankOrder > mine,
    publicNote = m.isSelf or try(CanEditPublicNote),
    viewOfficer = try(C_GuildInfo.CanViewOfficerNote),
    officerNote = try(C_GuildInfo.CanEditOfficerNote),
    leader = not m.isSelf and try(IsGuildLeader),
  }
end

-- ---------- actions ----------

local A = {}
function A.whisper(m)
  local tell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
  if tell then tell(m.full) end
end
function A.groupInvite(m) act("invite " .. m.name .. " to your group", C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit, m.full) end
function A.setRank(m, order)
  if order == m.rankOrder then return end
  if not try(C_GuildInfo.IsGuildRankAssignmentAllowed, m.guid, order) then
    say("that rank needs an authenticator on " .. m.name .. "'s account.") return
  end
  act("change " .. m.name .. "'s rank", C_GuildInfo.SetGuildRankOrder, m.guid, order)
end
function A.note(m, public)
  local label = public and "Public note" or "Officer note"
  T.dialog({
    title = label, text = m.name, accept = "Save",
    input = { text = public and m.note or m.officerNote, maxLetters = NOTE_MAX },
    onAccept = function(text) act("save the note", C_GuildInfo.SetNote, m.guid, text, public) end,
  })
end
function A.remove(m)
  T.dialog({
    title = "Remove from guild", accept = "Remove",
    text = "Remove " .. m.name .. " from the guild?",
    onAccept = function() act("remove " .. m.name, C_GuildInfo.RemoveFromGuild, m.guid) end,
  })
end
function A.leader(m)
  T.dialog({
    title = "Make guild leader", accept = "Make leader",
    text = "Make " .. m.name .. " the Guild Master? You'll step down to the rank below.",
    onAccept = function() act("make " .. m.name .. " guild leader", C_GuildInfo.SetLeader, m.full) end,
  })
end
function A.invite()
  T.dialog({
    title = "Invite to guild", text = "Their character name (First-Surname works too).", accept = "Invite",
    input = { maxLetters = 48 },
    onAccept = function(name)
      name = (name or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", "-")
      if name ~= "" then act("invite " .. name, C_GuildInfo.Invite, name) end
    end,
  })
end
function A.leave()
  local leader = try(IsGuildLeader)
  T.dialog({
    title = "Leave guild", accept = "Leave",
    text = leader and "You're the Guild Master: make someone else leader first, or disband the guild."
      or ("Leave <" .. safe(ns.guildName() or "") .. ">?"),
    onAccept = not leader and function() act("leave the guild", C_GuildInfo.Leave) end or nil,
  })
end
function A.disband()
  T.dialog({
    title = "Disband guild", accept = "Disband",
    text = "Disband <" .. safe(ns.guildName() or "") .. ">? Everyone is removed and the guild is gone for good.\n\nType DISBAND to confirm.",
    input = { maxLetters = 7 },
    onAccept = function(text) if (text or ""):upper() == "DISBAND" then act("disband the guild", C_GuildInfo.Disband) end end,
  })
end
function A.editText(kind)
  local motd = kind == "motd"
  T.dialog({
    title = motd and "Message of the day" or "Guild information", accept = "Save", width = 520,
    input = { text = motd and (try(C_GuildInfo.GetMOTD) or "") or (try(C_GuildInfo.GetInfoText) or ""),
      maxLetters = motd and MOTD_MAX or INFO_MAX, multiline = true, height = motd and 100 or 220 },
    onAccept = function(text)
      if motd then act("set the message of the day", C_GuildInfo.SetMOTD, text)
      else act("save the guild information", C_GuildInfo.SetInfoText, text) end
    end,
  })
end
ns.guildActions = A

-- ---------- right-click menu ----------

local function rankMenu(parent, m, r)
  for order = r.highest, r.lowest do
    local radio = parent:CreateRadio(GuildControlGetRankName(order) or ("Rank " .. order),
      function() return m.rankOrder == order end, function() A.setRank(m, order) end, order)
    if not try(C_GuildInfo.IsGuildRankAssignmentAllowed, m.guid, order) then radio:SetEnabled(false) end
  end
end

local function memberMenu(owner, m)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return end
  local r = rights(m)
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(m.name)
    if not m.isSelf then
      root:CreateButton("Whisper", function() A.whisper(m) end)
      local inv = root:CreateButton("Invite to group", function() A.groupInvite(m) end)
      if not m.online then inv:SetEnabled(false) end
    end
    if ns.players()[m.name] then
      root:CreateButton("View profile", function() ns.selected = m.name; ns.showTab("Character") end)
    end
    if r.rank then rankMenu(root:CreateButton("Set rank"), m, r) end
    if r.publicNote then root:CreateButton("Edit public note", function() A.note(m, true) end) end
    if r.officerNote then root:CreateButton("Edit officer note", function() A.note(m, false) end) end
    if r.leader then root:CreateButton("Make guild leader", function() A.leader(m) end) end
    if r.remove then root:CreateButton(color(T.HEX.danger, "Remove from guild"), function() A.remove(m) end) end
    if m.isSelf then root:CreateButton(color(T.HEX.danger, "Leave guild"), function() A.leave() end) end
  end)
end

-- ---------- member panel ----------

local R = { showOffline = true, filter = "", sort = 6, desc = false, selected = nil } -- online first, then most recently seen

local function noteBox(parent, label)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(44)
  b.label = T.text(b, "label"); b.label:SetPoint("TOPLEFT"); b.label:SetText(label:upper())
  local bg = T.fill(b, "BACKGROUND", T.C.midnight, 0.9)
  bg:SetPoint("TOPLEFT", 0, -14); bg:SetPoint("BOTTOMRIGHT")
  b.edge = T.outline(b, 0, T.C.gold, 0.25)
  b.text = T.text(b, "small")
  b.text:SetPoint("TOPLEFT", 8, -19); b.text:SetPoint("RIGHT", -8, 0)
  local hl = T.fill(b, "HIGHLIGHT", T.C.gold, 0.1)
  hl:SetPoint("TOPLEFT", 0, -14); hl:SetPoint("BOTTOMRIGHT")
  return b
end

local function buildPanel(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetWidth(262)
  p:SetPoint("TOPRIGHT"); p:SetPoint("BOTTOMRIGHT")
  T.panel(p)
  p:Hide()
  local close = T.closeButton(p, function() R.selected = nil; ns.refreshUI(true) end)
  close:SetPoint("TOPRIGHT", -4, -4)
  p.name = T.text(p, "heading"); p.name:SetPoint("TOPLEFT", 14, -14); p.name:SetPoint("RIGHT", -34, 0)
  p.line1 = T.text(p, "small"); p.line1:SetPoint("TOPLEFT", p.name, "BOTTOMLEFT", 0, -6)
  p.line2 = T.text(p, "muted"); p.line2:SetPoint("TOPLEFT", p.line1, "BOTTOMLEFT", 0, -3); p.line2:SetPoint("RIGHT", -14, 0)
  p.rankLabel = T.text(p, "label"); p.rankLabel:SetPoint("TOPLEFT", p.line2, "BOTTOMLEFT", 0, -14); p.rankLabel:SetText("RANK")
  p.rankText = T.text(p, "body"); p.rankText:SetPoint("TOPLEFT", p.rankLabel, "BOTTOMLEFT", 0, -4)
  p.rankButton = T.button(p, "Rank", 234, function(self) if R.member then
    local m, r = R.member, rights(R.member)
    MenuUtil.CreateContextMenu(self, function(_, root) rankMenu(root, m, r) end)
  end end, "tab")
  p.rankButton:SetPoint("TOPLEFT", p.rankLabel, "BOTTOMLEFT", 0, -4)
  p.note = noteBox(p, "Public note")
  p.note:SetPoint("TOPLEFT", p.rankLabel, "BOTTOMLEFT", 0, -38); p.note:SetPoint("RIGHT", -14, 0)
  p.note:SetScript("OnClick", function() if R.member and rights(R.member).publicNote then A.note(R.member, true) end end)
  p.officer = noteBox(p, "Officer note")
  p.officer:SetPoint("TOPLEFT", p.note, "BOTTOMLEFT", 0, -10); p.officer:SetPoint("RIGHT", -14, 0)
  p.officer:SetScript("OnClick", function() if R.member and rights(R.member).officerNote then A.note(R.member, false) end end)
  -- Buttons, two to a row, laid out by render.
  p.buttons = {
    whisper = T.button(p, "Whisper", 113, function() A.whisper(R.member) end, "tab"),
    group = T.button(p, "Group invite", 113, function() A.groupInvite(R.member) end, "tab"),
    profile = T.button(p, "Profile", 113, function() ns.selected = R.member.name; ns.showTab("Character") end, "tab"),
    leader = T.button(p, "Make leader", 113, function() A.leader(R.member) end, "tab"),
    remove = T.button(p, "Remove", 113, function() A.remove(R.member) end, "tab"),
    leave = T.button(p, "Leave guild", 113, function() A.leave() end, "tab"),
  }
  p.buttons.remove.label:SetTextColor(1, 0.54, 0.48)
  p.buttons.leave.label:SetTextColor(1, 0.54, 0.48)
  return p
end

local function renderPanel(p, m)
  R.member = m
  local r = rights(m)
  local cc = ns.classColor(m.classFile)
  p.name:SetText(T.classIcon(m.classFile) .. " " .. color(cc, safe(m.name)))
  p.line1:SetText(((m.level and ("Level " .. m.level .. " ")) or "") .. safe(m.className or ""))
  p.line2:SetText((m.zone ~= "" and (safe(m.zone) .. "  ·  ") or "") .. lastOnlineText(m))
  p.rankText:SetText(safe(m.rank))
  p.rankText:SetShown(not r.rank)
  p.rankButton:SetShown(r.rank and true or false)
  p.rankButton.label:SetText(safe(m.rank):upper() .. "  ▾")
  p.note.text:SetText(m.note ~= "" and safe(m.note) or (r.publicNote and color(T.HEX.muted, "Click to add a note") or ""))
  p.note:EnableMouse(r.publicNote and true or false)
  p.officer:SetShown(r.viewOfficer and true or false)
  p.officer.text:SetText(m.officerNote ~= "" and safe(m.officerNote) or (r.officerNote and color(T.HEX.muted, "Click to add an officer note") or ""))
  p.officer:EnableMouse(r.officerNote and true or false)
  local show = {
    whisper = not m.isSelf, group = not m.isSelf and m.online, profile = ns.players()[m.name] ~= nil,
    leader = r.leader, remove = r.remove, leave = m.isSelf,
  }
  local anchor = r.viewOfficer and p.officer or p.note
  local n = 0
  for _, key in ipairs({ "whisper", "group", "profile", "leader", "remove", "leave" }) do
    local b = p.buttons[key]
    b:ClearAllPoints()
    if show[key] then
      local col, row = n % 2, math.floor(n / 2)
      b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", col * 121, -16 - row * 34)
      b:Show()
      n = n + 1
    else
      b:Hide()
    end
  end
  p:Show()
end

-- ---------- roster view ----------

-- Builds the roster view into `area` (the Guild page's list area) with its controls on `bar`.
function ns.buildRoster(area, bar)
  R.area = area
  local holder = CreateFrame("Frame", nil, area)
  holder:SetPoint("TOPLEFT"); holder:SetPoint("BOTTOMRIGHT")
  R.holder = holder
  R.list = ns.List(holder, {
    { "Name", 170 }, { "Lvl", 28, "RIGHT" }, { "Rank", 100 }, { "Zone", 128 }, { "Note", 150 }, { "Last online", 82, "RIGHT" },
  }, function(i)
    if R.sort == i then R.desc = not R.desc else R.sort, R.desc = i, i == 2 end
    ns.refreshUI(true)
  end)
  R.list.header:SetClipsChildren(true)
  R.panel = buildPanel(area)

  local controls = {}
  R.search = T.searchBox(bar, 160, "Search the roster…", function(t) R.filter = t:lower(); ns.refreshUI() end)
  controls[#controls + 1] = R.search
  local check = CreateFrame("CheckButton", nil, bar, "UICheckButtonTemplate")
  check:SetSize(24, 24)
  check:SetChecked(R.showOffline)
  check:SetScript("OnClick", function(self) R.showOffline = self:GetChecked() and true or false; ns.refreshUI(true) end)
  local label = T.text(bar, "muted"); label:SetText("Show offline")
  R.invite = T.button(bar, "Invite", 90, function() A.invite() end)
  R.invite:SetPoint("TOPRIGHT", -26, -1)
  label:SetPoint("RIGHT", R.invite, "LEFT", -14, 0); check:SetPoint("RIGHT", label, "LEFT", -2, 0)
  R.count = T.text(bar, "muted", "RIGHT"); R.count:SetPoint("RIGHT", check, "LEFT", -14, 0)
  for _, c in ipairs({ check, label, R.invite, R.count }) do controls[#controls + 1] = c end
  R.controls = controls
  return R
end

function ns.showRosterControls(on)
  for _, c in ipairs(R.controls or {}) do c:SetShown(on) end
  if on then R.invite:SetShown(try(CanGuildInvite) and true or false) end
end

function ns.renderRoster()
  local all = members()
  local online, rows, selected = 0, {}, nil
  local canViewOfficer = try(C_GuildInfo.CanViewOfficerNote)
  for _, m in ipairs(all) do
    if m.online then online = online + 1 end
    if R.selected and m.guid == R.selected then selected = m end
    local search = (m.name .. " " .. m.rank .. " " .. m.zone .. " " .. m.note .. " " .. (m.className or "")):lower()
    if (R.showOffline or m.online or m.mobile) and (R.filter == "" or search:find(R.filter, 1, true)) then
      local dim = not m.online
      local name = T.classIcon(m.classFile) .. color(ns.classColor(m.classFile), safe(m.name))
      rows[#rows + 1] = {
        key = { m.name:lower(), m.level or 0, m.rankOrder, m.zone:lower(), m.note:lower(), m.away },
        cells = {
          name, m.level or "", dim and color(T.HEX.muted, safe(m.rank)) or safe(m.rank),
          color(dim and "7a8298" or T.HEX.text, safe(m.zone)), color(T.HEX.muted, safe(m.note)), lastOnlineText(m),
        },
        member = m,
        onClick = function(d, button, row)
          if button == "RightButton" then memberMenu(row, d.member) return end
          R.selected = (R.selected ~= d.member.guid) and d.member.guid or nil
          ns.refreshUI(true)
        end,
        onEnter = (canViewOfficer and m.officerNote ~= "") and function(row, d)
          GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
          GameTooltip:AddLine(d.member.name, T.C.gold[1], T.C.gold[2], T.C.gold[3])
          GameTooltip:AddLine("Officer note: " .. safe(d.member.officerNote), 1, 1, 1, true)
          GameTooltip:Show()
        end or nil,
      }
    end
  end
  local k, desc = R.sort, R.desc
  table.sort(rows, function(a, b)
    local x, y = a.key[k], b.key[k]
    if x == y then return a.key[1] < b.key[1] end
    if desc then return x > y end
    return x < y
  end)
  R.count:SetText(#all .. " members  ·  " .. online .. " online")
  R.invite:SetShown(try(CanGuildInvite) and true or false)
  R.holder:SetPoint("BOTTOMRIGHT", selected and -272 or 0, 0)
  R.list:SetRows(rows)
  if selected then renderPanel(R.panel, selected) else R.panel:Hide(); R.selected = nil; R.member = nil end
  ns.lastRosterRows = rows -- for the test harness
end

-- ---------- Guild Info page ----------

local G = {}

local function scrollText(parent, fontKey)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(1, 1)
  scroll:SetScrollChild(child)
  local fs = T.text(child, fontKey or "body")
  fs:SetPoint("TOPLEFT"); fs:SetWordWrap(true); fs:SetJustifyV("TOP"); fs:SetNonSpaceWrap(true)
  scroll:SetScript("OnSizeChanged", function(_, w) child:SetWidth(w); fs:SetWidth(w) end)
  function scroll:SetText(text)
    fs:SetText(text)
    child:SetHeight(math.max(1, fs:GetStringHeight() + 4))
  end
  return scroll
end

local function section(parent, title, onEdit)
  local h = T.text(parent, "heading"); h:SetText(title:upper())
  local edit = onEdit and T.button(parent, "Edit", 64, onEdit, "tab") or nil
  if edit then edit:SetHeight(20); edit:SetPoint("LEFT", h, "RIGHT", 10, 0) end
  return h, edit
end

function ns.buildGuildInfo(page)
  local left = CreateFrame("Frame", nil, page)
  left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT", 0, 46); left:SetWidth(360)
  local right = CreateFrame("Frame", nil, page)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 24, 0); right:SetPoint("BOTTOMRIGHT", 0, 46)

  local h1, e1 = section(left, "Message of the day", function() A.editText("motd") end)
  h1:SetPoint("TOPLEFT", 2, 0)
  G.motdEdit = e1
  local motdBox = CreateFrame("Frame", nil, left); T.panel(motdBox)
  motdBox:SetPoint("TOPLEFT", 0, -22); motdBox:SetPoint("RIGHT"); motdBox:SetHeight(90)
  G.motd = scrollText(motdBox); G.motd:SetPoint("TOPLEFT", 10, -8); G.motd:SetPoint("BOTTOMRIGHT", -28, 8)

  local h2, e2 = section(left, "Guild information", function() A.editText("info") end)
  h2:SetPoint("TOPLEFT", motdBox, "BOTTOMLEFT", 2, -18)
  G.infoEdit = e2
  local infoBox = CreateFrame("Frame", nil, left); T.panel(infoBox)
  infoBox:SetPoint("TOPLEFT", motdBox, "BOTTOMLEFT", 0, -40); infoBox:SetPoint("BOTTOMRIGHT")
  G.info = scrollText(infoBox); G.info:SetPoint("TOPLEFT", 10, -8); G.info:SetPoint("BOTTOMRIGHT", -28, 8)

  local h3 = section(right, "Guild log")
  h3:SetPoint("TOPLEFT", 2, 0)
  local logBox = CreateFrame("Frame", nil, right); T.panel(logBox)
  logBox:SetPoint("TOPLEFT", 0, -22); logBox:SetPoint("BOTTOMRIGHT")
  G.log = scrollText(logBox, "small"); G.log:SetPoint("TOPLEFT", 10, -8); G.log:SetPoint("BOTTOMRIGHT", -28, 8)

  -- Bottom row: "Use default guild UI", then leave / disband on the right.
  local switch = T.switch(page, function(on) ns.setDefaultGuildUI(on, true) end)
  switch:SetPoint("BOTTOMLEFT", 2, 8)
  G.switch = switch
  local sl = T.text(page, "small"); sl:SetPoint("LEFT", switch, "RIGHT", 10, 0)
  sl:SetText("Use default guild UI")
  local hint = T.text(page, "muted"); hint:SetPoint("LEFT", sl, "RIGHT", 8, 0)
  hint:SetText("(the guild key and button open Blizzard's guild window)")
  G.disband = T.button(page, "Disband", 100, function() A.disband() end, "tab")
  G.disband:SetPoint("BOTTOMRIGHT", 0, 4)
  G.leave = T.button(page, "Leave guild", 120, function() A.leave() end, "tab")
  G.leave:SetPoint("RIGHT", G.disband, "LEFT", -10, 0)
  G.leave.label:SetTextColor(1, 0.54, 0.48); G.disband.label:SetTextColor(1, 0.54, 0.48)
  G.shown = false
  page:SetScript("OnShow", function() try(QueryGuildEventLog); try(C_GuildInfo.GuildRoster) end)
end

local LOG = {
  invite = "GUILDEVENT_TYPE_INVITE", join = "GUILDEVENT_TYPE_JOIN", promote = "GUILDEVENT_TYPE_PROMOTE",
  demote = "GUILDEVENT_TYPE_DEMOTE", remove = "GUILDEVENT_TYPE_REMOVE", quit = "GUILDEVENT_TYPE_QUIT",
}

function ns.renderGuildInfo()
  local motd = try(C_GuildInfo.GetMOTD) or ""
  local info = try(C_GuildInfo.GetInfoText) or ""
  G.motd:SetText(motd ~= "" and safe(motd) or color(T.HEX.muted, "No message of the day."))
  G.info:SetText(info ~= "" and safe(info) or color(T.HEX.muted, "No guild information yet."))
  G.motdEdit:SetShown(try(CanEditMOTD) and true or false)
  G.infoEdit:SetShown(try(CanEditGuildInfo) and true or false)
  local lines = {}
  for i = (ns.num(try(GetNumGuildEvents)) or 0), 1, -1 do
    local kind, p1, p2, rank, y, mo, d, h = try(GetGuildEventInfo, i)
    local fmt = LOG[kind or ""] and _G[LOG[kind]]
    if fmt then
      local a, b = ns.playerKey(ns.text(p1)) or UNKNOWN, ns.playerKey(ns.text(p2)) or UNKNOWN
      local ok, msg = pcall(string.format, fmt, a, b, ns.text(rank) or "")
      if ok then
        local when = TimeUtil and try(TimeUtil.GetRecentTimeDate, y, mo, d, h)
        lines[#lines + 1] = safe(msg) .. (when and color(T.HEX.muted, "  " .. when) or "")
      end
    end
  end
  G.log:SetText(#lines > 0 and table.concat(lines, "\n") or color(T.HEX.muted, "Nothing in the log yet."))
  G.switch:SetOn(ns.useDefaultGuildUI())
  G.disband:SetShown(try(IsGuildLeader) and true or false)
end

-- Redraw when the guild changes.
local ev = CreateFrame("Frame")
for _, e in ipairs({ "GUILD_ROSTER_UPDATE", "GUILD_MOTD", "GUILD_EVENT_LOG_UPDATE", "GUILD_RANKS_UPDATE", "PLAYER_GUILD_UPDATE" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, arg1)
  -- Blizzard's member panel asks for a fresh roster when the update says it may.
  if event == "GUILD_ROSTER_UPDATE" and arg1 and PerpetuaFrame and PerpetuaFrame:IsShown() then try(C_GuildInfo.GuildRoster) end
  ns.refreshUI()
end)
