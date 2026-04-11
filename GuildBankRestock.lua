local ADDON_NAME = ...

local FRAME_W         = 340
local FRAME_H_FULL    = 400
local FRAME_H_COMPACT = 90

-- ============================================================
-- Item categories  (edit qty here or via the in-game UI)
-- ============================================================
local CATEGORIES = {
    {
        name = "Gems",
        items = {
            { name = "Telluric Eversong Diamond",       qty = 1, enabled = true },
            { name = "Powerful Eversong Diamond",        qty = 1, enabled = true },
            { name = "Indecipherable Eversong Diamond",  qty = 1, enabled = true },
            { name = "Stoic Eversong Diamond",           qty = 1, enabled = true },
            { name = "Flawless Versatile Lapis",         qty = 1, enabled = true },
            { name = "Flawless Deadly Lapis",            qty = 1, enabled = true },
            { name = "Flawless Masterful Lapis",         qty = 1, enabled = true },
            { name = "Flawless Versatile Amethyst",      qty = 1, enabled = true },
            { name = "Flawless Versatile Peridot",       qty = 1, enabled = true },
            { name = "Flawless Deadly Peridot",          qty = 1, enabled = true },
            { name = "Flawless Deadly Garnet",           qty = 1, enabled = true },
            { name = "Flawless Masterful Amethyst",      qty = 1, enabled = true },
            { name = "Flawless Quick Lapis",             qty = 1, enabled = true },
            { name = "Flawless Versatile Garnet",        qty = 1, enabled = true },
            { name = "Flawless Quick Peridot",           qty = 1, enabled = true },
            { name = "Flawless Masterful Garnet",        qty = 1, enabled = true },
            { name = "Flawless Quick Garnet",            qty = 1, enabled = true },
            { name = "Flawless Masterful Peridot",       qty = 1, enabled = true },
            { name = "Flawless Quick Amethyst",          qty = 1, enabled = true },
            { name = "Flawless Deadly Amethyst",         qty = 1, enabled = true },
        }
    },
    {
        name = "Enchants",
        items = {}
    },
    {
        name = "Potions",
        items = {}
    },
    {
        name = "Flasks",
        items = {}
    },
    {
        name = "Oils",
        items = {}
    },
}

-- ============================================================
-- State
-- ============================================================
local STATE = {
    IDLE       = "IDLE",
    SEARCHING  = "SEARCHING",
    READY      = "READY",
    CONFIRMING = "CONFIRMING",
}
local state = STATE.IDLE

local activeItems        = {}  -- { catIdx, itemIdx } for items in this run
local resultRows         = {}  -- listPos -> AH row
local boughtIndices      = {}  -- listPos -> true
local pendingListPos     = nil
local pendingItemID      = nil
local pendingQty         = nil
local listenerRegistered = false
local savedFrameHeight   = nil
local currentCatIdx      = 1

-- ============================================================
-- Helpers
-- ============================================================
local function Print(msg)
    print("|cff00ccffGuild Bank Restock:|r " .. tostring(msg))
end

local listener = {}

local function UnregisterListener()
    if listenerRegistered then
        Auctionator.EventBus:Unregister(listener, { Auctionator.Shopping.Tab.Events.SearchEnd })
        listenerRegistered = false
    end
end

local function Reset()
    UnregisterListener()
    state          = STATE.IDLE
    pendingListPos = nil
    pendingItemID  = nil
    pendingQty     = nil
    wipe(activeItems)
    wipe(resultRows)
    wipe(boughtIndices)
end

local function BuildSearchStrings()
    local list = {}
    for _, ref in ipairs(activeItems) do
        local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
        local s = Auctionator.API.v1.ConvertToSearchString(ADDON_NAME, {
            searchString = item.name,
            isExact      = true,
        })
        list[#list + 1] = s
    end
    return list
end

local function MapResultRows()
    wipe(resultRows)
    local dataProvider = AuctionatorShoppingFrame.ResultsListing.dataProvider
    for i = 1, dataProvider:GetCount() do
        local row = dataProvider:GetEntryAt(i)
        local itemName = C_Item.GetItemInfo(row.itemKey.itemID)
        if itemName then
            for listPos, ref in ipairs(activeItems) do
                local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
                if item.name == itemName then
                    resultRows[listPos] = row
                    break
                end
            end
        end
    end
end

local function GetNextItem()
    for listPos, ref in ipairs(activeItems) do
        if not boughtIndices[listPos] and resultRows[listPos] then
            return listPos, ref
        end
    end
    return nil, nil
end

-- ============================================================
-- UI – main frame
-- ============================================================
local frame = CreateFrame("Frame", "GuildBankRestockFrame", UIParent, "BackdropTemplate")
frame:SetSize(FRAME_W, FRAME_H_FULL)
frame:SetPoint("CENTER")
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
frame:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    tile = true, tileSize = 8, edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
})
frame:SetBackdropColor(0, 0, 0, 0.85)
frame:SetResizable(true)
frame:SetResizeBounds(280, 200, 700, 900)
frame:Hide()

local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
titleText:SetText("|cff00ccffGuild Bank Restock|r")

local stopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
stopBtn:SetSize(40, 16)
stopBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
stopBtn:SetText("X")

-- ============================================================
-- UI – category tabs
-- ============================================================
local TAB_H    = 22
local TAB_GAP  = 2
local NUM_CATS = #CATEGORIES
local TAB_W    = math.floor((FRAME_W - 16 - (NUM_CATS - 1) * TAB_GAP) / NUM_CATS)

local tabContainer = CreateFrame("Frame", nil, frame)
tabContainer:SetPoint("TOPLEFT",  titleText, "BOTTOMLEFT", 0, -6)
tabContainer:SetPoint("TOPRIGHT", frame,     "TOPRIGHT",  -8, 0)
tabContainer:SetHeight(TAB_H)

local tabButtons = {}
local SelectTab  -- forward declaration

for i, cat in ipairs(CATEGORIES) do
    local btn = CreateFrame("Button", nil, tabContainer, "UIPanelButtonTemplate")
    btn:SetSize(TAB_W, TAB_H)
    if i == 1 then
        btn:SetPoint("TOPLEFT", tabContainer, "TOPLEFT", 0, 0)
    else
        btn:SetPoint("TOPLEFT", tabButtons[i - 1], "TOPRIGHT", TAB_GAP, 0)
    end
    btn:SetText(cat.name)
    btn:SetScript("OnClick", function() SelectTab(i) end)
    tabButtons[i] = btn
end

-- ============================================================
-- UI – checklist section (visible only in IDLE)
-- ============================================================
local ALLNONE_H = 22

local checklistSection = CreateFrame("Frame", nil, frame)
checklistSection:SetPoint("TOPLEFT",     tabContainer, "BOTTOMLEFT",  0, -4)
checklistSection:SetPoint("BOTTOMRIGHT", frame,        "BOTTOMRIGHT", -8, 58)

local categoryGroups = {}  -- catIdx -> Frame  (declared before OnSizeChanged closure)

local scrollFrame = CreateFrame("ScrollFrame", nil, checklistSection, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     checklistSection, "TOPLEFT",     0, 0)
scrollFrame:SetPoint("BOTTOMRIGHT", checklistSection, "BOTTOMRIGHT", -20, ALLNONE_H + 4)

local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollChild:SetWidth(FRAME_W - 38)
scrollChild:SetHeight(1)
scrollFrame:SetScrollChild(scrollChild)
scrollFrame:SetScript("OnSizeChanged", function(self, w)
    scrollChild:SetWidth(w)
    for _, grp in ipairs(categoryGroups) do
        grp:SetWidth(w)
    end
end)

local allBtn = CreateFrame("Button", nil, checklistSection, "UIPanelButtonTemplate")
allBtn:SetSize(58, ALLNONE_H)
allBtn:SetPoint("BOTTOMLEFT", checklistSection, "BOTTOMLEFT", 0, 0)
allBtn:SetText("All")

local noneBtn = CreateFrame("Button", nil, checklistSection, "UIPanelButtonTemplate")
noneBtn:SetSize(58, ALLNONE_H)
noneBtn:SetPoint("LEFT", allBtn, "RIGHT", 4, 0)
noneBtn:SetText("None")

-- ============================================================
-- UI – status text and action button (always visible)
-- ============================================================
local statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusText:SetPoint("BOTTOMLEFT",  frame, "BOTTOMLEFT",  8, 38)
statusText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 38)
statusText:SetJustifyH("LEFT")
statusText:SetText("")

local actionBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
actionBtn:SetSize(220, 22)
actionBtn:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
actionBtn:SetText("Start")

local resizeGrip = CreateFrame("Button", nil, frame)
resizeGrip:SetSize(16, 16)
resizeGrip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
resizeGrip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
resizeGrip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
resizeGrip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
resizeGrip:SetScript("OnMouseDown", function(self, btn)
    if btn == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
end)
resizeGrip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    if state == STATE.IDLE then
        savedFrameHeight = frame:GetHeight()
    end
end)

-- ============================================================
-- Item rows  (checkbox + linked name + qty box, per category)
-- ============================================================
local categoryRows = {}  -- catIdx -> array of { cb, qtyBox }

local COL_CB   = 2
local COL_NAME = 24
local NAME_W   = 200
local COL_QTY  = COL_NAME + NAME_W + 4
local QTY_W    = 34
local ROW_H    = 20

for catIdx, cat in ipairs(CATEGORIES) do
    local group = CreateFrame("Frame", nil, scrollChild)
    group:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    group:SetWidth(FRAME_W - 38)
    group:SetHeight(math.max(#cat.items * ROW_H + 4, 1))
    group:Hide()
    categoryGroups[catIdx] = group
    categoryRows[catIdx]   = {}

    for i, item in ipairs(cat.items) do
        local yOff = -(i - 1) * ROW_H

        -- Checkbox
        local cb = CreateFrame("CheckButton", nil, group)
        cb:SetSize(18, 18)
        cb:SetPoint("TOPLEFT", group, "TOPLEFT", COL_CB, yOff - 1)
        cb:SetNormalTexture("Interface/Buttons/UI-CheckBox-Up")
        cb:SetPushedTexture("Interface/Buttons/UI-CheckBox-Down")
        cb:SetCheckedTexture("Interface/Buttons/UI-CheckBox-Check")
        cb:SetHighlightTexture("Interface/Buttons/UI-CheckBox-Highlight", "ADD")
        cb:SetChecked(item.enabled)
        cb:SetScript("OnClick", function(self)
            CATEGORIES[catIdx].items[i].enabled = self:GetChecked()
        end)

        -- Hover zone for tooltip (sits over the name area)
        local nameFrame = CreateFrame("Frame", nil, group)
        nameFrame:SetPoint("TOPLEFT", group, "TOPLEFT", COL_NAME, yOff)
        nameFrame:SetSize(NAME_W, ROW_H)
        nameFrame:EnableMouse(true)

        local label = nameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", nameFrame, "LEFT", 0, 0)
        label:SetWidth(NAME_W)
        label:SetJustifyH("LEFT")
        label:SetText(item.name)

        local function TryLoadLink(attempts)
            local _, link = GetItemInfo(item.name)
            if link then
                label:SetText(link)
                nameFrame.itemLink = link
            elseif attempts < 10 then
                C_Timer.After(0.5, function() TryLoadLink(attempts + 1) end)
            end
        end
        TryLoadLink(0)

        nameFrame:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        nameFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Quantity box
        local qtyBox = CreateFrame("EditBox", nil, group, "InputBoxTemplate")
        qtyBox:SetSize(QTY_W, 16)
        qtyBox:SetPoint("LEFT", group, "TOPLEFT", COL_QTY, yOff - ROW_H / 2)
        qtyBox:SetNumeric(true)
        qtyBox:SetMaxLetters(3)
        qtyBox:SetAutoFocus(false)
        qtyBox:SetText(tostring(item.qty))
        qtyBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
        qtyBox:SetScript("OnEscapePressed", function(self)
            self:SetText(tostring(CATEGORIES[catIdx].items[i].qty))
            self:ClearFocus()
        end)
        qtyBox:SetScript("OnEditFocusLost", function(self)
            local v = tonumber(self:GetText()) or 1
            if v < 1 then v = 1 end
            CATEGORIES[catIdx].items[i].qty = v
            self:SetText(tostring(v))
        end)

        categoryRows[catIdx][i] = { cb = cb, qtyBox = qtyBox }
    end
end

-- ============================================================
-- SelectTab
-- ============================================================
SelectTab = function(idx)
    for i, btn in ipairs(tabButtons) do
        if i == idx then
            btn:GetFontString():SetTextColor(1, 0.82, 0)  -- gold = active
        else
            btn:GetFontString():SetTextColor(1, 1, 1)     -- white = inactive
        end
    end
    categoryGroups[currentCatIdx]:Hide()
    currentCatIdx = idx
    categoryGroups[idx]:Show()
    scrollChild:SetHeight(math.max(#CATEGORIES[idx].items * ROW_H + 4, 1))
end

SelectTab(1)  -- initialize to first tab

-- ============================================================
-- All / None  (current tab only)
-- ============================================================
allBtn:SetScript("OnClick", function()
    for i, row in ipairs(categoryRows[currentCatIdx]) do
        CATEGORIES[currentCatIdx].items[i].enabled = true
        row.cb:SetChecked(true)
    end
end)

noneBtn:SetScript("OnClick", function()
    for i, row in ipairs(categoryRows[currentCatIdx]) do
        CATEGORIES[currentCatIdx].items[i].enabled = false
        row.cb:SetChecked(false)
    end
end)

-- ============================================================
-- UpdateUI
-- ============================================================
local function UpdateUI()
    if state == STATE.IDLE then
        tabContainer:Show()
        checklistSection:Show()
        frame:SetHeight(savedFrameHeight or FRAME_H_FULL)
        statusText:SetText("Select items and quantities, then Start.")
        actionBtn:SetText("Start")
        actionBtn:Enable()

    elseif state == STATE.SEARCHING then
        savedFrameHeight = frame:GetHeight()
        tabContainer:Hide()
        checklistSection:Hide()
        frame:SetHeight(FRAME_H_COMPACT)
        statusText:SetText("Searching...")
        actionBtn:SetText("Searching...")
        actionBtn:Disable()

    elseif state == STATE.READY then
        tabContainer:Hide()
        checklistSection:Hide()
        frame:SetHeight(FRAME_H_COMPACT)
        local listPos, ref = GetNextItem()
        if not listPos then
            statusText:SetText("|cff00ff00All items purchased!|r")
            actionBtn:SetText("Close")
            actionBtn:Enable()
        else
            local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
            statusText:SetText("Next: " .. item.name)
            actionBtn:SetText("Buy " .. item.qty .. "x " .. item.name)
            actionBtn:Enable()
        end

    elseif state == STATE.CONFIRMING then
        tabContainer:Hide()
        checklistSection:Hide()
        frame:SetHeight(FRAME_H_COMPACT)
        statusText:SetText("Confirming purchase...")
        actionBtn:SetText("Please wait...")
        actionBtn:Disable()
    end
end

-- ============================================================
-- Auctionator EventBus listener  (search completion)
-- ============================================================
function listener:ReceiveEvent(eventName)
    if eventName ~= Auctionator.Shopping.Tab.Events.SearchEnd then return end
    if state ~= STATE.SEARCHING then return end
    listenerRegistered = false
    Auctionator.EventBus:Unregister(self, { Auctionator.Shopping.Tab.Events.SearchEnd })
    MapResultRows()
    local found = 0
    for _ in pairs(resultRows) do found = found + 1 end
    Print("Search complete. " .. found .. "/" .. #activeItems .. " items found in AH.")
    state = STATE.READY
    UpdateUI()
end

-- ============================================================
-- Action button  (hardware event — allowed to call protected functions)
-- ============================================================
actionBtn:SetScript("OnClick", function()
    if state == STATE.IDLE then
        if not Auctionator or not Auctionator.API.v1.ConvertToSearchString then
            Print("Auctionator is not loaded or is outdated.")
            return
        end
        if not AuctionatorShoppingFrame or not AuctionatorShoppingFrame:IsVisible() then
            Print("Open the Auctionator Shopping tab first.")
            return
        end
        wipe(activeItems)
        wipe(boughtIndices)
        wipe(resultRows)
        for catIdx, cat in ipairs(CATEGORIES) do
            for itemIdx, item in ipairs(cat.items) do
                if item.enabled then
                    activeItems[#activeItems + 1] = { catIdx = catIdx, itemIdx = itemIdx }
                end
            end
        end
        if #activeItems == 0 then
            Print("No items selected — enable at least one.")
            return
        end
        Auctionator.EventBus:RegisterSource(listener, ADDON_NAME)
        Auctionator.EventBus:Register(listener, { Auctionator.Shopping.Tab.Events.SearchEnd })
        listenerRegistered = true
        state = STATE.SEARCHING
        UpdateUI()
        AuctionatorShoppingFrame:DoSearch(BuildSearchStrings())

    elseif state == STATE.READY then
        local listPos, ref = GetNextItem()
        if not listPos then
            Reset()
            frame:Hide()
            return
        end
        local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
        pendingListPos = listPos
        pendingItemID  = resultRows[listPos].itemKey.itemID
        pendingQty     = item.qty
        state = STATE.CONFIRMING
        UpdateUI()
        C_AuctionHouse.StartCommoditiesPurchase(pendingItemID, pendingQty)
    end
end)

stopBtn:SetScript("OnClick", function()
    Reset()
    frame:Hide()
    Print("Stopped.")
end)

-- ============================================================
-- WoW event frame  (AH purchase flow)
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_FAILED")

eventFrame:SetScript("OnEvent", function(_, event)
    if state ~= STATE.CONFIRMING then return end

    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if pendingItemID and pendingQty then
            C_AuctionHouse.ConfirmCommoditiesPurchase(pendingItemID, pendingQty)
        end

    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local name = C_Item.GetItemInfo(pendingItemID) or ("item " .. tostring(pendingItemID))
        Print("Purchased " .. tostring(pendingQty) .. "x " .. name .. ".")
        boughtIndices[pendingListPos] = true
        pendingListPos = nil
        pendingItemID  = nil
        pendingQty     = nil
        state = STATE.READY
        UpdateUI()

    elseif event == "COMMODITY_PURCHASE_FAILED" then
        Print("Purchase failed — stopping. Check your gold or try again.")
        Reset()
        UpdateUI()
    end
end)

-- ============================================================
-- Slash commands:  /restock          → show the window
--                  /restock stop     → cancel and close
-- ============================================================
SLASH_GUILDBANKRESTOCK1 = "/restock"
SLASH_GUILDBANKRESTOCK2 = "/bankrestock"
SLASH_GUILDBANKRESTOCK3 = "/rs"
SlashCmdList["GUILDBANKRESTOCK"] = function(msg)
    local cmd = msg:lower():match("^%s*(%S*)") or ""
    if cmd == "stop" then
        Reset()
        frame:Hide()
        Print("Stopped.")
    else
        frame:Show()
        UpdateUI()
    end
end
