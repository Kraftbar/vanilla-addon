-- Combat collection and encounter history. No UI dependencies.

local VA = VanillaAddon
local Combat = {}
VA.Combat = Combat
VA:RegisterModule("combat-core", Combat)

Combat.recentWindow = 5.0
Combat.recentTaken = {}
Combat.inCombat = false

CombatStats = CombatStats or {}
CombatStats.version = VA.version
CombatStats.config = VA.settings.warnings
CombatStats.debug = VA.settings.diagnostics.enabled
CombatStats.data = CombatStats.data or {}

local outgoingEvents = {
    CHAT_MSG_COMBAT_SELF_HITS = true,
    CHAT_MSG_COMBAT_SELF_CRITS = true,
    CHAT_MSG_SPELL_SELF_DAMAGE = true,
    CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE = true,
    CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE = true,
}

local incomingEvents = {
    CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS = true,
    CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE = true,
    CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE = true,
}

local function freshCurrent()
    return {
        startedAt = nil,
        startedClock = nil,
        damageDealt = 0,
        damageTaken = 0,
        attacksDealt = 0,
        hitsTaken = 0,
        timeToTargetDeath = 0,
        timeToPlayerDeath = 0,
        target = nil,
        targetLevel = nil,
        targets = {},
    }
end

Combat.current = freshCurrent()

function Combat:TrackOpponent(name, level)
    if not name or name == "" then return end
    local targets = self.current.targets
    for i = 1, VA:ArrayLen(targets) do
        local opponent = targets[i]
        if opponent.name == name then
            if level ~= nil then opponent.level = level end
            return
        end
    end
    VA:ArrayPush(targets, { name = name, level = level })
end

function Combat:CaptureTarget()
    if not UnitExists("target") then return false end
    if UnitCanAttack and not UnitCanAttack("player", "target") then return false end
    local target = UnitName("target")
    if not target or target == "" then return false end
    local level = UnitLevel("target")
    self.current.target = target
    self.current.targetLevel = level
    self:TrackOpponent(target, level)
    return true
end

local function syncCompatibility()
    local current = Combat.current
    CombatStats.config = VA.settings.warnings
    CombatStats.debug = VA.settings.diagnostics.enabled
    CombatStats.data.damageDealt = current.damageDealt
    CombatStats.data.damageTaken = current.damageTaken
    CombatStats.data.attacksDealt = current.attacksDealt
    CombatStats.data.combatStart = current.startedClock
    CombatStats.data.timeToTargetDeath = current.timeToTargetDeath
    CombatStats.data.timeToPlayerDeath = current.timeToPlayerDeath
end

function Combat:Start()
    if self.inCombat then return end
    self.inCombat = true
    self.current = freshCurrent()
    self.current.startedAt = time()
    self.current.startedClock = GetTime()
    self:CaptureTarget()
    self.recentTaken = {}
    syncCompatibility()
    VA:Emit("COMBAT_STARTED", self.current)
    VA:Diag("combat", "Started against " .. tostring(self.current.target or "no target"))
end

function Combat:GetElapsed()
    if not self.current.startedClock then return 0 end
    return max(0, GetTime() - self.current.startedClock)
end

function Combat:GetSnapshot()
    local elapsed = self:GetElapsed()
    local dealt = self.current.damageDealt or 0
    local taken = self.current.damageTaken or 0
    local targets = {}
    for i = 1, VA:ArrayLen(self.current.targets) do
        local opponent = self.current.targets[i]
        targets[i] = { name = opponent.name, level = opponent.level }
    end
    return {
        elapsed = elapsed,
        damageDealt = dealt,
        damageTaken = taken,
        dps = elapsed > 0 and dealt / elapsed or 0,
        dtps = elapsed > 0 and taken / elapsed or 0,
        attacksDealt = self.current.attacksDealt or 0,
        hitsTaken = self.current.hitsTaken or 0,
        target = self.current.target,
        targetLevel = self.current.targetLevel,
        targets = targets,
        timeToTargetDeath = self.current.timeToTargetDeath or 0,
        timeToPlayerDeath = self.current.timeToPlayerDeath or 0,
    }
end

function Combat:UpdateTargetEstimate()
    if not UnitExists("target") then
        self.current.timeToTargetDeath = 0
        return
    end
    self:CaptureTarget()
    local elapsed = self:GetElapsed()
    local dps = elapsed > 0 and (self.current.damageDealt or 0) / elapsed or 0
    local health = UnitHealth("target") or 0
    self.current.timeToTargetDeath = health > 0 and dps > 0 and health / dps or 0
end

function Combat:End()
    if not self.inCombat then return end
    local snapshot = self:GetSnapshot()
    self.inCombat = false
    snapshot.startedAt = self.current.startedAt or time()
    snapshot.endedAt = time()
    if snapshot.elapsed >= 1 or snapshot.damageDealt > 0 or snapshot.damageTaken > 0 then
        local history = VA.db.combatHistory
        VA:ArrayPush(history, snapshot)
        local limit = tonumber(VA.settings.combat.historyLimit or 20) or 20
        while VA:ArrayLen(history) > limit do VA:ArrayRemove(history, 1) end
    end
    VA:Emit("COMBAT_ENDED", snapshot)
    VA:Diag("combat", format("Ended: %.1fs, %.1f DPS, %.1f DTPS", snapshot.elapsed, snapshot.dps, snapshot.dtps))
    self.current = freshCurrent()
    self.recentTaken = {}
    syncCompatibility()
end

local function parsePeriodicIncoming(message)
    local _, _, amount, source = strfind(message, "^[Yy]ou suffer%s+(%d+).- from (.+)")
    if not amount then return nil, nil end
    source = gsub(source or "unknown", "%.$", "")
    return tonumber(amount), source
end

local function parseIncoming(message, eventName)
    if eventName == "CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE" then
        local amount, source = parsePeriodicIncoming(message)
        local _, _, opponent = strfind(source or "", "^(.+)'s .+$")
        return amount, source, opponent
    end
    local source, amount
    _, _, source, amount = strfind(message, "^(.+)'s .- hits [Yy]ou for (%d+)")
    if not source then _, _, source, amount = strfind(message, "^(.+)'s .- crits [Yy]ou for (%d+)") end
    if not source then _, _, source, amount = strfind(message, "^(.+) hits [Yy]ou for (%d+)") end
    if not source then _, _, source, amount = strfind(message, "^(.+) crits [Yy]ou for (%d+)") end
    if not amount then _, _, amount = strfind(message, "(%d+)") end
    return tonumber(amount), source, source
end

local function parseOutgoing(message, eventName)
    local amount, target
    if eventName == "CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE" or eventName == "CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE" then
        _, _, target, amount = strfind(message, "^(.-) suffers%s+(%d+)")
    elseif eventName == "CHAT_MSG_COMBAT_SELF_HITS" then
        _, _, target, amount = strfind(message, "^[Yy]ou hit (.+) for (%d+)")
    elseif eventName == "CHAT_MSG_COMBAT_SELF_CRITS" then
        _, _, target, amount = strfind(message, "^[Yy]ou crit (.+) for (%d+)")
    elseif eventName == "CHAT_MSG_SPELL_SELF_DAMAGE" then
        _, _, target, amount = strfind(message, "^Your .- hits (.+) for (%d+)")
        if not target then _, _, target, amount = strfind(message, "^Your .- crits (.+) for (%d+)") end
    else
        _, _, amount = strfind(message, "(%d+)")
    end
    if not amount then _, _, amount = strfind(message, "(%d+)") end
    return tonumber(amount), target
end

function Combat:PruneRecent(now)
    local write = 1
    for read = 1, VA:ArrayLen(self.recentTaken) do
        local row = self.recentTaken[read]
        if row and now - row.clock <= self.recentWindow then
            self.recentTaken[write] = row
            write = write + 1
        end
    end
    for i = write, VA:ArrayLen(self.recentTaken) do self.recentTaken[i] = nil end
end

function Combat:GetRecent()
    self:PruneRecent(GetTime())
    local total = 0
    local attackers = {}
    for i = 1, VA:ArrayLen(self.recentTaken) do
        local row = self.recentTaken[i]
        if row then
            total = total + (row.amount or 0)
            if row.source then attackers[row.source] = true end
        end
    end
    local count = 0
    for _ in pairs(attackers) do count = count + 1 end
    return total / self.recentWindow, count, attackers
end

function Combat:UpdatePlayerEstimate()
    local dtps, attackers = self:GetRecent()
    local health = UnitHealth("player") or 0
    self.current.timeToPlayerDeath = health > 0 and dtps > 0 and health / dtps or 0
    return dtps, attackers, health
end

function Combat:HandleDamage(eventName, message)
    if not self.inCombat then self:Start() end
    local amount, source, opponent
    if outgoingEvents[eventName] then
        amount, opponent = parseOutgoing(message, eventName)
        if amount then
            self.current.damageDealt = self.current.damageDealt + amount
            self.current.attacksDealt = self.current.attacksDealt + 1
        end
    elseif incomingEvents[eventName] then
        amount, source, opponent = parseIncoming(message, eventName)
        if amount then
            self.current.damageTaken = self.current.damageTaken + amount
            self.current.hitsTaken = self.current.hitsTaken + 1
            VA:ArrayPush(self.recentTaken, { clock = GetTime(), amount = amount, source = source })
        end
    end
    if not amount then
        VA:Diag("combat-unparsed", eventName .. " | " .. tostring(message))
        return
    end
    self:TrackOpponent(opponent)
    self:UpdateTargetEstimate()
    local recentDtps, recentAttackers, playerHealth = self:UpdatePlayerEstimate()
    syncCompatibility()
    VA:Diag("combat-event", format("%s amount=%d source=%s target=%s targetHP=%d targetTTD=%.2f playerHP=%d recentDTPS=%.2f attackers=%d playerTTD=%.2f",
        eventName, amount, tostring(source or "-"), tostring(self.current.target or "-"),
        UnitExists("target") and (UnitHealth("target") or 0) or 0,
        self.current.timeToTargetDeath or 0, playerHealth, recentDtps, recentAttackers,
        self.current.timeToPlayerDeath or 0))
    VA:Emit("COMBAT_UPDATED", { event = eventName, amount = amount, source = source, snapshot = self:GetSnapshot() })
end

function CombatWarn_GetRecent()
    return Combat:GetRecent()
end

local combatFrame = CreateFrame("Frame")
for eventName in pairs(outgoingEvents) do combatFrame:RegisterEvent(eventName) end
for eventName in pairs(incomingEvents) do combatFrame:RegisterEvent(eventName) end
combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
combatFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
combatFrame:SetScript("OnEvent", function()
    if event == "PLAYER_REGEN_DISABLED" then
        Combat:Start()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Combat:End()
    elseif event == "PLAYER_TARGET_CHANGED" then
        if Combat.inCombat then
            Combat:UpdateTargetEstimate()
            syncCompatibility()
            VA:Diag("combat-target", format("target=%s hp=%d targetTTD=%.2f dealt=%d elapsed=%.2f",
                tostring(Combat.current.target or "-"), UnitExists("target") and (UnitHealth("target") or 0) or 0,
                Combat.current.timeToTargetDeath or 0, Combat.current.damageDealt or 0, Combat:GetElapsed()))
            VA:Emit("COMBAT_ESTIMATE_UPDATED", { snapshot = Combat:GetSnapshot() })
        end
    else
        Combat:HandleDamage(event, arg1 or "")
    end
end)

function CombatStats:ToggleDebug(state)
    state = strlower(state or "")
    if state == "on" then VA.settings.diagnostics.enabled = true
    elseif state == "off" then VA.settings.diagnostics.enabled = false
    else VA.settings.diagnostics.enabled = not VA.settings.diagnostics.enabled end
    CombatStats.debug = VA.settings.diagnostics.enabled
    VA:Print("Combat diagnostics " .. (CombatStats.debug and "enabled" or "disabled"))
end

SLASH_COMBATSTATS1 = "/combatstats"
SlashCmdList["COMBATSTATS"] = function(message)
    local _, _, command, argument = strfind(message or "", "^(%S+)%s*(.*)$")
    command = strlower(command or "status")
    argument = strlower(argument or "")
    if command == "debug" then
        CombatStats:ToggleDebug(argument)
    elseif command == "clear" then
        VA.db.combatHistory = {}
        VA:Print("Combat history cleared")
    elseif command == "history" and VA.CombatUI and VA.CombatUI.ShowHistory then
        VA.CombatUI:ShowHistory()
    elseif command == "show" and VA.CombatUI then
        VA.CombatUI:SetVisible(true)
    elseif command == "hide" and VA.CombatUI then
        VA.CombatUI:SetVisible(false)
    else
        local snapshot = Combat:GetSnapshot()
        VA:Print(format("Combat %.1fs: %.1f DPS, %.1f DTPS. Commands: show|hide|history|clear|debug", snapshot.elapsed, snapshot.dps, snapshot.dtps))
    end
end
