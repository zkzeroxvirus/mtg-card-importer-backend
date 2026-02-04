-----------------------------------------------------------------------
-- Global variable for the card back image URL:
backURL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
-- Backend Configuration
BACKEND_URL = "https://mtg-card-importer-backend.onrender.com"

-- Relative anchor reused from Start Token
SPAWN_BUTTON_LOCAL = Vector{-4.2, 0, -3.9}
SPAWN_HEIGHT_OFFSET = 2

-- Anchor state
lastAnchorPos = nil
lastAnchorRot = nil
lastAnchorWorld = nil
--------------------------------------------------------------------------
function onLoad()

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




---------------------------------------------------------------------------
-- spawnRandomCommanders spawns 5 random commander cards with a 1-second delay each.
-- All cards are spawned at the same position (startPos) to form a pile.
---------------------------------------------------------------------------
function spawnRandomCommanders()
    self.removeButton(0)  -- removes the button with index 0
    local commanderCount = 5
    local startPos = getSpawnAnchor()
    
    for i = 1, commanderCount do
        local delay = (i - 1) * 1.0
        Wait.time(function()
            fetchRandomCommander(startPos, i)
        end, delay)
    end

    -- Create button after all commanders have spawned
    Wait.time(function()
        createSpawnButton()
    end, commanderCount)  -- Waits 5 seconds (since last spawn is at 4s)
end
function spawnRandomCommandersWO()
    local commanderCount = 5
    local startPos = getSpawnAnchor()
    
    for i = 1, commanderCount do
        local delay = (i - 1) * 1.0
        Wait.time(function()
            fetchRandomCommander(startPos, i)
        end, delay)
    end

    -- Create button after all commanders have spawned
    Wait.time(function()
        createSpawnButton()
    end, commanderCount)  -- Waits 5 seconds (since last spawn is at 4s)
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
    for i = 1, 22 do
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
        _G["spawnRandomCards" .. i] = function()
            spawnRandomCardsByNumber(i)
        end
    end
end


   
------------------------------------------------------------------------------------------

function fetchRandomCommander(spawnPos, n)
    local query = "is:commander"
    local url = BACKEND_URL .. "/random?q=" .. URLencode(query)
    WebRequest.get(url, function(response)
        if response.is_error or not response.text then
            print("Error fetching commander from backend.")
            return
        end
        local cardDat = getCardDatFromJSON(response.text, n)
        if cardDat then
            spawnObjectData({ data = cardDat, position = spawnPos, rotation = self.getRotation() })
        else
            print("Error processing commander card data: " .. tostring(response.text))
        end
    end)
end

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

---------------------------------------------------------------------------
-- spawnRandomCards spawns 22 random cards (default) using the strict card identity query.
---------------------------------------------------------------------------
function spawnRandomCards()
    spawnRandomCardsByNumber(22)
end

---------------------------------------------------------------------------
-- spawnRandomCardsByNumber spawns n random cards from any set that match the active card identity.
-- It builds an OR query using the "id=" operator (for strictly mono-colored cards)
-- and adds a clause "colorless type:artifact" so that only colorless artifacts are included.
-- All cards are spawned as a single deck object for optimal performance (no lag).
---------------------------------------------------------------------------
function spawnRandomCardsByNumber(n)
    local spawnPos = getSpawnAnchor()
    local id = ""
    if White then id = id .. "W" end
    if Blue  then id = id .. "U" end
    if Black then id = id .. "B" end
    if Red   then id = id .. "R" end
    if Green then id = id .. "G" end
    if id == "" then id = "C" end
printToAll(id)
    local query = "id:" .. id
    local url = BACKEND_URL .. "/random?q=" .. URLencode(query) .. "&count=" .. tostring(n)

    WebRequest.get(url, function(response)
        if response.is_error or not response.text then
            print("Error fetching card from backend.")
            return
        end

        local decoded = JSONdecode(response.text)
        if not decoded then
            print("Error: Invalid JSON from backend")
            return
        end

        local list = nil
        if decoded.object == "list" and decoded.data and type(decoded.data) == "table" then
            list = decoded.data
        elseif decoded.object == "card" or decoded.name then
            list = { decoded }
        elseif type(decoded) == "table" and decoded[1] then
            list = decoded
        else
            print("Error: Invalid response format from backend")
            return
        end

        -- Build deck object (like MTG Importer does) for optimal performance
        local deckDat = {
            Transform = { posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0, scaleX = 1, scaleY = 1, scaleZ = 1 },
            Name = "Deck",
            Nickname = "Random Cards (" .. tostring(#list) .. ")",
            Description = "Random cards matching color identity: " .. id,
            DeckIDs = {},
            CustomDeck = {},
            ContainedObjects = {}
        }

        -- Process all cards and add to deck
        for i, cardData in ipairs(list) do
            local cardDat = getCardDatFromJSON(cardData, 1000 + i)
            if cardDat then
                -- Add card to deck
                deckDat.DeckIDs[i] = cardDat.CardID
                deckDat.CustomDeck[1000 + i] = cardDat.CustomDeck[1000 + i]
                deckDat.ContainedObjects[i] = cardDat
            else
                print("Error processing card data for card " .. tostring(i))
            end
        end

        -- Spawn entire deck at once for optimal performance
        if #deckDat.ContainedObjects > 0 then
            spawnObjectData({
                data = deckDat,
                position = spawnPos,
                rotation = self.getRotation()
            })
            printToAll("Spawned " .. #deckDat.ContainedObjects .. " random cards as a deck")
        else
            print("No valid cards to spawn")
        end
    end)
end
function destroySelf()
    self.destroy()
end
