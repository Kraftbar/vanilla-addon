-- Initialize variables to keep track of damage and attacks
local totalDamage = 0
local numAttacks = 0

-- Function that handles combat events
local function onCombatEvent()
    -- TODO: Spells trigger this even with no damage in the message, so filter those out
    -- Find the first number in the combat message and parse it as damage
    local startPos, endPos = string.find(arg1, "%d+")
    local damage = tonumber(string.sub(arg1, startPos, endPos))

    -- Output the damage to the default chat frame
    DEFAULT_CHAT_FRAME:AddMessage(damage)

    -- Update the total damage and number of attacks
    totalDamage = totalDamage + damage
    numAttacks = numAttacks + 1

    -- Calculate and output the mean damage
    local meanDamage = totalDamage / numAttacks
    DEFAULT_CHAT_FRAME:AddMessage("Mean damage: " .. meanDamage)
end

-- Create a new frame and register for combat events
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS") -- Also consider CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS")
frame:SetScript("OnEvent", onCombatEvent)
