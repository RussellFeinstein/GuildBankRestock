local ADDON_NAME, ns = ...
local AceGUI = LibStub("AceGUI-3.0")
local CATEGORIES = ns.CATEGORIES

-- ============================================================
-- Shared UI state (Sidebar.lua and Tabs.lua read/write via ns.ui)
-- ============================================================
ns.ui = {
    LOG_TAB             = #CATEGORIES + 1,
    ABOUT_TAB           = #CATEGORIES + 2,
    ALL_TAB             = #CATEGORIES + 3,
    version             = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "?",
    currentCatIdx       = 1,
    currentRankFilter   = nil,
    showAllProfileItems = false,
    sidebarButtons      = {},
    mainFrame           = nil,  -- set below
    sidebarPanel        = nil,  -- set in Sidebar.lua
    contentGroup        = nil,  -- set in Tabs.lua
}
local ui = ns.ui

-- ============================================================
-- Static popup: new profile
-- ============================================================
StaticPopupDialogs["GUILDBANKRESTOCK_NEW_PROFILE"] = {
    text = "Enter a name for the new profile:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local name = self.EditBox:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then ns.CreateProfile(name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local name = self:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then ns.CreateProfile(name) end
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================
-- Static popup: save-as profile
-- ============================================================
StaticPopupDialogs["GUILDBANKRESTOCK_SAVE_PROFILE"] = {
    text = "Save profile as:",
    button1 = "Save",
    button2 = "Cancel",
    hasEditBox = true,
    OnShow = function(self)
        self.EditBox:SetText(ns.currentProfile or "")
        self.EditBox:HighlightText()
    end,
    OnAccept = function(self)
        local name = self.EditBox:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then ns.SaveProfileAs(name) end
    end,
    EditBoxOnEnterPressed = function(self)
        local name = self:GetText():match("^%s*(.-)%s*$")
        if name ~= "" then ns.SaveProfileAs(name) end
        self:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================
-- Frame-local state
-- ============================================================
local mainFrame            -- assigned below; also exposed as ui.mainFrame
local statusBar
local suppressStopMessage = false

local function SetStatusText(text)
    if statusBar then statusBar:SetText(text or "") end
end

-- ============================================================
-- Show the tab view  (IDLE state)
-- ============================================================
local ShowTabView = function()
    ui.sidebarPanel:Show()
    ns.SelectTab(ui.currentCatIdx)
end

-- ============================================================
-- Show the status view  (SEARCHING / READY / CONFIRMING)
-- ============================================================
local ShowStatusView = function(statusMsg, btnText, btnEnabled, btnHandler)
    ns.ReleaseCategoryScroll()
    ns.DetachLogFrame()
    ui.sidebarPanel:Hide()
    ui.contentGroup:ReleaseChildren()

    local container = AceGUI:Create("SimpleGroup")
    container:SetLayout("List")
    container:SetFullWidth(true)
    container:SetFullHeight(true)

    local label = AceGUI:Create("Label")
    label:SetFullWidth(true)
    label:SetText("\n\n" .. statusMsg)
    label:SetFontObject(GameFontNormalLarge)
    container:AddChild(label)

    local btn = AceGUI:Create("Button")
    btn:SetText(btnText)
    btn:SetRelativeWidth(0.7)
    btn:SetDisabled(not btnEnabled)
    if btnHandler then
        btn:SetCallback("OnClick", btnHandler)
    end
    container:AddChild(btn)

    ui.contentGroup:AddChild(container)
end

-- ============================================================
-- UpdateUI  (state machine)
-- ============================================================
local UpdateUI
UpdateUI = function()
    if not mainFrame then return end

    if ns.state == ns.STATE.IDLE then
        SetStatusText("Select items and quantities, then click Start.")
        ShowTabView()

    elseif ns.state == ns.STATE.SEARCHING then
        SetStatusText("Searching...")
        ShowStatusView("Searching...", "Searching...", false)

    elseif ns.state == ns.STATE.READY then
        local listPos, ref = ns.GetNextItem()
        if not listPos then
            SetStatusText("|cff00ff00All items purchased!|r")
            ShowStatusView(
                "|cff00ff00All items purchased!|r",
                "Close", true,
                function()
                    ns.Log("All items purchased.", 0.4, 1, 0.4)
                    suppressStopMessage = true
                    ns.Reset()
                    mainFrame:Hide()
                end
            )
        else
            local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
            local itemName = C_Item.GetItemInfo(item.id) or ("item:" .. item.id)
            local qty = ref.needed or item.qty

            local row = ns.resultRows[listPos]
            if item.maxPrice and item.maxPrice > 0 and row and row.minPrice and row.minPrice > item.maxPrice * 10000 then
                local actualGold = string.format("%.2f", row.minPrice / 10000)
                local msg = "Skipped " .. itemName .. ": " .. actualGold .. "g/ea exceeds max " .. item.maxPrice .. "g."
                ns.Print(msg)
                ns.Log(msg, 1, 0.82, 0)
                ns.boughtIndices[listPos] = true
                UpdateUI()
                return
            end

            SetStatusText("Next: " .. itemName)
            ShowStatusView(
                "Next: " .. itemName,
                "Buy " .. qty .. "x " .. itemName, true,
                function()
                    ns.pendingListPos = listPos
                    ns.pendingItemID  = ns.resultRows[listPos].itemKey.itemID
                    ns.pendingQty     = qty
                    ns.state = ns.STATE.CONFIRMING
                    UpdateUI()
                    C_AuctionHouse.StartCommoditiesPurchase(ns.pendingItemID, ns.pendingQty)
                end
            )
        end

    elseif ns.state == ns.STATE.CONFIRMING then
        SetStatusText("Confirming purchase...")
        ShowStatusView("Confirming purchase...", "Please wait...", false)
    end
end
ns.UpdateUI = UpdateUI

-- ============================================================
-- Callbacks for Profiles.lua  (rebuild current tab from state)
-- ============================================================
ns.RefreshToBuyUI = function()
    ns.RefreshSidebar()
    if ns.state == ns.STATE.IDLE then
        local idx = ui.currentCatIdx
        if idx ~= ui.LOG_TAB and idx ~= ui.ABOUT_TAB then
            ns.SelectTab(idx)
        end
    end
end

-- ============================================================
-- Main frame  (created at file load, starts hidden)
-- ============================================================
mainFrame = CreateFrame("Frame", "GuildBankRestockFrame", UIParent, "BackdropTemplate")
mainFrame:SetSize(1000, 560)
mainFrame:SetPoint("CENTER")
mainFrame:SetMovable(true)
mainFrame:SetResizable(true)
mainFrame:SetResizeBounds(600, 380)
mainFrame:SetClampedToScreen(true)
mainFrame:SetFrameStrata("MEDIUM")
mainFrame:SetBackdrop({
    bgFile   = "Interface/ChatFrame/ChatFrameBackground",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
mainFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.92)
mainFrame:SetBackdropBorderColor(0.65, 0.65, 0.65, 1)

local titleDrag = CreateFrame("Frame", nil, mainFrame)
titleDrag:SetPoint("TOPLEFT",  mainFrame, "TOPLEFT",  0, 0)
titleDrag:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", -30, 0)
titleDrag:SetHeight(30)
titleDrag:EnableMouse(true)
titleDrag:RegisterForDrag("LeftButton")
titleDrag:SetScript("OnDragStart", function() mainFrame:StartMoving() end)
titleDrag:SetScript("OnDragStop",  function() mainFrame:StopMovingOrSizing() end)

local titleText = titleDrag:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("CENTER", titleDrag, "CENTER", 0, 0)
titleText:SetText("Guild Bank Restock v" .. ui.version)

local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 2, 2)
closeButton:SetScript("OnClick", function() mainFrame:Hide() end)

local resizeGrip = CreateFrame("Button", nil, mainFrame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -2, 2)
resizeGrip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
resizeGrip:RegisterForDrag("LeftButton")
resizeGrip:SetScript("OnDragStart", function() mainFrame:StartSizing("BOTTOMRIGHT") end)
resizeGrip:SetScript("OnDragStop", function()
    mainFrame:StopMovingOrSizing()
    if ns.addon and ns.addon.db then
        ns.addon.db.global.windowWidth  = math.floor(mainFrame:GetWidth()  + 0.5)
        ns.addon.db.global.windowHeight = math.floor(mainFrame:GetHeight() + 0.5)
    end
end)

statusBar = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusBar:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  12, 10)
statusBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -30, 10)
statusBar:SetJustifyH("LEFT")

_G["GuildBankRestockMainFrame"] = mainFrame
tinsert(UISpecialFrames, "GuildBankRestockMainFrame")

mainFrame:HookScript("OnHide", function()
    if not suppressStopMessage then
        ns.Reset()
        ns.Print("Stopped.")
        ns.Log("Stopped.", 1, 0.6, 0.6)
    end
    suppressStopMessage = false
end)

mainFrame:Hide()
ns.frame   = mainFrame
ui.mainFrame = mainFrame

-- ============================================================
-- Apply saved settings  (called by GBR:OnInitialize)
-- ============================================================
ns.ApplySettingsToUI = function()
    local g = ns.addon and ns.addon.db and ns.addon.db.global
    if g and g.windowWidth and g.windowHeight then
        mainFrame:SetSize(g.windowWidth, g.windowHeight)
    end
    local ctxDB = ns.addon and ns.addon.db and ns.ContextDB and ns.ContextDB()
    ui.currentRankFilter = ctxDB and ctxDB.rankFilter or nil
    ns.RefreshSidebar()
end
