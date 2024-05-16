-- window.lua

function CreateMessageWindow(name, width, height, parent)
    local messageWindow = CreateFrame("Frame", name, parent or UIParent)
    messageWindow:SetWidth(width)
    messageWindow:SetHeight(height)
    messageWindow:SetPoint("CENTER", UIParent, "CENTER") -- Corrected this line
    messageWindow:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    messageWindow:SetBackdropColor(0, 0, 0, 1)

    -- Create the scrolling message frame
    messageWindow.scrollFrame = CreateFrame("ScrollingMessageFrame", nil, messageWindow)
    messageWindow.scrollFrame:SetPoint("TOPLEFT", messageWindow, "TOPLEFT", 10, -10)
    messageWindow.scrollFrame:SetWidth(width - 20)
    messageWindow.scrollFrame:SetHeight(height - 20)
    messageWindow.scrollFrame:SetFontObject(GameFontNormal)
    messageWindow.scrollFrame:SetJustifyH("LEFT")
    messageWindow.scrollFrame:SetMaxLines(100)
    messageWindow.scrollFrame:EnableMouseWheel(true)
    messageWindow.scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)

    -- Make the window draggable
    messageWindow:SetMovable(true)
    messageWindow:EnableMouse(true)
    messageWindow:RegisterForDrag("LeftButton")
    messageWindow:SetScript("OnDragStart", function() messageWindow:StartMoving() end)
    messageWindow:SetScript("OnDragStop", function() messageWindow:StopMovingOrSizing() end)

    return messageWindow
end

function AddMessage(messageWindow, message)
    messageWindow.scrollFrame:AddMessage(message)
    messageWindow.scrollFrame:ScrollToBottom()
end
