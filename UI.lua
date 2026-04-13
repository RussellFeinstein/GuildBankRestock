local ADDON_NAME, ns = ...

local CATEGORIES = ns.CATEGORIES

local FRAME_W         = 380
local FRAME_H_FULL    = 400
local FRAME_H_COMPACT = 90

-- ============================================================
-- Main frame
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
frame:SetResizeBounds(320, 200, 700, 900)
frame:Hide()
tinsert(UISpecialFrames, "GuildBankRestockFrame")

local suppressStopMessage = false
frame:SetScript("OnHide", function()
    if not suppressStopMessage then
        ns.Reset()
        ns.Print("Stopped.")
        ns.Log("Stopped.", 1, 0.6, 0.6)
    end
    suppressStopMessage = false
end)

ns.frame = frame  -- exposed for Commands.lua

local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
titleText:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8)
titleText:SetText("|cff00ccffGuild Bank Restock|r")

local stopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
stopBtn:SetSize(40, 16)
stopBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
stopBtn:SetText("X")

-- ============================================================
-- Category tabs
-- ============================================================
local TAB_H    = 22
local TAB_GAP  = 2
local NUM_CATS = #CATEGORIES
local LOG_TAB  = NUM_CATS + 1
local TAB_W    = math.floor((FRAME_W - 16 - (LOG_TAB - 1) * TAB_GAP) / LOG_TAB)

local tabContainer = CreateFrame("Frame", nil, frame)
tabContainer:SetPoint("TOPLEFT",  titleText, "BOTTOMLEFT", 0, -6)
tabContainer:SetPoint("TOPRIGHT", frame,     "TOPRIGHT",  -8, 0)
tabContainer:SetHeight(TAB_H)

local tabButtons    = {}
local currentCatIdx = 1
local SelectTab     -- forward declaration

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

local logTabBtn = CreateFrame("Button", nil, tabContainer, "UIPanelButtonTemplate")
logTabBtn:SetSize(TAB_W, TAB_H)
logTabBtn:SetPoint("TOPLEFT", tabButtons[NUM_CATS], "TOPRIGHT", TAB_GAP, 0)
logTabBtn:SetText("Log")
logTabBtn:SetScript("OnClick", function() SelectTab(LOG_TAB) end)
tabButtons[LOG_TAB] = logTabBtn

-- ============================================================
-- Checklist section
-- ============================================================
local ALLNONE_H = 22
local COL_CB    = 2
local COL_NAME  = 24
local QTY_W     = 34
local ROW_H     = 20
local SUBCAT_H  = 18

local checklistSection = CreateFrame("Frame", nil, frame)
checklistSection:SetPoint("TOPLEFT",     tabContainer, "BOTTOMLEFT",  0, -4)
checklistSection:SetPoint("BOTTOMRIGHT", frame,        "BOTTOMRIGHT", -8, 58)

local categoryGroups = {}  -- catIdx -> Frame

local HEADER_H = 16

local headerItem = checklistSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
headerItem:SetPoint("TOPLEFT", checklistSection, "TOPLEFT", COL_NAME, 0)
headerItem:SetText("Item")

local headerQty = checklistSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
headerQty:SetPoint("TOPRIGHT", checklistSection, "TOPRIGHT", -(QTY_W / 2 + 4), 0)
headerQty:SetText("Qty")

local scrollFrame = CreateFrame("ScrollFrame", nil, checklistSection, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     checklistSection, "TOPLEFT",     0, -HEADER_H)
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

local r1Btn = CreateFrame("Button", nil, checklistSection, "UIPanelButtonTemplate")
r1Btn:SetSize(44, ALLNONE_H)
r1Btn:SetPoint("LEFT", noneBtn, "RIGHT", 12, 0)
r1Btn:SetText("R1")

local r2Btn = CreateFrame("Button", nil, checklistSection, "UIPanelButtonTemplate")
r2Btn:SetSize(44, ALLNONE_H)
r2Btn:SetPoint("LEFT", r1Btn, "RIGHT", 4, 0)
r2Btn:SetText("R2")

local bothBtn = CreateFrame("Button", nil, checklistSection, "UIPanelButtonTemplate")
bothBtn:SetSize(54, ALLNONE_H)
bothBtn:SetPoint("LEFT", r2Btn, "RIGHT", 4, 0)
bothBtn:SetText("Both")

local logFrame = CreateFrame("ScrollingMessageFrame", "GuildBankRestockLogFrame", checklistSection)
logFrame:SetPoint("TOPLEFT",     checklistSection, "TOPLEFT",     0, -HEADER_H)
logFrame:SetPoint("BOTTOMRIGHT", checklistSection, "BOTTOMRIGHT", -4, ALLNONE_H + 4)
logFrame:SetFading(false)
logFrame:SetMaxLines(500)
logFrame:SetFontObject(GameFontNormalSmall)
logFrame:EnableMouseWheel(true)
logFrame:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
end)
logFrame:Hide()

ns.AppendLogEntry = function(msg, r, g, b)
    logFrame:AddMessage(msg, r or 1, g or 1, b or 1)
end

-- ============================================================
-- Status text, action button, resize grip
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

local savedFrameHeight = nil

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
    if ns.state == ns.STATE.IDLE then
        savedFrameHeight = frame:GetHeight()
    end
end)

-- ============================================================
-- Item rows  (checkbox + linked name + qty box, per category)
-- ============================================================
local categoryRows    = {}  -- catIdx -> array of { rowFrame/headerFrame, cb, qtyBox }
local categoryHeights = {}  -- catIdx -> total pixel height of the group

for catIdx, cat in ipairs(CATEGORIES) do
    local group = CreateFrame("Frame", nil, scrollChild)
    group:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
    group:SetWidth(FRAME_W - 38)
    group:Hide()
    categoryGroups[catIdx] = group
    categoryRows[catIdx]   = {}

    local yPos = 0

    for i, item in ipairs(cat.items) do
        if item.header then
            local headerFrame = CreateFrame("Frame", nil, group)
            headerFrame:SetPoint("TOPLEFT",  group, "TOPLEFT",  0, -yPos)
            headerFrame:SetPoint("TOPRIGHT", group, "TOPRIGHT", 0, -yPos)
            headerFrame:SetHeight(SUBCAT_H)

            local hl = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            hl:SetPoint("LEFT", headerFrame, "LEFT", COL_NAME, 0)
            hl:SetTextColor(1, 0.82, 0)
            hl:SetText(item.header)

            categoryRows[catIdx][i] = { headerFrame = headerFrame }
            yPos = yPos + SUBCAT_H
        else
            local rowFrame = CreateFrame("Frame", nil, group)
            rowFrame:SetPoint("TOPLEFT",  group, "TOPLEFT",  0, -yPos)
            rowFrame:SetPoint("TOPRIGHT", group, "TOPRIGHT", 0, -yPos)
            rowFrame:SetHeight(ROW_H)

            local cb = CreateFrame("CheckButton", nil, rowFrame)
            cb:SetSize(18, 18)
            cb:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", COL_CB, -1)
            cb:SetNormalTexture("Interface/Buttons/UI-CheckBox-Up")
            cb:SetPushedTexture("Interface/Buttons/UI-CheckBox-Down")
            cb:SetCheckedTexture("Interface/Buttons/UI-CheckBox-Check")
            cb:SetHighlightTexture("Interface/Buttons/UI-CheckBox-Highlight", "ADD")
            cb:SetChecked(item.enabled)
            cb:SetScript("OnClick", function(self)
                CATEGORIES[catIdx].items[i].enabled = self:GetChecked()
                ns.SaveItem(catIdx, i)
            end)

            local nameFrame = CreateFrame("Frame", nil, rowFrame)
            nameFrame:SetPoint("TOPLEFT",  rowFrame, "TOPLEFT",  COL_NAME,     0)
            nameFrame:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -(QTY_W + 8), 0)
            nameFrame:SetHeight(ROW_H)
            nameFrame:EnableMouse(true)

            local label = nameFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT",  nameFrame, "LEFT",  0, 0)
            label:SetPoint("RIGHT", nameFrame, "RIGHT", 0, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            label:SetText("item:" .. item.id)

            local function TryLoadLink(attempts)
                local _, link = GetItemInfo(item.id)
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

            local qtyBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
            qtyBox:SetSize(QTY_W, 16)
            qtyBox:SetPoint("RIGHT", rowFrame, "TOPRIGHT", -4, -ROW_H / 2)
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
                ns.SaveItem(catIdx, i)
            end)

            categoryRows[catIdx][i] = { rowFrame = rowFrame, cb = cb, qtyBox = qtyBox }
            yPos = yPos + ROW_H
        end
    end

    local totalH = math.max(yPos + 4, 1)
    group:SetHeight(totalH)
    categoryHeights[catIdx] = totalH
end

-- ============================================================
-- SelectTab
-- ============================================================
SelectTab = function(idx)
    for i, btn in ipairs(tabButtons) do
        if i == idx then
            btn:GetFontString():SetTextColor(1, 0.82, 0)
        else
            btn:GetFontString():SetTextColor(1, 1, 1)
        end
    end

    if currentCatIdx == LOG_TAB then
        logFrame:Hide()
    else
        categoryGroups[currentCatIdx]:Hide()
    end
    currentCatIdx = idx

    if idx == LOG_TAB then
        headerItem:Hide()
        headerQty:Hide()
        allBtn:Hide()
        noneBtn:Hide()
        r1Btn:Hide()
        r2Btn:Hide()
        bothBtn:Hide()
        logFrame:Show()
    else
        headerItem:Show()
        headerQty:Show()
        allBtn:Show()
        noneBtn:Show()
        r1Btn:Show()
        r2Btn:Show()
        bothBtn:Show()
        categoryGroups[idx]:Show()
        scrollChild:SetHeight(categoryHeights[idx] or 1)
    end
end

SelectTab(1)

-- ============================================================
-- All / None  (current tab only)
-- ============================================================
allBtn:SetScript("OnClick", function()
    for i, row in ipairs(categoryRows[currentCatIdx]) do
        if not row.headerFrame then
            CATEGORIES[currentCatIdx].items[i].enabled = true
            row.cb:SetChecked(true)
            ns.SaveItem(currentCatIdx, i)
        end
    end
end)

noneBtn:SetScript("OnClick", function()
    for i, row in ipairs(categoryRows[currentCatIdx]) do
        if not row.headerFrame then
            CATEGORIES[currentCatIdx].items[i].enabled = false
            row.cb:SetChecked(false)
            ns.SaveItem(currentCatIdx, i)
        end
    end
end)

-- ============================================================
-- R1 / R2 / Both  (all tabs)
-- ============================================================
local function ApplyRankFilter(rank)
    for catIdx, cat in ipairs(CATEGORIES) do
        local group = categoryGroups[catIdx]
        local yPos  = 0

        for i, item in ipairs(cat.items) do
            local row = categoryRows[catIdx][i]
            if item.header then
                local anyVisible = false
                for j = i + 1, #cat.items do
                    if cat.items[j].header then break end
                    local jItem = cat.items[j]
                    if not jItem.rank or (rank == nil) or (jItem.rank == rank) then
                        anyVisible = true
                        break
                    end
                end
                if anyVisible then
                    row.headerFrame:ClearAllPoints()
                    row.headerFrame:SetPoint("TOPLEFT",  group, "TOPLEFT",  0, -yPos)
                    row.headerFrame:SetPoint("TOPRIGHT", group, "TOPRIGHT", 0, -yPos)
                    row.headerFrame:Show()
                    yPos = yPos + SUBCAT_H
                else
                    row.headerFrame:Hide()
                end
            else
                local show = not item.rank or (rank == nil) or (item.rank == rank)
                item.enabled = show
                row.cb:SetChecked(show)
                if show then
                    row.rowFrame:ClearAllPoints()
                    row.rowFrame:SetPoint("TOPLEFT",  group, "TOPLEFT",  0, -yPos)
                    row.rowFrame:SetPoint("TOPRIGHT", group, "TOPRIGHT", 0, -yPos)
                    row.rowFrame:Show()
                    yPos = yPos + ROW_H
                else
                    row.rowFrame:Hide()
                end
            end
        end

        local totalH = math.max(yPos + 4, 1)
        group:SetHeight(totalH)
        categoryHeights[catIdx] = totalH
    end
    scrollChild:SetHeight(categoryHeights[currentCatIdx] or 1)
    ns.SaveRankFilter(rank)
end

local function SetRankButtonActive(rank)
    local function Color(btn, active)
        if active then
            btn:GetFontString():SetTextColor(1, 0.82, 0)  -- gold
        else
            btn:GetFontString():SetTextColor(1, 1, 1)     -- white
        end
    end
    Color(r1Btn,   rank == 1)
    Color(r2Btn,   rank == 2)
    Color(bothBtn, rank == nil)
end

r1Btn:SetScript("OnClick",   function() ApplyRankFilter(1);   SetRankButtonActive(1)   end)
r2Btn:SetScript("OnClick",   function() ApplyRankFilter(2);   SetRankButtonActive(2)   end)
bothBtn:SetScript("OnClick", function() ApplyRankFilter(nil); SetRankButtonActive(nil) end)

SetRankButtonActive(nil)  -- Both is the default state

-- Called by GuildBankRestock.lua after SavedVariables are loaded.
-- Refreshes all widgets from CATEGORIES and restores the saved rank filter.
ns.ApplySettingsToUI = function()
    for catIdx, cat in ipairs(CATEGORIES) do
        for i, item in ipairs(cat.items) do
            if not item.header then
                local row = categoryRows[catIdx][i]
                if row then
                    row.cb:SetChecked(item.enabled)
                    row.qtyBox:SetText(tostring(item.qty))
                end
            end
        end
    end
    local rank = GuildBankRestockDB and GuildBankRestockDB.rankFilter or nil
    ApplyRankFilter(rank)
    SetRankButtonActive(rank)
end

-- ============================================================
-- UpdateUI
-- ============================================================
local function UpdateUI()
    if ns.state == ns.STATE.IDLE then
        tabContainer:Show()
        checklistSection:Show()
        frame:SetHeight(savedFrameHeight or FRAME_H_FULL)
        statusText:SetText("Select items and quantities, then Start.")
        actionBtn:SetText("Start")
        actionBtn:Enable()

    elseif ns.state == ns.STATE.SEARCHING then
        savedFrameHeight = frame:GetHeight()
        tabContainer:Hide()
        checklistSection:Hide()
        frame:SetHeight(FRAME_H_COMPACT)
        statusText:SetText("Searching...")
        actionBtn:SetText("Searching...")
        actionBtn:Disable()

    elseif ns.state == ns.STATE.READY then
        tabContainer:Hide()
        checklistSection:Hide()
        frame:SetHeight(FRAME_H_COMPACT)
        local listPos, ref = ns.GetNextItem()
        if not listPos then
            statusText:SetText("|cff00ff00All items purchased!|r")
            actionBtn:SetText("Close")
            actionBtn:Enable()
        else
            local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
            local itemName = C_Item.GetItemInfo(item.id) or ("item:" .. item.id)
            statusText:SetText("Next: " .. itemName)
            actionBtn:SetText("Buy " .. item.qty .. "x " .. itemName)
            actionBtn:Enable()
        end

    elseif ns.state == ns.STATE.CONFIRMING then
        tabContainer:Hide()
        checklistSection:Hide()
        frame:SetHeight(FRAME_H_COMPACT)
        statusText:SetText("Confirming purchase...")
        actionBtn:SetText("Please wait...")
        actionBtn:Disable()
    end
end

ns.UpdateUI = UpdateUI  -- exposed for Core.lua callbacks

-- ============================================================
-- Action button
-- ============================================================
actionBtn:SetScript("OnClick", function()
    if ns.state == ns.STATE.IDLE then
        if not Auctionator or not Auctionator.API.v1.ConvertToSearchString then
            ns.Print("Auctionator is not loaded or is outdated.")
            return
        end
        if not AuctionatorShoppingFrame or not AuctionatorShoppingFrame:IsVisible() then
            ns.Print("Open the Auctionator Shopping tab first.")
            return
        end
        wipe(ns.activeItems)
        wipe(ns.boughtIndices)
        wipe(ns.resultRows)
        for catIdx, cat in ipairs(CATEGORIES) do
            for itemIdx, item in ipairs(cat.items) do
                if item.enabled and not item.header then
                    ns.activeItems[#ns.activeItems + 1] = { catIdx = catIdx, itemIdx = itemIdx }
                end
            end
        end
        if #ns.activeItems == 0 then
            ns.Print("No items selected — enable at least one.")
            return
        end
        Auctionator.EventBus:RegisterSource(ns.listener, ADDON_NAME)
        Auctionator.EventBus:Register(ns.listener, { Auctionator.Shopping.Tab.Events.SearchEnd })
        ns.listenerRegistered = true
        ns.state = ns.STATE.SEARCHING
        UpdateUI()
        ns.Log("Search started: " .. #ns.activeItems .. " items.", 0.8, 0.8, 1)
        AuctionatorShoppingFrame:DoSearch(ns.BuildSearchStrings())

    elseif ns.state == ns.STATE.READY then
        local listPos, ref = ns.GetNextItem()
        if not listPos then
            ns.Log("All items purchased.", 0.4, 1, 0.4)
            suppressStopMessage = true
            ns.Reset()
            frame:Hide()
            return
        end
        local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
        ns.pendingListPos = listPos
        ns.pendingItemID  = ns.resultRows[listPos].itemKey.itemID
        ns.pendingQty     = item.qty
        ns.state = ns.STATE.CONFIRMING
        UpdateUI()
        C_AuctionHouse.StartCommoditiesPurchase(ns.pendingItemID, ns.pendingQty)
    end
end)

stopBtn:SetScript("OnClick", function()
    frame:Hide()
end)
