-----------------------------------------------------------------------
-- Global variable for the card back image URL:
backURL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
-- Backend URL for random card generation
BACKEND_URL = "http://api.mtginfo.org"
--------------------------------------------------------------------------
Type = ""
Oracle = ""
Color = ""
Id = ""
ManaCost = ""
Power = ""
Toughness = ""
OTag = ""
IS = ""
NumberOfCards = 0
typeToggle = ":"
otagToggle = ":"
oracleToggle = ":"
colorToggle = ":"
idToggle = ":"
manaCostToggle = ":"
isToggle = ":"
layoutData = {row=5, col=6}
layoutButtonIndex = 8
layoutButtonVisible = false
layoutDeckDetected = false
layoutButtonNeedsRefresh = true
layoutButtonWatcherRunning = false
layoutInProgress = false

function onLoad()

    local item = self

    item.createButton({
        label = "Spawn Cards",  -- Button text
        click_function = "spawnRandomCommanders",  -- Function to call when clicked
        function_owner = self,  -- The owner of this button
        position = {0, 0.1, 1.4},  -- Position of the button relative to the item (adjust as needed)
        rotation = {0, 0, 0},  -- Rotation (if necessary)
        width = 600,  -- Width of the button (adjust based on item size)
        height = 140,  -- Height of the button (adjust based on item size)
        font_size = 72,  -- Font size for the button label
        scale = {1, 1, 1}  -- Scale of the button (optional)
    })
    self.createInput({
        input_function = "type_func",
        function_owner = self,
        label          = "Type",
        alignment      = 1,
        position       = {x=-1, y=0.1, z=-1},
        width          = 950,
        height         = 250,
        font_size      = 100,
        validation     = 1,
    })
    self.createInput({
        input_function = "oracle_func",
        function_owner = self,
        label          = "OracleText",
        alignment      = 1,
        position       = {x=-1, y=0.1, z=-0.5},
        width          = 950,
        height         = 250,
        font_size      = 100,
        validation     = 1,
    })
  self.createInput({
        input_function = "id_func",
        function_owner = self,
        label          = "id",
        alignment      = 1,
        position       = {x=-1, y=0.1, z=0},
        width          = 950,
        height         = 250,
        font_size      = 100,
        validation     = 1,
    })
  self.createInput({
        input_function = "manaCost_func",
        function_owner = self,
        label          = "CMC",
        alignment      = 1,
        position       = {x=-1, y=0.1, z=0.5},
        width          = 950,
        height         = 250,
        font_size      = 100,
        validation     = 1,
    })
 self.createInput({
        input_function = "color_func",
        function_owner = self,
        label          = "Color",
        alignment      = 1,
        position       = {x=-1, y=0.1, z=1},
        width          = 950,
        height         = 250,
        font_size      = 100,
        validation     = 1,
    })

 self.createInput({
        input_function = "otag_func",
        function_owner = self,
        label          = "Otag",
        alignment      = 1,
        position       = {x=1, y=0.1, z=-1},
        width          = 950,
        height         = 250,
        font_size      = 100,
        validation     = 1,
    })

 self.createInput({
        input_function = "is_func",
        function_owner = self,
        label          = "Is",
        alignment      = 1,
        position       = {x=1, y=0.1, z=-0.5},
        width          = 950,
        height         = 250,
        font_size      = 100,
        validation     = 1,
    })


 self.createInput({
        input_function = "number_func",
        function_owner = self,
        label          = "Number",
        alignment      = 1,
        position       = {x=-1, y=0.1, z=1.4},
        width          = 400,
        height         = 125,
        font_size      = 100,
        validation     = 2,
    })




 self.createButton({
      label=typeToggle,
      click_function="type_toggle",
      function_owner = self,
      label          = ":",
      position={-2.3,0.1,-1},
      scale={1,1,1},
      color={0.1,0.1,0.1},
      font_color={1,1,1},
      height=250,
      width=250,
      alignment = 5,
    })
self.createButton({
      label=oracleToggle,
      click_function="oracle_toggle",
      function_owner = self,
      label          = ":",
      position={-2.3,0.1,-0.5},
      scale={1,1,1},
      color={0.1,0.1,0.1},
      font_color={1,1,1},
      height=250,
      width=250,
      alignment = 5,
    })
    self.createButton({
      label=idToggle,
      click_function="id_toggle",
      function_owner = self,
      label          = ":",
      position={-2.3,0.1,0},
      scale={1,1,1},
      color={0.1,0.1,0.1},
      font_color={1,1,1},
      height=250,
      width=250,
      alignment = 5,
    })
    self.createButton({
      label=manaCostToggle,
      click_function="manaCost_toggle",
      function_owner = self,
      label          = ":",
      position={-2.3,0.1,0.5},
      scale={1,1,1},
      color={0.1,0.1,0.1},
      font_color={1,1,1},
      height=250,
      width=250,
      alignment = 5,
    })
    self.createButton({
      label=colorToggle,
      click_function="color_toggle",
      function_owner = self,
      label          = ":",
      position={-2.3,0.1,1},
      scale={1,1,1},
      color={0.1,0.1,0.1},
      font_color={1,1,1},
      height=250,
      width=250,
      alignment = 5,
    })

    self.createButton({
      label=otagToggle,
      click_function="otag_toggle",
      function_owner = self,
      label          = ":",
      position={2.3,0.1,-1},
      scale={1,1,1},
      color={0.1,0.1,0.1},
      font_color={1,1,1},
      height=250,
      width=250,
      alignment = 5,
    })

    self.createButton({
      label=isToggle,
      click_function="is_toggle",
      function_owner = self,
      label          = ":",
      position={2.3,0.1,-0.5},
      scale={1,1,1},
      color={0.1,0.1,0.1},
      font_color={1,1,1},
      height=250,
      width=250,
      alignment = 5,
    })

    createInputs()
    createClickButtons()
    ensureLayoutButtonWatcher()


end


function type_toggle()
    if typeToggle == ":" then
        typeToggle = "="
    else
        typeToggle = ":"
    end
    self.editButton({
        index = 1,
        label = typeToggle
    })
end

function oracle_toggle()
    if oracleToggle == ":" then
        oracleToggle = "="
    else
        oracleToggle = ":"
    end
    self.editButton({
        index = 2,
        label= oracleToggle
    })
end

function id_toggle()
    if idToggle == ":" then
        idToggle = "="
    else
        idToggle = ":"
    end
    self.editButton({
        index = 3,
        label= idToggle
    })
end

function manaCost_toggle()

    if manaCostToggle == ":" then
        manaCostToggle = "="
    elseif manaCostToggle == "=" then
        manaCostToggle = ">="
    elseif manaCostToggle == ">=" then
        manaCostToggle = "<="
    elseif manaCostToggle == "<=" then
        manaCostToggle = "<"
    elseif manaCostToggle == "<" then
        manaCostToggle = ">"
    elseif manaCostToggle == ">" then
        manaCostToggle = ":"
    end


    self.editButton({
        index = 4,
        label= manaCostToggle
    })
end

function color_toggle()
    if colorToggle == ":" then
        colorToggle = "="
    else
        colorToggle = ":"
    end
    self.editButton({
        index = 5,
        label= colorToggle
    })
end

function otag_toggle()
    if otagToggle == ":" then
        otagToggle = "="
    else
        otagToggle = ":"
    end
    self.editButton({
        index = 6,
        label = otagToggle
    })
end

function is_toggle()
    if isToggle == ":" then
        isToggle = "="
    else
        isToggle = ":"
    end
    self.editButton({
        index = 7,
        label = isToggle
    })
end

function otag_func(obj, color, input, stillEditing)

    if not stillEditing then
         OTag = input
    end
end

function is_func(obj, color, input, stillEditing)

    if not stillEditing then
         IS = input
    end
end


function power_func(obj, color, input, stillEditing)

    if not stillEditing then
         Power = input
    end
end

function toughness_func(obj, color, input, stillEditing)

    if not stillEditing then
         Toughness = input
    end
end

function number_func(obj, color, input, stillEditing)

    if not stillEditing then
         NumberOfCards = input
    end
end

function type_func(obj, color, input, stillEditing)

    if not stillEditing then
         Type = input
    end
end

function oracle_func(obj, color, input, stillEditing)

    if not stillEditing then
         Oracle = input
    end
end

function id_func(obj, color, input, stillEditing)

    if not stillEditing then
         Id = input
    end
end

function color_func(obj, color, input, stillEditing)

    if not stillEditing then
         Color = input
    end
end

function manaCost_func(obj, color, input, stillEditing)

    if not stillEditing then
         ManaCost = input
    end
end





---------------------------------------------------------------------------
-- spawnRandomCommanders spawns 5 random commander cards with a 1-second delay each.
-- All cards are spawned at the same position (startPos) to form a pile.
---------------------------------------------------------------------------
function spawnRandomCommanders()
    local commanderCount = NumberOfCards
    local startPos = self.getPosition() + 
Vector(0,0.1,0)

    if commanderCount == nil or tonumber(commanderCount) == nil or tonumber(commanderCount) < 1 then
        print("Please enter a Number greater than 0.")
        return
    end

    commanderCount = math.floor(tonumber(commanderCount))

    fetchRandomCommander(startPos, commanderCount)

end



   
------------------------------------------------------------------------------------------

---------------------------------------------------------------------------
-- fetchRandomCommander gets a random card from the backend.
---------------------------------------------------------------------------

function fetchRandomCommander(spawnPos, count)
    local queryParts = {}
    if Type ~= "" then
        table.insert(queryParts, "type"..typeToggle..Type)
    end
    if Oracle ~= "" then
        table.insert(queryParts, "oracle"..oracleToggle..Oracle)
    end
    if Color ~= "" then
        table.insert(queryParts, "color"..colorToggle..Color)
    end
    if Id ~= "" then
        table.insert(queryParts, "id"..idToggle..Id)
    end
    if ManaCost ~= "" then
        table.insert(queryParts, "cmc"..manaCostToggle..ManaCost)
    end
    if OTag ~= "" then
        table.insert(queryParts, "otag"..otagToggle..OTag)
    end
     if IS ~= "" then
        table.insert(queryParts, "is"..isToggle..IS)
    end

    local query = table.concat(queryParts, "+")

    if tonumber(count) == 1 then
        local encodedQuery = URLencode(query)
        local singleUrl = BACKEND_URL .. "/random?compact=spawn"
        if encodedQuery ~= "" then
            singleUrl = singleUrl .. "&q=" .. encodedQuery
        end

        WebRequest.get(singleUrl, function(response)
            if response.is_error then
                print("Error fetching single card from backend.")
                return
            end

            if response.response_code and response.response_code >= 400 then
                local errObj = JSONdecode(response.text)
                if errObj and errObj.details then
                    print("Backend error: " .. tostring(errObj.details))
                else
                    print("Backend error while fetching single card.")
                end
                return
            end

            local cardDat = getCardDatFromJSON(response.text, 1)
            if not cardDat then
                print("Error processing single card response.")
                return
            end

            spawnObjectData({ data = cardDat, position = spawnPos, rotation = self.getRotation() })
        end)
        return
    end

    local payload = {
        q = query,
        count = count,
        back = backURL
    }

    local headers = {
        Accept = "application/x-ndjson",
        ["Content-Type"] = "application/json"
    }

    local function splitNDJSONLines(respText)
        local lines = {}
        if not respText or respText == "" then
            return lines
        end

        for line in respText:gmatch("[^\r\n]+") do
            if line and line:match("%S") then
                table.insert(lines, line)
            end
        end

        return lines
    end

    local function firstSpawnJSONFromNDJSON(respText)
        local issues = {}
        local lines = splitNDJSONLines(respText)

        for _, line in ipairs(lines) do
            local trimmed = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if trimmed:match('^{"object"%s*:') then
                local parsed = JSONdecode(trimmed)
                if parsed then
                    if parsed.object == "warning" then
                        table.insert(issues, parsed.warning or "warning")
                    elseif parsed.object == "error" then
                        table.insert(issues, parsed.error or parsed.details or "error")
                    end
                end
            elseif trimmed:find('"ContainedObjects"', 1, true) or trimmed:match('"Name"%s*:%s*"DeckCustom"') then
                return trimmed, issues
            end
        end

        return nil, issues
    end

    local url = BACKEND_URL .. "/random/build"
    WebRequest.custom(url, "POST", true, JSON.encode(payload), headers, function(response)
        if response.is_error then
            print("Error building random deck from backend.")
            return
        end

        if response.response_code and response.response_code >= 400 then
            local errObj = JSONdecode(response.text)
            if errObj and errObj.details then
                print("Backend error: " .. tostring(errObj.details))
            else
                print("Backend error while building random deck.")
            end
            return
        end

        local deckJson, issues = firstSpawnJSONFromNDJSON(response.text)
        if not deckJson then
            if issues and #issues > 0 then
                print("Error processing deck build response: " .. table.concat(issues, ", "))
            else
                print("Error processing deck build response.")
            end
            return
        end

        spawnObjectJSON({ json = deckJson, position = spawnPos, rotation = self.getRotation() })

        if issues and #issues > 0 then
            print("Deck build warning: " .. table.concat(issues, ", "))
        end
    end)
end

---------------------------------------------------------------------------
-- getCardDatFromJSON converts Scryfall JSON into a TTS card data table.
-- Includes error checking for missing fields and Scryfall error objects.
---------------------------------------------------------------------------
function getCardDatFromJSON(json, n)
    local c = JSONdecode(json)
    if not c then
        print("Error: JSON decode returned nil for json: " .. tostring(json))
        return nil
    end
    if c.object == "error" then
        print("Error from backend: " .. (c.details or "unknown error"))
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



-----------------------------------------------------------
-- Card Layout
-----------------------------------------------------------
--Alphabetize cards by their names if they have one (true or false)
alphabetize = false
--Color of the deck highlight and preview elements
uiColor = {0,1,0}
--How many rows or columns are possible
maxRowCol = 20
--How much space is put between cards
spacer = -0.3
--If it flips the cards or not
flip = false
--Optional height offset so cards are raised off the table more
heightOffset = 0


--Detect if tool is placed on top of a deck, designating deck
function onCollisionEnter(collision_info)
    if layoutInProgress then
        return
    end

    if collision_info.collision_object.tag == "Deck" and collision_info.collision_object ~= deck then
        if deck ~= nil then deck.highlightOff() end
        deck = collision_info.collision_object
        deck.highlightOn(uiColor)
        setLayoutDeckDetected(true)
    end
end

function onCollisionExit(collision_info)
    if layoutInProgress then
        return
    end

    if deck ~= nil and collision_info.collision_object == deck then
        deck.highlightOff()
        deck = nil
        setLayoutDeckDetected(false)
    end
end

--Kill the highlight if the tool is destroyed
function onDestroy()
    layoutButtonWatcherRunning = false
    if deck~=nil then deck.highlightOff() end
end



--Click actions and input changes



--Click of the submit button, starts layout
function click_submit()
    --Error protection
    if deck == nil then
        setLayoutDeckDetected(false)
        broadcastToAll("No deck designated.", {0.9,0.2,0.2})
        return
    end
    -- Hide the layout button while running; it will reappear if a deck is detected again.
    setLayoutDeckDetected(false)
    --Lock until finished
    layoutInProgress = true
    self.setLock(true)
    --Lays out cards in a coroutine
    layout("card")
end


--Detect changes to number inputs
function input_change(_, _, userInput, stillEditing, layoutKey)
    if stillEditing == false then
        --Updates number or advises player to use a valid number
        if userInput=="" or tonumber(userInput)<1 or tonumber(userInput)>maxRowCol then
            broadcastToAll("Invalid number entry. Try a number from 1 - "..maxRowCol..".", {0.9,0.2,0.2})
        else
            layoutData[layoutKey] = math.abs(tonumber(userInput))
        end
    end
end



--Laying out of cards/buttons



--Coroutine that lays out cards
function layout(whichType)
    function layout_routine()
        --Get size of cards (need x/z) and add the spacer to it
        local size = deck.getBoundsNormalized().size
        size = {x=size.x+spacer, y=size.y, z=size.z+spacer}
        --Rotate the x/z to match the deck+tool's rotation
        local angle = math.rad(deck.getRotation().y - self.getRotation().y)
        local x = math.abs(size.x * math.cos(angle)) + math.abs(size.z * math.sin(angle))
        local z = math.abs(size.x * math.sin(angle)) + math.abs(size.z * math.cos(angle))
        size.x = x
        size.z = z
        local orderedIndices = nil
        if whichType == "card" and alphabetize == true then
            orderedIndices = buildOrderedIndexList()
        end
        --Determine first card's location
        local pos_starting = {
            x = -size.x * (layoutData.col-1)/2,
            y = 0 + heightOffset,
            z = -size.z
        }
        --Create variables used in placement
        local rowStep, colStep = 0, 0

        local function placeSingleCard(cardObj, pos)
            if not cardObj then
                return
            end

            cardObj.setPositionSmooth(pos)
            if flip then
                local rot = cardObj.getRotation()
                rot.z = rot.z + 180
                cardObj.setRotationSmooth(rot)
            end
        end

        --Placement
        for i=1, layoutData.col*layoutData.row do
            local priorDeckPos = nil
            if deck and deck.getPosition then
                priorDeckPos = deck.getPosition()
            end
            local consumedSingleCard = false

            --Find position for card
            local pos_local = {
                x = pos_starting.x + size.x * colStep,
                y = pos_starting.y,
                z = pos_starting.z - size.z * rowStep,
            }
            local pos = self.positionToWorld(pos_local)
            --Set up next loop
            colStep = colStep + 1
            if colStep > layoutData.col-1 then
                colStep = 0
                rowStep = rowStep + 1
            end
            --Apply action for position
            if whichType == "card" then
                --Places card
                if deck and deck.tag == "Card" then
                    placeSingleCard(deck, pos)
                    deck = nil
                    consumedSingleCard = true
                elseif alphabetize == false then
                    deck.takeObject({position=pos, flip=flip, smooth=true})
                else
                    if #deck.getObjects() > 0 then
                        --Handles most cards
                        local nextIndex = nil
                        if orderedIndices ~= nil and #orderedIndices > 0 then
                            nextIndex = table.remove(orderedIndices, 1)
                        else
                            nextIndex = findNextCardIndex()
                        end
                        deck.takeObject({position=pos, flip=flip, index=nextIndex, smooth=true})
                    else
                        --Handles the leftover card
                        local find_func = function(o) return o.tag=="Card" end
                        local objList = findInRadiusBy(deck.getPosition(), 0.5, find_func)
                        if #objList > 0 then
                            placeSingleCard(objList[1], pos)
                            deck = nil
                            consumedSingleCard = true
                        end
                    end
                end
            elseif whichType == "button" then
                --Places button
                self.createButton({
                    label="X", click_function="none", function_owner=self,
                    position=pos_local, height=0, width=0, font_size=1000,
                    font_color=uiColor,
                    rotation={0,deck.getRotation().y-self.getRotation().y,0},
                })
            end
            coroutine.yield(0)
            --Kills loop if deck is exhausted
            if deck == nil then
                if consumedSingleCard then
                    break
                end

                local recoverOrigin = priorDeckPos or self.getPosition()
                local recoveredCards = findInRadiusBy(recoverOrigin, 0.35, function(o) return o.tag=="Card" end)
                local nearestCard = nil
                local nearestDistSq = nil

                for _, cardObj in ipairs(recoveredCards) do
                    local cardPos = cardObj.getPosition and cardObj.getPosition() or nil
                    if cardPos then
                        local dx = cardPos.x - recoverOrigin.x
                        local dy = cardPos.y - recoverOrigin.y
                        local dz = cardPos.z - recoverOrigin.z
                        local distSq = (dx * dx) + (dy * dy) + (dz * dz)
                        if nearestDistSq == nil or distSq < nearestDistSq then
                            nearestDistSq = distSq
                            nearestCard = cardObj
                        end
                    end
                end

                if nearestCard then
                    deck = nearestCard
                else
                    break
                end
            end
        end

        layoutInProgress = false
        self.setLock(false)
        setLayoutDeckDetected(deck ~= nil and (deck.tag == "Deck" or deck.tag == "Card"))
        createClickButtons()
        return 1
    end
    startLuaCoroutine(self, "layout_routine")
end

function buildOrderedIndexList()
    local orderList = {}
    for _, card in ipairs(deck.getObjects()) do
        if card.nickname ~= "" then
            local insertTable = {name=card.nickname, index=card.index}
            table.insert(orderList, insertTable)
        end
    end

    local sort_func = function(a,b) return a["name"] > b["name"] end
    table.sort(orderList, sort_func)

    for _, card in ipairs(deck.getObjects()) do
        if card.nickname == "" then
            local insertTable = {name=card.nickname, index=card.index}
            table.insert(orderList, 1, insertTable)
        end
    end

    local indexList = {}
    for _, cardInfo in ipairs(orderList) do
        table.insert(indexList, cardInfo.index)
    end
    return indexList
end

--Gets the order of cards alphabetized
function findNextCardIndex()
    local orderList = {}
    for _, card in ipairs(deck.getObjects()) do
        if card.nickname ~= "" then
            local insertTable = {name=card.nickname, index=card.index}
            table.insert(orderList, insertTable)
        end
    end
    --Sort ordered list
    local sort_func = function(a,b) return a["name"] > b["name"] end
    table.sort(orderList, sort_func)
    --Add no-names onto start
    for _, card in ipairs(deck.getObjects()) do
        if card.nickname == "" then
            local insertTable = {name=card.nickname, index=card.index}
            table.insert(orderList, 1, insertTable)
        end
    end
    return orderList[1].index
end

--Finds objects in radius of a position, accepts optional filtering function
--Example func: function(o) return o.tag=="Deck" or o.tag=="Card" end
function findInRadiusBy(pos, radius, func)
    local objList = Physics.cast({
        origin=pos, direction={0,1,0}, type=2, size={radius,radius,radius},
        max_distance=0, --debug=true
    })

    local refinedList = {}
    for _, obj in ipairs(objList) do
        if func == nil then
            table.insert(refinedList, obj.hit_object)
        else
            if func(obj.hit_object) then
                table.insert(refinedList, obj.hit_object)
            end
        end
    end

    return refinedList
end



--Button/input creation



function createInputs()
    function colInput(w,x,y,z) input_change(w,x,y,z,"col") end
    self.createInput({
        input_function="colInput", function_owner=self, tooltip="Columns",
        alignment=3, rotation={0,0,180}, position={-0.1,-0.1,-1}, height=250, width=630,
        font_size=226, validation=2, tab=2, value=layoutData.col
    })
    function rowInput(w,x,y,z) input_change(w,x,y,z,"row") end
    self.createInput({
        input_function="rowInput", function_owner=self, tooltip="Rows",
        alignment=3, rotation={0,0,180}, position={-0.1,-0.1,1}, height=250, width=630,
        font_size=226, validation=2, tab=2, value=layoutData.row
    })
end

function createClickButtons()
    if not layoutDeckDetected or layoutButtonVisible then
        return
    end

    self.createButton({
        click_function="click_submit", 
        function_owner=self,
        label = "^^^^^Layout^^^^^",
        tooltip="Layout",
        position={0,0.1,-2}, height=140, width=1000
    })
    layoutButtonVisible = true
end

function hideLayoutButton()
    if layoutButtonVisible and layoutButtonIndex ~= nil then
        self.removeButton(layoutButtonIndex)
        layoutButtonVisible = false
    end
end

function refreshLayoutButtonFromFlag()
    if layoutDeckDetected then
        createClickButtons()
    else
        hideLayoutButton()
    end
end

function setLayoutDeckDetected(flag)
    local nextFlag = flag == true
    if layoutDeckDetected ~= nextFlag then
        layoutDeckDetected = nextFlag
        layoutButtonNeedsRefresh = true
    end
end

function ensureLayoutButtonWatcher()
    if layoutButtonWatcherRunning then
        return
    end

    layoutButtonWatcherRunning = true
    startLuaCoroutine(self, "layout_button_watcher")
end

function layout_button_watcher()
    while layoutButtonWatcherRunning do
        if layoutButtonNeedsRefresh then
            refreshLayoutButtonFromFlag()
            layoutButtonNeedsRefresh = false
        end
        coroutine.yield(0)
    end
    return 1
end


