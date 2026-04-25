local _, ns = ...

-- ============================================================
-- Personal inventory scanning  (bags + personal bank + warband bank)
-- Scan button attaches to BankFrame when the bank is opened.
-- ns.personalStock / ns.personalScanned declared in GuildBankRestock.lua
-- ============================================================

local personalScanBar
local personalScanBtn
local bankEventFrame = CreateFrame("Frame")

local function DoPersonalScan()
    ns.Print("Scanning personal inventory...")
    wipe(ns.personalStock)

    -- Player bags (backpack + 4 bag slots)
    for bagID = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID then
                local count = info.stackCount or info.itemCount or 1
                ns.personalStock[info.itemID] = (ns.personalStock[info.itemID] or 0) + count
            end
        end
    end

    -- Personal bank: main slots (BANK_CONTAINER = -1) + bank bag slots (5-11)
    local bankContainer = BANK_CONTAINER or -1
    for slot = 1, C_Container.GetContainerNumSlots(bankContainer) do
        local info = C_Container.GetContainerItemInfo(bankContainer, slot)
        if info and info.itemID then
            local count = info.stackCount or info.itemCount or 1
            ns.personalStock[info.itemID] = (ns.personalStock[info.itemID] or 0) + count
        end
    end
    for bagID = 5, 11 do
        local numSlots = C_Container.GetContainerNumSlots(bagID)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID then
                local count = info.stackCount or info.itemCount or 1
                ns.personalStock[info.itemID] = (ns.personalStock[info.itemID] or 0) + count
            end
        end
    end

    -- Warband bank (Account Bank, The War Within+)
    if C_AccountBank and C_AccountBank.GetNumAccountBankTabs then
        local ok, numTabs = pcall(C_AccountBank.GetNumAccountBankTabs)
        if ok and numTabs and numTabs > 0 then
            local numSlots = 98
            if C_AccountBank.GetNumAccountBankTabSlots then
                local ok2, n = pcall(C_AccountBank.GetNumAccountBankTabSlots)
                if ok2 and n then numSlots = n end
            end
            for tab = 1, numTabs do
                for slot = 1, numSlots do
                    local ok3, info = pcall(C_AccountBank.GetAccountBankItemInfo, tab, slot)
                    if ok3 and info and info.hyperlink then
                        local itemID = tonumber(info.hyperlink:match("item:(%d+)"))
                        if itemID then
                            local count = info.stackCount or info.itemCount or 1
                            ns.personalStock[itemID] = (ns.personalStock[itemID] or 0) + count
                        end
                    end
                end
            end
        end
    end

    ns.personalScanned  = true
    ns.personalScanTime = date("%H:%M:%S")
    ns.Log("--- Personal Inventory Scan ---", 0.4, 1, 0.8)
    local total = 0
    for itemID, count in pairs(ns.personalStock) do
        local name = GetItemInfo(itemID) or ("item:" .. itemID)
        ns.Log(count .. "x " .. name, 1, 1, 1)
        total = total + 1
    end
    ns.Log(total .. " unique item(s) found.", 0.4, 1, 0.8)
    if ns.RecalculateToBuy then ns.RecalculateToBuy() end
    if ns.RefreshToBuyUI then ns.RefreshToBuyUI() end
    ns.Print("Personal inventory scanned.")
    if personalScanBtn then
        personalScanBtn:SetText("Scanned!")
        C_Timer.After(2, function()
            if personalScanBtn then personalScanBtn:SetText("Scan for Restock") end
        end)
    end
end

local function OnBankOpened()
    if ns.context ~= "personal" then return end
    if not personalScanBar then
        local anchor = BankFrame or UIParent
        personalScanBar = CreateFrame("Frame", "GBRPersonalScanBar", UIParent, "BackdropTemplate")
        personalScanBar:SetSize(148, 30)
        personalScanBar:SetFrameStrata("MEDIUM")
        personalScanBar:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        personalScanBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        personalScanBar:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

        personalScanBtn = CreateFrame("Button", nil, personalScanBar, "UIPanelButtonTemplate")
        personalScanBtn:SetSize(136, 22)
        personalScanBtn:SetPoint("CENTER", personalScanBar, "CENTER")
        personalScanBtn:SetText("Scan for Restock")
        personalScanBtn:SetScript("OnClick", DoPersonalScan)
    end
    local anchor = BankFrame or UIParent
    personalScanBar:ClearAllPoints()
    if anchor ~= UIParent then
        personalScanBar:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)
    else
        personalScanBar:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
    end
    personalScanBar:Show()
end

local function OnBankClosed()
    if personalScanBar then personalScanBar:Hide() end
end

-- Exposed so the in-window scan button in UI.lua can call it directly
ns.DoPersonalScan = DoPersonalScan

-- WoW 10.0.2+: bank open/close via PlayerInteractionManager
if Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker then
    bankEventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    bankEventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    bankEventFrame:SetScript("OnEvent", function(_, event, interactionType)
        if interactionType ~= Enum.PlayerInteractionType.Banker then return end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            OnBankOpened()
        else
            OnBankClosed()
        end
    end)
else
    bankEventFrame:RegisterEvent("BANKFRAME_OPENED")
    bankEventFrame:RegisterEvent("BANKFRAME_CLOSED")
    bankEventFrame:SetScript("OnEvent", function(_, event)
        if event == "BANKFRAME_OPENED" then OnBankOpened() else OnBankClosed() end
    end)
end
