local ADDON_NAME, ns = ...

local CATEGORIES = ns.CATEGORIES

-- ============================================================
-- State
-- ============================================================
ns.STATE = {
    IDLE       = "IDLE",
    SEARCHING  = "SEARCHING",
    READY      = "READY",
    CONFIRMING = "CONFIRMING",
}
ns.state              = ns.STATE.IDLE
ns.activeItems        = {}   -- { catIdx, itemIdx } for items in this run
ns.resultRows         = {}   -- listPos -> AH row
ns.boughtIndices      = {}   -- listPos -> true
ns.pendingListPos     = nil
ns.pendingItemID      = nil
ns.pendingQty         = nil
ns.listenerRegistered = false
ns.listener           = {}
ns.log                = {}

-- ============================================================
-- Helpers
-- ============================================================
function ns.Print(msg)
    print("|cff00ccffGuild Bank Restock:|r " .. tostring(msg))
end

function ns.Log(msg, r, g, b)
    ns.log[#ns.log + 1] = { msg = msg, r = r, g = g, b = b }
    if ns.AppendLogEntry then
        ns.AppendLogEntry(msg, r, g, b)
    end
end

local function UnregisterListener()
    if ns.listenerRegistered then
        Auctionator.EventBus:Unregister(ns.listener, { Auctionator.Shopping.Tab.Events.SearchEnd })
        ns.listenerRegistered = false
    end
end

function ns.Reset()
    UnregisterListener()
    ns.state          = ns.STATE.IDLE
    ns.pendingListPos = nil
    ns.pendingItemID  = nil
    ns.pendingQty     = nil
    wipe(ns.activeItems)
    wipe(ns.resultRows)
    wipe(ns.boughtIndices)
end

function ns.BuildSearchStrings()
    local list = {}
    for _, ref in ipairs(ns.activeItems) do
        local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
        local s = Auctionator.API.v1.ConvertToSearchString(ADDON_NAME, {
            itemID  = item.id,
            isExact = true,
        })
        list[#list + 1] = s
    end
    return list
end

function ns.MapResultRows()
    wipe(ns.resultRows)
    local dataProvider = AuctionatorShoppingFrame.ResultsListing.dataProvider
    for i = 1, dataProvider:GetCount() do
        local row = dataProvider:GetEntryAt(i)
        for listPos, ref in ipairs(ns.activeItems) do
            local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
            if row.itemKey.itemID == item.id then
                ns.resultRows[listPos] = row
                break
            end
        end
    end
end

function ns.GetNextItem()
    for listPos, ref in ipairs(ns.activeItems) do
        if not ns.boughtIndices[listPos] and ns.resultRows[listPos] then
            return listPos, ref
        end
    end
    return nil, nil
end

-- ============================================================
-- SavedVariables  (GuildBankRestockDB)
-- ============================================================
local function LoadSettings()
    if not GuildBankRestockDB then
        GuildBankRestockDB = { items = {}, rankFilter = nil }
    end
    for catIdx, cat in ipairs(CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local saved = GuildBankRestockDB.items[catIdx .. "_" .. itemIdx]
                if saved then
                    item.enabled = saved.enabled
                    item.qty     = saved.qty
                end
            end
        end
    end
end

function ns.SaveItem(catIdx, itemIdx)
    if not GuildBankRestockDB then
        GuildBankRestockDB = { items = {}, rankFilter = nil }
    end
    local item = CATEGORIES[catIdx].items[itemIdx]
    GuildBankRestockDB.items[catIdx .. "_" .. itemIdx] = { enabled = item.enabled, qty = item.qty }
end

function ns.SaveRankFilter(rank)
    if not GuildBankRestockDB then
        GuildBankRestockDB = { items = {}, rankFilter = nil }
    end
    GuildBankRestockDB.rankFilter = rank
end

-- Runs after SavedVariables are available; ns.ApplySettingsToUI is set by UI.lua.
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(_, _, addonName)
    if addonName ~= ADDON_NAME then return end
    LoadSettings()
    if ns.ApplySettingsToUI then ns.ApplySettingsToUI() end
    initFrame:UnregisterEvent("ADDON_LOADED")
end)

-- ============================================================
-- Auctionator EventBus listener  (search completion)
-- ns.UpdateUI is set by UI.lua after it loads.
-- ============================================================
function ns.listener:ReceiveEvent(eventName)
    if eventName ~= Auctionator.Shopping.Tab.Events.SearchEnd then return end
    if ns.state ~= ns.STATE.SEARCHING then return end
    ns.listenerRegistered = false
    Auctionator.EventBus:Unregister(self, { Auctionator.Shopping.Tab.Events.SearchEnd })
    ns.MapResultRows()
    local found = 0
    for _ in pairs(ns.resultRows) do found = found + 1 end
    ns.Print("Search complete. " .. found .. "/" .. #ns.activeItems .. " items found in AH.")
    ns.Log("Search complete: " .. found .. "/" .. #ns.activeItems .. " found.", 0.4, 1, 0.8)
    for listPos, ref in ipairs(ns.activeItems) do
        if not ns.resultRows[listPos] then
            local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
            local name = C_Item.GetItemInfo(item.id) or ("item:" .. item.id)
            ns.Log("Not found: " .. name, 1, 0.5, 0.5)
        end
    end
    ns.state = ns.STATE.READY
    ns.UpdateUI()
end

-- ============================================================
-- WoW event frame  (AH purchase flow)
-- ============================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_FAILED")

eventFrame:SetScript("OnEvent", function(_, event)
    if ns.state ~= ns.STATE.CONFIRMING then return end

    if event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
        if ns.pendingItemID and ns.pendingQty then
            C_AuctionHouse.ConfirmCommoditiesPurchase(ns.pendingItemID, ns.pendingQty)
        end

    elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
        local name = C_Item.GetItemInfo(ns.pendingItemID) or ("item " .. tostring(ns.pendingItemID))
        ns.Print("Purchased " .. tostring(ns.pendingQty) .. "x " .. name .. ".")
        ns.Log("Bought " .. tostring(ns.pendingQty) .. "x " .. name, 0.4, 1, 0.4)
        ns.boughtIndices[ns.pendingListPos] = true
        ns.pendingListPos = nil
        ns.pendingItemID  = nil
        ns.pendingQty     = nil
        ns.state = ns.STATE.READY
        ns.UpdateUI()

    elseif event == "COMMODITY_PURCHASE_FAILED" then
        ns.Print("Purchase failed — stopping. Check your gold or try again.")
        ns.Log("Purchase failed — not enough gold or AH error.", 1, 0.3, 0.3)
        ns.Reset()
        ns.UpdateUI()
    end
end)
