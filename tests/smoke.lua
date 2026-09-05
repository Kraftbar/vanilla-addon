floor, max, min, mod = math.floor, math.max, math.min, math.fmod
string.gfind = string.gmatch
format, strlen, strsub, strlower, strupper, strfind = string.format, string.len, string.sub, string.lower, string.upper, string.find
gsub, tostring, tonumber, type, pairs, pcall = string.gsub, tostring, tonumber, type, pairs, pcall
tinsert = table.insert
getn = function(value) return #value end
date, time = os.date, os.time
SlashCmdList, UISpecialFrames, StaticPopupDialogs = {}, {}, {}
CANCEL = "Cancel"

local frames = {}
local function object(name)
    local value = { _name = name, _shown = true, _text = "", _scripts = {}, _events = {}, _checked = false, _value = 0 }
    setmetatable(value, { __index = function(self, key)
        if key == "nextCheck" or key == "pendingAt" or key == "settingQuery" then return nil end
        if key == "SetVerticalScroll" then return nil end
        if key == "SetScript" then return function(_, script, callback) self._scripts[script] = callback end end
        if key == "GetScript" then return function(_, script) return self._scripts[script] end end
        if key == "RegisterEvent" then return function(_, eventName) self._events[eventName] = true end end
        if key == "CreateTexture" or key == "CreateFontString" then return function() return object() end end
        if key == "GetName" then return function() return self._name end end
        if key == "SetText" then return function(_, text) self._text = text or "" end end
        if key == "GetText" then return function() return self._text end end
        if key == "SetChecked" then return function(_, checked) self._checked = checked end end
        if key == "GetChecked" then return function() return self._checked end end
        if key == "SetValue" then return function(_, number) self._value = number end end
        if key == "GetValue" then return function() return self._value end end
        if key == "Show" then return function() self._shown = true end end
        if key == "Hide" then return function() self._shown = false end end
        if key == "IsShown" then return function() return self._shown end end
        if key == "GetCenter" then return function() return 500, 400 end end
        if key == "GetPoint" then return function() return "CENTER", UIParent, "CENTER", 0, 0 end end
        return function() end
    end })
    return value
end

UIParent, Minimap = object("UIParent"), object("Minimap")
DEFAULT_CHAT_FRAME, UIErrorsFrame, GameTooltip = object("ChatFrame1"), object("UIErrorsFrame"), object("GameTooltip")
GameFontNormal, GameFontHighlightSmall, GameFontNormalSmall, GameFontNormalLarge = {}, {}, {}, {}
function CreateFrame(_, name, parent, template)
    if template == "UIPanelScrollBarTemplate" and parent then parent:SetVerticalScroll(0) end
    local frame = object(name)
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end
function getglobal(name) return _G[name] end
function GetTime() return os.clock() + 100 end
local targetName, targetHealth, targetLevel, targetExists = "Target", 500, 10, true
function UnitName(unit) if unit == "player" then return "Tester" end return targetName end
function UnitClass() return "Warrior", "WARRIOR" end
function UnitHealth(unit) if unit == "target" then return targetHealth end return 500 end
function UnitLevel(unit) if unit == "target" then return targetLevel end return 60 end
function UnitHealthMax() return 1000 end
function UnitExists(unit) return unit ~= "target" or targetExists end
function UnitAffectingCombat() return true end
function UnitFactionGroup() return "Alliance" end
function GetCVar() return "TestRealm" end
function GetBuildInfo() return "1.12.1" end
function UnitBuff() return nil end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function CastSpellByName() end
function SendChatMessage() end
function CheckInbox() end
function GetInboxNumItems() return 0 end
function GetInboxHeaderInfo() return nil end
function GetInboxItem() return nil end
function TakeInboxMoney() end
function AutoLootMailItem() end
function TakeInboxItem() end
function DeleteInboxItem() end
function StartAuction() end
function PlaceAuctionBid() end
function GetAuctionSellItemInfo() return nil end
function GetAuctionItemInfo() return nil end
function CalculateAuctionDeposit() return 0 end
local errorHandler = function(message) error(message) end
function geterrorhandler() return errorHandler end
function seterrorhandler(handler) errorHandler = handler end

ERR_AUCTION_SOLD_S = "A buyer has been found for your auction of %s."
ERR_AUCTION_EXPIRED_S = "Your auction of %s has expired."
ERR_AUCTION_WON_S = "You won an auction for %s."
AUCTION_SOLD_MAIL_SUBJECT = "Auction successful: %s"
AUCTION_EXPIRED_MAIL_SUBJECT = "Auction expired: %s"
AUCTION_WON_MAIL_SUBJECT = "Auction won: %s"
ERR_AUCTION_STARTED, ERR_AUCTION_BID_PLACED = "Auction created.", "Bid accepted."
ERR_NOT_ENOUGH_MONEY, ERR_ITEM_NOT_FOUND, ERR_AUCTION_BID_OWN, ERR_AUCTION_HIGHER_BID = "money", "item", "own", "higher"

local files = {
    "vanilla_core.lua", "combat_core.lua", "combat_ui.lua", "combat_warnings.lua", "player_features.lua",
    "ledger_core.lua", "ledger_economics.lua", "ledger_mail.lua", "ledger_ui.lua", "aux_core.lua", "aux_ui.lua",
}
for _, filename in ipairs(files) do assert(loadfile(filename))() end

local compactArray = { "old", "keep" }
compactArray[2] = nil
VanillaAddon:ArrayPush(compactArray, "new")
assert(compactArray[1] == "old" and compactArray[2] == "new", "array append left a gap")
assert(VanillaAddon:ArrayRemove(compactArray, 1) == "old" and compactArray[1] == "new", "array removal did not compact")

local function fire(eventName, message)
    event, arg1 = eventName, message
    for _, frame in ipairs(frames) do
        if frame._events[eventName] and frame._scripts.OnEvent then this = frame; frame._scripts.OnEvent() end
    end
end

fire("VARIABLES_LOADED")
fire("PLAYER_LOGIN")
assert(CombatHistoryMinimapButton, "combat history minimap button was not created")
CombatHistoryMinimapButton._scripts.OnClick()
assert(CombatHistoryFrame and CombatHistoryFrame:IsShown(), "combat history minimap button did not open history")
assert(VanillaAddon.CombatUI.historyRows[1].cells.when,
    "combat history did not create aligned table cells")
CombatHistoryMinimapButton._scripts.OnClick()
assert(not CombatHistoryFrame:IsShown(), "combat history minimap button did not close history")
targetName, targetLevel = "Wolf", 10
fire("PLAYER_REGEN_DISABLED")
fire("CHAT_MSG_COMBAT_SELF_HITS", "You hit Wolf for 40.")
targetName, targetHealth, targetLevel = "Second Target", 1000, 12
fire("PLAYER_TARGET_CHANGED")
assert(VanillaAddon.Combat.current.target == "Second Target", "target switch was not tracked")
assert(VanillaAddon.Combat.current.targetLevel == 12, "target level was not tracked")
assert(VanillaAddon.Combat.current.timeToTargetDeath > 0, "target switch left a zero death estimate")
targetExists = false
fire("PLAYER_TARGET_CHANGED")
assert(VanillaAddon.Combat.current.target == "Second Target", "losing the target erased its name")
assert(VanillaAddon.Combat.current.targetLevel == 12, "losing the target erased its level")
assert(VanillaAddon.Combat.current.timeToTargetDeath == 0, "losing the target kept a stale death estimate")
fire("CHAT_MSG_SPELL_PERIODIC_CREATURE_DAMAGE", "Wolf suffers 12 Fire damage from your Fireball.")
fire("CHAT_MSG_COMBAT_CREATURE_VS_SELF_HITS", "Wolf hits you for 20.")
fire("CHAT_MSG_SPELL_PERIODIC_SELF_DAMAGE", "You suffer 5 damage from Scorpid's Poison.")
fire("PLAYER_REGEN_ENABLED")
assert(#VanillaAddonDB.combatHistory == 1, "combat history was not recorded")
assert(VanillaLedgerDB.addon == VanillaAddonDB, "shared database is not nested in the persisted ledger database")
assert(VanillaAddonDB.combatHistory[1].damageDealt == 52, "outgoing damage mismatch")
assert(VanillaAddonDB.combatHistory[1].damageTaken == 25, "incoming damage mismatch")
assert(VanillaAddonDB.combatHistory[1].target == "Second Target", "history lost the last valid target")
assert(VanillaAddonDB.combatHistory[1].targetLevel == 12, "history lost the target level")
local combatTargets = VanillaAddonDB.combatHistory[1].targets
assert(#combatTargets == 3, "history did not retain every opponent")
assert(combatTargets[1].name == "Wolf" and combatTargets[1].level == 10,
    "history lost the first target and its level")
assert(combatTargets[2].name == "Second Target" and combatTargets[2].level == 12,
    "history lost the switched target and its level")
assert(combatTargets[3].name == "Scorpid" and combatTargets[3].level == nil,
    "history did not infer an untargeted attacker")

local inboxRows = {}
function GetInboxNumItems() return #inboxRows end
function GetInboxHeaderInfo(index)
    local row = inboxRows[index]
    return nil, "Interface/MailFrame/AuctionStationery", "Alliance Auction House", row.subject, row.money, 0, 30, row.hasItem, row.read
end
inboxRows = { { subject = "Auction successful: Linen Cloth", money = 950, hasItem = false, read = false } }
fire("MAIL_INBOX_UPDATE")
assert(#VanillaLedgerDB.sold == 1, "first auction mail was not recorded")
fire("MAIL_INBOX_UPDATE")
assert(#VanillaLedgerDB.sold == 1, "auction mail dedupe failed")
inboxRows = {}
fire("MAIL_INBOX_UPDATE")
inboxRows = { { subject = "Auction successful: Linen Cloth", money = 950, hasItem = false, read = false } }
fire("MAIL_INBOX_UPDATE")
assert(#VanillaLedgerDB.sold == 2, "later identical auction mail was discarded")

aux = {
    account = { item_ids = { ["Zeta Blade"] = 3, ["Alpha Blade"] = 1, ["Beta Blade"] = 2 } },
    faction = { ["TestRealm|Alliance"] = { post = { ["1:0"] = "12#100#200", ["2:0"] = "12#300#400" }, history = {} } },
}
local auxRows, auxTotal = VanillaAddon.AuxSearch:Run("blade")
assert(auxTotal == 3 and auxRows[1].name == "Alpha Blade", "Aux alphabetical search failed")
VanillaAddon.settings.aux.cachedOnly = true
auxRows, auxTotal = VanillaAddon.AuxSearch:Run("blade")
assert(auxTotal == 2, "Aux cached-only filter failed")

function GetAuctionItemInfo() return "Copper Bar", nil, 2, nil, nil, nil, nil, nil, 1000 end
PlaceAuctionBid("list", 1, 1000)
fire("CHAT_MSG_SYSTEM", ERR_AUCTION_BID_PLACED)
fire("CHAT_MSG_SYSTEM", "You won an auction for Copper Bar.")
local bought = VanillaLedgerDB.bought[#VanillaLedgerDB.bought]
assert(bought and bought.purchaseCost == 1000 and bought.qty == 2, "purchase economics were not attached")

function GetAuctionSellItemInfo() return "Copper Bar", nil, 1 end
function CalculateAuctionDeposit() return 50 end
StartAuction(700, 900, 12)
fire("CHAT_MSG_SYSTEM", ERR_AUCTION_STARTED)
fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Copper Bar.")
inboxRows = { { subject = "Auction successful: Copper Bar", money = 855, hasItem = false, read = false } }
fire("MAIL_INBOX_UPDATE")
local sold = VanillaLedgerDB.sold[#VanillaLedgerDB.sold]
assert(sold.item == "Copper Bar" and sold.money == 855, "sale mail did not merge into chat sale")
assert(sold.costBasis == 500 and sold.estimatedCut == 45, "sale economics were not calculated")

function GetAuctionSellItemInfo() return "Rough Stone", nil, 3 end
function CalculateAuctionDeposit() return 60 end
StartAuction(100, 200, 12)
fire("CHAT_MSG_SYSTEM", ERR_AUCTION_STARTED)
fire("CHAT_MSG_SYSTEM", "Your auction of Rough Stone has expired.")
local expired = VanillaLedgerDB.expired[#VanillaLedgerDB.expired]
assert(expired.depositLost == 60 and expired.qty == 3, "expired deposit economics were not calculated")
VanillaAddon.LedgerUI:Create()
assert(not VanillaAddon.LedgerUI.frame:IsShown(), "ledger frame should start hidden")
VanillaAddon.LedgerUI:Toggle()
assert(VanillaAddon.LedgerUI.frame:IsShown(), "first ledger toggle did not show the frame")
VanillaAddon.LedgerUI:Toggle()
assert(not VanillaAddon.LedgerUI.frame:IsShown(), "second ledger toggle did not hide the frame")
SlashCmdList["LEDGER"]("ui")
SlashCmdList["COMBATSTATS"]("history")
assert(strlen(VanillaAddon.CombatUI.historyRows[1].cells.when._text) == 19,
    "combat history timestamp lost precision")
assert(VanillaAddon.CombatUI.historyRows[1].cells.target._text == "Wolf +2",
    "combat history did not summarize multiple opponents")
assert(VanillaAddon.CombatUI.historyRows[1].cells.level._text == "10,...",
    "combat history did not summarize opponent levels")
for _, frame in ipairs(frames) do if frame._scripts.OnUpdate then this = frame; frame._scripts.OnUpdate() end end
assert(VanillaAddon:FormatCoins(-60) == "-0g 0s 60c", "negative coin formatting failed")
print("runtime smoke test: ok")
