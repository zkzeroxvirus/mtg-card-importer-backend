-----------------------------------------------------------------------
-- Global variable for the card back image URL:
backURL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
-- Backend Configuration
-- Local default: change port to 3001 if using docker-compose.local.yml
BACKEND_URL = "http://api.mtginfo.org"

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
NUMBER_BUTTON_COUNT = 22
scriptActive = true
--------------------------------------------------------------------------
function onLoad()
    scriptActive = true
    local item = self
    item.createButton({
        label = "Spawn Commanders",  -- Button text
        click_function = "spawnRandomCommanders",  -- Function to call when clicked
        function_owner = self,  -- The owner of this button
        position = {4.2, 0, -3.9},  -- Position of the button relative to the item (adjust as needed)
        rotation = {0, 0, 0},  -- Rotation (if necessary)
        width = 2000,  -- Width of the button (adjust based on item size)
        height = 450,  -- Height of the button (adjust based on item size)
        font_size = 225,  -- Font size for the button label
        scale = {1, 1, 1}  -- Scale of the button (optional)
    })
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

local function spawnNDJSONQueue(respText, onDone, batchSize)
    local lines = splitLines(respText)
    local spawnLines = {}

    for _, line in ipairs(lines) do
        local parsed = JSONdecode(line)
        if parsed and parsed.object == 'warning' then
            local warningText = parsed.warning or ((parsed.card_name or 'Card') .. ' was skipped')
            printToAll(tostring(warningText), Color.Orange)
        else
            table.insert(spawnLines, line)
        end
    end

    local index = 1
    local total = #spawnLines
    local batch = batchSize or 2
    local indicatorUpdateStep = 2

    local function processBatch()
        if not scriptActive then
            return
        end

        local processed = 0
        while index <= total and processed < batch do
            spawnObjectJSON({ json = spawnLines[index] })
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

local function spawnDecklistViaBuild(decklist, spawnPos, onComplete)
    local rot = self.getRotation()
    local payload = {
        -- Keep both keys for backward compatibility across backend versions.
        data = decklist,
        decklist = decklist,
        spawnMode = 'deck',
        back = backURL,
        hand = {
            position = { x = spawnPos.x, y = spawnPos.y, z = spawnPos.z },
            rotation = { x = rot.x, y = rot.y, z = rot.z }
        }
    }

    local function handleBuildResponse(resp, allowRetry)
        if not resp.is_done then
            return
        end

        if resp.is_error or (resp.response_code and resp.response_code >= 400) then
            local details = resp.error or ('HTTP ' .. tostring(resp.response_code or 'unknown'))
            if resp.text and resp.text ~= '' then
                details = details .. ' | ' .. tostring(resp.text)
            end

            if allowRetry and resp.text and resp.text:find('No valid cards in decklist', 1, true) then
                WebRequest.custom(
                    BACKEND_URL .. '/build',
                    'POST',
                    true,
                    decklist,
                    {
                        Accept = 'application/x-ndjson',
                        ['Content-Type'] = 'text/plain'
                    },
                    function(retryResp)
                        handleBuildResponse(retryResp, false)
                    end
                )
                return
            end

            print('Error building spawn objects from backend: ' .. tostring(details))
            endSpawning()
            if onComplete then onComplete(false) end
            return
        end

        if not resp.text or resp.text == '' then
            print('Backend returned an empty /build response.')
            endSpawning()
            if onComplete then onComplete(false) end
            return
        end

        spawnNDJSONQueue(resp.text, function(spawnedCount)
            if spawnedCount <= 0 then
                print('No valid cards to spawn')
            end
            Wait.time(function()
                endSpawning()
                if onComplete then onComplete(spawnedCount > 0) end
            end, 0.25)
        end, 2)
    end

    WebRequest.custom(
        BACKEND_URL .. '/build',
        'POST',
        true,
        JSON.encode(payload),
        {
            Accept = 'application/x-ndjson',
            ['Content-Type'] = 'application/json'
        },
        function(resp)
            handleBuildResponse(resp, true)
        end
    )
end

local function spawnRandomDeckViaBackend(query, count, spawnPos, onComplete, onFallback)
    local rot = self.getRotation()
    local payload = {
        q = query,
        count = count,
        back = backURL,
        hand = {
            position = { x = spawnPos.x, y = spawnPos.y, z = spawnPos.z },
            rotation = { x = rot.x, y = rot.y, z = rot.z }
        }
    }

    WebRequest.custom(
        BACKEND_URL .. '/random/build',
        'POST',
        true,
        JSON.encode(payload),
        {
            Accept = 'application/x-ndjson',
            ['Content-Type'] = 'application/json'
        },
        function(resp)
            if not resp.is_done then
                return
            end

            if resp.is_error or (resp.response_code and resp.response_code >= 400) or not resp.text or resp.text == '' then
                local details = resp.error or ('HTTP ' .. tostring(resp.response_code or 'unknown'))
                if resp.text and resp.text ~= '' then
                    details = details .. ' | ' .. tostring(resp.text)
                end
                print('Fast random/build path failed: ' .. tostring(details))
                if onFallback then
                    onFallback()
                    return
                end
                endSpawning()
                if onComplete then onComplete(false) end
                return
            end

            spawnNDJSONQueue(resp.text, function(spawnedCount)
                if spawnedCount <= 0 then
                    print('No valid cards to spawn')
                end
                Wait.time(function()
                    endSpawning()
                    if onComplete then onComplete(spawnedCount > 0) end
                end, 0.25)
            end, 2)
        end
    )
end

local function fetchRandomCardsViaBackend(query, count, onComplete, onFallback)
    local requestUrl = BACKEND_URL .. '/random?count=' .. tostring(count) .. '&q=' .. URLencode(query)

    WebRequest.get(requestUrl, function(resp)
        if not resp.is_done then
            return
        end

        if resp.is_error or (resp.response_code and resp.response_code >= 400) or not resp.text or resp.text == '' then
            local details = resp.error or ('HTTP ' .. tostring(resp.response_code or 'unknown'))
            if resp.text and resp.text ~= '' then
                details = details .. ' | ' .. tostring(resp.text)
            end
            print('Random fetch failed via /random: ' .. tostring(details))
            if onFallback then onFallback() end
            return
        end

        local parsed = JSONdecode(resp.text)
        if not parsed then
            print('Random fetch failed: invalid JSON response from /random')
            if onFallback then onFallback() end
            return
        end

        if parsed.object == 'error' then
            print('Random fetch failed: ' .. tostring(parsed.details or 'unknown error'))
            if onFallback then onFallback() end
            return
        end

        local cards = {}
        if parsed.object == 'list' and parsed.data then
            cards = parsed.data
        else
            cards = { parsed }
        end

        if onComplete then onComplete(cards) end
    end)
end

local function spawnSingleDeckFromCards(cardList, spawnPos)
    if not cardList or #cardList == 0 then
        print('No valid cards to spawn')
        endSpawning()
        return
    end

    buildDeckFromListAsync(cardList, 'Deck', '', 1, function(deckDat)
        spawnObjectData({
            data = deckDat,
            position = spawnPos,
            rotation = self.getRotation()
        })
        Wait.time(function()
            endSpawning()
        end, 0.25)
    end, 8)
end

local function makeSpawnRandomCardsHandler(count)
    return function()
        spawnRandomCardsByNumber(count)
    end
end

for i = 1, NUMBER_BUTTON_COUNT do
    _G["spawnRandomCards" .. i] = makeSpawnRandomCardsHandler(i)
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
    self.removeButton(0)  -- removes the button with index 0
    spawnRandomCommandersWO(true)
end

function spawnRandomCommandersWO(shouldCreateButton)
    if shouldCreateButton == nil then
        shouldCreateButton = true
    end
    if isSpawning then
        printToAll("Cards are still spawning! Please wait...", Color.Red)
        return
    end

    local commanderCount = 5
    local spawnPos = getSpawnAnchor()

    isSpawning = true
    totalCardsToSpawn = commanderCount
    cardsSpawned = 0
    createSpawningIndicator(spawnPos)

    local query = "is:commander game:paper"

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
function createSpawnButton()
    -- Clear any existing buttons to avoid duplicates after mulligans
    self.clearButtons()

    self.createButton({
        label="Mulligan/50 Essence",
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
    -- Create 22 numbered buttons arranged in two rows under the Random Cards button.
    local buttonWidth = 325   -- button width in pixels
    local buttonHeight = 325  -- button height in pixels
    local numPerRow = 11      -- two rows of 11 buttons each
    local startX = 1.65      -- adjust to center the row (for 11 buttons)
    local startZ = -0.1        -- first row directly under Random Cards button
    local spacingX = 0.65      -- horizontal spacing so buttons are touching
    local spacingZ = -0.65     -- vertical spacing for second row
    for i = 1, NUMBER_BUTTON_COUNT do
        local row = math.floor((i - 1) / numPerRow)
        local col = (i - 1) % numPerRow
        local posX = startX + col * spacingX
        local posZ = startZ + row * spacingZ
        self.createButton({
            click_function = "spawnRandomCards" .. i,
            function_owner = self,
            label = tostring(i),
            position = { posX, 0, posZ },
            rotation = {0, 0, 0},
            scale = {1, 1, 1},
            width = buttonWidth,
            height = buttonHeight,
            font_size = 150,
            color = Color.Grey
        })
    end
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
    self.editButton({ index = 2, color = newColor })
    printToAll("Black is now " .. tostring(Black))
end

function tW()
    White = not White
    local newColor = White and Color.White or Color.Grey
    self.editButton({ index = 3, color = newColor })
    printToAll("White is now " .. tostring(White))
end

function tU()
    Blue = not Blue
    local newColor = Blue and Color.Blue or Color.Grey
    self.editButton({ index = 4, color = newColor })
    printToAll("Blue is now " .. tostring(Blue))
end

function tG()
    Green = not Green
    local newColor = Green and Color.Green or Color.Grey
    self.editButton({ index = 5, color = newColor })
    printToAll("Green is now " .. tostring(Green))
end

function tR()
    Red = not Red
    local newColor = Red and Color.Red or Color.Grey
    self.editButton({ index = 6, color = newColor })
    printToAll("Red is now " .. tostring(Red))
end

-- spawnRandomCards spawns 22 random cards (default) using the active color identity filters.
---------------------------------------------------------------------------
function spawnRandomCards()
    spawnRandomCardsByNumber(22)
end

---------------------------------------------------------------------------
-- spawnRandomCardsByNumber spawns n random cards matching active color identity toggles.
-- When 2+ colors are selected, it guarantees at least one multicolored card,
-- then fills the remainder with the base identity query, and spawns as one deck.
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
        spawnRandomDeckViaBackend(query, countToSpawn, spawnPos, nil, function()
            print('Random spawn failed via /random/build')
            endSpawning()
        end)
    end

    if selectedColorCount > 1 and n > 0 then
        local multicolorQuery = baseQuery .. " c:m"

        fetchRandomCardsViaBackend(multicolorQuery, 1, function(multicolorCards)
            if not multicolorCards or #multicolorCards == 0 then
                spawnRandomWithQuery(baseQuery, n)
                return
            end

            local combinedCards = { multicolorCards[1] }
            local remainingCount = n - 1

            if remainingCount <= 0 then
                spawnSingleDeckFromCards(combinedCards, spawnPos)
                return
            end

            fetchRandomCardsViaBackend(baseQuery, remainingCount, function(baseCards)
                for _, card in ipairs(baseCards or {}) do
                    table.insert(combinedCards, card)
                end

                if #combinedCards < n then
                    print('Random fetch returned fewer cards than requested; expected ' .. tostring(n) .. ', got ' .. tostring(#combinedCards))
                end

                spawnSingleDeckFromCards(combinedCards, spawnPos)
            end, function()
                spawnRandomWithQuery(baseQuery, n)
            end)
        end, function()
            spawnRandomWithQuery(baseQuery, n)
        end)
        return
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
