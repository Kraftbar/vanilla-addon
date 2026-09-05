-- Combat windows and history UI. Remove this file from the TOC for headless tracking.

local VA = VanillaAddon
local UI = { historyOffset = 0, historyVisibleRows = 13 }
VA.CombatUI = UI
VA:RegisterModule("combat-ui", UI)

local historyColumns = {
    { key = "when", x = 0, width = 165, title = "When" },
    { key = "target", x = 169, width = 180, title = "Target" },
    { key = "level", x = 353, width = 45, title = "Lvl", right = true },
    { key = "time", x = 402, width = 55, title = "Time", right = true },
    { key = "dps", x = 461, width = 68, title = "DPS", right = true },
    { key = "dtps", x = 533, width = 68, title = "DTPS", right = true },
}

local function makeHistoryText(parent, column, font)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    text:SetPoint("TOPLEFT", parent, "TOPLEFT", column.x + 3, 0)
    text:SetWidth(column.width - 6)
    text:SetJustifyH(column.right and "RIGHT" or "LEFT")
    return text
end

local function formatTargetLevel(level)
    level = tonumber(level)
    if not level then return "--" end
    if level < 0 then return "??" end
    return tostring(level)
end

local function summarizeTargets(row)
    local targets = row.targets
    local count = VA:ArrayLen(targets)
    if count == 0 then
        return row.target or "Unknown", formatTargetLevel(row.targetLevel)
    end
    if count == 1 then
        return targets[1].name or "Unknown", formatTargetLevel(targets[1].level)
    end
    if count == 2 then
        return (targets[1].name or "Unknown") .. ", " .. (targets[2].name or "Unknown"),
            formatTargetLevel(targets[1].level) .. "," .. formatTargetLevel(targets[2].level)
    end
    return (targets[1].name or "Unknown") .. " +" .. (count - 1),
        formatTargetLevel(targets[1].level) .. ",..."
end

local function createMessageWindow(name, positionKey, width, height, xOffset)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetWidth(width)
    frame:SetHeight(height)
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    frame:SetBackdropColor(0, 0, 0, 0.92)
    frame:SetFrameStrata("HIGH")
    VA:ApplyFramePosition(positionKey, frame, "CENTER", xOffset, 0)
    VA:MakeMovable(frame, positionKey)

    local scroll = CreateFrame("ScrollingMessageFrame", name .. "Scroll", frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -10)
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

function UI:CreateWindows()
    if self.stats then return end
    self.stats = createMessageWindow("CombatStatsWindow", "combatStats", 300, 200, -310)
    self.death = createMessageWindow("SecondsUntilDeathWindow", "combatDeath", 300, 34, 0)
    self.info = createMessageWindow("CombatInfoWindow", "combatInfo", 300, 200, 310)
end

local function addMessage(frame, message)
    if frame and frame.scroll then
        frame.scroll:AddMessage(message)
        frame.scroll:ScrollToBottom()
    end
end

function UI:SetVisible(visible)
    self:CreateWindows()
    VA.settings.combat.visible = visible and true or false
    if visible then
        UI.stats:Show(); UI.death:Show(); UI.info:Show()
    else
        UI.stats:Hide(); UI.death:Hide(); UI.info:Hide()
    end
end

function UI:UpdateDeath(snapshot, attackers)
    local function estimate(value)
        if value and value > 0 then return format("%.1fs", value) end
        return "--"
    end
    addMessage(self.death, format("Target: %s / Me: %s%s",
        estimate(snapshot.timeToTargetDeath),
        estimate(snapshot.timeToPlayerDeath),
        attackers and attackers > 1 and (" [" .. attackers .. " attackers]") or ""))
end

local function updateEstimate(snapshot)
    local _, attackers = VA.Combat:GetRecent()
    UI:UpdateDeath(snapshot, attackers)
end

VA:On("COMBAT_UPDATED", function(payload)
    UI:CreateWindows()
    local snapshot = payload.snapshot
    if payload.source then
        addMessage(UI.info, format("Taken: %d | DTPS: %.1f | %s", payload.amount, snapshot.dtps, payload.source))
    else
        addMessage(UI.info, format("Dealt: %d | DPS: %.1f", payload.amount, snapshot.dps))
    end
    updateEstimate(snapshot)
end)

VA:On("COMBAT_ESTIMATE_UPDATED", function(payload) updateEstimate(payload.snapshot) end)

VA:On("COMBAT_ENDED", function(snapshot)
    UI:CreateWindows()
    addMessage(UI.stats, format("%.1fs | Dealt %d (%.1f DPS) | Taken %d (%.1f DTPS)",
        snapshot.elapsed, snapshot.damageDealt, snapshot.dps, snapshot.damageTaken, snapshot.dtps))
    addMessage(UI.death, "Target: -- / Me: --")
    if UI.historyFrame and UI.historyFrame:IsShown() then UI:RefreshHistory() end
end)

function UI:CreateHistory()
    if self.historyFrame then return end
    local frame = CreateFrame("Frame", "CombatHistoryFrame", UIParent)
    frame:SetWidth(650); frame:SetHeight(300)
    frame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    frame:SetBackdropColor(0, 0, 0, 0.96)
    VA:ApplyFramePosition("combatHistory", frame, "CENTER", 0, 0)
    VA:MakeMovable(frame, "combatHistory")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
    title:SetText("Combat History")

    local tableFrame = CreateFrame("Frame", nil, frame)
    tableFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -38)
    tableFrame:SetWidth(620); tableFrame:SetHeight(240)
    -- Rows are offset manually; satisfy UIPanelScrollBarTemplate's inherited
    -- callback without moving the table frame itself.
    tableFrame.SetVerticalScroll = function() end
    for i = 1, VA:ArrayLen(historyColumns) do
        local column = historyColumns[i]
        local header = makeHistoryText(tableFrame, column, "GameFontNormalSmall")
        header:SetText(column.title)
    end

    local rowArea = CreateFrame("Frame", nil, tableFrame)
    rowArea:SetPoint("TOPLEFT", tableFrame, "TOPLEFT", 0, -20)
    rowArea:SetWidth(606); rowArea:SetHeight(208)
    rowArea:EnableMouseWheel(true)
    self.historyRows = {}
    for rowIndex = 1, self.historyVisibleRows do
        local row = CreateFrame("Frame", nil, rowArea)
        row:SetWidth(606); row:SetHeight(16)
        row:SetPoint("TOPLEFT", rowArea, "TOPLEFT", 0, -((rowIndex - 1) * 16))
        row.cells = {}
        for columnIndex = 1, VA:ArrayLen(historyColumns) do
            local column = historyColumns[columnIndex]
            row.cells[column.key] = makeHistoryText(row, column)
        end
        self.historyRows[rowIndex] = row
    end

    local empty = tableFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    empty:SetPoint("TOPLEFT", tableFrame, "TOPLEFT", 3, -24)
    empty:SetText("No completed encounters yet.")
    self.historyEmpty = empty

    local slider = CreateFrame("Slider", nil, tableFrame, "UIPanelScrollBarTemplate")
    slider:SetPoint("TOPRIGHT", tableFrame, "TOPRIGHT", 8, -18)
    slider:SetPoint("BOTTOMRIGHT", tableFrame, "BOTTOMRIGHT", 8, 0)
    slider:SetMinMaxValues(0, 0); slider:SetValueStep(1); slider:SetValue(0)
    slider:SetScript("OnValueChanged", function()
        if UI.historySyncing then return end
        UI.historyOffset = floor((this:GetValue() or 0) + 0.5)
        UI:RenderHistory()
    end)
    self.historySlider = slider
    rowArea:SetScript("OnMouseWheel", function()
        local step = IsShiftKeyDown and IsShiftKeyDown() and 10 or 3
        UI.historyOffset = max(0, min(UI.historyMaxOffset or 0,
            UI.historyOffset + (arg1 > 0 and -step or step)))
        UI:RenderHistory()
    end)

    self.historyFrame = frame
    UISpecialFrames = UISpecialFrames or {}
    tinsert(UISpecialFrames, "CombatHistoryFrame")
end

function UI:RenderHistory()
    local data = VA.db.combatHistory
    local count = VA:ArrayLen(data)
    self.historyMaxOffset = max(0, count - self.historyVisibleRows)
    self.historyOffset = max(0, min(self.historyOffset or 0, self.historyMaxOffset))

    self.historySyncing = true
    self.historySlider:SetMinMaxValues(0, self.historyMaxOffset)
    self.historySlider:SetValue(self.historyOffset)
    self.historySyncing = nil
    if self.historyMaxOffset > 0 then self.historySlider:Show() else self.historySlider:Hide() end
    if count == 0 then self.historyEmpty:Show() else self.historyEmpty:Hide() end

    for i = 1, self.historyVisibleRows do
        local frameRow = self.historyRows[i]
        local row = data[count - self.historyOffset - i + 1]
        if row then
            local targetSummary, levelSummary = summarizeTargets(row)
            frameRow.cells.when:SetText(date("%Y-%m-%d %H:%M:%S", row.endedAt or time()))
            frameRow.cells.target:SetText(VA:TrimText(targetSummary, 26))
            frameRow.cells.level:SetText(levelSummary)
            frameRow.cells.time:SetText(format("%.1fs", row.elapsed or 0))
            frameRow.cells.dps:SetText(format("%.1f", row.dps or 0))
            frameRow.cells.dtps:SetText(format("%.1f", row.dtps or 0))
            frameRow:Show()
        else
            frameRow:Hide()
        end
    end
end

function UI:RefreshHistory()
    self:CreateHistory()
    self:RenderHistory()
end

function UI:ShowHistory()
    self:RefreshHistory()
    self.historyFrame:Show()
end

function UI:ToggleHistory()
    if self.historyFrame and self.historyFrame:IsShown() then
        self.historyFrame:Hide()
    else
        self:ShowHistory()
    end
end

VA:On("PLAYER_READY", function()
    UI:CreateWindows()
    UI:SetVisible(VA.settings.combat.visible)

    local button = CreateFrame("Button", "CombatHistoryMinimapButton", Minimap or UIParent)
    button:SetWidth(31); button:SetHeight(31)
    button:SetFrameStrata("HIGH"); button:SetFrameLevel(9)
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    VA:ApplyFramePosition("combatHistoryButton", button, "BOTTOMLEFT", 8, 8, Minimap or UIParent)
    VA:MakeMovable(button, "combatHistoryButton")

    local overlay = button:CreateTexture(nil, "OVERLAY")
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetWidth(52); overlay:SetHeight(52)
    overlay:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetWidth(20); icon:SetHeight(20)
    icon:SetPoint("CENTER", button, "CENTER", 0, 0)

    button:SetScript("OnClick", function() UI:ToggleHistory() end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:SetText("Combat History")
        GameTooltip:AddLine("Click: open history  Drag: move", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    UI.minimapButton = button

    addMessage(UI.info, "CombatStats v" .. VA.version .. " loaded. /combatstats")
end)
