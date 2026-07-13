---------------------------------------------------------------------------
-- MTG Roguelike — XP / Essence Master Controller
---------------------------------------------------------------------------

SPAWNER_TAG   = "MTGSpawner"
PLAYER_SPAWNER_TAG = "MTGPlayerSpawner"
MASTER_TAG    = "MTGMasterController"
MAX_PLAYERS   = 6
COMM_CACHE_SECONDS = 3

PLAYER_COLORS = {
    "White", "Brown", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink",
}

foundSpawners   = {}
spawnerCapabilityCache = {}
communicationCache = { at = 0, players = {}, byColor = {} }
xpGrantAmount   = 1
masterMode      = "xp"
historyLog      = {}
historyPage     = 1
currentScreen   = "main"
MAX_HISTORY        = 150
HISTORY_PAGE_SIZE  = 6
gameplaySettings = {
    dragovokiaTownDiscountEnabled      = false,
    sillyJesterMerchantDiscountEnabled = false,
    jackOLanternEnabled                = false,
    cursedPumpkinsEnabled              = false,
}

-- Button index layout (load-bearing — referenced by index in editButton calls):
--   Static buttons: 0 = Refresh, 1 = Grant All, 2 = Remove All,
--                   3 = Tab XP,  4 = Tab Essence, 5 = Tab History, 6 = Tab Settings
--   Static inputs:  0 = amount input
--   Per-player rows (6 rows × 4 buttons = 24), starting at index 7:
--     row i  →  base = 7 + (i-1)*4
--     base+0 = name display   base+1 = currency display
--     base+2 = +amount        base+3 = -amount

local MODE_THEME = {
    xp = {
        tabActive    = {0.15, 0.5, 0.15},
        tabInactive  = {0.2, 0.2, 0.2},
        grantLabel   = "Grant +XP",
        grantHandler = "click_grantAll",
        grantColor   = {0.15, 0.5, 0.15},
        removeLabel  = "Remove -XP",
        removeHandler= "click_removeAll",
        removeColor  = {0.5, 0.15, 0.15},
        rowAccent    = {0.1, 0.1, 0.4},
        rowPlusLabel = "+XP",
        rowMinusLabel= "-XP",
        rowPlusFn    = "grantXP_",
        rowMinusFn   = "removeXP_",
        rowPlusColor = {0.1, 0.5, 0.1},
        rowMinusColor= {0.5, 0.1, 0.1},
        slotPrefix   = "XP: ",
        slotEmpty    = "XP: --",
    },
    essence = {
        tabActive    = {0.4, 0.25, 0.55},
        tabInactive  = {0.2, 0.2, 0.2},
        grantLabel   = "Grant +Ess",
        grantHandler = "click_grantAllEssence",
        grantColor   = {0.4, 0.25, 0.55},
        removeLabel  = "Remove -Ess",
        removeHandler= "click_removeAllEssence",
        removeColor  = {0.35, 0.15, 0.45},
        rowAccent    = {0.4, 0.25, 0.55},
        rowPlusLabel = "+Ess",
        rowMinusLabel= "-Ess",
        rowPlusFn    = "grantEssence_",
        rowMinusFn   = "removeEssence_",
        rowPlusColor = {0.4, 0.25, 0.55},
        rowMinusColor= {0.35, 0.15, 0.45},
        slotPrefix   = "Ess: ",
        slotEmpty    = "Ess: --",
    },
}

local function theme() return MODE_THEME[masterMode] or MODE_THEME.xp end

local function nowSeconds()
    local ok, t = pcall(function() return Time.time end)
    if ok and type(t) == "number" then return t end
    return os.time() or 0
end

local function safeLower(v)
    if type(v) ~= "string" then return "" end
    return string.lower(v)
end

local function getPlayerSteamName(color)
    local p = Player[color]
    if p and p.steam_name then return safeLower(p.steam_name) end
    return ""
end

local function objectGuid(obj)
    local guid = ""
    pcall(function() guid = obj.getGUID() or "" end)
    return guid
end

local function hasSpawnerMethod(obj, methodName)
    if not obj or not methodName then return false end
    local ok, hasMethod = pcall(function()
        return obj.call("hasMTGSpawnerMethod", { name = methodName })
    end)
    return ok and hasMethod == true
end

local function isClaimedPlayerToken(obj)
    if not hasSpawnerMethod(obj, "isClaimedPlayerToken") then return false end
    local ok, claimed = pcall(function() return obj.call("isClaimedPlayerToken") end)
    return ok and claimed == true
end

local function claimedTokenMatchesColor(obj, color)
    local desiredName = getPlayerSteamName(color)
    if desiredName == "" then return false end

    if hasSpawnerMethod(obj, "getPlayerDisplayName") then
        local okName, displayName = pcall(function() return obj.call("getPlayerDisplayName") end)
        if okName and type(displayName) == "string" and safeLower(displayName) == desiredName then
            return true
        end
    end

    if hasSpawnerMethod(obj, "getPlayerKey") then
        local okKey, playerKey = pcall(function() return obj.call("getPlayerKey") end)
        if okKey and type(playerKey) == "string" then
            local keyName = safeLower(playerKey:gsub("_Essence$", ""))
            if keyName == desiredName then return true end
        end
    end

    return false
end

local function shallowCopyPlayers(players)
    local out = {}
    for i, entry in ipairs(players or {}) do
        out[i] = entry
    end
    return out
end

local function refreshCommunicationCache(force)
    local now = nowSeconds()
    if not force and communicationCache.players and (now - (communicationCache.at or 0)) < COMM_CACHE_SECONDS then
        return communicationCache
    end

    local cache = { at = now, players = {}, byColor = {} }
    local taggedPlayers = getObjectsWithTag(PLAYER_SPAWNER_TAG) or {}

    for _, color in ipairs(PLAYER_COLORS) do
        local p = Player[color]
        if p and p.seated then
            for _, obj in ipairs(taggedPlayers) do
                if obj ~= self and isClaimedPlayerToken(obj) and claimedTokenMatchesColor(obj, color) then
                    local name = color
                    pcall(function() name = obj.call("getPlayerDisplayName") or color end)
                    local entry = {
                        color = color,
                        name = name,
                        guid = objectGuid(obj),
                        spawner = obj,
                    }
                    table.insert(cache.players, entry)
                    cache.byColor[color] = entry
                    break
                end
            end
        end
    end

    communicationCache = cache
    return communicationCache
end

function getClaimedPlayerTokens(params)
    local force = type(params) == "table" and params.force == true
    return shallowCopyPlayers(refreshCommunicationCache(force).players)
end

function getClaimedPlayerToken(params)
    local color = ""
    if type(params) == "table" then color = tostring(params.color or params.playerColor or "") end
    if color == "" then return nil end
    local force = type(params) == "table" and params.force == true
    return refreshCommunicationCache(force).byColor[color]
end

function invalidateCommunicationCache()
    communicationCache = { at = 0, players = {}, byColor = {} }
end

local function callClaimedPlayerToken(entry, methodName, args)
    if type(entry) ~= "table" or not entry.spawner or type(methodName) ~= "string" or methodName == "" then
        return false
    end
    if not hasSpawnerMethod(entry.spawner, methodName) then return false end
    return pcall(function() entry.spawner.call(methodName, args) end)
end

function callClaimedPlayerTokens(params)
    if type(params) ~= "table" or type(params.method) ~= "string" then return 0 end
    local methodName = params.method
    local args = params.args
    local staggerFrames = math.max(1, math.floor(tonumber(params.staggerFrames) or 1))
    local players = getClaimedPlayerTokens({ force = params.force == true })
    local count = 0

    for i, entry in ipairs(players) do
        Wait.frames(function()
            callClaimedPlayerToken(entry, methodName, args)
        end, math.max(1, (i - 1) * staggerFrames))
        count = count + 1
    end

    return count
end

local function isPlayerSpawner(obj)
    if not obj or obj == self then return false end

    local okTagged, tagged = pcall(function() return obj.hasTag(PLAYER_SPAWNER_TAG) end)
    if okTagged and tagged then return true end

    local guid = ""
    pcall(function() guid = obj.getGUID() or "" end)
    if guid ~= "" and spawnerCapabilityCache[guid] ~= nil then
        return spawnerCapabilityCache[guid]
    end

    local script = ""
    pcall(function() script = obj.getLuaScript() or "" end)
    local isSpawner = string.find(script, "function%s+isMTGPlayerSpawner%s*%(") ~= nil
        or (string.find(script, "function%s+getXP%s*%(") ~= nil
            and string.find(script, "function%s+receiveXP%s*%(") ~= nil)

    if guid ~= "" then spawnerCapabilityCache[guid] = isSpawner end
    return isSpawner
end

local function getPlayerSpawnerObjects()
    local taggedPlayers = getObjectsWithTag(PLAYER_SPAWNER_TAG) or {}
    if #taggedPlayers > 0 then
        local out = {}
        for _, obj in ipairs(taggedPlayers) do
            if obj ~= self then table.insert(out, obj) end
        end
        return out
    end

    local out = {}
    for _, obj in ipairs(getObjectsWithTag(SPAWNER_TAG) or {}) do
        if isPlayerSpawner(obj) then table.insert(out, obj) end
    end
    return out
end

function hasMTGMasterMethod(params)
    local methodName = ""
    if type(params) == "table" then
        methodName = tostring(params.name or params.method or "")
    else
        methodName = tostring(params or "")
    end

    return ({
        resetTownActions = true,
        click_resetTownActions = true,
        setSillyJesterMerchantDiscountEnabled = true,
        getGameplaySettings = true,
        getClaimedPlayerTokens = true,
        getClaimedPlayerToken = true,
        callClaimedPlayerTokens = true,
        invalidateCommunicationCache = true,
        recordHistoryEvent = true,
    })[methodName] == true
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------

function onLoad(saved_data)
    self.addTag(MASTER_TAG)
    spawnerCapabilityCache = {}
    communicationCache = { at = 0, players = {}, byColor = {} }
    if saved_data and saved_data ~= "" then
        local ok, state = pcall(JSON.decode, saved_data)
        if ok and state then
            if state.xpGrantAmount then xpGrantAmount = state.xpGrantAmount end
            if state.masterMode == "essence" or state.masterMode == "xp" then
                masterMode = state.masterMode
            end
            if type(state.historyLog) == "table" then historyLog = state.historyLog end
            if type(state.historyPage) == "number" then historyPage = state.historyPage end
            if type(state.gameplaySettings) == "table" then
                local s = state.gameplaySettings
                gameplaySettings.dragovokiaTownDiscountEnabled = s.dragovokiaTownDiscountEnabled == true
                gameplaySettings.jackOLanternEnabled = s.jackOLanternEnabled == true
                gameplaySettings.cursedPumpkinsEnabled = s.cursedPumpkinsEnabled == true
            end
        end
    end

    gameplaySettings.sillyJesterMerchantDiscountEnabled = false

    showMainScreen()
    Wait.frames(refreshSpawners, 60)
end

function onSave()
    return JSON.encode({
        xpGrantAmount = xpGrantAmount,
        masterMode    = masterMode,
        historyLog    = historyLog,
        historyPage   = historyPage,
        gameplaySettings = gameplaySettings,
    })
end

---------------------------------------------------------------------------
-- Static UI
---------------------------------------------------------------------------

function createStaticUI()
    self.createButton({
        label = "Refresh", click_function = "click_refresh", function_owner = self,
        position = {-1.85, 0.1, -1.45},
        width = 500, height = 170, font_size = 85,
        color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "Grant +XP", click_function = "click_grantAll", function_owner = self,
        position = {0.35, 0.1, -1.45},
        width = 550, height = 170, font_size = 80,
        color = {0.15, 0.5, 0.15}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "Remove -XP", click_function = "click_removeAll", function_owner = self,
        position = {1.65, 0.1, -1.45},
        width = 550, height = 170, font_size = 80,
        color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "XP", click_function = "click_tabXP", function_owner = self,
        position = {-1.45, 0.1, -1.85},
        width = 330, height = 140, font_size = 72,
        color = {0.15, 0.5, 0.15}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "Essence", click_function = "click_tabEssence", function_owner = self,
        position = {-0.25, 0.1, -1.85},
        width = 330, height = 140, font_size = 60,
        color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "History", click_function = "click_historyTab", function_owner = self,
        position = {0.95, 0.1, -1.85},
        width = 330, height = 140, font_size = 60,
        color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "Settings", click_function = "click_settingsTab", function_owner = self,
        position = {2.15, 0.1, -1.85},
        width = 330, height = 140, font_size = 58,
        color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })

    self.createInput({
        input_function = "xpAmt_func", function_owner = self,
        label = "Amt", alignment = 3,
        position = {-0.85, 0.1, -1.45},
        width = 280, height = 170, font_size = 100,
        validation = 2, value = tostring(xpGrantAmount),
        color = {1, 1, 1}, font_color = {0, 0, 0},
    })
end

---------------------------------------------------------------------------
-- Player slot UI
---------------------------------------------------------------------------

local ROW_Z_START = -0.95
local ROW_Z_STEP  =  0.45

function slotBase(i) return 7 + (i - 1) * 4 end

function createPlayerSlots()
    for i = 1, MAX_PLAYERS do
        local z = ROW_Z_START + (i - 1) * ROW_Z_STEP

        self.createButton({
            label = "---", click_function = "mc_noop", function_owner = self,
            position = {-1.30, 0.1, z},
            width = 900, height = 150, font_size = 70,
            color = {0.92, 0.88, 0.78}, font_color = {0, 0, 0},
        })
        self.createButton({
            label = "XP: --", click_function = "mc_noop", function_owner = self,
            position = {0.30, 0.1, z},
            width = 400, height = 150, font_size = 85,
            color = {0.1, 0.1, 0.4}, font_color = {1, 1, 1},
        })
        self.createButton({
            label = "+XP", click_function = "grantXP_" .. i, function_owner = self,
            position = {1.20, 0.1, z},
            width = 280, height = 150, font_size = 95,
            color = {0.15, 0.5, 0.15}, font_color = {1, 1, 1},
        })
        self.createButton({
            label = "-XP", click_function = "removeXP_" .. i, function_owner = self,
            position = {1.95, 0.1, z},
            width = 280, height = 150, font_size = 95,
            color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
        })
    end
end

---------------------------------------------------------------------------
-- Mode handling
---------------------------------------------------------------------------

function setMasterMode(mode)
    if mode ~= "xp" and mode ~= "essence" then return end
    if mode == masterMode then return end
    masterMode = mode
    applyModeAppearance()
    updateSlotDisplay()
    self.script_state = onSave()
end

function click_tabXP()      setMasterMode("xp")      end
function click_tabEssence() setMasterMode("essence") end

function applyModeAppearance()
    if currentScreen ~= "main" then return end
    local t = theme()
    local activeIdx, inactiveIdx = (masterMode == "xp") and 3 or 4, (masterMode == "xp") and 4 or 3
    self.editButton({ index = activeIdx,   color = t.tabActive })
    self.editButton({ index = inactiveIdx, color = t.tabInactive })
    self.editButton({ index = 5, color = {0.2, 0.2, 0.2} })
    self.editButton({ index = 6, color = {0.2, 0.2, 0.2} })

    self.editButton({
        index = 1, label = t.grantLabel, click_function = t.grantHandler, color = t.grantColor,
    })
    self.editButton({
        index = 2, label = t.removeLabel, click_function = t.removeHandler, color = t.removeColor,
    })

    for i = 1, MAX_PLAYERS do
        local base = slotBase(i)
        self.editButton({ index = base + 1, color = t.rowAccent })
        self.editButton({ index = base + 2, label = t.rowPlusLabel,  click_function = t.rowPlusFn  .. i })
        self.editButton({ index = base + 3, label = t.rowMinusLabel, click_function = t.rowMinusFn .. i })
    end
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function refreshSpawners()
    foundSpawners = {}

    for _, obj in ipairs(getPlayerSpawnerObjects()) do
        table.insert(foundSpawners, obj)
    end

    table.sort(foundSpawners, function(a, b)
        return (a.getName() or "") < (b.getName() or "")
    end)

    updateSlotDisplay()
end

function updateSlotDisplay()
    if currentScreen ~= "main" then return end
    local t = theme()
    for i = 1, MAX_PLAYERS do
        local base    = slotBase(i)
        local spawner = foundSpawners[i]

        if spawner then
            local name = ""
            local okN, n = pcall(function() return spawner.call("getPlayerDisplayName") end)
            if okN and type(n) == "string" and n ~= "" then
                name = n
            else
                name = spawner.getName()
            end
            if name == "" then name = "Player " .. i end

            local currentVal = 0
            local getter = (masterMode == "xp") and "getXP" or "getEssence"
            local okV, val = pcall(function() return spawner.call(getter) end)
            if okV and val ~= nil then currentVal = val end

            self.editButton({ index = base,     label = name })
            self.editButton({ index = base + 1, label = t.slotPrefix .. currentVal })
            self.editButton({ index = base + 2, color = t.rowPlusColor })
            self.editButton({ index = base + 3, color = t.rowMinusColor })
        else
            self.editButton({ index = base,     label = "---" })
            self.editButton({ index = base + 1, label = t.slotEmpty })
            self.editButton({ index = base + 2, color = {0.3, 0.3, 0.3} })
            self.editButton({ index = base + 3, color = {0.3, 0.3, 0.3} })
        end
    end
end

---------------------------------------------------------------------------
-- Static button callbacks
---------------------------------------------------------------------------

function click_refresh() refreshSpawners() end

local function broadcastDelta(method, amount)
    local htype    = (method == "receiveXP") and "xp" or "essence"
    local getter   = (htype == "xp") and "getXP" or "getEssence"
    local targets  = {}
    local anyBuff  = false
    for _, spawner in ipairs(foundSpawners) do
        local before = nil
        local okBefore, beforeVal = pcall(function() return spawner.call(getter) end)
        if okBefore and type(beforeVal) == "number" then before = beforeVal end

        pcall(function() spawner.call(method, { amount = amount, suppressMasterHistory = true }) end)

        local applied = amount
        local okAfter, afterVal = pcall(function() return spawner.call(getter) end)
        if before ~= nil and okAfter and type(afterVal) == "number" then
            applied = afterVal - before
        end

        local name = ""
        local ok2, n = pcall(function() return spawner.call("getPlayerDisplayName") end)
        if ok2 and type(n) == "string" and n ~= "" then name = n else name = spawner.getName() end
        table.insert(targets, { spawnerGuid = spawner.getGUID(), playerName = name, finalAmount = applied })
        if applied ~= amount then anyBuff = true end
    end
    if #targets > 0 then
        appendHistoryEntry({
            htype      = htype,
            isAll      = true,
            playerName = "All Players",
            rawAmount  = amount,
            finalAmount = amount,
            targets    = targets,
            anyBuff    = anyBuff,
            reason     = "Manual " .. (amount >= 0 and "Grant All" or "Remove All"),
            source     = "XP Master",
            isReverted = false,
            timestamp  = os.date("%H:%M:%S"),
        })
    end
    Wait.frames(refreshSpawners, 45)
end

function click_grantAll()         broadcastDelta("receiveXP",       xpGrantAmount) end
function click_removeAll()        broadcastDelta("receiveXP",      -xpGrantAmount) end
function click_grantAllEssence()  broadcastDelta("receiveEssence",  xpGrantAmount) end
function click_removeAllEssence() broadcastDelta("receiveEssence", -xpGrantAmount) end

function xpAmt_func(_, _, input, stillEditing)
    if not stillEditing then
        xpGrantAmount = math.max(1, math.floor(tonumber(input) or 1))
        self.script_state = onSave()
    end
end

---------------------------------------------------------------------------
-- Per-player callbacks — TTS click handlers must be globals, hence _G[...]
---------------------------------------------------------------------------

function applyXP(index, amount)
    local spawner = foundSpawners[index]
    if not spawner then
        broadcastToAll("Slot " .. index .. " has no player spawner. Click Refresh.")
        return
    end
    local before = nil
    local okBefore, beforeVal = pcall(function() return spawner.call("getXP") end)
    if okBefore and type(beforeVal) == "number" then before = beforeVal end

    pcall(function() spawner.call("receiveXP", { amount = amount, suppressMasterHistory = true }) end)

    local applied = amount
    local okAfter, afterVal = pcall(function() return spawner.call("getXP") end)
    if before ~= nil and okAfter and type(afterVal) == "number" then
        applied = afterVal - before
    end
    logHistoryEntry(spawner, "xp", amount, applied, applied ~= amount)
    Wait.frames(refreshSpawners, 45)
end

function applyEssence(index, amount)
    local spawner = foundSpawners[index]
    if not spawner then
        broadcastToAll("Slot " .. index .. " has no player spawner. Click Refresh.")
        return
    end
    local before = nil
    local okBefore, beforeVal = pcall(function() return spawner.call("getEssence") end)
    if okBefore and type(beforeVal) == "number" then before = beforeVal end

    pcall(function() spawner.call("receiveEssence", { amount = amount, suppressMasterHistory = true }) end)

    local applied = amount
    local okAfter, afterVal = pcall(function() return spawner.call("getEssence") end)
    if before ~= nil and okAfter and type(afterVal) == "number" then
        applied = afterVal - before
    end
    logHistoryEntry(spawner, "essence", amount, applied, applied ~= amount)
    Wait.frames(refreshSpawners, 45)
end

for i = 1, MAX_PLAYERS do
    _G["grantXP_"      .. i] = function() applyXP(i,       xpGrantAmount) end
    _G["removeXP_"     .. i] = function() applyXP(i,      -xpGrantAmount) end
    _G["grantEssence_" .. i] = function() applyEssence(i,  xpGrantAmount) end
    _G["removeEssence_".. i] = function() applyEssence(i, -xpGrantAmount) end
end

function mc_noop() end

function refreshSlots()          refreshSpawners() end
function spawnerXPChanged()      refreshSpawners() end
function spawnerEssenceChanged() refreshSpawners() end

function getGameplaySettings()
    return {
        dragovokiaTownDiscountEnabled      = gameplaySettings.dragovokiaTownDiscountEnabled == true,
        sillyJesterMerchantDiscountEnabled = gameplaySettings.sillyJesterMerchantDiscountEnabled == true,
        jackOLanternEnabled                = gameplaySettings.jackOLanternEnabled == true,
        cursedPumpkinsEnabled              = gameplaySettings.cursedPumpkinsEnabled == true,
    }
end

function setSillyJesterMerchantDiscountEnabled(params)
    local enabled = false
    if type(params) == "table" then
        enabled = params.enabled == true
    else
        enabled = params == true
    end
    if gameplaySettings.sillyJesterMerchantDiscountEnabled == enabled then
        return enabled
    end
    gameplaySettings.sillyJesterMerchantDiscountEnabled = enabled
    self.script_state = onSave()
    if currentScreen == "settings" then
        showSettingsScreen()
    end
    return enabled
end

---------------------------------------------------------------------------
-- Screen management
---------------------------------------------------------------------------

function showMainScreen()
    currentScreen = "main"
    self.clearButtons()
    self.clearInputs()
    createStaticUI()
    createPlayerSlots()
    applyModeAppearance()
end

---------------------------------------------------------------------------
-- Settings screen
---------------------------------------------------------------------------

local function settingLabel(value)
    return value and "ON" or "OFF"
end

local function settingColor(value, onColor, offColor)
    if value then return onColor end
    return offColor
end

function showSettingsScreen()
    currentScreen = "settings"
    self.clearButtons()
    self.clearInputs()

    self.createButton({
        label = "< Back", click_function = "click_settingsBack", function_owner = self,
        position = {-1.85, 0.1, -1.45}, width = 500, height = 170, font_size = 85,
        color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "XP Master Settings", click_function = "mc_noop", function_owner = self,
        position = {0.4, 0.1, -1.45}, width = 1050, height = 170, font_size = 70,
        color = {0.15, 0.15, 0.4}, font_color = {1, 1, 1},
    })

    self.createButton({
        label = "Dragovokia\n" .. settingLabel(gameplaySettings.dragovokiaTownDiscountEnabled),
        click_function = "click_toggleDragovokia", function_owner = self,
        position = {-0.95, 0.1, -0.70}, width = 900, height = 280, font_size = 70,
        color = settingColor(gameplaySettings.dragovokiaTownDiscountEnabled, {0.15, 0.45, 0.15}, {0.45, 0.15, 0.15}),
        font_color = {1, 1, 1},
        tooltip = "Town actions that cost XP cost 5 less XP (minimum 5 XP).",
    })
    self.createButton({
        label = "Silly, the Jester\nTraveler Controlled",
        click_function = "mc_noop", function_owner = self,
        position = {1.05, 0.1, -0.70}, width = 900, height = 280, font_size = 62,
        color = gameplaySettings.sillyJesterMerchantDiscountEnabled and {0.15, 0.4, 0.2} or {0.22, 0.22, 0.22},
        font_color = {1, 1, 1},
        tooltip = "Active only while Silly, the Jester is in town. Merchant packs cost 50% less, rounded down to nearest 5 XP (minimum 5 XP).",
    })
    self.createButton({
        label = "Jack-o-Lantern\n" .. settingLabel(gameplaySettings.jackOLanternEnabled),
        click_function = "click_toggleJackOLantern", function_owner = self,
        position = {-0.95, 0.1, 0.45}, width = 900, height = 320, font_size = 63,
        color = settingColor(gameplaySettings.jackOLanternEnabled, {0.5, 0.35, 0.05}, {0.3, 0.15, 0.08}),
        font_color = {1, 0.95, 0.7},
        tooltip = "Cathedral is disabled. XP gains are increased by +40% (additive).",
    })
    self.createButton({
        label = "Cursed Pumpkins\n" .. settingLabel(gameplaySettings.cursedPumpkinsEnabled),
        click_function = "click_toggleCursedPumpkins", function_owner = self,
        position = {1.05, 0.1, 0.45}, width = 900, height = 320, font_size = 58,
        color = settingColor(gameplaySettings.cursedPumpkinsEnabled, {0.45, 0.25, 0.05}, {0.25, 0.12, 0.08}),
        font_color = {1, 0.92, 0.65},
        tooltip = "Merchant packs are once per town per player. Cathedral, Upgrade, and Augment are disabled. XP gains are increased by +100% (additive).",
    })
    self.createButton({
        label = "Reset Town Actions",
        click_function = "click_resetTownActions", function_owner = self,
        position = {0.05, 0.1, 1.55}, width = 1800, height = 210, font_size = 78,
        color = {0.5, 0.32, 0.08}, font_color = {1, 0.95, 0.75},
        tooltip = "Resets per-town action locks on all player tokens (for example Cursed Pumpkins merchant purchase limits).",
    })
end

local function toggleSetting(key)
    if gameplaySettings[key] == nil then return end
    gameplaySettings[key] = not gameplaySettings[key]
    self.script_state = onSave()
    showSettingsScreen()
end

function click_settingsTab()            showSettingsScreen() end
function click_settingsBack()           showMainScreen(); Wait.frames(refreshSpawners, 5) end
function click_toggleDragovokia()       toggleSetting("dragovokiaTownDiscountEnabled") end
function click_toggleJackOLantern()     toggleSetting("jackOLanternEnabled") end
function click_toggleCursedPumpkins()   toggleSetting("cursedPumpkinsEnabled") end

local function resetTownActionsForSpawners()
    local resetCount = 0
    for _, obj in ipairs(getPlayerSpawnerObjects()) do
        local ok = pcall(function() obj.call("resetTownActions") end)
        if ok then resetCount = resetCount + 1 end
    end
    return resetCount
end

function resetTownActions(params)
    local silent = type(params) == "table" and params.silent == true
    local skipUi = type(params) == "table" and params.skipUi == true
    local resetCount = resetTownActionsForSpawners()
    if not silent then
        broadcastToAll("[XP Master] Reset Town Actions applied to " .. tostring(resetCount) .. " spawner(s).", {0.95, 0.75, 0.35})
    end
    if not skipUi and currentScreen == "settings" then
        showSettingsScreen()
    end
    return resetCount
end

function click_resetTownActions()
    resetTownActions()
end

---------------------------------------------------------------------------
-- History log helpers
---------------------------------------------------------------------------

local function trimHistory()
    while #historyLog > MAX_HISTORY do table.remove(historyLog) end
end

local function normalizeHistoryType(htype)
    htype = tostring(htype or "xp")
    if htype == "ess" or htype == "essence" then return "essence" end
    return "xp"
end

function appendHistoryEntry(entry)
    if type(entry) ~= "table" then return nil end
    entry.htype = normalizeHistoryType(entry.htype)
    entry.playerName = tostring(entry.playerName or "Unknown")
    entry.reason = tostring(entry.reason or entry.description or "Adjustment")
    entry.source = tostring(entry.source or "XP Master")
    entry.timestamp = entry.timestamp or os.date("%H:%M:%S")
    entry.isReverted = entry.isReverted == true
    if type(entry.finalAmount) ~= "number" then
        entry.finalAmount = tonumber(entry.amount or entry.rawAmount) or 0
    end
    if type(entry.rawAmount) ~= "number" then entry.rawAmount = entry.finalAmount end
    table.insert(historyLog, 1, entry)
    trimHistory()
    self.script_state = onSave()
    if currentScreen == "history" then showHistoryScreen() end
    return entry
end

function recordHistoryEvent(params)
    if type(params) ~= "table" then return false end
    local entry = {
        htype         = params.htype or params.type or params.resource,
        spawnerGuid   = params.spawnerGuid,
        playerName    = params.playerName,
        rawAmount     = tonumber(params.rawAmount or params.amount),
        finalAmount   = tonumber(params.finalAmount or params.applied or params.amount),
        balanceBefore = tonumber(params.balanceBefore),
        balanceAfter  = tonumber(params.balanceAfter or params.balance),
        reason        = params.reason or params.description,
        source        = params.source,
        isExternal    = true,
        isReverted    = false,
        timestamp     = params.timestamp or os.date("%H:%M:%S"),
    }
    appendHistoryEntry(entry)
    return true
end

function logHistoryEntry(spawner, htype, rawAmount, finalAmount, buffApplied)
    local name = ""
    local ok, n = pcall(function() return spawner.call("getPlayerDisplayName") end)
    if ok and type(n) == "string" and n ~= "" then name = n else name = spawner.getName() end
    appendHistoryEntry({
        htype       = htype,
        spawnerGuid = spawner.getGUID(),
        playerName  = name,
        rawAmount   = rawAmount,
        finalAmount = finalAmount,
        buffApplied = buffApplied,
        reason      = "Manual " .. ((rawAmount or 0) >= 0 and "Grant" or "Remove"),
        source      = "XP Master",
        isReverted  = false,
        timestamp   = os.date("%H:%M:%S"),
    })
end

function revertHistoryEntry(entryIdx)
    local entry = historyLog[entryIdx]
    if not entry or entry.isReverted then return end
    local method = (entry.htype == "xp") and "receiveXP" or "receiveEssence"
    if entry.isAll then
        for _, target in ipairs(entry.targets or {}) do
            local spawner = nil
            for _, s in ipairs(getObjectsWithTag(SPAWNER_TAG)) do
                if s.getGUID() == target.spawnerGuid then spawner = s; break end
            end
            if spawner then
                pcall(function() spawner.call(method, { amount = -target.finalAmount, bypassBuff = true, suppressMasterHistory = true }) end)
            end
        end
    else
        local spawner = nil
        for _, s in ipairs(getObjectsWithTag(SPAWNER_TAG)) do
            if s.getGUID() == entry.spawnerGuid then spawner = s; break end
        end
        if not spawner then
            broadcastToAll("Cannot revert: spawner for " .. entry.playerName .. " not found.")
            return
        end
        pcall(function() spawner.call(method, { amount = -entry.finalAmount, bypassBuff = true, suppressMasterHistory = true }) end)
    end
    entry.isReverted = true
    appendHistoryEntry({
        htype = entry.htype,
        playerName = entry.isAll and "All Players" or entry.playerName,
        spawnerGuid = entry.spawnerGuid,
        rawAmount = -(entry.finalAmount or entry.rawAmount or 0),
        finalAmount = -(entry.finalAmount or entry.rawAmount or 0),
        reason = "Revert: " .. tostring(entry.reason or "Adjustment"),
        source = "XP Master",
        isRevertEntry = true,
        isReverted = true,
    })
    self.script_state = onSave()
    Wait.frames(showHistoryScreen, 15)
end

for i = 1, HISTORY_PAGE_SIZE do
    _G["revertEntry_" .. i] = function()
        local entryIdx = (historyPage - 1) * HISTORY_PAGE_SIZE + i
        revertHistoryEntry(entryIdx)
    end
end

---------------------------------------------------------------------------
-- History screen
---------------------------------------------------------------------------

function showHistoryScreen()
    currentScreen = "history"
    self.clearButtons()
    self.clearInputs()

    local totalEntries = #historyLog
    local totalPages   = math.max(1, math.ceil(totalEntries / HISTORY_PAGE_SIZE))
    historyPage = math.min(historyPage, totalPages)

    -- Static row 1: Back | Title | Page
    self.createButton({
        label = "< Back", click_function = "click_historyBack", function_owner = self,
        position = {-1.85, 0.1, -1.45}, width = 500, height = 170, font_size = 85,
        color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "XP & Ess History", click_function = "mc_noop", function_owner = self,
        position = {0.25, 0.1, -1.45}, width = 750, height = 170, font_size = 70,
        color = {0.15, 0.15, 0.4}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "Pg " .. historyPage .. "/" .. totalPages, click_function = "mc_noop", function_owner = self,
        position = {1.65, 0.1, -1.45}, width = 350, height = 170, font_size = 75,
        color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })
    -- Static row 2: Prev | Next
    self.createButton({
        label = "< Prev", click_function = "click_histPrev", function_owner = self,
        position = {-0.72, 0.1, -1.85}, width = 550, height = 140, font_size = 75,
        color = (historyPage > 1) and {0.3, 0.3, 0.55} or {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })
    self.createButton({
        label = "Next >", click_function = "click_histNext", function_owner = self,
        position = {0.72, 0.1, -1.85}, width = 550, height = 140, font_size = 75,
        color = (historyPage < totalPages) and {0.3, 0.3, 0.55} or {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
    })

    -- Entry rows
    local startIdx = (historyPage - 1) * HISTORY_PAGE_SIZE + 1
    for row = 1, HISTORY_PAGE_SIZE do
        local entryIdx = startIdx + row - 1
        local z        = ROW_Z_START + (row - 1) * ROW_Z_STEP

        if entryIdx <= totalEntries then
            local e       = historyLog[entryIdx]
            local typeStr = (e.htype == "xp") and "XP" or "Ess"
            local nameLabel, amtLabel, amtColor
            if e.isAll then
                local n    = #(e.targets or {})
                nameLabel  = "All (" .. n .. ")"
                local sign = e.rawAmount >= 0 and "+" or ""
                local star = e.anyBuff and " *" or ""
                amtLabel   = sign .. e.rawAmount .. " " .. typeStr .. star
                amtColor   = e.rawAmount >= 0 and {0.1, 0.35, 0.1} or {0.35, 0.1, 0.1}
            else
                nameLabel  = e.playerName
                local sign = e.finalAmount >= 0 and "+" or ""
                local star = e.buffApplied and " *" or ""
                amtLabel   = sign .. e.finalAmount .. " " .. typeStr .. star
                amtColor   = e.finalAmount >= 0 and {0.1, 0.35, 0.1} or {0.35, 0.1, 0.1}
            end
            local reasonLabel = tostring(e.reason or e.source or "")
            local nameFont = 70
            if reasonLabel ~= "" then
                nameLabel = nameLabel .. "\n" .. reasonLabel
                nameFont = 48
            end
            local revertLabel = e.isReverted and "Done" or "Revert"
            local revertColor = e.isReverted and {0.3, 0.3, 0.3} or {0.7, 0.4, 0.1}

            self.createButton({ label = nameLabel, click_function = "mc_noop", function_owner = self,
                position = {-1.30, 0.1, z}, width = 900, height = 150, font_size = nameFont,
                color = {0.92, 0.88, 0.78}, font_color = {0, 0, 0},
            })
            self.createButton({ label = amtLabel, click_function = "mc_noop", function_owner = self,
                position = {0.30, 0.1, z}, width = 400, height = 150, font_size = 75,
                color = amtColor, font_color = {1, 1, 1},
            })
            self.createButton({ label = e.timestamp, click_function = "mc_noop", function_owner = self,
                position = {1.20, 0.1, z}, width = 280, height = 150, font_size = 60,
                color = {0.18, 0.18, 0.18}, font_color = {0.65, 0.65, 0.65},
            })
            self.createButton({ label = revertLabel, click_function = "revertEntry_" .. row, function_owner = self,
                position = {1.95, 0.1, z}, width = 280, height = 150, font_size = 75,
                color = revertColor, font_color = {1, 1, 1},
            })
        else
            -- Empty row placeholder
            for _, x in ipairs({-1.30, 0.30, 1.20, 1.95}) do
                self.createButton({ label = "", click_function = "mc_noop", function_owner = self,
                    position = {x, 0.1, z}, width = (x == -1.30) and 900 or 280, height = 150, font_size = 70,
                    color = {0.12, 0.12, 0.12}, font_color = {0.4, 0.4, 0.4},
                })
            end
        end
    end
end

---------------------------------------------------------------------------
-- History click handlers
---------------------------------------------------------------------------

function click_historyTab()  showHistoryScreen() end

function click_historyBack()
    showMainScreen()
    Wait.frames(refreshSpawners, 5)
end

function click_histPrev()
    if historyPage > 1 then
        historyPage = historyPage - 1
        showHistoryScreen()
    end
end

function click_histNext()
    local total = math.max(1, math.ceil(#historyLog / HISTORY_PAGE_SIZE))
    if historyPage < total then
        historyPage = historyPage + 1
        showHistoryScreen()
    end
end
