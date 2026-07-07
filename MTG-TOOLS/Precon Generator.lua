-- Random Commander precon loader.
-- Source selection and deck/card building live in the backend at /precons/random.

PRECON_BACKEND_URL = "http://api.mtginfo.org"
--PRECON_BACKEND_URL = "http://localhost:3000"
PRECON_BACKEND_RANDOM_URL = PRECON_BACKEND_URL .. "/precons/random"

MAINDECK_POSITION_OFFSET = {0.0, 1, 0.1286}
COMMANDER_POSITION_OFFSET = {0.7286, 1, -0.8257}

lock = false
playerColor = nil

local function printErr(message)
    printToAll(message, {r=0.9, g=0.2, b=0.2})
end

local function printInfo(message)
    printToAll(message, {r=0.3, g=0.3, b=0.3})
end

local function decodeJSON(text)
    local success, parsed = pcall(function()
        return JSON.decode(text or "")
    end)

    if success then
        return parsed
    end

    return nil
end

local function firstBackendDeckFromNDJSON(respText)
    local issues = {}

    if not respText or respText == "" then
        return nil, issues
    end

    for line in respText:gmatch("[^\r\n]+") do
        if line and line:match("%S") then
            local parsed = decodeJSON(line)

            if parsed then
                if parsed.object == "warning" then
                    table.insert(issues, parsed.warning or "warning")
                elseif parsed.object == "error" then
                    table.insert(issues, parsed.details or parsed.error or "backend error")
                elseif parsed.Name == "DeckCustom" or parsed.ContainedObjects then
                    return parsed, issues
                else
                    table.insert(issues, "unexpected backend payload")
                end
            else
                table.insert(issues, "invalid backend JSON")
            end
        end
    end

    return nil, issues
end

local function finishImport()
    lock = false
    self.setLock(false)
end

local function failImport(message)
    printErr(message)
    printErr("Precon import failed.")
    finishImport()
end

local function cloneArray(values)
    local out = {}
    if type(values) ~= "table" then
        return out
    end

    for _, value in ipairs(values) do
        table.insert(out, value)
    end

    return out
end

local function copyCustomDeckEntries(source, target)
    if type(source) ~= "table" or type(target) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        target[tostring(key)] = value
    end
end

local function addCardCustomDeckEntries(card, customDeck)
    if type(card) ~= "table" then
        return
    end

    copyCustomDeckEntries(card.CustomDeck, customDeck)

    if type(card.States) == "table" then
        for _, state in pairs(card.States) do
            if type(state) == "table" then
                copyCustomDeckEntries(state.CustomDeck, customDeck)
            end
        end
    end
end

local function buildDeckFromCards(sourceDeck, cards, nicknameSuffix)
    if type(cards) ~= "table" or #cards == 0 then
        return nil
    end

    if #cards == 1 then
        return cards[1]
    end

    local deck = {
        CardID = sourceDeck.CardID or 0,
        Name = "DeckCustom",
        Nickname = (sourceDeck.Nickname or "Precon") .. (nicknameSuffix or ""),
        Description = sourceDeck.Description or "",
        Transform = sourceDeck.Transform,
        HideWhenFaceDown = sourceDeck.HideWhenFaceDown == true,
        AltLookAngle = sourceDeck.AltLookAngle or {x = 0, y = 0, z = 0},
        DeckIDs = {},
        CustomDeck = {},
        ContainedObjects = cloneArray(cards),
    }

    for _, card in ipairs(cards) do
        if card.CardID then
            table.insert(deck.DeckIDs, card.CardID)
        end
        addCardCustomDeckEntries(card, deck.CustomDeck)
    end

    return deck
end

local function splitPreconDeck(deckDat)
    local mainCards = {}
    local commanderCards = {}

    for _, card in ipairs(deckDat.ContainedObjects or {}) do
        if card._preconSection == "commander" then
            table.insert(commanderCards, card)
        else
            table.insert(mainCards, card)
        end
    end

    if #commanderCards == 0 then
        return deckDat, nil
    end

    return buildDeckFromCards(deckDat, mainCards, "\n[i]Maindeck[/i]"),
        buildDeckFromCards(deckDat, commanderCards, "\n[i]Commanders[/i]"),
        #commanderCards
end

function importDeck()
    if lock then
        printErr("Error: Deck import started while importer locked.")
        return 1
    end

    lock = true
    self.setLock(true)
    printInfo("Starting backend precon import...")

    WebRequest.get(PRECON_BACKEND_RANDOM_URL, function(webReturn)
        if webReturn.response_code and webReturn.response_code >= 400 then
            local errObj = decodeJSON(webReturn.text or "{}")
            local message = "Backend returned HTTP " .. tostring(webReturn.response_code)

            if errObj then
                message = errObj.details or errObj.error or message
            end

            failImport(message)
            return
        elseif webReturn.error then
            failImport("Backend request error: " .. webReturn.error)
            return
        elseif webReturn.is_error then
            failImport("Backend request error: unknown")
            return
        end

        local deckDat, issues = firstBackendDeckFromNDJSON(webReturn.text)
        if not deckDat then
            if issues and #issues > 0 then
                failImport("Backend precon response did not include a deck: " .. table.concat(issues, ", "))
            else
                failImport("Backend precon response did not include a deck.")
            end
            return
        end

        local maindeckDat, commanderDat, commanderCount = splitPreconDeck(deckDat)
        local rotation = self.getRotation()

        if maindeckDat then
            spawnObjectData({
                data = maindeckDat,
                position = self.positionToWorld(MAINDECK_POSITION_OFFSET),
                rotation = rotation
            })
        end

        if commanderDat then
            spawnObjectData({
                data = commanderDat,
                position = self.positionToWorld(COMMANDER_POSITION_OFFSET),
                rotation = rotation
            })
        end

        printInfo("Backend precon import complete!")
        if commanderCount and commanderCount > 0 then
            printInfo("Separated " .. tostring(commanderCount) .. " commander card(s).")
        end
        if deckDat.Nickname and deckDat.Nickname ~= "" then
            printInfo("Loaded: " .. deckDat.Nickname)
        end
        if issues and #issues > 0 then
            printToAll("Precon import warning: " .. table.concat(issues, ", "), {r=1, g=0.6, b=0.1})
        end

        finishImport()
    end)

    return 1
end

local function drawUI()
    self.clearInputs()
    self.clearButtons()

    self.createButton({
        click_function = "onLoadDeckURLButton",
        function_owner = self,
        label = "RANDOM PRECON!",
        position = {-1, 0.1, 1.15},
        rotation = {0, 0, 0},
        width = 850,
        height = 160,
        font_size = 80,
        color = {0.5, 0.5, 0.5},
        font_color = {r=1, b=1, g=1},
        tooltip = "Click to load a random precon",
    })
end

function onLoadDeckURLButton(_, pc, _)
    if lock then
        printToColor("Another deck is currently being imported. Please wait for that to finish.", pc)
        return
    end

    playerColor = pc
    startLuaCoroutine(self, "importDeck")
end

function onLoad(_)
    drawUI()
end
