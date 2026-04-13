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

-- ============================================================
-- Helpers
-- ============================================================
function ns.Print(msg)
    print("|cff00ccffGuild Bank Restock:|r " .. tostring(msg))
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
        ns.boughtIndices[ns.pendingListPos] = true
        ns.pendingListPos = nil
        ns.pendingItemID  = nil
        ns.pendingQty     = nil
        ns.state = ns.STATE.READY
        ns.UpdateUI()

    elseif event == "COMMODITY_PURCHASE_FAILED" then
        ns.Print("Purchase failed — stopping. Check your gold or try again.")
        ns.Reset()
        ns.UpdateUI()
    end
end)
