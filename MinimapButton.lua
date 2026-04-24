local ADDON_NAME, ns = ...

-- ============================================================
-- Minimap Button
-- ============================================================
local DEFAULT_ANGLE = math.pi * 0.25  -- top-right area

local btn = CreateFrame("Button", "GuildBankRestockMinimapButton", Minimap)
btn:SetFrameLevel(8)
btn:SetSize(31, 31)

local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER")
icon:SetTexture(413587)  -- GUILDPERK_MOBILEBANKING

local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)

local hilite = btn:CreateTexture(nil, "HIGHLIGHT")
hilite:SetAllPoints()
hilite:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
hilite:SetBlendMode("ADD")

local function GetAngle()
    return (ns.addon and ns.addon.db and ns.addon.db.global.minimapAngle) or DEFAULT_ANGLE
end

local function SaveAngle(a)
    if ns.addon and ns.addon.db then
        ns.addon.db.global.minimapAngle = a
    end
end

local function UpdatePos(a)
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
end

btn:RegisterForDrag("LeftButton")
btn:RegisterForClicks("LeftButtonUp")

btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
        local cx, cy = Minimap:GetCenter()
        local scale  = UIParent:GetEffectiveScale()
        local mx, my = GetCursorPosition()
        local a = math.atan2(my / scale - cy, mx / scale - cx)
        UpdatePos(a)
        SaveAngle(a)
    end)
end)

btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

btn:SetScript("OnClick", function()
    if ns.frame and ns.frame:IsShown() then
        ns.frame:Hide()
    elseif ns.frame then
        ns.frame:Show()
        ns.UpdateUI()
    end
end)

btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Guild Bank Restock")
    GameTooltip:AddLine("Click to open / close.", 1, 1, 1)
    GameTooltip:AddLine("Drag to move.", 1, 1, 1)
    GameTooltip:Show()
end)

btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

ns.InitMinimapButton = function()
    UpdatePos(GetAngle())
    btn:Show()
end
