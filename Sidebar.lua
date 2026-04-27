local ADDON_NAME, ns = ...
local CATEGORIES = ns.CATEGORIES
local ui = ns.ui

local C_GREEN  = "|cff00ff00"
local C_ORANGE = "|cffff8844"

-- ============================================================
-- Sidebar panel (parented to main frame)
-- ============================================================
local sidebarPanel = CreateFrame("Frame", nil, ui.mainFrame)
sidebarPanel:SetPoint("TOPLEFT",    ui.mainFrame, "TOPLEFT",    14, -36)
sidebarPanel:SetPoint("BOTTOMLEFT", ui.mainFrame, "BOTTOMLEFT", 14,  32)
sidebarPanel:SetWidth(150)
ui.sidebarPanel = sidebarPanel

-- ============================================================
-- Widget locals (used by the do-block and RefreshSidebar)
-- ============================================================
local guildCtxBtn, personalCtxBtn
local sidebarBulkBtn, sidebarRestockBtn
local sidebarProfileNav, sidebarProfileLabel, sidebarProfileDelBtn, sidebarProfileActions
local sidebarScanRow, sidebarScanStatus, sidebarScanBtn, sidebarScanHint
local categoryBtns = {}

local RefreshSidebar  -- forward declaration; defined after the do-block

-- ============================================================
-- Build sidebar widgets
-- ============================================================
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
        ns.SelectTab(ui.currentCatIdx)
    end)

    personalCtxBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    personalCtxBtn:SetSize(73, ctxH)
    personalCtxBtn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 75, -4)
    personalCtxBtn:SetText("Personal")
    personalCtxBtn:SetScript("OnClick", function()
        if ns.context == "personal" then return end
        ns.SwitchContext("personal")
        ns.SelectTab(ui.currentCatIdx)
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
        ui.showAllProfileItems = false
        RefreshSidebar()
        ns.SelectTab(ui.currentCatIdx)
    end)

    sidebarRestockBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    sidebarRestockBtn:SetSize(73, modeH)
    sidebarRestockBtn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 75, -(4 + ctxH + 4))
    sidebarRestockBtn:SetText("Restock")
    sidebarRestockBtn:SetScript("OnClick", function()
        if ns.mode == "restock" then return end
        ns.mode = "restock"
        ns.ContextDB().mode = "restock"
        ui.showAllProfileItems = false
        ns.RecalculateToBuy()
        RefreshSidebar()
        ns.SelectTab(ui.currentCatIdx)
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

    sidebarScanBtn = CreateFrame("Button", nil, sidebarScanRow, "UIPanelButtonTemplate")
    sidebarScanBtn:SetSize(146, 20)
    sidebarScanBtn:SetPoint("TOPLEFT", sidebarScanRow, "TOPLEFT", 0, 0)
    sidebarScanBtn:SetText("Scan Inventory")
    sidebarScanBtn:SetScript("OnClick", function()
        if ns.DoPersonalScan then ns.DoPersonalScan() end
    end)

    sidebarScanStatus = sidebarScanRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sidebarScanStatus:SetPoint("TOPLEFT", sidebarScanRow, "TOPLEFT", 2, -22)
    sidebarScanStatus:SetWidth(142)
    sidebarScanStatus:SetJustifyH("LEFT")
    sidebarScanStatus:SetText(C_ORANGE .. "Not scanned|r")

    sidebarScanHint = sidebarPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sidebarScanHint:SetPoint("TOPLEFT", sidebarScanStatus, "BOTTOMLEFT", 0, -4)
    sidebarScanHint:SetWidth(140)
    sidebarScanHint:SetJustifyH("LEFT")
    sidebarScanHint:Hide()

    -- ── Category buttons (positions updated by RefreshSidebar) ─
    local defaultY = -(4 + ctxH + 4 + modeH + 10)
    for i, cat in ipairs(CATEGORIES) do
        if #cat.items > 0 then
            local btn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
            btn:SetSize(146, btnH)
            btn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, defaultY)
            btn:SetText(cat.name)
            local idx = i
            btn:SetScript("OnClick", function() ns.SelectTab(idx) end)
            ui.sidebarButtons[idx] = btn
            categoryBtns[i]        = btn
            defaultY = defaultY - btnH - pad
        end
    end

    -- ── Bottom buttons (fixed anchors) ────────────────────────
    local selectedBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    selectedBtn:SetSize(146, btnH)
    selectedBtn:SetPoint("BOTTOMLEFT", sidebarPanel, "BOTTOMLEFT", 2, (btnH + pad) * 2 + 4)
    selectedBtn:SetText("Selected")
    selectedBtn:SetScript("OnClick", function() ns.SelectTab(ui.ALL_TAB) end)
    ui.sidebarButtons[ui.ALL_TAB] = selectedBtn

    local aboutBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    aboutBtn:SetSize(146, btnH)
    aboutBtn:SetPoint("BOTTOMLEFT", sidebarPanel, "BOTTOMLEFT", 2, btnH + pad + 4)
    aboutBtn:SetText("About")
    aboutBtn:SetScript("OnClick", function() ns.SelectTab(ui.ABOUT_TAB) end)
    ui.sidebarButtons[ui.ABOUT_TAB] = aboutBtn

    local logBtn = CreateFrame("Button", nil, sidebarPanel, "UIPanelButtonTemplate")
    logBtn:SetSize(146, btnH)
    logBtn:SetPoint("BOTTOMLEFT", sidebarPanel, "BOTTOMLEFT", 2, 4)
    logBtn:SetText("Log")
    logBtn:SetScript("OnClick", function() ns.SelectTab(ui.LOG_TAB) end)
    ui.sidebarButtons[ui.LOG_TAB] = logBtn
end

-- ============================================================
-- RefreshSidebar  (updates highlights and repositions dynamic sections)
-- ============================================================
RefreshSidebar = function()
    if not sidebarBulkBtn then return end

    local isPersonal = ns.context == "personal"
    guildCtxBtn:SetNormalFontObject(isPersonal and GameFontNormal or GameFontHighlight)
    personalCtxBtn:SetNormalFontObject(isPersonal and GameFontHighlight or GameFontNormal)
    if isPersonal then
        guildCtxBtn:UnlockHighlight(); personalCtxBtn:LockHighlight()
    else
        guildCtxBtn:LockHighlight(); personalCtxBtn:UnlockHighlight()
    end

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

    -- Scan section (guild and personal)
    if isPersonal then
        if ns.personalScanned and ns.personalScanTime then
            sidebarScanStatus:SetText(C_GREEN .. "Scanned " .. ns.personalScanTime .. "|r")
        elseif ns.personalScanned then
            sidebarScanStatus:SetText(C_GREEN .. "Scanned|r")
        else
            sidebarScanStatus:SetText(C_ORANGE .. "Not scanned|r")
        end
        sidebarScanBtn:Show()
    else
        if ns.guildBankScanned and ns.guildBankScanTime then
            sidebarScanStatus:SetText(C_GREEN .. "Scanned " .. ns.guildBankScanTime .. "|r")
        elseif ns.guildBankScanned then
            sidebarScanStatus:SetText(C_GREEN .. "Scanned|r")
        else
            sidebarScanStatus:SetText(C_ORANGE .. "Not scanned|r")
        end
        sidebarScanBtn:Hide()
    end
    sidebarScanRow:ClearAllPoints()
    sidebarScanRow:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, y)
    sidebarScanRow:Show()
    y = y - 40

    local notScanned = (ns.context == "guild" and not ns.guildBankScanned)
                    or (ns.context == "personal" and not ns.personalScanned)
    if ns.mode == "restock" and notScanned then
        sidebarScanHint:SetText(ns.context == "guild"
            and "Open the guild bank\nto scan."
            or  "Open your bank\nto scan.")
        sidebarScanHint:Show()
        y = y - 28
    else
        sidebarScanHint:Hide()
    end

    y = y - 6  -- separator gap before category buttons

    for i = 1, #CATEGORIES do
        local btn = categoryBtns[i]
        if btn then
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", sidebarPanel, "TOPLEFT", 2, y)
            y = y - 28
        end
    end
end

ns.RefreshSidebar = function() RefreshSidebar() end
