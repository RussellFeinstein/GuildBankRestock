local _, ns = ...

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
        ns.Reset()
        ns.frame:Hide()
        ns.Print("Stopped.")
    else
        ns.frame:Show()
        ns.UpdateUI()
    end
end
