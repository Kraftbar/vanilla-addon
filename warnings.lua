-- Low HP + Time-To-Die warning module (Vanilla 1.12 / Lua 5.0)
-- Adds a red popup via UIErrorsFrame when HP is low and estimated TTD is short.

-- Safe defaults and integration with existing CombatStats table if present
local function ensure_warn_config()
  CombatStats = CombatStats or { config = {} , data = {} }
  CombatStats.config = CombatStats.config or {}
  CombatStats.data = CombatStats.data or {}
  if CombatStats.config.warnEnabled == nil then CombatStats.config.warnEnabled = true end
  if CombatStats.config.warnHPPct == nil then CombatStats.config.warnHPPct = 0.35 end   -- 35%
  if CombatStats.config.warnTTD == nil then CombatStats.config.warnTTD = 5.0 end        -- seconds
  if CombatStats.config.warnCooldown == nil then CombatStats.config.warnCooldown = 8.0 end
end

ensure_warn_config()

local lastWarnAt = 0
local recentWindow = 5.0 -- seconds to look back for DTPS
local recentEvents = {}   -- array of {t, amount, src}

local function pruneRecent(now)
  local i = 1
  while i <= (getn and getn(recentEvents) or 0) do
    local e = recentEvents[i]
    if not e or (now - (e.t or 0)) > recentWindow then
      table.remove(recentEvents, i)
    else
      i = i + 1
    end
  end
end

local function addRecent(amount, src)
  local now = GetTime()
  table.insert(recentEvents, { t = now, amount = tonumber(amount) or 0, src = src })
  pruneRecent(now)
end

-- Expose a helper so other modules (window.lua) can use recent-window DTPS
function CombatWarn_GetRecent()
  local now = GetTime()
  pruneRecent(now)
  local sum = 0
  local attackers = {}
  local n = (getn and getn(recentEvents) or 0)
  for i = 1, n do
    local e = recentEvents[i]
    sum = sum + (e.amount or 0)
    if e.src then attackers[e.src] = true end
  end
  local count = 0; for _ in pairs(attackers) do count = count + 1 end
  return (sum / recentWindow), count, recentWindow
end

local function ShowLowTTDWarning(ttd, hpPct)
  local pct = math.floor(((hpPct or 0) * 100) + 0.5)
  local msg = string.format("LOW HP! TTD: %.1fs (HP: %d%%)", ttd or 0, pct)
  UIErrorsFrame:AddMessage(msg, 1.0, 0.1, 0.1, 1.0, 5)
  -- Also reflect this in the existing SecondsUntilDeath window, if present
  local scroll = getglobal and getglobal("SecondsUntilDeathWindowScroll") or SecondsUntilDeathWindowScroll
  if scroll and scroll.AddMessage then
    scroll:AddMessage("|cffff0000[LOW TTD]|r " .. msg)
    if scroll.ScrollToBottom then scroll:ScrollToBottom() end
  end
end

local function EstimateTTD()
  -- Prefer CombatStats data if available
  local cs = CombatStats
  local maxHp = UnitHealthMax("player") or 0
  local hp = UnitHealth("player") or 0
  if maxHp <= 0 then return 0, 0, 0 end
  local hpPct = hp / maxHp

  -- Recent-window DTPS that reacts quickly to multiple mobs
  local now = GetTime()
  pruneRecent(now)
  local sum = 0
  local attackers = {}
  local n = (getn and getn(recentEvents) or 0)
  for i = 1, n do
    local e = recentEvents[i]
    sum = sum + (e.amount or 0)
    if e.src then attackers[e.src] = true end
  end
  local dtpsRecent = sum / recentWindow

  -- Fallback to long-average if recent window empty (e.g., lull in hits)
  local dtps = dtpsRecent
  if dtps <= 0 and cs and cs.data and cs.data.damageTaken and cs.data.combatStart then
    local elapsed = GetTime() - (cs.data.combatStart or GetTime())
    if elapsed > 0 then dtps = (cs.data.damageTaken or 0) / elapsed end
  end

  local ttd = 0
  if dtps and dtps > 0 then ttd = hp / dtps end
  return ttd, hpPct, dtps, attackers
end

local function MaybeWarnLowTTD()
  if not CombatStats or not CombatStats.config or not CombatStats.config.warnEnabled then return end
  if not (UnitAffectingCombat("player") or UnitAffectingCombat("target")) then return end
  local now = GetTime()
  if (now - (lastWarnAt or 0)) < (CombatStats.config.warnCooldown or 8.0) then return end

  local ttd, hpPct, _, attackers = EstimateTTD()
  if hpPct < (CombatStats.config.warnHPPct or 0.35) and ttd > 0 and ttd <= (CombatStats.config.warnTTD or 5.0) then
    lastWarnAt = now
    ShowLowTTDWarning(ttd, hpPct)
    if CombatStats and CombatStats.debug then
      local count = 0; for _ in attackers do count = count + 1 end
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatStats DEBUG]|r Warn fired: ttd=" .. string.format("%.2f", ttd) .. ", hp%=" .. string.format("%.1f", hpPct * 100) .. ", attackers=" .. tostring(count))
    end
  end
end

-- Driver: lightweight frame with OnUpdate + init on login
local warnFrame = CreateFrame("Frame")
warnFrame:RegisterEvent("PLAYER_LOGIN")
warnFrame:RegisterEvent("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS")
warnFrame:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
warnFrame:SetScript("OnEvent", function()
  ensure_warn_config()
  if event == "PLAYER_LOGIN" then
    -- Kick a first check after login
    MaybeWarnLowTTD()
  else
    local msg = arg1
    if type(msg) == "string" then
      -- Parse damage events to build short-window DTPS and attacker set
      -- Examples: "Wolf hits You for 12." / "Murloc Raider crits You for 35."
      -- Spells: "Defias Wizard's Fireball hits You for 37 Fire damage."
      local src, dmg
      -- Spell with possessive
      _, _, src, dmg = string.find(msg, "^(.+)'s .- hits You for (%d+)")
      if not src then _, _, src, dmg = string.find(msg, "^(.+)'s .- crits You for (%d+)") end
      -- Melee without possessive
      if not src then _, _, src, dmg = string.find(msg, "^(.+) hits You for (%d+)") end
      if not src then _, _, src, dmg = string.find(msg, "^(.+) crits You for (%d+)") end
      -- Fallback: just number
      if not dmg then _, _, dmg = string.find(msg, "(%d+)") end
      if dmg then addRecent(tonumber(dmg) or 0, src) end
    end
  end
end)

warnFrame:SetScript("OnUpdate", function()
  if (this.tick or 1) > GetTime() then return end
  this.tick = GetTime() + 0.5 -- check twice a second
  MaybeWarnLowTTD()
end)

-- Slash commands for configuration
SLASH_COMBATWARN1 = "/combatwarn"
SlashCmdList["COMBATWARN"] = function(msg)
  ensure_warn_config()
  msg = msg or ""
  local _, _, cmd, arg = string.find(msg, "^(%S+)%s*(.*)$")
  cmd = strlower(cmd or "")
  arg = strlower(arg or "")

  if cmd == "on" then
    CombatStats.config.warnEnabled = true
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r Enabled")
  elseif cmd == "off" then
    CombatStats.config.warnEnabled = false
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r Disabled")
  elseif cmd == "ttd" then
    local v = tonumber(arg)
    if v and v > 0 then
      CombatStats.config.warnTTD = v
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r TTD threshold set to " .. string.format("%.1f", v) .. "s")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r Usage: /combatwarn ttd <seconds>")
    end
  elseif cmd == "hpp" then
    local v = tonumber(arg)
    if v and v > 0 and v <= 100 then
      CombatStats.config.warnHPPct = v / 100
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r HP%% threshold set to " .. tostring(v) .. "%")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r Usage: /combatwarn hpp <percent>")
    end
  elseif cmd == "cooldown" then
    local v = tonumber(arg)
    if v and v >= 0 then
      CombatStats.config.warnCooldown = v
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r Cooldown set to " .. string.format("%.1f", v) .. "s")
    else
      DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r Usage: /combatwarn cooldown <seconds>")
    end
  else
    DEFAULT_CHAT_FRAME:AddMessage("|cffffff00[CombatWarn]|r Commands: on | off | ttd <sec> | hpp <percent> | cooldown <sec>")
  end
end
