-----------------------------------------------------------------------
-- Global variable for the card back image URL:
backURL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
-- Backend Configuration
-- Local default: change port to 3001 if using docker-compose.local.yml
BACKEND_URL = "http://api.mtginfo.org"
--BACKEND_URL = "http://localhost:3000"

-- Relative anchor reused from Start Token
SPAWN_BUTTON_LOCAL = Vector{-4.2, 0, -3.9}
SPAWN_HEIGHT_OFFSET = 2

-- Anchor state
lastAnchorPos = nil
lastAnchorRot = nil
lastAnchorWorld = nil

-- Spawning state tracking (prevents concurrent spawns)
isSpawning = false
spawnIndicatorText = nil
cardsSpawned = 0
totalCardsToSpawn = 0
RANDOM_CARD_SPAWN_COUNT = 100
scriptActive = true

-- Commander color filter variables (separate from card color filters)
CommanderWhite = false
CommanderBlue = false
CommanderBlack = false
CommanderRed = false
CommanderGreen = false
CommanderColorless = false
CommanderLockoutMode = false  -- false = Color Combo Mode, true = Lockout Mode
COMMANDER_SPAWN_MIN = 1
COMMANDER_SPAWN_MAX = 20
commanderSpawnCount = 5

-- Dynamic button index cache keyed by click_function
buttonIndexesByClick = {}

local function refreshButtonIndexes()
    buttonIndexesByClick = {}
    local buttons = self.getButtons() or {}
    for i, btn in ipairs(buttons) do
        if btn and btn.click_function then
            buttonIndexesByClick[btn.click_function] = i - 1
        end
    end
end

local function getButtonIndex(clickFunctionName)
    refreshButtonIndexes()
    return buttonIndexesByClick[clickFunctionName]
end

local function setButtonToggleColor(clickFunctionName, color)
    local idx = getButtonIndex(clickFunctionName)
    if idx ~= nil then
        self.editButton({ index = idx, color = color })
    end
end
--------------------------------------------------------------------------
function onLoad()
    scriptActive = true
    createSpawnButton()
end

-----------------------------------------------------------------------
-- SPAWN ANCHOR
-----------------------------------------------------------------------
function getSpawnAnchor()
    local pos = self.getPosition()
    local rot = self.getRotation()

    local moved = (not lastAnchorPos) or math.abs(pos.x - lastAnchorPos.x) > 0.001 or math.abs(pos.y - lastAnchorPos.y) > 0.001 or math.abs(pos.z - lastAnchorPos.z) > 0.001
    local rotated = (not lastAnchorRot) or math.abs(rot.x - lastAnchorRot.x) > 0.001 or math.abs(rot.y - lastAnchorRot.y) > 0.001 or math.abs(rot.z - lastAnchorRot.z) > 0.001

    if moved or rotated or not lastAnchorWorld then
        local anchorLocal = Vector{SPAWN_BUTTON_LOCAL.x, SPAWN_BUTTON_LOCAL.y + SPAWN_HEIGHT_OFFSET, SPAWN_BUTTON_LOCAL.z}
        lastAnchorWorld = self.positionToWorld(anchorLocal)
        lastAnchorPos = pos
        lastAnchorRot = rot
    end
    return lastAnchorWorld
end

-----------------------------------------------------------------------
-- SPAWNING INDICATOR FUNCTIONS (similar to MTG Importer)
-----------------------------------------------------------------------
function getSpawningProgressText()
    return 'Spawning...\n' .. totalCardsToSpawn .. ' cards'
end

function createSpawningIndicator(position)
    if spawnIndicatorText then
        destroySpawningIndicator()
    end
    
    -- Create 3D text indicator above the spawn position
    local textPosition = {position.x, position.y + 3, position.z}
    local selfRot = self.getRotation()
    local textObject = spawnObject({
        type = '3DText',
        position = textPosition,
        rotation = {selfRot.x, selfRot.y + 180, selfRot.z}
    })
    
    textObject.TextTool.setValue(getSpawningProgressText())
    textObject.TextTool.setFontSize(60)
    spawnIndicatorText = textObject
end

function updateSpawningIndicator()
    if spawnIndicatorText then
        spawnIndicatorText.TextTool.setValue(getSpawningProgressText())
    end
end

function destroySpawningIndicator()
    if spawnIndicatorText then
        spawnIndicatorText.destruct()
        spawnIndicatorText = nil
    end
end

function endSpawning()
    isSpawning = false
    cardsSpawned = 0
    totalCardsToSpawn = 0
    destroySpawningIndicator()
end

local function splitLines(resp)
    local lines = {}
    for s in (resp or ''):gmatch('[^\r\n]+') do
        table.insert(lines, s)
    end
    return lines
end

local function decodeNDJSONLine(line)
    if not line or line == '' then
        return nil
    end

    local ok, parsed = pcall(function()
        return JSON.decode(line)
    end)

    if not ok then
        return nil
    end

    return parsed
end

local function postNDJSON(url, payload, callback)
    WebRequest.custom(
        url,
        'POST',
        true,
        JSON.encode(payload),
        {
            Accept = 'application/x-ndjson',
            ['Content-Type'] = 'application/json',
            ['Accept-Language'] = 'en'
        },
        callback
    )
end

local spawnNDJSONQueue

local function buildDeckFromTTSObjects(cards, spawnPos)
    if not cards or #cards <= 1 then
        return nil
    end

    local customDeck = {}
    local deckIDs = {}
    local containedObjects = {}

    for i, card in ipairs(cards) do
        deckIDs[i] = card.CardID
        containedObjects[i] = card

        for key, value in pairs(card.CustomDeck or {}) do
            customDeck[tostring(key)] = value
        end

        if card.States then
            for _, state in pairs(card.States) do
                if state and state.CustomDeck then
                    for stateKey, stateValue in pairs(state.CustomDeck) do
                        customDeck[tostring(stateKey)] = stateValue
                    end
                end
            end
        end
    end

    local selfRot = self.getRotation()
    local deckTransform = {
        posX = spawnPos and spawnPos.x or 0,
        posY = spawnPos and spawnPos.y or 2,
        posZ = spawnPos and spawnPos.z or 0,
        rotX = selfRot.x,
        rotY = selfRot.y,
        rotZ = 180,
        scaleX = 1,
        scaleY = 1,
        scaleZ = 1
    }

    return {
        Name = 'DeckCustom',
        Nickname = 'Deck',
        Description = '',
        Transform = deckTransform,
        HideWhenFaceDown = false,
        DeckIDs = deckIDs,
        CustomDeck = customDeck,
        ContainedObjects = containedObjects
    }
end

local function finishSpawnFromNDJSON(respText, spawnPos, onComplete)
    spawnNDJSONQueue(respText, spawnPos, function(spawnedCount)
        if spawnedCount <= 0 then
            print('No valid cards to spawn')
        end
        Wait.time(function()
            endSpawning()
            if onComplete then onComplete(spawnedCount > 0) end
        end, 0.25)
    end)
end

local function handleNDJSONBuildResponse(resp, spawnPos, onComplete, onFallback, context)
    if not resp.is_done then
        return
    end

    if resp.is_error or (resp.response_code and resp.response_code >= 400) or not resp.text or resp.text == '' then
        local details = resp.error or ('HTTP ' .. tostring(resp.response_code or 'unknown'))
        if resp.text and resp.text ~= '' then
            details = details .. ' | ' .. tostring(resp.text)
        end
        print((context or 'NDJSON build request failed') .. ': ' .. tostring(details))
        if onFallback then
            onFallback(resp)
            return
        end
        endSpawning()
        if onComplete then onComplete(false) end
        return
    end

    finishSpawnFromNDJSON(resp.text, spawnPos, onComplete)
end

spawnNDJSONQueue = function(respText, spawnPos, onDone, batchSize)
    local lines = splitLines(respText)
    local fallbackSpawnLines = {}
    local cardObjects = {}
    local directDeck = nil
    local issues = {}

    for _, line in ipairs(lines) do
        local parsed = decodeNDJSONLine(line)
        if parsed and parsed.object == 'warning' then
            issues[#issues + 1] = parsed.warning or ((parsed.card_name or 'Card') .. ' was skipped')
        elseif parsed and parsed.object == 'error' then
            issues[#issues + 1] = parsed.error or parsed.details or 'Spawn error'
        elseif parsed and parsed.Name == 'DeckCustom' and parsed.ContainedObjects and #parsed.ContainedObjects > 0 then
            directDeck = parsed
        elseif parsed and parsed.Name == 'Card' and parsed.CardID and parsed.CustomDeck then
            cardObjects[#cardObjects + 1] = parsed
        else
            if line and line ~= '' then
                fallbackSpawnLines[#fallbackSpawnLines + 1] = line
            end
        end
    end

    if #issues == 1 then
        printToAll(tostring(issues[1]), Color.Orange)
    elseif #issues > 1 then
        printToAll('Spawn warnings: ' .. tostring(#issues) .. ' cards were skipped.', Color.Orange)
    end

    if directDeck then
        local selfRot = self.getRotation()
        if not directDeck.Transform then
            directDeck.Transform = {}
        end
        directDeck.Transform.posX = spawnPos and spawnPos.x or directDeck.Transform.posX or 0
        directDeck.Transform.posY = spawnPos and spawnPos.y or directDeck.Transform.posY or 2
        directDeck.Transform.posZ = spawnPos and spawnPos.z or directDeck.Transform.posZ or 0
        directDeck.Transform.rotX = selfRot.x
        directDeck.Transform.rotY = selfRot.y
        directDeck.Transform.rotZ = 180
        directDeck.Transform.scaleX = directDeck.Transform.scaleX or 1
        directDeck.Transform.scaleY = directDeck.Transform.scaleY or 1
        directDeck.Transform.scaleZ = directDeck.Transform.scaleZ or 1

        spawnObjectData({
            data = directDeck,
            position = { directDeck.Transform.posX, directDeck.Transform.posY, directDeck.Transform.posZ },
            rotation = { directDeck.Transform.rotX, directDeck.Transform.rotY, directDeck.Transform.rotZ }
        })
        cardsSpawned = #(directDeck.ContainedObjects or {})
        updateSpawningIndicator()
        if onDone then
            onDone(cardsSpawned)
        end
        return
    end

    local compactDeck = buildDeckFromTTSObjects(cardObjects, spawnPos)
    if compactDeck then
        spawnObjectData({
            data = compactDeck,
            position = { compactDeck.Transform.posX, compactDeck.Transform.posY, compactDeck.Transform.posZ },
            rotation = { compactDeck.Transform.rotX, compactDeck.Transform.rotY, compactDeck.Transform.rotZ }
        })
        cardsSpawned = #cardObjects
        updateSpawningIndicator()
        if onDone then
            onDone(#cardObjects)
        end
        return
    end

    if #cardObjects == 1 and #fallbackSpawnLines == 0 then
        local selfRot = self.getRotation()
        spawnObjectData({
            data = cardObjects[1],
            position = { spawnPos.x, spawnPos.y, spawnPos.z },
            rotation = { selfRot.x, selfRot.y, 180 }
        })
        cardsSpawned = 1
        updateSpawningIndicator()
        if onDone then
            onDone(1)
        end
        return
    end

    local index = 1
    local total = #fallbackSpawnLines
    local totalSpawnLines = #fallbackSpawnLines
    local adaptiveBatch = 4
    if totalSpawnLines >= 40 then
        adaptiveBatch = 8
    end
    if totalSpawnLines >= 80 then
        adaptiveBatch = 12
    end
    if totalSpawnLines >= 140 then
        adaptiveBatch = 16
    end
    local batch = batchSize or adaptiveBatch
    local indicatorUpdateStep = math.max(8, math.floor(totalSpawnLines / 10))

    local function processBatch()
        if not scriptActive then
            return
        end

        local processed = 0
        while index <= total and processed < batch do
            spawnObjectJSON({ json = fallbackSpawnLines[index] })
            cardsSpawned = cardsSpawned + 1
            if cardsSpawned == totalCardsToSpawn or (cardsSpawned % indicatorUpdateStep) == 0 then
                updateSpawningIndicator()
            end
            index = index + 1
            processed = processed + 1
        end

        if index <= total then
            Wait.frames(processBatch, 1)
        elseif onDone then
            onDone(total)
        end
    end

    processBatch()
end

-- START TOKEN random spawning is intentionally routed only through /random/build.
local function getCommanderEnforcementSetting(defaultValue)
    local enforceCommander = defaultValue
    if enforceCommander == nil then
        enforceCommander = true
    end

    if Global and Global.getVar then
        local globalSetting = Global.getVar('MTG_ENFORCE_COMMANDER_FORMAT')
        if globalSetting ~= nil then
            enforceCommander = globalSetting ~= false
        end
    end

    return enforceCommander
end

local function spawnRandomDeckViaBackend(query, count, spawnPos, onComplete, onFallback, enforceCommanderOverride)
    local enforceCommander = getCommanderEnforcementSetting(enforceCommanderOverride)

    local rot = self.getRotation()
    local payload = {
        q = query,
        count = count,
        enforceCommander = enforceCommander,
        back = backURL,
        hand = {
            position = { x = spawnPos.x, y = spawnPos.y, z = spawnPos.z },
            rotation = { x = rot.x, y = rot.y, z = rot.z }
        }
    }

    postNDJSON(BACKEND_URL .. '/random/build', payload, function(resp)
        handleNDJSONBuildResponse(resp, spawnPos, onComplete, function()
            if onFallback then
                onFallback()
                return
            end
            endSpawning()
            if onComplete then onComplete(false) end
        end, 'Fast random/build path failed')
    end)
end

local function spawnSingleRandomCardViaBackend(query, spawnPos, onComplete, onFallback, enforceCommanderOverride)
    local enforceCommander = getCommanderEnforcementSetting(enforceCommanderOverride)
    local encodedQuery = URLencode(query or '')
    local url = BACKEND_URL .. '/random?compact=spawn&q=' .. encodedQuery .. '&enforceCommander=' .. tostring(enforceCommander)

    WebRequest.get(url, function(resp)
        if not resp.is_done then
            return
        end

        if resp.is_error or (resp.response_code and resp.response_code >= 400) or not resp.text or resp.text == '' then
            local details = resp.error or ('HTTP ' .. tostring(resp.response_code or 'unknown'))
            if resp.text and resp.text ~= '' then
                details = details .. ' | ' .. tostring(resp.text)
            end
            print('Single random card request failed: ' .. tostring(details))
            if onFallback then
                onFallback(resp)
                return
            end
            endSpawning()
            if onComplete then onComplete(false) end
            return
        end

        local ok, parsed = pcall(function()
            return JSON.decode(resp.text)
        end)

        if not ok or not parsed then
            print('Single random card response was not valid JSON')
            if onFallback then
                onFallback(resp)
                return
            end
            endSpawning()
            if onComplete then onComplete(false) end
            return
        end

        if parsed.object == 'error' then
            print('Single random card request returned error: ' .. tostring(parsed.details or parsed.error or 'unknown'))
            if onFallback then
                onFallback(resp)
                return
            end
            endSpawning()
            if onComplete then onComplete(false) end
            return
        end

        spawnSingleCardFromData(parsed, { spawnPos.x, spawnPos.y, spawnPos.z }, 1)
        if onComplete then onComplete(true) end
    end)
end

function spawnRandomCards100()
    -- Spawn 100 cards, then replace this button with a small "1" button
    if isSpawning then
        printToAll("Cards are still spawning! Please wait...", Color.Red)
        return
    end
    
    isSpawning = true
    totalCardsToSpawn = RANDOM_CARD_SPAWN_COUNT
    cardsSpawned = 0
    
    local spawnPos = getSpawnAnchor()
    createSpawningIndicator(spawnPos)
    
    local id = ""
    local selectedColorCount = 0
    if White then id = id .. "W" end
    if White then selectedColorCount = selectedColorCount + 1 end
    if Blue  then id = id .. "U" end
    if Blue then selectedColorCount = selectedColorCount + 1 end
    if Black then id = id .. "B" end
    if Black then selectedColorCount = selectedColorCount + 1 end
    if Red   then id = id .. "R" end
    if Red then selectedColorCount = selectedColorCount + 1 end
    if Green then id = id .. "G" end
    if Green then selectedColorCount = selectedColorCount + 1 end
    if id == "" then id = "C" end
    local baseQuery = "id:" .. id

    local function spawnRandomWithQuery(query, countToSpawn)
        if countToSpawn <= 1 then
            spawnSingleRandomCardViaBackend(query, spawnPos, function()
                -- After 100 cards spawn, replace "Spawn 100" button with small "1" button
                replaceSpawn100WithButton1()
            end, function()
                print('Single random spawn failed via /random?compact=spawn')
                endSpawning()
            end, false)
            return
        end

        spawnRandomDeckViaBackend(query, countToSpawn, spawnPos, function()
            -- After 100 cards spawn, replace "Spawn 100" button with small "1" button
            replaceSpawn100WithButton1()
        end, function()
            print('Random spawn failed via /random/build')
            endSpawning()
        end, false)
    end

    if selectedColorCount == 0 or selectedColorCount == 5 then
        spawnRandomWithQuery(baseQuery, RANDOM_CARD_SPAWN_COUNT)
    else
        spawnRandomWithQuery(baseQuery, RANDOM_CARD_SPAWN_COUNT)
    end
end

function replaceSpawn100WithButton1()
    -- Remove the "Spawn 100" button and create small "1" button
    local spawn100Index = getButtonIndex("spawnRandomCards100")
    if spawn100Index ~= nil then
        self.removeButton(spawn100Index)
    end
    self.createButton({
        click_function = "spawnSingleCard",
        function_owner = self,
        label = "Spawn 1",
        position = {4.2, 0, -0.4},
        rotation = {0, 0, 0},
        scale = {1, 1, 1},
        width = 2600,
        height = 325,
        font_size = 175,
        color = Color.Grey
    })
end

function spawnSingleCard()
    spawnRandomCardsByNumber(1)
end

function buildDeckFromList(list, nickname, description, idOffset)
    local deckDat = {
        Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0, scaleX = 1, scaleY = 1, scaleZ = 1 },
        Name = "Deck",
        Nickname = nickname,
        Description = description,
        DeckIDs = {},
        CustomDeck = {},
        ContainedObjects = {}
    }

    for i, cardData in ipairs(list) do
        local deckId = idOffset + i
        local cardDat = getCardDatFromJSON(cardData, deckId)
        if cardDat then
            deckDat.DeckIDs[i] = cardDat.CardID
            deckDat.CustomDeck[deckId] = cardDat.CustomDeck[deckId]
            deckDat.ContainedObjects[i] = cardDat

            cardsSpawned = cardsSpawned + 1
            updateSpawningIndicator()
        else
            print("Error processing card data for card " .. tostring(i))
        end
    end

    return deckDat
end

function buildDeckFromListAsync(list, nickname, description, idOffset, onComplete, batchSize)
    local deckDat = {
        Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0, scaleX = 1, scaleY = 1, scaleZ = 1 },
        Name = "Deck",
        Nickname = nickname,
        Description = description,
        DeckIDs = {},
        CustomDeck = {},
        ContainedObjects = {}
    }

    local index = 1
    local total = #list
    local batch = batchSize or 8
    local indicatorUpdateStep = 4

    local function processBatch()
        if not scriptActive then return end

        local processed = 0
        while index <= total and processed < batch do
            local cardData = list[index]
            local deckId = idOffset + index
            local cardDat = getCardDatFromJSON(cardData, deckId)
            if cardDat then
                deckDat.DeckIDs[index] = cardDat.CardID
                deckDat.CustomDeck[deckId] = cardDat.CustomDeck[deckId]
                deckDat.ContainedObjects[index] = cardDat
                cardsSpawned = cardsSpawned + 1
                if cardsSpawned == total or (cardsSpawned % indicatorUpdateStep) == 0 then
                    updateSpawningIndicator()
                end
            else
                print("Error processing card data for card " .. tostring(index))
            end
            index = index + 1
            processed = processed + 1
        end

        if index <= total then
            Wait.frames(processBatch, 1)
        else
            if scriptActive then
                onComplete(deckDat)
            end
        end
    end

    processBatch()
end

function spawnSingleCardFromData(cardData, spawnPos, idOffset)
    local cardDat = getCardDatFromJSON(cardData, idOffset)
    if not cardDat then
        print("No valid card data to spawn")
        endSpawning()
        return
    end
    spawnObjectData({
        data = cardDat,
        position = spawnPos,
        rotation = self.getRotation()
    })
    Wait.time(function()
        endSpawning()
    end, 0.5)
end


---------------------------------------------------------------------------
-- spawnRandomCommanders spawns 5 random commander cards with a 1-second delay each.
-- All cards are spawned at the same position (startPos) to form a pile.
---------------------------------------------------------------------------
function spawnRandomCommanders()
    spawnRandomCommandersWO(false)
end

function spawnRandomCommandersWO(shouldCreateButton)
    if type(shouldCreateButton) ~= "boolean" then
        shouldCreateButton = false
    end
    if isSpawning then
        printToAll("Cards are still spawning! Please wait...", Color.Red)
        return
    end

    local commanderCount = commanderSpawnCount
    local spawnPos = getSpawnAnchor()

    isSpawning = true
    totalCardsToSpawn = commanderCount
    cardsSpawned = 0
    createSpawningIndicator(spawnPos)

    -- Build query based on commander color filters and current mode.
    local query = "is:commander game:paper"
    if CommanderLockoutMode then
        -- Lockout Mode: exclude selected colors from results
        if CommanderWhite then query = query .. " -c:w" end
        if CommanderBlue  then query = query .. " -c:u" end
        if CommanderBlack then query = query .. " -c:b" end
        if CommanderRed   then query = query .. " -c:r" end
        if CommanderGreen then query = query .. " -c:g" end
    else
        -- Color Combo Mode: match exact color identity
        local id = ""
        if CommanderWhite then id = id .. "w" end
        if CommanderBlue  then id = id .. "u" end
        if CommanderBlack then id = id .. "b" end
        if CommanderRed   then id = id .. "r" end
        if CommanderGreen then id = id .. "g" end
        if CommanderColorless then id = id .. "c" end
        if id ~= "" then
            query = query .. " id=" .. id
        end
    end

    if commanderCount <= 1 then
        spawnSingleRandomCardViaBackend(query, spawnPos, function()
            if shouldCreateButton then
                createSpawnButton()
            end
        end, function()
            print('Single commander spawn failed via /random?compact=spawn')
            endSpawning()
            if shouldCreateButton then
                createSpawnButton()
            end
        end)
        return
    end

    spawnRandomDeckViaBackend(query, commanderCount, spawnPos, function()
        if shouldCreateButton then
            createSpawnButton()
        end
    end, function()
        print('Random commander spawn failed via /random/build')
        endSpawning()
        if shouldCreateButton then
            createSpawnButton()
        end
    end)
end

local function getCommanderCountLabel()
    return tostring(commanderSpawnCount)
end

local function updateCommanderCountButton()
    local idx = getButtonIndex("commanderCountDisplay")
    if idx ~= nil then
        self.editButton({ index = idx, label = getCommanderCountLabel() })
    end
end

function commanderCountDisplay()
    -- Intentionally empty: this is a label-like button for display only.
end

function commanderCountMinus()
    commanderSpawnCount = math.max(COMMANDER_SPAWN_MIN, commanderSpawnCount - 1)
    updateCommanderCountButton()
end

function commanderCountPlus()
    commanderSpawnCount = math.min(COMMANDER_SPAWN_MAX, commanderSpawnCount + 1)
    updateCommanderCountButton()
end

function createSpawnButton()
    -- Clear all buttons and recreate them fresh
    self.clearButtons()

    self.createButton({
        label="Spawn Commanders",
        click_function="spawnRandomCommandersWO",
        function_owner=self,
        position={.9, 0, -1.9},
        rotation={0, 0, 0},
        width=1275,
        height=200,
        font_size=125
    })

    self.createButton({
        click_function = "destroySelf",
        function_owner = self,
        label          = "X",
        position       = {8.1, 0, -1.9},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 200,
        height         = 200,
        font_size      = 150,
        color          = Color.Red

    })
    -- Color toggle buttons.
    self.createButton({
        click_function = "tB",
        function_owner = self,
        label          = "B",
        position       = {8, 0, -1.4},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 300,
        height         = 200,
        font_size      = 150,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tW",
        function_owner = self,
        label          = "W",
        position       = {7.3, 0, -1.4},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 300,
        height         = 200,
        font_size      = 150,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tU",
        function_owner = self,
        label          = "U",
        position       = {6.6, 0, -1.4},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 300,
        height         = 200,
        font_size      = 150,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tG",
        function_owner = self,
        label          = "G",
        position       = {5.9, 0, -1.4},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 300,
        height         = 200,
        font_size      = 150,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tR",
        function_owner = self,
        label          = "R",
        position       = {5.2, 0, -1.4},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 300,
        height         = 200,
        font_size      = 150,
        color          = Color.Grey
    })
    -- Single random card-count button for the variant: always spawn 100 cards.
    -- After spawn, this will be replaced by a small "1" button via replaceSpawn100WithButton1()
    self.createButton({
        click_function = "spawnRandomCards100",
        function_owner = self,
        label = "Spawn 100",
        position = {4.2, 0, -0.4},
        rotation = {0, 0, 0},
        scale = {1, 1, 1},
        width = 2600,
        height = 325,
        font_size = 175,
        color = Color.Grey
    })

    -- Commander count controls for Spawn Commanders.
    self.createButton({
        click_function = "commanderCountMinus",
        function_owner = self,
        label          = "-",
        position       = {2.45, 0, -1.9},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 180,
        height         = 180,
        font_size      = 140,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "commanderCountDisplay",
        function_owner = self,
        label          = getCommanderCountLabel(),
        position       = {2.8, 0, -1.9},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 220,
        height         = 180,
        font_size      = 120,
        color          = Color.Black
    })
    self.createButton({
        click_function = "commanderCountPlus",
        function_owner = self,
        label          = "+",
        position       = {3.15, 0, -1.9},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 180,
        height         = 180,
        font_size      = 140,
        color          = Color.Grey
    })
    
    -- Commander color toggles: positioned below Spawn Commanders button.
    self.createButton({
        click_function = "tCmdB",
        function_owner = self,
        label          = "B",
        position       = {1.775, 0, -2.3},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 150,
        height         = 100,
        font_size      = 75,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tCmdW",
        function_owner = self,
        label          = "W",
        position       = {1.425, 0, -2.3},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 150,
        height         = 100,
        font_size      = 75,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tCmdU",
        function_owner = self,
        label          = "U",
        position       = {1.075, 0, -2.3},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 150,
        height         = 100,
        font_size      = 75,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tCmdG",
        function_owner = self,
        label          = "G",
        position       = {0.725, 0, -2.3},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 150,
        height         = 100,
        font_size      = 75,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tCmdR",
        function_owner = self,
        label          = "R",
        position       = {0.375, 0, -2.3},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 150,
        height         = 100,
        font_size      = 75,
        color          = Color.Grey
    })
    self.createButton({
        click_function = "tCmdC",
        function_owner = self,
        label          = "C",
        position       = {0.025, 0, -2.3},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 150,
        height         = 100,
        font_size      = 75,
        color          = Color.Grey
    })
    -- Commander filter mode toggle: switches between Color Combo and Lockout mode.
    -- Resets all color selections on switch to prevent invalid state.
    self.createButton({
        click_function = "toggleCommanderMode",
        function_owner = self,
        label          = "Mode:\nCombo",
        position       = {2.45, 0, -2.3},
        rotation       = {0, 0, 0},
        scale          = {1, 1, 1},
        width          = 400,
        height         = 200,
        font_size      = 60,
        color          = Color.Grey
    })
end


   
------------------------------------------------------------------------------------------

---------------------------------------------------------------------------
-- getCardDatFromJSON converts Scryfall JSON into a TTS card data table.
-- Includes error checking for missing fields and Scryfall error objects.
---------------------------------------------------------------------------
function getCardDatFromJSON(json, n)
    local c = type(json) == "table" and json or JSONdecode(json)
    if not c then
        print("Error: JSON decode returned nil for json: " .. tostring(json))
        return nil
    end
    if c.object == "error" then
        print("Error from Scryfall: " .. (c.details or "unknown error"))
        return nil
    end
    if not (c.name or (c.card_faces and c.card_faces[1] and c.card_faces[1].name)) then
        print("Error: Card data missing name field. JSON: " .. json)
        return nil
    end
    local cardName = ""
    c.face = ''
    c.oracle = ''
    local qual = 'large'
    local imagesuffix = ''
    if c.image_status ~= 'highres_scan' then
        imagesuffix = '?' .. tostring(os.date("%x")):gsub('/', '')
    end
    if c.card_faces and c.image_uris then
        for i, f in ipairs(c.card_faces) do
            if c.cmc then
                f.name = f.name:gsub('"', '') .. "\n" .. f.type_line .. ' ' .. c.cmc .. 'CMC'
            else
                f.name = f.name:gsub('"', '') .. "\n" .. f.type_line .. ' ' .. f.cmc .. 'CMC'
            end
            if i == 1 then
                cardName = f.name
            end
            c.oracle = c.oracle .. f.name .. "\n" .. setOracle(f) .. (i == #c.card_faces and "" or "\n")
        end
    elseif c.card_faces then
        local f = c.card_faces[1]
        if c.cmc then
            cardName = f.name:gsub('"', '') .. "\n" .. f.type_line .. ' ' .. c.cmc .. 'CMC DFC'
        else
            cardName = f.name:gsub('"', '') .. "\n" .. f.type_line .. ' ' .. f.cmc .. 'CMC DFC'
        end
        c.oracle = setOracle(f)
    else
        cardName = c.name:gsub('"', '') .. "\n" .. c.type_line .. ' ' .. c.cmc .. 'CMC'
        c.oracle = setOracle(c)
    end
    local backDat = nil
    if c.card_faces and not c.image_uris then
        local faceAddress = c.card_faces[1].image_uris.normal:gsub('%?.*', ''):gsub('normal', qual) .. imagesuffix
        local backAddress = c.card_faces[2].image_uris.normal:gsub('%?.*', ''):gsub('normal', qual) .. imagesuffix
        if faceAddress:find('/back/') and backAddress:find('/front/') then
            local temp = faceAddress; faceAddress = backAddress; backAddress = temp
        end
        c.face = faceAddress
        local f = c.card_faces[2]
        local name
        if c.cmc then
            name = f.name:gsub('"', '') .. "\n" .. f.type_line .. "\nCMC: " .. c.cmc .. " DFC"
        else
            name = f.name:gsub('"', '') .. "\n" .. f.type_line .. "\nCMC: " .. f.cmc .. " DFC"
        end
        local oracle = setOracle(f)
        local b = n + 100
        backDat = {
            Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0, scaleX = 1, scaleY = 1, scaleZ = 1 },
            Name = "Card",
            Nickname = name,
            Description = oracle,
            Memo = c.oracle_id,
            CardID = b * 100,
            CustomDeck = { [b] = { FaceURL = backAddress, BackURL = backURL, NumWidth = 1, NumHeight = 1, Type = 0, BackIsHidden = true, UniqueBack = false } },
        }
    elseif c.image_uris then
        c.face = c.image_uris.normal:gsub('%?.*', ''):gsub('normal', qual) .. imagesuffix
        if cardName:lower():match('geralf') then
            c.face = c.image_uris.normal:gsub('%?.*', ''):gsub('normal', 'png'):gsub('jpg', 'png') .. imagesuffix
        end
    end
    local cardDat = {
        Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0, scaleX = 1, scaleY = 1, scaleZ = 1 },
        Name = "Card",
        Nickname = cardName,
        Description = c.oracle,
        Memo = c.oracle_id,
        CardID = n * 100,
        CustomDeck = { [n] = { FaceURL = c.face, BackURL = backURL, NumWidth = 1, NumHeight = 1, Type = 0, BackIsHidden = true, UniqueBack = false } },
    }
    if backDat then
        cardDat.States = { [2] = backDat }
    end
    return cardDat
end

---------------------------------------------------------------------------
-- setOracle appends power/toughness or loyalty to the oracle text.
---------------------------------------------------------------------------
function setOracle(c)
    local n = "\n[b]"
    if c.power then
        n = n .. c.power .. '/' .. c.toughness
    elseif c.loyalty then
        n = n .. tostring(c.loyalty)
    else
        n = false
    end
    return (c.oracle_text or "") .. (n and n .. "[/b]" or "")
end

---------------------------------------------------------------------------
-- Simple JSONdecode wrapper.
---------------------------------------------------------------------------
function JSONdecode(txt)
    return JSON.decode(txt)
end

---------------------------------------------------------------------------
-- URLencode helper function.
---------------------------------------------------------------------------
function URLencode(str)
    if (str) then
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^%w ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = str:gsub(" ", "+")
    end
    return str    
end
-------------------------------------------------------------
---------------------------------------------------------------------------
-- Color toggle functions
---------------------------------------------------------------------------
function tB()
    Black = not Black
    local newColor = Black and Color.Black or Color.Grey
    setButtonToggleColor("tB", newColor)
    printToAll("Black is now " .. tostring(Black))
end

function tW()
    White = not White
    local newColor = White and Color.White or Color.Grey
    setButtonToggleColor("tW", newColor)
    printToAll("White is now " .. tostring(White))
end

function tU()
    Blue = not Blue
    local newColor = Blue and Color.Blue or Color.Grey
    setButtonToggleColor("tU", newColor)
    printToAll("Blue is now " .. tostring(Blue))
end

function tG()
    Green = not Green
    local newColor = Green and Color.Green or Color.Grey
    setButtonToggleColor("tG", newColor)
    printToAll("Green is now " .. tostring(Green))
end

function tR()
    Red = not Red
    local newColor = Red and Color.Red or Color.Grey
    setButtonToggleColor("tR", newColor)
    printToAll("Red is now " .. tostring(Red))
end

-- Commander color toggle helpers
---------------------------------------------------------------------------
local function getCommanderToggleColor(isActive, colorName)
    if not isActive then return Color.Grey end
    if CommanderLockoutMode then
        return Color.new(1, 0.5, 0)  -- orange = locked out
    end
    -- Combo mode: use the card color
    if colorName == "B" then return Color.Black end
    if colorName == "W" then return Color.White end
    if colorName == "U" then return Color.Blue end
    if colorName == "G" then return Color.Green end
    if colorName == "R" then return Color.Red end
    if colorName == "C" then return Color.Brown end
    return Color.Grey
end

local function updateAllCommanderColorButtons()
    setButtonToggleColor("tCmdB", getCommanderToggleColor(CommanderBlack, "B"))
    setButtonToggleColor("tCmdW", getCommanderToggleColor(CommanderWhite, "W"))
    setButtonToggleColor("tCmdU", getCommanderToggleColor(CommanderBlue, "U"))
    setButtonToggleColor("tCmdG", getCommanderToggleColor(CommanderGreen, "G"))
    setButtonToggleColor("tCmdR", getCommanderToggleColor(CommanderRed, "R"))
    setButtonToggleColor("tCmdC", getCommanderToggleColor(CommanderColorless, "C"))
end

-- Commander mode toggle
---------------------------------------------------------------------------
function toggleCommanderMode()
    CommanderLockoutMode = not CommanderLockoutMode
    -- Safety: reset all color selections when switching modes
    CommanderWhite    = false
    CommanderBlue     = false
    CommanderBlack    = false
    CommanderRed      = false
    CommanderGreen    = false
    CommanderColorless = false
    -- Update the mode button appearance
    local modeLabel = CommanderLockoutMode and "Mode:\nLockout" or "Mode:\nCombo"
    local modeColor = CommanderLockoutMode and Color.new(1, 0.5, 0) or Color.Grey
    local idx = getButtonIndex("toggleCommanderMode")
    if idx ~= nil then
        self.editButton({ index = idx, label = modeLabel, color = modeColor })
    end
    -- Refresh all color toggle buttons to reflect cleared state
    updateAllCommanderColorButtons()
    local modeName = CommanderLockoutMode and "Lockout" or "Color Combo"
    printToAll("Commander filter mode: " .. modeName, Color.White)
end

-- Commander color toggle functions
---------------------------------------------------------------------------
function tCmdB()
    CommanderBlack = not CommanderBlack
    setButtonToggleColor("tCmdB", getCommanderToggleColor(CommanderBlack, "B"))
    local suffix = CommanderLockoutMode and " locked out" or ""
    printToAll("Commander Black" .. suffix .. ": " .. tostring(CommanderBlack))
end

function tCmdW()
    CommanderWhite = not CommanderWhite
    setButtonToggleColor("tCmdW", getCommanderToggleColor(CommanderWhite, "W"))
    local suffix = CommanderLockoutMode and " locked out" or ""
    printToAll("Commander White" .. suffix .. ": " .. tostring(CommanderWhite))
end

function tCmdU()
    CommanderBlue = not CommanderBlue
    setButtonToggleColor("tCmdU", getCommanderToggleColor(CommanderBlue, "U"))
    local suffix = CommanderLockoutMode and " locked out" or ""
    printToAll("Commander Blue" .. suffix .. ": " .. tostring(CommanderBlue))
end

function tCmdG()
    CommanderGreen = not CommanderGreen
    setButtonToggleColor("tCmdG", getCommanderToggleColor(CommanderGreen, "G"))
    local suffix = CommanderLockoutMode and " locked out" or ""
    printToAll("Commander Green" .. suffix .. ": " .. tostring(CommanderGreen))
end

function tCmdR()
    CommanderRed = not CommanderRed
    setButtonToggleColor("tCmdR", getCommanderToggleColor(CommanderRed, "R"))
    local suffix = CommanderLockoutMode and " locked out" or ""
    printToAll("Commander Red" .. suffix .. ": " .. tostring(CommanderRed))
end

function tCmdC()
    if CommanderLockoutMode then
        printToAll("Colorless lockout is not supported. Switch to Combo mode.", Color.Orange)
        return
    end
    CommanderColorless = not CommanderColorless
    setButtonToggleColor("tCmdC", getCommanderToggleColor(CommanderColorless, "C"))
    printToAll("Commander Colorless: " .. tostring(CommanderColorless))
end

-- spawnRandomCards spawns 100 random cards (default) using the active color identity filters.
---------------------------------------------------------------------------
function spawnRandomCards()
    spawnRandomCardsByNumber(RANDOM_CARD_SPAWN_COUNT)
end

---------------------------------------------------------------------------
-- spawnRandomCardsByNumber spawns n random cards matching active color identity toggles.
-- Includes spawning indicator and prevents concurrent spawns.
---------------------------------------------------------------------------
function spawnRandomCardsByNumber(n)
    -- Safety check: prevent concurrent spawns
    if isSpawning then
        printToAll("Cards are still spawning! Please wait...", Color.Red)
        return
    end
    
    -- Set spawning state
    isSpawning = true
    totalCardsToSpawn = n
    cardsSpawned = 0
    
    local spawnPos = getSpawnAnchor()
    
    -- Create spawning indicator
    createSpawningIndicator(spawnPos)
    
    local id = ""
    local selectedColorCount = 0
    if White then id = id .. "W" end
    if White then selectedColorCount = selectedColorCount + 1 end
    if Blue  then id = id .. "U" end
    if Blue then selectedColorCount = selectedColorCount + 1 end
    if Black then id = id .. "B" end
    if Black then selectedColorCount = selectedColorCount + 1 end
    if Red   then id = id .. "R" end
    if Red then selectedColorCount = selectedColorCount + 1 end
    if Green then id = id .. "G" end
    if Green then selectedColorCount = selectedColorCount + 1 end
    if id == "" then id = "C" end
    local baseQuery = "id:" .. id

    local function spawnRandomWithQuery(query, countToSpawn)
        if countToSpawn <= 1 then
            spawnSingleRandomCardViaBackend(query, spawnPos, nil, function()
                print('Single random spawn failed via /random?compact=spawn')
                endSpawning()
            end, false)
            return
        end

        spawnRandomDeckViaBackend(query, countToSpawn, spawnPos, nil, function()
            print('Random spawn failed via /random/build')
            endSpawning()
        end, false)
    end

    spawnRandomWithQuery(baseQuery, n)
end
function destroySelf()
    self.destroy()
end

function onDestroy()
    scriptActive = false
    endSpawning()
end
