local ADDON_NAME, ns = ...

local CATEGORIES = ns.CATEGORIES

-- ============================================================
-- Ace3 addon object
-- ============================================================
local GBR = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME,
    "AceConsole-3.0",
    "AceEvent-3.0"
)
ns.addon = GBR

-- ============================================================
-- AceDB defaults
-- ============================================================
local defaults = {
    global = {
        items         = {},
        rankFilter    = nil,
        mode          = "bulk",
        activeProfile = nil,
        profiles      = {},
        budget        = 0,
    },
}

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
ns.activeItems        = {}
ns.resultRows         = {}
ns.boughtIndices      = {}
ns.pendingListPos     = nil
ns.pendingItemID      = nil
ns.pendingQty         = nil
ns.listenerRegistered = false
ns.listener           = {}
ns.log                = {}
ns.guildBankStock     = {}
ns.guildBankScanned   = false
ns.mode               = "bulk"
ns.currentProfile     = nil
ns.toBuy              = {}
ns.budget             = 0
ns.runStartMoney      = 0

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
-- SavedVariables (via AceDB)
-- ============================================================
local function LoadSettings()
    local db = ns.addon.db.global
    ns.mode           = db.mode or "bulk"
    ns.currentProfile = db.activeProfile
    ns.budget         = db.budget or 0
    for catIdx, cat in ipairs(CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local saved = db.items[catIdx .. "_" .. itemIdx]
                if saved then
                    item.enabled = saved.enabled
                    item.qty     = saved.qty
                end
            end
        end
    end
end

function ns.SaveItem(catIdx, itemIdx)
    local item = CATEGORIES[catIdx].items[itemIdx]
    ns.addon.db.global.items[catIdx .. "_" .. itemIdx] = {
        enabled = item.enabled,
        qty     = item.qty,
    }
end

function ns.SaveRankFilter(rank)
    ns.addon.db.global.rankFilter = rank
end

-- ============================================================
-- Addon lifecycle
-- ============================================================
function GBR:OnInitialize()
    -- Migrate pre-Ace3 SavedVariables (detect by presence of items table but no profileKeys)
    local legacyData = nil
    if GuildBankRestockDB
       and type(GuildBankRestockDB.items) == "table"
       and not GuildBankRestockDB.profileKeys then
        legacyData = {
            items         = GuildBankRestockDB.items,
            rankFilter    = GuildBankRestockDB.rankFilter,
            mode          = GuildBankRestockDB.mode,
            activeProfile = GuildBankRestockDB.activeProfile,
            profiles      = GuildBankRestockDB.profiles,
            budget        = GuildBankRestockDB.budget,
        }
        GuildBankRestockDB = nil
    end

    self.db = LibStub("AceDB-3.0"):New("GuildBankRestockDB", defaults, true)

    if legacyData then
        local g = self.db.global
        for k, v in pairs(legacyData.items or {}) do
            g.items[k] = v
        end
        g.rankFilter    = legacyData.rankFilter
        g.mode          = legacyData.mode or "bulk"
        g.activeProfile = legacyData.activeProfile
        g.budget        = legacyData.budget or 0
        if type(legacyData.profiles) == "table" then
            for name, data in pairs(legacyData.profiles) do
                g.profiles[name] = data
            end
        end
    end

    LoadSettings()
    if ns.ApplySettingsToUI then ns.ApplySettingsToUI() end

    self:RegisterChatCommand("restock",     "HandleSlashCommand")
    self:RegisterChatCommand("bankrestock", "HandleSlashCommand")
    self:RegisterChatCommand("rs",          "HandleSlashCommand")
end

function GBR:OnEnable()
    self:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
    self:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
    self:RegisterEvent("COMMODITY_PURCHASE_FAILED")
end

-- ============================================================
-- Slash commands  (absorbs Commands.lua)
-- ============================================================
function GBR:HandleSlashCommand(msg)
    local cmd = msg:lower():match("^%s*(%S*)") or ""
    if cmd == "stop" then
        ns.frame.frame:Hide()
    elseif cmd == "version" or cmd == "v" then
        local v = GetAddOnMetadata(ADDON_NAME, "Version") or "?"
        ns.Print("Version " .. v)
    else
        ns.frame.frame:Show()
        ns.UpdateUI()
    end
end

-- ============================================================
-- AceEvent handlers
-- ============================================================
function GBR:AUCTION_HOUSE_THROTTLED_SYSTEM_READY()
    if ns.state ~= ns.STATE.CONFIRMING then return end
    if ns.pendingItemID and ns.pendingQty then
        C_AuctionHouse.ConfirmCommoditiesPurchase(ns.pendingItemID, ns.pendingQty)
    end
end

function GBR:COMMODITY_PURCHASE_SUCCEEDED()
    if ns.state ~= ns.STATE.CONFIRMING then return end
    local name = C_Item.GetItemInfo(ns.pendingItemID) or ("item " .. tostring(ns.pendingItemID))
    ns.Print("Purchased " .. tostring(ns.pendingQty) .. "x " .. name .. ".")
    ns.Log("Bought " .. tostring(ns.pendingQty) .. "x " .. name, 0.4, 1, 0.4)
    ns.boughtIndices[ns.pendingListPos] = true
    ns.pendingListPos = nil
    ns.pendingItemID  = nil
    ns.pendingQty     = nil

    if ns.budget > 0 then
        local spent = ns.runStartMoney - GetMoney()
        if spent >= ns.budget * 10000 then
            local g = math.floor(spent / 10000)
            local s = math.floor((spent % 10000) / 100)
            local c = spent % 100
            local summary = string.format("Budget reached: %dg %ds %dc spent.", g, s, c)
            ns.Print(summary)
            ns.Log(summary, 1, 0.82, 0)
            local remaining = {}
            for listPos, ref in ipairs(ns.activeItems) do
                if not ns.boughtIndices[listPos] then
                    local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
                    remaining[#remaining + 1] = C_Item.GetItemInfo(item.id) or ("item:" .. item.id)
                end
            end
            if #remaining > 0 then
                ns.Print("Not purchased: " .. table.concat(remaining, ", "))
                for _, itemName in ipairs(remaining) do
                    ns.Log("Not purchased: " .. itemName, 1, 0.5, 0.5)
                end
            end
            ns.Reset()
            ns.UpdateUI()
            return
        end
    end

    ns.state = ns.STATE.READY
    ns.UpdateUI()
end

function GBR:COMMODITY_PURCHASE_FAILED()
    if ns.state ~= ns.STATE.CONFIRMING then return end
    ns.Print("Purchase failed — stopping. Check your gold or try again.")
    ns.Log("Purchase failed — not enough gold or AH error.", 1, 0.3, 0.3)
    ns.Reset()
    ns.UpdateUI()
end

-- ============================================================
-- Auctionator EventBus listener
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
