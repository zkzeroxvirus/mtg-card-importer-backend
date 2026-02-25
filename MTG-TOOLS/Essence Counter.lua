MAX_VALUE = 999999
WEB_URL = "https://script.google.com/macros/s/AKfycbwIVox39JBPeMswdPtZHfELAH7XJFo4Ih-ib-BPqR7NDACaxapoO5kqcC1xGwwrS3EX/exec"
DEBOUNCE_SECONDS = 3.0
MIN_SYNC_INTERVAL_SECONDS = 8.0
local TOOLTIP_WRAP = 80
local BAG_MARKER = "[from-bag]"
local CAPTURE_NOTE_PREFIX = "CAPTURE_TICKET_V1"
local CAPTURE_TICKET_LABEL = "Capture Ticket:"

-- Relative anchor for spawned reward tokens
SPAWN_BUTTON_LOCAL = Vector{2, 0.2, 0}
SPAWN_HEIGHT_OFFSET = 2

-- Anchor state
lastAnchorPos = nil
lastAnchorRot = nil
lastAnchorWorld = nil

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

-- Crypt Buffs (effects + unlock conditions)
local CRYPT_REWARDS = {
    { name = "Flame of Progress", desc = "+25% Experience.\nUnlock: Beat Azlask, the Swelling Scourge." },
    { name = "Spiritual Guidance", desc = "+25% Essence.\nUnlock: Beat Hinata, Dawn-Crowned." },
    { name = "Fickle Duplicant", desc = "At the beginning of the game you get 1 free Scryfall creature card, but it is a 1/1 balloon in addition to its other creature types and abilities.\nUnlock: Beat The Jolly Balloon Man." },
    { name = "Undying Legionary", desc = "+5 Max HP.\nUnlock: Beat Imotekh the Stormlord." },
    { name = "Treasure Pirate", desc = "At the beginning of every encounter, start with a Treasure token.\nUnlock: Beat Olivia, Opulent Outlaw." },
    { name = "Finders Keepers", desc = "Once per encounter you may look at the top 3 cards of target player's library and put them back in any order, then draw a card.\nUnlock: Beat Yuriko, the Tiger's Shadow." },
    { name = "Quick Spell", desc = "Once per town, you may upgrade a card for free.\nUnlock: Beat Kudo, King Among Bears." },
    { name = "The God Trees Blessing", desc = "You may pick the color of your choice for Merchant Packs that have color.\nYou may switch the color identity of the rewards from encounters (mono blue to mono red, etc.).\nUnlock: Beat Jared Carthalion." },
    { name = "Respited Gift", desc = "+1 Cashout per fight.\nUnlock: Beat Kibo, Uktabi Prince." },
    { name = "Might of Okaun", desc = "During your upkeep flip a coin. If you win the flip, draw a card. If you lose the flip, lose 1 life.\nUnlock: Beat Okaun and Zndrsplt." },
    { name = "Shapeshifter", desc = "All creatures you own in all zones gain a creature type your commander has. Pick this after deckbuilding.\nUnlock: Beat Morophon, the Boundless." },
    { name = "Unearthly Reach", desc = "+2 ticket slots.\nUnlock: Beat Tormod and Ravos." },
}

-- Achievements (effects + unlock conditions)
local ACHIEVEMENTS_LIST = {
    { name = "Happy Fun Land", desc = "At the beginning of the game, spawn 5 random attractions to create your attraction deck.\nUnlock: Beat a crypt fight with attractions." },
    { name = "Nature's Blessing", desc = "Instead of gaining dual lands during deck creation, you may instead get triomes.\nUnlock: Beat a crypt with 50 or more lands in your deck." },
    { name = "Dog's Best Friend", desc = "At the beginning of the game, before deckbuilding, gain a random companion. You must adhere to the companion rules when deckbuilding. Free mulligan cards must also follow your companion.\nUnlock: Beat a crypt fight with a companion in your deck." },
    { name = "Orzhov Identity Buff - Tithe and Toil", desc = "If your commander is White: Once per turn, when a token enters the battlefield under your control, you may populate 1. If your commander is Black: Once per turn, when a non-token creature you control dies, you may create a 1/1 Black Zombie.\nUnlock: Beat a crypt fight where all players' commander identities were either White, Black, or Orzhov." },
    { name = "Simic Identity Buff - Adaptive Pattern", desc = "If your commander is Blue: Once per turn, when you draw your second card this turn, you may put a +1/+1 counter on a creature you control. If your commander is Green: Once per turn, when a +1/+1 counter is placed on a creature you control, you may draw a card.\nUnlock: Beat a crypt fight where all players' commander identities were either Green, Blue, or Simic." },
    { name = "Azorius Identity Buff - Law of Efficiency", desc = "If your commander is White: Once per turn, when you cast a spell during another player's turn, you may gain 1 life. If your commander is Blue: Once per turn, when you counter a spell or ability, you may draw a card.\nUnlock: Beat a crypt fight where all players' commander identities were either White, Blue, or Azorius." },
    { name = "Boros Identity Buff - Charge of Conviction", desc = "If your commander is White: Once per turn, when one or more creatures you control attacks, you may untap one creature you control. If your commander is Red: Once per turn, when a creature you control attacks alone, you may give it +2/+0 until end of turn.\nUnlock: Beat a crypt fight where all players' commander identities were either Red, White, or Boros." },
    { name = "Changeling's Land Form", desc = "At the beginning of the game start with a random basic land on the battlefield.\nUnlock: Beat a crypt fight with a Changeling commander." },
    { name = "Golgari Identity Buff - Cycle of Rot", desc = "If your commander is Black: Once per turn, when a permanent enters your graveyard from the battlefield, you may put a -1/-1 counter on target creature. If your commander is Green: Once per turn, when a creature dies, you may create a Food token.\nUnlock: Beat a crypt fight where all players' commander identities were either Black, Green, or Golgari." },
    { name = "Izzet Identity Buff - Experimental Sparks", desc = "If your commander is Blue: Once per turn, when you cast an instant, you may scry 1, then draw 1. If your commander is Red: Once per turn, when you cast a sorcery, you may deal 1 damage to any target.\nUnlock: Beat a crypt fight where all players' commander identities were either Blue, Red, or Izzet." },
    { name = "Dimir Identity Buff - Whisper Network", desc = "If your commander is Blue: Once per turn, when you cast a spell on an opponent's turn, you may untap target nonland permanent. If your commander is Black: Once per turn, when you target a permanent you don't control, you may exile target card in any graveyard.\nUnlock: Beat a crypt fight where all players' commander identities were either Blue, Black, or Dimir." },
    { name = "Selesnya Identity Buff - Harmony's Bloom", desc = "If your commander is White: Once per turn, when you gain life, you may put a +1/+1 counter on a creature you control. If your commander is Green: Once per turn, when you cast a creature spell, you may gain 1 life.\nUnlock: Beat a crypt fight where all players' commander identities were either Green, White, or Selesnya." },
    { name = "Raccoon's Rage", desc = "At the beginning of the game start with a Mountain on the battlefield.\nUnlock: Beat a crypt fight with a Raccoon commander." },
    { name = "Gamblers never quit", desc = "Once per town, when you pick your first town action that costs XP, you flip a coin. You may not use this buff if you cannot pay double the XP cost. If you win the coin flip, the town action is free. If you lose the coin flip, the town action costs double XP.\nUnlock: Win a coin flip 6 times in a row." },
    { name = "Stick it To Me", desc = "At the beginning of the game, spawn 5 random sticker sheets to create your sticker deck.\nUnlock: Beat a crypt fight with stickers." },
    { name = "Gruul Identity Buff - Primal Fury", desc = "If your commander is Red: Once per turn, when a creature you control becomes modified, you may give it haste until end of turn. If your commander is Green: Once per turn, when a creature you control attacks, you may give it trample until end of turn.\nUnlock: Beat a crypt fight where all players' commander identities were either Red, Green, or Gruul." },
    { name = "Chaos", desc = "Once per game, reroll an event.\nUnlock: Open 5 events in a row before an encounter." },
    { name = "Horse's Gallop", desc = "At the beginning of the game start with a Forest on the battlefield.\nUnlock: Beat a crypt fight with a Horse commander." },
    { name = "Victory lap", desc = "Your buff maximum increases by 3 (from 4 to 7).\nUnlock: Beat 3 crypt bosses in a single session." },
    { name = "Dawn of Crabs", desc = "At the beginning of the game start with a Plains on the battlefield.\nUnlock: Beat a crypt fight with a Crab commander." },
    { name = "Rakdos Identity Buff - Showstopper's Encore", desc = "If your commander is Black: Once per turn, when a creature dies, you may draw a card and lose 1 life. If your commander is Red: Once per turn, when you deal combat damage to an opponent, you may create a Treasure token.\nUnlock: Beat a crypt fight where all players' commander identities were either Black, Red, or Rakdos." },
    { name = "One with death", desc = "Gain a second free card during deck creation. One of those free cards can be a Game Changer.\nUnlock: Beat a crypt fight on turn one." },
    { name = "Compelling Madness", desc = "Once per encounter, target player gains 5 life. This can be done at instant speed.\nUnlock: Only if you indirectly kill one non-host player in a session." },
    { name = "Fish Pond", desc = "At the beginning of the game start with an Island on the battlefield.\nUnlock: Beat a crypt fight with a Fish commander." },
    { name = "Construct's Salvation", desc = "At the beginning of the game start with a Wastes on the battlefield.\nUnlock: Beat a crypt fight with a Construct commander." },
    { name = "Scorpion's Nest", desc = "At the beginning of the game start with a Swamp on the battlefield.\nUnlock: Beat a crypt fight with a Scorpion commander." },
}

-- Tickets (effects + timing)
local TICKETS_LIST = {
    { name = "Vanguard Ticket", desc = "You may begin the game with a vanguard of your choice between three random choices." },
    { name = "Color Combo Ticket", desc = "At the beginning of the game, before deckbuilding, pick your color identity to play with." },
    { name = "Emblem Ticket", desc = "You may begin the game with an emblem of your choice between three random choices." },
    { name = "Sol Ring Ticket", desc = "You get a Sol Ring Ticket. This allows you to have a free Sol Ring in your deck without it counting towards your 39." },
    { name = "Conspiracy Ticket", desc = "You may begin the game with a conspiracy of your choice between three random choices before picking your commander." },
    { name = "Trinket Ticket", desc = "You may begin the game with a trinket of your choice between three random choices." },
}

local lastValue = 0
local lastName = ""
local lastDescription = ""
local lastAchievements = ""
local lastCrypt = ""
local lastTickets = ""
local lastCaptures = ""
local localPlayerKey = nil
local isSyncEnabled = false
local pendingHandle = nil
local syncInFlight = false
local syncQueued = false
local syncDirty = false
local lastSyncSentAt = 0
local lastSyncSignature = ""
local recentlyHandledGuids = {}
local watcherActive = false
local watcherHandle = nil
local saveBlobCache = nil
local saveBlobDirty = true

local state = { value = 0, achievements = {}, crypt = {}, tickets = {}, captures = {} }
local plusSteps = { 5, 10, 50 }
local minusSteps = { -5, -10, -50 }

-- Base template for all spawned reward tokens (shared model/physics)
local MESH_URL = "https://steamusercontent-a.akamaihd.net/ugc/1327949700692125593/FFAF751A7D6392C0A1C2A94727C7DA513B5F5960/"
local BASE_SPAWN_TEMPLATE = {
    Name = "Custom_Model",
    Transform = {
        posX = 0, posY = 1, posZ = 0,
        rotX = 0, rotY = 0, rotZ = 0,
        scaleX = 0.7, scaleY = 0.7, scaleZ = 0.7,
    },
    Nickname = "",
    Description = "",
    GMNotes = "",
    ColorDiffuse = { r = 1, g = 1, b = 1 },
    Locked = false,
    Grid = false,
    Snap = false,
    Autoraise = true,
    Sticky = false,
    Tooltip = true,
    Hands = false,
    MaterialIndex = -1,
    MeshURL = MESH_URL,
    Rigidbody = {
        Mass = 0.5,
        Drag = 0.1,
        AngularDrag = 0.1,
        UseGravity = true,
        Freeze = false,
    },
    CustomMesh = {
        MeshURL = MESH_URL,
        DiffuseURL = "",
        ColliderURL = MESH_URL,
        Convex = true,
        MaterialIndex = 3,
        TypeIndex = 1,
        CustomShader = {
            SpecularColor = { r = 0, g = 0, b = 0 },
            SpecularIntensity = 0,
            SpecularSharpness = 2,
            FresnelStrength = 0,
        },
        CastShadows = true,
    },
}

local CAPTURE_BAG_TEMPLATE = {
    GUID = "",
    Name = "Custom_Model_Infinite_Bag",
    Transform = {
        posX = 0, posY = 0, posZ = 0,
        rotX = 0, rotY = 0, rotZ = 0,
        scaleX = 0.7, scaleY = 0.7, scaleZ = 0.7,
    },
    Nickname = "",
    Description = "",
    GMNotes = "",
    AltLookAngle = { x = 0, y = 0, z = 0 },
    ColorDiffuse = { r = 1, g = 1, b = 1 },
    LayoutGroupSortIndex = 0,
    Value = 0,
    Locked = false,
    Grid = true,
    Snap = false,
    IgnoreFoW = false,
    MeasureMovement = false,
    DragSelectable = true,
    Autoraise = true,
    Sticky = true,
    Tooltip = true,
    GridProjection = false,
    HideWhenFaceDown = false,
    Hands = false,
    MaterialIndex = -1,
    MeshIndex = -1,
    CustomMesh = {
        MeshURL = MESH_URL,
        DiffuseURL = "",
        NormalURL = "",
        ColliderURL = MESH_URL,
        Convex = true,
        MaterialIndex = 1,
        TypeIndex = 7,
        CustomShader = {
            SpecularColor = { r = 224, g = 208, b = 191 },
            SpecularIntensity = 0,
            SpecularSharpness = 2,
            FresnelStrength = 0.107142858,
        },
        CastShadows = true,
    },
    LuaScript = "",
    LuaScriptState = "",
    XmlUI = "",
    ContainedObjects = {},
}

local extractCaptureFaceUrlFromPayload
local buildCaptureBagSpawnData

-- Image URLs per reward (fill these with real URLs later)
local SPAWN_IMAGES = {
    -- Crypt Buffs
    ["Flame of Progress"] = "https://cards.scryfall.io/large/front/c/3/c329ff2b-0331-4934-a8df-870dd7bf402b.jpg",
    ["Spiritual Guidance"] = "https://cards.scryfall.io/large/front/5/0/504a69eb-3c2d-4bb1-b117-252b15acf0c2.jpg",
    ["Fickle Duplicant"] = "https://cards.scryfall.io/large/front/4/c/4c8f2c0f-7ed8-4d72-8f94-33ad615bf21d.jpg",
    ["Undying Legionary"] = "https://cards.scryfall.io/large/front/c/1/c160c1f7-714e-444a-ab74-c64c3a099a48.jpg",
    ["Treasure Pirate"] = "https://cards.scryfall.io/large/front/8/6/861b5889-0183-4bee-afeb-a4b2aa700a8e.jpg?1689996018",
    ["Finders Keepers"] = "https://cards.scryfall.io/large/front/f/3/f340cbf7-5bbe-45b9-a4bf-d1caa500ff93.jpg",
    ["Quick Spell"] = "https://cards.scryfall.io/large/front/6/7/67751745-61c9-488f-b5b3-310c0bafdda7.jpg",
    ["The God Trees Blessing"] = "https://cards.scryfall.io/large/front/1/7/17315a12-a7f8-45ba-ac3b-a62c789e75d0.jpg",
    ["Respited Gift"] = "https://cards.scryfall.io/large/front/2/7/275b4c56-e17e-49ec-8946-0e95a4bfa1ae.jpg",
    ["Might of Okaun"] = "https://cards.scryfall.io/large/front/9/4/94eea6e3-20bc-4dab-90ba-3113c120fb90.jpg",
    ["Shapeshifter"] = "https://cards.scryfall.io/large/front/d/7/d79f7ecc-c43b-48de-9d90-1085cf2bce5d.jpg?1738928117",
    ["Unearthly Reach"] = "https://cards.scryfall.io/large/front/3/c/3caa9c55-5e3b-436b-84a9-b7ccebf63799.jpg",

    -- Achievements
    ["Happy Fun Land"] = "https://cards.scryfall.io/large/front/c/5/c52057f7-a78a-4edc-8e95-edaea6376e76.jpg",
    ["Nature's Blessing"] = "https://cards.scryfall.io/large/front/b/e/be72862d-d71e-4b18-98a6-59019399f631.jpg",
    ["Dog's Best Friend"] = "https://cards.scryfall.io/large/front/1/b/1bd8e61c-2ee8-4243-a848-7008810db8a0.jpg",
    ["Orzhov Identity Buff - Tithe and Toil"] = "https://cards.scryfall.io/large/front/4/0/4029c3a0-a999-453a-a838-7adb81e481ee.jpg",
    ["Simic Identity Buff - Adaptive Pattern"] = "https://cards.scryfall.io/large/front/f/6/f6d381eb-6cb6-4505-aebe-995c1ddc8527.jpg",
    ["Azorius Identity Buff - Law of Efficiency"] = "https://cards.scryfall.io/large/front/3/0/30dc237e-b28a-4b65-9790-6b434828bf2e.jpg",
    ["Boros Identity Buff - Charge of Conviction"] = "https://cards.scryfall.io/large/front/8/7/87e80447-9572-43a7-8487-3249cd9ce596.jpg",
    ["Changeling's Land Form"] = "https://cards.scryfall.io/large/front/7/f/7f36775e-9e48-49cc-a771-d58481712edc.jpg",
    ["Golgari Identity Buff - Cycle of Rot"] = "https://cards.scryfall.io/large/front/c/6/c6717954-35d8-4d7e-95aa-f7d26d15d4b2.jpg",
    ["Izzet Identity Buff - Experimental Sparks"] = "https://cards.scryfall.io/large/front/0/6/06c9158c-064b-4d12-b860-d2c1450d1897.jpg",
    ["Dimir Identity Buff - Whisper Network"] = "https://cards.scryfall.io/large/front/d/a/dac8975a-0d41-4538-8e49-a2de5d410b6c.jpg",
    ["Selesnya Identity Buff - Harmony's Bloom"] = "https://cards.scryfall.io/large/front/3/4/34ea44f2-cb2f-4b86-83fc-fe507f05bb9d.jpg",
    ["Raccoon's Rage"] = "https://steamusercontent-a.akamaihd.net/ugc/9510145195220216105/C4209F043077BD6652279AF682ECAB7F75A505E3/",
    ["Gamblers never quit"] = "https://cards.scryfall.io/large/front/5/6/567665f3-4227-4f3c-bfbe-4e9576f32b50.jpg",
    ["Stick it To Me"] = "https://cards.scryfall.io/large/front/f/a/fa0c5716-a222-41a1-88cf-8b4aae87f92b.jpg",
    ["Gruul Identity Buff - Primal Fury"] = "https://cards.scryfall.io/large/front/7/c/7c4a08e9-06c7-43e9-a855-4f507a35ae8b.jpg",
    ["Chaos"] = "https://cards.scryfall.io/large/front/7/b/7b09ab3a-344c-42d0-9f71-e8374214cda1.jpg",
    ["Horse's Gallop"] = "https://steamusercontent-a.akamaihd.net/ugc/15336545532534506892/445376E890EA053549AB6A3FB3FD0DB5C729955A/",
    ["Victory lap"] = "https://cards.scryfall.io/large/front/9/c/9cb27fb1-41b1-49b8-bb3b-2c8a011ae7a9.jpg",
    ["Dawn of Crabs"] = "https://steamusercontent-a.akamaihd.net/ugc/9481460801084540271/81770BACB89B63B59E1CD958E2458588805FC83D/",
    ["Rakdos Identity Buff - Showstopper's Encore"] = "https://cards.scryfall.io/large/front/c/c/cc6fd2d5-8eb2-4265-a1bf-d4ae635285af.jpg",
    ["One with death"] = "https://cards.scryfall.io/large/front/e/b/eb9963e0-a22a-4a64-aa0c-b7c67c5fee96.jpg",
    ["Compelling Madness"] = "https://cards.scryfall.io/large/front/7/7/772306d4-63d1-4d90-8c1b-4e4d6edb9aab.jpg",
    ["Fish Pond"] = "https://cards.scryfall.io/large/front/1/a/1a056620-f9a3-4643-bf4a-1b7cfe2fcb63.jpg",
    ["Construct's Salvation"] = "https://cards.scryfall.io/large/front/0/f/0f93e8ad-8ef6-4cf1-a664-d1477f1ebae4.jpg",
    ["Scorpion's Nest"] = "https://steamusercontent-a.akamaihd.net/ugc/13833641350492110911/A0EA0189C890735A0A44F612BA4731B72D45CFAB/",

    -- Tickets
    ["Vanguard Ticket"] = "https://cards.scryfall.io/large/front/8/f/8fb54be2-b9c5-4433-a198-4b935979718a.jpg",
    ["Color Combo Ticket"] = "https://cards.scryfall.io/large/front/8/4/84238335-e08c-421c-b9b9-70a679ff2967.jpg",
    ["Emblem Ticket"] = "https://cards.scryfall.io/large/front/3/2/327ddaaf-b6a7-4c80-9b38-5ab68181b3d6.jpg",
    ["Sol Ring Ticket"] = "https://cards.scryfall.io/large/front/e/e/ee6e5a35-fe21-4dee-b0ef-a8f2841511ad.jpg",
    ["Conspiracy Ticket"] = "https://cards.scryfall.io/large/front/1/6/167c6740-0625-4987-8fac-516aab564ca1.jpg",
    ["Trinket Ticket"] = "https://cards.scryfall.io/large/front/a/5/a53baf25-1782-427b-a9dd-fc9b8dc6444f.jpg",
}

local function findRewardDescByName(reward_name)
    for _, entry in ipairs(CRYPT_REWARDS) do
        if entry.name == reward_name then return entry.desc end
    end
    for _, entry in ipairs(ACHIEVEMENTS_LIST) do
        if entry.name == reward_name then return entry.desc end
    end
    for _, entry in ipairs(TICKETS_LIST) do
        if entry.name == reward_name then return entry.desc end
    end
    return nil
end

-- Spawn a reward token near this checker (requires image URL to be set)
local function spawnRewardToken(reward_name)
    local imageUrl = SPAWN_IMAGES[reward_name]
    if not imageUrl then
        return nil
    end

    -- deep copy to avoid mutating the base template
    local spawnData = JSON.decode(JSON.encode(BASE_SPAWN_TEMPLATE))

    -- Use anchored spawn position and match counter's rotation
    local spawnPos = getSpawnAnchor()
    local counterRot = self.getRotation()
    spawnData.Transform.posX = spawnPos.x
    spawnData.Transform.posY = spawnPos.y
    spawnData.Transform.posZ = spawnPos.z
    spawnData.Transform.rotX = counterRot.x
    spawnData.Transform.rotY = counterRot.y + 180
    spawnData.Transform.rotZ = counterRot.z

    -- apply texture in the data before spawn
    spawnData.CustomMesh.DiffuseURL = imageUrl

    local spawned = spawnObjectData({ data = spawnData })
    if spawned then
        spawned.setName(reward_name)
        local desc = findRewardDescByName(reward_name)
        if desc and desc ~= "" then
            spawned.setDescription(desc)
        end
        spawned.setLock(false)
    end
    return spawned
end

local function buildCaptureTicketName(captureName)
    return "[b]" .. CAPTURE_TICKET_LABEL .. "[/b]  " .. tostring(captureName or "")
end

local function buildCaptureNotes(captureName, imageUrl)
    return CAPTURE_NOTE_PREFIX .. "\n" .. tostring(captureName or "") .. "\n" .. tostring(imageUrl or "")
end

local function spawnCaptureToken(captureItem)
    if not captureItem then return nil end
    if captureItem.bagData then
        local bagData = buildCaptureBagSpawnData(captureItem)
        if bagData then
            local spawnPos = getSpawnAnchor()
            local counterRot = self.getRotation()
            bagData.Transform = bagData.Transform or {}
            bagData.Transform.posX = spawnPos.x
            bagData.Transform.posY = spawnPos.y
            bagData.Transform.posZ = spawnPos.z
            bagData.Transform.rotX = counterRot.x
            bagData.Transform.rotY = counterRot.y + 180
            bagData.Transform.rotZ = counterRot.z

            local spawned = spawnObjectData({ data = bagData })
            if spawned then
                spawned.setLock(false)
                return spawned
            end
        end
    end

    local imageUrl = captureItem.url or ""
    if imageUrl == "" and captureItem.bagData then
        imageUrl = extractCaptureFaceUrlFromPayload(captureItem.bagData)
    end
    if imageUrl == "" then
        return nil
    end

    local spawnData = JSON.decode(JSON.encode(BASE_SPAWN_TEMPLATE))
    local spawnPos = getSpawnAnchor()
    local counterRot = self.getRotation()
    spawnData.Transform.posX = spawnPos.x
    spawnData.Transform.posY = spawnPos.y
    spawnData.Transform.posZ = spawnPos.z
    spawnData.Transform.rotX = counterRot.x
    spawnData.Transform.rotY = counterRot.y + 180
    spawnData.Transform.rotZ = counterRot.z
    spawnData.CustomMesh.DiffuseURL = imageUrl

    local spawned = spawnObjectData({ data = spawnData })
    if spawned then
        spawned.setName(buildCaptureTicketName(captureItem.name))
        spawned.setGMNotes(buildCaptureNotes(captureItem.name, imageUrl))
        spawned.setLock(false)
    end
    return spawned
end

-- Rewards UI state
local uiVisible = false
local uiTab = "crypt" -- crypt | achievements | tickets | captures
local uiSelectedTab = nil
local uiSelectedId = nil
local PAGE_SIZE = 26

local uiSlotMap = { crypt = {}, achievements = {}, tickets = {}, captures = {} }

local function slotPrefixForTab(tabKey)
    if tabKey == "achievements" then return "ach_slot_" end
    if tabKey == "tickets" then return "ticket_slot_" end
    if tabKey == "captures" then return "capture_slot_" end
    return "crypt_slot_"
end

-- forward declaration (needed because onLoad calls it)
local uiRefresh

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseNumber(input)
    if input == nil then return nil end
    local s = tostring(input)
    s = trim(s)
    if s == "" then return nil end
    -- Allow friendly formats like "1,000" or "+100".
    s = s:gsub(",", "")
    s = s:gsub("%s+", "")
    return tonumber(s)
end

-- Basic signed number detection (single leading + or -)
local function parseSignedNumber(input)
    if input == nil then return nil end
    local s = tostring(input)
    s = trim(s)
    s = s:gsub(",", "")
    if s:match("^[%+%-]%d+$") then
        return tonumber(s)
    end
    return nil
end

-- Evaluate simple add/sub expressions like "200-50+5"; returns nil on invalid input.
local function evalSimpleExpression(input)
    if input == nil then return nil end
    local s = tostring(input)
    s = s:gsub(",", "")
    s = s:gsub("%s+", "")
    if s == "" then return nil end
    if not s:match("^[%+%-]?%d+([%+%-]%d+)*$") then return nil end

    local total = 0
    for num in s:gmatch("[%+%-]?%d+") do
        total = total + tonumber(num)
    end
    return total
end

local function urlEncode(str)
    if str == nil then return "" end
    str = tostring(str)
    str = string.gsub(str, "[^%w _%%%-%.~]", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    str = string.gsub(str, " ", "+")
    return str
end

local function resolveSteamName(player_color)
    if type(player_color) == "table" then
        local name = player_color.steam_name or player_color.name or player_color.color
        if name and name ~= "" then return name end
    end
    if type(player_color) == "string" then
        local p = Player[player_color]
        if p then
            local name = p.steam_name or p.name
            if name and name ~= "" then return name end
        end
    end
    return nil
end

-- Prefer a stable Steam ID for keys so name changes do not orphan data
local function resolvePlayerId(player_color)
    if type(player_color) == "table" then
        local sid = player_color.steam_id or player_color.steamId or player_color.steamid
        if sid and sid ~= "" then return tostring(sid) end
    end
    if type(player_color) == "string" then
        local p = Player[player_color]
        if p then
            local sid = p.steam_id or p.steamId or p.steamid
            if sid and sid ~= "" then return tostring(sid) end
        end
    end
    return nil
end

local function toId(name)
    local id = string.lower(name or "")
    id = id:gsub("[^%w]+", "_")
    id = id:gsub("^_+", ""):gsub("_+$", "")
    return id
end

local function entryName(entry)
    if type(entry) == "table" then return entry.name end
    return entry
end

local function entryDesc(entry)
    if type(entry) == "table" then return entry.desc end
    return nil
end

-- Normalize names for robust matching (handles curly quotes/dashes and spacing)
local function normalizeName(s)
    s = string.lower(s or "")
    -- Strip simple TTS-style bbcode tags like [b] [/b] [i] [/i]
    s = s:gsub("%[/?[biuBIU]%]", "")
    s = s:gsub("[“”]", '"')
    s = s:gsub("[’‘]", "'")
    -- Remove any straight or curly quotes so tokens with quotes still match
    s = s:gsub('"', ""):gsub("'", "")
    s = s:gsub("[–—]", "-")
    s = s:gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function stripBbcode(s)
    return (tostring(s or ""):gsub("%[/?[biuBIU]%]", ""))
end

local function parseCaptureTicketName(rawName)
    if rawName == nil then return nil end
    local plain = stripBbcode(rawName)
    local lower = string.lower(plain)
    local idx = lower:find(string.lower(CAPTURE_TICKET_LABEL), 1, true)
    if not idx then return nil end
    local after = plain:sub(idx + #CAPTURE_TICKET_LABEL)
    local name = trim(after)
    if name == "" then return nil end
    return name
end

local function parseCaptureNotes(notes)
    if notes == nil or notes == "" then return nil, nil end
    local header, nameLine, rest = tostring(notes):match("^([^\r\n]*)\r?\n([^\r\n]*)\r?\n?(.*)$")
    if header ~= CAPTURE_NOTE_PREFIX then return nil, nil end
    local urlLine = rest and rest:match("^([^\r\n]+)") or ""
    return trim(nameLine or ""), trim(urlLine or "")
end

local function sanitizeCaptureBagData(data)
    if type(data) ~= "table" then return nil end

    -- Keep already-minimized payloads as-is.
    if data._schema == "capture_payload_v1" then
        return data
    end

    -- Build minimal payload from full TTS object data.
    if data.Name == "Custom_Model_Infinite_Bag" and type(data.ContainedObjects) == "table" and #data.ContainedObjects > 0 then
        local minimalContained = JSON.decode(JSON.encode(data.ContainedObjects))
        for _, contained in ipairs(minimalContained) do
            if type(contained) == "table" then
                contained.GUID = nil
                contained.LuaScript = nil
                contained.LuaScriptState = nil
            end
        end
        return {
            _schema = "capture_payload_v1",
            Nickname = data.Nickname or "",
            DiffuseURL = (data.CustomMesh and data.CustomMesh.DiffuseURL) or "",
            ContainedObjects = minimalContained,
        }
    end

    -- Backward compatibility: compact/legacy payloads are preserved and handled at spawn time.
    if data._compact == true or data.Name == "Custom_Model_Infinite_Bag" then
        return data
    end

    return nil
end

extractCaptureFaceUrlFromPayload = function(payload)
    if type(payload) ~= "table" then return "" end

    if payload.DiffuseURL and payload.DiffuseURL ~= "" then
        return tostring(payload.DiffuseURL)
    end

    if payload.CustomMesh and payload.CustomMesh.DiffuseURL and payload.CustomMesh.DiffuseURL ~= "" then
        return tostring(payload.CustomMesh.DiffuseURL)
    end

    local contained = payload.ContainedObjects
    if type(contained) == "table" and #contained > 0 then
        local first = contained[1]
        if type(first) == "table" and type(first.CustomDeck) == "table" then
            for _, deck in pairs(first.CustomDeck) do
                if type(deck) == "table" and deck.FaceURL and deck.FaceURL ~= "" then
                    return tostring(deck.FaceURL)
                end
            end
        end
    end

    if type(payload.card) == "table" and payload.card.faceURL and payload.card.faceURL ~= "" then
        return tostring(payload.card.faceURL)
    end
    if type(payload.bag) == "table" and payload.bag.diffuseURL and payload.bag.diffuseURL ~= "" then
        return tostring(payload.bag.diffuseURL)
    end

    return ""
end

buildCaptureBagSpawnData = function(captureItem)
    if not captureItem or type(captureItem.bagData) ~= "table" then return nil end

    local payload = captureItem.bagData

    -- Minimal payload: plug data into a fixed full template.
    if payload._schema == "capture_payload_v1" then
        local contained = payload.ContainedObjects
        if type(contained) ~= "table" or #contained == 0 then return nil end

        local out = JSON.decode(JSON.encode(CAPTURE_BAG_TEMPLATE))
        local faceUrl = payload.DiffuseURL or captureItem.url or extractCaptureFaceUrlFromPayload(payload)
        out.Nickname = buildCaptureTicketName(captureItem.name)
        out.GMNotes = buildCaptureNotes(captureItem.name, faceUrl or "")
        out.CustomMesh.DiffuseURL = faceUrl or ""
        out.ContainedObjects = JSON.decode(JSON.encode(contained))
        return out
    end

    -- Legacy full payload remains supported.
    if payload.Name == "Custom_Model_Infinite_Bag" and type(payload.ContainedObjects) == "table" and #payload.ContainedObjects > 0 then
        local out = JSON.decode(JSON.encode(payload))
        local faceUrl = extractCaptureFaceUrlFromPayload(payload)
        out.Nickname = buildCaptureTicketName(captureItem.name)
        out.GMNotes = buildCaptureNotes(captureItem.name, faceUrl)
        if out.CustomMesh and (not out.CustomMesh.DiffuseURL or out.CustomMesh.DiffuseURL == "") then
            out.CustomMesh.DiffuseURL = faceUrl
        end
        return out
    end

    -- Backward-compatible conversion for compact payload shape.
    if payload._compact == true and type(payload.card) == "table" then
        local faceUrl = extractCaptureFaceUrlFromPayload(payload)
        local backUrl = payload.card.backURL or "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"
        local cardId = tonumber(payload.card.cardID) or 100
        if cardId < 100 then cardId = 100 end
        local deckSlot = math.floor(cardId / 100)
        if deckSlot < 1 then deckSlot = 1 end

        local contained = {
            {
                Name = "Card",
                Nickname = payload.card.nickname or tostring(captureItem.name or ""),
                Description = payload.card.description or "",
                Memo = payload.card.memo or "",
                CardID = cardId,
                HideWhenFaceDown = (payload.card.hideWhenFaceDown ~= false),
                Hands = (payload.card.hands ~= false),
                SidewaysCard = (payload.card.sideways == true),
                CustomDeck = {
                    [deckSlot] = {
                        FaceURL = faceUrl,
                        BackURL = backUrl,
                        NumWidth = payload.card.numWidth or 1,
                        NumHeight = payload.card.numHeight or 1,
                        BackIsHidden = (payload.card.backIsHidden ~= false),
                        UniqueBack = (payload.card.uniqueBack == true),
                        Type = payload.card.deckType or 0,
                    }
                }
            }
        }

        local out = JSON.decode(JSON.encode(CAPTURE_BAG_TEMPLATE))
        out.Nickname = buildCaptureTicketName(captureItem.name)
        out.GMNotes = buildCaptureNotes(captureItem.name, faceUrl)
        out.CustomMesh.DiffuseURL = faceUrl
        out.ContainedObjects = contained
        return out
    end

    return nil
end

local function extractCaptureBagData(obj)
    if not obj or not obj.getData then return nil end
    local ok, data = pcall(function() return obj.getData() end)
    if not ok or type(data) ~= "table" then return nil end
    if type(data.ContainedObjects) ~= "table" or #data.ContainedObjects == 0 then
        return nil
    end
    return sanitizeCaptureBagData(data)
end

local function tryRegisterCaptureFromObject(obj)
    if not obj then return false end
    local rawName = ""
    if obj.getName then
        local okName, nameValue = pcall(function() return obj.getName() end)
        if okName and nameValue then rawName = nameValue end
    end

    local gmNotes = ""
    if obj.getGMNotes then
        local okNotes, notesValue = pcall(function() return obj.getGMNotes() end)
        if okNotes and notesValue then gmNotes = notesValue end
    end

    local noteName, noteUrl = parseCaptureNotes(gmNotes)
    local captureName = (noteName and noteName ~= "" and noteName) or parseCaptureTicketName(rawName)
    if not captureName then return false end

    local bagData = extractCaptureBagData(obj)

    local imageUrl = noteUrl or ""
    if imageUrl == "" and obj.getCustomObject then
        local okCustom, custom = pcall(function() return obj.getCustomObject() end)
        if okCustom and custom then
            imageUrl = custom.diffuse or custom.face or ""
        end
    end

    local id = toId(captureName)
    state.captures[id] = {
        id = id,
        name = captureName,
        unlocked = true,
        url = imageUrl,
        bagData = bagData,
        desc = "Capture ticket for " .. captureName .. "."
    }
    return id
end

local function normalizeCapturesTable(captures)
    local out = {}
    if type(captures) ~= "table" then return out end
    for key, item in pairs(captures) do
        if type(item) == "table" then
            local name = item.name or item.capture_name or item.title or (type(key) == "string" and key or "")
            if name ~= "" then
                local id = item.id or toId(name)
                local url = item.url or item.imageUrl or item.image or ""
                local desc = item.desc or ("Capture ticket for " .. name .. ".")
                local bagData = sanitizeCaptureBagData(item.bagData or item.bag_data)
                if url == "" and bagData then
                    url = extractCaptureFaceUrlFromPayload(bagData)
                end
                out[id] = { id = id, name = name, unlocked = (item.unlocked ~= false), url = url, bagData = bagData, desc = desc }
            end
        elseif type(item) == "string" and type(key) == "string" then
            local name = item
            local id = toId(name)
            out[id] = { id = id, name = name, unlocked = true, url = "", desc = "Capture ticket for " .. name .. "." }
        end
    end
    return out
end

local function decodeCaptures(value)
    if value == nil then return {} end
    if type(value) == "string" then
        local ok, decoded = pcall(JSON.decode, value)
        if ok then return normalizeCapturesTable(decoded) end
        return {}
    end
    if type(value) == "table" then
        return normalizeCapturesTable(value)
    end
    return {}
end

local function serializeCaptures(captures)
    return JSON.encode(captures or {})
end

local function invalidateSaveBlobCache()
    saveBlobCache = nil
    saveBlobDirty = true
end

local function getCaptureIds(catTable)
    local ids = {}
    for id, _ in pairs(catTable or {}) do
        ids[#ids + 1] = id
    end
    table.sort(ids, function(a, b)
        local na = (catTable[a] and catTable[a].name) or a
        local nb = (catTable[b] and catTable[b].name) or b
        return string.lower(na) < string.lower(nb)
    end)
    return ids
end

local function getObjectGuidSafe(obj)
    if not obj then return nil end
    local ok, guid = pcall(function() return obj.getGUID() end)
    if not ok or not guid or guid == "" then return nil end
    return guid
end

local function markHandledObjectOnce(obj)
    local guid = getObjectGuidSafe(obj)
    if not guid then return false end
    if recentlyHandledGuids[guid] then
        return true
    end

    recentlyHandledGuids[guid] = true
    Wait.time(function()
        recentlyHandledGuids[guid] = nil
    end, 0.75)

    return false
end

local function safeDestructObject(obj)
    if not obj then return end
    Wait.frames(function()
        pcall(function()
            if obj.destruct then obj.destruct() end
        end)
    end, 1)
end

-- Wrap tooltip text so it stays readable inside TTS tooltips.
local function wrapTooltip(text, maxLen)
    if not text or maxLen == nil or maxLen <= 0 then return text end

    local wrapped = {}

    -- Preserve intentional newlines by wrapping each segment independently.
    for segment in (tostring(text) .. "\n"):gmatch("([^\n]*)\n") do
        local line = ""
        for word in segment:gmatch("%S+") do
            local newLen = #line + (#line > 0 and 1 or 0) + #word
            if newLen > maxLen then
                wrapped[#wrapped + 1] = line
                line = word
            else
                line = (#line == 0) and word or (line .. " " .. word)
            end
        end
        wrapped[#wrapped + 1] = line
    end

    return table.concat(wrapped, "\n")
end

-- Add readability tweaks for identity buffs: make each condition start on its own line.
local function formatIdentityDesc(name, desc)
    if not desc or not name then return desc end
    if not string.find(name, "Identity Buff", 1, true) then return desc end
    return desc:gsub("%s*If your commander", "\nIf your commander")
end

-- forward declaration (used by initAchievements before definition)
local initCategoryFromList

-- initialize achievements from placeholder list (to be replaced with real names later)
local function initAchievements()
    return initCategoryFromList(ACHIEVEMENTS_LIST)
end

local PLACEHOLDER_DESC = "(Description pending - update later)"

local function isPlaceholderDesc(desc, item)
    if desc == nil then return true end
    local s = trim(tostring(desc))
    if s == "" then return true end
    local lower = string.lower(s)
    if lower == string.lower(PLACEHOLDER_DESC) then return true end
    if string.find(lower, "description pending", 1, true) then return true end
    if item then
        if s == item.name or s == item.id then return true end
    end
    return false
end

local function ensurePlaceholderDescriptions(cat)
    if type(cat) ~= "table" then return end
    for _, item in pairs(cat) do
        if type(item) == "table" then
            if item.desc == nil or tostring(item.desc) == "" or item.desc == item.name or item.desc == item.id then
                item.desc = PLACEHOLDER_DESC
            end
        end
    end
end

initCategoryFromList = function(list)
    local t = {}
    for _, entry in ipairs(list or {}) do
        local name = entryName(entry)
        if name and name ~= "" then
            local id = toId(name)
            local desc = entryDesc(entry) or PLACEHOLDER_DESC
            t[id] = { id = id, name = name, unlocked = false, unlock_time = nil, desc = desc }
        end
    end
    return t
end

-- use generic category serialization for achievements as well

local function serializeCategory(cat)
    local parts = {}
    for id, item in pairs(cat or {}) do
        table.insert(parts, id .. ":" .. (item.unlocked and "1" or "0"))
    end
    return table.concat(parts, "|")
end

local function deserializeCategory(serialized, template)
    local out = template and initCategoryFromList(template) or {}
    if not serialized or serialized == "" then return out end
    for pair in string.gmatch(serialized, "[^|]+") do
        local id, status = string.match(pair, "([^:]+):(%d)")
        if id then
            if not out[id] then out[id] = { id = id, name = id, desc = PLACEHOLDER_DESC } end
            out[id].unlocked = (status == "1")
        end
    end
    ensurePlaceholderDescriptions(out)
    return out
end

local function mergeSavedCategory(savedTable, templateList)
    -- Always start with a complete template so new items appear in UI.
    local out = initCategoryFromList(templateList or {})
    if type(savedTable) ~= "table" then
        ensurePlaceholderDescriptions(out)
        return out
    end
    for id, savedItem in pairs(savedTable) do
        if out[id] and type(savedItem) == "table" then
            out[id].unlocked = (savedItem.unlocked == true)
            out[id].unlock_time = savedItem.unlock_time or out[id].unlock_time
            if not isPlaceholderDesc(savedItem.desc, savedItem) then
                out[id].desc = savedItem.desc
            end
        end
    end
    ensurePlaceholderDescriptions(out)
    return out
end

-- Fixed steps; description no longer affects button layout

local function clampValue(v)
    if v > MAX_VALUE then return MAX_VALUE end
    if v < 0 then return 0 end
    return v
end

local function formatDelta(n)
    if n > 0 then return "+" .. tostring(n) end
    return tostring(n)
end

local function colorForText()
    local tint = self.getColorTint()
    local light = (tint.r * 0.3 + tint.r * 0.3 * (1 - tint.g) + tint.g + tint.b * 0.4 > 0.925)
    return light and { 0, 0, 0, 100 } or { 1, 1, 1, 100 }
end

local function getNowSeconds()
    if Time and Time.time ~= nil then
        if type(Time.time) == "number" then
            return Time.time
        end
        if type(Time.time) == "function" then
            local ok, t = pcall(Time.time)
            if ok and type(t) == "number" then return t end
        end
    end
    return os.clock()
end

local function queueSyncSend(delaySeconds)
    local delay = tonumber(delaySeconds) or DEBOUNCE_SECONDS
    if delay < 0 then delay = 0 end
    if pendingHandle then Wait.stop(pendingHandle) pendingHandle = nil end
    pendingHandle = Wait.time(function()
        pendingHandle = nil
        sendData()
    end, delay)
end

local function requestSync(delaySeconds)
    syncDirty = true
    invalidateSaveBlobCache()
    if not localPlayerKey or not isSyncEnabled then return end
    queueSyncSend(delaySeconds or DEBOUNCE_SECONDS)
end

-- Everything is GUI-based for this object (no self.createButton / self.createInput).
local function setValueDirect(val)
    if val == nil then return end
    state.value = clampValue(val)
    self.setVar("currentValue", state.value)
    lastValue = state.value

    if self.UI then
        self.UI.setAttribute("ess_value", "text", tostring(state.value))
    elseif uiRefresh then
        uiRefresh()
    end

    requestSync(DEBOUNCE_SECONDS)
end

local function adjustValue(delta)
    local newVal = state.value + delta
    if newVal < 0 then newVal = 0 end
    setValueDirect(newVal)
end

local function registerDeltaHandler(delta, idx)
    local fn = "click_delta_" .. idx
    _G[fn] = function()
        adjustValue(delta)
    end
    return fn
end

-- Legacy 3D delta handlers are no longer used (GUI buttons call ui_ess_delta).

local function uiSetAttr(id, attr, value)
    if not self.UI then return end
    if not id or id == "" then return end
    self.UI.setAttribute(id, attr, tostring(value))
end

local function uiSetActive(id, isActive)
    uiSetAttr(id, "active", isActive and "true" or "false")
end

local function uiSetText(id, text)
    uiSetAttr(id, "text", text or "")
end

local function uiSetInteractable(id, isInteractable)
    uiSetAttr(id, "interactable", isInteractable and "true" or "false")
end

local function getCurrentCategoryTable()
    if uiTab == "achievements" then return state.achievements end
    if uiTab == "tickets" then return state.tickets end
    if uiTab == "captures" then return state.captures end
    return state.crypt
end

local function getOrderedIds(catTable)
    if uiTab == "captures" then
        return getCaptureIds(catTable)
    end
    local ids = {}
    local seen = {}

    local sourceList = CRYPT_REWARDS
    if uiTab == "achievements" then sourceList = ACHIEVEMENTS_LIST end
    if uiTab == "tickets" then sourceList = TICKETS_LIST end

    -- First, add in the explicit list order
    for _, entry in ipairs(sourceList or {}) do
        local name = entryName(entry)
        if name and name ~= "" then
            local id = toId(name)
            if catTable then
                if not catTable[id] then
                    catTable[id] = { id = id, name = name, unlocked = false, desc = entryDesc(entry) or PLACEHOLDER_DESC }
                elseif not catTable[id].desc or catTable[id].desc == PLACEHOLDER_DESC then
                    catTable[id].desc = entryDesc(entry) or catTable[id].desc or PLACEHOLDER_DESC
                end
                ids[#ids + 1] = id
                seen[id] = true
            end
        end
    end

    -- Then, append any unexpected ids (keeps compatibility with older saves)
    local extras = {}
    for id, _ in pairs(catTable or {}) do
        if not seen[id] then extras[#extras + 1] = id end
    end
    table.sort(extras)
    for _, id in ipairs(extras) do
        ids[#ids + 1] = id
    end

    return ids
end

uiRefresh = function()
    if not self.UI then return end

    -- Keep layout owned by XML. Lua only toggles visibility + content.
    uiSetActive("Navigation", uiVisible)
    uiSetActive("Unlockables", uiVisible)
    uiSetText("btn_show_rewards", uiVisible and "Hide Rewards" or "Show Rewards")

    -- Essence display
    uiSetText("ess_value", tostring(state.value))

    if not uiVisible then
        return
    end

    local catTable = getCurrentCategoryTable()
    local ids = getOrderedIds(catTable)

    local totalCount = #ids

    -- Page navigation (Host Helper-style)
    uiSetActive("Crypt Buffs", uiTab == "crypt")
    uiSetActive("Achievements", uiTab == "achievements")
    uiSetActive("Tickets", uiTab == "tickets")
    uiSetActive("Captures", uiTab == "captures")

    local activeBtn = "#66CC66|#66CC66|#66CC66|#66CC66"
    local inactiveBtn = "#666666|#666666|#666666|#666666"
    uiSetAttr("page_btn_crypt_buffs", "colors", uiTab == "crypt" and activeBtn or inactiveBtn)
    uiSetAttr("page_btn_achievements", "colors", uiTab == "achievements" and activeBtn or inactiveBtn)
    uiSetAttr("page_btn_tickets", "colors", uiTab == "tickets" and activeBtn or inactiveBtn)
    uiSetAttr("page_btn_captures", "colors", uiTab == "captures" and activeBtn or inactiveBtn)

    -- Slot population (per-tab panel slots)
    local prefix = slotPrefixForTab(uiTab)
    for i = 1, PAGE_SIZE do
        uiSlotMap[uiTab][i] = nil
        local slotId = prefix .. tostring(i)
        uiSetActive(slotId, false)
        uiSetText(slotId, "")
        uiSetAttr(slotId, "fontSize", "18")
        uiSetAttr(slotId, "alignment", "MiddleLeft")
        uiSetAttr(slotId, "textColor", "#FFFFFF")
        uiSetAttr(slotId, "tooltip", "")
        uiSetAttr(slotId, "colors", "#606060|#606060|#606060|#606060")
        uiSetAttr(slotId, "interactable", "true")
        -- Ensure click handler stays wired even if XML got modified
        uiSetAttr(slotId, "onClick", "ui_select_reward")
    end

    local slot = 1
    for idx = 1, totalCount do
        local rewardId = ids[idx]
        if rewardId then
            local item = catTable[rewardId]
            if item then
                if slot > PAGE_SIZE then break end
                uiSlotMap[uiTab][slot] = item.id

                local locked = (not item.unlocked)
                local isSelected = (uiSelectedTab == uiTab and uiSelectedId == item.id)

                -- State colors:
                -- - locked: subdued gray
                -- - unlocked: steady blue (flat to avoid toggle/rocker look)
                -- - selected: brighter blue
                local colors
                if isSelected then
                    colors = locked and "#1f3b66|#2a5aaa|#142a4a|#606060" or "#2563eb|#2563eb|#1d4ed8|#1d4ed8"
                else
                    colors = locked and "#505050|#606060|#404040|#606060" or "#1f4fbf|#1f4fbf|#1a3f99|#1a3f99"
                end
                local tooltipRaw
                local descText = item.desc and ("\n" .. formatIdentityDesc(item.name, item.desc)) or ""
                if item.unlocked then
                    tooltipRaw = (item.name or "") .. " [Unlocked]" .. descText
                else
                    tooltipRaw = (item.name or "") .. " [Locked]" .. descText
                end
                local tooltip = wrapTooltip(tooltipRaw, TOOLTIP_WRAP)

                local slotId = prefix .. tostring(slot)
                uiSetActive(slotId, true)
                uiSetText(slotId, item.name or "")
                uiSetAttr(slotId, "fontSize", "18")
                uiSetAttr(slotId, "alignment", "MiddleLeft")
                uiSetAttr(slotId, "textColor", "#FFFFFF")
                uiSetAttr(slotId, "colors", colors)
                uiSetAttr(slotId, "tooltip", tooltip or "")
                uiSetAttr(slotId, "interactable", "true")
                uiSetAttr(slotId, "onClick", "ui_select_reward")

                slot = slot + 1
            end
        end
    end

    -- Description
    local selectedText = "Select an item to view its description."
    if uiSelectedTab == uiTab and uiSelectedId and catTable[uiSelectedId] then
        local item = catTable[uiSelectedId]
        if item.unlocked then
            selectedText = item.desc or item.name
        else
            selectedText = (item.name or "") .. " (Locked)"
        end
    end
    uiSetText("bsq_desc_text", selectedText)
end

local function uiIsReady()
    if not self.UI then return false end
    local ok, v = pcall(function()
        return self.UI.getAttribute("btn_show_rewards", "text")
    end)
    return ok and v ~= nil
end

local function uiRefreshWhenReady(attempt)
    attempt = attempt or 1
    if uiIsReady() then
        if uiRefresh then uiRefresh() end
        return
    end
    if attempt >= 15 then
        -- Avoid infinite looping if the object's XML UI is missing/not applied.
        return
    end
    Wait.time(function()
        uiRefreshWhenReady(attempt + 1)
    end, 0.1)
end

function resetValue()
    setValueDirect(0)
end

-- unlock is managed via token drop only; no click-to-unlock

-- Description no longer alters steps

function onLoad(saved)
    invalidateSaveBlobCache()
    self.interactable = true
    self.setVar("whatIAm", "Counter")
    self.setVar("Supports_getTotalValue", false)
    self.setVar("Supports_getMaxTotalValue", false)
    self.setVar("Supports_getMaxSingleValue", false)
    self.setVar("whatIAmSpecfically", "[finmod]X Digit Counter with Achievements")

    if saved and saved ~= "" then
        local ok, data = pcall(JSON.decode, saved)
        if ok and type(data) == "table" then
            state.value = clampValue(data.value or 0)
            state.achievements = mergeSavedCategory(data.achievements, ACHIEVEMENTS_LIST)
            state.crypt = mergeSavedCategory(data.crypt, CRYPT_REWARDS)
            state.tickets = mergeSavedCategory(data.tickets, TICKETS_LIST)
            state.captures = decodeCaptures(data.captures)
            if data.playerKey and data.playerKey ~= "" then
                localPlayerKey = data.playerKey
            end
        end
    else
        state.achievements = initCategoryFromList(ACHIEVEMENTS_LIST)
        state.crypt = initCategoryFromList(CRYPT_REWARDS)
        state.tickets = initCategoryFromList(TICKETS_LIST)
        state.captures = {}
    end

    -- Keep the watcher/sync source-of-truth in sync with loaded value
    self.setVar("currentValue", state.value)

    -- Everything is handled via GUI
    -- Start collapsed (matches XML default active="false" for rewards UI).
    uiVisible = false
    uiTab = "crypt"
    uiSelectedTab = nil
    uiSelectedId = nil
    -- initialize sync
    lastValue = state.value
    lastAchievements = serializeCategory(state.achievements)
    lastName = self.getName()
    lastDescription = self.getDescription()
    lastCrypt = serializeCategory(state.crypt)
    lastTickets = serializeCategory(state.tickets)
    lastCaptures = serializeCaptures(state.captures)
    -- If this object already has a saved playerKey (spawned from a player's saved objects),
    -- pull the latest server state immediately so the UI is up to date before interaction.
    if localPlayerKey then
        fetchSavedValue()
    end

    -- Render initial UI state (XML lives on the object; Lua only updates values)
    uiRefreshWhenReady()
end

function onSave()
    if not saveBlobDirty and saveBlobCache then
        return saveBlobCache
    end

    saveBlobCache = JSON.encode({
        value = state.value,
        achievements = state.achievements,
        crypt = state.crypt,
        tickets = state.tickets,
        captures = state.captures,
        playerKey = localPlayerKey
    })
    saveBlobDirty = false
    return saveBlobCache
end

function onPickUp(player_color)
    local desc = self.getDescription() or ""
    local pname = resolveSteamName(player_color)
    local pid = resolvePlayerId(player_color)

    -- If this was a fresh pull from the bag, claim/rename and strip the marker
    if string.find(desc, BAG_MARKER, 1, true) then
        if pname then
            self.setName(pname)
            lastName = pname
        end

        local cleaned = trim(desc:gsub("%[from%-bag%]", ""))
        self.setDescription(cleaned)
        lastDescription = cleaned
    end

    local currentName = trim(self.getName() or "")
    local keyBase = pid or pname

    -- Only claim a key if we don't already have one AND the object already has a name
    -- (prevents generating a key for unnamed/placeholder objects).
    if not localPlayerKey and keyBase and currentName ~= "" then
        localPlayerKey = keyBase .. "_Essence"
        invalidateSaveBlobCache()
    end

    -- Fetch saved value before marking as changed (handles fresh pulls and named objects)
    if localPlayerKey and not isSyncEnabled then
        fetchSavedValue()
        return
    end

    -- Existing counters without the marker still need a key to sync; fetch if we just set one
    if localPlayerKey and not isSyncEnabled then
        fetchSavedValue()
    end
end

function onNameChanged(new_name)
    lastName = new_name
    requestSync(DEBOUNCE_SECONDS)
end

function onDescriptionChanged(new_desc)
    lastDescription = new_desc
    requestSync(DEBOUNCE_SECONDS)
end

function startChangeWatcher()
    return
end

function fetchSavedValue()
    if not localPlayerKey then
        isSyncEnabled = true
        return
    end
    local url = WEB_URL .. "?playerKey=" .. urlEncode(localPlayerKey)

    WebRequest.get(url, function(req)
        if req.is_error then
            isSyncEnabled = true
            return
        end

        if req.text == nil or req.text == "" then
            isSyncEnabled = true
            if localPlayerKey then
                sendData(true)
            end
            return
        end

        local ok, data = pcall(JSON.decode, req.text)
        if not ok then
            isSyncEnabled = true
            return
        end

        if data.value ~= nil then
            state.value = clampValue(parseNumber(data.value) or 0)
            self.setVar("currentValue", state.value)
            lastValue = state.value
            print("[" .. self.getName() .. "] Loaded Essence: " .. state.value)
        end

        if data.name and tostring(data.name) ~= "" then
            self.setName(data.name)
            lastName = data.name
        end

        if data.description ~= nil then
            local desc = trim(tostring(data.description))
            self.setDescription(desc)
            lastDescription = desc
        end
        
        if data.achievements then
            state.achievements = deserializeCategory(data.achievements, ACHIEVEMENTS_LIST)
            lastAchievements = data.achievements
        end

        if data.crypt then
            state.crypt = deserializeCategory(data.crypt, CRYPT_REWARDS)
            lastCrypt = data.crypt
        end
        if data.tickets then
            state.tickets = deserializeCategory(data.tickets, TICKETS_LIST)
            lastTickets = data.tickets
        end
        if data.captures then
            state.captures = decodeCaptures(data.captures)
            lastCaptures = serializeCaptures(state.captures)
        end

        invalidateSaveBlobCache()

        syncDirty = false

        ensurePlaceholderDescriptions(state.achievements)
        ensurePlaceholderDescriptions(state.crypt)
        ensurePlaceholderDescriptions(state.tickets)

        uiRefreshWhenReady()
        
        isSyncEnabled = true
    end)
end

function sendData(force)
    if not localPlayerKey then
        return
    end

    if not force and not syncDirty then
        return
    end

    if syncInFlight then
        syncQueued = true
        return
    end

    local desc = trim(self.getDescription() or "")
    local payload = {
        playerKey = localPlayerKey,
        timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        name = self.getName(),
        description = desc,
        value = state.value,
        achievements = serializeCategory(state.achievements),
        crypt = serializeCategory(state.crypt),
        tickets = serializeCategory(state.tickets),
        captures = serializeCaptures(state.captures)
    }

    local signature = table.concat({
        tostring(payload.playerKey or ""),
        tostring(payload.name or ""),
        tostring(payload.description or ""),
        tostring(payload.value or ""),
        tostring(payload.achievements or ""),
        tostring(payload.crypt or ""),
        tostring(payload.tickets or ""),
        tostring(payload.captures or "")
    }, "\30")

    if signature == lastSyncSignature then
        syncDirty = false
        return
    end

    local now = getNowSeconds()
    local elapsed = now - (lastSyncSentAt or 0)
    if elapsed < MIN_SYNC_INTERVAL_SECONDS then
        queueSyncSend(MIN_SYNC_INTERVAL_SECONDS - elapsed)
        return
    end

    lastName = payload.name
    lastDescription = payload.description
    lastAchievements = payload.achievements
    lastCrypt = payload.crypt
    lastTickets = payload.tickets
    lastCaptures = payload.captures
    lastSyncSignature = signature
    lastSyncSentAt = now
    syncInFlight = true

    WebRequest.post(WEB_URL, JSON.encode(payload), function(req)
        syncInFlight = false
        if req.is_error then
            lastSyncSignature = ""
            syncDirty = true
            if syncQueued then
                syncQueued = false
                queueSyncSend(DEBOUNCE_SECONDS)
            end
            return
        end
        syncDirty = false
        if syncQueued then
            syncQueued = false
            queueSyncSend(DEBOUNCE_SECONDS)
        end
    end, { ["Content-Type"] = "application/json" })
end

-- Optional: Token drop detection (requires scripting zone setup)
function onObjectEnterScriptingZone(zone, object)
    if zone ~= self then return end
    if not object then return end
    
    local obj_name = object.getName() or ""
    local obj_norm = normalizeName(obj_name)

    -- Crypt rewards: exact name match (case-insensitive)
    for _, entry in ipairs(CRYPT_REWARDS) do
        local name = entryName(entry)
        if name and obj_norm == normalizeName(name) then
            local id = toId(name)
            if state.crypt[id] and not state.crypt[id].unlocked then
                if markHandledObjectOnce(object) then return end
                state.crypt[id].unlocked = true
                print("[" .. self.getName() .. "] Unlocked Crypt: " .. name)
                safeDestructObject(object)
                uiVisible = true
                uiTab = "crypt"
                uiSelectedTab = "crypt"
                uiSelectedId = id
                -- Reflect in UI and sync
                uiRefreshWhenReady()
                requestSync(DEBOUNCE_SECONDS)
            end
            return
        end
    end

    -- Achievements: match by exact name too (placeholders)
    for _, entry in ipairs(ACHIEVEMENTS_LIST) do
        local name = entryName(entry)
        if name and obj_norm == normalizeName(name) then
            local id = toId(name)
            if state.achievements[id] and not state.achievements[id].unlocked then
                if markHandledObjectOnce(object) then return end
                state.achievements[id].unlocked = true
                print("[" .. self.getName() .. "] Unlocked Achievement: " .. name)
                safeDestructObject(object)
                uiVisible = true
                uiTab = "achievements"
                uiSelectedTab = "achievements"
                uiSelectedId = id
                if uiRefresh then uiRefresh() end
                requestSync(DEBOUNCE_SECONDS)
            end
            return
        end
    end

    -- Tickets: exact name match
    for _, entry in ipairs(TICKETS_LIST) do
        local name = entryName(entry)
        if name and obj_norm == normalizeName(name) then
            local id = toId(name)
            if state.tickets[id] and not state.tickets[id].unlocked then
                if markHandledObjectOnce(object) then return end
                state.tickets[id].unlocked = true
                print("[" .. self.getName() .. "] Unlocked Ticket: " .. name)
                safeDestructObject(object)
                uiVisible = true
                uiTab = "tickets"
                uiSelectedTab = "tickets"
                uiSelectedId = id
                if uiRefresh then uiRefresh() end
                requestSync(DEBOUNCE_SECONDS)
            end
            return
        end
    end
end

-- Unlocks when an object is dropped onto/near the Block Square
function onObjectDropped(player_color, dropped_object)
    if not dropped_object then return end
    if not dropped_object.getPosition then return end
    local okPos, pos = pcall(function() return dropped_object.getPosition() end)
    if not okPos or type(pos) ~= "table" then return end
    local my = self.getPosition()
    local dx = pos.x - my.x
    local dz = pos.z - my.z
    local dist2 = dx*dx + dz*dz
    -- radius threshold ~1.2 world units around the block center
    if dist2 > (1.2*1.2) then return end

    local obj_name = ""
    if dropped_object.getName then
        local okName, nameValue = pcall(function() return dropped_object.getName() end)
        if okName and nameValue then obj_name = nameValue end
    end
    local obj_norm = normalizeName(obj_name)

    local okCapture, captureId = pcall(function()
        return tryRegisterCaptureFromObject(dropped_object)
    end)
    if not okCapture then
        return
    end
    if captureId then
        if markHandledObjectOnce(dropped_object) then return end
        safeDestructObject(dropped_object)
        uiVisible = true
        uiTab = "captures"
        uiSelectedTab = "captures"
        uiSelectedId = captureId
        uiRefreshWhenReady()
        requestSync(DEBOUNCE_SECONDS)
        return
    end

    for _, entry in ipairs(CRYPT_REWARDS) do
        local name = entryName(entry)
        if name and obj_norm == normalizeName(name) then
            local id = toId(name)
            if state.crypt[id] and not state.crypt[id].unlocked then
                if markHandledObjectOnce(dropped_object) then return end
                state.crypt[id].unlocked = true
                safeDestructObject(dropped_object)
                uiVisible = true
                uiTab = "crypt"
                uiSelectedTab = "crypt"
                uiSelectedId = id
                uiRefreshWhenReady()
                requestSync(DEBOUNCE_SECONDS)
            end
            return
        end
    end

    -- Achievements exact match (placeholders until real names provided)
    for _, entry in ipairs(ACHIEVEMENTS_LIST) do
        local name = entryName(entry)
        if name and obj_norm == normalizeName(name) then
            local id = toId(name)
            if state.achievements[id] and not state.achievements[id].unlocked then
                if markHandledObjectOnce(dropped_object) then return end
                state.achievements[id].unlocked = true
                safeDestructObject(dropped_object)
                uiVisible = true
                uiTab = "achievements"
                uiSelectedTab = "achievements"
                uiSelectedId = id
                uiRefreshWhenReady()
                requestSync(DEBOUNCE_SECONDS)
            end
            return
        end
    end

    -- Tickets exact match
    for _, entry in ipairs(TICKETS_LIST) do
        local name = entryName(entry)
        if name and obj_norm == normalizeName(name) then
            local id = toId(name)
            if state.tickets[id] and not state.tickets[id].unlocked then
                if markHandledObjectOnce(dropped_object) then return end
                state.tickets[id].unlocked = true
                safeDestructObject(dropped_object)
                uiVisible = true
                uiTab = "tickets"
                uiSelectedTab = "tickets"
                uiSelectedId = id
                uiRefreshWhenReady()
                requestSync(DEBOUNCE_SECONDS)
            end
            return
        end
    end
end

-- UI structure is defined in the object's XML; Lua only updates values/attributes.

function ui_ess_clear(_, _)
    setValueDirect(0)
end

function ui_set_essence(_, value, _)
    local raw = tostring(value or "")

    -- If this is a simple signed number ("+5" / "-10"), treat it as a delta
    local signedNum = parseSignedNumber(raw)
    if signedNum ~= nil then
        adjustValue(signedNum)
        return
    end

    -- If it's a plain number, set it directly (keeps the old absolute-set behavior)
    local plainNum = parseNumber(raw)
    if plainNum ~= nil then
        setValueDirect(plainNum)
        return
    end

    -- Otherwise allow simple math expressions (e.g., "200-50" -> 150)
    local exprValue = evalSimpleExpression(raw)
    if exprValue == nil then
        uiRefreshWhenReady()
        return
    end

    setValueDirect(exprValue)
end

function ui_ess_delta(_, _, id)
    local deltaStr = string.match(tostring(id or ""), "^ess_delta_([%-0-9]+)$")
    local delta = tonumber(deltaStr)
    if not delta then return end
    adjustValue(delta)
end

function ui_tab_crypt(_, _)
    uiTab = "crypt"
    uiSelectedTab = uiTab
    uiSelectedId = nil
    uiRefreshWhenReady()
end
function ui_tab_achievements(_, _)
    uiTab = "achievements"
    uiSelectedTab = uiTab
    uiSelectedId = nil
    uiRefreshWhenReady()
end
function ui_tab_tickets(_, _)
    uiTab = "tickets"
    uiSelectedTab = uiTab
    uiSelectedId = nil
    uiRefreshWhenReady()
end
function ui_tab_captures(_, _)
    uiTab = "captures"
    uiSelectedTab = uiTab
    uiSelectedId = nil
    uiRefreshWhenReady()
end

local function set_rewards_tab_internal(tabKey)
    if tabKey ~= "crypt" and tabKey ~= "achievements" and tabKey ~= "tickets" and tabKey ~= "captures" then return end
    uiTab = tabKey
    uiSelectedTab = uiTab
    uiSelectedId = nil
end

function ui_nav_rewards_tab(_, _, id)
    -- Host Helper pattern: infer target from element id
    local tabKey = tostring(id or ""):match("^tab_(%w+)$")
    if tabKey ~= "crypt" and tabKey ~= "achievements" and tabKey ~= "tickets" and tabKey ~= "captures" then return end
    set_rewards_tab_internal(tabKey)
    uiRefreshWhenReady()
end

-- Back-compat alias (older XML versions)
function ui_tab_select(player, value, id)
    ui_nav_rewards_tab(player, value, id)
end
function ui_prev_page(_, _)
    -- Paging removed; kept for back-compat.
end
function ui_next_page(_, _)
    -- Paging removed; kept for back-compat.
end

function ui_toggle_rewards(_, _)
    uiVisible = not uiVisible
    uiRefreshWhenReady()
end

function ui_select_reward(_, _, id)
    -- Normalize id to avoid trailing/leading whitespace issues
    local rawId = tostring(id or "")
    rawId = rawId:gsub("^%s+", ""):gsub("%s+$", "")

    -- Accept matches even if there are stray characters around
    local tid, slotNumStr = string.match(rawId, "(crypt|ach|ticket|capture)_slot_(%d+)")
    local slotNum = tonumber(slotNumStr)

    -- Fallback parsing if pattern failed (handles unexpected characters/format)
    if not tid or not slotNum then
        local fallbackTid
        local fallbackSlot
        fallbackSlot = tonumber(string.match(rawId, "ticket_slot_(%d+)") or string.match(rawId, "ach_slot_(%d+)") or string.match(rawId, "crypt_slot_(%d+)") or string.match(rawId, "capture_slot_(%d+)"))
        if rawId:find("ticket_slot_", 1, true) then
            fallbackTid = "ticket"
        elseif rawId:find("ach_slot_", 1, true) then
            fallbackTid = "ach"
        elseif rawId:find("crypt_slot_", 1, true) then
            fallbackTid = "crypt"
        elseif rawId:find("capture_slot_", 1, true) then
            fallbackTid = "capture"
        end

        if fallbackTid and fallbackSlot then
            tid = fallbackTid
            slotNum = fallbackSlot
            slotNumStr = tostring(fallbackSlot)
        else
            return
        end
    end

    local tabKey = (tid == "crypt" and "crypt") or (tid == "ach" and "achievements") or (tid == "capture" and "captures") or "tickets"
    local rewardId
    if tabKey == "captures" then
        local captureIds = getCaptureIds(state.captures or {})
        rewardId = captureIds[slotNum]
    else
        rewardId = uiSlotMap[tabKey] and uiSlotMap[tabKey][slotNum] or nil
    end

    -- Fallback: if mapping is missing, derive by slot index
    if not rewardId then
        if tabKey == "captures" then
            local captureIds = getCaptureIds(state.captures or {})
            rewardId = captureIds[slotNum]
            if not rewardId then
                return
            end
        else
            local sourceList = (tabKey == "crypt" and CRYPT_REWARDS)
                or (tabKey == "achievements" and ACHIEVEMENTS_LIST)
                or TICKETS_LIST
            local entry = sourceList and sourceList[slotNum] or nil
            if entry and entry.name then
                rewardId = toId(entry.name)
                -- Ensure the table exists and has the item so downstream logic works
                local targetTable = (tabKey == "crypt" and state.crypt)
                    or (tabKey == "achievements" and state.achievements)
                    or state.tickets
                if targetTable and not targetTable[rewardId] then
                    targetTable[rewardId] = { id = rewardId, name = entry.name, unlocked = false, desc = entry.desc or PLACEHOLDER_DESC }
                end
            else
                return
            end
        end
    end
    if not rewardId then
        return
    end

    local catTable = (tabKey == "crypt" and state.crypt)
        or (tabKey == "achievements" and state.achievements)
        or (tabKey == "captures" and state.captures)
        or state.tickets
    local item = catTable and catTable[rewardId] or nil

    if not item then
        return
    end

    -- Spawn only if unlocked
    if item.unlocked then
        if tabKey == "captures" then
            local okSpawn, spawned = pcall(function()
                return spawnCaptureToken(item)
            end)
            if not okSpawn then
                print("[" .. self.getName() .. "] Capture spawn error: " .. tostring(item.name))
            elseif not spawned then
                print("[" .. self.getName() .. "] Capture spawn failed: " .. tostring(item.name))
            end
        else
            spawnRewardToken(item.name)
        end
    end

    uiSelectedTab = tabKey
    uiSelectedId = rewardId
    uiRefreshWhenReady()
end

-- Host Helper-style page navigation callback
function ui_nav_page(_, _, id)
    local page = tostring(id or ""):match("^page_btn_(%w+)$")
    if page == "crypt_buffs" then
        uiTab = "crypt"
    elseif page == "achievements" then
        uiTab = "achievements"
    elseif page == "tickets" then
        uiTab = "tickets"
    elseif page == "captures" then
        uiTab = "captures"
    else
        return
    end
    uiSelectedTab = uiTab
    uiSelectedId = nil
    uiRefreshWhenReady()
end

-- Initialize UI after load
function onDestroy()
    watcherActive = false
    if watcherHandle then
        Wait.stop(watcherHandle)
        watcherHandle = nil
    end
    if pendingHandle then
        Wait.stop(pendingHandle)
        pendingHandle = nil
    end

    if self.UI and self.UI.hide then
        self.UI.hide("Navigation")
        self.UI.hide("Unlockables")
    end
end