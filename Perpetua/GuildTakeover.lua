-- The guild key and the guild button on the micro menu open the Perpetua window's Guild page instead of
-- Blizzard's guild window. Holding Shift opens Blizzard's, as before.
--
-- Nothing of Blizzard's is replaced, so nothing of theirs is tainted:
--  * the key: an override binding (ours, set out of combat) on whatever key is bound to "Toggle Guild" clicks
--    our own button; Shift + that key clicks a secure button that clicks the real guild button, so Blizzard's
--    window still opens through secure code.
--  * the micro button: a plain frame of ours sits over it and opens Perpetua. While Shift is held it stops
--    taking the mouse, so the click lands on the real button underneath.
-- "Use default guild UI" (PerpetuaDB.guildTakeover = false: Options > AddOns > Perpetua, the Guild Info page or
-- /ppta guildui) or being outside the guild puts everything back to Blizzard's.
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

local overlay -- over GuildMicroButton

function ns.guildTakeoverOn()
  return PerpetuaDB.guildTakeover ~= false and not ns.locked()
end

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

-- The one switch everything uses: on = Blizzard's own guild window, as if Perpetua weren't installed.
function ns.useDefaultGuildUI() return PerpetuaDB.guildTakeover == false end
function ns.setDefaultGuildUI(on, quiet)
  PerpetuaDB.guildTakeover = not on
  apply()
  if not quiet then
    print("|cffd4af37Perpetua|r: " .. (on and "the guild key and guild button open Blizzard's guild window. Your guild tools are still in /ppta."
      or "the guild key and guild button open Perpetua (hold Shift for Blizzard's guild window)."))
  end
  if ns.refreshUI then ns.refreshUI(true) end
end

-- Options > AddOns > Perpetua: a checkbox for it.
local function registerSettings()
  if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterProxySetting) then return end
  local category = Settings.RegisterVerticalLayoutCategory("Perpetua")
  local setting = Settings.RegisterProxySetting(category, "PERPETUA_DEFAULT_GUILD_UI", Settings.VarType.Boolean,
    "Use default guild UI", false, ns.useDefaultGuildUI, function(value) ns.setDefaultGuildUI(value, true) end)
  Settings.CreateCheckbox(category, setting,
    "The guild key (J) and the guild button open Blizzard's guild window instead of Perpetua's. The rest of the addon works as before.")
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
    -- Say once that the guild key opens Perpetua now, and how to have Blizzard's back.
    if not PerpetuaDB.guildTakeoverTold and not ns.locked() then
      PerpetuaDB.guildTakeoverTold = true
      C_Timer.After(12, function()
        print("|cffd4af37Perpetua|r: the guild key (J) and guild button now open Perpetua's guild window; Shift opens Blizzard's. " ..
          "Prefer Blizzard's? Type |cfff2d78c/ppta guildui|r or tick \"Use default guild UI\" in Options > AddOns > Perpetua.")
      end)
    end
  end
  if event == "PLAYER_REGEN_ENABLED" and not pending then return end
  -- Guild info arrives a moment after login and after joining or leaving.
  C_Timer.After(event == "PLAYER_LOGIN" and 5 or 0.5, apply)
end)
