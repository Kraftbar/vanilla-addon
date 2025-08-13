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
        local dtps = elapsed > 0 and Round(CombatStats.data.damageTaken / elapsed, 1) or 0
        AddMessage(infoWindow, string.format("Taken: %d | DTPS: %.1f", damage, dtps))
        local health = UnitHealth("player")
        CombatStats.data.timeToPlayerDeath = dtps > 0 and Round(health / dtps, 1) or 0
        if CombatStats.debug then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Damage taken: " .. damage .. ", Total: " .. CombatStats.data.damageTaken)
        end
    end

    -- Update death prediction
    AddMessage(deathWindow, string.format("Seconds until Target Death: %.1f / Me: %.1f",
        CombatStats.data.timeToTargetDeath, CombatStats.data.timeToPlayerDeath))
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
        wisdomButton:SetPoint("CENTER", UIParent, "CENTER", 0, -200)  -- Position it somewhere visible
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