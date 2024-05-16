-- health.lua

-- Create the message window
local healthWindow = CreateMessageWindow("HealthWindow", 300, 100)
healthWindow:SetPoint("CENTER", UIParent, "CENTER", 150, 0) -- Ensure it's properly positioned

-- Function that updates the health information in the health frame
local function onHealthEvent()
    
    local curHealth = UnitHealth("target")
    local maxHealth = UnitHealthMax("target")

    -- Update the text in the health frame with the current and max health
    local message = "Current target health: " .. curHealth .. ", Max health: " .. maxHealth
    AddMessage(healthWindow, message)
    
    local curHealth = UnitHealth("player")
    local maxHealth = UnitHealthMax("player")

    -- Update the text in the health frame with the current and max health
    local message = "Current player health: " .. curHealth .. ", Max health: " .. maxHealth
    AddMessage(healthWindow, message)
end

-- Create a new frame and register for unit health events
local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("PLAYER_TARGET_CHANGED") -- Ensure updates when target changes
frame:SetScript("OnEvent", onHealthEvent)
