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
ns.skippedIndices     = {}
ns.searchGen          = 0
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
    -- After OnInitialize, ns.log is aliased to ns.addon.db.global.log (same table reference),
    -- so a single append covers both the in-memory and saved-vars views. Pre-init we still
    -- have the original empty table so logs aren't dropped if anything fires before AceDB sets up.
    local fullMsg = "[" .. date("%m/%d %H:%M:%S") .. "] " .. msg
    ns.log[#ns.log + 1] = { msg = fullMsg, r = r, g = g, b = b }
    if #ns.log > 500 then table.remove(ns.log, 1) end
    if ns.AppendLogEntry then
        ns.AppendLogEntry(fullMsg, r, g, b)
    end
end

-- Log-only diagnostic helper for in-flight tracing of the search path. Writes to the
-- in-addon log only, never to chat. Intentional: the log is the recoverable diagnostic
-- record (visible in the Log tab, exportable when reporting issues), while chat stays
-- curated for user-actionable messages. The 500-entry log cap handles long-term bloat.
local function diag(msg)
    ns.Log("[diag] " .. msg, 1, 1, 0.5)
end

local function UnregisterListener()
    if ns.listenerRegistered then
        Auctionator.EventBus:Unregister(ns.listener, { Auctionator.Shopping.Tab.Events.SearchEnd })
        ns.listenerRegistered = false
    end
end

function ns.Reset()
    UnregisterListener()
    -- If we initiated a search and it's still in flight on Auctionator's side, abort it.
    -- Just unregistering our listener doesn't stop Auctionator — its SearchProvider keeps
    -- querying the AH and would eventually fire SearchEnd into a stale state (or, if the
    -- user re-clicks Start Search before the old search ends, our newly-registered
    -- listener could receive the OLD search's results). Only stop when we know the search
    -- is ours (state == SEARCHING) so we don't kill a manual user-initiated search that
    -- happens to be running in the Auctionator window.
    if (ns.state == ns.STATE.SEARCHING or ns.state == ns.STATE.READY)
       and AuctionatorShoppingFrame and AuctionatorShoppingFrame.StopSearch then
        AuctionatorShoppingFrame:StopSearch()
    end
    -- Bump the search generation to invalidate any in-flight async name-load callbacks.
    -- Cancelled callbacks compare ns.searchGen against a captured `thisGen` and drop their
    -- results when the values disagree. Without this, a close-and-restart while names are
    -- still loading would let stale callbacks decrement the previous run's `pending` and
    -- fire FireAuctionatorSearch with a names array that no longer matches activeItems.
    ns.searchGen = (ns.searchGen or 0) + 1
    ns.state          = ns.STATE.IDLE
    ns.pendingListPos = nil
    ns.pendingItemID  = nil
    ns.pendingQty     = nil
    wipe(ns.activeItems)
    wipe(ns.resultRows)
    wipe(ns.boughtIndices)
    wipe(ns.skippedIndices)
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

function ns.BuildSearchStrings(names)
    -- Auctionator.API.v1.ConvertToSearchString validates that term.searchString is a string
    -- (the item NAME). Passing itemID is silently ignored. Caller resolves IDs to names
    -- via Item:CreateFromItemID():ContinueOnItemLoad(...) before calling us.
    local list = {}
    for i, ref in ipairs(ns.activeItems) do
        local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
        local name = names and names[i] or C_Item.GetItemInfo(item.id)
        if not name then
            error("Item name not loaded for #" .. i .. " (id=" .. tostring(item.id) .. ")")
        end
        local ok, s = pcall(Auctionator.API.v1.ConvertToSearchString, ADDON_NAME, {
            searchString = name,
            isExact      = true,
        })
        if not ok then
            error("ConvertToSearchString failed on item #" .. i .. " (id=" .. tostring(item.id) .. " name=" .. tostring(name) .. "): " .. tostring(s))
        end
        list[#list + 1] = s
    end
    return list
end

function ns.MapResultRows(results)
    -- Auctionator fires SearchEnd with the full results array as the event payload,
    -- BEFORE its own DataProvider has finished processing them. Reading from
    -- AuctionatorShoppingFrame.ResultsListing.dataProvider here returns stale or empty
    -- data because AppendEntries only queues to entriesToProcess; cachedResults is
    -- populated across subsequent OnUpdate frames. The event payload bypasses that
    -- lag and is what we actually want.
    wipe(ns.resultRows)
    if not results then return end
    for _, row in ipairs(results) do
        for listPos, ref in ipairs(ns.activeItems) do
            local item = CATEGORIES[ref.catIdx].items[ref.itemIdx]
            if row.itemKey and row.itemKey.itemID == item.id then
                ns.resultRows[listPos] = row
                break
            end
        end
    end
end

function ns.GetNextItem()
    for listPos, ref in ipairs(ns.activeItems) do
        if not ns.boughtIndices[listPos]
           and not ns.skippedIndices[listPos]
           and ns.resultRows[listPos] then
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
    local searchEndEvent = Auctionator.Shopping and Auctionator.Shopping.Tab
        and Auctionator.Shopping.Tab.Events and Auctionator.Shopping.Tab.Events.SearchEnd
    if not searchEndEvent then
        ns.Log("Auctionator.Shopping.Tab.Events.SearchEnd is nil. Auctionator API may have changed.", 1, 0.3, 0.3)
        return
    end
    Auctionator.EventBus:Register(ns.listener, { searchEndEvent })
    ns.listenerRegistered = true
    ns.runStartMoney = GetMoney()
    ns.searchGen = (ns.searchGen or 0) + 1
    local thisGen = ns.searchGen
    ns.state = ns.STATE.SEARCHING
    ns.UpdateUI()
    local startedMsg = "Search started: " .. #ns.activeItems .. " items." ..
        (ns.budget > 0 and ("  Budget: " .. ns.budget .. "g") or "")
    ns.Log(startedMsg, 0.8, 0.8, 1)

    -- Auctionator's ConvertToSearchString needs item NAMES (not IDs). Names load async via
    -- the WoW item cache; pre-warm them all, then fire the AH search from the continuation.
    -- thisGen guards against cancel-and-restart races: Reset bumps ns.searchGen, so any
    -- old callbacks that fire after a restart compare unequal and drop their results.
    local pending = #ns.activeItems
    local names   = {}
    diag("Resolving " .. pending .. " item names asynchronously (gen=" .. thisGen .. ").")

    for i, ref in ipairs(ns.activeItems) do
        local catItem = CATEGORIES[ref.catIdx].items[ref.itemIdx]
        local itemObj = Item:CreateFromItemID(catItem.id)
        itemObj:ContinueOnItemLoad(function()
            if ns.searchGen ~= thisGen then
                diag("Stale ContinueOnItemLoad callback dropped (gen=" .. thisGen .. ", current=" .. tostring(ns.searchGen) .. ").")
                return
            end
            names[i]  = itemObj:GetItemName()
            pending   = pending - 1
            if pending == 0 then
                ns.FireAuctionatorSearch(names, thisGen)
            end
        end)
    end
end

ns.FireAuctionatorSearch = function(names, thisGen)
    if ns.searchGen ~= thisGen then
        diag("FireAuctionatorSearch dropped: gen mismatch (gen=" .. tostring(thisGen) .. ", current=" .. tostring(ns.searchGen) .. ").")
        return
    end
    diag("All " .. #names .. " names resolved; building search strings.")
    local sbsOk, sbsResult = pcall(ns.BuildSearchStrings, names)
    if not sbsOk then
        ns.Log("BuildSearchStrings error: " .. tostring(sbsResult), 1, 0.3, 0.3)
        ns.Reset()
        ns.UpdateUI()
        return
    end
    diag("Built " .. #sbsResult .. " search string(s). First: " .. tostring(sbsResult[1] or "<none>"))
    if not AuctionatorShoppingFrame.DoSearch then
        ns.Log("AuctionatorShoppingFrame:DoSearch is nil. Auctionator API mismatch.", 1, 0.3, 0.3)
        return
    end
    local doOk, doErr = pcall(function() AuctionatorShoppingFrame:DoSearch(sbsResult) end)
    if not doOk then
        ns.Log("DoSearch error: " .. tostring(doErr), 1, 0.3, 0.3)
    else
        diag("DoSearch returned. Waiting on Auctionator SearchEnd.")
    end
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
function ns.listener:ReceiveEvent(eventName, results)
    local resultCount = type(results) == "table" and #results or tostring(results)
    diag("EventBus fired: " .. tostring(eventName) .. " (results=" .. resultCount .. ").")
    local expected = Auctionator and Auctionator.Shopping and Auctionator.Shopping.Tab
        and Auctionator.Shopping.Tab.Events and Auctionator.Shopping.Tab.Events.SearchEnd
    if eventName ~= expected then
        diag("  ignoring (eventName not SearchEnd).")
        return
    end
    if ns.state ~= ns.STATE.SEARCHING then
        diag("  ignoring (state=" .. tostring(ns.state) .. ", not SEARCHING).")
        return
    end
    ns.listenerRegistered = false
    Auctionator.EventBus:Unregister(self, { expected })
    local mapOk, mapErr = pcall(ns.MapResultRows, results)
    if not mapOk then
        ns.Log("MapResultRows error: " .. tostring(mapErr), 1, 0.3, 0.3)
        ns.state = ns.STATE.READY
        ns.UpdateUI()
        return
    end
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
