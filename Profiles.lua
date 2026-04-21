local _, ns = ...

-- ============================================================
-- Profile management
-- Profiles store per-item bank target quantities independent
-- of the bulk-buy qty. ns.guildBankStock / ns.toBuy are
-- declared in GuildBankRestock.lua.
-- ============================================================

function ns.GetProfileNames()
    local names = {}
    for name in pairs(GuildBankRestockDB.profiles or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function ns.CreateProfile(name)
    if not GuildBankRestockDB.profiles then GuildBankRestockDB.profiles = {} end
    GuildBankRestockDB.profiles[name] = GuildBankRestockDB.profiles[name] or {}
    ns.SetActiveProfile(name)
end

function ns.DeleteProfile(name)
    if GuildBankRestockDB.profiles then
        GuildBankRestockDB.profiles[name] = nil
    end
    local names = ns.GetProfileNames()
    ns.SetActiveProfile(names[1])  -- nil if no profiles remain
end

function ns.SetActiveProfile(name)
    ns.currentProfile = name
    GuildBankRestockDB.activeProfile = name
    ns.RecalculateToBuy()
    if ns.RefreshProfileUI then ns.RefreshProfileUI() end
end

function ns.GetProfileTarget(catIdx, itemIdx)
    if not ns.currentProfile then return 0 end
    local profile = GuildBankRestockDB.profiles and GuildBankRestockDB.profiles[ns.currentProfile]
    return profile and (profile[catIdx .. "_" .. itemIdx] or 0) or 0
end

function ns.SetProfileTarget(catIdx, itemIdx, qty)
    if not ns.currentProfile then return end
    if not GuildBankRestockDB.profiles then GuildBankRestockDB.profiles = {} end
    if not GuildBankRestockDB.profiles[ns.currentProfile] then
        GuildBankRestockDB.profiles[ns.currentProfile] = {}
    end
    GuildBankRestockDB.profiles[ns.currentProfile][catIdx .. "_" .. itemIdx] = qty > 0 and qty or nil
end

function ns.RecalculateToBuy()
    wipe(ns.toBuy)
    if ns.mode ~= "restock" or not ns.currentProfile then return end
    for catIdx, cat in ipairs(ns.CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local target = ns.GetProfileTarget(catIdx, itemIdx)
                local inBank = ns.guildBankScanned and (ns.guildBankStock[item.id] or 0) or 0
                ns.toBuy[catIdx .. "_" .. itemIdx] = math.max(0, target - inBank)
            end
        end
    end
    if ns.RefreshToBuyUI then ns.RefreshToBuyUI() end
end
