local _, ns = ...

-- ============================================================
-- Guild Bank scanning  (manual — triggered by button on the bank UI)
-- ns.guildBankStock / ns.guildBankScanned declared in GuildBankRestock.lua
-- ============================================================

local scanBtn
local scanBar
local scanEventFrame = CreateFrame("Frame")

local function DoScan()
    ns.Print("Scanning guild bank...")
    wipe(ns.guildBankStock)

    local numTabs = GetNumGuildBankTabs()
    local queue = {}
    for i = 1, numTabs do queue[i] = i end

    local currentTab = nil

    local function ReadTab()
        for slot = 1, 98 do
            local link = GetGuildBankItemLink(currentTab, slot)
            if link then
                local itemID = tonumber(link:match("item:(%d+)"))
                if itemID then
                    local _, _, count = GetGuildBankItemInfo(currentTab, slot)
                    ns.guildBankStock[itemID] = (ns.guildBankStock[itemID] or 0) + (count or 1)
                end
            end
        end
    end

    local function ScanNext()
        if #queue == 0 then
            scanEventFrame:UnregisterEvent("GUILDBANKBAGSLOTS_CHANGED")
            scanEventFrame:SetScript("OnEvent", nil)
            ns.guildBankScanned = true
            ns.Log("--- Guild Bank Scan ---", 0.4, 1, 0.8)
            local total = 0
            for itemID, count in pairs(ns.guildBankStock) do
                local name = GetItemInfo(itemID) or ("item:" .. itemID)
                ns.Log(count .. "x " .. name, 1, 1, 1)
                total = total + 1
            end
            ns.Log(total .. " unique item(s) found.", 0.4, 1, 0.8)
            if ns.RecalculateToBuy then ns.RecalculateToBuy() end
            if ns.RefreshToBuyUI then ns.RefreshToBuyUI() end
            ns.Print("Guild bank scanned.")
            if scanBtn then
                scanBtn:SetText("Scanned!")
                C_Timer.After(2, function()
                    if scanBtn then scanBtn:SetText("Scan for Restock") end
                end)
            end
            return
        end
        currentTab = table.remove(queue, 1)
        QueryGuildBankTab(currentTab)
    end

    scanEventFrame:RegisterEvent("GUILDBANKBAGSLOTS_CHANGED")
    scanEventFrame:SetScript("OnEvent", function()
        if not currentTab then return end
        ReadTab()
        currentTab = nil
        ScanNext()
    end)

    ScanNext()
end

local function OnBankOpened()
    if not GuildBankFrame then
        ns.Print("GuildBankRestock: GuildBankFrame not found — scan button unavailable.")
        return
    end
    if not scanBar then
        scanBar = CreateFrame("Frame", "GuildBankRestockBar", UIParent, "BackdropTemplate")
        scanBar:SetSize(136, 30)
        scanBar:SetFrameStrata("MEDIUM")
        scanBar:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        scanBar:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        scanBar:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

        scanBtn = CreateFrame("Button", nil, scanBar, "UIPanelButtonTemplate")
        scanBtn:SetSize(124, 22)
        scanBtn:SetPoint("CENTER", scanBar, "CENTER")
        scanBtn:SetText("Scan for Restock")
        scanBtn:SetScript("OnClick", DoScan)
    end
    scanBar:ClearAllPoints()
    scanBar:SetPoint("TOPRIGHT", GuildBankFrame, "BOTTOMRIGHT", 0, -2)
    scanBar:Show()
end

local function OnBankClosed()
    if scanBar then scanBar:Hide() end
end

local eventFrame = CreateFrame("Frame")

-- WoW 10.0.2+: guild bank open/close moved to PlayerInteractionManager
if Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker then
    eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
    eventFrame:RegisterEvent("PLAYER_INTERACTION_MANAGER_FRAME_HIDE")
    eventFrame:SetScript("OnEvent", function(_, event, interactionType)
        if interactionType ~= Enum.PlayerInteractionType.GuildBanker then return end
        if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
            OnBankOpened()
        else
            OnBankClosed()
        end
    end)
else
    -- Fallback for older API
    eventFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
    eventFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
    eventFrame:SetScript("OnEvent", function(_, event)
        if event == "GUILDBANKFRAME_OPENED" then
            OnBankOpened()
        else
            OnBankClosed()
        end
    end)
end
