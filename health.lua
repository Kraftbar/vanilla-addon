
local healthFrame = CreateHealthFrame(TargetFrame,0)


-- Function that updates the health information in the health frame
local function onHealthEvent()
    -- Get the current and max health of the target
    local curHealth = UnitHealth("target")
    local maxHealth = UnitHealthMax("target")
    
    -- Update the text in the health frame with the current and max health
    healthFrame.text:SetText("Current health: " .. curHealth .. ", Max health: " .. maxHealth)
end

-- Create a new frame and register for unit health events
local frame = CreateFrame("Frame")

---------------------------
frame:RegisterEvent("UNIT_HEALTH")
frame:SetScript("OnEvent", onHealthEvent)



local testhealthFrame = CreateHealthFrame(TargetFrame,1)
testhealthFrame.text:SetText("Current health: asdasdsad")