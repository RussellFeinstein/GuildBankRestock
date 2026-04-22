local ADDON_NAME, ns = ...
local AceGUI = LibStub("AceGUI-3.0")
local CATEGORIES = ns.CATEGORIES

-- ============================================================
-- Local state
-- ============================================================
local frame                -- AceGUI Frame widget
local tabGroup             -- AceGUI TabGroup (recreated on state transitions)
local logFrame             -- raw ScrollingMessageFrame
local currentCatIdx    = 1
local currentRankFilter    = nil
local suppressStopMessage  = false

local LOG_TAB = #CATEGORIES + 1

-- Forward declarations
local BuildCategoryContent, BuildLogContent
local ShowTabView, ShowStatusView, UpdateUI, StartSearch

-- ============================================================
-- Log frame  (raw — AceGUI has no colored-text scroll widget)
-- ============================================================
logFrame = CreateFrame("ScrollingMessageFrame", "GuildBankRestockLogFrame", UIParent)
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

local function DetachLogFrame()
    if logFrame:GetParent() ~= UIParent then
        logFrame:Hide()
        logFrame:SetParent(UIParent)
    end
end

-- ============================================================
-- Static popup for profile creation
-- ============================================================
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

-- ============================================================
-- Start search
-- ============================================================
StartSearch = function()
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
                    local qty = ns.toBuy[key] or 0
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
    ns.runStartMoney = GetMoney()
    ns.state = ns.STATE.SEARCHING
    UpdateUI()
    ns.Log("Search started: " .. #ns.activeItems .. " items." ..
        (ns.budget > 0 and ("  Budget: " .. ns.budget .. "g") or ""), 0.8, 0.8, 1)
    AuctionatorShoppingFrame:DoSearch(ns.BuildSearchStrings())
end

-- ============================================================
-- Build category tab content  (rebuilt on every tab select)
-- ============================================================
BuildCategoryContent = function(catIdx)
    tabGroup:ReleaseChildren()
    DetachLogFrame()

    local cat = CATEGORIES[catIdx]
    if not cat then return end

    -- Helper: add a standard button to a parent widget
    local function AddBtn(parent, text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetWidth(width)
        btn:SetCallback("OnClick", onClick)
        parent:AddChild(btn)
        return btn
    end

    -- Helper: apply gold color when rank/mode matches active filter
    local function RankLabel(label, rank)
        return currentRankFilter == rank and ("|cffffd100" .. label .. "|r") or label
    end

    local function ModeLabel(label, mode)
        return ns.mode == mode and ("|cffffd100" .. label .. "|r") or label
    end

    -- ── Mode row ──────────────────────────────────────────────
    local modeRow = AceGUI:Create("SimpleGroup")
    modeRow:SetLayout("Flow")
    modeRow:SetFullWidth(true)

    AddBtn(modeRow, ModeLabel("Bulk", "bulk"), 60, function()
        ns.mode = "bulk"
        ns.addon.db.global.mode = "bulk"
        BuildCategoryContent(catIdx)
    end)

    AddBtn(modeRow, ModeLabel("Restock", "restock"), 70, function()
        ns.mode = "restock"
        ns.addon.db.global.mode = "restock"
        ns.RecalculateToBuy()
        BuildCategoryContent(catIdx)
    end)

    tabGroup:AddChild(modeRow)

    -- ── Profile row (restock only) ────────────────────────────
    if ns.mode == "restock" then
        local profileRow = AceGUI:Create("SimpleGroup")
        profileRow:SetLayout("Flow")
        profileRow:SetFullWidth(true)

        local names = ns.GetProfileNames()

        AddBtn(profileRow, "<", 30, function()
            if #names < 2 then return end
            local idx = 1
            for i, n in ipairs(names) do if n == ns.currentProfile then idx = i break end end
            idx = idx - 1; if idx < 1 then idx = #names end
            ns.SetActiveProfile(names[idx])
        end)

        local profileLabel = AceGUI:Create("Label")
        profileLabel:SetText(ns.currentProfile or "(no profile)")
        profileLabel:SetWidth(110)
        profileRow:AddChild(profileLabel)

        AddBtn(profileRow, ">", 30, function()
            if #names < 2 then return end
            local idx = 1
            for i, n in ipairs(names) do if n == ns.currentProfile then idx = i break end end
            idx = idx % #names + 1
            ns.SetActiveProfile(names[idx])
        end)

        AddBtn(profileRow, "+", 30, function()
            StaticPopup_Show("GUILDBANKRESTOCK_NEW_PROFILE")
        end)

        local delBtn = AddBtn(profileRow, "-", 30, function()
            if ns.currentProfile then ns.DeleteProfile(ns.currentProfile) end
        end)
        delBtn:SetDisabled(not ns.currentProfile)

        tabGroup:AddChild(profileRow)
    end

    -- ── Column header row ─────────────────────────────────────
    local headerRow = AceGUI:Create("SimpleGroup")
    headerRow:SetLayout("Flow")
    headerRow:SetFullWidth(true)

    local itemHeader = AceGUI:Create("Label")
    itemHeader:SetText("|cffffd100Item|r")
    itemHeader:SetRelativeWidth(ns.mode == "restock" and 0.48 or 0.55)
    headerRow:AddChild(itemHeader)

    if ns.mode == "restock" then
        local th = AceGUI:Create("Label")
        th:SetText("|cffffd100Target|r")
        th:SetRelativeWidth(0.17)
        headerRow:AddChild(th)

        local bh = AceGUI:Create("Label")
        bh:SetText("|cffffd100To Buy|r")
        bh:SetRelativeWidth(0.17)
        headerRow:AddChild(bh)
    else
        local qh = AceGUI:Create("Label")
        qh:SetText("|cffffd100Qty|r")
        qh:SetRelativeWidth(0.20)
        headerRow:AddChild(qh)
    end

    local mgh = AceGUI:Create("Label")
    mgh:SetText("|cffffd100Max g|r")
    mgh:SetRelativeWidth(0.18)
    headerRow:AddChild(mgh)

    tabGroup:AddChild(headerRow)

    -- ── Button bar: All / None / R1 / R2 / Both / Budget / Start ──
    local btnBar = AceGUI:Create("SimpleGroup")
    btnBar:SetLayout("Flow")
    btnBar:SetFullWidth(true)

    AddBtn(btnBar, "All", 40, function()
        for i2, item2 in ipairs(cat.items) do
            if not item2.header then
                item2.enabled = true
                ns.SaveItem(catIdx, i2)
            end
        end
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, "None", 48, function()
        for i2, item2 in ipairs(cat.items) do
            if not item2.header then
                item2.enabled = false
                ns.SaveItem(catIdx, i2)
            end
        end
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("R1", 1), 34, function()
        currentRankFilter = 1
        ns.SaveRankFilter(1)
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("R2", 2), 34, function()
        currentRankFilter = 2
        ns.SaveRankFilter(2)
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("Both", nil), 44, function()
        currentRankFilter = nil
        ns.SaveRankFilter(nil)
        BuildCategoryContent(catIdx)
    end)

    -- Budget: inline label + editbox + Start button
    local budgetLabel = AceGUI:Create("Label")
    budgetLabel:SetText(" Budget:")
    budgetLabel:SetWidth(54)
    btnBar:AddChild(budgetLabel)

    local budgetBox = AceGUI:Create("EditBox")
    budgetBox:SetWidth(46)
    budgetBox:SetLabel("")
    budgetBox:SetText(tostring(ns.budget))
    budgetBox:DisableButton(true)
    budgetBox:SetCallback("OnEnterPressed", function(_, _, text)
        local v = math.max(0, tonumber(text) or 0)
        budgetBox:SetText(tostring(v))
        ns.budget = v
        ns.addon.db.global.budget = v
    end)
    btnBar:AddChild(budgetBox)

    AddBtn(btnBar, "Start", 52, StartSearch)

    tabGroup:AddChild(btnBar)

    -- ── Scrollable item list (fills remaining height) ─────────
    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    tabGroup:AddChild(scroll)

    for i, item in ipairs(cat.items) do
        if item.header then
            -- Only show header if at least one item below it passes the rank filter
            local anyVisible = false
            for j = i + 1, #cat.items do
                if cat.items[j].header then break end
                local jItem = cat.items[j]
                if not jItem.rank or currentRankFilter == nil or jItem.rank == currentRankFilter then
                    anyVisible = true
                    break
                end
            end
            if anyVisible then
                local heading = AceGUI:Create("Heading")
                heading:SetText(item.header)
                heading:SetFullWidth(true)
                scroll:AddChild(heading)
            end

        elseif not item.rank or currentRankFilter == nil or item.rank == currentRankFilter then
            local rowGroup = AceGUI:Create("SimpleGroup")
            rowGroup:SetLayout("Flow")
            rowGroup:SetFullWidth(true)

            local cb = AceGUI:Create("CheckBox")
            cb:SetRelativeWidth(ns.mode == "restock" and 0.48 or 0.55)
            cb:SetValue(item.enabled)
            cb:SetLabel("item:" .. item.id)

            local function TryLoadLink(attempts)
                local _, link = GetItemInfo(item.id)
                if link then
                    cb:SetLabel(link)
                    cb.itemLink = link
                elseif attempts < 10 then
                    C_Timer.After(0.5, function() TryLoadLink(attempts + 1) end)
                end
            end
            TryLoadLink(0)

            cb:SetCallback("OnValueChanged", function(_, _, val)
                item.enabled = val
                ns.SaveItem(catIdx, i)
            end)
            cb:SetCallback("OnEnter", function(widget)
                if widget.itemLink then
                    GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                    GameTooltip:SetHyperlink(widget.itemLink)
                    GameTooltip:Show()
                end
            end)
            cb:SetCallback("OnLeave", function() GameTooltip:Hide() end)
            rowGroup:AddChild(cb)

            if ns.mode == "restock" then
                local targetBox = AceGUI:Create("EditBox")
                targetBox:SetRelativeWidth(0.17)
                targetBox:SetLabel("")
                targetBox:SetText(tostring(ns.GetProfileTarget(catIdx, i)))
                targetBox:DisableButton(true)
                targetBox:SetMaxLetters(3)

                local toBuyBox = AceGUI:Create("EditBox")
                toBuyBox:SetRelativeWidth(0.17)
                toBuyBox:SetLabel("")
                toBuyBox:SetText(tostring(ns.toBuy[catIdx .. "_" .. i] or 0))
                toBuyBox:DisableButton(true)
                toBuyBox:SetMaxLetters(3)

                targetBox:SetCallback("OnEnterPressed", function(_, _, text)
                    local v = math.max(0, tonumber(text) or 0)
                    targetBox:SetText(tostring(v))
                    ns.SetProfileTarget(catIdx, i, v)
                    local inBank = ns.guildBankScanned and (ns.guildBankStock[item.id] or 0) or 0
                    local needed = math.max(0, v - inBank)
                    ns.toBuy[catIdx .. "_" .. i] = needed
                    toBuyBox:SetText(tostring(needed))
                end)

                toBuyBox:SetCallback("OnEnterPressed", function(_, _, text)
                    local v = math.max(0, tonumber(text) or 0)
                    toBuyBox:SetText(tostring(v))
                    ns.toBuy[catIdx .. "_" .. i] = v
                end)

                rowGroup:AddChild(targetBox)
                rowGroup:AddChild(toBuyBox)
            else
                local qty = AceGUI:Create("EditBox")
                qty:SetRelativeWidth(0.20)
                qty:SetLabel("")
                qty:SetText(tostring(item.qty))
                qty:SetMaxLetters(3)
                qty:DisableButton(true)
                qty:SetCallback("OnEnterPressed", function(_, _, text)
                    local v = tonumber(text) or 1
                    if v < 1 then v = 1 end
                    item.qty = v
                    qty:SetText(tostring(v))
                    ns.SaveItem(catIdx, i)
                end)
                rowGroup:AddChild(qty)
            end

            local maxPriceBox = AceGUI:Create("EditBox")
            maxPriceBox:SetRelativeWidth(0.18)
            maxPriceBox:SetLabel("")
            maxPriceBox:SetText(item.maxPrice and item.maxPrice > 0 and tostring(item.maxPrice) or "")
            maxPriceBox:SetMaxLetters(6)
            maxPriceBox:DisableButton(true)
            maxPriceBox:SetCallback("OnEnterPressed", function(_, _, text)
                local v = tonumber(text) or 0
                if v < 0 then v = 0 end
                item.maxPrice = v > 0 and v or nil
                maxPriceBox:SetText(v > 0 and tostring(v) or "")
                ns.SaveItem(catIdx, i)
            end)
            rowGroup:AddChild(maxPriceBox)

            scroll:AddChild(rowGroup)
        end
    end
end

-- ============================================================
-- Build log tab content
-- ============================================================
BuildLogContent = function()
    tabGroup:ReleaseChildren()
    logFrame:SetParent(tabGroup.content)
    logFrame:ClearAllPoints()
    logFrame:SetPoint("TOPLEFT",     tabGroup.content, "TOPLEFT",     4, -4)
    logFrame:SetPoint("BOTTOMRIGHT", tabGroup.content, "BOTTOMRIGHT", -4,  4)
    logFrame:Show()
end

-- ============================================================
-- Show the tab view  (IDLE state)
-- ============================================================
ShowTabView = function()
    DetachLogFrame()
    frame:ReleaseChildren()

    local tabs = {}
    for i, cat in ipairs(CATEGORIES) do
        tabs[#tabs + 1] = { value = tostring(i), text = cat.name }
    end
    tabs[#tabs + 1] = { value = "log", text = "Log" }

    tabGroup = AceGUI:Create("TabGroup")
    tabGroup:SetTabs(tabs)
    tabGroup:SetLayout("List")
    tabGroup:SetCallback("OnGroupSelected", function(_, _, group)
        DetachLogFrame()
        if group == "log" then
            currentCatIdx = LOG_TAB
            BuildLogContent()
        else
            currentCatIdx = tonumber(group) or 1
            BuildCategoryContent(currentCatIdx)
        end
    end)
    frame:AddChild(tabGroup)

    local tabVal = currentCatIdx == LOG_TAB and "log" or tostring(currentCatIdx)
    tabGroup:SelectTab(tabVal)
end

-- ============================================================
-- Show the status view  (SEARCHING / READY / CONFIRMING)
-- ============================================================
ShowStatusView = function(statusMsg, btnText, btnEnabled, btnHandler)
    DetachLogFrame()
    frame:ReleaseChildren()

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

    frame:AddChild(container)
end

-- ============================================================
-- UpdateUI  (state machine)
-- ============================================================
UpdateUI = function()
    if not frame then return end

    if ns.state == ns.STATE.IDLE then
        frame:SetStatusText("Select items and quantities, then click Start.")
        ShowTabView()

    elseif ns.state == ns.STATE.SEARCHING then
        frame:SetStatusText("Searching...")
        ShowStatusView("Searching...", "Searching...", false)

    elseif ns.state == ns.STATE.READY then
        local listPos, ref = ns.GetNextItem()
        if not listPos then
            frame:SetStatusText("|cff00ff00All items purchased!|r")
            ShowStatusView(
                "|cff00ff00All items purchased!|r",
                "Close", true,
                function()
                    ns.Log("All items purchased.", 0.4, 1, 0.4)
                    suppressStopMessage = true
                    ns.Reset()
                    frame.frame:Hide()
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

            frame:SetStatusText("Next: " .. itemName)
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
        frame:SetStatusText("Confirming purchase...")
        ShowStatusView("Confirming purchase...", "Please wait...", false)
    end
end
ns.UpdateUI = UpdateUI

-- ============================================================
-- Callbacks for Profiles.lua  (rebuild current tab from state)
-- ============================================================
ns.RefreshToBuyUI = function()
    if ns.state == ns.STATE.IDLE and currentCatIdx ~= LOG_TAB then
        BuildCategoryContent(currentCatIdx)
    end
end

ns.RefreshProfileUI = function()
    if ns.state == ns.STATE.IDLE and currentCatIdx ~= LOG_TAB then
        BuildCategoryContent(currentCatIdx)
    end
end

-- ============================================================
-- Main frame  (created at file load, starts hidden)
-- ============================================================
local _version = GetAddOnMetadata(ADDON_NAME, "Version") or "?"
frame = AceGUI:Create("Frame")
frame:SetTitle("Guild Bank Restock v" .. _version)
frame:SetWidth(440)
frame:SetHeight(560)
frame:SetLayout("Fill")

-- HookScript so frame.frame:Hide() from ANY path (ESC, X, /rs stop) fires reset
frame.frame:HookScript("OnHide", function()
    if not suppressStopMessage then
        ns.Reset()
        ns.Print("Stopped.")
        ns.Log("Stopped.", 1, 0.6, 0.6)
    end
    suppressStopMessage = false
end)

frame.frame:Hide()

ns.frame = frame  -- exposed as AceGUI widget; use ns.frame.frame for raw WoW frame ops

-- ============================================================
-- Apply saved settings  (called by GBR:OnInitialize)
-- ============================================================
ns.ApplySettingsToUI = function()
    currentRankFilter = ns.addon and ns.addon.db and ns.addon.db.global.rankFilter or nil
    -- ns.mode, ns.budget, ns.currentProfile already set by LoadSettings
end
