-- Vanilla 1.12 sales ledger for auctions (no dependency on Aux)

local function ensure_db()
    if not VanillaLedgerDB then
        VanillaLedgerDB = {}
    end
    VanillaLedgerDB.sold = VanillaLedgerDB.sold or {}
    VanillaLedgerDB.expired = VanillaLedgerDB.expired or {}
    VanillaLedgerDB.version = VanillaLedgerDB.version or 1
    if VanillaLedgerDB.debug == nil then VanillaLedgerDB.debug = false end
    VanillaLedgerDB.mailSeen = VanillaLedgerDB.mailSeen or {}
    -- UI preferences (view: all|sold|expired)
    VanillaLedgerDB.view = VanillaLedgerDB.view or "all"
    VanillaLedgerErrors = VanillaLedgerErrors or {}
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("VARIABLES_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("MAIL_INBOX_UPDATE")

local soldPattern
local expiredPattern
local mailSoldPattern
local mailExpiredPattern

local function add_entry(bucket, item)
    tinsert(VanillaLedgerDB[bucket], {
        item = item,
        t = time(),
    })
end

local function ledgerPrint(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[Ledger]|r " .. msg)
end

local function debugPrint(msg)
    if VanillaLedgerDB and VanillaLedgerDB.debug then
        ledgerPrint(msg)
    end
end

local function formatCoins(copper)
    copper = tonumber(copper or 0) or 0
    local g = floor(copper / 10000)
    local s = floor(mod(copper, 10000) / 100)
    local c = floor(mod(copper, 100))
    return format("%dg %ds %dc", g, s, c)
end

local function mailboxSig(subject, money, sender, daysLeft, CODAmount, hasItem)
    subject = subject or ""
    sender = sender or ""
    money = tonumber(money or 0) or 0
    local dl = floor(((daysLeft or 0) * 1000) + 0.5)
    local cod = tonumber(CODAmount or 0) or 0
    local hi = hasItem and 1 or 0
    return subject .. "|" .. tostring(money) .. "|" .. sender .. "|" .. tostring(dl) .. "|" .. tostring(cod) .. "|" .. tostring(hi)
end

local function simpleMailKey(subject, money, sender)
    subject = subject or ""
    sender = sender or ""
    money = tonumber(money or 0) or 0
    return subject .. "|" .. tostring(money) .. "|" .. sender
end

-- Ephemeral dedupe across multiple API paths (resets on reload)
local recentSeen = {}
local function markRecent(key)
    recentSeen[key] = GetTime() or 0
end
local function wasRecent(key)
    local t = recentSeen[key]
    if not t then return false end
    if (GetTime() or 0) - t < 5 then return true end
    recentSeen[key] = nil
    return false
end

local function recordInboxIndex(index, source)
    local a, b, sender, subject, money, CODAmount, daysLeft, hasItem = GetInboxHeaderInfo(index)
    subject = subject or ""
    sender = sender or ""
    money = money or 0
    ensure_db()
    local sig = mailboxSig(subject, money, sender, daysLeft, CODAmount, hasItem)
    local simple = simpleMailKey(subject, money, sender)
    if not VanillaLedgerDB.mailSeen[sig] and not wasRecent(simple) then
        local _, _, soldItem = string.find(subject, mailSoldPattern or "")
        if soldItem and money and money > 0 then
            tinsert(VanillaLedgerDB.sold, { item = soldItem, t = time(), money = money, source = source or "mail" })
            VanillaLedgerDB.mailSeen[sig] = true
            markRecent(simple)
            debugPrint("Inbox(" .. tostring(index) .. ") recorded: " .. soldItem .. " for " .. tostring(money) .. "c (" .. (source or "mail") .. ")")
        end
    end
end

local function dateKey(ts)
    return date("%Y-%m-%d", ts)
end

local function buildSoldGroups(filterDayKey)
    ensure_db()
    local groups = {}
    for i = 1, getn(VanillaLedgerDB.sold) do
        local e = VanillaLedgerDB.sold[i]
        local dkey = dateKey(e.t or time())
        if not filterDayKey or dkey == filterDayKey then
            local price = e.money or -1
            local key = dkey .. "\031" .. (e.item or "?") .. "\031" .. tostring(price)
            if not groups[key] then
                groups[key] = { day = dkey, item = e.item or "?", price = price, count = 0, total = 0 }
            end
            groups[key].count = groups[key].count + 1
            if e.money and e.money > 0 then
                groups[key].total = groups[key].total + e.money
            end
        end
    end
    -- flatten to array
    local arr, n = {}, 0
    for _, g in pairs(groups) do
        n = n + 1
        arr[n] = g
    end
    -- sort: by day desc, then by count desc
    table.sort(arr, function(a, b)
        if a.day ~= b.day then return a.day > b.day end
        if a.count ~= b.count then return a.count > b.count end
        return (a.item or "") < (b.item or "")
    end)
    return arr
end

local function buildDaySummaries()
    ensure_db()
    local dayMap = {}
    for i = 1, getn(VanillaLedgerDB.sold) do
        local e = VanillaLedgerDB.sold[i]
        local dkey = dateKey(e.t or time())
        local price = e.money or -1
        dayMap[dkey] = dayMap[dkey] or { day = dkey, totalCount = 0, totalMoney = 0, groups = {} }
        local day = dayMap[dkey]
        day.totalCount = day.totalCount + 1
        if e.money and e.money > 0 then day.totalMoney = day.totalMoney + e.money end
        local gkey = (e.item or "?") .. "\031" .. tostring(price)
        local g = day.groups[gkey]
        if not g then
            g = { item = e.item or "?", price = price, count = 0, total = 0 }
            day.groups[gkey] = g
        end
        g.count = g.count + 1
        if e.money and e.money > 0 then g.total = g.total + e.money end
    end
    -- flatten and sort per-day groups and days
    local days, n = {}, 0
    for _, d in pairs(dayMap) do
        -- flatten groups
        local arr, m = {}, 0
        for _, g in pairs(d.groups) do m = m + 1; arr[m] = g end
        table.sort(arr, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.item or "") < (b.item or "")
        end)
        d.groups = arr
        n = n + 1; days[n] = d
    end
    table.sort(days, function(a, b) return a.day > b.day end)
    return days
end

-- Build grouped counts for expired (unsold) items
local function buildExpiredGroups(filterDayKey)
    ensure_db()
    local groups = {}
    for i = 1, getn(VanillaLedgerDB.expired) do
        local e = VanillaLedgerDB.expired[i]
        local dkey = dateKey(e.t or time())
        if not filterDayKey or dkey == filterDayKey then
            local key = dkey .. "\031" .. (e.item or "?")
            if not groups[key] then
                groups[key] = { day = dkey, item = e.item or "?", count = 0 }
            end
            groups[key].count = groups[key].count + 1
        end
    end
    local arr, n = {}, 0
    for _, g in pairs(groups) do
        n = n + 1
        arr[n] = g
    end
    table.sort(arr, function(a, b)
        if a.day ~= b.day then return a.day > b.day end
        if a.count ~= b.count then return a.count > b.count end
        return (a.item or "") < (b.item or "")
    end)
    return arr
end

-- Build per-day summaries for expired items
local function buildExpiredDaySummaries()
    ensure_db()
    local dayMap = {}
    for i = 1, getn(VanillaLedgerDB.expired) do
        local e = VanillaLedgerDB.expired[i]
        local dkey = dateKey(e.t or time())
        dayMap[dkey] = dayMap[dkey] or { day = dkey, totalCount = 0, groups = {} }
        local day = dayMap[dkey]
        day.totalCount = day.totalCount + 1
        local gkey = (e.item or "?")
        local g = day.groups[gkey]
        if not g then
            g = { item = e.item or "?", count = 0 }
            day.groups[gkey] = g
        end
        g.count = g.count + 1
    end
    local days, n = {}, 0
    for _, d in pairs(dayMap) do
        local arr, m = {}, 0
        for _, g in pairs(d.groups) do m = m + 1; arr[m] = g end
        table.sort(arr, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.item or "") < (b.item or "")
        end)
        d.groups = arr
        n = n + 1; days[n] = d
    end
    table.sort(days, function(a, b) return a.day > b.day end)
    return days
end

local function printSummary(filter)
    local dk
    if filter == "today" then dk = dateKey(time()) end
    if dk then
        local groups = buildSoldGroups(dk)
        if getn(groups) == 0 then ledgerPrint("No sales recorded for " .. dk) return end
        local total = 0; for i = 1, getn(groups) do total = total + (groups[i].total or 0) end
        ledgerPrint("Summary for " .. dk .. " — total " .. formatCoins(total))
        for i = 1, getn(groups) do
            local g = groups[i]
            local priceText = (g.price and g.price > 0) and (" - total " .. formatCoins(g.total)) or ""
            DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s%s", g.count, g.item, priceText))
        end
        return
    end
    -- all days
    local days = buildDaySummaries()
    if getn(days) == 0 then ledgerPrint("No sales recorded") return end
    ledgerPrint("Daily totals:")
    for i = 1, getn(days) do
        local d = days[i]
        DEFAULT_CHAT_FRAME:AddMessage(format("%s — %d items — %s", d.day, d.totalCount, formatCoins(d.totalMoney)))
    end
end

-- UI view helpers
local function LedgerSetView(view)
    ensure_db()
    view = strlower(view or "")
    if view ~= "all" and view ~= "sold" and view ~= "expired" then
        ledgerPrint("Unknown view. Use: all, sold, expired")
        return
    end
    VanillaLedgerDB.view = view
    ledgerPrint("View set to: " .. view)
    if LedgerFrame and LedgerFrame:IsShown() then ShowLedgerUI() end
end

local function LedgerToggleView()
    ensure_db()
    local v = VanillaLedgerDB.view or "all"
    if v == "all" then v = "sold" elseif v == "sold" then v = "expired" else v = "all" end
    LedgerSetView(v)
end

eventFrame:SetScript("OnEvent", function()
    if event == "VARIABLES_LOADED" then
        ensure_db()
        soldPattern = gsub(ERR_AUCTION_SOLD_S, "%%s", "(.+)")
        expiredPattern = gsub(ERR_AUCTION_EXPIRED_S, "%%s", "(.+)")
        if AUCTION_SOLD_MAIL_SUBJECT then
            mailSoldPattern = gsub(AUCTION_SOLD_MAIL_SUBJECT, "%%s", "(.+)")
        else
            mailSoldPattern = "^Auction successful:%s*(.+)$"
        end
        if AUCTION_EXPIRED_MAIL_SUBJECT then
            mailExpiredPattern = gsub(AUCTION_EXPIRED_MAIL_SUBJECT, "%%s", "(.+)")
        else
            mailExpiredPattern = "^Auction expired:%s*(.+)$"
        end
        debugPrint("VARIABLES_LOADED: patterns initialized")
    elseif event == "ADDON_LOADED" then
        if arg1 == "vanilla-addon" then
            debugPrint("ADDON_LOADED: vanilla-addon")
        end
    elseif event == "PLAYER_LOGIN" then
        ensure_db()
        ledgerPrint("Hello from Ledger!")
        ledgerPrint(string.format("loaded. Sold: %d, Expired: %d. Debug: %s", getn(VanillaLedgerDB.sold), getn(VanillaLedgerDB.expired), VanillaLedgerDB.debug and "on" or "off"))
        -- Create minimap button and UI
        if not LedgerMinimapButton then
            local btn = CreateFrame("Button", "LedgerMinimapButton", Minimap)
            btn:SetWidth(31); btn:SetHeight(31)
            btn:SetFrameStrata("LOW"); btn:SetFrameLevel(8)
            btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
            btn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 8, -8)
            local overlay = btn:CreateTexture(nil, "OVERLAY")
            overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
            overlay:SetWidth(52); overlay:SetHeight(52)
            overlay:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
            local icon = btn:CreateTexture(nil, "ARTWORK")
            icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
            icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
            icon:SetWidth(20); icon:SetHeight(20)
            icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
            btn.icon = icon
            btn:SetScript("OnEnter", function()
                GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
                GameTooltip:SetText("Ledger", 1, 1, 1)
                GameTooltip:AddLine("Left-click: Toggle Ledger UI", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("Right-click: Print today's summary", 0.9, 0.9, 0.9)
                GameTooltip:AddLine("Shift-click: Toggle view (All/Sold/Expired)", 0.9, 0.9, 0.9)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:SetScript("OnClick", function()
                if arg1 == "RightButton" then
                    printSummary("today")
                else
                    if IsShiftKeyDown() then
                        LedgerToggleView()
                    else
                        if LedgerFrame and LedgerFrame:IsShown() then LedgerFrame:Hide() else ShowLedgerUI() end
                    end
                end
            end)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        end
    elseif event == "MAIL_SHOW" then
        -- Trigger an inbox refresh when mailbox opens
        debugPrint("MAIL_SHOW: checking inbox")
        CheckInbox()
    elseif event == "MAIL_INBOX_UPDATE" then
        ensure_db()
        -- Process inbox to capture offline sales and amounts
        local num = GetInboxNumItems()
        debugPrint("MAIL_INBOX_UPDATE: items=" .. tostring(num))
        for i = 1, (num or 0) do
            local a, b, sender, subject, money, CODAmount, daysLeft, hasItem, wasRead, wasReturned = GetInboxHeaderInfo(i)
            subject = subject or ""
            sender = sender or ""
            money = money or 0
            -- Build a signature to avoid duplicates
            local sig = mailboxSig(subject, money, sender, daysLeft, CODAmount, hasItem)
            local simple = simpleMailKey(subject, money, sender)
            if not VanillaLedgerDB.mailSeen[sig] and not wasRecent(simple) then
                local _, _, soldItem = string.find(subject, mailSoldPattern or "")
                if soldItem and money and money > 0 then
                    ensure_db()
                    tinsert(VanillaLedgerDB.sold, { item = soldItem, t = time(), money = money, source = "mail" })
                    VanillaLedgerDB.mailSeen[sig] = true
                    markRecent(simple)
                    debugPrint("Mail sold recorded: " .. soldItem .. " for " .. tostring(money) .. "c")
                else
                    local _, _, expItem = string.find(subject, mailExpiredPattern or "")
                    if expItem then
                        ensure_db()
                        tinsert(VanillaLedgerDB.expired, { item = expItem, t = time(), source = "mail" })
                        VanillaLedgerDB.mailSeen[sig] = true
                        markRecent(simple)
                        debugPrint("Mail expired recorded: " .. expItem)
                    end
                end
            end
        end
    elseif event == "CHAT_MSG_SYSTEM" then
        if not soldPattern then return end
        local msg = arg1
        debugPrint("CHAT_MSG_SYSTEM: " .. tostring(msg))
        if type(msg) == "string" then
            local _, _, item = string.find(msg, soldPattern)
            if item then
                ensure_db()
                add_entry("sold", item)
                debugPrint("Recorded sold: " .. item .. string.format(" (total %d)", getn(VanillaLedgerDB.sold)))
                return
            end
            _, _, item = string.find(msg, expiredPattern)
            if item then
                ensure_db()
                add_entry("expired", item)
                debugPrint("Recorded expired: " .. item .. string.format(" (total %d)", getn(VanillaLedgerDB.expired)))
                return
            end
        end
    end
end)

SLASH_LEDGER1 = "/ledger"
SlashCmdList["LEDGER"] = function(msg)
    ensure_db()
    msg = msg or ""
    msg = gsub(msg, "^%s+", "")
    msg = gsub(msg, "%s+$", "")
    local cmd, argText = "", ""
    local s, e = string.find(msg, "%s+")
    if s then
        cmd = strlower(string.sub(msg, 1, s - 1))
        argText = strlower(string.sub(msg, e + 1))
    else
        cmd = strlower(msg)
    end

    if cmd == "debug" then
        if argText == "on" then
            VanillaLedgerDB.debug = true
            ledgerPrint("Debug enabled")
        elseif argText == "off" then
            VanillaLedgerDB.debug = false
            ledgerPrint("Debug disabled")
        else
            VanillaLedgerDB.debug = not VanillaLedgerDB.debug
            ledgerPrint("Debug " .. (VanillaLedgerDB.debug and "enabled" or "disabled"))
        end
    elseif cmd == "stats" or cmd == "" then
        ledgerPrint(string.format("Sold: %d, Expired: %d", getn(VanillaLedgerDB.sold), getn(VanillaLedgerDB.expired)))
    elseif cmd == "status" then
        ledgerPrint(string.format("Status — Sold: %d, Expired: %d, Debug: %s", getn(VanillaLedgerDB.sold), getn(VanillaLedgerDB.expired), VanillaLedgerDB.debug and "on" or "off"))
    elseif cmd == "reset" then
        local keepDebug = VanillaLedgerDB.debug
        VanillaLedgerDB = { sold = {}, expired = {}, version = 1, debug = keepDebug }
        ledgerPrint("Ledger reset.")
    elseif cmd == "list" then
        local n = 10
        ledgerPrint("Last 10 sold:")
        local soldCount = getn(VanillaLedgerDB.sold)
        for i = max(1, soldCount - n + 1), soldCount do
            local e = VanillaLedgerDB.sold[i]
            local extra = ""
            if e.money then extra = " - " .. formatCoins(e.money) end
            DEFAULT_CHAT_FRAME:AddMessage(format("- %s (%s)%s", e.item, date("%Y-%m-%d %H:%M", e.t), extra))
        end
    elseif cmd == "summary" then
        local which = nil
        if argText == "today" then which = "today" end
        printSummary(which)
    elseif cmd == "view" then
        if argText == nil or argText == "" then
            ledgerPrint("Usage: /ledger view [all|sold|expired]")
        else
            LedgerSetView(argText)
        end
    elseif cmd == "toggleview" or cmd == "tview" then
        LedgerToggleView()
    elseif cmd == "listexpired" or cmd == "lexp" then
        local n = 10
        ledgerPrint("Last 10 expired:")
        local expCount = getn(VanillaLedgerDB.expired)
        for i = max(1, expCount - n + 1), expCount do
            local e = VanillaLedgerDB.expired[i]
            DEFAULT_CHAT_FRAME:AddMessage(format("- %s (%s)", e.item, date("%Y-%m-%d %H:%M", e.t)))
        end
    elseif cmd == "expired" then
        local days = buildExpiredDaySummaries()
        if getn(days) == 0 then ledgerPrint("No expired auctions recorded") return end
        ledgerPrint("Daily expired totals:")
        for i = 1, getn(days) do
            local d = days[i]
            DEFAULT_CHAT_FRAME:AddMessage(format("%s — %d items", d.day, d.totalCount))
        end
    elseif cmd == "dayexp" then
        local dkey = argText and gsub(argText, "^%s+", "") or ""
        if dkey == "" then
            ledgerPrint("Usage: /ledger dayexp YYYY-MM-DD")
        else
            local groups = buildExpiredGroups(dkey)
            if getn(groups) == 0 then ledgerPrint("No expired auctions recorded for " .. dkey) return end
            ledgerPrint("Expired for " .. dkey .. ":")
            for i = 1, getn(groups) do
                local g = groups[i]
                DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s", g.count, g.item))
            end
        end
    elseif cmd == "day" then
        local dkey = argText and gsub(argText, "^%s+", "") or ""
        if dkey == "" then
            ledgerPrint("Usage: /ledger day YYYY-MM-DD")
        else
            local groups = buildSoldGroups(dkey)
            if getn(groups) == 0 then ledgerPrint("No sales recorded for " .. dkey) return end
            local total = 0; for i = 1, getn(groups) do total = total + (groups[i].total or 0) end
            ledgerPrint("Summary for " .. dkey .. " — total " .. formatCoins(total))
            for i = 1, getn(groups) do
                local g = groups[i]
                local priceText = (g.price and g.price > 0) and (" - total " .. formatCoins(g.total)) or ""
                DEFAULT_CHAT_FRAME:AddMessage(format("- %dx %s%s", g.count, g.item, priceText))
            end
        end
    elseif cmd == "days" then
        local days = buildDaySummaries()
        if getn(days) == 0 then ledgerPrint("No sales recorded") return end
        ledgerPrint("Days with activity:")
        for i = 1, getn(days) do
            local d = days[i]
            DEFAULT_CHAT_FRAME:AddMessage(format("%s — %d items — %s", d.day, d.totalCount, formatCoins(d.totalMoney)))
        end
    elseif cmd == "revenue" or cmd == "total" or cmd == "sum" then
        local total = 0
        local counted = 0
        for i = 1, getn(VanillaLedgerDB.sold) do
            local e = VanillaLedgerDB.sold[i]
            if e.money and e.money > 0 then
                total = total + e.money
                counted = counted + 1
            end
        end
        ledgerPrint(format("Revenue: %s (from %d mailed sales)", formatCoins(total), counted))
    elseif cmd == "errors" then
        local n = getn(VanillaLedgerErrors)
        if n == 0 then ledgerPrint("No errors logged") return end
        ledgerPrint("Last errors:")
        for i = max(1, n - 9), n do
            DEFAULT_CHAT_FRAME:AddMessage(VanillaLedgerErrors[i])
        end
    elseif cmd == "clrerrors" then
        VanillaLedgerErrors = {}
        ledgerPrint("Error log cleared")
    else
        DEFAULT_CHAT_FRAME:AddMessage("/ledger [stats|status|list|summary [today]|days|day YYYY-MM-DD|revenue|listexpired|expired|dayexp YYYY-MM-DD|view [all|sold|expired]|toggleview|errors|clrerrors|reset|debug [on|off]]")
    end
end

-- Minimal ledger UI (scrolling frame) toggled by the minimap button
function ShowLedgerUI()
    ensure_db()
    if not LedgerFrame then
        local f = CreateFrame("Frame", "LedgerFrame", UIParent)
        f:SetWidth(320); f:SetHeight(260)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        f:SetBackdropColor(0, 0, 0, 1)
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", function() f:StartMoving() end)
        f:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
        title:SetText("Ledger")
        f.title = title

        local scroll = CreateFrame("ScrollingMessageFrame", "LedgerScroll", f)
        scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -30)
        scroll:SetWidth(300)
        scroll:SetHeight(210)
        scroll:SetFontObject(GameFontNormal)
        scroll:SetJustifyH("LEFT")
        scroll:SetMaxLines(1000)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function()
            if arg1 > 0 then scroll:ScrollUp() else scroll:ScrollDown() end
        end)
        f.scroll = scroll

        -- View buttons (All, Sold, Exp)
        local function makeBtn(name, text, xOff, handler)
            local b = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
            b:SetWidth(54); b:SetHeight(20)
            b:SetPoint("TOPRIGHT", f, "TOPRIGHT", xOff, -8)
            b:SetText(text)
            b:SetScript("OnClick", handler)
            return b
        end
        makeBtn("LedgerBtnAll", "All", -8, function() LedgerSetView("all") end)
        makeBtn("LedgerBtnSold", "Sold", -66, function() LedgerSetView("sold") end)
        makeBtn("LedgerBtnExp", "Exp", -124, function() LedgerSetView("expired") end)

        LedgerFrame = f
    end

    LedgerScroll:Clear()
    local header = "Ledger"
    if VanillaLedgerDB and VanillaLedgerDB.view then
        header = header .. " - " .. strupper(string.sub(VanillaLedgerDB.view, 1, 1)) .. string.sub(VanillaLedgerDB.view, 2)
    end
    if LedgerFrame.title then LedgerFrame.title:SetText(header) end

    local showSold = (VanillaLedgerDB.view == "all" or VanillaLedgerDB.view == "sold")
    local showExp  = (VanillaLedgerDB.view == "all" or VanillaLedgerDB.view == "expired")

    if showSold then
        local days = buildDaySummaries()
        LedgerScroll:AddMessage("Daily Ledger Totals (Sold):")
        for i = 1, getn(days) do
            local d = days[i]
            LedgerScroll:AddMessage(format("%s — %d items — %s", d.day, d.totalCount, formatCoins(d.totalMoney)))
            for j = 1, min(getn(d.groups), 20) do
                local g = d.groups[j]
                local priceText = (g.price and g.price > 0) and (" - total " .. formatCoins(g.total)) or ""
                LedgerScroll:AddMessage(format("  - %dx %s%s", g.count, g.item, priceText))
            end
        end
    end

    if showExp then
        local expDays = buildExpiredDaySummaries()
        if showSold and getn(expDays) > 0 then LedgerScroll:AddMessage(" ") end
        if getn(expDays) > 0 then
            LedgerScroll:AddMessage("Daily Expired Totals (Unsold):")
            for i = 1, getn(expDays) do
                local d = expDays[i]
                LedgerScroll:AddMessage(format("%s — %d items", d.day, d.totalCount))
                for j = 1, min(getn(d.groups), 20) do
                    local g = d.groups[j]
                    LedgerScroll:AddMessage(format("  - %dx %s", g.count, g.item))
                end
            end
        else
            if not showSold then
                LedgerScroll:AddMessage("No expired auctions recorded.")
            end
        end
    end
    LedgerFrame:Show()
end

-- Error logging: wrap the error handler to collect into SavedVariables
do
    local origHandler = geterrorhandler and geterrorhandler() or nil
    local function handler(msg)
        ensure_db()
        local line = format("%s %s", date("%Y-%m-%d %H:%M:%S"), tostring(msg))
        tinsert(VanillaLedgerErrors, line)
        if getn(VanillaLedgerErrors) > 200 then
            table.remove(VanillaLedgerErrors, 1)
        end
        if origHandler then return origHandler(msg) end
    end
    if seterrorhandler then
        seterrorhandler(handler)
    end
end

-- Hook taking money to ensure recording even if dedupe or timing missed it
do
    local orig_TakeInboxMoney = TakeInboxMoney
    function TakeInboxMoney(index)
        recordInboxIndex(index, "mail-click")
        return orig_TakeInboxMoney(index)
    end
end

-- Hook other common mail API used by auto-mail addons
do
    local orig_AutoLootMailItem = AutoLootMailItem
    if orig_AutoLootMailItem then
        function AutoLootMailItem(index)
            recordInboxIndex(index, "auto-loot")
            return orig_AutoLootMailItem(index)
        end
    end
end

do
    local orig_TakeInboxItem = TakeInboxItem
    if orig_TakeInboxItem then
        function TakeInboxItem(index, attachment)
            recordInboxIndex(index, "take-item")
            return orig_TakeInboxItem(index, attachment)
        end
    end
end

do
    local orig_DeleteInboxItem = DeleteInboxItem
    if orig_DeleteInboxItem then
        function DeleteInboxItem(index)
            recordInboxIndex(index, "delete")
            return orig_DeleteInboxItem(index)
        end
    end
end
