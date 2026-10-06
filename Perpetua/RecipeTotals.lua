-- Recipe totals: with two or more recipes tracked, one more block under the objective tracker's Profession list
-- adds up the reagents they need between them, drawn like Blizzard's own blocks (same font, colours, dash and tick).
--
-- It's our own frame anchored below the module's last block, not a block added to the module. Anything addon code
-- writes into Blizzard's tracker taints it, and a tainted tracker gets quest item buttons blocked in combat. The
-- hook only reads the module's state after each layout.
local _, ns = ...
local try = ns.try

-- ObjectiveTrackerModuleMixin's lineSpacing, fromBlockOffsetY and blockOffsetX.
local LINE_SPACING, BLOCK_GAP, INDENT = 4, 10, 20

local frame, rows = nil, {}
local waitingForNames = false

-- Text height the way the tracker measures it (ObjectiveTrackerBlockMixin:SetStringText): up to two lines.
local function setText(fs, text, color)
  fs:SetMaxLines(2)
  fs:SetHeight(0)
  fs:SetText(text)
  fs:SetTextColor(color.r, color.g, color.b)
  return fs:GetHeight()
end

-- { itemID, name, have, need } in the order the tracker lists them, and how many recipes are tracked.
local function totals()
  local list, byItem, count = {}, {}, 0
  for _, recraft in ipairs({ false, true }) do
    for _, recipeID in ipairs(try(C_TradeSkillUI.GetRecipesTracked, recraft) or {}) do
      count = count + 1
      local schematic = try(C_TradeSkillUI.GetRecipeSchematic, recipeID, recraft)
      for _, slot in ipairs(schematic and schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        if slot.required and slot.reagentType == Enum.CraftingReagentType.Basic and reagent and reagent.itemID then
          local row = byItem[reagent.itemID]
          if not row then
            local have = 0
            for _, r in ipairs(slot.reagents) do
              if r.itemID then have = have + (try(ItemUtil.GetCraftingReagentCount, r.itemID) or 0) end
            end
            row = { itemID = reagent.itemID, have = have, need = 0 }
            byItem[reagent.itemID] = row
            list[#list + 1] = row
          end
          row.need = row.need + (slot.quantityRequired or 0)
        end
      end
    end
  end
  for _, row in ipairs(list) do
    row.name = try(C_Item.GetItemNameByID, row.itemID)
    if not row.name then
      try(C_Item.RequestLoadItemDataByID, row.itemID)
      waitingForNames = true
    end
  end
  return list, count
end

local function row(i)
  if rows[i] then return rows[i] end
  local r = CreateFrame("Frame", nil, frame)
  r.Dash = r:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
  r.Dash:SetPoint("TOPLEFT", 0, 1)
  r.Dash:SetText(QUEST_DASH)
  r.Text = r:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
  r.Text:SetPoint("TOP")
  r.Text:SetPoint("LEFT", r.Dash, "RIGHT")
  r.Text:SetPoint("RIGHT")
  r.Icon = r:CreateTexture(nil, "ARTWORK")
  r.Icon:SetAtlas("ui-questtracker-tracker-check", false)
  r.Icon:SetSize(16, 16)
  r.Icon:SetPoint("TOPLEFT", -10, 2)
  rows[i] = r
  return r
end

local function update()
  local m = ProfessionsRecipeTracker
  frame:Hide()
  if ns.locked() or not m:IsShown() or m:IsCollapsed() or not m.lastBlock
    or m.state ~= ObjectiveTrackerModuleState.ShownFully then return end
  waitingForNames = false
  local list, count = totals()
  if count < 2 or #list == 0 then return end

  frame:ClearAllPoints()
  frame:SetPoint("TOP", m.lastBlock, "BOTTOM", 0, -BLOCK_GAP)
  frame:SetPoint("LEFT", m.ContentsFrame, "LEFT", INDENT, 0)
  frame:SetPoint("RIGHT", m.ContentsFrame, "RIGHT")

  local height = setText(frame.Header, "All tracked recipes", OBJECTIVE_TRACKER_COLOR.Header)
  local anchor = frame.Header
  for i, item in ipairs(list) do
    local r = row(i)
    local met = item.have >= item.need
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -LINE_SPACING)
    r:SetPoint("RIGHT")
    r.Dash:SetShown(not met)
    r.Icon:SetShown(met)
    local text = PROFESSIONS_TRACKER_REAGENT_FORMAT:format(
      PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT:format(item.have, item.need), item.name or "…")
    local h = setText(r.Text, text, OBJECTIVE_TRACKER_COLOR[met and "Complete" or "Normal"])
    r:SetHeight(h)
    r:Show()
    height = height + h + LINE_SPACING
    anchor = r
  end
  for i = #list + 1, #rows do rows[i]:Hide() end
  frame:SetHeight(height)
  frame:Show()
end

local function setup()
  local m = ProfessionsRecipeTracker
  if frame or not (m and m.EndLayout and C_TradeSkillUI and C_TradeSkillUI.GetRecipesTracked) then return end
  frame = CreateFrame("Frame", nil, m.ContentsFrame)
  frame:Hide()
  frame.Header = frame:CreateFontString(nil, "ARTWORK", "ObjectiveTrackerLineFont")
  frame.Header:SetPoint("TOPLEFT")
  frame.Header:SetPoint("RIGHT")
  hooksecurefunc(m, "EndLayout", function() try(update) end)
  -- An item name that wasn't cached yet shows as "…" until the client has it.
  frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  frame:SetScript("OnEvent", function() if waitingForNames then try(update) end end)
end

if C_AddOns.IsAddOnLoaded("Blizzard_ObjectiveTracker") then
  setup()
else
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function(_, _, name)
    if name == "Blizzard_ObjectiveTracker" then f:UnregisterAllEvents(); setup() end
  end)
end
