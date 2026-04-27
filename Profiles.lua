local _, ns = ...

-- ============================================================
-- Profile management
-- Profiles store per-item bank target quantities independent
-- of the bulk-buy qty. ns.guildBankStock / ns.toBuy are
-- declared in GuildBankRestock.lua.
-- ============================================================

local function db()
    local g = ns.addon.db.global
    return ns.context == "personal" and g.personal or g
end

local function SnapshotInclusion(profile)
    profile._inc = {}
    for catIdx, cat in ipairs(ns.CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header and item.enabled then
                profile._inc[catIdx .. "_" .. itemIdx] = true
            end
        end
    end
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
    SnapshotInclusion(db().profiles[name])
    ns.SetActiveProfile(name)
end

function ns.DeleteProfile(name)
    if db().profiles then
        db().profiles[name] = nil
    end
    local names = ns.GetProfileNames()
    ns.SetActiveProfile(names[1])
    if #names == 0 then
        ns.Print("No profiles remain — create one with New.")
    end
end

function ns.SetActiveProfile(name)
    ns.currentProfile  = name
    db().activeProfile = name
    -- Sync item.enabled with the profile's inclusion snapshot so StartSearch stays correct.
    if name then
        local profile = db().profiles and db().profiles[name]
        if profile and profile._inc ~= nil then
            for catIdx, cat in ipairs(ns.CATEGORIES) do
                for itemIdx, item in ipairs(cat.items) do
                    if not item.header then
                        local want = profile._inc[catIdx .. "_" .. itemIdx] == true
                        if item.enabled ~= want then
                            item.enabled = want
                            ns.SaveItem(catIdx, itemIdx)
                        end
                    end
                end
            end
        end
    end
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

function ns.SaveProfileAs(newName)
    if not newName or newName == "" then return end
    if not db().profiles then db().profiles = {} end
    local currentData = (ns.currentProfile and db().profiles[ns.currentProfile]) or {}
    db().profiles[newName] = {}
    for k, v in pairs(currentData) do
        if k ~= "_inc" then
            db().profiles[newName][k] = v
        end
    end
    SnapshotInclusion(db().profiles[newName])
    ns.SetActiveProfile(newName)
end

function ns.RecalculateToBuy()
    wipe(ns.toBuy)
    if ns.mode ~= "restock" or not ns.currentProfile then return end
    for catIdx, cat in ipairs(ns.CATEGORIES) do
        for itemIdx, item in ipairs(cat.items) do
            if not item.header then
                local target = ns.GetProfileTarget(catIdx, itemIdx)
                ns.toBuy[catIdx .. "_" .. itemIdx] = math.max(0, target - ns.GetStock(item.id))
            end
        end
    end
    if ns.RefreshToBuyUI then ns.RefreshToBuyUI() end
end

-- Returns true if catIdx/itemIdx is part of the current profile's inclusion snapshot.
-- Profiles without a snapshot (_inc == nil) show everything (backward compat).
function ns.IsProfileIncluded(catIdx, itemIdx)
    if not ns.currentProfile then return true end
    local profile = db().profiles and db().profiles[ns.currentProfile]
    if not profile or profile._inc == nil then return true end
    return profile._inc[catIdx .. "_" .. itemIdx] == true
end

function ns.SetProfileIncluded(catIdx, itemIdx, included)
    if not ns.currentProfile then return end
    if not db().profiles then return end
    local profile = db().profiles[ns.currentProfile]
    if not profile then return end
    if not profile._inc then profile._inc = {} end
    profile._inc[catIdx .. "_" .. itemIdx] = included or nil
end
