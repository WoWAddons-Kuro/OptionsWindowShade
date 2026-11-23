-- OptionsWindowShade: two subtle title-bar buttons on Blizzard's Options window (SettingsPanel).
--   Shade  -> the panel stays SHOWN but is anchored below the screen; a title-bar strip appears where
--             the real title bar was. (Never Hide(): SettingsPanel:OnHide() flushes search text and
--             unapplied settings.)
--   Lock   -> unlocked = drag the title bar to move. SetUserPlaced(false) after every drag so the
--             client never remembers the position.
-- Everything resets in SettingsPanel's OnHide hook, so the window always reopens centered and locked.
-- No SavedVariables. Nothing protected is touched; works in combat.
local ADDON, NS = ...
local L = NS.L

local PANEL_TITLEBAR_HEIGHT = 26   -- band at the top of SettingsPanel that acts as the drag handle
local STRIP_HEIGHT = 44            -- SettingsFrameTemplate: title tile + enough body for the nine-slice bottom edge to close cleanly
local BUTTON_SIZE = 18
local ALPHA_REST, ALPHA_HOVER = 0.55, 1.0

-- All runtime state. Nothing is ever written onto SettingsPanel itself.
local OWS_State = {
  built = false,
  shaded = false,
  unlocked = false,
  savedPoints = nil,      -- { {point, relTo, relPoint, x, y}, ... } captured at shade time
  applyingOurAnchor = false,
  panelButtons = {},      -- shade/lock buttons on the real title bar
  stripButtons = {},      -- shade/lock buttons on the strip
  strip = nil,
  dragHandle = nil,
}
NS.State = OWS_State

local function PanelIsOpen()
  return SettingsPanel and SettingsPanel:IsShown()
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff9ecbffOptionsWindowShade|r: " .. msg)
end

local function BindingLine(bindingName)
  local key = GetBindingKey(bindingName)
  if key then return L["Keybind: %s"]:format(GetBindingText(key)) end
  return L["Keybind: none"]
end

-------------------------------------------------------------------------------
-- Icon buttons
-------------------------------------------------------------------------------

-- kind = "shade" | "lock". Textures are desaturated and dim at rest; brighten on hover.
-- If a texture path is missing on some flavour, SetTexture returns false and a glyph shows instead.
local ICONS = {
  shade = { on = "Interface\\Buttons\\UI-Panel-ExpandButton-Up",  off = "Interface\\Buttons\\UI-Panel-CollapseButton-Up", glyphOn = "+", glyphOff = "-" },
  lock  = { on = "Interface\\Buttons\\LockButton-Unlocked-Up",    off = "Interface\\Buttons\\LockButton-Locked-Up",      glyphOn = "U", glyphOff = "L" },
}

local function SetIconState(button, active)
  local def = ICONS[button.owsKind]
  local path = active and def.on or def.off
  local ok = button.Icon:SetTexture(path)
  if ok then
    button.Icon:Show(); button.Glyph:Hide()
  else
    button.Icon:Hide(); button.Glyph:Show()
    button.Glyph:SetText(active and def.glyphOn or def.glyphOff)
  end
end

local function ShowButtonTooltip(button)
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  if button.owsKind == "shade" then
    GameTooltip:SetText(OWS_State.shaded and L["Unshade window"] or L["Shade window"])
    GameTooltip:AddLine(BindingLine("OPTIONSWINDOWSHADE_TOGGLE_SHADE"), 0.7, 0.7, 0.7)
  else
    GameTooltip:SetText(OWS_State.unlocked and L["Lock window"] or L["Unlock window"])
    if not OWS_State.unlocked then GameTooltip:AddLine(L["Drag the title bar to move it."], 1, 1, 1) end
    GameTooltip:AddLine(BindingLine("OPTIONSWINDOWSHADE_TOGGLE_LOCK"), 0.7, 0.7, 0.7)
  end
  GameTooltip:Show()
end

local function CreateIconButton(parent, kind, onClick)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  b.owsKind = kind
  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetAllPoints()
  b.Icon:SetDesaturated(true)
  b.Glyph = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  b.Glyph:SetPoint("CENTER")
  b.Glyph:SetTextColor(0.8, 0.8, 0.8)
  b.Glyph:Hide()
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetAlpha(ALPHA_REST)
  b:SetScript("OnEnter", function(self) self:SetAlpha(ALPHA_HOVER); ShowButtonTooltip(self) end)
  b:SetScript("OnLeave", function(self) self:SetAlpha(ALPHA_REST); GameTooltip:Hide() end)
  b:SetScript("OnClick", function(self) onClick(); if self:IsMouseOver() then ShowButtonTooltip(self) end end)
  return b
end

local function RefreshIcons()
  for _, set in ipairs({ OWS_State.panelButtons, OWS_State.stripButtons }) do
    if set.shade then SetIconState(set.shade, OWS_State.shaded) end
    if set.lock then SetIconState(set.lock, OWS_State.unlocked) end
  end
end

-------------------------------------------------------------------------------
-- Lock / move
-------------------------------------------------------------------------------

local function SetUnlocked(unlocked)
  OWS_State.unlocked = unlocked
  if OWS_State.dragHandle then OWS_State.dragHandle:EnableMouse(unlocked) end
  RefreshIcons()
end

local function CapturePanelPoints()
  local pts = {}
  for i = 1, SettingsPanel:GetNumPoints() do pts[i] = { SettingsPanel:GetPoint(i) } end
  return pts
end

local function RestorePanelPoints(pts)
  OWS_State.applyingOurAnchor = true
  SettingsPanel:ClearAllPoints()
  if pts and #pts > 0 then
    for _, p in ipairs(pts) do SettingsPanel:SetPoint(unpack(p, 1, 5)) end
  else
    SettingsPanel:SetPoint("CENTER")
  end
  OWS_State.applyingOurAnchor = false
end

function NS.ToggleLock()
  if not PanelIsOpen() then return false end
  if OWS_State.unlocked then
    -- Locking snaps the window back to where it was when it was unlocked: a moved position
    -- is never kept, so there is no point leaving it somewhere it will not stay.
    if not OWS_State.shaded then RestorePanelPoints(OWS_State.lockedPoints) end
    OWS_State.lockedPoints = nil
    SetUnlocked(false)
  else
    OWS_State.lockedPoints = CapturePanelPoints()
    SetUnlocked(true)
  end
  return true
end

local function CreateDragHandle()
  local h = CreateFrame("Frame", nil, SettingsPanel)
  h:SetPoint("TOPLEFT", SettingsPanel, "TOPLEFT", 0, 0)
  h:SetPoint("RIGHT", OWS_State.panelButtons.lock, "LEFT", -2, 0)
  h:SetHeight(PANEL_TITLEBAR_HEIGHT)
  h:SetFrameLevel(SettingsPanel:GetFrameLevel() + 5)
  h:EnableMouse(false)
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function() if OWS_State.unlocked and not OWS_State.shaded then SettingsPanel:StartMoving() end end)
  h:SetScript("OnDragStop", function()
    SettingsPanel:StopMovingOrSizing()
    SettingsPanel:SetUserPlaced(false)   -- the client must never remember this position
  end)
  return h
end

-------------------------------------------------------------------------------
-- Shade
-------------------------------------------------------------------------------

local function ApplyOffscreenAnchor()
  OWS_State.applyingOurAnchor = true
  SettingsPanel:ClearAllPoints()
  SettingsPanel:SetPoint("TOP", UIParent, "BOTTOM", 0, -200)
  OWS_State.applyingOurAnchor = false
end

local function CreateStrip()
  -- Inherit the panel's own chrome template (Bg + NineSlice/title tile + Text + ClosePanelButton),
  -- so the strip is pixel-identical to the real title bar on every flavour; it is just short.
  local s = CreateFrame("Frame", "OptionsWindowShade_Strip", UIParent, "SettingsFrameTemplate")
  s:SetFrameStrata("HIGH")
  s:SetHeight(STRIP_HEIGHT)
  s:EnableMouse(true)   -- swallow clicks so the world behind the strip is not hit
  s:Hide()

  s.Title = s.NineSlice and s.NineSlice.Text
  if not s.Title then
    s.Title = s:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    s.Title:SetPoint("TOP", 0, -5)
  end

  -- Same X as the real title bar; routes through SettingsPanel:Close() so discard-confirm works.
  s.Close = s.ClosePanelButton
  if not s.Close then
    s.Close = CreateFrame("Button", nil, s, "UIPanelCloseButton")
    s.Close:SetPoint("TOPRIGHT", s, "TOPRIGHT", 2, 1)
  end
  s.Close:SetScript("OnClick", function() if SettingsPanel then SettingsPanel:Close() end end)

  OWS_State.stripButtons.shade = CreateIconButton(s, "shade", function() NS.ToggleShade() end)
  OWS_State.stripButtons.shade:SetPoint("RIGHT", s.Close, "LEFT", -4, 0)
  OWS_State.stripButtons.lock = CreateIconButton(s, "lock", function() NS.ToggleLock() end)
  OWS_State.stripButtons.lock:SetPoint("RIGHT", OWS_State.stripButtons.shade, "LEFT", -2, 0)

  -- The strip is always draggable (there is nothing to protect while shaded). Where it is dropped
  -- becomes where the window unshades to: the panel's TOPLEFT is re-anchored under the strip.
  s:SetMovable(true)
  s:SetClampedToScreen(true)
  local h = CreateFrame("Frame", nil, s)
  h:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
  h:SetPoint("RIGHT", OWS_State.stripButtons.lock, "LEFT", -2, 0)
  h:SetHeight(PANEL_TITLEBAR_HEIGHT)
  h:EnableMouse(true)
  h:RegisterForDrag("LeftButton")
  h:SetScript("OnDragStart", function() s:StartMoving() end)
  h:SetScript("OnDragStop", function()
    s:StopMovingOrSizing()
    s:SetUserPlaced(false)
    -- The strip has the panel's scale, so its TOPLEFT in UIParent space is the panel's TOPLEFT.
    local left, top = s:GetLeft(), s:GetTop()
    if left and top then
      OWS_State.savedPoints = { { "TOPLEFT", UIParent, "BOTTOMLEFT", left, top } }
    end
  end)
  s.DragHandle = h
  return s
end

local function Shade()
  if OWS_State.shaded then return end
  local panel = SettingsPanel
  local left, top, width = panel:GetLeft(), panel:GetTop(), panel:GetWidth()
  local scale = panel:GetScale()

  OWS_State.savedPoints = CapturePanelPoints()

  OWS_State.shaded = true
  ApplyOffscreenAnchor()

  local s = OWS_State.strip
  s:SetScale(scale)
  s:SetWidth(width)
  s:ClearAllPoints()
  -- GetLeft/GetTop are in the panel's scaled coordinates; convert to the strip's own scale
  -- (identical by construction) relative to UIParent's bottom-left.
  s:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  s.Title:SetText(panel.NineSlice and panel.NineSlice.Text and panel.NineSlice.Text:GetText() or SETTINGS_TITLE or "Options")
  s:SetFrameLevel(panel:GetFrameLevel() + 10)
  s:Show()
  RefreshIcons()
end

local function Unshade()
  if not OWS_State.shaded then return end
  OWS_State.shaded = false
  OWS_State.strip:Hide()
  RestorePanelPoints(OWS_State.savedPoints)
  OWS_State.savedPoints = nil
  RefreshIcons()
end

function NS.ToggleShade()
  if not PanelIsOpen() then return false end
  if OWS_State.shaded then Unshade() else Shade() end
  return true
end

-- UIParent's panel manager may re-anchor SettingsPanel while another panel opens/closes.
-- If that happens while shaded, put it back below the screen so the strip stays truthful.
local function OnPanelSetPoint()
  if OWS_State.shaded and not OWS_State.applyingOurAnchor then
    C_Timer.After(0, function() if OWS_State.shaded then ApplyOffscreenAnchor() end end)
  end
end

-------------------------------------------------------------------------------
-- Reset + build
-------------------------------------------------------------------------------

local function ResetAll()
  Unshade()
  OWS_State.lockedPoints = nil
  SetUnlocked(false)
  if SettingsPanel then SettingsPanel:SetUserPlaced(false) end
end

local function Build()
  if OWS_State.built or not SettingsPanel then return end
  OWS_State.built = true
  local panel = SettingsPanel
  local anchorTo = panel.ClosePanelButton or panel

  OWS_State.panelButtons.shade = CreateIconButton(panel, "shade", function() NS.ToggleShade() end)
  OWS_State.panelButtons.lock = CreateIconButton(panel, "lock", function() NS.ToggleLock() end)
  if panel.ClosePanelButton then
    OWS_State.panelButtons.shade:SetPoint("RIGHT", anchorTo, "LEFT", -4, 0)
  else
    OWS_State.panelButtons.shade:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -30, -4)
  end
  OWS_State.panelButtons.lock:SetPoint("RIGHT", OWS_State.panelButtons.shade, "LEFT", -2, 0)
  for _, b in pairs(OWS_State.panelButtons) do b:SetFrameLevel(panel:GetFrameLevel() + 6) end

  OWS_State.dragHandle = CreateDragHandle()
  OWS_State.strip = CreateStrip()

  panel:HookScript("OnHide", ResetAll)
  hooksecurefunc(panel, "SetPoint", OnPanelSetPoint)
  RefreshIcons()
end

-------------------------------------------------------------------------------
-- Keybinding globals (Bindings.xml) and slash command
-------------------------------------------------------------------------------

function OptionsWindowShade_ToggleShade() NS.ToggleShade() end
function OptionsWindowShade_ToggleLock() NS.ToggleLock() end

local function Version()
  local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
  return get and get(ADDON, "Version") or "dev"
end

SLASH_OPTIONSWINDOWSHADE1 = "/optionswindowshade"
SLASH_OPTIONSWINDOWSHADE2 = "/ows"
SlashCmdList.OPTIONSWINDOWSHADE = function(msg)
  msg = (msg or ""):lower():match("^%s*(%S*)")
  if msg == "shade" then
    if not NS.ToggleShade() then Print(L["Open the Options window first."]) end
  elseif msg == "lock" then
    if not NS.ToggleLock() then Print(L["Open the Options window first."]) end
  else
    Print(Version() .. " - " .. L["Usage: /ows shade | lock | help"])
    Print("shade: " .. BindingLine("OPTIONSWINDOWSHADE_TOGGLE_SHADE") .. "  |  lock: " .. BindingLine("OPTIONSWINDOWSHADE_TOGGLE_LOCK"))
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function()
  Build()
  -- Belt and braces: if Blizzard_Settings_Shared were ever load-on-demand, build when it shows up.
  if not OWS_State.built then
    ev:RegisterEvent("ADDON_LOADED")
    ev:SetScript("OnEvent", function(_, _, name) if SettingsPanel then Build(); ev:UnregisterEvent("ADDON_LOADED") end end)
  end
end)