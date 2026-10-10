-- The guild key and the guild button on the micro menu open the Perpetua window's Guild page instead of
-- Blizzard's guild window. Holding Shift opens Blizzard's, as before.
--
-- Nothing of Blizzard's is replaced, so nothing of theirs is tainted:
--  * the key: an override binding (ours, set out of combat) on whatever key is bound to "Toggle Guild" clicks
--    our own button; Shift + that key clicks a secure button that clicks the real guild button, so Blizzard's
--    window still opens through secure code.
--  * the micro button: a plain frame of ours sits over it and opens Perpetua. While Shift is held it stops
--    taking the mouse, so the click lands on the real button underneath.
-- It's a "new feature" you opt into (PerpetuaDB.guildTakeover = true): the New guild window switch at the top of
-- the Perpetua window, Options > AddOns > Perpetua, the Guild Info page or /ppta guildui. Off (the default) or
-- outside the guild, the key and the button are Blizzard's.
local _, ns = ...
local try = ns.try

local owner = CreateFrame("Frame")             -- owns the override bindings
local opener = CreateFrame("Button", "PerpetuaGuildKey", UIParent)
opener:SetScript("OnClick", function() ns.toggle("Guild") end)

-- Shift: Blizzard's window, through a secure click on the real micro button.
local blizzard = CreateFrame("Button", "PerpetuaBlizzardGuild", UIParent, "SecureActionButtonTemplate")
blizzard:RegisterForClicks("AnyUp", "AnyDown")
blizzard:SetAttribute("type", "click")
blizzard:SetAttribute("useOnKeyDown", false)

blizzard:Hide() -- bindings click it while hidden; it only shows while floating over one of our buttons (below)

-- Buttons in the Perpetua window that open Blizzard's guild window (notes, message of the day, guild info: the
-- game only lets Blizzard's own UI change those). Our buttons can't click Blizzard's securely, so on hover the secure
-- button above moves over ours and takes the click itself. In combat it can't move, so the click just says so.
local hovering
local function float(target)
  if InCombatLockdown() or not GuildMicroButton then return end
  hovering = target
  blizzard:ClearAllPoints()
  blizzard:SetAllPoints(target)
  blizzard:SetFrameStrata(target:GetFrameStrata())
  blizzard:SetFrameLevel(target:GetFrameLevel() + 10)
  blizzard:Show()
end
blizzard:SetScript("OnEnter", function(self)
  if not hovering then return end
  try(hovering.LockHighlight, hovering)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(hovering.blizzardTitle or "Blizzard's guild window", 0.83, 0.69, 0.22)
  GameTooltip:AddLine(hovering.blizzardTip or "Opens Blizzard's guild window.", 1, 1, 1, true)
  GameTooltip:Show()
end)
blizzard:SetScript("OnLeave", function(self)
  if hovering then try(hovering.UnlockHighlight, hovering) end
  GameTooltip:Hide()
  hovering = nil
  if not InCombatLockdown() then self:Hide(); self:ClearAllPoints() end
end)
-- The Perpetua window steps aside so Blizzard's has the screen.
blizzard:SetScript("PreClick", function() if hovering and PerpetuaFrame then PerpetuaFrame:Hide() end end)

function ns.opensBlizzardGuild(button, title, tip)
  button.blizzardTitle, button.blizzardTip = title, tip
  button:HookScript("OnEnter", function(self) float(self) end)
  -- Only reached when the secure button wasn't over it (in combat, or no guild button on this client).
  button:HookScript("OnClick", function()
    print("|cffd4af37Perpetua|r: Blizzard's guild window can only be opened from here out of combat. "
      .. "Shift + your guild key (J) opens it any time.")
  end)
end

local overlay -- over GuildMicroButton

function ns.newGuildWindow() return PerpetuaDB.guildTakeover == true end
function ns.guildTakeoverOn() return ns.newGuildWindow() and not ns.locked() end

local pending, applied = false, nil
local function apply()
  if InCombatLockdown() then pending = true return end
  pending = false
  local on = ns.guildTakeoverOn()
  -- Setting override bindings fires UPDATE_BINDINGS, which calls this again: only redo it when something changed.
  local state = tostring(on) .. ":" .. table.concat({ GetBindingKey("TOGGLEGUILDTAB") }, ",")
  if state == applied then return end
  applied = state
  ClearOverrideBindings(owner)
  if GuildMicroButton then blizzard:SetAttribute("clickbutton", GuildMicroButton) end
  if on then
    for _, key in ipairs({ GetBindingKey("TOGGLEGUILDTAB") }) do
      SetOverrideBindingClick(owner, false, key, "PerpetuaGuildKey", "LeftButton")
      -- Shift + the key for Blizzard's window, unless Shift + that key already does something else.
      local shifted = key:find("SHIFT%-") and nil or ("SHIFT-" .. key)
      if shifted and (GetBindingAction(shifted) or "") == "" and GuildMicroButton then
        SetOverrideBindingClick(owner, false, shifted, "PerpetuaBlizzardGuild", "LeftButton")
      end
    end
  end
  if overlay then overlay:SetShown(on) end
end
ns.applyGuildTakeover = apply

-- The one switch everything uses.
function ns.setNewGuildWindow(on, quiet)
  PerpetuaDB.guildTakeover = on and true or false
  apply()
  if not quiet then
    print("|cffd4af37Perpetua|r: " .. (on and "new guild window on: the guild key and guild button open Perpetua (hold Shift for Blizzard's)."
      or "new guild window off: the guild key and guild button open Blizzard's guild window."))
  end
  if ns.refreshUI then ns.refreshUI(true) end
end

-- Options > AddOns > Perpetua: a checkbox for it.
local function registerSettings()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
  local category = Settings.RegisterVerticalLayoutCategory("Perpetua")
  local setting = Settings.RegisterProxySetting(category, "PERPETUA_NEW_GUILD_WINDOW", Settings.VarType.Boolean,
    "New guild window", false, ns.newGuildWindow, function(value) ns.setNewGuildWindow(value, true) end)
  Settings.CreateCheckbox(category, setting,
    "New: the guild key (J) and the guild button open Perpetua's guild window instead of Blizzard's. Hold Shift for Blizzard's.")
  Settings.RegisterAddOnCategory(category)
end

local function makeOverlay()
  local mb = GuildMicroButton
  if overlay or not mb then return end
  overlay = CreateFrame("Button", nil, mb)
  overlay:SetAllPoints(mb)
  overlay:SetFrameLevel(mb:GetFrameLevel() + 5)
  overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  overlay:SetScript("OnClick", function() ns.toggle("Guild") end)
  -- Look like the button underneath: its highlight and its tooltip.
  overlay:SetScript("OnEnter", function()
    try(mb.LockHighlight, mb)
    local enter = mb:GetScript("OnEnter")
    if enter then try(enter, mb) end
    if GameTooltip:IsOwned(mb) then
      GameTooltip:AddLine("Opens Perpetua. Shift-click for Blizzard's guild window.", 0.83, 0.69, 0.22, true)
      GameTooltip:Show()
    end
  end)
  overlay:SetScript("OnLeave", function()
    try(mb.UnlockHighlight, mb)
    local leave = mb:GetScript("OnLeave")
    if leave then try(leave, mb) else GameTooltip:Hide() end
  end)
  overlay:SetShown(ns.guildTakeoverOn())
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UPDATE_BINDINGS")
f:RegisterEvent("PLAYER_GUILD_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("MODIFIER_STATE_CHANGED")
f:SetScript("OnEvent", function(_, event)
  if event == "MODIFIER_STATE_CHANGED" then
    -- Shift held: let clicks through to the real button.
    if overlay then overlay:EnableMouse(not IsShiftKeyDown()) end
    return
  end
  if event == "PLAYER_LOGIN" then
    makeOverlay()
    try(registerSettings)
  end
  if event == "PLAYER_REGEN_ENABLED" and not pending then return end
  -- Guild info arrives a moment after login and after joining or leaving.
  C_Timer.After(event == "PLAYER_LOGIN" and 5 or 0.5, apply)
end)
