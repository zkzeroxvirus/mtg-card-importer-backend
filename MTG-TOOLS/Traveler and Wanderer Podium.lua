-- Wanderer / Traveler trigger helper
-- Detect tagged objects, show a temporary button, and apply XP effects through MTGSpawner APIs.

SPAWNER_TAG = "MTGSpawner"
MASTER_TAG = "MTGMasterController"

DETECTION_TAGS = {
Wanderer = true,
Traveler = true,
}

PLAYER_COLORS = {
"White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink",
}

TEMP_BUTTON_LIFETIME = 35
BARD_COOLDOWN_SECONDS = 300
TRAVELER_RESET_COOLDOWN_SECONDS = 10

activeWandererGuid = nil
activeWandererName = nil
activeConfig = nil
pressedPlayers = {}
bardLastUsedAt = 0
lastTravelerResetAt = 0
spawnerScriptCache = {}
collidingTaggedGuids = {}
giantIceToadXPInput = {}
voteEligibleColors = {}
voteSelections = {}
activeSillyJesterGuids = {}

local function nowSeconds()
return os.time() or 0
end

local function safeLower(v)
if type(v) ~= "string" then return "" end
return string.lower(v)
end

local function trimName(name)
if type(name) ~= "string" or name == "" then return "Unknown Wanderer" end
return name
end

local function isSillyJesterName(name)
local lowered = safeLower(name)
return string.find(lowered, "silly, the jester", 1, true)
or string.find(lowered, "silly the jester", 1, true)
end

local function getDetectionDisplayName(obj)
if not obj then return "Unknown Wanderer" end

local nickname = ""
local name = ""
pcall(function() nickname = obj.getNickname() or "" end)
pcall(function() name = obj.getName() or "" end)

if nickname ~= "" then return nickname end
if name ~= "" then return name end
return "Unknown Wanderer"
end

local function getObjectDescription(obj)
if not obj then return "" end
local desc = ""
pcall(function() desc = obj.getDescription() or "" end)
return desc
end

local function parseFixedXPCost(description)
if type(description) ~= "string" or description == "" then return nil end
local lowered = safeLower(description)

-- Skip variable pricing like "pay any amount of experience".
if string.find(lowered, "any amount of experience", 1, true) then return nil end

local amount = string.match(lowered, "pay%s+(%d+)%s*xp")
if amount then
return -tonumber(amount)
end

return nil
end

local function escapeLuaPattern(str)
return (str:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

local function getSpawnerScript(obj)
if not obj then return "" end
local guid = ""
pcall(function() guid = obj.getGUID() or "" end)
if guid ~= "" and spawnerScriptCache[guid] ~= nil then
return spawnerScriptCache[guid]
end

local script = ""
pcall(function() script = obj.getLuaScript() or "" end)
if guid ~= "" then
spawnerScriptCache[guid] = script
end
return script
end

local function spawnerHasFunction(obj, functionName)
local script = getSpawnerScript(obj)
if script == "" then return false end

local fn = escapeLuaPattern(functionName)
if string.find(script, "function%s+" .. fn .. "%s*%(") then return true end
if string.find(script, fn .. "%s*=%s*function%s*%(") then return true end
return false
end

local function isXPSpawner(obj)
if not obj or obj == self then return false end
return spawnerHasFunction(obj, "receiveXP") or spawnerHasFunction(obj, "receiveEssence")
end

local function hasDetectionTag(obj)
if not obj then return false end
for tagName, _ in pairs(DETECTION_TAGS) do
local ok, tagged = pcall(function() return obj.hasTag(tagName) end)
if ok and tagged then return true end
end
local displayName = safeLower(getDetectionDisplayName(obj))
if string.find(displayName, "bearded grunt", 1, true) then return true end
if isSillyJesterName(displayName) then return true end
return false
end

local function hasActiveSillyJester()
for _, _ in pairs(activeSillyJesterGuids) do
return true
end
return false
end

local function getMasterController()
local tagged = getObjectsWithTag(MASTER_TAG)
if type(tagged) ~= "table" then return nil end
return tagged[1]
end

local function setSillyJesterDiscountEnabled(enabled)
local master = getMasterController()
if not master then return false end
return pcall(function()
master.call("setSillyJesterMerchantDiscountEnabled", { enabled = enabled == true })
end)
end

local function getEncounterMessage(obj, displayName, hasAction)
local loweredName = safeLower(displayName)
if string.find(loweredName, "bearded grunt", 1, true) then
return "The Bearded Grunt calls for a vote: " .. displayName
end

if string.find(loweredName, "trader", 1, true) then
return "A Trader arrives with wares: " .. displayName .. " - Vote on trades or selling!"
end

if isSillyJesterName(loweredName) then
return "Silly, the Jester sets up shop in town. Until it leaves, Merchant packs cost 50% less."
end

if string.find(loweredName, "hollyphant", 1, true) then
return "A majestic Hollyphant blesses the town! Each player gains an additional Cathedral use this turn."
end

local isWanderer = false
local isTraveler = false
pcall(function() isWanderer = obj.hasTag("Wanderer") end)
pcall(function() isTraveler = obj.hasTag("Traveler") end)

if isWanderer then
return "A Wanderer appears on the road: " .. displayName
end

if isTraveler then
return "A Traveler arrives in town: " .. displayName
end

if hasAction then
return "An encounter appears: " .. displayName
end
return displayName .. " moves on."
end

local function getWandererConfig(obj)
local displayName = getDetectionDisplayName(obj)
local n = safeLower(displayName)
local description = getObjectDescription(obj)
local parsedXPDelta = parseFixedXPCost(description)
local hasTravelerTag = false
pcall(function() hasTravelerTag = obj.hasTag("Traveler") end)

if string.find(n, "bearded grunt", 1, true) then
return {
label = "Bearded Grunt Vote",
mode = "vote",
resource = "xp",
delta = 0,
}
end

local cfg = nil
if parsedXPDelta ~= nil then
cfg = {
label = "Use (" .. tostring(parsedXPDelta) .. "XP)",
delta = parsedXPDelta,
mode = "single",
resource = "xp",
}
end

if not cfg then
cfg = {
label = "Hire (-5XP)",
delta = -5,
mode = "single",
resource = "xp",
}
end

if string.find(n, "cartographer", 1, true) then
cfg.label = "Hire (-10XP)"
cfg.delta = -10
elseif string.find(n, "giant ice toad", 1, true) then
cfg.label = "Transmute XP"
cfg.mode = "giant_ice_toad"
cfg.delta = 0
cfg.resource = "xp"
elseif string.find(n, "wayfarer", 1, true) then
cfg.label = "Destroy (+5XP)"
cfg.delta = 5
elseif string.find(n, "veiled trinket broker", 1, true) then
cfg.label = "Hire (-40XP)"
cfg.delta = -40
elseif string.find(n, "essence broker", 1, true) then
cfg.label = "Hire (+10 Essence)"
cfg.delta = 10
cfg.resource = "essence"
elseif string.find(n, "wandering bard", 1, true) then
cfg.label = "Dance (+5XP)"
cfg.mode = "bard"
cfg.delta = 5
elseif isSillyJesterName(n) then
return {
label = "Silly, the Jester",
mode = "silly_jester",
resource = "xp",
delta = 0,
}
elseif string.find(n, "hollyphant", 1, true) then
return {
label = "Hollyphant",
mode = "hollyphant",
resource = "xp",
delta = 0,
}
elseif string.find(n, "the trader", 1, true) then
return {
label = "The Trader Vote",
mode = "vote_trader",
resource = "xp",
delta = 0,
}
elseif string.find(n, "traveler", 1, true) and parsedXPDelta == nil then
return nil
elseif parsedXPDelta == nil then
-- For Traveler-tagged objects without a fixed XP cost, skip button generation.
if hasTravelerTag then return nil end
end

cfg.applyTownTravelerReduction = hasTravelerTag and cfg.mode == "single"
and cfg.resource == "xp" and type(cfg.delta) == "number" and cfg.delta < 0

return cfg
end

local function getSeatedColors()
local out = {}
for _, color in ipairs(PLAYER_COLORS) do
local p = Player[color]
if p and p.seated then
table.insert(out, color)
end
end
return out
end

local function getTaggedSpawners()
local tagged = getObjectsWithTag(SPAWNER_TAG)
if type(tagged) ~= "table" then return {} end

local out = {}
for _, obj in ipairs(tagged) do
if isXPSpawner(obj) then
table.insert(out, obj)
end
end
return out
end

local function notifySpawnersTravelerEffect(travelerName)
local spawners = getTaggedSpawners()
for _, spawner in ipairs(spawners) do
if spawnerHasFunction(spawner, "receiveTravelerEffect") then
pcall(function() spawner.call("receiveTravelerEffect", { name = travelerName }) end)
end
end
end

local function resetTownActionsViaMaster()
local now = nowSeconds()
if now - lastTravelerResetAt < TRAVELER_RESET_COOLDOWN_SECONDS then
return false
end
lastTravelerResetAt = now

local master = getMasterController()
if not master then return false end
if spawnerHasFunction(master, "resetTownActions") then
return pcall(function() master.call("resetTownActions") end)
end
if spawnerHasFunction(master, "click_resetTownActions") then
return pcall(function() master.call("click_resetTownActions") end)
end
return false
end

local function findSpawnerForColor(playerColor)
local desiredColor = safeLower(playerColor)
local desiredName = ""
local p = Player[playerColor]
if p and p.steam_name then desiredName = safeLower(p.steam_name) end

local tagged = getTaggedSpawners()
local fallback = nil

for _, spawner in ipairs(tagged) do
if spawner ~= self then
local methods = {"getPlayerColor", "getOwnerColor", "getSeatColor", "getColor"}
for _, methodName in ipairs(methods) do
if spawnerHasFunction(spawner, methodName) then
local ok, val = pcall(function() return spawner.call(methodName) end)
if ok and type(val) == "string" and safeLower(val) == desiredColor then
return spawner
end
end
end

if spawnerHasFunction(spawner, "getPlayerDisplayName") then
local okName, dispName = pcall(function() return spawner.call("getPlayerDisplayName") end)
if okName and type(dispName) == "string" and desiredName ~= "" and safeLower(dispName) == desiredName then
return spawner
end
end

local sName = ""
pcall(function() sName = spawner.getName() or "" end)
if sName ~= "" then
local lowered = safeLower(sName)
if string.find(lowered, desiredColor, 1, true) then
return spawner
end
if desiredName ~= "" and string.find(lowered, desiredName, 1, true) then
return spawner
end
end

if not fallback then fallback = spawner end
end
end

return fallback
end

local function applyResourceToSpawner(spawner, resourceType, delta)
if not spawner then return false, 0 end
local receiveMethod = (resourceType == "essence") and "receiveEssence" or "receiveXP"
local getterMethod = (resourceType == "essence") and "getEssence" or "getXP"
if not spawnerHasFunction(spawner, receiveMethod) then return false, 0 end

local before = nil
if spawnerHasFunction(spawner, getterMethod) then
local okBefore, beforeVal = pcall(function() return spawner.call(getterMethod) end)
if okBefore and type(beforeVal) == "number" then
before = beforeVal
end
end

local okCall = pcall(function()
spawner.call(receiveMethod, { amount = delta })
end)
if not okCall then
return false, 0
end

local applied = delta
if before ~= nil and spawnerHasFunction(spawner, getterMethod) then
local okAfter, afterVal = pcall(function() return spawner.call(getterMethod) end)
if okAfter and type(afterVal) == "number" then
applied = afterVal - before
end
end

return true, applied
end

local function getTravelerAdjustedDelta(spawner, delta)
if type(delta) ~= "number" or delta >= 0 then return delta end
if not spawnerHasFunction(spawner, "applyTownCostModifiers") then return delta end

local baseCost = math.max(0, math.floor(-delta))
if baseCost <= 0 then return delta end

local ok, adjustedCost = pcall(function()
return spawner.call("applyTownCostModifiers", baseCost)
end)
if not ok or type(adjustedCost) ~= "number" then return delta end

adjustedCost = math.max(0, math.floor(adjustedCost))
return -adjustedCost
end

local function formatXPDeltaLabel(label, delta)
local amount = math.floor(tonumber(delta) or 0)
local signed = (amount >= 0 and "+" or "") .. tostring(amount) .. "XP"
local replaced, count = tostring(label or "Use"):gsub("%([%+%-]?%d+XP%)", "(" .. signed .. ")", 1)
if count == 0 then
return tostring(label or "Use") .. " (" .. signed .. ")"
end
return replaced
end

local function getTravelerPreviewSpawner()
for _, color in ipairs(getSeatedColors()) do
local spawner = findSpawnerForColor(color)
if spawner then return spawner end
end
local tagged = getTaggedSpawners()
return tagged[1]
end

local function applyTravelerPreviewLabel(cfg)
if type(cfg) ~= "table" or not cfg.applyTownTravelerReduction then return end
if type(cfg.delta) ~= "number" or cfg.delta >= 0 then return end
local spawner = getTravelerPreviewSpawner()
if not spawner then return end
local previewDelta = getTravelerAdjustedDelta(spawner, cfg.delta)
cfg.label = formatXPDeltaLabel(cfg.label, previewDelta)
end

local function applyToSinglePlayer(playerColor, resourceType, delta, options)
local spawner = findSpawnerForColor(playerColor)
if not spawner then
printToColor("No player spawner found for " .. tostring(playerColor) .. ".", playerColor, {1, 0.3, 0.3})
return false
end

local requestedDelta = delta
if type(options) == "table" and options.applyTownTravelerReduction
and resourceType == "xp" and type(delta) == "number" and delta < 0 then
requestedDelta = getTravelerAdjustedDelta(spawner, delta)
local baseCost = -delta
local adjustedCost = -requestedDelta
if adjustedCost < baseCost then
printToColor("Town reduction applied: " .. tostring(baseCost) .. " -> " .. tostring(adjustedCost) .. " XP.", playerColor, {0.55, 1, 0.55})
end
end

local ok, applied = applyResourceToSpawner(spawner, resourceType, requestedDelta)
if not ok then
printToColor("Could not contact XP system for " .. tostring(playerColor) .. ".", playerColor, {1, 0.3, 0.3})
return false
end

local unit = (resourceType == "essence") and "Essence" or "XP"

if applied ~= requestedDelta then
if requestedDelta < 0 then
printToColor("Not enough " .. unit .. " for this Wanderer.", playerColor, {1, 0.3, 0.3})
else
printToColor("Wanderer applied partial " .. unit .. " change: " .. tostring(applied) .. ".", playerColor, {1, 0.8, 0.3})
end
else
local sign = (requestedDelta >= 0) and "+" or ""
printToColor("Wanderer effect applied: " .. sign .. tostring(requestedDelta) .. " " .. unit, playerColor, {0.55, 1, 0.55})
end

return true
end

local function applyBardToSeatedPlayers()
local seated = getSeatedColors()
if #seated == 0 then
broadcastToAll("[Wandering Bard] No seated players to grant XP.", {1, 0.8, 0.3})
return false
end

local successCount = 0
for _, color in ipairs(seated) do
local spawner = findSpawnerForColor(color)
if spawner then
local ok = applyResourceToSpawner(spawner, "xp", 5)
if ok then successCount = successCount + 1 end
end
end

if successCount > 0 then
broadcastToAll("[Wandering Bard] Granted +5 XP to " .. tostring(successCount) .. " seated player(s).", {0.55, 1, 0.55})
return true
end

broadcastToAll("[Wandering Bard] Failed to find player spawners.", {1, 0.3, 0.3})
return false
end

local function applyGiantIceToadForPlayer(playerColor)
local spawner = findSpawnerForColor(playerColor)
if not spawner then
printToColor("No player spawner found for " .. tostring(playerColor) .. ".", playerColor, {1, 0.3, 0.3})
return false
end

if not spawnerHasFunction(spawner, "getXP") then
printToColor("Could not read your XP for Giant Ice Toad.", playerColor, {1, 0.3, 0.3})
return false
end

local okXP, xpValue = pcall(function() return spawner.call("getXP") end)
local xp = (okXP and type(xpValue) == "number") and xpValue or 0
if xp <= 0 then
printToColor("You have no XP to transmute.", playerColor, {1, 0.8, 0.3})
return false
end

local requestedXP = giantIceToadXPInput[playerColor]
if type(requestedXP) ~= "number" or requestedXP <= 0 then
printToColor("Enter XP to transmute in the field first.", playerColor, {1, 0.8, 0.3})
return false
end

if requestedXP > xp then
printToColor("You only have " .. tostring(xp) .. " XP.", playerColor, {1, 0.8, 0.3})
return false
end

local okSpend, appliedXP = applyResourceToSpawner(spawner, "xp", -requestedXP)
if not okSpend then
printToColor("Giant Ice Toad could not spend your XP.", playerColor, {1, 0.3, 0.3})
return false
end

local spentXP = 0
if type(appliedXP) == "number" and appliedXP < 0 then
spentXP = -appliedXP
end
if spentXP <= 0 then
printToColor("No XP was spent.", playerColor, {1, 0.8, 0.3})
return false
end

local essenceGain = math.floor(spentXP * 3)
local okEssence = applyResourceToSpawner(spawner, "essence", essenceGain)
if not okEssence then
printToColor("XP was spent, but essence gain failed.", playerColor, {1, 0.3, 0.3})
return false
end

giantIceToadXPInput[playerColor] = nil

printToColor("Giant Ice Toad: -" .. tostring(spentXP) .. " XP, +" .. tostring(essenceGain) .. " Essence.", playerColor, {0.55, 1, 0.55})
return true
end

function setGiantIceToadXPInput(_, playerColor, inputValue, _)
local amount = tonumber(inputValue)
if type(amount) ~= "number" then
giantIceToadXPInput[playerColor] = nil
return
end

amount = math.floor(amount)
if amount <= 0 then
giantIceToadXPInput[playerColor] = nil
return
end

giantIceToadXPInput[playerColor] = amount
end

local function clearActionButton()
self.clearButtons()
self.clearInputs()
end

local function hasTaggedCollision()
for _, _ in pairs(collidingTaggedGuids) do
return true
end
return false
end

local function clearActiveDetectionState(clearButton)
activeWandererGuid = nil
activeWandererName = nil
activeConfig = nil
pressedPlayers = {}
voteEligibleColors = {}
voteSelections = {}
giantIceToadXPInput = {}
if clearButton then
clearActionButton()
end
end

local function createActionButton()
if not activeConfig then return end

self.clearButtons()
self.clearInputs()
if activeConfig.mode == "vote" then
	self.createButton({
		label = "Each player\n+15 XP",
		click_function = "pressVoteXP",
		function_owner = self,
		position = {0, 0.30, 0.5},
		rotation = {0, 0, 0},
		width = 550,
		height = 120,
		font_size = 42,
		color = {0.12, 0.28, 0.14},
		font_color = {1, 1, 1},
	})
	self.createButton({
		label = "Each player\n+1 building use",
		click_function = "pressVoteBuilding",
		function_owner = self,
		position = {0, 0.30, 0.8},
		rotation = {0, 0, 0},
		width = 550,
		height = 120,
		font_size = 42,
		color = {0.28, 0.2, 0.1},
		font_color = {1, 1, 1},
	})
	self.createButton({
		label = "Each player\n+2 basic lands",
		click_function = "pressVoteLands",
		function_owner = self,
		position = {0, 0.30, 1.1},
		rotation = {0, 0, 0},
		width = 550,
		height = 120,
		font_size = 42,
		color = {0.12, 0.18, 0.3},
		font_color = {1, 1, 1},
	})
	return
elseif activeConfig.mode == "vote_trader" then
	self.createButton({
		label = "Allow 2 trades",
		click_function = "pressVoteTraderTrades",
		function_owner = self,
		position = {0, 0.30, 0.5},
		rotation = {0, 0, 0},
		width = 550,
		height = 120,
		font_size = 42,
		color = {0.28, 0.15, 0.28},
		font_color = {1, 1, 1},
	})
	self.createButton({
		label = "Sell cards",
		click_function = "pressVoteTraderSell",
		function_owner = self,
		position = {0, 0.30, 0.8},
		rotation = {0, 0, 0},
		width = 550,
		height = 120,
		font_size = 42,
		color = {0.28, 0.15, 0.15},
		font_color = {1, 1, 1},
	})
	return
elseif activeConfig.mode == "hollyphant" or activeConfig.mode == "silly_jester" then
	-- Automatic traveler effects are applied in activateForDetectedObject.
	return
end

self.createButton({
label = activeConfig.label,
click_function = "pressWandererButton",
function_owner = self,
position = {0, 0.28, 0.5},
rotation = {0, 0, 0},
width = 550,
height = 100,
font_size = 52,
color = {0.12, 0.28, 0.14},
font_color = {1, 1, 1},
tooltip = "Each player can press once until a new Wanderer/Traveler is detected.",
})

if activeConfig.mode == "giant_ice_toad" then
self.createInput({
input_function = "setGiantIceToadXPInput",
function_owner = self,
label = "XP to transmute",
value = "",
alignment = 3,
position = {0, 0.28, 0.8},
rotation = {0, 0, 0},
width = 520,
height = 95,
font_size = 54,
validation = 2,
tab = 1,
tooltip = "Enter how much XP to spend. Giant Ice Toad gives triple essence.",
})
end

end

local function getVoteEligibleColors()
local out = {}
for _, color in ipairs(getSeatedColors()) do
if findSpawnerForColor(color) then
table.insert(out, color)
end
end
return out
end

local function countSelectedVotes()
local count = 0
for _, _ in pairs(voteSelections) do
count = count + 1
end
return count
end

local function applyBeardedGruntVote(choiceKey)
local outcomes = {
xp = {
message = "Bearded Grunt vote won: each player gains 15 XP.",
apply = function(spawner)
applyResourceToSpawner(spawner, "xp", 15)
end,
},
building = {
message = "Bearded Grunt vote won: each player may use one additional building this Town beyond its normal limit.",
apply = function(spawner)
pcall(function() spawner.call("grantBonusBuildingUse", { isGeneric = true }) end)
end,
},
land = {
message = "Bearded Grunt vote won: each player may add up to 2 basic lands to their deck.",
apply = function(spawner)
pcall(function() spawner.call("grantBasicLandAdds", { amount = 2 }) end)
end,
},
}

local outcome = outcomes[choiceKey]
if not outcome then return false end

for _, color in ipairs(voteEligibleColors) do
local spawner = findSpawnerForColor(color)
if spawner then
outcome.apply(spawner)
end
end

broadcastToAll(outcome.message, {0.75, 0.9, 1})
if choiceKey == "land" then
broadcastToAll("All players should know: the Bearded Grunt land option won.", {0.85, 1, 0.85})
end
return true
end

local function finalizeBeardedGruntVote()
local counts = { xp = 0, building = 0, land = 0 }
for _, choiceKey in pairs(voteSelections) do
if counts[choiceKey] ~= nil then
counts[choiceKey] = counts[choiceKey] + 1
end
end

local bestCount = -1
local tiedChoices = {}
for _, choiceKey in ipairs({"xp", "building", "land"}) do
local count = counts[choiceKey] or 0
if count > bestCount then
bestCount = count
tiedChoices = { choiceKey }
elseif count == bestCount then
table.insert(tiedChoices, choiceKey)
end
end

local chosenKey = tiedChoices[1]
if #tiedChoices > 1 then
chosenKey = tiedChoices[math.random(#tiedChoices)]
broadcastToAll("Bearded Grunt vote tied. Coin flip chose: " .. chosenKey, {1, 0.9, 0.5})
end

applyBeardedGruntVote(chosenKey)
clearActiveDetectionState(true)
end

local function castBeardedGruntVote(playerColor, choiceKey)
if not activeConfig or activeConfig.mode ~= "vote" then return end

local eligible = false
for _, color in ipairs(voteEligibleColors) do
if color == playerColor then
eligible = true
break
end
end

if not eligible then
printToColor("You do not have a detected spawner for this vote.", playerColor, {1, 0.3, 0.3})
return
end

if voteSelections[playerColor] then
printToColor("You already voted.", playerColor, {1, 0.8, 0.3})
return
end

voteSelections[playerColor] = choiceKey
pressedPlayers[playerColor] = true

local votesCast = countSelectedVotes()
local remaining = #voteEligibleColors - votesCast
printToColor("Vote recorded. Remaining voters: " .. tostring(math.max(0, remaining)), playerColor, {0.55, 1, 0.55})

if remaining <= 0 then
finalizeBeardedGruntVote()
end
end

function pressVoteXP(_, playerColor, _)
castBeardedGruntVote(playerColor, "xp")
end

function pressVoteBuilding(_, playerColor, _)
castBeardedGruntVote(playerColor, "building")
end

function pressVoteLands(_, playerColor, _)
castBeardedGruntVote(playerColor, "land")
end

local function applyTraderVote(choiceKey)
local outcomes = {
trades = {
message = "Trader vote won: each player may make 2 additional trades this Town.",
apply = function(spawner)
for _ = 1, 2 do
pcall(function() spawner.call("grantBonusBuildingUse", { buildingKey = "Bazaar", isGeneric = false }) end)
end
end,
},
sell = {
message = "Trader vote won: each player may sell up to two cards for XP equal to twice each card's mana value. Enter Sell Mode.",
apply = function(spawner)
pcall(function() spawner.call("enterSellMode", nil) end)
end,
},
}

local outcome = outcomes[choiceKey]
if not outcome then return false end

for _, color in ipairs(voteEligibleColors) do
local spawner = findSpawnerForColor(color)
if spawner then
outcome.apply(spawner)
end
end

broadcastToAll(outcome.message, {0.75, 1, 0.95})
return true
end

local function finalizeTraderVote()
local counts = { trades = 0, sell = 0 }
for _, choiceKey in pairs(voteSelections) do
if counts[choiceKey] ~= nil then
counts[choiceKey] = counts[choiceKey] + 1
end
end

local bestCount = -1
local tiedChoices = {}
for _, choiceKey in ipairs({"trades", "sell"}) do
local count = counts[choiceKey] or 0
if count > bestCount then
bestCount = count
tiedChoices = { choiceKey }
elseif count == bestCount then
table.insert(tiedChoices, choiceKey)
end
end

local chosenKey = tiedChoices[1]
if #tiedChoices > 1 then
chosenKey = tiedChoices[math.random(#tiedChoices)]
broadcastToAll("Trader vote tied. Coin flip chose: " .. chosenKey, {1, 0.9, 0.5})
end

applyTraderVote(chosenKey)
clearActiveDetectionState(true)
end

local function castTraderVote(playerColor, choiceKey)
if not activeConfig or activeConfig.mode ~= "vote_trader" then return end

local eligible = false
for _, color in ipairs(voteEligibleColors) do
if color == playerColor then
eligible = true
break
end
end

if not eligible then
printToColor("You do not have a detected spawner for this vote.", playerColor, {1, 0.3, 0.3})
return
end

if voteSelections[playerColor] then
printToColor("You already voted.", playerColor, {1, 0.8, 0.3})
return
end

voteSelections[playerColor] = choiceKey
pressedPlayers[playerColor] = true

local votesCast = countSelectedVotes()
local remaining = #voteEligibleColors - votesCast
printToColor("Vote recorded. Remaining voters: " .. tostring(math.max(0, remaining)), playerColor, {0.55, 1, 0.55})

if remaining <= 0 then
finalizeTraderVote()
end
end

function pressVoteTraderTrades(_, playerColor, _)
castTraderVote(playerColor, "trades")
end

function pressVoteTraderSell(_, playerColor, _)
castTraderVote(playerColor, "sell")
end

local function activateForDetectedObject(obj)
if not obj or not hasDetectionTag(obj) then return end

local guid = ""
pcall(function() guid = obj.getGUID() or "" end)
local name = getDetectionDisplayName(obj)

if guid ~= "" and guid == activeWandererGuid then return end

activeWandererGuid = guid
activeWandererName = trimName(name)
activeConfig = getWandererConfig(obj)
applyTravelerPreviewLabel(activeConfig)
pressedPlayers = {}
voteEligibleColors = {}
voteSelections = {}

local isTravelerObject = false
pcall(function() isTravelerObject = obj.hasTag("Traveler") end)
if isTravelerObject then
resetTownActionsViaMaster()
end

if activeConfig then
if activeConfig.mode == "silly_jester" then
setSillyJesterDiscountEnabled(true)
broadcastToAll(getEncounterMessage(obj, activeWandererName, true), {0.75, 0.9, 1})
return
elseif activeConfig.mode == "hollyphant" then
-- Auto-apply Hollyphant effect: grant Cathedral uses to all seated players
local seatedColors = getVoteEligibleColors()
for _, color in ipairs(seatedColors) do
local spawner = findSpawnerForColor(color)
if spawner then
pcall(function() spawner.call("grantBonusBuildingUse", { buildingKey = "Cathedral", isGeneric = false }) end)
end
end
broadcastToAll("A majestic Hollyphant blesses the town! Each player gains an additional Cathedral use this turn.", {0.75, 0.9, 1})
return
else
-- All other modes (vote, vote_trader, xp, etc)
if activeConfig.mode == "vote" then
voteEligibleColors = getVoteEligibleColors()
if #voteEligibleColors == 0 then
clearActionButton()
broadcastToAll("The Bearded Grunt has no detected spawners to vote.", {1, 0.3, 0.3})
return
end
elseif activeConfig.mode == "vote_trader" then
voteEligibleColors = getVoteEligibleColors()
if #voteEligibleColors == 0 then
clearActionButton()
broadcastToAll("The Trader has no detected spawners to vote.", {1, 0.3, 0.3})
return
end
end
createActionButton()
broadcastToAll(getEncounterMessage(obj, activeWandererName, true), {0.75, 0.9, 1})
end
else
local lowerName = safeLower(activeWandererName)
if string.find(lowerName, "fungal lich", 1, true) or string.find(lowerName, "lich lord", 1, true) then
notifySpawnersTravelerEffect(activeWandererName)
broadcastToAll(getEncounterMessage(obj, activeWandererName, true), {0.75, 0.9, 1})
clearActionButton()
return
end
clearActionButton()
broadcastToAll(getEncounterMessage(obj, activeWandererName, false), {0.75, 0.9, 1})
end
end

function onLoad(_)
spawnerScriptCache = {}
collidingTaggedGuids = {}
giantIceToadXPInput = {}
voteEligibleColors = {}
voteSelections = {}
activeSillyJesterGuids = {}
lastTravelerResetAt = 0
clearActionButton()
end

function onObjectDropped(_, _)
-- Intentionally disabled: activation only occurs on direct collision/landing.
end

function onCollisionEnter(collision_info)
if not collision_info then return end
local obj = collision_info.collision_object
if not obj or not hasDetectionTag(obj) then return end

local guid = ""
pcall(function() guid = obj.getGUID() or "" end)
if guid ~= "" then
collidingTaggedGuids[guid] = true
if isSillyJesterName(getDetectionDisplayName(obj)) then
activeSillyJesterGuids[guid] = true
end
end

activateForDetectedObject(obj)
end

function onCollisionExit(collision_info)
if not collision_info then return end
local obj = collision_info.collision_object
if not obj or not hasDetectionTag(obj) then return end

local guid = ""
pcall(function() guid = obj.getGUID() or "" end)
if guid ~= "" then
collidingTaggedGuids[guid] = nil
if isSillyJesterName(getDetectionDisplayName(obj)) then
activeSillyJesterGuids[guid] = nil
if not hasActiveSillyJester() then
setSillyJesterDiscountEnabled(false)
end
end
end

if guid ~= "" and guid == activeWandererGuid and not hasTaggedCollision() then
clearActiveDetectionState(true)
end
end

function pressWandererButton(_, playerColor, _)
if not activeConfig then
printToColor("No active Wanderer effect.", playerColor, {1, 0.3, 0.3})
return
end

if activeConfig.mode == "vote" then
printToColor("Use one of the Bearded Grunt vote buttons.", playerColor, {1, 0.8, 0.3})
return
end

if pressedPlayers[playerColor] then
printToColor("You already used this Wanderer this spawn.", playerColor, {1, 0.8, 0.3})
return
end

if activeConfig.mode == "bard" then
local now = nowSeconds()
local waitLeft = BARD_COOLDOWN_SECONDS - (now - bardLastUsedAt)
if waitLeft > 0 then
printToColor("Wandering Bard is on cooldown for " .. tostring(waitLeft) .. "s.", playerColor, {1, 0.8, 0.3})
return
end

local ok = applyBardToSeatedPlayers()
if ok then
bardLastUsedAt = now
pressedPlayers[playerColor] = true
end
return
end

if activeConfig.mode == "giant_ice_toad" then
local ok = applyGiantIceToadForPlayer(playerColor)
if ok then
pressedPlayers[playerColor] = true
end
return
end

local resourceType = activeConfig.resource or "xp"
local ok = applyToSinglePlayer(playerColor, resourceType, activeConfig.delta, activeConfig)
if ok then
pressedPlayers[playerColor] = true
local who = (activeWandererName and activeWandererName ~= "") and activeWandererName or "Wanderer"
printToColor("Used " .. who .. ".", playerColor, {0.55, 1, 0.55})
end
end


