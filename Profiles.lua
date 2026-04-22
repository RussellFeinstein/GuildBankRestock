local _, ns = ...

-- ============================================================
-- Profile management
-- Profiles store per-item bank target quantities independent
-- of the bulk-buy qty. ns.guildBankStock / ns.toBuy are
-- declared in GuildBankRestock.lua.
-- ============================================================

local function db()
    return ns.addon.db.global
end

function ns.GetProfileNames()
    local names = {}
    for name in pairs(db().profiles or {}) do
        names[#names + 1] = name
    end
    table.sort(names)
    return names
end

function ns.CreateProfile(name)
    if not db().profiles then db().profiles = {} end
    db().profiles[name] = db().profiles[name] or {}
    ns.SetActiveProfile(name)
end

function ns.DeleteProfile(name)
    if db().profiles then
        db().profiles[name] = nil
    end
    local names = ns.GetProfileNames()
    ns.SetActiveProfile(names[1])
end

function ns.SetActiveProfile(name)
    ns.currentProfile        = name
    db().activeProfile       = name
    ns.RecalculateToBuy()
    if ns.RefreshProfileUI then ns.RefreshProfileUI() end
end

function ns.GetProfileTarget(catIdx, itemIdx)
    if not ns.currentProfile then return 0 end
    local profile = db().profiles and db().profiles[ns.currentProfile]
    return profile and (profile[catIdx .. "_" .. itemIdx] or 0) or 0
end

function ns.SetProfileTarget(catIdx, itemIdx, qty)
    if not ns.currentProfile then return end
    if not db().profiles then db().profiles = {} end
    if not db().profiles[ns.currentProfile] then
        db().profiles[ns.currentProfile] = {}
    end
    db().profiles[ns.currentProfile][catIdx .. "_" .. itemIdx] = qty > 0 and qty or nil
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
