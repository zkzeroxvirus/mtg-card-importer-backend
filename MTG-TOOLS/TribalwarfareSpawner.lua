-----------------------------------------------------------------------
-- Simple random card spawner for Tabletop Simulator
-- Filters supported: Type and CMC
-- Always spawns exactly 1 card
-----------------------------------------------------------------------

backURL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
BACKEND_URL = "http://api.mtginfo.org"

Type = ""
ManaCost = ""

function onLoad()
    self.createButton({
        label = "Spawn Card",
        click_function = "spawnRandomCard",
        function_owner = self,
        position = {0, 0.1, 1.25},
        rotation = {0, 0, 0},
        width = 900,
        height = 180,
        font_size = 100,
        scale = {1, 1, 1}
    })

    self.createInput({
        input_function = "type_func",
        function_owner = self,
        label = "Type:",
        alignment = 1,
        position = {x=0, y=0.1, z=-0.2},
        width = 450,
        height = 180,
        font_size = 100,
        validation = 1,
    })

    self.createInput({
        input_function = "manaCost_func",
        function_owner = self,
        label = "CMC<=",
        alignment = 1,
        position = {x=0, y=0.1, z=0.45},
        width = 450,
        height = 180,
        font_size = 100,
        validation = 1,
    })
end

function type_func(obj, color, input, stillEditing)
    if not stillEditing then
        Type = input
    end
end

function manaCost_func(obj, color, input, stillEditing)
    if not stillEditing then
        ManaCost = input
    end
end

function spawnRandomCard()
    local queryParts = {}

    if Type ~= "" then
        table.insert(queryParts, "type:" .. Type)
    end

    if ManaCost ~= "" then
        table.insert(queryParts, "cmc<=" .. ManaCost)
    end

    local query = table.concat(queryParts, "+")
    local url = BACKEND_URL .. "/random?compact=spawn&enforceCommander=false"

    if query ~= "" then
        url = url .. "&q=" .. URLencode(query)
    end

    WebRequest.get(url, function(response)
        if response.is_error then
            print("Error fetching card from backend.")
            return
        end

        if response.response_code and response.response_code >= 400 then
            local errObj = JSONdecode(response.text)
            if errObj and errObj.details then
                print("Backend error: " .. tostring(errObj.details))
            else
                print("Backend error while fetching card.")
            end
            return
        end

        local cardDat = getCardDatFromJSON(response.text, 1)
        if not cardDat then
            print("Error processing card response.")
            return
        end

        spawnObjectData({
            data = cardDat,
            position = self.getPosition() + Vector(0, 0.1, 0),
            rotation = self.getRotation()
        })
    end)
end

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
    c.face = ""
    c.oracle = ""
    local qual = "large"
    local imageSuffix = ""

    if c.image_status ~= "highres_scan" then
        imageSuffix = "?" .. tostring(os.date("%x")):gsub("/", "")
    end

    if c.card_faces and c.image_uris then
        for i, f in ipairs(c.card_faces) do
            if c.cmc then
                f.name = f.name:gsub('"', "") .. "\n" .. f.type_line .. " " .. c.cmc .. "CMC"
            else
                f.name = f.name:gsub('"', "") .. "\n" .. f.type_line .. " " .. f.cmc .. "CMC"
            end

            if i == 1 then
                cardName = f.name
            end

            c.oracle = c.oracle .. f.name .. "\n" .. setOracle(f) .. (i == #c.card_faces and "" or "\n")
        end
    elseif c.card_faces then
        local f = c.card_faces[1]
        if c.cmc then
            cardName = f.name:gsub('"', "") .. "\n" .. f.type_line .. " " .. c.cmc .. "CMC DFC"
        else
            cardName = f.name:gsub('"', "") .. "\n" .. f.type_line .. " " .. f.cmc .. "CMC DFC"
        end
        c.oracle = setOracle(f)
    else
        cardName = c.name:gsub('"', "") .. "\n" .. c.type_line .. " " .. c.cmc .. "CMC"
        c.oracle = setOracle(c)
    end

    local backDat = nil
    if c.card_faces and not c.image_uris then
        local faceAddress = c.card_faces[1].image_uris.normal:gsub('%?.*', ''):gsub('normal', qual) .. imageSuffix
        local backAddress = c.card_faces[2].image_uris.normal:gsub('%?.*', ''):gsub('normal', qual) .. imageSuffix
        if faceAddress:find('/back/') and backAddress:find('/front/') then
            local temp = faceAddress
            faceAddress = backAddress
            backAddress = temp
        end

        c.face = faceAddress
        local f = c.card_faces[2]
        local name
        if c.cmc then
            name = f.name:gsub('"', "") .. "\n" .. f.type_line .. "\nCMC: " .. c.cmc .. " DFC"
        else
            name = f.name:gsub('"', "") .. "\n" .. f.type_line .. "\nCMC: " .. f.cmc .. " DFC"
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
        c.face = c.image_uris.normal:gsub('%?.*', ''):gsub('normal', qual) .. imageSuffix
        if cardName:lower():match('geralf') then
            c.face = c.image_uris.normal:gsub('%?.*', ''):gsub('normal', 'png'):gsub('jpg', 'png') .. imageSuffix
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

function setOracle(c)
    local n = "\n[b]"
    if c.power then
        n = n .. c.power .. "/" .. c.toughness
    elseif c.loyalty then
        n = n .. tostring(c.loyalty)
    else
        n = false
    end
    return (c.oracle_text or "") .. (n and n .. "[/b]" or "")
end

function JSONdecode(txt)
    return JSON.decode(txt)
end

function URLencode(str)
    if str then
        str = str:gsub("\n", "\r\n")
        str = str:gsub("([^%w ])", function(c)
            return string.format("%%%02X", string.byte(c))
        end)
        str = str:gsub(" ", "+")
    end
    return str
end
