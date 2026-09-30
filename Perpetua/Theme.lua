-- The site's look in game: gold linework on deep royal navy, Cinzel for headings and buttons, Cormorant
-- Garamond for text (both SIL Open Font License, in Media/Fonts), the crest and the corner brackets from
-- perpetua.css. Everything is drawn with plain textures, so it doesn't depend on Blizzard's frame art.
local _, ns = ...
local T = {}
ns.T = T

local MEDIA = "Interface\\AddOns\\Perpetua\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
T.CREST = MEDIA .. "crest"

-- perpetua.css :root
local C = {
  gold = { 0.831, 0.686, 0.216 }, pale = { 0.949, 0.843, 0.549 }, warm = { 0.910, 0.784, 0.455 },
  navy = { 0.055, 0.102, 0.251 }, midnight = { 0.047, 0.090, 0.188 }, royal = { 0.082, 0.165, 0.369 },
  text = { 0.937, 0.902, 0.784 }, muted = { 0.639, 0.675, 0.788 },
}
T.C = C
T.HEX = { gold = "d4af37", pale = "f2d78c", warm = "e8c874", text = "efe6c8", muted = "a3acc9", ok = "8fd18a", danger = "ff8a7a" }

local function font(name, file, size, color, fallback)
  local f = CreateFont(name)
  if f:SetFont(MEDIA .. "Fonts\\" .. file, size, "") == false and fallback then f:CopyFontObject(fallback) end
  f:SetTextColor(color[1], color[2], color[3])
  f:SetShadowColor(0, 0, 0, 0.85)
  f:SetShadowOffset(1, -1)
  return f
end

T.fonts = {
  title   = font("PerpetuaFontTitle", "Cinzel-Bold.ttf", 24, C.gold, GameFontNormalLarge),
  heading = font("PerpetuaFontHeading", "Cinzel-Bold.ttf", 12, C.gold, GameFontNormal),
  label   = font("PerpetuaFontLabel", "Cinzel-SemiBold.ttf", 10, C.gold, GameFontNormalSmall),
  button  = font("PerpetuaFontButton", "Cinzel-Bold.ttf", 11, C.gold, GameFontNormal),
  name    = font("PerpetuaFontName", "Cinzel-Bold.ttf", 22, C.text, GameFontNormalLarge),
  body    = font("PerpetuaFontBody", "CormorantGaramond-SemiBold.ttf", 16, C.text, GameFontHighlight),
  small   = font("PerpetuaFontSmall", "CormorantGaramond-SemiBold.ttf", 15, C.text, GameFontHighlightSmall),
  muted   = font("PerpetuaFontMuted", "CormorantGaramond-SemiBoldItalic.ttf", 14, C.muted, GameFontDisableSmall),
  tagline = font("PerpetuaFontTagline", "CormorantGaramond-SemiBoldItalic.ttf", 14, C.warm, GameFontNormalSmall),
  close   = font("PerpetuaFontClose", "CormorantGaramond-Bold.ttf", 28, C.warm, GameFontNormalLarge),
  brand   = font("PerpetuaFontBrand", "Cinzel-Bold.ttf", 17, C.gold, GameFontNormalLarge),
  page    = font("PerpetuaFontPage", "Cinzel-Bold.ttf", 21, C.gold, GameFontNormalLarge),
  nav     = font("PerpetuaFontNav", "Cinzel-SemiBold.ttf", 11, C.text, GameFontNormal),
}

function T.hex(key, s) return "|cff" .. (T.HEX[key] or key) .. s .. "|r" end

function T.text(parent, fontKey, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFontObject(T.fonts[fontKey or "body"])
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  return fs
end

function T.fill(frame, layer, color, alpha)
  local t = frame:CreateTexture(nil, layer or "BACKGROUND")
  t:SetTexture(WHITE)
  t:SetVertexColor(color[1], color[2], color[3], alpha or 1)
  return t
end

-- A 1px rectangle `inset` pixels inside frame. Returns an object with SetAlpha / SetColor for all four sides.
function T.outline(frame, inset, color, alpha, layer)
  inset = inset or 0
  local sides = {}
  for i = 1, 4 do sides[i] = T.fill(frame, layer or "BORDER", color or C.gold, alpha) end
  local top, bottom, left, right = sides[1], sides[2], sides[3], sides[4]
  top:SetPoint("TOPLEFT", inset, -inset); top:SetPoint("TOPRIGHT", -inset, -inset); top:SetHeight(1)
  bottom:SetPoint("BOTTOMLEFT", inset, inset); bottom:SetPoint("BOTTOMRIGHT", -inset, inset); bottom:SetHeight(1)
  left:SetPoint("TOPLEFT", inset, -inset); left:SetPoint("BOTTOMLEFT", inset, inset); left:SetWidth(1)
  right:SetPoint("TOPRIGHT", -inset, -inset); right:SetPoint("BOTTOMRIGHT", -inset, inset); right:SetWidth(1)
  return {
    SetAlpha = function(_, a) for _, s in ipairs(sides) do s:SetAlpha(a) end end,
    SetColor = function(_, c, a) for _, s in ipairs(sides) do s:SetVertexColor(c[1], c[2], c[3], a or 1) end end,
  }
end

-- The modern frame: navy gradient, one thin gold border, a gold accent line fading in and out along the top.
function T.window(frame)
  local bg = T.fill(frame, "BACKGROUND", C.midnight, 0.97)
  bg:SetAllPoints()
  pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(C.midnight[1], C.midnight[2], C.midnight[3], 0.98),
    CreateColor(C.royal[1], C.royal[2], C.royal[3], 0.96))
  T.outline(frame, 0, C.gold, 0.45)
  local l, r = T.fill(frame, "ARTWORK", C.gold, 1), T.fill(frame, "ARTWORK", C.gold, 1)
  l:SetHeight(2); r:SetHeight(2)
  l:SetPoint("TOPLEFT", 1, -1); l:SetPoint("TOPRIGHT", frame, "TOP", 0, -1)
  r:SetPoint("TOPRIGHT", -1, -1); r:SetPoint("TOPLEFT", frame, "TOP", 0, -1)
  pcall(l.SetGradient, l, "HORIZONTAL", CreateColor(C.gold[1], C.gold[2], C.gold[3], 0), CreateColor(C.gold[1], C.gold[2], C.gold[3], 0.9))
  pcall(r.SetGradient, r, "HORIZONTAL", CreateColor(C.gold[1], C.gold[2], C.gold[3], 0.9), CreateColor(C.gold[1], C.gold[2], C.gold[3], 0))
end

-- A game icon cropped of its baked-in border, with a thin gold edge. Returns the texture.
function T.icon(parent, path, size)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(size, size)
  local tex = holder:CreateTexture(nil, "ARTWORK")
  tex:SetPoint("TOPLEFT", 1, -1); tex:SetPoint("BOTTOMRIGHT", -1, 1)
  tex:SetTexture(path)
  tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  holder.edge = T.outline(holder, 0, C.gold, 0.35, "OVERLAY")
  holder.tex = tex
  return holder
end

-- Sidebar entry: icon and label; hover glows, the selected one gets a gold bar and a brighter label.
function T.navButton(parent, label, iconPath, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(38)
  b.fill = T.fill(b, "BACKGROUND", C.gold, 0)
  b.fill:SetAllPoints()
  b.bar = T.fill(b, "ARTWORK", C.gold, 1)
  b.bar:SetPoint("TOPLEFT"); b.bar:SetPoint("BOTTOMLEFT"); b.bar:SetWidth(3)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(); hl:SetTexture(WHITE); hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.07)
  b.icon = T.icon(b, iconPath, 22)
  b.icon:SetPoint("LEFT", 18, 0)
  b.label = T.text(b, "nav")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 12, 0)
  b.label:SetText(label:upper())
  function b:SetSelected(on)
    self.fill:SetAlpha(on and 0.13 or 0)
    self.bar:SetShown(on)
    local c = on and C.pale or C.text
    self.label:SetTextColor(c[1], c[2], c[3], on and 1 or 0.78)
    self.icon.tex:SetDesaturated(not on)
    self.icon.tex:SetAlpha(on and 1 or 0.7)
    self.icon.edge:SetAlpha(on and 0.9 or 0.3)
  end
  b:SetSelected(false)
  b:SetScript("OnClick", onClick)
  return b
end

-- Icons inside text: a class crest or an item's icon, as a |T...|t escape.
function T.classIcon(classFile, size)
  local c = CLASS_ICON_TCOORDS and classFile and CLASS_ICON_TCOORDS[classFile]
  if not c then return "" end
  size = size or 16
  return string.format("|TInterface\\WorldStateFrame\\ICONS-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t ", size, size,
    c[1] * 256 + 4, c[2] * 256 - 4, c[3] * 256 + 4, c[4] * 256 - 4)
end

function T.itemIcon(itemID, size)
  local icon = itemID and (ns.try(C_Item and C_Item.GetItemIconByID, itemID) or ns.try(GetItemIcon, itemID))
  if not icon then return "" end
  size = size or 16
  return string.format("|T%s:%d:%d:0:0:64:64:5:59:5:59|t ", tostring(icon), size, size)
end

-- The site's .card: navy gradient, gold line, a fainter line inside, and the four corner brackets.
function T.card(frame)
  local bg = T.fill(frame, "BACKGROUND", C.midnight, 0.97)
  bg:SetAllPoints()
  pcall(bg.SetGradient, bg, "VERTICAL", CreateColor(C.midnight[1], C.midnight[2], C.midnight[3], 0.98),
    CreateColor(C.royal[1], C.royal[2], C.royal[3], 0.97))
  T.outline(frame, 0, C.gold, 1)
  T.outline(frame, 5, C.gold, 0.22)
  T.outline(frame, 10, C.gold, 0.38)
  local coords = { TOPLEFT = { 0, 1, 0, 1 }, TOPRIGHT = { 1, 0, 0, 1 }, BOTTOMLEFT = { 0, 1, 1, 0 }, BOTTOMRIGHT = { 1, 0, 1, 0 } }
  local offsets = { TOPLEFT = { -7, 7 }, TOPRIGHT = { 7, 7 }, BOTTOMLEFT = { -7, -7 }, BOTTOMRIGHT = { 7, -7 } }
  for point, tc in pairs(coords) do
    local t = frame:CreateTexture(nil, "OVERLAY")
    t:SetTexture(MEDIA .. "bracket")
    t:SetSize(42, 42)
    t:SetTexCoord(tc[1], tc[2], tc[3], tc[4])
    t:SetPoint(point, offsets[point][1], offsets[point][2])
  end
end

-- The gold rule with a diamond in the middle (.rule on the site).
function T.rule(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetHeight(10)
  local left, right = T.fill(f, "ARTWORK", C.gold, 0.6), T.fill(f, "ARTWORK", C.gold, 0.6)
  left:SetHeight(1); right:SetHeight(1)
  left:SetPoint("LEFT"); left:SetPoint("RIGHT", f, "CENTER", -9, 0)
  right:SetPoint("RIGHT"); right:SetPoint("LEFT", f, "CENTER", 9, 0)
  local diamond = T.fill(f, "ARTWORK", C.gold, 1)
  diamond:SetSize(7, 7)
  diamond:SetPoint("CENTER")
  pcall(diamond.SetRotation, diamond, math.rad(45))
  return f
end

-- Buttons like the site's .cta: "solid" (gold, navy text) or "tab" (gold outline, solid when selected).
function T.button(parent, label, width, onClick, kind)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(width or 120, 26)
  b.bg = T.fill(b, "BACKGROUND", C.gold, 1)
  b.bg:SetAllPoints()
  b.edge = T.outline(b, 0, C.pale, 1)
  b.label = T.text(b, "button", "CENTER")
  b.label:SetPoint("CENTER", 0, 0)
  b.label:SetText(label:upper())
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(WHITE)
  hl:SetVertexColor(C.gold[1], C.gold[2], C.gold[3], 0.18)
  function b:SetSelected(on)
    local solid = kind ~= "tab" or on
    self.bg:SetAlpha(solid and 1 or 0)
    self.edge:SetColor(solid and C.pale or C.gold, solid and 1 or 0.55)
    local c = solid and C.navy or C.gold
    self.label:SetTextColor(c[1], c[2], c[3])
    self.label:SetShadowColor(0, 0, 0, solid and 0 or 0.85)
  end
  b:SetSelected(false)
  b:SetScript("OnClick", onClick)
  return b
end

-- Search box: midnight field with a gold hairline, placeholder text while empty.
function T.searchBox(parent, width, placeholder, onChange)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(width, 26)
  e:SetAutoFocus(false)
  e:SetFontObject(T.fonts.small)
  e:SetTextInsets(10, 10, 0, 0)
  local bg = T.fill(e, "BACKGROUND", C.midnight, 1)
  bg:SetAllPoints()
  local edge = T.outline(e, 0, C.gold, 0.4)
  local hint = T.text(e, "muted")
  hint:SetPoint("LEFT", 10, 0)
  hint:SetText(placeholder or "")
  local function sync() hint:SetShown((e:GetText() or "") == "" and not e:HasFocus()) end
  e:SetScript("OnTextChanged", function(self) sync(); onChange(self:GetText() or "") end)
  e:SetScript("OnEditFocusGained", function() edge:SetAlpha(1); sync() end)
  e:SetScript("OnEditFocusLost", function() edge:SetAlpha(0.4); sync() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

function T.closeButton(parent, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(28, 28)
  local x = T.text(b, "close", "CENTER")
  x:SetPoint("CENTER", 0, 1)
  x:SetText("×")
  b:SetScript("OnEnter", function() x:SetTextColor(C.pale[1], C.pale[2], C.pale[3]) end)
  b:SetScript("OnLeave", function() x:SetTextColor(C.warm[1], C.warm[2], C.warm[3]) end)
  b:SetScript("OnClick", onClick)
  return b
end

-- A plain panel (.panel): faint navy fill and a gold hairline.
function T.panel(frame)
  local bg = T.fill(frame, "BACKGROUND", C.midnight, 0.55)
  bg:SetAllPoints()
  T.outline(frame, 0, C.gold, 0.32)
end

-- Addons can't open a browser, so a web address is shown in a box, selected, ready for Ctrl+C.
local copyBox
function T.copyBox(title, url)
  if not copyBox then
    local f = CreateFrame("Frame", "PerpetuaCopyBox", UIParent)
    f:SetSize(520, 150)
    f:SetPoint("CENTER", 0, 120)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    T.window(f)
    tinsert(UISpecialFrames, "PerpetuaCopyBox")
    f.title = T.text(f, "heading")
    f.title:SetPoint("TOPLEFT", 22, -20)
    f.title:SetPoint("RIGHT", -50, 0)
    local close = T.closeButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -12, -12)
    local field = CreateFrame("EditBox", nil, f)
    field:SetPoint("TOPLEFT", 22, -52)
    field:SetPoint("RIGHT", -22, 0)
    field:SetHeight(30)
    field:SetAutoFocus(false)
    field:SetFontObject(ChatFontNormal)
    field:SetTextColor(C.pale[1], C.pale[2], C.pale[3])
    field:SetTextInsets(10, 10, 0, 0)
    local bg = T.fill(field, "BACKGROUND", C.midnight, 1)
    bg:SetAllPoints()
    T.outline(field, 0, C.gold, 0.6)
    -- Read-only: typing puts the address back, selected.
    field:SetScript("OnTextChanged", function(self, userInput) if userInput then self:SetText(f.url); self:HighlightText() end end)
    field:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    field:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    field:SetScript("OnEscapePressed", function() f:Hide() end)
    field:SetScript("OnEnterPressed", function() f:Hide() end)
    -- Close once it's been copied.
    field:SetScript("OnKeyUp", function(_, key) if key == "C" and IsControlKeyDown() then C_Timer.After(0.1, function() f:Hide() end) end end)
    f.field = field
    f.hint = T.text(f, "muted")
    f.hint:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -10)
    f.hint:SetText("Press Ctrl+C to copy, then paste it into your browser.")
    copyBox = f
  end
  copyBox.url = url
  copyBox.title:SetText((title or "Open on the site"):upper())
  copyBox.field:SetText(url)
  copyBox:Show()
  copyBox.field:SetFocus()
  copyBox.field:HighlightText()
end
