local _, ns = ...

-- ============================================================
-- Guild Bank scanning  (manual — triggered by button on the bank UI)
-- ns.guildBankStock / ns.guildBankScanned declared in GuildBankRestock.lua
-- ============================================================

local scanBtn

local function DoScan()
    wipe(ns.guildBankStock)
    local numTabs = GetNumGuildBankTabs()
    for tab = 1, numTabs do
        QueryGuildBankTab(tab)
    end
    C_Timer.After(0.5, function()
        for tab = 1, GetNumGuildBankTabs() do
            for slot = 1, 98 do
                local link = GetGuildBankItemLink(tab, slot)
                if link then
                    local itemID = tonumber(link:match("item:(%d+)"))
                    if itemID then
                        local _, _, count = GetGuildBankItemInfo(tab, slot)
                        ns.guildBankStock[itemID] = (ns.guildBankStock[itemID] or 0) + (count or 1)
                    end
                end
            end
        end
        ns.guildBankScanned = true
        if ns.RecalculateToBuy then ns.RecalculateToBuy() end
        ns.Print("Guild bank scanned.")
        if scanBtn then
            scanBtn:SetText("Scanned!")
            C_Timer.After(2, function()
                if scanBtn then scanBtn:SetText("Scan for Restock") end
            end)
        end
    end)
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("GUILDBANKFRAME_OPENED")
eventFrame:RegisterEvent("GUILDBANKFRAME_CLOSED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "GUILDBANKFRAME_OPENED" then
        if not scanBtn then
            scanBtn = CreateFrame("Button", nil, GuildBankFrame, "UIPanelButtonTemplate")
            scanBtn:SetSize(120, 22)
            scanBtn:SetPoint("BOTTOMLEFT", GuildBankFrame, "BOTTOMLEFT", 8, 8)
            scanBtn:SetText("Scan for Restock")
            scanBtn:SetScript("OnClick", DoScan)
        end
        scanBtn:Show()
    elseif event == "GUILDBANKFRAME_CLOSED" then
        if scanBtn then scanBtn:Hide() end
    end
end)
