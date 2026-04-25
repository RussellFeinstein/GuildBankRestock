local ADDON_NAME, ns = ...
local AceGUI = LibStub("AceGUI-3.0")
local CATEGORIES = ns.CATEGORIES

-- ============================================================
-- Local state
-- ============================================================
local mainFrame
local contentGroup
local sidebarPanel
local sidebarButtons = {}
local statusBar
local logFrame
local logScrollbar
local logExportBtn
local logScrollbarUpdating = false
local currentCatIdx        = 1
local currentRankFilter    = nil
local suppressStopMessage  = false
local guildCtxBtn, personalCtxBtn
local categoryScroll
local showAllProfileItems  = false

-- Sidebar controls for mode / profile / scan (created in sidebar do-block)
local sidebarBulkBtn, sidebarRestockBtn
local sidebarProfileNav, sidebarProfileLabel, sidebarProfileDelBtn, sidebarProfileActions
local sidebarScanRow, sidebarScanStatus
local categoryBtns = {}

local _version  = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "?"
local LOG_TAB   = #CATEGORIES + 1
local ABOUT_TAB = #CATEGORIES + 2
local ALL_TAB   = #CATEGORIES + 3

-- Forward declarations
local BuildCategoryContent, BuildLogContent, BuildAboutContent, BuildAllItemsContent
local ShowTabView, ShowStatusView, UpdateUI, StartSearch
local SelectTab, RefreshSidebar

local function SetStatusText(text)
    if statusBar then statusBar:SetText(text or "") end
end

-- ============================================================
-- Log frame  (raw — AceGUI has no colored-text scroll widget)
-- ============================================================
logFrame = CreateFrame("ScrollingMessageFrame", "GuildBankRestockLogFrame", UIParent)
logFrame:SetFading(false)
logFrame:SetMaxLines(500)
logFrame:SetFontObject(GameFontNormalSmall)
logFrame:SetJustifyH("LEFT")
logFrame:SetInsertMode("TOP")
logFrame:EnableMouseWheel(true)
logFrame:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then self:ScrollUp() else self:ScrollDown() end
    if logScrollbar then
        logScrollbarUpdating = true
        local max = self:GetMaxScrollRange() or 0
        logScrollbar:SetMinMaxValues(0, max)
        logScrollbar:SetValue(max - self:GetScrollOffset())
        logScrollbarUpdating = false
    end
end)
logFrame:Hide()

ns.AppendLogEntry = function(msg, r, g, b)
    logFrame:AddMessage(msg, r or 1, g or 1, b or 1)
end

local function ReleaseCategoryScroll()
    categoryScroll = nil  -- actual release handled by contentGroup:ReleaseChildren()
end

local function DetachLogFrame()
    if logFrame:GetParent() ~= UIParent then
        logFrame:Hide()
        logFrame:SetParent(UIParent)
    end
    if logScrollbar then
        logScrollbar:Hide()
        logScrollbar:SetParent(UIParent)
    end
    if logExportBtn then
        logExportBtn:Hide()
        logExportBtn:SetParent(UIParent)
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
-- Static popup for save-as profile
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
            if ns.context == "personal" then
                ns.Print("Nothing to buy — you're fully stocked for this profile.")
                ns.Log("Fully stocked. No items queued.", 0.4, 1, 0.4)
            else
                ns.Print("Nothing to buy — guild bank is fully stocked for this profile.")
                ns.Log("Guild bank fully stocked. No items queued.", 0.4, 1, 0.4)
            end
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
-- TSM price helpers
-- ============================================================
local function GetTSMPrice(itemID)
    if not TSM_API then return nil end
    local itemString = "i:" .. itemID
    local ok, price = pcall(TSM_API.GetCustomPriceValue, "DBMarket", itemString)
    if ok and type(price) == "number" and price > 0 then
        return price  -- copper
    end
    return nil
end

local function FormatGold(copper)
    if not copper or copper <= 0 then return "—" end
    local gold = copper / 10000
    if gold >= 100 then
        return string.format("%dg", math.floor(gold + 0.5))
    else
        return string.format("%.1fg", gold)
    end
end

-- ============================================================
-- Build category tab content  (rebuilt on every tab select)
-- ============================================================
BuildCategoryContent = function(catIdx)
    ReleaseCategoryScroll()
    contentGroup:ReleaseChildren()
    DetachLogFrame()

    local cat = CATEGORIES[catIdx]
    if not cat then return end

    -- Helper: add a standard button to a parent widget.
    -- Pass width=nil to auto-size to the label text.
    local function AddBtn(parent, text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        if width then
            btn:SetWidth(width)
        else
            btn:SetAutoWidth(true)
        end
        btn:SetCallback("OnClick", onClick)
        parent:AddChild(btn)
        return btn
    end

    local function RankLabel(label, rank)
        return currentRankFilter == rank and ("|cffffd100" .. label .. "|r") or label
    end

    -- ── Column header row ─────────────────────────────────────
    local headerRow = AceGUI:Create("SimpleGroup")
    headerRow:SetLayout("Flow")
    headerRow:SetFullWidth(true)

    local itemHeader = AceGUI:Create("Label")
    itemHeader:SetText("|cffffd100Item|r")
    itemHeader:SetRelativeWidth(ns.mode == "restock" and 0.27 or 0.38)
    headerRow:AddChild(itemHeader)

    if ns.mode == "restock" then
        local th = AceGUI:Create("Label")
        th:SetText("|cffffd100Target|r")
        th:SetRelativeWidth(0.07)
        headerRow:AddChild(th)

        local ibh = AceGUI:Create("Label")
        ibh:SetText("|cffffd100" .. (ns.context == "personal" and "In Bags" or "In Bank") .. "|r")
        ibh:SetRelativeWidth(0.07)
        headerRow:AddChild(ibh)

        local bh = AceGUI:Create("Label")
        bh:SetText("|cffffd100To Buy|r")
        bh:SetRelativeWidth(0.07)
        headerRow:AddChild(bh)
    else
        local qh = AceGUI:Create("Label")
        qh:SetText("|cffffd100Qty|r")
        qh:SetRelativeWidth(0.10)
        headerRow:AddChild(qh)
    end

    local mkth = AceGUI:Create("Label")
    mkth:SetText("|cffffd100Mkt Price|r")
    mkth:SetRelativeWidth(0.13)
    mkth.label:SetJustifyH("CENTER")
    headerRow:AddChild(mkth)

    local esth = AceGUI:Create("Label")
    esth:SetText("|cffffd100Est g|r")
    esth:SetRelativeWidth(0.12)
    esth.label:SetJustifyH("CENTER")
    headerRow:AddChild(esth)

    local mgh = AceGUI:Create("Label")
    mgh:SetText("|cffffd100Max g|r")
    mgh:SetRelativeWidth(0.12)
    headerRow:AddChild(mgh)

    -- ── Button bar row 1: Select All / None / Rank filters ──
    local btnBar = AceGUI:Create("SimpleGroup")
    btnBar:SetLayout("Flow")
    btnBar:SetFullWidth(true)

    AddBtn(btnBar, "Select All", nil, function()
        for i2, item2 in ipairs(cat.items) do
            if not item2.header then
                local visible = ns.mode ~= "restock" or not ns.currentProfile
                    or ns.IsProfileIncluded(catIdx, i2) or showAllProfileItems
                if visible then
                    item2.enabled = true
                    ns.SaveItem(catIdx, i2)
                    if ns.mode == "restock" and ns.currentProfile then
                        ns.SetProfileIncluded(catIdx, i2, true)
                    end
                end
            end
        end
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, "Select None", nil, function()
        for i2, item2 in ipairs(cat.items) do
            if not item2.header then
                local visible = ns.mode ~= "restock" or not ns.currentProfile
                    or ns.IsProfileIncluded(catIdx, i2) or showAllProfileItems
                if visible then
                    item2.enabled = false
                    ns.SaveItem(catIdx, i2)
                    if ns.mode == "restock" and ns.currentProfile then
                        ns.SetProfileIncluded(catIdx, i2, false)
                    end
                end
            end
        end
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("Rank 1", 1), nil, function()
        currentRankFilter = 1
        ns.SaveRankFilter(1)
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("Rank 2", 2), nil, function()
        currentRankFilter = 2
        ns.SaveRankFilter(2)
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("All Ranks", nil), nil, function()
        currentRankFilter = nil
        ns.SaveRankFilter(nil)
        BuildCategoryContent(catIdx)
    end)

    if ns.mode == "restock" and ns.currentProfile then
        AddBtn(btnBar, showAllProfileItems and "Hide Extra" or "Add Items", nil, function()
            showAllProfileItems = not showAllProfileItems
            BuildCategoryContent(catIdx)
        end)
    end

    contentGroup:AddChild(btnBar)

    -- ── Estimated total across all categories for this run ──
    local runEstTotal = 0
    for ci, ccat in ipairs(CATEGORIES) do
        for ii, citem in ipairs(ccat.items) do
            if not citem.header and citem.enabled then
                local price = GetTSMPrice(citem.id)
                if price then
                    local qty = ns.mode == "restock"
                        and math.max(0, ns.toBuy[ci .. "_" .. ii] or 0)
                        or (citem.qty or 1)
                    runEstTotal = runEstTotal + price * qty
                end
            end
        end
    end

    -- ── Button bar row 2: right-aligned Est Run / Budget / Start Search ──
    local searchBar = AceGUI:Create("SimpleGroup")
    searchBar:SetLayout("Flow")
    searchBar:SetFullWidth(true)

    local spacer = AceGUI:Create("Label")
    spacer:SetRelativeWidth(0.5)
    spacer:SetText("")
    searchBar:AddChild(spacer)

    local runTotalLabel = AceGUI:Create("Label")
    runTotalLabel:SetText(TSM_API
        and ("|cffffd100Est Run:|r " .. FormatGold(runEstTotal))
        or "|cff888888Est Run: (no TSM)|r")
    runTotalLabel:SetWidth(150)
    searchBar:AddChild(runTotalLabel)

    local budgetLabel = AceGUI:Create("Label")
    budgetLabel:SetText("Budget:")
    budgetLabel:SetWidth(50)
    searchBar:AddChild(budgetLabel)

    local budgetBox = AceGUI:Create("EditBox")
    budgetBox:SetWidth(60)
    budgetBox:SetLabel("")
    budgetBox:SetText(tostring(ns.budget))
    budgetBox:DisableButton(true)
    budgetBox:SetCallback("OnEnterPressed", function(_, _, text)
        local v = math.max(0, tonumber(text) or 0)
        budgetBox:SetText(tostring(v))
        ns.budget = v
        ns.ContextDB().budget = v
    end)
    searchBar:AddChild(budgetBox)

    AddBtn(searchBar, "Start Search", nil, StartSearch)

    contentGroup:AddChild(headerRow)

    -- ── Scrollable item list (fills remaining height) ─────────
    categoryScroll = AceGUI:Create("ScrollFrame")
    local scroll = categoryScroll
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    contentGroup:AddChild(scroll)
    -- AceGUI List layout sets TOPLEFT only; extend to bottom leaving room for searchBar
    scroll.frame:SetPoint("BOTTOMRIGHT", contentGroup.content, "BOTTOMRIGHT", 0, 32)

    contentGroup:AddChild(searchBar)
    searchBar.frame:ClearAllPoints()
    searchBar.frame:SetPoint("BOTTOMLEFT",  contentGroup.content, "BOTTOMLEFT",  0, 0)
    searchBar.frame:SetPoint("BOTTOMRIGHT", contentGroup.content, "BOTTOMRIGHT", 0, 0)

    local function ItemIsVisible(iIdx, iItem)
        if iItem.rank and currentRankFilter ~= nil and iItem.rank ~= currentRankFilter then
            return false
        end
        if ns.mode == "restock" and ns.currentProfile then
            if not ns.IsProfileIncluded(catIdx, iIdx) and not showAllProfileItems then
                return false
            end
        end
        return true
    end

    local editBoxes = {}
    for i, item in ipairs(cat.items) do
        if item.header then
            local anyVisible = false
            for j = i + 1, #cat.items do
                if cat.items[j].header then break end
                if ItemIsVisible(j, cat.items[j]) then
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

        elseif ItemIsVisible(i, item) then
            local rowGroup = AceGUI:Create("SimpleGroup")
            rowGroup:SetLayout("Flow")
            rowGroup:SetFullWidth(true)

            local cb = AceGUI:Create("CheckBox")
            cb:SetRelativeWidth(ns.mode == "restock" and 0.27 or 0.38)
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
                if ns.mode == "restock" and ns.currentProfile then
                    ns.SetProfileIncluded(catIdx, i, val)
                    if not val then
                        BuildCategoryContent(catIdx)
                    end
                end
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
                targetBox:SetRelativeWidth(0.07)
                targetBox:SetLabel("")
                targetBox:SetText(tostring(ns.GetProfileTarget(catIdx, i)))
                targetBox:DisableButton(true)
                targetBox:SetMaxLetters(3)

                local inBankBox = AceGUI:Create("EditBox")
                inBankBox:SetRelativeWidth(0.07)
                inBankBox:SetLabel("")
                inBankBox:SetText(tostring(ns.GetStock(item.id)))
                inBankBox:DisableButton(true)
                inBankBox:SetMaxLetters(3)
                inBankBox:SetDisabled(true)

                local toBuyBox = AceGUI:Create("EditBox")
                toBuyBox:SetRelativeWidth(0.07)
                toBuyBox:SetLabel("")
                toBuyBox:SetText(tostring(ns.toBuy[catIdx .. "_" .. i] or 0))
                toBuyBox:DisableButton(true)
                toBuyBox:SetMaxLetters(3)

                local function ApplyTarget(text)
                    local v = math.max(0, tonumber(text) or 0)
                    targetBox:SetText(tostring(v))
                    ns.SetProfileTarget(catIdx, i, v)
                    local needed = math.max(0, v - ns.GetStock(item.id))
                    ns.toBuy[catIdx .. "_" .. i] = needed
                    toBuyBox:SetText(tostring(needed))
                end

                targetBox:SetCallback("OnEnterPressed", function(_, _, text)
                    ApplyTarget(text)
                end)

                targetBox:SetCallback("OnEditFocusLost", function(widget)
                    ApplyTarget(widget:GetText())
                end)

                toBuyBox:SetCallback("OnEnterPressed", function(_, _, text)
                    local v = math.max(0, tonumber(text) or 0)
                    ns.toBuy[catIdx .. "_" .. i] = v
                    BuildCategoryContent(catIdx)
                end)

                rowGroup:AddChild(targetBox)
                rowGroup:AddChild(inBankBox)
                rowGroup:AddChild(toBuyBox)
                editBoxes[#editBoxes + 1] = targetBox.editbox
                editBoxes[#editBoxes + 1] = toBuyBox.editbox
            else
                local qty = AceGUI:Create("EditBox")
                qty:SetRelativeWidth(0.10)
                qty:SetLabel("")
                qty:SetText(tostring(item.qty))
                qty:SetMaxLetters(3)
                qty:DisableButton(true)
                qty:SetCallback("OnEnterPressed", function(_, _, text)
                    local v = tonumber(text) or 1
                    if v < 1 then v = 1 end
                    item.qty = v
                    ns.SaveItem(catIdx, i)
                    BuildCategoryContent(catIdx)
                end)
                rowGroup:AddChild(qty)
                editBoxes[#editBoxes + 1] = qty.editbox
            end

            -- TSM market price and estimated cost for this item
            local tsmPrice = GetTSMPrice(item.id)
            local buyQty = ns.mode == "restock" and (ns.toBuy[catIdx .. "_" .. i] or 0) or (item.qty or 1)

            local mktLabel = AceGUI:Create("Label")
            mktLabel:SetRelativeWidth(0.13)
            mktLabel:SetText(FormatGold(tsmPrice))
            mktLabel.label:SetJustifyH("CENTER")
            rowGroup:AddChild(mktLabel)

            local estLabel = AceGUI:Create("Label")
            estLabel:SetRelativeWidth(0.12)
            estLabel:SetText(tsmPrice and FormatGold(tsmPrice * buyQty) or "—")
            estLabel.label:SetJustifyH("CENTER")
            rowGroup:AddChild(estLabel)

            local maxPriceBox = AceGUI:Create("EditBox")
            maxPriceBox:SetRelativeWidth(0.12)
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
            editBoxes[#editBoxes + 1] = maxPriceBox.editbox

            scroll:AddChild(rowGroup)
        end
    end

    -- ── Keyboard navigation ────────────────────────────────────
    -- editBoxes is row-major: restock has 3 cols (target,toBuy,maxPrice),
    -- bulk has 2 cols (qty,maxPrice). UP/DOWN move by column; LEFT/RIGHT
    -- move within the row; TAB/Shift-TAB move linearly.
    local colsPerRow = ns.mode == "restock" and 3 or 2
    for idx, eb in ipairs(editBoxes) do
        eb:SetScript("OnKeyDown", function(self, key)
            local col = (idx - 1) % colsPerRow  -- 0-based column index
            local dest
            if key == "TAB" then
                self:SetPropagateKeyboardInput(false)
                dest = IsShiftKeyDown() and (editBoxes[idx - 1] or editBoxes[#editBoxes])
                                        or  (editBoxes[idx + 1] or editBoxes[1])
            elseif key == "RIGHT" then
                self:SetPropagateKeyboardInput(false)
                if col < colsPerRow - 1 then dest = editBoxes[idx + 1] end
            elseif key == "LEFT" then
                self:SetPropagateKeyboardInput(false)
                if col > 0 then dest = editBoxes[idx - 1] end
            elseif key == "DOWN" then
                self:SetPropagateKeyboardInput(false)
                -- next row same column; wrap to first row
                dest = editBoxes[idx + colsPerRow] or editBoxes[col + 1]
            elseif key == "UP" then
                self:SetPropagateKeyboardInput(false)
                -- prev row same column; wrap to last row
                dest = editBoxes[idx - colsPerRow] or editBoxes[#editBoxes - (colsPerRow - 1 - col)]
            elseif key == "RETURN" or key == "NUMPADENTER" then
                self:SetPropagateKeyboardInput(false)
                return
            else
                self:SetPropagateKeyboardInput(true)
                return
            end
            if dest then dest:SetFocus(); dest:HighlightText() end
        end)
    end
end

-- ============================================================
-- Build "Selected" tab — all checked/profile items across every category
-- ============================================================
BuildAllItemsContent = function()
    ReleaseCategoryScroll()
    contentGroup:ReleaseChildren()
    DetachLogFrame()

    local function AddBtn(parent, text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        if width then btn:SetWidth(width) else btn:SetAutoWidth(true) end
        btn:SetCallback("OnClick", onClick)
        parent:AddChild(btn)
        return btn
    end

    local function RankLabel(label, rank)
        return currentRankFilter == rank and ("|cffffd100" .. label .. "|r") or label
    end

    -- ── Column header row ─────────────────────────────────────
    local headerRow = AceGUI:Create("SimpleGroup")
    headerRow:SetLayout("Flow")
    headerRow:SetFullWidth(true)

    local itemHeader = AceGUI:Create("Label")
    itemHeader:SetText("|cffffd100Item|r")
    itemHeader:SetRelativeWidth(ns.mode == "restock" and 0.27 or 0.38)
    headerRow:AddChild(itemHeader)

    if ns.mode == "restock" then
        local th = AceGUI:Create("Label") th:SetText("|cffffd100Target|r") th:SetRelativeWidth(0.07) headerRow:AddChild(th)
        local ibh = AceGUI:Create("Label") ibh:SetText("|cffffd100" .. (ns.context == "personal" and "In Bags" or "In Bank") .. "|r") ibh:SetRelativeWidth(0.07) headerRow:AddChild(ibh)
        local bh = AceGUI:Create("Label") bh:SetText("|cffffd100To Buy|r") bh:SetRelativeWidth(0.07) headerRow:AddChild(bh)
    else
        local qh = AceGUI:Create("Label") qh:SetText("|cffffd100Qty|r") qh:SetRelativeWidth(0.10) headerRow:AddChild(qh)
    end

    local mkth = AceGUI:Create("Label") mkth:SetText("|cffffd100Mkt Price|r") mkth:SetRelativeWidth(0.13) mkth.label:SetJustifyH("CENTER") headerRow:AddChild(mkth)
    local esth = AceGUI:Create("Label") esth:SetText("|cffffd100Est g|r") esth:SetRelativeWidth(0.12) esth.label:SetJustifyH("CENTER") headerRow:AddChild(esth)
    local mgh = AceGUI:Create("Label") mgh:SetText("|cffffd100Max g|r") mgh:SetRelativeWidth(0.12) headerRow:AddChild(mgh)

    -- ── Button bar ────────────────────────────────────────────
    local btnBar = AceGUI:Create("SimpleGroup")
    btnBar:SetLayout("Flow")
    btnBar:SetFullWidth(true)

    AddBtn(btnBar, "Select All", nil, function()
        for ci, ccat in ipairs(CATEGORIES) do
            for ii, citem in ipairs(ccat.items) do
                if not citem.header then
                    local visible = ns.mode ~= "restock" or not ns.currentProfile
                        or ns.IsProfileIncluded(ci, ii) or showAllProfileItems
                    if visible then
                        citem.enabled = true
                        ns.SaveItem(ci, ii)
                        if ns.mode == "restock" and ns.currentProfile then
                            ns.SetProfileIncluded(ci, ii, true)
                        end
                    end
                end
            end
        end
        BuildAllItemsContent()
    end)

    AddBtn(btnBar, "Select None", nil, function()
        for ci, ccat in ipairs(CATEGORIES) do
            for ii, citem in ipairs(ccat.items) do
                if not citem.header then
                    local visible = ns.mode ~= "restock" or not ns.currentProfile
                        or ns.IsProfileIncluded(ci, ii) or showAllProfileItems
                    if visible then
                        citem.enabled = false
                        ns.SaveItem(ci, ii)
                        if ns.mode == "restock" and ns.currentProfile then
                            ns.SetProfileIncluded(ci, ii, false)
                        end
                    end
                end
            end
        end
        BuildAllItemsContent()
    end)

    AddBtn(btnBar, RankLabel("Rank 1", 1), nil, function()
        currentRankFilter = 1; ns.SaveRankFilter(1); BuildAllItemsContent()
    end)
    AddBtn(btnBar, RankLabel("Rank 2", 2), nil, function()
        currentRankFilter = 2; ns.SaveRankFilter(2); BuildAllItemsContent()
    end)
    AddBtn(btnBar, RankLabel("All Ranks", nil), nil, function()
        currentRankFilter = nil; ns.SaveRankFilter(nil); BuildAllItemsContent()
    end)

    if ns.mode == "restock" and ns.currentProfile then
        AddBtn(btnBar, showAllProfileItems and "Hide Extra" or "Add Items", nil, function()
            showAllProfileItems = not showAllProfileItems
            BuildAllItemsContent()
        end)
    end

    contentGroup:AddChild(btnBar)

    -- ── Estimated run total ───────────────────────────────────
    local runEstTotal = 0
    for ci, ccat in ipairs(CATEGORIES) do
        for ii, citem in ipairs(ccat.items) do
            if not citem.header and citem.enabled then
                local price = GetTSMPrice(citem.id)
                if price then
                    local qty = ns.mode == "restock"
                        and math.max(0, ns.toBuy[ci .. "_" .. ii] or 0)
                        or (citem.qty or 1)
                    runEstTotal = runEstTotal + price * qty
                end
            end
        end
    end

    -- ── Search bar ────────────────────────────────────────────
    local searchBar = AceGUI:Create("SimpleGroup")
    searchBar:SetLayout("Flow")
    searchBar:SetFullWidth(true)

    local spacer = AceGUI:Create("Label") spacer:SetRelativeWidth(0.5) spacer:SetText("") searchBar:AddChild(spacer)

    local runTotalLabel = AceGUI:Create("Label")
    runTotalLabel:SetText(TSM_API
        and ("|cffffd100Est Run:|r " .. FormatGold(runEstTotal))
        or "|cff888888Est Run: (no TSM)|r")
    runTotalLabel:SetWidth(150)
    searchBar:AddChild(runTotalLabel)

    local budgetLabel = AceGUI:Create("Label") budgetLabel:SetText("Budget:") budgetLabel:SetWidth(50) searchBar:AddChild(budgetLabel)

    local budgetBox = AceGUI:Create("EditBox")
    budgetBox:SetWidth(60)
    budgetBox:SetLabel("")
    budgetBox:SetText(tostring(ns.budget))
    budgetBox:DisableButton(true)
    budgetBox:SetCallback("OnEnterPressed", function(_, _, text)
        local v = math.max(0, tonumber(text) or 0)
        budgetBox:SetText(tostring(v))
        ns.budget = v
        ns.ContextDB().budget = v
    end)
    searchBar:AddChild(budgetBox)
    AddBtn(searchBar, "Start Search", nil, StartSearch)

    contentGroup:AddChild(headerRow)

    -- ── Scrollable item list ──────────────────────────────────
    categoryScroll = AceGUI:Create("ScrollFrame")
    local scroll = categoryScroll
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    contentGroup:AddChild(scroll)
    scroll.frame:SetPoint("BOTTOMRIGHT", contentGroup.content, "BOTTOMRIGHT", 0, 32)

    contentGroup:AddChild(searchBar)
    searchBar.frame:ClearAllPoints()
    searchBar.frame:SetPoint("BOTTOMLEFT",  contentGroup.content, "BOTTOMLEFT",  0, 0)
    searchBar.frame:SetPoint("BOTTOMRIGHT", contentGroup.content, "BOTTOMRIGHT", 0, 0)

    local editBoxes = {}
    local anyItems  = false

    for catIdx, cat in ipairs(CATEGORIES) do
        -- Collect visible items for this category
        local visibleItems = {}
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local rankOk = not item.rank or currentRankFilter == nil or item.rank == currentRankFilter
                if rankOk then
                    local show
                    if ns.mode == "restock" and ns.currentProfile then
                        show = ns.IsProfileIncluded(catIdx, itemIdx) or showAllProfileItems
                    else
                        show = item.enabled
                    end
                    if show then
                        visibleItems[#visibleItems + 1] = { itemIdx = itemIdx, item = item }
                    end
                end
            end
        end

        if #visibleItems > 0 then
            anyItems = true
            local catHeading = AceGUI:Create("Heading")
            catHeading:SetText(cat.name)
            catHeading:SetFullWidth(true)
            scroll:AddChild(catHeading)

            for _, entry in ipairs(visibleItems) do
                local i    = entry.itemIdx
                local item = entry.item

                local rowGroup = AceGUI:Create("SimpleGroup")
                rowGroup:SetLayout("Flow")
                rowGroup:SetFullWidth(true)

                local cb = AceGUI:Create("CheckBox")
                cb:SetRelativeWidth(ns.mode == "restock" and 0.27 or 0.38)
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
                    if ns.mode == "restock" and ns.currentProfile then
                        ns.SetProfileIncluded(catIdx, i, val)
                        if not val then BuildAllItemsContent() end
                    end
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
                    targetBox:SetRelativeWidth(0.07) targetBox:SetLabel("") targetBox:DisableButton(true) targetBox:SetMaxLetters(3)
                    targetBox:SetText(tostring(ns.GetProfileTarget(catIdx, i)))

                    local inBankBox = AceGUI:Create("EditBox")
                    inBankBox:SetRelativeWidth(0.07) inBankBox:SetLabel("") inBankBox:DisableButton(true) inBankBox:SetMaxLetters(3) inBankBox:SetDisabled(true)
                    inBankBox:SetText(tostring(ns.GetStock(item.id)))

                    local toBuyBox = AceGUI:Create("EditBox")
                    toBuyBox:SetRelativeWidth(0.07) toBuyBox:SetLabel("") toBuyBox:DisableButton(true) toBuyBox:SetMaxLetters(3)
                    toBuyBox:SetText(tostring(ns.toBuy[catIdx .. "_" .. i] or 0))

                    local function ApplyTarget(text)
                        local v = math.max(0, tonumber(text) or 0)
                        targetBox:SetText(tostring(v))
                        ns.SetProfileTarget(catIdx, i, v)
                        local needed = math.max(0, v - ns.GetStock(item.id))
                        ns.toBuy[catIdx .. "_" .. i] = needed
                        toBuyBox:SetText(tostring(needed))
                    end
                    targetBox:SetCallback("OnEnterPressed", function(_, _, text) ApplyTarget(text) end)
                    targetBox:SetCallback("OnEditFocusLost", function(widget) ApplyTarget(widget:GetText()) end)
                    toBuyBox:SetCallback("OnEnterPressed", function(_, _, text)
                        local v = math.max(0, tonumber(text) or 0)
                        ns.toBuy[catIdx .. "_" .. i] = v
                        BuildAllItemsContent()
                    end)

                    rowGroup:AddChild(targetBox)
                    rowGroup:AddChild(inBankBox)
                    rowGroup:AddChild(toBuyBox)
                    editBoxes[#editBoxes + 1] = targetBox.editbox
                    editBoxes[#editBoxes + 1] = toBuyBox.editbox
                else
                    local qty = AceGUI:Create("EditBox")
                    qty:SetRelativeWidth(0.10) qty:SetLabel("") qty:SetMaxLetters(3) qty:DisableButton(true)
                    qty:SetText(tostring(item.qty))
                    qty:SetCallback("OnEnterPressed", function(_, _, text)
                        local v = tonumber(text) or 1
                        if v < 1 then v = 1 end
                        item.qty = v
                        ns.SaveItem(catIdx, i)
                        BuildAllItemsContent()
                    end)
                    rowGroup:AddChild(qty)
                    editBoxes[#editBoxes + 1] = qty.editbox
                end

                local tsmPrice = GetTSMPrice(item.id)
                local buyQty   = ns.mode == "restock" and (ns.toBuy[catIdx .. "_" .. i] or 0) or (item.qty or 1)

                local mktLabel = AceGUI:Create("Label") mktLabel:SetRelativeWidth(0.13) mktLabel:SetText(FormatGold(tsmPrice)) mktLabel.label:SetJustifyH("CENTER") rowGroup:AddChild(mktLabel)
                local estLabel = AceGUI:Create("Label") estLabel:SetRelativeWidth(0.12) estLabel:SetText(tsmPrice and FormatGold(tsmPrice * buyQty) or "—") estLabel.label:SetJustifyH("CENTER") rowGroup:AddChild(estLabel)

                local maxPriceBox = AceGUI:Create("EditBox")
                maxPriceBox:SetRelativeWidth(0.12) maxPriceBox:SetLabel("") maxPriceBox:SetMaxLetters(6) maxPriceBox:DisableButton(true)
                maxPriceBox:SetText(item.maxPrice and item.maxPrice > 0 and tostring(item.maxPrice) or "")
                maxPriceBox:SetCallback("OnEnterPressed", function(_, _, text)
                    local v = tonumber(text) or 0
                    if v < 0 then v = 0 end
                    item.maxPrice = v > 0 and v or nil
                    maxPriceBox:SetText(v > 0 and tostring(v) or "")
                    ns.SaveItem(catIdx, i)
                end)
                rowGroup:AddChild(maxPriceBox)
                editBoxes[#editBoxes + 1] = maxPriceBox.editbox

                scroll:AddChild(rowGroup)
            end
        end
    end

    if not anyItems then
        local emptyLabel = AceGUI:Create("Label")
        emptyLabel:SetText(ns.mode == "restock"
            and "|cff888888No items in profile. Use 'Add Items' or check items in each category tab.|r"
            or  "|cff888888No items selected. Check items in each category tab.|r")
        emptyLabel:SetFullWidth(true)
        scroll:AddChild(emptyLabel)
    end

    -- ── Keyboard navigation ────────────────────────────────────
    local colsPerRow = ns.mode == "restock" and 3 or 2
    for idx, eb in ipairs(editBoxes) do
        eb:SetScript("OnKeyDown", function(self, key)
            local col  = (idx - 1) % colsPerRow
            local dest
            if key == "TAB" then
                self:SetPropagateKeyboardInput(false)
                dest = IsShiftKeyDown() and (editBoxes[idx - 1] or editBoxes[#editBoxes])
                                        or  (editBoxes[idx + 1] or editBoxes[1])
            elseif key == "RIGHT" then
                self:SetPropagateKeyboardInput(false)
                if col < colsPerRow - 1 then dest = editBoxes[idx + 1] end
            elseif key == "LEFT" then
                self:SetPropagateKeyboardInput(false)
                if col > 0 then dest = editBoxes[idx - 1] end
            elseif key == "DOWN" then
                self:SetPropagateKeyboardInput(false)
                dest = editBoxes[idx + colsPerRow] or editBoxes[col + 1]
            elseif key == "UP" then
                self:SetPropagateKeyboardInput(false)
                dest = editBoxes[idx - colsPerRow] or editBoxes[#editBoxes - (colsPerRow - 1 - col)]
            elseif key == "RETURN" or key == "NUMPADENTER" then
                self:SetPropagateKeyboardInput(false)
                return
            else
                self:SetPropagateKeyboardInput(true)
                return
            end
            if dest then dest:SetFocus(); dest:HighlightText() end
        end)
    end
end

-- ============================================================
-- Build log tab content
-- ============================================================
BuildLogContent = function()
    ReleaseCategoryScroll()
    contentGroup:ReleaseChildren()
    DetachLogFrame()

    local content = contentGroup.content

    -- Create scrollbar once
    if not logScrollbar then
        logScrollbar = CreateFrame("Slider", "GBRLogScrollBar", UIParent, "UIPanelScrollBarTemplate")
        logScrollbar:SetWidth(16)
        logScrollbar:SetMinMaxValues(0, 0)
        logScrollbar:SetValueStep(1)
        logScrollbar:SetObeyStepOnDrag(true)

        local function SyncScrollbar()
            logScrollbarUpdating = true
            local max = logFrame:GetMaxScrollRange() or 0
            logScrollbar:SetMinMaxValues(0, max)
            logScrollbar:SetValue(max - logFrame:GetScrollOffset())
            logScrollbarUpdating = false
        end

        _G["GBRLogScrollBarScrollUpButton"]:SetScript("OnClick", function()
            logFrame:ScrollUp()
            SyncScrollbar()
        end)
        _G["GBRLogScrollBarScrollDownButton"]:SetScript("OnClick", function()
            logFrame:ScrollDown()
            SyncScrollbar()
        end)

        logScrollbar:SetScript("OnValueChanged", function(self, value)
            if logScrollbarUpdating then return end
            local _, max = self:GetMinMaxValues()
            logFrame:SetScrollOffset(math.floor((max - value) + 0.5))
        end)
    end

    -- Create export button once
    if not logExportBtn then
        logExportBtn = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
        logExportBtn:SetSize(80, 22)
        logExportBtn:SetText("Export")
        logExportBtn:SetScript("OnClick", function()
            local lines = {}
            for _, entry in ipairs(ns.log) do
                lines[#lines + 1] = entry.msg
            end
            local exportFrame = AceGUI:Create("Frame")
            exportFrame:SetTitle("Guild Bank Restock — Log Export")
            exportFrame:SetWidth(520)
            exportFrame:SetHeight(420)
            exportFrame:SetLayout("Fill")
            local editBox = AceGUI:Create("MultiLineEditBox")
            editBox:SetLabel("Select all (Ctrl+A) and copy (Ctrl+C):")
            editBox:SetText(table.concat(lines, "\n"))
            editBox:DisableButton(true)
            editBox:SetFullWidth(true)
            editBox:SetFullHeight(true)
            exportFrame:AddChild(editBox)
            C_Timer.After(0.05, function()
                editBox.editBox:SetFocus()
                editBox.editBox:HighlightText()
            end)
        end)
    end

    -- Position log frame (leave room for scrollbar on right, export button on top)
    logFrame:SetParent(content)
    logFrame:ClearAllPoints()
    logFrame:SetPoint("TOPLEFT",     content, "TOPLEFT",     4, -30)
    logFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20,  4)
    logFrame:Show()

    -- Position scrollbar
    logScrollbar:SetParent(content)
    logScrollbar:ClearAllPoints()
    logScrollbar:SetPoint("TOPRIGHT",    content, "TOPRIGHT",    0, -16)
    logScrollbar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0,  16)
    logScrollbar:Show()

    -- Position export button
    logExportBtn:SetParent(content)
    logExportBtn:ClearAllPoints()
    logExportBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    logExportBtn:Show()

    -- Sync scrollbar to current position
    local max = logFrame:GetMaxScrollRange() or 0
    logScrollbar:SetMinMaxValues(0, max)
    logScrollbar:SetValue(max - logFrame:GetScrollOffset())
end

-- ============================================================
-- About tab content
-- ============================================================
BuildAboutContent = function()
    ReleaseCategoryScroll()
    contentGroup:ReleaseChildren()
    DetachLogFrame()

    local scroll = AceGUI:Create("ScrollFrame")
    scroll:SetLayout("List")
    scroll:SetFullWidth(true)
    scroll:SetFullHeight(true)
    contentGroup:AddChild(scroll)

    local function Heading(text)
        local lbl = AceGUI:Create("Label")
        lbl:SetText("|cffffd700" .. text .. "|r")
        lbl:SetFontObject(GameFontNormalHuge)
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    end

    local function Body(text)
        local lbl = AceGUI:Create("Label")
        lbl:SetText(text)
        lbl:SetFontObject(GameFontNormalLarge)
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    end

    local function Spacer()
        local lbl = AceGUI:Create("Label")
        lbl:SetText(" ")
        lbl:SetFullWidth(true)
        scroll:AddChild(lbl)
    end

    Body("|cffffd700Guild Bank Restock|r  |cffaaaaaa" .. _version .. "|r\n")
    Body("Automates buying raid consumables from the Auction House via Auctionator. Switch between |cffffd700Guild Bank|r mode (restock the bank for your raid) and |cffffd700Personal|r mode (restock your own bags). Set your targets once — the addon handles searching and buying for you.")

    Spacer()
    Heading("Who Is It For?")
    Body("|cffffd700Guild Bank mode|r — Officers and managers responsible for raid supply. Scan the guild bank, see what's short, and let the addon buy the difference.\n\n|cffffd700Personal mode|r — Any player keeping their own consumables stocked. Scan your bags, bank, and warband bank, then buy whatever you're running low on.")

    Spacer()
    Heading("Features")
    Body(
        "|cffaaaaaa•|r  Categories: Gems, Enchants, Potions, Flasks, Oils, Food, Runes\n" ..
        "|cffaaaaaa•|r  Guild Bank and Personal contexts with separate settings and profiles\n" ..
        "|cffaaaaaa•|r  Per-item quantity targets with optional max-price caps\n" ..
        "|cffaaaaaa•|r  Bulk Mode — buy a fixed quantity of each selected item\n" ..
        "|cffaaaaaa•|r  Restock Mode — scan inventory first, only buy what's missing\n" ..
        "|cffaaaaaa•|r  Budget cap to limit total spend per session\n" ..
        "|cffaaaaaa•|r  Named profiles for different raid comps or roles\n" ..
        "|cffaaaaaa•|r  Persistent activity log with export\n" ..
        "|cffaaaaaa•|r  Minimap button for quick access"
    )

    Spacer()
    Heading("Getting Started")
    Body(
        "1. Open the addon with |cffaaaaaa/rs|r or click the minimap button\n" ..
        "2. Choose |cffffd700Guild|r or |cffffd700Personal|r at the top of the sidebar\n" ..
        "3. Check the items you want and set quantities\n" ..
        "4. Open the Auction House, then click |cffffd700Start Search|r\n" ..
        "5. In Restock mode: open your bank first and click |cffffd700Scan for Restock|r"
    )

    Spacer()
    Heading("Slash Commands")
    Body(
        "|cffaaaaaa/restock|r  or  |cffaaaaaa/rs|r — Open the window\n" ..
        "|cffaaaaaa/restock stop|r — Close the window\n" ..
        "|cffaaaaaa/restock version|r — Print the current version"
    )

    Spacer()
    Heading("Requirements")
    Body("|cffffd700Auctionator|r must be installed and enabled.")

    Spacer()
    Heading("Author")
    Body("Made by |cffffd700Katorri|r")
end

-- ============================================================
-- Show the tab view  (IDLE state)
-- ============================================================
ShowTabView = function()
    sidebarPanel:Show()
    SelectTab(currentCatIdx)
end

-- ============================================================
-- Show the status view  (SEARCHING / READY / CONFIRMING)
-- ============================================================
ShowStatusView = function(statusMsg, btnText, btnEnabled, btnHandler)
    ReleaseCategoryScroll()
    DetachLogFrame()
    sidebarPanel:Hide()
    contentGroup:ReleaseChildren()

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

    contentGroup:AddChild(container)
end

-- ============================================================
-- UpdateUI  (state machine)
-- ============================================================
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
    RefreshSidebar()
    if ns.state == ns.STATE.IDLE and currentCatIdx ~= LOG_TAB and currentCatIdx ~= ABOUT_TAB then
        if currentCatIdx == ALL_TAB then
            BuildAllItemsContent()
        else
            BuildCategoryContent(currentCatIdx)
        end
    end
end

ns.RefreshProfileUI = function()
    showAllProfileItems = false
    RefreshSidebar()
    if ns.state == ns.STATE.IDLE and currentCatIdx ~= LOG_TAB and currentCatIdx ~= ABOUT_TAB then
        if currentCatIdx == ALL_TAB then
            BuildAllItemsContent()
        else
            BuildCategoryContent(currentCatIdx)
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

-- Draggable title bar
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
titleText:SetText("Guild Bank Restock v" .. _version)

-- Close button
local closeButton = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeButton:SetPoint("TOPRIGHT", mainFrame, "TOPRIGHT", 2, 2)
closeButton:SetScript("OnClick", function() mainFrame:Hide() end)

-- Resize grip (bottom-right corner)
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

-- Status bar
statusBar = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statusBar:SetPoint("BOTTOMLEFT",  mainFrame, "BOTTOMLEFT",  12, 10)
statusBar:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -30, 10)
statusBar:SetJustifyH("LEFT")

-- ESC closes the window
_G["GuildBankRestockMainFrame"] = mainFrame
tinsert(UISpecialFrames, "GuildBankRestockMainFrame")

-- HookScript so Hide() from ANY path (ESC, X button, /rs stop) fires reset
mainFrame:HookScript("OnHide", function()
    if not suppressStopMessage then
        ns.Reset()
        ns.Print("Stopped.")
        ns.Log("Stopped.", 1, 0.6, 0.6)
    end
    suppressStopMessage = false
end)

-- Sidebar panel (left, 120 px wide)
sidebarPanel = CreateFrame("Frame", nil, mainFrame)
sidebarPanel:SetPoint("TOPLEFT",    mainFrame, "TOPLEFT",    14, -36)
sidebarPanel:SetPoint("BOTTOMLEFT", mainFrame, "BOTTOMLEFT", 14,  32)
sidebarPanel:SetWidth(150)

-- Sidebar (built once; dynamic section positions are set by RefreshSidebar)
do
    local btnH  = 26
    local pad   = 2
    local ctxH  = 22
    local modeH = 22

    -- ── Context row: Guild | Personal ────────────────────────
    guildCtxBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    guildCtxBtn:SetSize(71, ctxH)
    guildCtxBtn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, -4)
    guildCtxBtn:SetText("Guild")
    guildCtxBtn:SetScript("OnClick", function()
        if ns.context == "guild" then return end
        ns.SwitchContext("guild")
        SelectTab(currentCatIdx)
    end)

    personalCtxBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    personalCtxBtn:SetSize(73, ctxH)
    personalCtxBtn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 75, -4)
    personalCtxBtn:SetText("Personal")
    personalCtxBtn:SetScript("OnClick", function()
        if ns.context == "personal" then return end
        ns.SwitchContext("personal")
        SelectTab(currentCatIdx)
    end)

    -- ── Mode row: Bulk | Restock ──────────────────────────────
    sidebarBulkBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    sidebarBulkBtn:SetSize(71, modeH)
    sidebarBulkBtn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, -(4 + ctxH + 4))
    sidebarBulkBtn:SetText("Bulk")
    sidebarBulkBtn:SetScript("OnClick", function()
        if ns.mode == "bulk" then return end
        ns.mode = "bulk"
        ns.ContextDB().mode = "bulk"
        showAllProfileItems = false
        RefreshSidebar()
        SelectTab(currentCatIdx)
    end)

    sidebarRestockBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    sidebarRestockBtn:SetSize(73, modeH)
    sidebarRestockBtn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 75, -(4 + ctxH + 4))
    sidebarRestockBtn:SetText("Restock")
    sidebarRestockBtn:SetScript("OnClick", function()
        if ns.mode == "restock" then return end
        ns.mode = "restock"
        ns.ContextDB().mode = "restock"
        showAllProfileItems = false
        ns.RecalculateToBuy()
        RefreshSidebar()
        SelectTab(currentCatIdx)
    end)

    -- ── Profile nav: << Name >> (shown when mode = restock) ──
    sidebarProfileNav = CreateFrame("Frame", nil, sidebarPanel)
    sidebarProfileNav:SetSize(146, 22)
    sidebarProfileNav:Hide()

    local prevBtn = CreateFrame("Button", nil, sidebarProfileNav, "UIPanelButtonTemplate")
    prevBtn:SetSize(24, 20)
    prevBtn:SetPoint("LEFT", sidebarProfileNav, "LEFT", 0, 0)
    prevBtn:SetText("<<")
    prevBtn:SetScript("OnClick", function()
        local names = ns.GetProfileNames()
        if #names < 2 then return end
        local idx = 1
        for i, n in ipairs(names) do if n == ns.currentProfile then idx = i break end end
        idx = idx - 1; if idx < 1 then idx = #names end
        ns.SetActiveProfile(names[idx])
    end)

    sidebarProfileLabel = sidebarProfileNav:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sidebarProfileLabel:SetPoint("LEFT",  prevBtn,           "RIGHT",  2,   0)
    sidebarProfileLabel:SetPoint("RIGHT", sidebarProfileNav, "RIGHT", -26,  0)
    sidebarProfileLabel:SetJustifyH("CENTER")
    sidebarProfileLabel:SetText("(no profile)")

    local nextBtn = CreateFrame("Button", nil, sidebarProfileNav, "UIPanelButtonTemplate")
    nextBtn:SetSize(24, 20)
    nextBtn:SetPoint("RIGHT", sidebarProfileNav, "RIGHT", 0, 0)
    nextBtn:SetText(">>")
    nextBtn:SetScript("OnClick", function()
        local names = ns.GetProfileNames()
        if #names < 2 then return end
        local idx = 1
        for i, n in ipairs(names) do if n == ns.currentProfile then idx = i break end end
        idx = idx % #names + 1
        ns.SetActiveProfile(names[idx])
    end)

    -- ── Profile actions: New | Delete | Save ─────────────────
    sidebarProfileActions = CreateFrame("Frame", nil, sidebarPanel)
    sidebarProfileActions:SetSize(146, 22)
    sidebarProfileActions:Hide()

    local newBtn = CreateFrame("Button", nil, sidebarProfileActions, "UIPanelButtonTemplate")
    newBtn:SetSize(46, 20)
    newBtn:SetPoint("LEFT", sidebarProfileActions, "LEFT", 0, 0)
    newBtn:SetText("New")
    newBtn:SetScript("OnClick", function() StaticPopup_Show("GUILDBANKRESTOCK_NEW_PROFILE") end)

    sidebarProfileDelBtn = CreateFrame("Button", nil, sidebarProfileActions, "UIPanelButtonTemplate")
    sidebarProfileDelBtn:SetSize(50, 20)
    sidebarProfileDelBtn:SetPoint("LEFT", sidebarProfileActions, "LEFT", 48, 0)
    sidebarProfileDelBtn:SetText("Delete")
    sidebarProfileDelBtn:SetScript("OnClick", function()
        if ns.currentProfile then ns.DeleteProfile(ns.currentProfile) end
    end)

    local saveBtn = CreateFrame("Button", nil, sidebarProfileActions, "UIPanelButtonTemplate")
    saveBtn:SetSize(46, 20)
    saveBtn:SetPoint("LEFT", sidebarProfileActions, "LEFT", 100, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function() StaticPopup_Show("GUILDBANKRESTOCK_SAVE_PROFILE") end)

    -- ── Scan row (shown when context = personal) ──────────────
    sidebarScanRow = CreateFrame("Frame", nil, sidebarPanel)
    sidebarScanRow:SetSize(146, 36)
    sidebarScanRow:Hide()

    local scanBtn = CreateFrame("Button", nil, sidebarScanRow, "UIPanelButtonTemplate")
    scanBtn:SetSize(146, 20)
    scanBtn:SetPoint("TOPLEFT", sidebarScanRow, "TOPLEFT", 0, 0)
    scanBtn:SetText("Scan Inventory")
    scanBtn:SetScript("OnClick", function()
        if ns.DoPersonalScan then ns.DoPersonalScan() end
    end)

    sidebarScanStatus = sidebarScanRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sidebarScanStatus:SetPoint("TOPLEFT", sidebarScanRow, "TOPLEFT", 2, -22)
    sidebarScanStatus:SetWidth(142)
    sidebarScanStatus:SetJustifyH("LEFT")
    sidebarScanStatus:SetText("|cffff8844Not scanned|r")

    -- ── Category buttons (positions updated by RefreshSidebar) ─
    local defaultY = -(4 + ctxH + 4 + modeH + 10)
    for i, cat in ipairs(CATEGORIES) do
        local btn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
        btn:SetSize(146, btnH)
        btn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, defaultY)
        btn:SetText(cat.name)
        local idx = i
        btn:SetScript("OnClick", function() SelectTab(idx) end)
        sidebarButtons[idx] = btn
        categoryBtns[i]     = btn
        defaultY = defaultY - btnH - pad
    end

    -- ── Bottom buttons (fixed anchors) ────────────────────────
    local aboutBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    aboutBtn:SetSize(146, btnH)
    aboutBtn:SetPoint("BOTTOMLEFT", sidebarPanel, "BOTTOMLEFT", 2, (btnH + pad) * 2 + 4)
    aboutBtn:SetText("About")
    aboutBtn:SetScript("OnClick", function() SelectTab(ABOUT_TAB) end)
    sidebarButtons[ABOUT_TAB] = aboutBtn

    local selectedBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    selectedBtn:SetSize(146, btnH)
    selectedBtn:SetPoint("BOTTOMLEFT", sidebarPanel, "BOTTOMLEFT", 2, btnH + pad + 4)
    selectedBtn:SetText("Selected")
    selectedBtn:SetScript("OnClick", function() SelectTab(ALL_TAB) end)
    sidebarButtons[ALL_TAB] = selectedBtn

    local logBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    logBtn:SetSize(146, btnH)
    logBtn:SetPoint("BOTTOMLEFT", sidebarPanel, "BOTTOMLEFT", 2, 4)
    logBtn:SetText("Log")
    logBtn:SetScript("OnClick", function() SelectTab(LOG_TAB) end)
    sidebarButtons[LOG_TAB] = logBtn
end

-- ============================================================
-- RefreshSidebar  (updates highlights and repositions dynamic sections)
-- ============================================================
RefreshSidebar = function()
    if not sidebarBulkBtn then return end

    -- Guild / Personal highlight
    local isPersonal = ns.context == "personal"
    guildCtxBtn:SetNormalFontObject(isPersonal and GameFontNormal or GameFontHighlight)
    personalCtxBtn:SetNormalFontObject(isPersonal and GameFontHighlight or GameFontNormal)
    if isPersonal then
        guildCtxBtn:UnlockHighlight(); personalCtxBtn:LockHighlight()
    else
        guildCtxBtn:LockHighlight(); personalCtxBtn:UnlockHighlight()
    end

    -- Bulk / Restock highlight
    local isBulk = ns.mode == "bulk"
    sidebarBulkBtn:SetNormalFontObject(isBulk and GameFontHighlight or GameFontNormal)
    sidebarRestockBtn:SetNormalFontObject(isBulk and GameFontNormal or GameFontHighlight)
    if isBulk then
        sidebarBulkBtn:LockHighlight(); sidebarRestockBtn:UnlockHighlight()
    else
        sidebarBulkBtn:UnlockHighlight(); sidebarRestockBtn:LockHighlight()
    end

    -- y starts just below the two fixed rows (context + mode) plus their gaps
    local y = -(4 + 22 + 4 + 22 + 6)  -- -58

    -- Profile section (restock only)
    local showProfile = ns.mode == "restock"
    if showProfile then
        sidebarProfileLabel:SetText(ns.currentProfile or "(no profile)")
        if ns.currentProfile then sidebarProfileDelBtn:Enable() else sidebarProfileDelBtn:Disable() end
        sidebarProfileNav:ClearAllPoints()
        sidebarProfileNav:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, y)
        sidebarProfileNav:Show()
        y = y - 26
        sidebarProfileActions:ClearAllPoints()
        sidebarProfileActions:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, y)
        sidebarProfileActions:Show()
        y = y - 26
    else
        sidebarProfileNav:Hide()
        sidebarProfileActions:Hide()
    end

    -- Scan section (personal only)
    local showScan = isPersonal
    if showScan then
        if ns.personalScanned and ns.personalScanTime then
            sidebarScanStatus:SetText("|cff00ff00Scanned " .. ns.personalScanTime .. "|r")
        elseif ns.personalScanned then
            sidebarScanStatus:SetText("|cff00ff00Scanned|r")
        else
            sidebarScanStatus:SetText("|cffff8844Not scanned|r")
        end
        sidebarScanRow:ClearAllPoints()
        sidebarScanRow:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, y)
        sidebarScanRow:Show()
        y = y - 40
    else
        sidebarScanRow:Hide()
    end

    y = y - 6  -- separator gap before category buttons

    for _, btn in ipairs(categoryBtns) do
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, y)
        y = y - 28
    end
end

-- AceGUI content group (fills the right side of the window)
contentGroup = AceGUI:Create("SimpleGroup")
contentGroup:SetLayout("List")
contentGroup.frame:SetParent(mainFrame)
contentGroup.frame:ClearAllPoints()
contentGroup.frame:SetPoint("TOPLEFT",     mainFrame, "TOPLEFT",     172, -36)
contentGroup.frame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT",  -18,  32)

-- SelectTab: highlight active sidebar button and rebuild content
SelectTab = function(idx)
    -- Flush any pending edit box value so it isn't lost on tab switch
    local focused = GetCurrentKeyboardFocus and GetCurrentKeyboardFocus()
    if focused then focused:ClearFocus() end

    for _, btn in pairs(sidebarButtons) do
        btn:SetNormalFontObject(GameFontNormal)
        btn:UnlockHighlight()
    end
    if sidebarButtons[idx] then
        sidebarButtons[idx]:SetNormalFontObject(GameFontHighlight)
        sidebarButtons[idx]:LockHighlight()
    end
    currentCatIdx = idx
    if idx == LOG_TAB then
        BuildLogContent()
    elseif idx == ABOUT_TAB then
        BuildAboutContent()
    elseif idx == ALL_TAB then
        BuildAllItemsContent()
    else
        BuildCategoryContent(idx)
    end
end

mainFrame:Hide()
ns.frame = mainFrame  -- raw WoW frame; callers use ns.frame directly (no .frame indirection)

-- ============================================================
-- Apply saved settings  (called by GBR:OnInitialize)
-- ============================================================
ns.ApplySettingsToUI = function()
    local g = ns.addon and ns.addon.db and ns.addon.db.global
    if g and g.windowWidth and g.windowHeight then
        mainFrame:SetSize(g.windowWidth, g.windowHeight)
    end
    local ctxDB = ns.addon and ns.addon.db and ns.ContextDB and ns.ContextDB()
    currentRankFilter = ctxDB and ctxDB.rankFilter or nil
    RefreshSidebar()
end

ns.RefreshSidebar = function() RefreshSidebar() end
