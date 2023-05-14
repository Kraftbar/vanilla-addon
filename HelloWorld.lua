
Sandbox = { }

function Sandbox:HelloWorld()
    message("Hello World!")
end

function Sandbox:HideGryphons()
    MainMenuBarLeftEndCap:Hide()
    MainMenuBarRightEndCap:Hide()
end
local totalDamage = 0
local numAttacks = 0
local function onCombatEvent()
    local startPos, endPos = string.find(arg1, "%d+")
    local damage = tonumber(string.sub(arg1, startPos, endPos))
    DEFAULT_CHAT_FRAME:AddMessage(arg1   )


    totalDamage = totalDamage + damage
    numAttacks = numAttacks + 1
    local meanDamage = totalDamage / numAttacks
    DEFAULT_CHAT_FRAME:AddMessage("Mean damage: " .. meanDamage)
    
end


local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_HITS")
frame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
frame:RegisterEvent("CHAT_MSG_COMBAT_SELF_CRITS")
frame:SetScript("OnEvent", onCombatEvent)
