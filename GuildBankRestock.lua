local ADDON_NAME, ns = ...

local CATEGORIES = ns.CATEGORIES

local COPPER_PER_GOLD   = 10000
local COPPER_PER_SILVER = 100

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
        log           = {},
        minimapAngle  = nil,
        context       = "guild",
        windowWidth   = nil,
        windowHeight  = nil,
        firstRun      = true,
        personal      = {
            items         = {},
            rankFilter    = nil,
            mode          = "bulk",
            activeProfile = nil,
            profiles      = {},
            budget        = 0,
        },
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
ns.context            = "guild"
ns.personalStock      = {}
ns.personalScanned    = false
ns.personalScanTime   = nil
ns.guildBankScanTime  = nil

-- ============================================================
-- Helpers
-- ============================================================
function ns.Print(msg)
    print("|cff00ccffGuild Bank Restock:|r " .. tostring(msg))
end

function ns.Log(msg, r, g, b)
    local fullMsg = "[" .. date("%m/%d %H:%M:%S") .. "] " .. msg
    ns.log[#ns.log + 1] = { msg = fullMsg, r = r, g = g, b = b }
    if ns.addon and ns.addon.db then
        local dbLog = ns.addon.db.global.log
        dbLog[#dbLog + 1] = { msg = fullMsg, r = r, g = g, b = b }
        if #dbLog > 500 then table.remove(dbLog, 1) end
    end
    if ns.AppendLogEntry then
        ns.AppendLogEntry(fullMsg, r, g, b)
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

function ns.ContextDB()
    local g = ns.addon.db.global
    return ns.context == "personal" and g.personal or g
end

function ns.GetStock(itemID)
    if ns.context == "guild" then
        return ns.guildBankScanned and (ns.guildBankStock[itemID] or 0) or 0
    else
        return ns.personalScanned and (ns.personalStock[itemID] or 0) or 0
    end
end

function ns.SwitchContext(newContext)
    ns.context = newContext
    ns.addon.db.global.context = newContext
    ns.LoadContextSettings(newContext)
    if ns.ApplySettingsToUI then ns.ApplySettingsToUI() end
    if ns.RecalculateToBuy then ns.RecalculateToBuy() end
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
function ns.LoadContextSettings(context)
    local g = ns.addon.db.global
    local ctxDB = context == "personal" and g.personal or g
    ns.mode           = ctxDB.mode or "bulk"
    ns.currentProfile = ctxDB.activeProfile
    ns.budget         = ctxDB.budget or 0
    for catIdx, cat in ipairs(CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local saved = ctxDB.items[catIdx .. "_" .. itemIdx]
                if saved then
                    item.enabled  = saved.enabled
                    item.qty      = saved.qty or item.qty or 1
                    item.maxPrice = saved.maxPrice
                else
                    item.enabled  = false
                    item.maxPrice = nil
                end
            end
        end
    end
end

local function LoadSettings()
    ns.context = ns.addon.db.global.context or "guild"
    ns.LoadContextSettings(ns.context)
end

function ns.SaveItem(catIdx, itemIdx)
    local item = CATEGORIES[catIdx].items[itemIdx]
    ns.ContextDB().items[catIdx .. "_" .. itemIdx] = {
        enabled  = item.enabled,
        qty      = item.qty,
        maxPrice = item.maxPrice,
    }
end

function ns.SaveRankFilter(rank)
    ns.ContextDB().rankFilter = rank
end

-- ============================================================
-- Search kick-off  (called by the Start Search button in UI)
-- ============================================================
ns.StartSearch = function()
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
    ns.UpdateUI()
    ns.Log("Search started: " .. #ns.activeItems .. " items." ..
        (ns.budget > 0 and ("  Budget: " .. ns.budget .. "g") or ""), 0.8, 0.8, 1)
    AuctionatorShoppingFrame:DoSearch(ns.BuildSearchStrings())
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
    if self.db.global.firstRun then
        ns.Print("New? Open the minimap button and check the |cFF00FF00About|r tab.")
        self.db.global.firstRun = false
    end
    if ns.ApplySettingsToUI then ns.ApplySettingsToUI() end
    if ns.RecalculateToBuy then ns.RecalculateToBuy() end
    if ns.InitMinimapButton then ns.InitMinimapButton() end

    -- Load persisted log and replay into the ScrollingMessageFrame
    ns.log = self.db.global.log
    if ns.AppendLogEntry then
        for _, entry in ipairs(ns.log) do
            ns.AppendLogEntry(entry.msg, entry.r, entry.g, entry.b)
        end
    end

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
        ns.frame:Hide()
    elseif cmd == "version" or cmd == "v" then
        local v = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON_NAME, "Version") or "?"
        ns.Print("Version " .. v)
    else
        ns.frame:Show()
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
        if spent >= ns.budget * COPPER_PER_GOLD then
            local g = math.floor(spent / COPPER_PER_GOLD)
            local s = math.floor((spent % COPPER_PER_GOLD) / COPPER_PER_SILVER)
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
