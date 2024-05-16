############ dmg.lua ############

-- Initialize variables to keep track of damage, attacks, and time
local totalDamageDealt = 0
local totalDamageTaken = 0
local numAttacksDealt = 0
local combatStartTime = nil

-- Create the message window for combat stats
local combatStatsWindow = CreateMessageWindow("CombatStatsWindow", 300, 200)
combatStatsWindow:SetPoint("CENTER", UIParent, "CENTER", -150, 0) -- Adjust this line if needed
combatStatsWindow:SetFrameStrata("HIGH")  -- Ensure it's on top of other UI elements
combatStatsWindow:Show()  -- Make sure the window is shown

-- Create the third window for displaying seconds until death
local secondsUntilDeathWindow = CreateMessageWindow("SecondsUntilDeathWindow", 300, 30)
secondsUntilDeathWindow:SetPoint("CENTER", UIParent, "CENTER", 0, -250) -- Adjust this line if needed
secondsUntilDeathWindow:SetFrameStrata("HIGH")  -- Ensure it's on top of other UI elements
secondsUntilDeathWindow:Show()  -- Make sure the window is shown

-- Variables to store seconds until death
local secondsUntilTargetDeath = 0
local secondsUntilPlayerDeath = 0

-- Reset function to be called when combat ends
local function resetCombatStats()
    totalDamageDealt = 0
    totalDamageTaken = 0
    numAttacksDealt = 0
    combatStartTime = nil
    secondsUntilTargetDeath = 0
    secondsUntilPlayerDeath = 0
end

-- Function that handles combat events
local function onCombatEvent()
    -- Debug: Print event and combatMessage to the default chat frame
    local combatMessage = arg1
    DEFAULT_CHAT_FRAME:AddMessage("Event: " .. (event or "nil"))
    DEFAULT_CHAT_FRAME:AddMessage("combatMessage: " .. (combatMessage or "nil"))

    if event == "PLAYER_REGEN_ENABLED" then
        -- Calculate and output the DPS (damage dealt) and DTPS (damage taken per second) at the end of combat
        if combatStartTime then
            local elapsedTime = GetTime() - combatStartTime
            local dpsDealt = totalDamageDealt / elapsedTime
            local dtpsTaken = totalDamageTaken / elapsedTime
            AddMessage(combatStatsWindow, string.format("Combat ended. DTPS (Taken): %.1f", dtpsTaken))
            AddMessage(combatStatsWindow, string.format("Combat ended. DPS  (Dealt): %.1f", dpsDealt))
        end
        resetCombatStats()
        AddMessage(secondsUntilDeathWindow, string.format("Seconds until Target Death: %.1f / Me: %.1f", 0, 0))
        return
    end

    -- Check if combatMessage is nil
    if not combatMessage then
        return
    end

    -- Find the first number in the combat message and parse it as damage
    local startPos, endPos = string.find(combatMessage, "%d+")
    if startPos and endPos then
        local damage = tonumber(string.sub(combatMessage, startPos, endPos))

        -- Update variables depending on the type of event
        if event == "CHAT_MSG_COMBAT_SELF_HITS" or event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_COMBAT_SELF_CRITS" then
            -- Debug: Print the damage dealt value to the default chat frame
            DEFAULT_CHAT_FRAME:AddMessage("Damage Dealt: " .. damage)

            -- Update the total damage dealt and number of attacks dealt
            totalDamageDealt = totalDamageDealt + damage
            numAttacksDealt = numAttacksDealt + 1

            -- Start the combat timer if it's the first attack
            if not combatStartTime then
                combatStartTime = GetTime()
            end

            -- Calculate the elapsed time and DPS (damage dealt)
            local elapsedTime = GetTime() - combatStartTime
            local dpsDealt = totalDamageDealt / elapsedTime

            -- Debug: Output the damage and mean damage dealt in the chat frame
            local outputMessage = string.format("Damage Dealt: %.1f |  DPS:  %.1f", damage, dpsDealt)
            DEFAULT_CHAT_FRAME:AddMessage(outputMessage)

            -- Calculate seconds until target's death
            local targetCurrentHealth = UnitHealth("target")
            secondsUntilTargetDeath = targetCurrentHealth / dpsDealt
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Seconds until Target Death: %.1f", secondsUntilTargetDeath))  -- Added

        elseif event == "CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS" or event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
            -- Debug: Print the damage taken value to the default chat frame
            DEFAULT_CHAT_FRAME:AddMessage("Damage Taken: " .. damage)

            -- Update the total damage taken
            totalDamageTaken = totalDamageTaken + damage

            -- Start the combat timer if it's the first attack
            if not combatStartTime then
                combatStartTime = GetTime()
            end

            -- Calculate the elapsed time and DTPS (damage taken per second)
            local elapsedTime = GetTime() - combatStartTime
            local dtpsTaken = totalDamageTaken / elapsedTime

            -- Debug: Output the damage taken in the chat frame
            local outputMessage = string.format("Damage Taken: %.1f | DTPS: %.1f", damage, dtpsTaken)
            DEFAULT_CHAT_FRAME:AddMessage(outputMessage)

            -- Calculate seconds until player's death
            local playerCurrentHealth = UnitHealth("player")
            secondsUntilPlayerDeath = playerCurrentHealth / dtpsTaken
            DEFAULT_CHAT_FRAME:AddMessage(string.format("Seconds until Player Death: %.1f", secondsUntilPlayerDeath))  -- Added

        end

        -- Update the third window with both values on one line
        AddMessage(secondsUntilDeathWindow, string.format("Seconds until Target Death: %.1f / Me: %.1f", secondsUntilTargetDeath, secondsUntilPlayerDeath))
        DEFAULT_CHAT_FRAME:AddMessage(string.format("Seconds until Target Death: %.1f / Me: %.1f", secondsUntilTargetDeath, secondsUntilPlayerDeath))  -- Added

    else
        -- Debug: No damage found in combatMessage
        DEFAULT_CHAT_FRAME:AddMessage("No damage found in combatMessage.")
    end        
end

-- Create a new frame and register for combat events
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS")
frame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
frame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
frame:RegisterEvent("PLAYER_REGEN_ENABLED") -- Event for leaving combat

frame:SetScript("OnEvent", onCombatEvent)
