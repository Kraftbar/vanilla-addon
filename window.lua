-- Version: 1.2.3
-- Context: Vanilla addon (1.12.1) with combat stats displayed in columns.
-- Notes: Added debug mode for detailed logging. Added mouse wheel scrolling to the standard chat window.

-- LLM instructions
-- Context: Vanilla addon (1.12.1) with combat stats displayed in columns.
-- Context: NOTE THERE MIGHT BE A VERY RELEVANT REASON FOR THAT THIS IS WRITTEN A LITTLE SCUFFED, as it is very old code/ interface 
--          be careful breaking things. NOTE also its lua version 5.0 
-- docs: https://github.com/refaim/Vanilla-WoW-Lua-Definitions,  https://www.lua.org/manual/5.0/, https://wowpedia.fandom.com/wiki/Widget_API?oldid=278403, https://wowpedia.fandom.com/wiki/Global_functions?oldid=270108, 
--       https://github.com/shagu/ShaguDPS/tree/master





-- Global addon table
CombatStats = {
    version = "1.2.3",
    debug = false,  -- Debug mode flag, off by default
    config = {
        width = 300,
        height = 200,
        visible = true,
    },
    data = {
        damageDealt = 0,
        damageTaken = 0,
        attacksDealt = 0,
        combatStart = nil,
        timeToTargetDeath = 0,
        timeToPlayerDeath = 0,  
    },
}

-- Utility: Create a movable message window
local function CreateMessageWindow(name, width, height, xOffset)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetPoint("CENTER", UIParent, "CENTER", xOffset, 0)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 1)
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function() frame:StartMoving() end)
    frame:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local scroll = CreateFrame("ScrollingMessageFrame", name .. "Scroll", frame)
    scroll:SetPoint("TOPLEFT", 10, -10)
    scroll:SetWidth(width - 20)
    scroll:SetHeight(height - 20)
    scroll:SetFontObject(GameFontNormal)
    scroll:SetJustifyH("LEFT")
    scroll:SetMaxLines(1000)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function()
        if arg1 > 0 then scroll:ScrollUp() else scroll:ScrollDown() end
    end)

    frame.scroll = scroll
    return frame
end

-- Utility: Add message to a window
local function AddMessage(window, msg)
    if window and window.scroll then
        window.scroll:AddMessage(msg)
        window.scroll:ScrollToBottom()
    end
end

-- Utility: Round numbers
local function Round(num, places)
    local mult = 10 ^ (places or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- Initialize windows
local statsWindow = CreateMessageWindow("CombatStatsWindow", CombatStats.config.width, CombatStats.config.height, -150)
local deathWindow = CreateMessageWindow("SecondsUntilDeathWindow", CombatStats.config.width, 30, 0)
local infoWindow = CreateMessageWindow("CombatInfoWindow", CombatStats.config.width, CombatStats.config.height, 150)

-- Combat state management
local inCombat = false
local function UpdateCombatState()
    local newState = UnitAffectingCombat("player") or UnitAffectingCombat("target")
    if newState and not inCombat then
        inCombat = true
        CombatStats.data.combatStart = GetTime()
        if CombatStats.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Entered combat.")
        end
    elseif not newState and inCombat then
        inCombat = false
        if CombatStats.data.combatStart then
            local elapsed = GetTime() - CombatStats.data.combatStart
            local dps = elapsed > 0 and Round(CombatStats.data.damageDealt / elapsed, 1) or 0
            local dtps = elapsed > 0 and Round(CombatStats.data.damageTaken / elapsed, 1) or 0
            AddMessage(statsWindow, string.format("Combat ended.   Taken: %-6.1f   Dealt: %-6.1f", dtps, dps))
            if CombatStats.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Left combat. Stats reset.")
            end
        end
        CombatStats.data.damageDealt = 0
        CombatStats.data.damageTaken = 0
        CombatStats.data.attacksDealt = 0
        CombatStats.data.combatStart = nil
        CombatStats.data.timeToTargetDeath = 0
        CombatStats.data.timeToPlayerDeath = 0
        AddMessage(deathWindow, "Seconds until Target Death: 0.0 / Me: 0.0")
    end
end

-- Combat log parsing
local function ParseCombatMessage(event, message)
    if not message then return end

    -- Debug: Log raw event and message
    if CombatStats.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Event: " .. event .. ", Message: " .. message)
    end

    -- Extract damage value
    local damage = nil
    local startPos, endPos = string.find(message, "%d+")
    if startPos and endPos then
        damage = tonumber(string.sub(message, startPos, endPos))
    end
    if not damage then
        if CombatStats.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r No damage found in message.")
        end
        return
    end

    local time = GetTime()
    if not CombatStats.data.combatStart then CombatStats.data.combatStart = time end
    local elapsed = time - CombatStats.data.combatStart

    -- Damage dealt
    if event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_COMBAT_SELF_CRITS" then
        CombatStats.data.damageDealt = CombatStats.data.damageDealt + damage
        CombatStats.data.attacksDealt = CombatStats.data.attacksDealt + 1
        local dps = elapsed > 0 and Round(CombatStats.data.damageDealt / elapsed, 1) or 0
        AddMessage(infoWindow, string.format("Dealt: %d | DPS: %.1f", damage, dps))
        if UnitExists("target") then
            local health = UnitHealth("target")
            CombatStats.data.timeToTargetDeath = dps > 0 and Round(health / dps, 1) or 0
        end
        if CombatStats.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Damage dealt: " .. damage .. ", Total: " .. CombatStats.data.damageDealt)
        end

    -- Damage taken
    elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" or event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
        CombatStats.data.damageTaken = CombatStats.data.damageTaken + damage
        -- Prefer recent-window DTPS (multi-mob aware) if available, fallback to long average
        local dtpsLong = elapsed > 0 and (CombatStats.data.damageTaken / elapsed) or 0
        local dtpsRecent, attackers = 0, 0
        if CombatWarn_GetRecent then
            local d, n = CombatWarn_GetRecent()
            dtpsRecent, attackers = d or 0, n or 0
        end
        local usedDtps = dtpsRecent > 0 and dtpsRecent or dtpsLong
        AddMessage(infoWindow, string.format("Taken: %d | DTPS: %.1f%s", damage, Round(usedDtps, 1), (attackers and attackers > 1) and (" (" .. attackers .. " mobs)") or ""))
        local health = UnitHealth("player")
        CombatStats.data.timeToPlayerDeath = usedDtps > 0 and Round(health / usedDtps, 1) or 0
        if CombatStats.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Damage taken: " .. damage .. ", Total: " .. CombatStats.data.damageTaken .. ", usedDtps=" .. string.format("%.2f", usedDtps))
        end
    end

    -- Update death prediction
    local mobsText = ""
    if CombatWarn_GetRecent then
        local _, n = CombatWarn_GetRecent()
        if n and n > 1 then mobsText = " [" .. n .. " mobs]" end
    end
    AddMessage(deathWindow, string.format("Seconds until Target Death: %.1f / Me: %.1f%s",
        CombatStats.data.timeToTargetDeath, CombatStats.data.timeToPlayerDeath, mobsText))
end

-- Function to toggle debug mode
function CombatStats:ToggleDebug(state)
    state = strlower(state or "")  -- Case-insensitive input
    if state == "on" then
        self.debug = true
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats]|r Debug mode enabled.")
    elseif state == "off" then
        self.debug = false
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats]|r Debug mode disabled.")
    else
        -- Toggle current state if no argument is provided
        self.debug = not self.debug
        local status = self.debug and "enabled" or "disabled"
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats]|r Debug mode " .. status .. ".")
    end
end

-- Slash command handler
SlashCmdList["COMBATSTATS"] = function(msg)
    local _, _, cmd, arg = string.find(msg, "(%a+)%s*(%a*)")
    cmd = strlower(cmd or "")
    arg = strlower(arg or "")
    if cmd == "debug" then
        CombatStats:ToggleDebug(arg)
    else
        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats]|r Available commands: debug [on|off]")
    end
end
SLASH_COMBATSTATS1 = "/combatstats"

-- Provide a fallback registration for Aux offline search slash commands
SLASH_AUXFIND1 = "/auxfind"
SLASH_AUXFIND2 = "/afind"
SLASH_VANFIND1 = "/vanfind"
SlashCmdList["AUXFIND"] = function(msg)
    msg = msg or ""
    msg = gsub(msg, "^%s+", "")
    msg = gsub(msg, "%s+$", "")
    if AuxFind_HandleSlash then
        AuxFind_HandleSlash(msg)
        return
    end
    if AuxFind_Run then
        AuxFind_Run(msg)
        else
        -- Minimal inline fallback using Aux saved variables
        -- Create a tiny AuxFind window locally so results never spam combat/info windows
        local function LocalAuxFind_Open()
            local f = (getglobal and getglobal("AuxFindFrame")) or AuxFindFrame
            if not f then
                f = CreateFrame("Frame", "AuxFindFrame", UIParent)
                f:SetWidth(400); f:SetHeight(260)
                f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
                f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
                f:SetBackdropColor(0, 0, 0, 1)
                f:EnableMouse(true)
                f:SetMovable(true)
                f:RegisterForDrag("LeftButton")
                f:SetScript("OnDragStart", function() f:StartMoving() end)
                f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
                local close = CreateFrame("Button", nil, f, "UIPanelCloseButton"); close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
                local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10); title:SetText("Aux Search")
                local eb = CreateFrame("EditBox", "AuxFindEditBox", f, "InputBoxTemplate")
                eb:SetAutoFocus(false)
                eb:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -32)
                eb:SetWidth(280); eb:SetHeight(20)
                eb:SetText("")
                local go = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
                go:SetWidth(80); go:SetHeight(20)
                go:SetText("Search")
                go:SetPoint("LEFT", eb, "RIGHT", 6, 0)
                local scroll = CreateFrame("ScrollingMessageFrame", "AuxFindResultsScroll", f)
                scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -60)
                scroll:SetWidth(380); scroll:SetHeight(180)
                scroll:SetFontObject(GameFontNormal)
                scroll:SetJustifyH("LEFT")
                scroll:SetMaxLines(1000)
                scroll:EnableMouseWheel(true)
                scroll:SetScript("OnMouseWheel", function()
                    if arg1 > 0 then scroll:ScrollUp() else scroll:ScrollDown() end
                end)
                go:SetScript("OnClick", function()
                    local q = eb:GetText() or ""
                    SlashCmdList["AUXFIND"](q)
                end)
                -- Enter key triggers immediate search (fallback UI)
                eb:SetScript("OnEnterPressed", function()
                    local q = this:GetText() or ""
                    SlashCmdList["AUXFIND"](q)
                end)
                eb:SetScript("OnTextChanged", function()
                    local txt = this:GetText() or ""
                    if strlen(txt) >= 3 then
                        if (this._last_q or "") ~= txt and (GetTime() - (this._last_t or 0)) > 0.5 then
                            this._last_q = txt; this._last_t = GetTime(); SlashCmdList["AUXFIND"](txt)
                        end
                    end
                end)
                -- Allow closing with ESC when using fallback window
                UISpecialFrames = UISpecialFrames or {}
                local found = false
                for i = 1, (getn and getn(UISpecialFrames) or 0) do if UISpecialFrames[i] == "AuxFindFrame" then found = true break end end
                if not found then tinsert(UISpecialFrames, "AuxFindFrame") end
            end
            f:Show()
            local eb = (getglobal and getglobal("AuxFindEditBox")) or AuxFindEditBox
            if eb and eb.SetFocus then eb:SetFocus() end
        end
        local function LocalAuxFind_Display(lines)
            local function arrlen(t)
                if getn then return getn(t) end
                if table and table.getn then return table.getn(t) end
                local n = 0; for _ in pairs(t) do n = n + 1 end; return n
            end
            LocalAuxFind_Open()
            local scroll = (getglobal and getglobal("AuxFindResultsScroll")) or AuxFindResultsScroll
            if scroll and scroll.Clear then scroll:Clear() end
            for i = 1, arrlen(lines) do
                if scroll and scroll.AddMessage then scroll:AddMessage(lines[i]) else DEFAULT_CHAT_FRAME:AddMessage(lines[i]) end
            end
            if scroll and scroll.ScrollToBottom then scroll:ScrollToBottom() end
        end
        if not aux or not aux.account or not aux.account.item_ids then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[AuxFind]|r Aux DB not available. Ensure aux-addon is enabled.")
            return
        end
        local function coins(c)
            c = tonumber(c or 0) or 0
            local g = floor(c / 10000)
            local s = floor(mod(c, 10000) / 100)
            local cc = floor(mod(c, 100))
            if g > 0 then return format("%dg %ds %dc", g, s, cc) end
            if s > 0 then return format("%ds %dc", s, cc) end
            return format("%dc", cc)
        end
        local function faction_key()
            local realm = GetCVar("realmName") or "?"
            local faction = UnitFactionGroup("player") or "Alliance"
            return realm .. "|" .. faction
        end
        local function parse_post_value(v)
            if type(v) ~= "string" then return nil, nil end
            local _, _, _dur, minp, buy = string.find(v, "^(%d+)%#([%d%.]+)%#([%d%.]+)")
            if minp then minp = tonumber(minp) end
            if buy then buy = tonumber(buy) end
            return minp, buy
        end
        local function median_from_history(s)
            if type(s) ~= "string" then return nil end
            local vals, n = {}, 0
            for price in string.gfind(s, "([%d%.]+)@") do
                local v = tonumber(price)
                if v and v > 0 then n = n + 1; vals[n] = v end
            end
            if n == 0 then return nil end
            table.sort(vals)
            if mod(n, 2) == 1 then
                return vals[(n + 1) / 2]
            else
                return (vals[n / 2] + vals[n / 2 + 1]) / 2
            end
        end
        local function has_all_tokens(name, query)
            name = strlower(name or "")
            name = gsub(name, "[^%w]+", " ")
            name = gsub(name, "%s+", " ")
            name = " " .. name .. " "
            for tok in string.gfind(strlower(query or ""), "(%w+)") do
                local needle = " " .. tok .. " "
                if not strfind(name, needle, 1, 1) then return false end
            end
            return true
        end
        local function run_search(query)
            local post, hist = nil, nil
            if aux and aux.faction then
                local fk = faction_key()
                post = aux.faction[fk] and aux.faction[fk].post or nil
                hist = aux.faction[fk] and aux.faction[fk].history or nil
            end
            local hits, n = {}, 0
            -- Numeric ID support
            local idq = nil; do local _, _, d = string.find(query or "", "^(%d+)$"); if d then idq = tonumber(d) end end
            for name, id in pairs(aux.account.item_ids) do
                if (idq and tonumber(id) == idq) or (not idq and has_all_tokens(name, query)) then
                    n = n + 1
                    hits[n] = { name = name, id = id }
                    if n >= 50 then break end
                end
            end
            if n == 0 then
                LocalAuxFind_Display({"|cffffff00[AuxFind]|r No matches for: " .. (query or "")})
                return
            end
            table.sort(hits, function(a, b) return a.name < b.name end)
            local function arrlen(t)
                if getn then return getn(t) end
                if table and table.getn then return table.getn(t) end
                local n = 0; for _ in t do n = n + 1 end; return n
            end
            local function arrlen(t)
                if getn then return getn(t) end
                if table and table.getn then return table.getn(t) end
                local n = 0; for _ in t do n = n + 1 end; return n
            end
            local lines = {"|cffffff00[AuxFind]|r Results for '" .. (query or "") .. "':"}
            local shown = 0
            for i = 1, n do
                local it = hits[i]
                local priceText = nil
                if post then
                    local key0 = tostring(it.id) .. ":0"
                    local minp, buy = parse_post_value(post[key0])
                    if minp and buy then priceText = coins(minp) .. " | " .. coins(buy) end
                    if not priceText then
                        for k, v in pairs(post) do
                            if strfind(k, "^" .. tostring(it.id) .. ":") then
                                local m2, b2 = parse_post_value(v)
                                if m2 and b2 then priceText = coins(m2) .. " | " .. coins(b2); break end
                            end
                        end
                    end
                end
                if (not priceText) and hist then
                    local best = hist[tostring(it.id) .. ":0"]
                    if not best then
                        for k, v in pairs(hist) do
                            if strfind(k, "^" .. tostring(it.id) .. ":") then best = v; break end
                        end
                    end
                    local med = median_from_history(best)
                    if med and med > 0 then priceText = "median ~ " .. coins(med) end
                end
                if priceText then
                    lines[arrlen(lines) + 1] = format("- %s (%d): %s", it.name, it.id, priceText)
                    shown = shown + 1
                    if shown >= 12 then
                        lines[arrlen(lines) + 1] = "... more results omitted. Refine your search."
                        break
                    end
                end
            end
            if shown == 0 then
                LocalAuxFind_Display({"|cffffff00[AuxFind]|r No priced matches for '" .. (query or "") .. "'."})
            else
                LocalAuxFind_Display(lines)
            end
        end

        -- Fallback commands and search
        if msg == "" then
            LocalAuxFind_Open(); return
        elseif msg == "icon" or msg == "button" then
            -- Minimal icon: center it for visibility and allow drag
            local parent = Minimap or UIParent
            local btn = AuxSearchMinimapButton or CreateFrame("Button", "AuxSearchMinimapButton", parent)
            btn:SetWidth(31); btn:SetHeight(31)
            btn:SetFrameStrata("HIGH"); btn:SetFrameLevel(10)
            btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            btn:SetMovable(true); btn:EnableMouse(true); btn:RegisterForDrag("LeftButton")
            btn:SetScript("OnDragStart", function() btn:StartMoving() end)
            btn:SetScript("OnDragStop", function() btn:StopMovingOrSizing() end)
            btn:ClearAllPoints()
            if Minimap then
                btn:SetPoint("TOPRIGHT", Minimap, "TOPRIGHT", -8, -8)
            else
                btn:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            end
            if not btn.icon then
                local overlay = btn:CreateTexture(nil, "OVERLAY")
                overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
                overlay:SetWidth(52); overlay:SetHeight(52)
                overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
                local icon = btn:CreateTexture(nil, "ARTWORK")
                icon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_02")
                icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
                icon:SetWidth(20); icon:SetHeight(20)
                icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
                btn.icon = icon
            end
            btn:SetScript("OnClick", function() LocalAuxFind_Open() end)
            btn:Show(); return
        elseif msg == "center" then
            if AuxSearchMinimapButton then AuxSearchMinimapButton:ClearAllPoints(); AuxSearchMinimapButton:SetPoint("CENTER", UIParent, "CENTER", 0, 0); AuxSearchMinimapButton:Show() end; return
        else
            run_search(msg)
        end
    end
end

-- Mirror handler for /vanfind alias
SlashCmdList["VANFIND"] = function(msg)
    SlashCmdList["AUXFIND"](msg)
end

-- Event handler
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS")
eventFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
eventFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function()
    if event == "PLAYER_LOGIN" then
        AddMessage(infoWindow, "CombatStats v" .. CombatStats.version .. " loaded.")
        AddMessage(infoWindow, "WoW Version: " .. GetBuildInfo())
        AddMessage(infoWindow, "Lua Version: " .. (_VERSION or "Unknown"))
        statsWindow:Show()
        deathWindow:Show()
        infoWindow:Show()
        if CombatStats.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Addon initialized.")
        end
        -- Enable mouse wheel scrolling on standard chat window
        DEFAULT_CHAT_FRAME:EnableMouseWheel(true)
        DEFAULT_CHAT_FRAME:SetScript("OnMouseWheel", function()
            if arg1 > 0 then DEFAULT_CHAT_FRAME:ScrollUp() else DEFAULT_CHAT_FRAME:ScrollDown() end
        end)
        -- Re-register AuxFind slashes on login to be safe
        SLASH_AUXFIND1 = "/auxfind"; SLASH_AUXFIND2 = "/afind"; SLASH_VANFIND1 = "/vanfind"
        SlashCmdList["VANFIND"] = SlashCmdList["VANFIND"] or function(msg) SlashCmdList["AUXFIND"](msg) end
        AddMessage(infoWindow, "AuxFind ready: /auxfind /afind /vanfind")
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED" then
        UpdateCombatState()
    else
        ParseCombatMessage(event, arg1)
    end
end)

-- Periodic combat state check
eventFrame:SetScript("OnUpdate", function()
    if (this.tick or 1) > GetTime() then return end
    this.tick = GetTime() + 0.5 -- Check every 0.5 seconds
    UpdateCombatState()
end)




-- Player-specific features

-- VersionTracker: Grok-addon-1.2.5
-- Context: Combined player-specific features (CrazyFrog and Wisdom Button) under a single do block for smoother checking. Assumes "Crazyforg" is the character for both; adjust names if different chars.

do
    local playerName = UnitName("player")
    local _, class = UnitClass("player")

    if playerName == "Crazyforg" then
        -- Crazy Frog Feature
        -- Context: Only run Crazy Frog feature when UnitName("player") == "Crazyforg". 
        -- API: UnitName("unit") returns the unit’s name (and realm if cross-realm).

        local crazyPhrases = {
            lowHealth      = "Baa aramba baa bom baa barooumba!",
            critHit        = "Ring ding ding ding daa baa!",
            dodged         = "Oops! Slippery like a frog!",
            killingBlow    = "Safe and sound, ba, da, da!",
            gainedBuff     = "Power up! Ding, da, ding!",
            enteredCombat  = "Let's goooo! Bom bom baa da bom!",
            leftCombat     = "All clear! Boing boing boing!",
        }

        local function CrazyFrog_OnEvent()
            local event = event  -- global var in 1.12
            local msg   = arg1  -- arg1 is the first message param
            if event == "CHAT_MSG_COMBAT_SELF_CRITS" then
                SendChatMessage(crazyPhrases.critHit, "SAY")
            elseif event == "CHAT_MSG_COMBAT_SELF_HITS" and string.find(msg, "dodge") then
                SendChatMessage(crazyPhrases.dodged, "SAY")
            elseif event == "CHAT_MSG_COMBAT_SELF_HITS" and string.find(msg, "You") and string.find(msg, "slain") then
                SendChatMessage(crazyPhrases.killingBlow, "SAY")
            elseif event == "UNIT_HEALTH" and arg1 == "player" then
                local hp, maxHp = UnitHealth("player"), UnitHealthMax("player")
                if maxHp > 0 and hp / maxHp < 0.25 then
                    SendChatMessage(crazyPhrases.lowHealth, "SAY")
                end
            elseif event == "PLAYER_REGEN_DISABLED" then
                SendChatMessage(crazyPhrases.enteredCombat, "SAY")
            elseif event == "PLAYER_REGEN_ENABLED" then
                SendChatMessage(crazyPhrases.leftCombat, "SAY")
            end
        end

        local crazyFrame = CreateFrame("Frame")
        crazyFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
        crazyFrame:RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS")
        crazyFrame:RegisterEvent("UNIT_HEALTH")
        crazyFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        crazyFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        crazyFrame:SetScript("OnEvent", CrazyFrog_OnEvent)
    end

    if  class == "PALADIN" then
        -- Wisdom Button for Paladin
        -- Context: Shows a button if no Blessing of Wisdom buff; clicking casts it on self.

        -- Create the button
        local wisdomButton = CreateFrame("Button", "WisdomButton", UIParent, "UIPanelButtonTemplate")
        wisdomButton:SetWidth(120)
        wisdomButton:SetHeight(30)
        wisdomButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -20, 20)  -- Bottom-right with padding
        wisdomButton:SetText("Bless Wisdom")
        wisdomButton:SetScript("OnClick", function()
            CastSpellByName("Blessing of Wisdom")
        end)

        -- Function to check for Blessing of Wisdom buff
        local function HasWisdomBuff()
            for i = 1, 16 do  -- Vanilla max buffs
                local texture = UnitBuff("player", i)
                if texture == "Interface\\Icons\\Spell_Holy_SealOfWisdom" then
                    return true
                end
            end
            return false
        end

        -- Frame for event handling
        local wisdomFrame = CreateFrame("Frame")
        wisdomFrame:RegisterEvent("PLAYER_AURAS_CHANGED")
        wisdomFrame:SetScript("OnEvent", function()
            if HasWisdomBuff() then
                wisdomButton:Hide()
            else
                wisdomButton:Show()
            end
        end)

        -- Initial check on load
        if HasWisdomBuff() then
            wisdomButton:Hide()
        else
            wisdomButton:Show()
        end
    end
end


-- VersionTracker: Grok-addon-1.2.5
-- Context: Player-specific features combined under single check block for efficiency. If features are for different characters, replace the second 'if playerName == "Crazyforg"' with the actual paladin name.
