local ADDON_NAME, ns = ...
local AceGUI = LibStub("AceGUI-3.0")
local CATEGORIES = ns.CATEGORIES
local ui = ns.ui

-- ============================================================
-- Log frame  (raw WoW frame; AceGUI has no colored-text widget)
-- ============================================================
local logFrame = CreateFrame("ScrollingMessageFrame", "GuildBankRestockLogFrame", UIParent)
logFrame:SetFading(false)
logFrame:SetMaxLines(500)
logFrame:SetFontObject(GameFontNormalSmall)
logFrame:SetJustifyH("LEFT")
logFrame:SetInsertMode("TOP")
logFrame:EnableMouseWheel(true)
logFrame:Hide()

local logScrollbarUpdating = false
local logScrollbar, logExportBtn

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

ns.AppendLogEntry = function(msg, r, g, b)
    logFrame:AddMessage(msg, r or 1, g or 1, b or 1)
end

-- ============================================================
-- Category scroll + log frame helpers
-- ============================================================
local categoryScroll

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

ns.ReleaseCategoryScroll = ReleaseCategoryScroll
ns.DetachLogFrame        = DetachLogFrame

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
-- Forward declarations
-- ============================================================
local BuildCategoryContent, BuildAllItemsContent, BuildLogContent, BuildAboutContent
local SelectTab
local contentGroup  -- assigned below after function definitions

-- ============================================================
-- Build category tab content  (rebuilt on every tab select)
-- ============================================================
BuildCategoryContent = function(catIdx)
    ReleaseCategoryScroll()
    contentGroup:ReleaseChildren()
    DetachLogFrame()

    local cat = CATEGORIES[catIdx]
    if not cat then return end

    local function AddBtn(parent, text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        if width then btn:SetWidth(width) else btn:SetAutoWidth(true) end
        btn:SetCallback("OnClick", onClick)
        parent:AddChild(btn)
        return btn
    end

    local function RankLabel(label, rank)
        return ui.currentRankFilter == rank and ("|cffffd100" .. label .. "|r") or label
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
                local rankOk = not item2.rank or ui.currentRankFilter == nil or item2.rank == ui.currentRankFilter
                if rankOk then
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
                local rankOk = not item2.rank or ui.currentRankFilter == nil or item2.rank == ui.currentRankFilter
                if rankOk then
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
        ui.currentRankFilter = 1
        ns.SaveRankFilter(1)
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("Rank 2", 2), nil, function()
        ui.currentRankFilter = 2
        ns.SaveRankFilter(2)
        BuildCategoryContent(catIdx)
    end)

    AddBtn(btnBar, RankLabel("All Ranks", nil), nil, function()
        ui.currentRankFilter = nil
        ns.SaveRankFilter(nil)
        BuildCategoryContent(catIdx)
    end)

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

    AddBtn(searchBar, "Start Search", nil, ns.StartSearch)

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

    local function ItemIsVisible(iItem)
        if iItem.rank and ui.currentRankFilter ~= nil and iItem.rank ~= ui.currentRankFilter then
            return false
        end
        return true
    end

    local editBoxes = {}
    for i, item in ipairs(cat.items) do
        if item.header then
            local anyVisible = false
            for j = i + 1, #cat.items do
                if cat.items[j].header then break end
                if ItemIsVisible(cat.items[j]) then
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

        elseif ItemIsVisible(item) then
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
        return ui.currentRankFilter == rank and ("|cffffd100" .. label .. "|r") or label
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
                        or ns.IsProfileIncluded(ci, ii) or ui.showAllProfileItems
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
                        or ns.IsProfileIncluded(ci, ii) or ui.showAllProfileItems
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
        ui.currentRankFilter = 1; ns.SaveRankFilter(1); BuildAllItemsContent()
    end)
    AddBtn(btnBar, RankLabel("Rank 2", 2), nil, function()
        ui.currentRankFilter = 2; ns.SaveRankFilter(2); BuildAllItemsContent()
    end)
    AddBtn(btnBar, RankLabel("All Ranks", nil), nil, function()
        ui.currentRankFilter = nil; ns.SaveRankFilter(nil); BuildAllItemsContent()
    end)

    if ns.mode == "restock" and ns.currentProfile then
        AddBtn(btnBar, ui.showAllProfileItems and "Hide Extra" or "Add Items", nil, function()
            ui.showAllProfileItems = not ui.showAllProfileItems
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
    AddBtn(searchBar, "Start Search", nil, ns.StartSearch)

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
        local visibleItems = {}
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local rankOk = not item.rank or ui.currentRankFilter == nil or item.rank == ui.currentRankFilter
                if rankOk then
                    local show
                    if ns.mode == "restock" and ns.currentProfile then
                        show = ns.IsProfileIncluded(catIdx, itemIdx) or ui.showAllProfileItems
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
            exportFrame:SetHeight(400)
            exportFrame:SetLayout("Fill")

            local editBox = AceGUI:Create("MultiLineEditBox")
            editBox:SetLabel("")
            editBox:SetNumLines(20)
            editBox:DisableButton(true)
            editBox:SetText(table.concat(lines, "\n"))
            exportFrame:AddChild(editBox)

            exportFrame:SetCallback("OnClose", function(widget) AceGUI:Release(widget) end)
        end)
    end

    logFrame:SetParent(content)
    logFrame:ClearAllPoints()
    logFrame:SetPoint("TOPLEFT",    content, "TOPLEFT",     0,   0)
    logFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -20, 20)
    logFrame:Show()

    logScrollbar:SetParent(content)
    logScrollbar:ClearAllPoints()
    logScrollbar:SetPoint("TOPRIGHT",    content, "TOPRIGHT",    0,   0)
    logScrollbar:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0,  20)
    logScrollbar:Show()

    logExportBtn:SetParent(content)
    logExportBtn:ClearAllPoints()
    logExportBtn:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
    logExportBtn:Show()

    local max = logFrame:GetMaxScrollRange() or 0
    logScrollbarUpdating = true
    logScrollbar:SetMinMaxValues(0, max)
    logScrollbar:SetValue(max - logFrame:GetScrollOffset())
    logScrollbarUpdating = false
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

    Body("|cffffd700Guild Bank Restock|r  |cffaaaaaa" .. ui.version .. "|r\n")
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
-- AceGUI content group (fills the right side of the window)
-- ============================================================
contentGroup = AceGUI:Create("SimpleGroup")
contentGroup:SetLayout("List")
contentGroup.frame:SetParent(ui.mainFrame)
contentGroup.frame:ClearAllPoints()
contentGroup.frame:SetPoint("TOPLEFT",     ui.mainFrame, "TOPLEFT",     172, -36)
contentGroup.frame:SetPoint("BOTTOMRIGHT", ui.mainFrame, "BOTTOMRIGHT",  -18,  32)
ui.contentGroup = contentGroup

-- ============================================================
-- SelectTab: highlight active sidebar button and rebuild content
-- ============================================================
SelectTab = function(idx)
    local focused = GetCurrentKeyboardFocus and GetCurrentKeyboardFocus()
    if focused then focused:ClearFocus() end

    for _, btn in pairs(ui.sidebarButtons) do
        btn:SetNormalFontObject(GameFontNormal)
        btn:UnlockHighlight()
    end
    if ui.sidebarButtons[idx] then
        ui.sidebarButtons[idx]:SetNormalFontObject(GameFontHighlight)
        ui.sidebarButtons[idx]:LockHighlight()
    end
    ui.currentCatIdx = idx
    if idx == ui.LOG_TAB then
        BuildLogContent()
    elseif idx == ui.ABOUT_TAB then
        BuildAboutContent()
    elseif idx == ui.ALL_TAB then
        BuildAllItemsContent()
    else
        BuildCategoryContent(idx)
    end
end
ns.SelectTab = SelectTab
