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
local _version = GetAddOnMetadata(ADDON_NAME, "Version") or "?"
titleText:SetText("|cff00ccffGuild Bank Restock|r |cff888888v" .. _version .. "|r")

local stopBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
stopBtn:SetSize(40, 16)
stopBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
stopBtn:SetText("X")

-- ============================================================
-- Mode bar  (Bulk / Restock)  +  profile selector
-- ============================================================
local modeBar = CreateFrame("Frame", nil, frame)
modeBar:SetPoint("TOPLEFT",  titleText, "BOTTOMLEFT",  0, -4)
modeBar:SetPoint("TOPRIGHT", frame,     "TOPRIGHT",   -8,  0)
modeBar:SetHeight(20)

local bulkBtn = CreateFrame("Button", nil, modeBar, "UIPanelButtonTemplate")
bulkBtn:SetSize(54, 18)
bulkBtn:SetPoint("TOPLEFT", modeBar, "TOPLEFT", 0, 0)
bulkBtn:SetText("Bulk")

local restockModeBtn = CreateFrame("Button", nil, modeBar, "UIPanelButtonTemplate")
restockModeBtn:SetSize(64, 18)
restockModeBtn:SetPoint("LEFT", bulkBtn, "RIGHT", 4, 0)
restockModeBtn:SetText("Restock")

local profileArea = CreateFrame("Frame", nil, modeBar)
profileArea:SetPoint("LEFT",  restockModeBtn, "RIGHT", 8, 0)
profileArea:SetPoint("RIGHT", modeBar,        "RIGHT", 0, 0)
profileArea:SetHeight(18)
profileArea:Hide()

local deleteProfileBtn = CreateFrame("Button", nil, profileArea, "UIPanelButtonTemplate")
deleteProfileBtn:SetSize(22, 18)
deleteProfileBtn:SetPoint("RIGHT", profileArea, "RIGHT", 0, 0)
deleteProfileBtn:SetText("-")

local newProfileBtn = CreateFrame("Button", nil, profileArea, "UIPanelButtonTemplate")
newProfileBtn:SetSize(22, 18)
newProfileBtn:SetPoint("RIGHT", deleteProfileBtn, "LEFT", -4, 0)
newProfileBtn:SetText("+")

local nextProfileBtn = CreateFrame("Button", nil, profileArea, "UIPanelButtonTemplate")
nextProfileBtn:SetSize(20, 18)
nextProfileBtn:SetPoint("RIGHT", newProfileBtn, "LEFT", -4, 0)
nextProfileBtn:SetText(">")

local prevProfileBtn = CreateFrame("Button", nil, profileArea, "UIPanelButtonTemplate")
prevProfileBtn:SetSize(20, 18)
prevProfileBtn:SetPoint("LEFT", profileArea, "LEFT", 0, 0)
prevProfileBtn:SetText("<")

local profileNameText = profileArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
profileNameText:SetPoint("LEFT",  prevProfileBtn, "RIGHT",  4, 0)
profileNameText:SetPoint("RIGHT", nextProfileBtn,  "LEFT", -4, 0)
profileNameText:SetJustifyH("CENTER")
profileNameText:SetText("(no profile)")

-- ============================================================
-- Category tabs
-- ============================================================
local TAB_H    = 22
local TAB_GAP  = 2
local NUM_CATS = #CATEGORIES
local LOG_TAB  = NUM_CATS + 1
local TAB_W    = math.floor((FRAME_W - 16 - (LOG_TAB - 1) * TAB_GAP) / LOG_TAB)

local tabContainer = CreateFrame("Frame", nil, frame)
tabContainer:SetPoint("TOPLEFT",  modeBar, "BOTTOMLEFT", 0, -4)
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
local TARGET_W  = 36
local TOBUY_W   = 36
local NAME_RIGHT_BULK    = -(QTY_W + 8)
local NAME_RIGHT_RESTOCK = -(TARGET_W + TOBUY_W + 12)
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

local headerTarget = checklistSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
headerTarget:SetPoint("TOPRIGHT", checklistSection, "TOPRIGHT", -(TOBUY_W + TARGET_W / 2 + 8), 0)
headerTarget:SetText("Target")
headerTarget:Hide()

local headerToBuy = checklistSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
headerToBuy:SetPoint("TOPRIGHT", checklistSection, "TOPRIGHT", -(TOBUY_W / 2 + 4), 0)
headerToBuy:SetText("To Buy")
headerToBuy:Hide()

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
            nameFrame:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", NAME_RIGHT_BULK, 0)
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

            local toBuyBox  -- forward-declared so targetBox's closure can reference it

            local targetBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
            targetBox:SetSize(TARGET_W, 16)
            targetBox:SetPoint("RIGHT", rowFrame, "TOPRIGHT", -(TOBUY_W + 8), -ROW_H / 2)
            targetBox:SetNumeric(true)
            targetBox:SetMaxLetters(3)
            targetBox:SetAutoFocus(false)
            targetBox:SetText("0")
            targetBox:Hide()
            targetBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            targetBox:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(ns.GetProfileTarget(catIdx, i)))
                self:ClearFocus()
            end)
            targetBox:SetScript("OnEditFocusLost", function(self)
                local v = math.max(0, tonumber(self:GetText()) or 0)
                self:SetText(tostring(v))
                ns.SetProfileTarget(catIdx, i, v)
                local inBank = ns.guildBankScanned and (ns.guildBankStock[CATEGORIES[catIdx].items[i].id] or 0) or 0
                local needed = math.max(0, v - inBank)
                ns.toBuy[catIdx .. "_" .. i] = needed
                if toBuyBox then toBuyBox:SetText(tostring(needed)) end
            end)

            toBuyBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
            toBuyBox:SetSize(TOBUY_W, 16)
            toBuyBox:SetPoint("RIGHT", rowFrame, "TOPRIGHT", -4, -ROW_H / 2)
            toBuyBox:SetNumeric(true)
            toBuyBox:SetMaxLetters(3)
            toBuyBox:SetAutoFocus(false)
            toBuyBox:SetText("0")
            toBuyBox:Hide()
            toBuyBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            toBuyBox:SetScript("OnEscapePressed", function(self)
                self:SetText(tostring(ns.toBuy[catIdx .. "_" .. i] or 0))
                self:ClearFocus()
            end)
            toBuyBox:SetScript("OnEditFocusLost", function(self)
                local v = math.max(0, tonumber(self:GetText()) or 0)
                self:SetText(tostring(v))
                ns.toBuy[catIdx .. "_" .. i] = v
            end)

            categoryRows[catIdx][i] = { rowFrame = rowFrame, cb = cb, qtyBox = qtyBox, nameFrame = nameFrame, targetBox = targetBox, toBuyBox = toBuyBox }
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
        headerTarget:Hide()
        headerToBuy:Hide()
        allBtn:Hide()
        noneBtn:Hide()
        r1Btn:Hide()
        r2Btn:Hide()
        bothBtn:Hide()
        logFrame:Show()
    else
        headerItem:Show()
        if ns.mode == "restock" then
            headerQty:Hide()
            headerTarget:Show()
            headerToBuy:Show()
        else
            headerQty:Show()
            headerTarget:Hide()
            headerToBuy:Hide()
        end
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

-- ============================================================
-- Mode switching + profile UI
-- ============================================================
local function SetMode(mode)
    ns.mode = mode
    GuildBankRestockDB.mode = mode

    if mode == "bulk" then
        bulkBtn:GetFontString():SetTextColor(1, 0.82, 0)
        restockModeBtn:GetFontString():SetTextColor(1, 1, 1)
        profileArea:Hide()
        headerQty:Show()
        headerTarget:Hide()
        headerToBuy:Hide()
    else
        bulkBtn:GetFontString():SetTextColor(1, 1, 1)
        restockModeBtn:GetFontString():SetTextColor(1, 0.82, 0)
        profileArea:Show()
        headerQty:Hide()
        headerTarget:Show()
        headerToBuy:Show()
        ns.RecalculateToBuy()
    end

    for catIdx in ipairs(CATEGORIES) do
        for _, row in ipairs(categoryRows[catIdx]) do
            if not row.headerFrame then
                if mode == "bulk" then
                    row.qtyBox:Show()
                    row.targetBox:Hide()
                    row.toBuyBox:Hide()
                    row.nameFrame:ClearAllPoints()
                    row.nameFrame:SetPoint("TOPLEFT",  row.rowFrame, "TOPLEFT",  COL_NAME,       0)
                    row.nameFrame:SetPoint("TOPRIGHT", row.rowFrame, "TOPRIGHT", NAME_RIGHT_BULK, 0)
                else
                    row.qtyBox:Hide()
                    row.targetBox:Show()
                    row.toBuyBox:Show()
                    row.nameFrame:ClearAllPoints()
                    row.nameFrame:SetPoint("TOPLEFT",  row.rowFrame, "TOPLEFT",  COL_NAME,           0)
                    row.nameFrame:SetPoint("TOPRIGHT", row.rowFrame, "TOPRIGHT", NAME_RIGHT_RESTOCK,  0)
                end
            end
        end
    end
end

ns.SetMode = SetMode

ns.RefreshToBuyUI = function()
    for catIdx, cat in ipairs(CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local row = categoryRows[catIdx][itemIdx]
                if row and row.toBuyBox then
                    row.toBuyBox:SetText(tostring(ns.toBuy[catIdx .. "_" .. itemIdx] or 0))
                end
            end
        end
    end
end

ns.RefreshProfileUI = function()
    local names = ns.GetProfileNames()
    profileNameText:SetText(ns.currentProfile or "(no profile)")
    local hasMany = #names > 1
    if hasMany then prevProfileBtn:Enable() nextProfileBtn:Enable()
    else prevProfileBtn:Disable() nextProfileBtn:Disable() end
    if ns.currentProfile then deleteProfileBtn:Enable() else deleteProfileBtn:Disable() end
    for catIdx, cat in ipairs(CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local row = categoryRows[catIdx][itemIdx]
                if row and row.targetBox then
                    row.targetBox:SetText(tostring(ns.GetProfileTarget(catIdx, itemIdx)))
                end
            end
        end
    end
end

StaticPopupDialogs["GUILDBANKRESTOCK_NEW_PROFILE"] = {
    text = "Enter a name for the new profile:",
    button1 = "Create",
    button2 = "Cancel",
    hasEditBox = true,
    OnAccept = function(self)
        local name = self.editBox:GetText():match("^%s*(.-)%s*$")
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

bulkBtn:SetScript("OnClick",        function() SetMode("bulk")    end)
restockModeBtn:SetScript("OnClick", function() SetMode("restock") end)

prevProfileBtn:SetScript("OnClick", function()
    local names = ns.GetProfileNames()
    if #names < 2 then return end
    local idx = 1
    for i, n in ipairs(names) do if n == ns.currentProfile then idx = i; break end end
    idx = idx - 1; if idx < 1 then idx = #names end
    ns.SetActiveProfile(names[idx])
end)

nextProfileBtn:SetScript("OnClick", function()
    local names = ns.GetProfileNames()
    if #names < 2 then return end
    local idx = 1
    for i, n in ipairs(names) do if n == ns.currentProfile then idx = i; break end end
    idx = idx % #names + 1
    ns.SetActiveProfile(names[idx])
end)

newProfileBtn:SetScript("OnClick",    function() StaticPopup_Show("GUILDBANKRESTOCK_NEW_PROFILE") end)
deleteProfileBtn:SetScript("OnClick", function()
    if ns.currentProfile then ns.DeleteProfile(ns.currentProfile) end
end)

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
    ns.currentProfile = GuildBankRestockDB and GuildBankRestockDB.activeProfile or nil
    local savedMode = (GuildBankRestockDB and GuildBankRestockDB.mode) or "bulk"
    SetMode(savedMode)
    if savedMode == "restock" then ns.RefreshProfileUI() end
end

-- ============================================================
-- UpdateUI
-- ============================================================
local function UpdateUI()
    if ns.state == ns.STATE.IDLE then
        modeBar:Show()
        tabContainer:Show()
        checklistSection:Show()
        frame:SetHeight(savedFrameHeight or FRAME_H_FULL)
        statusText:SetText("Select items and quantities, then Start.")
        actionBtn:SetText("Start")
        actionBtn:Enable()

    elseif ns.state == ns.STATE.SEARCHING then
        modeBar:Hide()
        savedFrameHeight = frame:GetHeight()
        tabContainer:Hide()
        checklistSection:Hide()
        frame:SetHeight(FRAME_H_COMPACT)
        statusText:SetText("Searching...")
        actionBtn:SetText("Searching...")
        actionBtn:Disable()

    elseif ns.state == ns.STATE.READY then
        modeBar:Hide()
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
            actionBtn:SetText("Buy " .. (ref.needed or item.qty) .. "x " .. itemName)
            actionBtn:Enable()
        end

    elseif ns.state == ns.STATE.CONFIRMING then
        modeBar:Hide()
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
        if ns.mode == "restock" then
            if not ns.currentProfile then
                ns.Print("No profile selected — create one with the + button.")
                return
            end
            local skipped = 0
            for catIdx, cat in ipairs(CATEGORIES) do
                for itemIdx, item in ipairs(cat.items) do
                    if item.enabled and not item.header then
                        local key = catIdx .. "_" .. itemIdx
                        local row = categoryRows[catIdx][itemIdx]
                        local qty = (row and row.toBuyBox and tonumber(row.toBuyBox:GetText())) or (ns.toBuy[key] or 0)
                        ns.toBuy[key] = qty
                        if qty > 0 then
                            ns.activeItems[#ns.activeItems + 1] = { catIdx = catIdx, itemIdx = itemIdx, needed = qty }
                        else
                            skipped = skipped + 1
                        end
                    end
                end
            end
            if #ns.activeItems == 0 then
                ns.Print("Nothing to buy — guild bank is fully stocked for this profile.")
                ns.Log("Guild bank fully stocked. No items queued.", 0.4, 1, 0.4)
                return
            end
            if skipped > 0 then
                ns.Log(skipped .. " item(s) skipped — already at target stock.", 1, 0.82, 0)
            end
        else
            for catIdx, cat in ipairs(CATEGORIES) do
                for itemIdx, item in ipairs(cat.items) do
                    if item.enabled and not item.header then
                        ns.activeItems[#ns.activeItems + 1] = { catIdx = catIdx, itemIdx = itemIdx, needed = item.qty }
                    end
                end
            end
            if #ns.activeItems == 0 then
                ns.Print("No items selected — enable at least one.")
                return
            end
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
        ns.pendingQty     = ref.needed or item.qty
        ns.state = ns.STATE.CONFIRMING
        UpdateUI()
        C_AuctionHouse.StartCommoditiesPurchase(ns.pendingItemID, ns.pendingQty)
    end
end)

stopBtn:SetScript("OnClick", function()
    frame:Hide()
end)
