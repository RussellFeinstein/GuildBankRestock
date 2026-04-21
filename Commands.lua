local ADDON_NAME, ns = ...

-- ============================================================
-- Slash commands:  /restock          → show the window
--                  /restock stop     → cancel and close
-- ============================================================
SLASH_GUILDBANKRESTOCK1 = "/restock"
SLASH_GUILDBANKRESTOCK2 = "/bankrestock"
SLASH_GUILDBANKRESTOCK3 = "/rs"
SlashCmdList["GUILDBANKRESTOCK"] = function(msg)
    local cmd = msg:lower():match("^%s*(%S*)") or ""
    if cmd == "stop" then
        ns.frame:Hide()
    elseif cmd == "version" or cmd == "v" then
        local v = GetAddOnMetadata(ADDON_NAME, "Version") or "?"
        ns.Print("Version " .. v)
    else
        ns.frame:Show()
        ns.UpdateUI()
    end
end
