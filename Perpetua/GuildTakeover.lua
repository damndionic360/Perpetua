-- The guild key and the guild button on the micro menu open the Perpetua window's Guild page instead of
-- Blizzard's guild window. Holding Shift opens Blizzard's, as before.
--
-- Nothing of Blizzard's is replaced, so nothing of theirs is tainted:
--  * the key: an override binding (ours, set out of combat) on whatever key is bound to "Toggle Guild" clicks
--    our own button; Shift + that key clicks a secure button that clicks the real guild button, so Blizzard's
--    window still opens through secure code.
--  * the micro button: a plain frame of ours sits over it and opens Perpetua. While Shift is held it stops
--    taking the mouse, so the click lands on the real button underneath.
-- Off (PerpetuaDB.guildTakeover = false) or outside the guild, everything goes back to Blizzard's.
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
  if event == "PLAYER_LOGIN" then makeOverlay() end
  if event == "PLAYER_REGEN_ENABLED" and not pending then return end
  -- Guild info arrives a moment after login and after joining or leaving.
  C_Timer.After(event == "PLAYER_LOGIN" and 5 or 0.5, apply)
end)
