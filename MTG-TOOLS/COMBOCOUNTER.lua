--==============================================================================
-- MTGRoguelikeSpawner V2 — Pack shop + Mystery engine + Auto-splay
--==============================================================================

--Credits to Sirin For the Original Essence Counter

backURL    = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
backendURL = 'http://api.mtginfo.org'
SCRYFALL_SEARCH_URL = 'https://api.scryfall.com/cards/search'
cardStackName        = 'Mystery Booster'
cardStackDescription = ''
nBooster = 0
boosterDecks = {}
local BOOSTER_BUILD_TIMEOUT = 25
local RANDOM_BUILD_ENDPOINT_PATH = '/random/build'
local RANDOM_LIST_ENDPOINT_PATH = '/random'
local SEARCH_ENDPOINT_PATH = '/search'
local BACKEND_POOL_COUNT_LIMIT = 1000

AUTOSPLAY_SPAWN_DELAY_FRAMES = 10
POOL_CHECK_DEBOUNCE_SECONDS  = 0.7

TTS_INPUT_VALIDATION_INT     = 2
TTS_INPUT_VALIDATION_NONE    = 1
TTS_INPUT_ALIGN_RIGHT        = 3

CAPTURE_BASE_COST  = 500
CAPTURE_PRICE_STEP = 250
DUPLICATE_REWARD_ESSENCE = 250
CRYPT_BOSS_ESSENCE = 500

LABEL_BG = {0.92, 0.88, 0.78}

alphabetize  = false
uiColor      = {0, 1, 0}
maxRowCol    = 20
spacer       = 0.01
flip         = true
heightOffset = 0

XP_MIN = 0
SPAWNER_TAG = "MTGSpawner"
MASTER_TAG = "MTGMasterController"
MASTER_REFRESH_HOOKS = {"spawnerXPChanged", "spawnerEssenceChanged", "refreshSlots", "refreshSpawners"}

PACK_COSTS = {
  mystery  = 5,
  identity = 10,
  pro      = 20,
  mythic   = 50,
  otag     = 75,
}

-- Town action costs
HOST_ACTIONS_TAG = "MTGHostTownActions"
UPGRADE_COST     = 25
AUGMENT_COST     = 50
GUILD_ROLL_COST  = 10

-- Building usage limits per town
BUILDING_LIMITS = {
  Portal    = 1,
  Cathedral = 1,
  Bazaar    = 2,
  Bank      = 1,
  Tavern    = 1,
  -- Merchant, Mystic, Guild, Blacksmith: no limit (XP-gated instead)
}

-- Minimum unique cards the backend pool must contain before a purchase is allowed.
-- Packs not listed here skip the check entirely.
PACK_MIN_POOL = {
  pro    = 45,
  mythic = 30,
  otag   = 15,
}

TERM_TYPES = {"type", "cmc", "keyword"}
TERM_OPS = {
  type    = {":", "="},
  cmc     = {"=", "<", "<=", ">", ">="},
  keyword = {":"},
}
PORTAL_TERM_TYPES = {"type", "keyword"}
PORTAL_TERM_OPS   = { type = {":", "="}, keyword = {":"} }

xp = 0
-- Edit note: Default auto-splay layout updated to 8 columns by 3 rows. Signed, Sirin.
settings = {
  cardsPerPack = 15,
  autoSplay    = false,
  splayCols    = 8,
  splayRows    = 3,
}
currentScreen = "shop"
activePack    = nil
packInput = {
  colors    = {W=false, U=false, B=false, R=false, G=false, C=false},
  colorOp   = ":",
  termType1 = 1,
  termOp1   = 1,
  termValue1 = "",
  termType2 = 1,
  termOp2   = 1,
  termValue2 = "",
  otag      = "",
}
portalInput = { termType=1, termOp=1, termValue="", count=5 }
portalTravelerFungalLichActive = false
portalCountLabelButtonIndex = nil
portalProjectedLabelButtonIndex = nil
pendingMysticCard = nil
pendingMysticCMC  = nil
pendingBazaarCard = nil
pendingBazaarMode = nil
pendingBazaarCMC  = nil
uiButtonIndices = {}
uiInputIndices  = {}
xpDisplayIndex      = nil
essenceDisplayIndex = nil
poolSizeButtonIndex = nil   -- index of the live pool-size label on the input screen
poolCheckHandle     = nil   -- Wait handle for debounced pool check
splayState = {}

-- Building bonus uses (persist across towns)
bonusBuildingUsesGeneric = 0      -- Generic bonus use for any building
bonusBuildingUsesByKey   = {}     -- Bonus uses per specific building {Cathedral=1, Bazaar=2, ...}
pendingCashoutCard       = nil    -- Card awaiting redemption as bonus use

-- Building uses this town (reset each town advance)
buildingUsesThisTown     = {}     -- Remaining uses per building {Cathedral=1, Bazaar=2, ...}

MAX_VALUE = 999999
WEB_URL = "https://script.google.com/macros/s/AKfycbwIVox39JBPeMswdPtZHfELAH7XJFo4Ih-ib-BPqR7NDACaxapoO5kqcC1xGwwrS3EX/exec"
DEBOUNCE_SECONDS = 3.0
MIN_SYNC_INTERVAL_SECONDS = 8.0
BAG_MARKER = "[from-bag]"
CAPTURE_NOTE_PREFIX = "CAPTURE_TICKET"
CAPTURE_NOTE_PREFIX_LEGACY = "CAPTURE_TICKET_V1"
CAPTURE_TICKET_LABEL = "Capture Ticket:"
PAGE_SIZE = 6
ESSENCE_TABS = {"crypt", "achievements", "tickets", "brands", "captures"}
ESSENCE_TAB_LABELS = {
  crypt        = "Crypt",
  achievements = "Achievements",
  tickets      = "Tickets",
  brands       = "Brands",
  captures     = "Captures",
}

CRYPT_REWARDS = {
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
    { name = "Unearthly Reach", desc = "It gives either an additional Upkeep or End Step.\nUnlock: Beat Tormod and Ravos." },
    { name = "Momentum Engine", desc = "Until end of turn, you don't lose unspent mana as steps and phases end.\nUnlock: Beat Yurlok of Scorch Thrash." },
    { name = "Eternal Servitude", desc = "Once each turn, whenever a creature you control becomes the target of a spell, it phases out.\n\nWhenever a creature you control phases in, create a tapped 1/1 white Spirit creature token.\nUnlock: Beat King of the Oathbreakers." },
    { name = "Dark Beginnings", desc = "Your commander is augmented after deck creation.\nUnlock: Beat Maha, Its Feathers Night." },
    { name = "The Chosen Path", desc = "Once per encounter, choose one:\n\n- {2}: Search your library for a basic land card, put that card onto the battlefield tapped, then shuffle.\n- Look at the top six cards of your library. You may reveal a creature card from among them and put it into your hand. Put the rest on the bottom of your library in any order.\n\nUnlock: Beat Loot, Exuberant Explorer." },
    { name = "Paragon Adornments", desc = "Equipment costs {1} less to cast.\nEquipment costs {1} less to equip.\nUnlock: Beat Reyav, Master Smith." },
    { name = "Lucky Pull", desc = "Whenever one or more creatures you control deal combat damage to an opponent, draw a card.\n\n(Beat Jin Sakai, Ghost of Tsushima)" },
    { name = "Upgrades, People, Upgrades", desc = "You may activate abilities of creatures you control as though those creatures had haste.\n\n(Defeat Iron Spider, Stark Upgrade)" },
}

ACHIEVEMENTS_LIST = {
    { name = "Happy Fun Land", desc = "At the beginning of the game, spawn 5 random attractions to create your attraction deck.\nUnlock: Beat a crypt fight with attractions." },
    { name = "Nature's Blessing", desc = "Instead of gaining dual lands during deck creation, you may instead get triomes.\nUnlock: Beat a crypt with 50 or more lands in your deck." },
    { name = "Dog's Best Friend", desc = "At the beginning of the game, before deckbuilding, gain a random companion. You must adhere to the companion rules when deckbuilding. Free mulligan cards must also follow your companion.\nUnlock: Beat a crypt fight with a companion in your deck." },
    { name = "Orzhov Identity Buff - Tithe and Toil", desc = "If your commander is White: Once per turn, when a token enters the battlefield under your control, you may populate 1. \nIf your commander is Black: Once per turn, when a non-token creature you control dies, you may create a 1/1 Black Zombie.\nUnlock: Beat a crypt fight where all players' commander identities were either White, Black, or Orzhov." },
    { name = "Simic Identity Buff - Adaptive Pattern", desc = "If your commander is Blue: Once per turn, when you draw your second card this turn, you may put a +1/+1 counter on a creature you control. \nIf your commander is Green: Once per turn, when a +1/+1 counter is placed on a creature you control, you may draw a card.\nUnlock: Beat a crypt fight where all players' commander identities were either Green, Blue, or Simic." },
    { name = "Azorius Identity Buff - Law of Efficiency", desc = "If your commander is White: Once per turn, when you cast a spell during another player's turn, you may gain 1 life. \nIf your commander is Blue: Once per turn, when you counter a spell or ability, you may draw a card.\nUnlock: Beat a crypt fight where all players' commander identities were either White, Blue, or Azorius." },
    { name = "Boros Identity Buff - Charge of Conviction", desc = "If your commander is White: Once per turn, when one or more creatures you control attacks, you may untap one creature you control. \nIf your commander is Red: Once per turn, when a creature you control attacks alone, you may give it +2/+0 until end of turn.\nUnlock: Beat a crypt fight where all players' commander identities were either Red, White, or Boros." },
    { name = "Changeling's Land Form", desc = "After you draw your opening hand and finish mulligans, you may put a Random Basic Land card from outside the game into your hand.\n(Beat a crypt fight with a Changeling Commander)" },
    { name = "Golgari Identity Buff - Cycle of Rot", desc = "If your commander is Black: Once per turn, when a permanent enters your graveyard from the battlefield, you may put a -1/-1 counter on target creature. \nIf your commander is Green: Once per turn, when a creature dies, you may create a Food token.\nUnlock: Beat a crypt fight where all players' commander identities were either Black, Green, or Golgari." },
    { name = "Izzet Identity Buff - Experimental Sparks", desc = "If your commander is Blue: Once per turn, when you cast an instant, you may scry 1, then draw 1. \nIf your commander is Red: Once per turn, when you cast a sorcery, you may deal 1 damage to any target.\nUnlock: Beat a crypt fight where all players' commander identities were either Blue, Red, or Izzet." },
    { name = "Dimir Identity Buff - Whisper Network", desc = "If your commander is Blue: Once per turn, when you cast a spell on an opponent's turn, you may untap target nonland permanent. \nIf your commander is Black: Once per turn, when you target a permanent you don't control, you may exile target card in any graveyard.\nUnlock: Beat a crypt fight where all players' commander identities were either Blue, Black, or Dimir." },
    { name = "Selesnya Identity Buff - Harmony's Bloom", desc = "If your commander is White: Once per turn, when you gain life, you may put a +1/+1 counter on a creature you control. \nIf your commander is Green: Once per turn, when you cast a creature spell, you may gain 1 life.\nUnlock: Beat a crypt fight where all players' commander identities were either Green, White, or Selesnya." },
    { name = "Raccoon's Rage", desc = "After you draw your opening hand and finish mulligans, you may put a Mountain card from outside the game into your hand.\n(Beat a crypt fight with a Raccoon Commander)" },
    { name = "Gamblers never quit", desc = "Once per town, when you pick your first XP-cost town action, including Merchant pack purchases, you flip a coin. You may not use this buff if you cannot pay double the XP cost. If you win the coin flip, the town action is free. If you lose the coin flip, the town action costs double XP.\nUnlock: Win a coin flip 6 times in a row." },
    { name = "Stick it To Me", desc = "At the beginning of the game, spawn 5 random sticker sheets to create your sticker deck.\nUnlock: Beat a crypt fight with stickers." },
    { name = "Gruul Identity Buff - Primal Fury", desc = "If your commander is Red: Once per turn, when a creature you control becomes modified, you may give it haste until end of turn. \nIf your commander is Green: Once per turn, when a creature you control attacks, you may give it trample until end of turn.\nUnlock: Beat a crypt fight where all players' commander identities were either Red, Green, or Gruul." },
    { name = "Chaos", desc = "Once per game, reroll an event.\nUnlock: Open 5 events in a row before an encounter." },
    { name = "Horse's Gallop", desc = "After you draw your opening hand and finish mulligans, you may put a Forest card from outside the game into your hand.\n(Beat a crypt fight with a Horse Commander)" },
    { name = "Victory lap", desc = "You have two additional free mulligans.\nUnlock: Beat 3 crypt bosses in a single session." },
    { name = "Dawn of Crabs", desc = "After you draw your opening hand and finish mulligans, you may put a Plains card from outside the game into your hand.\n(Beat a crypt fight with a Crab Commander)" },
    { name = "Rakdos Identity Buff - Showstopper's Encore", desc = "If your commander is Black: Once per turn, when a creature dies, you may draw a card and lose 1 life. \nIf your commander is Red: Once per turn, when you deal combat damage to an opponent, you may create a Treasure token.\nUnlock: Beat a crypt fight where all players' commander identities were either Black, Red, or Rakdos." },
    { name = "One with death", desc = "Gain a second free card during deck creation. One of those free cards can be a Game Changer.\nUnlock: Beat a crypt fight on turn two or earlier." },
    { name = "Compelling Madness", desc = "Once per encounter, target player gains 5 life. This can be done at instant speed.\nUnlock: Only if you indirectly kill one non-host player in a session." },
    { name = "Fish Pond", desc = "After you draw your opening hand and finish mulligans, you may put an Island card from outside the game into your hand.\n(Beat a crypt fight with a Fish Commander)" },
    { name = "Construct's Salvation", desc = "After you draw your opening hand and finish mulligans, you may put a Wastes card from outside the game into your hand.\n(Beat a crypt fight with a Construct Commander)" },
    { name = "Scorpion's Nest", desc = "After you draw your opening hand and finish mulligans, you may put a Swamp card from outside the game into your hand.\n(Beat a crypt fight with a Scorpion Commander)" },
}

BRANDS_LIST = {
    {
        name = "Brand of the Cartographer",
        repeatable = true,
        desc = "Base Cost: 500 Essence.\nWhen drafting, you may replace 2 basic lands with dual lands or triomes.\nEach additional Rank increases the cost by the base price.",
    },
    {
        name = "Brand of the Conclave",
        repeatable = true,
        desc = "Base Cost: 1000 Essence.\nDuring deckbuilding and at The Guild, you get 1 additional Commander choice whenever Commanders are generated for you.\nEach additional Rank increases the cost by the base price.",
    },
    {
        name = "Brand of Recurrence",
        repeatable = true,
        desc = "Base Cost: 1250 Essence.\nDuring deckbuilding and at The Guild, you may reroll Commanders 1 additional time for free. Does not allow rerolling the 100-card nonland draft pile.\nEach additional Rank increases the cost by the base price.",
    },
    {
        name = "Brand of the Open Hand",
        repeatable = true,
        desc = "Base Cost: 1750 Essence.\nWhenever you open a pack, that pack contains 1 additional card to choose from.\nEach additional Rank increases the cost by the base price.",
    },
    {
        name = "Brand of the Blinded Eye",
        repeatable = true,
        desc = "Base Cost: 2000 Essence.\nDuring deckbuilding, choose one color to exclude when rolling Commanders.\nEach additional Rank increases the cost by the base price.",
    },
    {
        name = "Brand of the Infinite Void",
        repeatable = true,
        desc = "Base Cost: 500 Essence.\nYour deck size minimum is reduced by 1 per Rank of this Brand.\nEach additional Rank increases the cost by the base price.",
    },
}

TICKETS_LIST = {
    { name = "Arcane Signet Ticket", desc = "Free Arcane Signet in your deck without it counting towards your 39.\nBase Cost: 750" },
    { name = "Sol Ring Ticket",      desc = "Free Sol Ring in your deck without it counting towards your 39.\nBase Cost: 1500" },
    { name = "Leyline Ticket",       desc = "Free Leyline in your deck without it counting towards your 39.\nBase Cost: 1500" },
    { name = "Color Combo Ticket",   desc = "Pick the color identity of commanders you receive before drafting your deck.\nBase Cost: 2000" },
    { name = "Trinket Ticket",       desc = "Begin the game with a trinket of your choice between three random choices.\nBase Cost: 2500" },
    { name = "Conspiracy Ticket",    desc = "Begin the game with a conspiracy of your choice between three random choices. (Before picking commander)\nBase Cost: 4000" },
    { name = "Vanguard Ticket",      desc = "Begin the game with a vanguard of your choice between three random choices. (Takes up 2 Slots)\nBase Cost: 5000" },
    { name = "Emblem Ticket",        desc = "Begin the game with an emblem of your choice between three random choices. (Takes up 3 Slots)\nBase Cost: 10000" },
}

essence = 0
essenceState = {
  achievements = {},
  crypt        = {},
  tickets      = {},
  brands       = {},
  captures     = {},
}
localPlayerKey    = nil
claimedPlayerName = nil   -- nil = unclaimed

isSyncEnabled    = false
syncDirty        = false
syncInFlight     = false
syncQueued       = false
lastSyncSentAt   = 0
lastSyncSignature = ""
pendingHandle    = nil
recentlyHandledGuids = {}

essenceTab  = "crypt"
essencePage = 1
pendingPurchase  = nil
pendingSell      = nil
pendingSellCard  = nil
pendingSellCMC   = nil
pendingSellIsDeck = false
pendingSellXPEarned = 0

-- Equipped buffs — up to 4 active slots shared across all categories
MAX_EQUIPPED  = 4
equippedBuffs = {}   -- [1..4]: nil  or  {name=..., category=...}

-- Admin mode — toggled by White seat in Settings; not persisted across saves
adminMode = false

-- Session-only transaction history (never saved or synced)
xpHistory      = {}
essenceHistory = {}
HIST_PAGE_SIZE = 5
xpHistPage     = 1
essHistPage    = 1
xpHistRowMap   = {}
essHistRowMap  = {}
pendingRevertType  = nil
pendingRevertEntry = nil

-- Town action state
pendingTownAction    = nil   -- legacy single pending action; migrated into pendingTownActions on load
pendingTownActions   = {}    -- queued {requestId, type, submittedAt, costPaid, usedBonus} while host processes
townResultCards      = nil   -- active {requestId, type, cardGuids} result awaiting player choice; persisted
townResultQueue      = {}    -- additional host results waiting behind the active result screen
pendingTownCardObj   = nil   -- card object staged for Upgrade/Augment confirm
pendingTownActionType = nil  -- "upgrade" or "augment" during confirm step
townNoteValue        = ""    -- live value of the optional-note input field
cathedralTextValue   = ""    -- live value of the Cathedral description input
merchantPacksPurchasedThisTown = {}
gamblersNeverQuitUsedThisTown = false  -- Gamblers Never Quit fires at most once per town

function getMasterController()
  local masters = getObjectsWithTag(MASTER_TAG) or {}
  return masters[1]
end

function getMasterGameplaySettings()
  local state = {
    dragovokiaTownDiscountEnabled = false,
    sillyJesterMerchantDiscountEnabled = false,
    jackOLanternEnabled = false,
    cursedPumpkinsEnabled = false,
  }
  local master = getMasterController()
  if not master then return state end
  local ok, fromMaster = pcall(function() return master.call("getGameplaySettings") end)
  if not ok or type(fromMaster) ~= "table" then return state end
  state.dragovokiaTownDiscountEnabled = fromMaster.dragovokiaTownDiscountEnabled == true
  state.sillyJesterMerchantDiscountEnabled = fromMaster.sillyJesterMerchantDiscountEnabled == true
  state.jackOLanternEnabled = fromMaster.jackOLanternEnabled == true
  state.cursedPumpkinsEnabled = fromMaster.cursedPumpkinsEnabled == true
  return state
end

function getGlobalXPBonusPercent()
  local settingsState = getMasterGameplaySettings()
  local bonusPercent = 0
  if settingsState.jackOLanternEnabled then bonusPercent = bonusPercent + 40 end
  if settingsState.cursedPumpkinsEnabled then bonusPercent = bonusPercent + 100 end
  return bonusPercent
end

function isTownActionBlocked(actionType)
  local settingsState = getMasterGameplaySettings()
  if actionType == "cathedral" then
    if settingsState.cursedPumpkinsEnabled then
      return true, "Cursed Pumpkins is active: Cathedral is disabled."
    end
    if settingsState.jackOLanternEnabled then
      return true, "Jack-o-Lantern is active: Cathedral is disabled."
    end
  end
  if actionType == "upgrade" or actionType == "augment" then
    if settingsState.cursedPumpkinsEnabled then
      return true, "Cursed Pumpkins is active: Upgrade and Augment are disabled."
    end
  end
  return false, nil
end

function compactTownQueueList(list)
  local out = {}
  if type(list) ~= "table" then return out end
  local keyed = {}
  for key, entry in pairs(list) do
    if type(entry) == "table" then
      local index = tonumber(key)
      keyed[#keyed + 1] = {index = index or (#keyed + 1), entry = entry}
    end
  end
  table.sort(keyed, function(a, b) return a.index < b.index end)
  for _, item in ipairs(keyed) do
    out[#out + 1] = item.entry
  end
  return out
end

function normalizeTownActionQueues()
  pendingTownActions = compactTownQueueList(pendingTownActions)
  townResultQueue = compactTownQueueList(townResultQueue)
  if type(pendingTownAction) == "table" then
    table.insert(pendingTownActions, pendingTownAction)
    pendingTownAction = nil
  end
end

function hasPendingTownAction()
  normalizeTownActionQueues()
  return #pendingTownActions > 0
end

function addPendingTownAction(entry)
  normalizeTownActionQueues()
  table.insert(pendingTownActions, entry)
end

function removePendingTownAction(requestId, actionType)
  normalizeTownActionQueues()
  local fallbackIndex = nil
  for i, entry in ipairs(pendingTownActions) do
    if requestId ~= nil and entry.requestId == requestId then
      table.remove(pendingTownActions, i)
      return entry
    end
    if fallbackIndex == nil and (actionType == nil or entry.type == actionType) then
      fallbackIndex = i
    end
  end
  if fallbackIndex then
    local entry = pendingTownActions[fallbackIndex]
    table.remove(pendingTownActions, fallbackIndex)
    return entry
  end
  return nil
end

function getPendingTownActionSummary()
  normalizeTownActionQueues()
  local count = #pendingTownActions
  if count <= 0 then return "No Town actions queued." end
  local parts = {}
  local maxShown = math.min(count, 3)
  for i = 1, maxShown do
    local entry = pendingTownActions[i]
    local actionType = entry.type or "request"
    table.insert(parts, actionType:sub(1,1):upper() .. actionType:sub(2))
  end
  local suffix = (count > maxShown) and (" +" .. tostring(count - maxShown) .. " more") or ""
  return tostring(count) .. " Town action(s) queued: " .. table.concat(parts, ", ") .. suffix
end

function showNextTownResultOrShop()
  normalizeTownActionQueues()
  if not townResultCards and #townResultQueue > 0 then
    townResultCards = table.remove(townResultQueue, 1)
  end
  if townResultCards then
    if townResultCards.type == "cathedral" then
      showCathedralResult()
    else
      showUpgradeResult()
    end
  else
    showShopScreen()
  end
end

function resetMerchantTownLocks()
  merchantPacksPurchasedThisTown = {}
end
function resetBuildingUsageForNewTown()
  -- Initialize each building with its remaining uses (from BUILDING_LIMITS)
  buildingUsesThisTown = {}
  for buildingKey, limit in pairs(BUILDING_LIMITS) do
    buildingUsesThisTown[buildingKey] = limit
  end
end

function resetTownActions()
  resetMerchantTownLocks()
  resetBuildingUsageForNewTown()
  gamblersNeverQuitUsedThisTown = false
  portalTravelerFungalLichActive = false
  if currentScreen == "buy" then
    showBuyScreen()
  elseif currentScreen == "experience" then
    showExperienceScreen()
  end
end

function canUseBuildingThisTown(buildingKey)
  if not BUILDING_LIMITS[buildingKey] then return true end  -- No limit = unlimited
  local townUses = buildingUsesThisTown[buildingKey] or 0
  local genericBonus = bonusBuildingUsesGeneric or 0
  local buildingBonus = bonusBuildingUsesByKey[buildingKey] or 0
  return (townUses + genericBonus + buildingBonus) > 0
end

function decrementBuildingUse(buildingKey)
  local hasAnyUse = (buildingUsesThisTown[buildingKey] or 0) > 0
    or (bonusBuildingUsesByKey[buildingKey] or 0) > 0
    or (bonusBuildingUsesGeneric or 0) > 0
  if not hasAnyUse then return end
  -- Decrement in order: townUses first, then buildingBonus, then genericBonus
  if BUILDING_LIMITS[buildingKey] and buildingUsesThisTown[buildingKey] and buildingUsesThisTown[buildingKey] > 0 then
    buildingUsesThisTown[buildingKey] = buildingUsesThisTown[buildingKey] - 1
  elseif bonusBuildingUsesByKey[buildingKey] and bonusBuildingUsesByKey[buildingKey] > 0 then
    bonusBuildingUsesByKey[buildingKey] = bonusBuildingUsesByKey[buildingKey] - 1
  elseif bonusBuildingUsesGeneric and bonusBuildingUsesGeneric > 0 then
    bonusBuildingUsesGeneric = bonusBuildingUsesGeneric - 1
  end
end

function grantBonusBuildingUse(params)
  if not params then params = {} end
  local buildingKey = params.buildingKey
  local isGeneric = params.isGeneric or false
  
  if isGeneric then
    bonusBuildingUsesGeneric = (bonusBuildingUsesGeneric or 0) + 1
  else
    -- Ensure table exists and buildingKey is valid before indexing
    if not buildingKey then return end
    if not bonusBuildingUsesByKey then bonusBuildingUsesByKey = {} end
    bonusBuildingUsesByKey[buildingKey] = (bonusBuildingUsesByKey[buildingKey] or 0) + 1
  end
end

function enterSellMode()
  pendingSell = {cardsToSell = 0, maxCards = 2}
  pendingSellXPEarned = 0
  pendingSellIsDeck = false
  currentScreen = "sell_confirm"
  openScreen("sell_confirm", nil, "Sell Cards for XP")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Drop single cards (max 2) or a 2-card deck.\nGain = 2 × total CMC",
    position = {0, 0.1, 0.0},
    width = 1600, height = 300, font_size = 70,
    color = {0.2, 0.2, 0.15}, font_color = {0.9, 0.9, 0.5},
  })
  trackButton({
    click_function = "click_sellModeCancel", function_owner = self,
    label = "Exit Sell Mode", position = {0, 0.1, 1.2},
    width = 900, height = 200, font_size = 80,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
end

function getBuildingUsesThisTown(buildingKey)
  return buildingUsesThisTown[buildingKey] or 0
end

function markMerchantPackPurchased(packName)
  if not packName or packName == "" then return end
  merchantPacksPurchasedThisTown[packName] = true
end

function clearMerchantPackPurchased(packName)
  if not packName or packName == "" then return end
  merchantPacksPurchasedThisTown[packName] = nil
end

function isMerchantPackLockedForTown(packName)
  if not packName or packName == "" then return false end
  local settingsState = getMasterGameplaySettings()
  if not settingsState.cursedPumpkinsEnabled then return false end
  return merchantPacksPurchasedThisTown[packName] == true
end

function applyTownCostModifiers(baseCost)
  local cost = math.max(0, math.floor(tonumber(baseCost) or 0))
  local settingsState = getMasterGameplaySettings()
  if settingsState.dragovokiaTownDiscountEnabled and cost > 0 then
    cost = math.max(5, cost - 5)
  end
  return cost
end

function refundXP(amount, description)
  local amt = math.max(0, math.floor(tonumber(amount) or 0))
  if amt <= 0 then return xp end
  xp = math.max(XP_MIN, math.floor(xp + amt))
  recordXPTransaction(amt, description or "XP Refund")
  refreshXPDisplay()
  notifyMasters()
  return xp
end

function getBlacksmithBonusUseKey(actionType)
  if actionType == "upgrade" then return "Blacksmith:Upgrade" end
  if actionType == "augment" then return "Blacksmith:Augment" end
  return nil
end

function getTownActionCost(actionType)
  local baseCost = 0
  if actionType == "upgrade" then
    baseCost = UPGRADE_COST
  elseif actionType == "augment" then
    baseCost = AUGMENT_COST
  end
  local cost = applyTownCostModifiers(baseCost)
  local bonusKey = getBlacksmithBonusUseKey(actionType)
  if bonusKey and (bonusBuildingUsesByKey[bonusKey] or 0) > 0 then
    return 0, true
  end
  return cost, false
end

function consumeBlacksmithBonusUse(actionType)
  local bonusKey = getBlacksmithBonusUseKey(actionType)
  if not bonusKey then return false end
  if (bonusBuildingUsesByKey[bonusKey] or 0) <= 0 then return false end
  decrementBuildingUse(bonusKey)
  return true
end

function getEffectiveStandardPackCount()
  return math.max(1, settings.cardsPerPack + getPackChoiceBonusFromBrands())
end

function getEffectivePortalPackCount(count)
  local baseCount = math.max(1, math.floor(tonumber(count) or 1))
  return math.max(1, baseCount + getPackChoiceBonusFromBrands())
end

function applyMerchantCostModifiers(baseCost)
  local cost = math.max(0, math.floor(tonumber(baseCost) or 0))
  local settingsState = getMasterGameplaySettings()
  if settingsState.sillyJesterMerchantDiscountEnabled and cost > 0 then
    cost = math.floor((cost * 0.5) / 5) * 5
    cost = math.max(5, cost)
  end
  return applyTownCostModifiers(cost)
end

function getMerchantPackCost(packKey)
  return applyMerchantCostModifiers(PACK_COSTS[packKey] or 0)
end

--==============================================================================
-- onLoad / onSave / onDestroy
--==============================================================================
function onLoad(saved)
  resetMerchantTownLocks()
  -- Seed from current catalog templates first so newly added entries appear on older saves.
  essenceState.crypt        = initCategoryFromList(CRYPT_REWARDS)
  essenceState.achievements = initCategoryFromList(ACHIEVEMENTS_LIST)
  essenceState.tickets      = initCategoryFromList(TICKETS_LIST)
  essenceState.brands       = initCategoryFromList(BRANDS_LIST)
  essenceState.captures     = {}

  if saved and saved ~= "" then
    local ok, data = pcall(JSON.decode, saved)
    if ok and type(data) == "table" then
      -- GUID mismatch = copy-pasted card; skip data load and stay unclaimed.
      local savedGuid   = type(data.claimedGuid) == "string" and data.claimedGuid or nil
      local guidMatches = (savedGuid == nil) or (savedGuid == self.getGUID())
      if guidMatches then
        if type(data.xp) == "number" then xp = math.max(XP_MIN, math.floor(data.xp)) end
        if type(data.settings) == "table" then
          local s = data.settings
          if type(s.cardsPerPack) == "number" then settings.cardsPerPack = math.max(1, math.floor(s.cardsPerPack)) end
          if type(s.autoSplay)    == "boolean" then settings.autoSplay    = s.autoSplay end
          local legacy = (type(s.splayCols) ~= "number") and (type(s.splayRows) == "number" or type(s.splayCols) == "number")
          if legacy then
            if type(s.splayRows) == "number" then settings.splayCols = math.max(1, math.floor(s.splayRows)) end
            if type(s.splayCols) == "number" then settings.splayRows = math.max(1, math.floor(s.splayCols)) end
          else
            if type(s.splayCols) == "number" then settings.splayCols = math.max(1, math.floor(s.splayCols)) end
            if type(s.splayRows) == "number" then settings.splayRows = math.max(1, math.floor(s.splayRows)) end
          end
        end
        if type(data.essence) == "number" then essence = clampEssence(data.essence) end
        if type(data.essenceState) == "table" then
          essenceState.crypt        = mergeSavedCategory(data.essenceState.crypt,        CRYPT_REWARDS)
          essenceState.achievements = mergeSavedCategory(data.essenceState.achievements, ACHIEVEMENTS_LIST)
          essenceState.tickets      = mergeSavedCategory(data.essenceState.tickets,      TICKETS_LIST)
          essenceState.brands       = mergeSavedCategory(data.essenceState.brands,       BRANDS_LIST)
          if data.essenceState.captures ~= nil then
            essenceState.captures = ess_decodeCaptures(data.essenceState.captures)
          end
        end
        if type(data.localPlayerKey) == "string" and data.localPlayerKey ~= "" then
          localPlayerKey = data.localPlayerKey
          if type(data.claimedPlayerName) == "string" and data.claimedPlayerName ~= "" then
            claimedPlayerName = data.claimedPlayerName
            self.setName(claimedPlayerName)
          end
        end
        if type(data.essenceTab) == "string" then essenceTab = data.essenceTab end
        if type(data.essencePage) == "number" then essencePage = math.max(1, math.floor(data.essencePage)) end
        if type(data.equippedBuffs) == "table" then
          equippedBuffs = {}
          for i = 1, MAX_EQUIPPED do
            local b = data.equippedBuffs[i]
            -- Brands are not equippable; silently drop any legacy saved entries.
            if type(b) == "table" and type(b.name) == "string" and b.category ~= "brands" then
              equippedBuffs[i] = {name = b.name, category = b.category}
            end
          end
        end
        if type(data.pendingTownAction) == "table" then
          pendingTownAction = data.pendingTownAction
        end
        if type(data.pendingTownActions) == "table" then
          pendingTownActions = data.pendingTownActions
        end
        if type(data.townResultCards) == "table" then
          townResultCards = data.townResultCards
        end
        if type(data.townResultQueue) == "table" then
          townResultQueue = data.townResultQueue
        end
        if type(data.buildingUsesThisTown) == "table" then
          buildingUsesThisTown = {}
          for key, val in pairs(data.buildingUsesThisTown) do
            if type(val) == "number" then
              buildingUsesThisTown[key] = math.max(0, math.floor(val))
            end
          end
        end
        if type(data.bonusBuildingUsesGeneric) == "number" then
          bonusBuildingUsesGeneric = math.max(0, math.floor(data.bonusBuildingUsesGeneric))
        else
          -- Fallback: initialize if not in profile
          bonusBuildingUsesGeneric = 0
        end
        if type(data.bonusBuildingUsesByKey) == "table" then
          bonusBuildingUsesByKey = {}
          for key, val in pairs(data.bonusBuildingUsesByKey) do
            if type(val) == "number" then
              bonusBuildingUsesByKey[key] = math.max(0, math.floor(val))
            end
          end
        else
          -- Fallback: initialize if not in profile
          bonusBuildingUsesByKey = {}
        end
      end
    end
  end
  
  -- Fallback: ensure buildingUsesThisTown is initialized with defaults
  if not buildingUsesThisTown or next(buildingUsesThisTown) == nil then
    resetBuildingUsageForNewTown()
  end
  
  self.addTag(SPAWNER_TAG)
  normalizeTownActionQueues()

  -- Restore town screens if we reloaded mid-flow; otherwise show shop
  if townResultCards then
    if townResultCards.type == "cathedral" then
      Wait.frames(showCathedralResult, 60)
    else
      Wait.frames(showUpgradeResult, 60)
    end
  elseif townResultQueue and #townResultQueue > 0 then
    Wait.frames(showNextTownResultOrShop, 60)
  else
    showNextTownResultOrShop()
  end

  if localPlayerKey then
    Wait.frames(function() pcall(fetchSavedValue) end, 30)
  end
end

function onSave()
  -- Unclaimed cards save nothing so a new player gets a clean slate.
  if not localPlayerKey then return "" end
  normalizeTownActionQueues()
  return JSON.encode({
    xp                           = xp,
    settings                     = settings,
    essence                      = essence,
    essenceState                 = essenceState,
    localPlayerKey               = localPlayerKey,
    claimedPlayerName            = claimedPlayerName,
    claimedGuid                  = self.getGUID(),
    essenceTab                   = essenceTab,
    essencePage                  = essencePage,
    equippedBuffs                = equippedBuffs,
    pendingTownAction            = nil,
    pendingTownActions           = pendingTownActions,
    townResultCards              = townResultCards,
    townResultQueue              = townResultQueue,
    buildingUsesThisTown         = buildingUsesThisTown,
    bonusBuildingUsesGeneric     = bonusBuildingUsesGeneric,
    bonusBuildingUsesByKey       = bonusBuildingUsesByKey,
  })
end

function onDestroy()
  nBooster = 0
  boosterDecks = {}
end

function updateSave()
end

--==============================================================================
-- Mystery booster engine
--==============================================================================
local function getMysteryPackQueries()
  local urlPrefix = backendURL .. '/random?q='
  local slots = {}
  for _, c in pairs({'w','u','b','r','g'}) do
    table.insert(slots, urlPrefix .. 'r<rare+c=' .. c)
    table.insert(slots, urlPrefix .. 'r<rare+c=' .. c)
  end
  table.insert(slots, urlPrefix .. 'id=c+r<rare')
  table.insert(slots, urlPrefix .. 'id=c+r<rare')
  table.insert(slots, urlPrefix .. 'c:m+r<rare')
  table.insert(slots, urlPrefix .. 'r>=rare+frame:2015')
  table.insert(slots, urlPrefix .. 'r>=rare')
  return slots
end

local function decodeQueryValue(value)
  if not value then return '' end
  local decoded = value:gsub('%+', ' ')
  decoded = decoded:gsub('%%(%x%x)', function(hex) return string.char(tonumber(hex, 16)) end)
  return decoded
end

local function normalizeQueryForBuild(query)
  local normalized = tostring(query or '')
  normalized = normalized:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  return normalized
end

local function extractQueryFromRandomUrl(url)
  if type(url) ~= 'string' or url == '' then return nil end
  local rawQuery = url:match('[%?&]q=([^&]+)')
  if not rawQuery and not url:find('/random?', 1, true) then rawQuery = url end
  if not rawQuery or rawQuery == '' then return nil end
  local normalized = normalizeQueryForBuild(decodeQueryValue(rawQuery))
  if normalized == '' then return nil end
  return normalized
end

local function firstDeckFromNDJSON(respText)
  if not respText or respText == '' then return nil end
  for line in respText:gmatch('[^\r\n]+') do
    if line and line:match('%S') then
      local ok, parsed = pcall(JSON.decode, line)
      if ok and type(parsed) == 'table' and parsed.Name == 'DeckCustom' then
        return parsed
      end
    end
  end
  return nil
end

local function prefixDeckNicknames(deck, prefix)
  if not deck or not deck.ContainedObjects then return deck end
  for _, card in ipairs(deck.ContainedObjects) do
    if card.Nickname then
      local first = card.Nickname:match("^([^\n]*)") or ""
      local rest  = card.Nickname:sub(#first + 1)
      card.Nickname = prefix .. " " .. first .. rest
    end
  end
  return deck
end

local function postBuildNDJSON(payload, callback)
  WebRequest.custom(
    backendURL .. RANDOM_BUILD_ENDPOINT_PATH,
    'POST', true, JSON.encode(payload),
    {
      Accept = 'application/x-ndjson',
      ['Content-Type'] = 'application/json',
      ['Accept-Language'] = 'en',
    },
    callback
  )
end

local function getDeckEntryForCardId(deckObject, cardId)
  if not deckObject or not deckObject.CustomDeck or not cardId then return nil end
  local deckNum = math.floor(tonumber(cardId) / 100)
  if not deckNum or deckNum <= 0 then return nil end
  return deckObject.CustomDeck[tostring(deckNum)] or deckObject.CustomDeck[deckNum]
end

local function remapDeckCardIds(cardDat, deckObject, n)
  if not cardDat then return nil end
  local primaryDeckEntry = getDeckEntryForCardId(deckObject, cardDat.CardID)
  if not primaryDeckEntry and cardDat.CustomDeck then
    for _, e in pairs(cardDat.CustomDeck) do primaryDeckEntry = e break end
  end
  if not primaryDeckEntry then return nil end
  cardDat.CardID = n * 100
  cardDat.CustomDeck = { [n] = primaryDeckEntry }
  if cardDat.States and cardDat.States[2] then
    local backState = cardDat.States[2]
    local stateDeckEntry = getDeckEntryForCardId(deckObject, backState.CardID)
    if not stateDeckEntry and backState.CustomDeck then
      for _, e in pairs(backState.CustomDeck) do stateDeckEntry = e break end
    end
    local stateDeckId = n + 100
    backState.CardID = stateDeckId * 100
    if stateDeckEntry then
      backState.CustomDeck = { [stateDeckId] = stateDeckEntry }
    else
      backState.CustomDeck = nil
    end
  end
  return cardDat
end

local function cardDatFromBuildResponse(respText, n)
  local deckObject = firstDeckFromNDJSON(respText)
  if not deckObject or not deckObject.ContainedObjects or not deckObject.ContainedObjects[1] then return nil end
  return remapDeckCardIds(deckObject.ContainedObjects[1], deckObject, n)
end

local function stripQueryAndHash(url)
  if type(url) ~= 'string' then return '' end
  local trimmed = url:gsub('#.*$', '')
  trimmed = trimmed:gsub('%?.*$', '')
  return trimmed
end

local function normalizeScryfallSize(url)
  if type(url) ~= 'string' then return url end
  return url:gsub('(https?://cards%.scryfall%.io/)(large)(/)', '%1normal%3')
end

local function urlEncode(str)
  if type(str) ~= 'string' then return '' end
  return (str:gsub('([^%w%-_%.~])', function(c)
    return string.format('%%%02X', string.byte(c))
  end))
end

local function proxyImageURL(url)
  if type(url) ~= 'string' or url == '' then return url end
  local sourceUrl = stripQueryAndHash(url)
  sourceUrl = normalizeScryfallSize(sourceUrl)
  if not sourceUrl:find('^https?://cards%.scryfall%.io/') then
    return url
  end
  local ext = sourceUrl:match('%.([A-Za-z0-9]+)$') or 'jpg'
  if ext == 'jpeg' then ext = 'jpg' end
  return 'https://api.mtginfo.org/image-proxy/' .. urlEncode(sourceUrl) .. '.' .. ext
end

local function faceUrlFromRandomCard(card)
  if type(card) ~= 'table' then return '' end
  if type(card.image_uris) == 'table' then
    local face = card.image_uris.normal or card.image_uris.large or card.image_uris.png or card.image_uris.small or ''
    return proxyImageURL(face)
  end
  if type(card.card_faces) == 'table' and type(card.card_faces[1]) == 'table' and type(card.card_faces[1].image_uris) == 'table' then
    local iu = card.card_faces[1].image_uris
    local face = iu.normal or iu.large or iu.png or iu.small or ''
    return proxyImageURL(face)
  end
  return ''
end

-- Edit note: OTAG pack builds now consume mtginfo /random list responses and convert them into a local TTS deck. Signed, Sirin.
local function deckFromRandomListResponse(respText)
  if not respText or respText == '' then return nil end
  local ok, parsed = pcall(JSON.decode, respText)
  if not ok or type(parsed) ~= 'table' or type(parsed.data) ~= 'table' then return nil end

  local deckDat = {
    Transform = {posX=0,posY=0,posZ=0,rotX=0,rotY=180,rotZ=180,scaleX=1,scaleY=1,scaleZ=1},
    Name = 'DeckCustom', Nickname = cardStackName, Description = cardStackDescription,
    DeckIDs = {}, CustomDeck = {}, ContainedObjects = {},
  }

  local slot = 1
  for _, card in ipairs(parsed.data) do
    local face = faceUrlFromRandomCard(card)
    if face ~= '' then
      local cardId = slot * 100
      local deckKey = tostring(slot)

      local outCard = JSON.decode(JSON.encode(CAPTURE_CARD_TEMPLATE))
      outCard.Nickname = tostring(card.name or '')
      outCard.Description = tostring(card.type_line or '')
      outCard.GMNotes = tostring(card.id or '')
      outCard.CardID = cardId
      outCard.CustomDeck = {
        [deckKey] = {
          FaceURL = face,
          BackURL = backURL,
          NumWidth = 1,
          NumHeight = 1,
          BackIsHidden = true,
          UniqueBack = false,
          Type = 0,
        }
      }

      table.insert(deckDat.ContainedObjects, outCard)
      table.insert(deckDat.DeckIDs, cardId)
      deckDat.CustomDeck[deckKey] = outCard.CustomDeck[deckKey]
      slot = slot + 1
    end
  end

  if #deckDat.ContainedObjects == 0 then return nil end
  return deckDat
end

function getDeckDat(urlTable, boosterN)
  local deckDat = {
    Transform = {posX=0,posY=0,posZ=0,rotX=0,rotY=180,rotZ=180,scaleX=1,scaleY=1,scaleZ=1},
    Name = "Deck", Nickname = cardStackName, Description = cardStackDescription,
    DeckIDs = {}, CustomDeck = {}, ContainedObjects = {},
  }
  local nLoading, nLoaded = 0, 0
  for n, url in ipairs(urlTable) do
    nLoading = nLoading + 1
    local function assignCardDat(cd)
      if cd then
        deckDat.ContainedObjects[n] = cd
        deckDat.DeckIDs[n] = cd.CardID
        deckDat.CustomDeck[n] = cd.CustomDeck[n]
      else
        printToAll('Mystery Pack: failed to fetch slot ' .. tostring(n), {1, 0.5, 0.2})
      end
      nLoaded = nLoaded + 1
    end
    local randomQuery = extractQueryFromRandomUrl(url)
    if randomQuery then
      postBuildNDJSON({q = randomQuery, count = 1, enforceCommander = false, forceApi = false, back = backURL}, function(wr)
        if not wr.is_done then return end
        local hasError = wr.is_error or (wr.response_code and wr.response_code >= 400)
        if hasError or not wr.text or wr.text == '' then assignCardDat(nil) return end
        assignCardDat(cardDatFromBuildResponse(wr.text, n))
      end)
    else
      assignCardDat(nil)
    end
  end
  local finalized = false
  local function finalizeDeckDat()
    if finalized then return end
    finalized = true
    local doubles = false
    local namesSeen = {}
    for _, card in pairs(deckDat.ContainedObjects) do
      local cardName = card and card.Nickname
      if cardName then
        if namesSeen[cardName] then
          doubles = true
          break
        end
        namesSeen[cardName] = true
      end
    end

    local newObjects, newIDs = {}, {}
    for i = 1, #urlTable do
      if deckDat.ContainedObjects[i] then
        table.insert(newObjects, deckDat.ContainedObjects[i])
        table.insert(newIDs, deckDat.DeckIDs[i])
      end
    end
    deckDat.ContainedObjects = newObjects
    deckDat.DeckIDs = newIDs
    if doubles then
      getDeckDat(urlTable, boosterN)
    else
      boosterDecks[boosterN] = deckDat
    end
  end
  Wait.condition(finalizeDeckDat, function() return nLoading == nLoaded end)
  Wait.time(function()
    if finalized then return end
    printToAll('Mystery Pack: card fetch timeout, using partial results.', {1, 0.6, 0.2})
    finalizeDeckDat()
  end, BOOSTER_BUILD_TIMEOUT)
end

--==============================================================================
-- Master controller integration
--==============================================================================
function getXP()
  return xp
end

function receiveXP(params)
  local amt, bypass = 0, false
  if type(params) == "number" then amt = params
  elseif type(params) == "table" and type(params.amount) == "number" then
    amt = params.amount
    bypass = params.bypassBuff == true
  end
  local bonus = 0
  if not bypass then
    local flameBonus = calcBuffBonus("Flame of Progress", amt)
    local modeBonus = 0
    if amt > 0 then
      local pct = getGlobalXPBonusPercent()
      if pct > 0 then
        modeBonus = math.ceil(amt * (pct / 100))
      end
    end
    bonus = flameBonus + modeBonus
    if flameBonus > 0 then
      broadcastToAll("[" .. self.getName() .. "] Flame of Progress: +" .. tostring(flameBonus) .. " bonus XP!", {1, 0.9, 0.4})
    end
    if modeBonus > 0 then
      broadcastToAll("[" .. self.getName() .. "] XP mode bonus: +" .. tostring(modeBonus) .. " XP!", {1, 0.75, 0.35})
    end
  end
  xp = math.max(XP_MIN, math.floor(xp + amt + bonus))
  recordXPTransaction(math.floor(amt + bonus), bypass and "Reverted XP" or "Received XP")
  refreshXPDisplay()
  notifyMasters()
  return xp
end

function notifyMasters()
  local masters = getObjectsWithTag(MASTER_TAG) or {}
  for _, m in ipairs(masters) do
    for _, hook in ipairs(MASTER_REFRESH_HOOKS) do
      pcall(function() m.call(hook, {spawner = self, xp = xp, essence = essence}) end)
    end
  end
end

function xp_noop() end

function getTimeStr()
  local t = os.date("*t")
  return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

function recordXPTransaction(amount, description)
  table.insert(xpHistory, 1, {amount=amount, balance=xp, time=getTimeStr(), description=description})
  if #xpHistory > 100 then table.remove(xpHistory) end
end

function recordEssenceTransaction(amount, description)
  table.insert(essenceHistory, 1, {amount=amount, balance=essence, time=getTimeStr(), description=description})
  if #essenceHistory > 100 then table.remove(essenceHistory) end
end

function applyEssenceDeltaTracked(amt, description, bypassBuff)
  local before = essence
  applyEssenceDelta(amt, bypassBuff)
  local actual = essence - before
  if actual ~= 0 then recordEssenceTransaction(actual, description) end
end

--==============================================================================
-- UI tracking
--==============================================================================
function trackButton(params)
  if params.function_owner == nil then params.function_owner = self end
  local existing = self.getButtons() or {}
  local idx = #existing
  self.createButton(params)
  table.insert(uiButtonIndices, idx)
  return idx
end

function trackInput(params)
  if params.function_owner == nil then params.function_owner = self end
  local existing = self.getInputs() or {}
  local idx = #existing
  self.createInput(params)
  table.insert(uiInputIndices, idx)
  return idx
end

function tb_label(opts)
  opts.click_function = opts.click_function or "xp_noop"
  opts.width      = opts.width      or 800
  opts.height     = opts.height     or 180
  opts.font_size  = opts.font_size  or 90
  opts.color      = opts.color      or LABEL_BG
  opts.font_color = opts.font_color or {0, 0, 0}
  return trackButton(opts)
end

function openScreen(name, rightButton, title)
  clearAllUI()
  currentScreen = name
  drawHeader(rightButton, title)
end

function clearAllUI()
  -- Cancel any in-flight debounced pool check so it doesn't fire on a new screen.
  if poolCheckHandle then
    pcall(function() Wait.Stop(poolCheckHandle) end)
    poolCheckHandle = nil
  end
  poolSizeButtonIndex = nil
  self.clearButtons()
  self.clearInputs()
  uiButtonIndices = {}
  uiInputIndices  = {}
  xpDisplayIndex      = nil
  essenceDisplayIndex = nil
end

function refreshXPDisplay()
  if xpDisplayIndex ~= nil then
    self.editButton({index = xpDisplayIndex, label = "XP: " .. tostring(xp)})
  end
end

function refreshEssenceDisplay()
  if essenceDisplayIndex ~= nil then
    self.editButton({index = essenceDisplayIndex, label = "Essence: " .. tostring(essence)})
  end
end

function updatePoolLabel(text, col)
  if poolSizeButtonIndex ~= nil then
    self.editButton({
      index      = poolSizeButtonIndex,
      label      = text,
      color      = col or {0.15, 0.15, 0.25},
      font_color = {1, 1, 1},
    })
  end
end

function doPoolCheck()
  poolCheckHandle = nil
  if not activePack or not PACK_MIN_POOL[activePack] then return end
  local q
  if     activePack == "pro"    then q = buildProQuery()
  elseif activePack == "mythic" then q = buildMythicQuery()
  elseif activePack == "otag"   then q = buildOtagQuery() end
  if not q or q == "" then
    updatePoolLabel("Pool: set a filter", {0.35, 0.25, 0.15})
    return
  end
  updatePoolLabel("Pool: checking…", {0.2, 0.2, 0.3})
  checkPoolSize(q, function(count)
    if currentScreen ~= "input" then return end  -- user navigated away
    local minPool = PACK_MIN_POOL[activePack] or 0
    if count == nil then
      updatePoolLabel("Pool: unavailable", {0.3, 0.3, 0.3})
    elseif count < minPool then
      updatePoolLabel("Pool: " .. tostring(count) .. " / " .. tostring(minPool) .. " ✗  (too few)", {0.65, 0.2, 0.15})
    else
      updatePoolLabel("Pool: " .. tostring(count) .. " ✓", {0.15, 0.45, 0.2})
    end
  end)
end

function schedulePoolCheck()
  if not activePack or not PACK_MIN_POOL[activePack] then return end
  if poolCheckHandle then
    pcall(function() Wait.Stop(poolCheckHandle) end)
    poolCheckHandle = nil
  end
  updatePoolLabel("Pool: …", {0.2, 0.2, 0.3})
  poolCheckHandle = Wait.time(doPoolCheck, 0.7)
end

-- rightButton : nil | "back" | "ess_shop_back" | "capture_cancel"
-- Layout: Top-Left = XP | Top-Center = title | Top-Right = Essence | Bottom-Left = Back/Cancel
function drawHeader(rightButton, title)
  xpDisplayIndex = trackButton({
    click_function = "click_xpHeader", function_owner = self,
    label = "XP: " .. tostring(xp),
    position = {-1.7, 0.1, -1.15},
    width = 500, height = 230, font_size = 100,
    color = {0.1, 0.1, 0.4}, font_color = {1, 1, 1},
    tooltip = "Click to view XP history",
  })
  if title then
    trackButton({
      click_function = "xp_noop", function_owner = self,
      label = title,
      position = {0, 0.1, -1.15},
      width = 900, height = 230, font_size = 90,
      color = {0.15, 0.15, 0.2}, font_color = {1, 1, 1},
    })
  end
  essenceDisplayIndex = trackButton({
    click_function = "click_essHeader", function_owner = self,
    label = "Essence: " .. tostring(essence),
    position = {1.7, 0.1, -1.15},
    width = 600, height = 230, font_size = 80,
    color = {0.4, 0.25, 0.55}, font_color = {1, 1, 1},
    tooltip = "Click to view Essence history",
  })
  if rightButton == "back" then
    trackButton({
      click_function = "click_essenceBack", function_owner = self,
      label = "Back",
      position = {-1.6, 0.1, 1.3},
      width = 500, height = 200, font_size = 95,
      color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
    })
  elseif rightButton == "ess_shop_back" then
    trackButton({
      click_function = "click_essShopBack", function_owner = self,
      label = "Back",
      position = {-1.6, 0.1, 1.3},
      width = 500, height = 200, font_size = 95,
      color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
    })
  elseif rightButton == "capture_cancel" then
    trackButton({
      click_function = "click_captureCancel", function_owner = self,
      label = "Cancel",
      position = {-1.6, 0.1, 1.3},
      width = 500, height = 200, font_size = 95,
      color = {0.55, 0.15, 0.15}, font_color = {1, 1, 1},
    })
  end
end

--==============================================================================
-- History screens
--==============================================================================
function click_xpHeader()  xpHistPage = 1;  showXPHistoryScreen()      end
function click_essHeader() essHistPage = 1; showEssenceHistoryScreen() end

function showXPHistoryScreen()
  openScreen("xp_history", nil, "XP History")
  xpHistRowMap = {}
  local entries = xpHistory
  local total   = #entries
  local pages   = math.max(1, math.ceil(total / HIST_PAGE_SIZE))
  xpHistPage    = math.max(1, math.min(xpHistPage, pages))
  local startI  = (xpHistPage - 1) * HIST_PAGE_SIZE + 1
  if total == 0 then
    trackButton({
      click_function = "xp_noop", function_owner = self,
      label = "No XP transactions this session.",
      position = {0, 0.1, 0.15}, width = 1700, height = 200, font_size = 70,
      color = {0.12, 0.12, 0.22}, font_color = {0.7, 0.7, 0.9},
    })
  else
    local zTop, zStep = -0.72, 0.42
    for row = 0, HIST_PAGE_SIZE - 1 do
      local i = startI + row
      if i > total then break end
      local e    = entries[i]
      xpHistRowMap[row] = e
      local sign = e.amount >= 0 and "+" or ""
      local lbl  = sign .. e.amount .. " XP  |  Bal: " .. e.balance .. "  |  " .. e.time .. "\n" .. e.description
      local col  = e.amount >= 0 and {0.1, 0.28, 0.1} or {0.3, 0.1, 0.1}
      trackButton({
        click_function = "click_xpHistRow" .. row, function_owner = self,
        label = lbl, position = {0, 0.1, zTop + row * zStep},
        width = 1700, height = 190, font_size = 62,
        color = col, font_color = {1, 1, 1},
        tooltip = adminMode and "Right-click to revert (Admin)" or nil,
      })
    end
  end
  if pages > 1 then
    if xpHistPage > 1 then
      trackButton({
        click_function = "click_xpHistPrev", function_owner = self,
        label = "< Prev", position = {-0.9, 0.1, 1.25},
        width = 420, height = 160, font_size = 72,
        color = {0.25, 0.25, 0.35}, font_color = {1, 1, 1},
      })
    end
    trackButton({
      click_function = "xp_noop", function_owner = self,
      label = xpHistPage .. " / " .. pages, position = {0, 0.1, 1.25},
      width = 320, height = 160, font_size = 72,
      color = {0.15, 0.15, 0.2}, font_color = {1, 1, 1},
    })
    if xpHistPage < pages then
      trackButton({
        click_function = "click_xpHistNext", function_owner = self,
        label = "Next >", position = {0.9, 0.1, 1.25},
        width = 420, height = 160, font_size = 72,
        color = {0.25, 0.25, 0.35}, font_color = {1, 1, 1},
      })
    end
  end
  trackButton({
    click_function = "click_xpHistBack", function_owner = self,
    label = "Back", position = {-1.6, 0.1, 1.4},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function click_xpHistBack() showShopScreen()                            end
function click_xpHistPrev() xpHistPage = xpHistPage - 1; showXPHistoryScreen() end
function click_xpHistNext() xpHistPage = xpHistPage + 1; showXPHistoryScreen() end

function showEssenceHistoryScreen()
  openScreen("ess_history", nil, "Essence History")
  essHistRowMap = {}
  local entries = essenceHistory
  local total   = #entries
  local pages   = math.max(1, math.ceil(total / HIST_PAGE_SIZE))
  essHistPage   = math.max(1, math.min(essHistPage, pages))
  local startI  = (essHistPage - 1) * HIST_PAGE_SIZE + 1
  if total == 0 then
    trackButton({
      click_function = "xp_noop", function_owner = self,
      label = "No Essence transactions this session.",
      position = {0, 0.1, 0.15}, width = 1700, height = 200, font_size = 70,
      color = {0.22, 0.12, 0.22}, font_color = {0.9, 0.7, 0.9},
    })
  else
    local zTop, zStep = -0.72, 0.42
    for row = 0, HIST_PAGE_SIZE - 1 do
      local i = startI + row
      if i > total then break end
      local e    = entries[i]
      essHistRowMap[row] = e
      local sign = e.amount >= 0 and "+" or ""
      local lbl  = sign .. e.amount .. " Ess  |  Bal: " .. e.balance .. "  |  " .. e.time .. "\n" .. e.description
      local col  = e.amount >= 0 and {0.15, 0.1, 0.28} or {0.32, 0.1, 0.15}
      trackButton({
        click_function = "click_essHistRow" .. row, function_owner = self,
        label = lbl, position = {0, 0.1, zTop + row * zStep},
        width = 1700, height = 190, font_size = 62,
        color = col, font_color = {1, 1, 1},
        tooltip = adminMode and "Right-click to revert (Admin)" or nil,
      })
    end
  end
  if pages > 1 then
    if essHistPage > 1 then
      trackButton({
        click_function = "click_essHistPrev", function_owner = self,
        label = "< Prev", position = {-0.9, 0.1, 1.25},
        width = 420, height = 160, font_size = 72,
        color = {0.25, 0.25, 0.35}, font_color = {1, 1, 1},
      })
    end
    trackButton({
      click_function = "xp_noop", function_owner = self,
      label = essHistPage .. " / " .. pages, position = {0, 0.1, 1.25},
      width = 320, height = 160, font_size = 72,
      color = {0.15, 0.15, 0.2}, font_color = {1, 1, 1},
    })
    if essHistPage < pages then
      trackButton({
        click_function = "click_essHistNext", function_owner = self,
        label = "Next >", position = {0.9, 0.1, 1.25},
        width = 420, height = 160, font_size = 72,
        color = {0.25, 0.25, 0.35}, font_color = {1, 1, 1},
      })
    end
  end
  trackButton({
    click_function = "click_essHistBack", function_owner = self,
    label = "Back", position = {-1.6, 0.1, 1.4},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function click_essHistBack() showShopScreen()                                  end
function click_essHistPrev() essHistPage = essHistPage - 1; showEssenceHistoryScreen() end
function click_essHistNext() essHistPage = essHistPage + 1; showEssenceHistoryScreen() end

-- Per-row click handlers (TTS requires named globals, no closures)
function click_xpHistRow0(o,c,alt)  onHistRowClick("xp",  0, alt) end
function click_xpHistRow1(o,c,alt)  onHistRowClick("xp",  1, alt) end
function click_xpHistRow2(o,c,alt)  onHistRowClick("xp",  2, alt) end
function click_xpHistRow3(o,c,alt)  onHistRowClick("xp",  3, alt) end
function click_xpHistRow4(o,c,alt)  onHistRowClick("xp",  4, alt) end
function click_essHistRow0(o,c,alt) onHistRowClick("ess", 0, alt) end
function click_essHistRow1(o,c,alt) onHistRowClick("ess", 1, alt) end
function click_essHistRow2(o,c,alt) onHistRowClick("ess", 2, alt) end
function click_essHistRow3(o,c,alt) onHistRowClick("ess", 3, alt) end
function click_essHistRow4(o,c,alt) onHistRowClick("ess", 4, alt) end

function onHistRowClick(kind, row, altClick)
  if not altClick then return end
  if not adminMode then return end
  local map   = (kind == "xp") and xpHistRowMap or essHistRowMap
  local entry = map[row]
  if not entry then return end
  pendingRevertType  = kind
  pendingRevertEntry = entry
  showRevertConfirm(kind, entry)
end

function showRevertConfirm(kind, entry)
  openScreen("revert_confirm", nil, "Revert Transaction")
  local unit  = (kind == "xp") and "XP" or "Essence"
  local sign  = entry.amount >= 0 and "+" or ""
  local delta = -entry.amount
  local dsign = delta >= 0 and "+" or ""
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = sign .. entry.amount .. " " .. unit
        .. "  |  Bal after: " .. entry.balance
        .. "\n" .. entry.time .. "  |  " .. entry.description,
    position = {0, 0.1, -0.3},
    width = 1700, height = 220, font_size = 62,
    color = entry.amount >= 0 and {0.1, 0.28, 0.1} or {0.3, 0.1, 0.1},
    font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Will apply:  " .. dsign .. delta .. " " .. unit,
    position = {0, 0.1, 0.2},
    width = 1700, height = 180, font_size = 72,
    color = {0.18, 0.18, 0.1},
    font_color = delta >= 0 and {0.5, 1, 0.5} or {1, 0.5, 0.5},
  })
  trackButton({
    click_function = "click_revertCancel", function_owner = self,
    label = "Cancel",
    position = {-0.7, 0.1, 0.85},
    width = 700, height = 220, font_size = 80,
    color = {0.35, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_revertConfirmOK", function_owner = self,
    label = "Revert",
    position = {0.7, 0.1, 0.85},
    width = 700, height = 220, font_size = 80,
    color = {0.15, 0.35, 0.15}, font_color = {1, 1, 1},
  })
end

function click_revertCancel()
  local kind = pendingRevertType
  pendingRevertType  = nil
  pendingRevertEntry = nil
  if kind == "xp" then showXPHistoryScreen() else showEssenceHistoryScreen() end
end

function click_revertConfirmOK()
  local kind  = pendingRevertType
  local entry = pendingRevertEntry
  pendingRevertType  = nil
  pendingRevertEntry = nil
  if not entry then showShopScreen(); return end
  local delta = -entry.amount
  if kind == "xp" then
    xp = math.max(XP_MIN, xp + delta)
    recordXPTransaction(delta, "[Revert] " .. entry.description)
    refreshXPDisplay()
    notifyMasters()
    broadcastToAll(self.getName() .. ": [Admin] Reverted XP transaction: "
        .. (delta >= 0 and "+" or "") .. delta .. " XP", {1, 0.9, 0.4})
    showXPHistoryScreen()
  else
    essence = clampEssence(essence + delta)
    recordEssenceTransaction(delta, "[Revert] " .. entry.description)
    refreshEssenceDisplay()
    notifyMasters()
    markDirty()
    broadcastToAll(self.getName() .. ": [Admin] Reverted Essence transaction: "
        .. (delta >= 0 and "+" or "") .. delta .. " Essence", {0.7, 0.5, 1})
    showEssenceHistoryScreen()
  end
end

--==============================================================================
-- Screen builders
--==============================================================================
function getPlayerDisplayName()
  if claimedPlayerName and claimedPlayerName ~= "" then return claimedPlayerName end
  if localPlayerKey and localPlayerKey ~= "" then
    return (localPlayerKey:gsub("_Essence$", ""))
  end
  return "Unclaimed"
end

function showShopScreen()
  activePack = nil
  openScreen("shop", nil, getPlayerDisplayName())
  trackButton({
    click_function = "click_shopCashout", function_owner = self,
    label = "Redeem Cashout",
    position = {0, 0.1, -0.5},
    width = 1800, height = 230, font_size = 85,
    color = {0.45, 0.35, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_shopExperience", function_owner = self,
    label = "Experience",
    position = {-1.4, 0.1, 0.25},
    width = 600, height = 320, font_size = 90,
    color = {0.15, 0.4, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_shopEssence", function_owner = self,
    label = "Essence",
    position = {0, 0.1, 0.25},
    width = 600, height = 320, font_size = 100,
    color = {0.4, 0.25, 0.55}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_shopSettings", function_owner = self,
    label = "Settings",
    position = {1.4, 0.1, 0.25},
    width = 600, height = 320, font_size = 100,
    color = {0.2, 0.2, 0.2}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_endSession", function_owner = self,
    label = "End Session",
    position = {0, 0.1, 1.05},
    width = 1800, height = 230, font_size = 85,
    color = {0.45, 0.15, 0.15}, font_color = {1, 0.85, 0.85},
    tooltip = "Convert XP to Essence, then count your deck's CMC",
  })
end

function click_shopExperience()  showExperienceScreen() end
function click_shopEssence()     showEssenceScreen()    end
function click_shopCashout()     showRedeemCashoutScreen() end
function click_shopSettings()    showSettingsScreen()   end
function click_shopBuy()         showExperienceScreen() end
function click_shopXPShop()      showExperienceScreen() end
function click_shopEssenceShop() showEssenceScreen()    end

function click_endSession() showEndSessionConfirm() end

function showEndSessionConfirm()
  openScreen("end_session_confirm", nil)
  local bonus     = calcBuffBonus("Spiritual Guidance", xp)
  local total     = xp + bonus
  local bonusNote = (bonus > 0) and ("\n(+" .. bonus .. " Spiritual Guidance bonus)") or ""
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "End Session?",
    position = {0, 0.1, -0.75}, width = 1200, height = 170, font_size = 95,
    color = {0.3, 0.1, 0.1}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Convert " .. tostring(xp) .. " XP -> " .. tostring(total) .. " Essence" .. bonusNote,
    position = {0, 0.1, -0.05}, width = 1400, height = 200, font_size = 68,
    color = {0.2, 0.15, 0.25}, font_color = {0.85, 0.75, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Then place deck to add CMC to Essence",
    position = {0, 0.1, 0.55}, width = 1300, height = 150, font_size = 62,
    color = {0.15, 0.15, 0.2}, font_color = {0.75, 0.75, 0.9},
  })
  trackButton({
    click_function = "click_endSessionCancel", function_owner = self,
    label = "Cancel",
    position = {-1.0, 0.1, 1.2}, width = 500, height = 150, font_size = 80,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_endSessionConfirmOK", function_owner = self,
    label = "Confirm",
    position = {1.0, 0.1, 1.2}, width = 500, height = 150, font_size = 80,
    color = {0.15, 0.45, 0.15}, font_color = {1, 1, 1},
  })
end

function click_endSessionCancel() showShopScreen() end

function click_endSessionConfirmOK()
  resetMerchantTownLocks()
  local xpAmt = xp
  xp = XP_MIN
  recordXPTransaction(-xpAmt, "End Session (converted to Essence)")
  refreshXPDisplay()
  notifyMasters()
  markDirty()
  applyEssenceDeltaTracked(xpAmt, "End Session: XP -> Essence")
  showEndSessionDeckPrompt()
end

function showEndSessionDeckPrompt()
  openScreen("end_session_deck", nil)
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Place your deck on this card",
    position = {0, 0.1, -0.3}, width = 1300, height = 200, font_size = 78,
    color = {0.15, 0.15, 0.3}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "CMC total will be added to Essence",
    position = {0, 0.1, 0.35}, width = 1300, height = 150, font_size = 65,
    color = {0.12, 0.12, 0.22}, font_color = {0.75, 0.75, 0.95},
  })
  trackButton({
    click_function = "click_endSessionSkipDeck", function_owner = self,
    label = "Skip",
    position = {0, 0.1, 1.2}, width = 500, height = 150, font_size = 80,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function click_endSessionSkipDeck() showShopScreen() end

function showRedeemCashoutScreen()
  pendingCashoutCard = nil
  openScreen("redeem_cashout_prompt", nil, "Redeem Cashout")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Drop a Cashout Token here\nto redeem a Bonus Building Use",
    position = {0, 0.1, -0.25},
    width = 1600, height = 350, font_size = 70,
    color = {0.35, 0.25, 0.15}, font_color = {1, 0.9, 0.6},
  })
  trackButton({
    click_function = "click_redeemCashoutBack", function_owner = self,
    label = "Back",
    position = {0, 0.1, 1.2},
    width = 500, height = 150, font_size = 80,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function click_redeemCashoutBack() showShopScreen() end

function extractCMCFromName(name)
  if not name then return nil end
  local cmct = name:match("%d+%s*CMC")
  if not cmct then return nil end
  local cmc = cmct:match("%d+")
  return cmc and tonumber(cmc) or nil
end

function handleEndSessionDeck(obj)
  if not obj or obj == self then return end
  if currentScreen ~= "end_session_deck" then return end
  local tag = ""
  pcall(function() tag = obj.tag or "" end)
  if tag ~= "Deck" and tag ~= "Card" then return end

  local totalCMC = 0
  if tag == "Deck" then
    local ok, data = pcall(function() return obj.getData() end)
    if ok and data and data.ContainedObjects then
      for _, card in ipairs(data.ContainedObjects) do
        local cmc = extractCMCFromName(card.Nickname)
        if cmc then totalCMC = totalCMC + cmc end
      end
    end
  else
    local cardName = ""
    pcall(function() cardName = obj.getName() or "" end)
    local cmc = extractCMCFromName(cardName)
    if cmc then totalCMC = cmc end
  end

  applyEssenceDeltaTracked(totalCMC, "Deck CMC Bonus")
  broadcastToAll("[" .. self.getName() .. "] End Session: +" .. tostring(totalCMC)
    .. " CMC added to Essence!", {0.6, 0.4, 1.0})
  showShopScreen()
end

function showExperienceScreen()
  activePack = nil
  openScreen("experience", nil, "Experience")
  -- Row 1 (4 wide, spacing=1.0): Merchant | Portal | Mystic | Guild
  local BW, BH, BF = 420, 190, 60
  trackButton({
    click_function = "click_xpShopEnter", function_owner = self,
    label = "Merchant",
    position = {-1.5, 0.1, -0.2},
    width = BW, height = BH, font_size = BF,
    color = {0.15, 0.4, 0.15}, font_color = {1, 1, 1},
    tooltip = "Buy packs with XP",
  })
  trackButton({
    click_function = "click_xpPortal", function_owner = self,
    label = "Portal",
    position = {-0.5, 0.1, -0.2},
    width = BW, height = BH, font_size = BF,
    color = {0.1, 0.35, 0.45}, font_color = {1, 1, 1},
    tooltip = "Spawn cards by Type or Keyword — 1 XP per card",
  })
  trackButton({
    click_function = "click_xpMystic", function_owner = self,
    label = "Mystic",
    position = {0.5, 0.1, -0.2},
    width = BW, height = BH, font_size = BF,
    color = {0.35, 0.1, 0.45}, font_color = {1, 1, 1},
    tooltip = "Disenchant a card for 5 XP — gain 2× its mana value in Essence",
  })
  trackButton({
    click_function = "click_xpGuild", function_owner = self,
    label = "Guild",
    position = {1.5, 0.1, -0.2},
    width = BW, height = BH, font_size = BF,
    color = {0.45, 0.35, 0.05}, font_color = {1, 0.95, 0.6},
    tooltip = "Roll a d6 for random commanders — 10 XP",
  })
  -- Row 2: Cathedral | Blacksmith | Bazaar
  trackButton({
    click_function = "click_xpCathedral", function_owner = self,
    label = "Cathedral",
    position = {-1.5, 0.1, 0.55},
    width = BW, height = BH, font_size = BF,
    color = {0.1, 0.2, 0.35}, font_color = {0.8, 0.9, 1.0},
    tooltip = "Request a custom card from the host — free",
  })
  trackButton({
    click_function = "click_xpBlacksmith", function_owner = self,
    label = "Blacksmith",
    position = {0, 0.1, 0.55},
    width = BW, height = BH, font_size = BF,
    color = {0.22, 0.18, 0.1}, font_color = {1.0, 0.88, 0.55},
    tooltip = "Upgrade or Augment a card",
  })
  trackButton({
    click_function = "click_xpBazaar", function_owner = self,
    label = "Bazaar",
    position = {1.5, 0.1, 0.55},
    width = BW, height = BH, font_size = BF,
    color = {0.35, 0.22, 0.08}, font_color = {1, 0.9, 0.5},
    tooltip = "Sell tokens or cards for Essence",
  })
  trackButton({
    click_function = "click_experienceBack", function_owner = self,
    label = "Back",
    position = {-1.6, 0.1, 1.38},
    width = 450, height = 185, font_size = 85,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function click_xpShopEnter()    showBuyScreen()      end
function click_xpPortal()
  if not canUseBuildingThisTown("Portal") then
    broadcastToAll("[" .. self.getName() .. "] Portal: No uses remaining this town.", {0.95, 0.45, 0.2})
    return
  end
  openPortalInput()
end
function click_xpMystic()       showMysticScreen()   end
function click_xpGuild()        showGuildScreen()    end
function click_xpCathedral()
  local blocked, reason = isTownActionBlocked("cathedral")
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    return
  end
  if not canUseBuildingThisTown("Cathedral") then
    broadcastToAll("[" .. self.getName() .. "] Cathedral: No uses remaining this town.", {0.95, 0.45, 0.2})
    return
  end
  showCathedralInput()
end
function click_xpBlacksmith()
  local blockedUp = isTownActionBlocked("upgrade")
  local blockedAug = isTownActionBlocked("augment")
  if blockedUp or blockedAug then
    broadcastToAll("[" .. self.getName() .. "] Cursed Pumpkins is active: Blacksmith actions are disabled.", {0.95, 0.45, 0.2})
    return
  end
  showBlacksmithScreen()
end
function click_xpBazaar()
  if not canUseBuildingThisTown("Bazaar") then
    broadcastToAll("[" .. self.getName() .. "] Bazaar: No uses remaining this town.", {0.95, 0.45, 0.2})
    return
  end
  showBazaarScreen()
end
function click_experienceBack() showShopScreen()     end

function showBuyScreen()
  openScreen("buy", nil, "XP Shop")
  local xs = {-1.7, 0, 1.7}
  local zs = {-0.2, 0.7}
  local packs = {
    {"mystery", "Mystery"}, {"identity", "Identity"}, {"pro", "Pro"},
    {"mythic", "Mythic"},   {"otag", "OTAG"},
  }
  for i, p in ipairs(packs) do
    local row = math.ceil(i / 3)
    local col = ((i - 1) % 3) + 1
    drawPackButton(xs[col], zs[row], p[1], p[2])
  end
  trackButton({
    click_function = "click_buyBack", function_owner = self,
    label = "Back",
    position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function drawPackButton(x, z, packKey, displayName)
  local cost = getMerchantPackCost(packKey)
  local isLocked = isMerchantPackLockedForTown(packKey)
  local label = displayName .. "\n" .. tostring(cost) .. " XP"
  if isLocked then label = displayName .. "\nSOLD (THIS TOWN)" end
  trackButton({
    click_function = isLocked and "xp_noop" or ("click_buy_" .. packKey), function_owner = self,
    label = label,
    position = {x, 0.1, z},
    width = 500, height = 320, font_size = 80,
    color = isLocked and {0.32, 0.12, 0.12} or {0.18, 0.18, 0.28}, font_color = {1, 1, 1},
  })
end

function click_buyBack() showExperienceScreen() end
function click_buy_mystery()  tryOpenPackInput("mystery")  end
function click_buy_identity() tryOpenPackInput("identity") end
function click_buy_pro()      tryOpenPackInput("pro")      end
function click_buy_set()      tryOpenPackInput("set")      end
function click_buy_mythic()   tryOpenPackInput("mythic")   end
function click_buy_otag()     tryOpenPackInput("otag")     end

--==============================================================================
-- PORTAL SCREEN
--==============================================================================
function resetPortalInput()
  portalInput = { termType=1, termOp=1, termValue="", count=5 }
end

function getPortalMaxCount()
  return portalTravelerFungalLichActive and 20 or 15
end

function grantFungalLichPortalBonus()
  if portalTravelerFungalLichActive then return end
  portalTravelerFungalLichActive = true
  broadcastToAll("[" .. self.getName() .. "] Fungal Lich: Portal now allows up to 20 XP this town.", {0.5, 0.8, 0.45})
  if currentScreen == "input" and activePack == "portal" then
    openPortalInput()
  end
end

function receiveTravelerEffect(params)
  if type(params) ~= "table" then return end
  local travelerName = tostring(params.name or params.traveler or params.effect or "")
  local lowered = travelerName:lower()
  if lowered:match("fungal lich") then
    grantFungalLichPortalBonus()
  end
end

function refreshPortalPreviewLabels()
  local portalMaxCount = getPortalMaxCount()
  if portalCountLabelButtonIndex and self.editButton then
    pcall(function() self.editButton({index = portalCountLabelButtonIndex, label = "Count (1-" .. tostring(portalMaxCount) .. ")"}) end)
  end
  if portalProjectedLabelButtonIndex and self.editButton then
    pcall(function() self.editButton({index = portalProjectedLabelButtonIndex, label = tostring(getEffectivePortalPackCount(portalInput.count))}) end)
  end
end

function openPortalInput()
  if activePack ~= "portal" then
    resetPortalInput()
    resetPackInput()
  end
  activePack = "portal"
  portalCountLabelButtonIndex = nil
  portalProjectedLabelButtonIndex = nil
  openScreen("input", nil)
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Temporal Pack  —  1 XP per card",
    position = {-0.1, 0.1, -1.05},
    width = 1100, height = 130, font_size = 67,
    color = LABEL_BG, font_color = {0, 0, 0},
  })
  drawColorToggles(-0.4)
  drawPortalTermSlot(0.15)
  local portalMaxCount = getPortalMaxCount()
  portalCountLabelButtonIndex = trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Count (1-" .. tostring(portalMaxCount) .. ")",
    position = {-1.2, 0.1, 0.72},
    width = 700, height = 180, font_size = 82,
    color = LABEL_BG, font_color = {0, 0, 0},
  })
  trackInput({
    input_function = "portal_count_input", function_owner = self,
    label = "5", value = tostring(portalInput.count),
    alignment = TTS_INPUT_ALIGN_RIGHT, validation = TTS_INPUT_VALIDATION_INT,
    position = {1.2, 0.1, 0.72},
    width = 400, height = 180, font_size = 100,
    color = {1, 1, 1}, font_color = {0, 0, 0},
  })
  portalProjectedLabelButtonIndex = trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "" .. tostring(getEffectivePortalPackCount(portalInput.count)),
    position = {2, 0.1, 0.72},
    width = 180, height = 180, font_size = 60,
    color = {0.92, 0.95, 0.98}, font_color = {0, 0, 0},
  })
  trackButton({
    click_function = "click_inputCancel", function_owner = self,
    label = "Cancel", position = {-1.1, 0.1, 1.25},
    width = 500, height = 130, font_size = 80,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_inputEnter", function_owner = self,
    label = "Confirm", position = {1.1, 0.1, 1.25},
    width = 500, height = 130, font_size = 80,
    color = {0.15, 0.5, 0.15}, font_color = {1, 1, 1},
  })
end

function drawPortalTermSlot(z)
  local termType  = PORTAL_TERM_TYPES[portalInput.termType] or "type"
  local opList    = PORTAL_TERM_OPS[termType] or {":"}
  local termOp    = opList[portalInput.termOp] or opList[1]
  trackButton({
    click_function = "click_portalTermType", function_owner = self,
    label = termType,
    position = {-1.65, 0.1, z},
    width = 460, height = 180, font_size = 80,
    color = {0.1, 0.25, 0.4}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_portalTermOp", function_owner = self,
    label = termOp,
    position = {-0.85, 0.1, z},
    width = 380, height = 180, font_size = 90,
    color = {0.25, 0.1, 0.35}, font_color = {1, 1, 1},
  })
  trackInput({
    input_function = "portal_term_input", function_owner = self,
    label = "value", value = portalInput.termValue,
    alignment = TTS_INPUT_ALIGN_RIGHT, validation = TTS_INPUT_VALIDATION_NONE,
    position = {1.15, 0.1, z},
    width = 650, height = 180, font_size = 90,
    color = {1, 1, 1}, font_color = {0, 0, 0},
    char_limit = 0,
  })
end

function click_portalTermType()
  portalInput.termType = (portalInput.termType % #PORTAL_TERM_TYPES) + 1
  portalInput.termOp   = 1
  openPortalInput()
end
function click_portalTermOp()
  local t = PORTAL_TERM_TYPES[portalInput.termType] or "type"
  local n = #(PORTAL_TERM_OPS[t] or {":"})
  portalInput.termOp = (portalInput.termOp % n) + 1
  openPortalInput()
end
function portal_term_input(_, _, v)  portalInput.termValue = v or "" end
function portal_count_input(_, _, v)
  local n = tonumber(v)
  if n then
    portalInput.count = math.max(1, math.min(getPortalMaxCount(), math.floor(n)))
  else
    portalInput.count = 5
  end
  refreshPortalPreviewLabels()
end

function buildPortalQuery()
  local parts = {}
  local c = colorString()
  if c ~= "" then table.insert(parts, "id" .. (packInput.colorOp or ":") .. c) end
  if portalInput.termValue ~= "" then
    local t   = PORTAL_TERM_TYPES[portalInput.termType] or "type"
    local ops = PORTAL_TERM_OPS[t] or {":"}
    local op  = ops[portalInput.termOp] or ops[1]
    table.insert(parts, t .. op .. portalInput.termValue)
  end
  return table.concat(parts, "+")
end

function attemptPortalPurchase()
  local count = math.max(1, math.min(getPortalMaxCount(), portalInput.count or 5))
  local effectiveCount = getEffectivePortalPackCount(count)
  local cost  = count
  if xp < cost then
    broadcastToAll("[" .. self.getName() .. "] Not enough XP for Temporal Pack (need "
      .. cost .. ", have " .. xp .. ").", {0.9, 0.3, 0.3})
    return
  end
  local q = buildPortalQuery()
  if not q or q == "" then
    broadcastToAll("[" .. self.getName() .. "] Set at least one filter for a Temporal Pack.", {0.9, 0.3, 0.3})
    return
  end
  xp = math.max(XP_MIN, xp - cost)
  recordXPTransaction(-cost, "Temporal Pack (" .. count .. " cards)")
  decrementBuildingUse("Portal")
  notifyMasters()
  broadcastToAll("[" .. self.getName() .. "] Temporal Pack (" .. effectiveCount .. " cards) for "
    .. cost .. " XP (" .. xp .. " remaining).", {0.4, 0.85, 0.4})
  postBuildNDJSON({ q=q, count=effectiveCount, enforceCommander=true, forceApi=false, back=backURL },
    function(wr)
      if not wr.is_done then return end
      local hasError = wr.is_error or (wr.response_code and wr.response_code >= 400)
      if hasError or not wr.text or wr.text == "" then
        refundXP(cost, "Temporal Pack Refund (fetch error)"); refreshEssenceDisplay()
        broadcastToAll("[" .. self.getName() .. "] Temporal Pack fetch failed. XP refunded.", {0.9, 0.3, 0.3})
        return
      end
      local deck = firstDeckFromNDJSON(wr.text)
      if not deck then
        refundXP(cost, "Temporal Pack Refund (no cards)"); refreshEssenceDisplay()
        broadcastToAll("[" .. self.getName() .. "] Temporal Pack returned no cards. XP refunded.", {0.9, 0.3, 0.3})
        return
      end
      prefixDeckNicknames(deck, "[Temporal]")
      spawnPackDeck(deck)
    end)
  showExperienceScreen()
end

--==============================================================================
-- MYSTIC SCREEN
--==============================================================================
function showMysticScreen()
  activePack = nil
  pendingMysticCard = nil
  pendingMysticCMC  = nil
  openScreen("mystic_prompt", nil, "Mystic")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Drop a card here to disenchant it.\n5 XP -> 2x its Mana Value in Essence",
    position = {0, 0.1, 0.05},
    width = 1700, height = 350, font_size = 75,
    color = {0.18, 0.1, 0.25}, font_color = {0.9, 0.8, 1.0},
  })
  trackButton({
    click_function = "click_mysticBack", function_owner = self,
    label = "Back", position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end
function click_mysticBack() showExperienceScreen() end

function showMysticConfirm(displayName, cmc)
  openScreen("mystic_confirm", nil, "Disenchant?")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = displayName,
    position = {0, 0.1, -0.35},
    width = 1700, height = 200, font_size = 75,
    color = {0.2, 0.15, 0.3}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Gain " .. (cmc * 2) .. " Essence   (Cost: 5 XP)",
    position = {0, 0.1, 0.2},
    width = 1700, height = 200, font_size = 80,
    color = {0.15, 0.1, 0.2}, font_color = {0.7, 1.0, 0.8},
  })
  trackButton({
    click_function = "click_mysticCancel", function_owner = self,
    label = "Cancel", position = {-1.1, 0.1, 1.0},
    width = 500, height = 200, font_size = 90,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_mysticConfirm", function_owner = self,
    label = "Disenchant", position = {1.1, 0.1, 1.0},
    width = 700, height = 200, font_size = 80,
    color = {0.35, 0.1, 0.45}, font_color = {1, 1, 1},
  })
end

function click_mysticConfirm()
  if not pendingMysticCard or not pendingMysticCMC then showMysticScreen() return end
  if xp < 5 then
    broadcastToAll("[" .. self.getName() .. "] Not enough XP to disenchant (need 5).", {0.9, 0.3, 0.3})
    showMysticScreen()
    return
  end
  local cmc  = pendingMysticCMC
  local gain = cmc * 2
  xp = math.max(XP_MIN, xp - 5)
  recordXPTransaction(-5, "Disenchant")
  notifyMasters()
  applyEssenceDeltaTracked(gain, "Disenchant")
  broadcastToAll("[" .. self.getName() .. "] Disenchanted for +" .. gain
    .. " Essence (CMC " .. cmc .. "). -5 XP.", {0.7, 0.5, 1.0})
  pcall(function() pendingMysticCard.destruct() end)
  pendingMysticCard = nil
  pendingMysticCMC  = nil
  showMysticScreen()
end

function click_mysticCancel()
  pendingMysticCard = nil
  pendingMysticCMC  = nil
  showMysticScreen()
end

function handleMysticDrop(obj)
  local tag = ""
  pcall(function() tag = obj.tag or "" end)
  if tag ~= "Card" then
    broadcastToAll("[" .. self.getName() .. "] Mystic: drop a single card (not a deck).", {0.9, 0.6, 0.3})
    return
  end
  lookupCardCMC(obj, function(cmc)
    if not cmc then
      broadcastToAll("[" .. self.getName() .. "] Mystic: couldn't determine CMC for this card.", {0.9, 0.3, 0.3})
      return
    end
    pendingMysticCard = obj
    pendingMysticCMC  = cmc
    local rawName    = ""
    pcall(function() rawName = obj.getName() or "" end)
    local displayName = rawName:match("^([^\n]*)") or rawName
    if displayName == "" then displayName = "Unknown Card" end
    showMysticConfirm(displayName, cmc)
  end)
end

function lookupCardCMC(obj, callback)
  local name = ""
  pcall(function() name = obj.getName() or "" end)
  local cmc = extractCMCFromName(name)
  if cmc then callback(cmc) return end
  local rawName = name:match("^([^\n]+)") or name
  rawName = rawName:gsub("%s+", "%%20")
  if rawName == "" then callback(nil) return end
  local url = "https://api.scryfall.com/cards/named?exact=" .. rawName
  WebRequest.custom(url, "GET", true, nil,
    { ["User-Agent"] = "MTGRoguelikeSpawner/2.0 (TTS mod; contact mtd.danab@gmail.com)" },
    function(wr)
      if wr.is_error or not wr.text then callback(nil) return end
      local v = wr.text:match('"cmc"%s*:%s*([%d%.]+)')
      callback(v and math.floor(tonumber(v)) or nil)
    end)
end

function showSellConfirm(displayName, cmc)
  openScreen("sell_confirm", nil, "Sell for Essence?")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = displayName,
    position = {0, 0.1, -0.35},
    width = 1700, height = 200, font_size = 75,
    color = {0.2, 0.15, 0.3}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Gain " .. (cmc * 2) .. " Essence   (CMC: " .. cmc .. ")",
    position = {0, 0.1, 0.2},
    width = 1700, height = 200, font_size = 80,
    color = {0.15, 0.1, 0.2}, font_color = {0.7, 1.0, 0.8},
  })
  trackButton({
    click_function = "click_sellCancel", function_owner = self,
    label = "Cancel", position = {-1.1, 0.1, 1.0},
    width = 500, height = 200, font_size = 90,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_sellConfirm", function_owner = self,
    label = "Sell", position = {1.1, 0.1, 1.0},
    width = 700, height = 200, font_size = 80,
    color = {0.35, 0.1, 0.45}, font_color = {1, 1, 1},
  })
end

function click_sellConfirm()
  if not pendingSellCard or not pendingSellCMC then enterSellMode() return end
  if pendingSell.cardsToSell >= pendingSell.maxCards then
    broadcastToAll("[" .. self.getName() .. "] You've already sold your maximum of " .. pendingSell.maxCards .. " cards.", {0.9, 0.3, 0.3})
    enterSellMode()
    return
  end
  
  local cmc  = pendingSellCMC
  local isDeck = pendingSellIsDeck or false
  local cardsBeingSold = isDeck and 2 or 1
  
  -- Check if selling this would exceed limit
  if pendingSell.cardsToSell + cardsBeingSold > pendingSell.maxCards then
    broadcastToAll("[" .. self.getName() .. "] Can't sell " .. cardsBeingSold .. " cards - would exceed the 2-card limit.", {0.9, 0.3, 0.3})
    enterSellMode()
    return
  end
  
  local gain = cmc * 2
  xp = xp + gain
  recordXPTransaction(gain, "Trader: Sell Card" .. (isDeck and "s" or ""))
  pendingSellXPEarned = pendingSellXPEarned + gain
  pendingSell.cardsToSell = pendingSell.cardsToSell + cardsBeingSold
  broadcastToAll("[" .. self.getName() .. "] Sold " .. (isDeck and "deck" or "card") .. " for +" .. gain
    .. " XP (total CMC " .. cmc .. ").", {0.7, 1.0, 0.7})
  notifyMasters()
  refreshXPDisplay()
  pcall(function() pendingSellCard.destruct() end)
  pendingSellCard = nil
  pendingSellCMC  = nil
  pendingSellIsDeck = false
  
  -- Auto-exit if we've sold the maximum (2 cards)
  if pendingSell.cardsToSell >= pendingSell.maxCards then
    click_sellModeCancel()
  else
    enterSellMode()
  end
end

function click_sellCancel()
  pendingSellCard = nil
  pendingSellCMC  = nil
  pendingSellIsDeck = false
  enterSellMode()
end

function click_sellModeCancel()
  pendingSellCard = nil
  pendingSellCMC  = nil
  pendingSellIsDeck = false
  if pendingSellXPEarned > 0 then
    showTraderSellSummary()
  else
    pendingSell = nil
    currentScreen = nil
    showShopScreen()
  end
end

function showTraderSellSummary()
  openScreen("trader_sell_summary", nil, "Trader: Cards Sold")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Total Earned",
    position = {0, 0.1, -0.5},
    width = 1200, height = 170, font_size = 95,
    color = {0.3, 0.15, 0.1}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = pendingSellXPEarned .. " XP",
    position = {0, 0.1, 0.15},
    width = 1400, height = 250, font_size = 110,
    color = {0.2, 0.15, 0.25}, font_color = {0.85, 1.0, 0.75},
  })
  trackButton({
    click_function = "click_tradeSellSummaryOK", function_owner = self,
    label = "Continue",
    position = {0, 0.1, 1.2}, width = 700, height = 150, font_size = 80,
    color = {0.15, 0.45, 0.15}, font_color = {1, 1, 1},
  })
end

function click_tradeSellSummaryOK()
  pendingSell = nil
  pendingSellXPEarned = 0
  currentScreen = nil
  showShopScreen()
end

function handleSellModeDrop(obj)
  local tag = ""
  pcall(function() tag = obj.tag or "" end)
  
  if tag == "Card" then
    -- Single card sale
    lookupCardCMC(obj, function(cmc)
      if not cmc then
        broadcastToAll("[" .. self.getName() .. "] Trader: couldn't determine CMC for this card.", {0.9, 0.3, 0.3})
        return
      end
      pendingSellCard = obj
      pendingSellCMC  = cmc
      pendingSellIsDeck = false
      local rawName    = ""
      pcall(function() rawName = obj.getName() or "" end)
      local displayName = rawName:match("^([^\n]*)") or rawName
      if displayName == "" then displayName = "Unknown Card" end
      showSellConfirm(displayName, cmc)
    end)
  elseif tag == "Deck" then
    -- Deck sale - must be exactly 2 cards
    local deckObjects = {}
    pcall(function() deckObjects = obj.getObjects() or {} end)
    
    if #deckObjects ~= 2 then
      broadcastToAll("[" .. self.getName() .. "] Trader: decks must contain exactly 2 cards.", {0.9, 0.3, 0.3})
      return
    end
    
    -- Look up CMC for both cards and calculate total
    local totalCMC = 0
    local cardsProcessed = 0
    local function processDeckCard(index, cardData)
      -- Create a wrapper object since cardData from getObjects() is just a table, not a TTS object
      local cardWrapper = {
        getName = function() return cardData.name or "Unknown Card" end
      }
      lookupCardCMC(cardWrapper, function(cmc)
        cardsProcessed = cardsProcessed + 1
        totalCMC = totalCMC + (cmc or 0)
        
        if cardsProcessed == 2 then
          pendingSellCard = obj
          pendingSellCMC  = totalCMC
          pendingSellIsDeck = true
          local deckName = ""
          pcall(function() deckName = obj.getName() or "" end)
          local displayName = deckName:match("^([^\n]*)") or deckName
          if displayName == "" then displayName = "Deck" end
          displayName = displayName .. " (2 cards)"
          showSellConfirm(displayName, totalCMC)
        end
      end)
    end
    
    for i, cardData in ipairs(deckObjects) do
      processDeckCard(i, cardData)
    end
  else
    broadcastToAll("[" .. self.getName() .. "] Trader: drop a single card or a 2-card deck.", {0.9, 0.6, 0.3})
    return
  end
end

--==============================================================================
-- BLACKSMITH SCREEN
--==============================================================================
function showBlacksmithScreen()
  openScreen("blacksmith", nil, "Blacksmith")
  local BW, BH, BF = 700, 280, 70
  local upgradeCost, upgradeFree = getTownActionCost("upgrade")
  trackButton({
    click_function = "click_blacksmithUpgrade", function_owner = self,
    label = "Upgrade\n" .. (upgradeFree and "Free" or tostring(upgradeCost) .. " XP"),
    position = {-0.75, 0.1, 0.15},
    width = BW, height = BH, font_size = BF,
    color = {0.15, 0.3, 0.12}, font_color = {0.8, 1.0, 0.7},
    tooltip = "Submit a card to be upgraded — " .. UPGRADE_COST .. " XP",
  })
  local augmentCost, augmentFree = getTownActionCost("augment")
  trackButton({
    click_function = "click_blacksmithAugment", function_owner = self,
    label = "Augment\n" .. (augmentFree and "Free" or tostring(augmentCost) .. " XP"),
    position = {0.75, 0.1, 0.15},
    width = BW, height = BH, font_size = BF,
    color = {0.28, 0.18, 0.08}, font_color = {1.0, 0.88, 0.55},
    tooltip = "Submit a card for augment — " .. AUGMENT_COST .. " XP — host may return multiple versions",
  })
  trackButton({
    click_function = "click_blacksmithBack", function_owner = self,
    label = "Back",
    position = {-1.6, 0.1, 1.38},
    width = 450, height = 185, font_size = 85,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end
function click_blacksmithBack()    showExperienceScreen()   end
function click_blacksmithUpgrade()
  showUpgradeInput("upgrade")
end
function click_blacksmithAugment()
  showUpgradeInput("augment")
end

--==============================================================================
-- BAZAAR SCREEN
--==============================================================================
function showBazaarScreen()
  pendingBazaarCard = nil
  pendingBazaarMode = nil
  pendingBazaarCMC  = nil
  openScreen("bazaar", nil, "Bazaar")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Sell tokens or cards for Essence",
    position = {0, 0.1, -0.45},
    width = 1500, height = 150, font_size = 65,
    color = {0.2, 0.15, 0.08}, font_color = {0.9, 0.85, 0.7},
  })
  trackButton({
    click_function = "click_bazaarCashOut", function_owner = self,
    label = "Cash Out\n10 XP",
    position = {-0.75, 0.1, 0.2},
    width = 700, height = 280, font_size = 75,
    color = {0.4, 0.28, 0.05}, font_color = {1, 0.9, 0.5},
    tooltip = "Sell a token (T# - Name) for 10 Essence",
  })
  trackButton({
    click_function = "click_bazaarSellCMC", function_owner = self,
    label = "Sell by CMC\n2x Mana Value",
    position = {0.75, 0.1, 0.2},
    width = 700, height = 280, font_size = 70,
    color = {0.28, 0.2, 0.35}, font_color = {0.85, 0.75, 1},
    tooltip = "Sell any card for 2x its CMC in Essence",
  })
  trackButton({
    click_function = "click_bazaarBack", function_owner = self,
    label = "Back",
    position = {-1.6, 0.1, 1.38},
    width = 450, height = 185, font_size = 85,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end
function click_bazaarBack()    showExperienceScreen()    end
function click_bazaarCashOut() showBazaarCashOutPrompt() end
function click_bazaarSellCMC() showBazaarSellCMCPrompt() end

function showBazaarCashOutPrompt()
  pendingBazaarCard = nil
  pendingBazaarMode = "cashout"
  pendingBazaarCMC  = nil
  openScreen("bazaar_cashout_prompt", nil, "Cash Out")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Drop a token here — 10 XP",
    position = {0, 0.1, 0.05},
    width = 1700, height = 350, font_size = 68,
    color = {0.25, 0.18, 0.05}, font_color = {1, 0.9, 0.6},
  })
  trackButton({
    click_function = "click_bazaarCashOutBack", function_owner = self,
    label = "Back",
    position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end
function click_bazaarCashOutBack() showBazaarScreen() end

function showBazaarSellCMCPrompt()
  pendingBazaarCard = nil
  pendingBazaarMode = "cmc"
  pendingBazaarCMC  = nil
  openScreen("bazaar_cmc_prompt", nil, "Sell by CMC")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Drop a card here — gain 2x its Mana Value in Essence",
    position = {0, 0.1, 0.05},
    width = 1700, height = 350, font_size = 72,
    color = {0.18, 0.12, 0.25}, font_color = {0.9, 0.8, 1.0},
  })
  trackButton({
    click_function = "click_bazaarSellCMCBack", function_owner = self,
    label = "Back",
    position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end
function click_bazaarSellCMCBack() showBazaarScreen() end

function showBazaarConfirm(displayName, gain, currency)
  openScreen("bazaar_confirm", nil, "Sell at Bazaar?")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = displayName,
    position = {0, 0.1, -0.35},
    width = 1700, height = 200, font_size = 72,
    color = {0.25, 0.18, 0.08}, font_color = {1, 0.9, 0.6},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Gain " .. tostring(gain) .. " " .. (currency or "Essence"),
    position = {0, 0.1, 0.2},
    width = 1700, height = 200, font_size = 80,
    color = {0.15, 0.12, 0.2}, font_color = {0.7, 1.0, 0.8},
  })
  trackButton({
    click_function = "click_bazaarCancel", function_owner = self,
    label = "Cancel",
    position = {-1.1, 0.1, 1.0},
    width = 500, height = 200, font_size = 90,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_bazaarConfirmOK", function_owner = self,
    label = "Sell",
    position = {1.1, 0.1, 1.0},
    width = 500, height = 200, font_size = 90,
    color = {0.4, 0.28, 0.05}, font_color = {1, 0.9, 0.5},
  })
end

function click_bazaarCancel()
  local mode = pendingBazaarMode
  pendingBazaarCard = nil
  pendingBazaarCMC  = nil
  if mode == "cashout" then
    showBazaarCashOutPrompt()
  else
    showBazaarSellCMCPrompt()
  end
end

function click_bazaarConfirmOK()
  local card = pendingBazaarCard
  local mode = pendingBazaarMode
  local cmc  = pendingBazaarCMC
  pendingBazaarCard = nil
  pendingBazaarMode = nil
  pendingBazaarCMC  = nil
  if not card then showBazaarScreen() return end
  decrementBuildingUse("Bazaar")
  local rawName = ""
  pcall(function() rawName = card.getName() or "" end)
  local displayName = rawName:match("^([^\n]*)") or rawName
  if displayName == "" then displayName = "?" end
  if mode == "cashout" then
    receiveXP({amount = 10})
    broadcastToAll("[" .. self.getName() .. "] Cashed out " .. displayName .. " for +10 XP.", {1, 0.9, 0.5})
  elseif mode == "cmc" then
    local gain = (cmc or 0) * 2
    applyEssenceDeltaTracked(gain, "Bazaar Sell CMC: " .. displayName)
    broadcastToAll("[" .. self.getName() .. "] Sold " .. displayName .. " (CMC " .. tostring(cmc or 0) .. ") for +" .. gain .. " Essence.", {0.7, 0.5, 1.0})
  end
  pcall(function() card.destruct() end)
  showBazaarScreen()
end

function isBazaarSellableObject(obj)
  local tag = ""
  pcall(function() tag = obj.tag or "" end)
  if tag == "Card" then return true end
  local data = nil
  pcall(function() data = obj.getData() end)
  -- Edit note: Allow Bazaar cash-out to accept dropped Custom_Model objects. Signed, Sirin.
  if type(data) == "table" and data.Name == "Custom_Model" then
    return true
  end
  return false
end

function handleBazaarCashOutDrop(obj)
  if not isBazaarSellableObject(obj) then
    broadcastToAll("[" .. self.getName() .. "] Bazaar: drop a single cashout token.", {0.9, 0.6, 0.3})
    return
  end
  local name = ""
  pcall(function() name = obj.getName() or "" end)
  local firstName = name:match("^([^\n]*)") or name
  if not firstName:match("^T%d+%s*%-") then
    broadcastToAll("[" .. self.getName() .. "] Bazaar: not a Cash Out token — name must start like \"T3 - Bonus Guild\".", {0.9, 0.3, 0.3})
    return
  end
  pendingBazaarCard = obj
  pendingBazaarMode = "cashout"
  pendingBazaarCMC  = nil
  showBazaarConfirm(firstName, 10, "XP")
end

function handleBazaarSellCMCDrop(obj)
  if not isBazaarSellableObject(obj) then
    broadcastToAll("[" .. self.getName() .. "] Bazaar: drop a single card (not a deck).", {0.9, 0.6, 0.3})
    return
  end
  lookupCardCMC(obj, function(cmc)
    if not cmc then
      broadcastToAll("[" .. self.getName() .. "] Bazaar: couldn't determine CMC for this card.", {0.9, 0.3, 0.3})
      return
    end
    pendingBazaarCard = obj
    pendingBazaarMode = "cmc"
    pendingBazaarCMC  = cmc
    local rawName = ""
    pcall(function() rawName = obj.getName() or "" end)
    local displayName = rawName:match("^([^\n]*)") or rawName
    if displayName == "" then displayName = "Unknown Card" end
    showBazaarConfirm(displayName, cmc * 2)
  end)
end

--==============================================================================
-- MERCHANT PACK CASHOUT REDEMPTION
--==============================================================================

-- Merchant Pack definitions with setup functions to pre-populate filters
-- When a cashout is redeemed, the pack input screen opens with these values pre-filled
MERCHANT_PACKS = {
  -- T1 Packs (Simple, opens to basic preset)
  ["Mono White Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=true, U=false, B=false, R=false, G=false}
      packInput.colorOp = ":"
    end,
  },
  ["Mono Blue Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=false, U=true, B=false, R=false, G=false}
      packInput.colorOp = ":"
    end,
  },
  ["Mono Black Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=false, U=false, B=true, R=false, G=false}
      packInput.colorOp = ":"
    end,
  },
  ["Mono Red Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=true, G=false}
      packInput.colorOp = ":"
    end,
  },
  ["Mono Green Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=true}
      packInput.colorOp = ":"
    end,
  },
  ["Mono Colorless Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=true}
      packInput.colorOp = ":"
    end,
  },
  ["Colorless Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=true}
      packInput.colorOp = ":"
    end,
  },
  ["Mystery Pack"] = {
    tier = 1,
    packType = "mystery",
    setup = function()
      -- Mystery pack has no special setup
    end,
  },
  ["Enchantment Pack"] = {
    tier = 1,
    packType = "pro",
    setup = function()
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = "enchantment"
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=false}
    end,
  },
  ["ID Pack"] = {
    tier = 1,
    packType = "identity",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false}
      packInput.colorOp = ":"
    end,
  },
  ["Planeswalker Pack"] = {
    tier = 1,
    packType = "pro",
    setup = function()
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = "planeswalker"
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=false}
    end,
  },
  
  -- T2 Packs (Advanced, opens to customizable preset)
  ["Mono White Pro Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=true, U=false, B=false, R=false, G=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
    end,
  },
  ["Mono Blue Pro Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=true, B=false, R=false, G=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
    end,
  },
  ["Mono Black Pro Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=false, B=true, R=false, G=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
    end,
  },
  ["Mono Red Pro Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=true, G=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
    end,
  },
  ["Mono Green Pro Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=true}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
    end,
  },
  ["Mono Colorless Pro Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=true}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
    end,
  },
  ["Artifact Pack"] = {
    tier = 1,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = "artifact"
    end,
  },
  ["Artifact Pro Pack"] = {
    tier = 2,
    packType = "mythic",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = "artifact"
      packInput.termType2 = 1
      packInput.termOp2 = 1
      packInput.termValue2 = ""
    end,
  },
  ["ID Enchantment Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = "enchantment"
    end,
  },
  ["ID Planeswalker Pack"] = {
    tier = 2,
    packType = "mythic",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = "planeswalker"
      packInput.termType2 = 1
      packInput.termOp2 = 1
      packInput.termValue2 = ""
    end,
  },
  ["Set Pack"] = {
    tier = 2,
    packType = "otag",
    setup = function()
      packInput.otag = ""
      packInput.colors = {W=false, U=false, B=false, R=false, G=false}
    end,
  },
  ["Colorless Pro Pack"] = {
    tier = 2,
    packType = "pro",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=true}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
    end,
  },
  ["Mythic Pack"] = {
    tier = 2,
    packType = "mythic",
    setup = function()
      packInput.colors = {W=false, U=false, B=false, R=false, G=false, C=false}
      packInput.termType1 = 1
      packInput.termOp1 = 1
      packInput.termValue1 = ""
      packInput.termType2 = 1
      packInput.termOp2 = 1
      packInput.termValue2 = ""
    end,
  },
}

-- Cache for pending merchant pack cashout
pendingMerchantPackCashout = nil  -- Stores {object, packName} while redeeming

function handleMerchantPackCashoutDrop(obj, packName)
  if not obj then return end
  
  local packDef = MERCHANT_PACKS[packName]
  if not packDef then
    broadcastToAll("[" .. self.getName() .. "] Merchant Pack: \"" .. packName .. "\" is not recognized.", {0.9, 0.3, 0.3})
    ess_safeDestructObject(obj)
    return
  end
  
  -- Mystery packs have no filters to configure — spawn immediately without
  -- touching pendingMerchantPackCashout so the flag can never get stuck.
  if packDef.packType == "mystery" then
    broadcastToAll("[" .. self.getName() .. "] Redeeming Merchant Pack: " .. packName, {0.5, 0.85, 0.5})
    spawnMysteryPack(0, "mystery")
    ess_safeDestructObject(obj)
    requestSync(DEBOUNCE_SECONDS)
    showRedeemCashoutScreen()
    return
  end

  -- Store the cashout token reference
  pendingMerchantPackCashout = {
    object = obj,
    packName = packName,
  }
  
  -- Reset pack input and apply setup
  resetPackInput()
  packDef.setup()
  
  -- Open the merchant pack input screen
  activePack = packDef.packType
  openPackInput(packDef.packType)
  
  broadcastToAll("[" .. self.getName() .. "] Merchant Pack: \"" .. packName .. "\" ready. Customize filters if desired.", {0.5, 0.85, 0.5})
end

function resetPackInput()
  packInput = {
    colors    = {W=false, U=false, B=false, R=false, G=false, C=false},
    colorOp   = ":",
    termType1 = 1,
    termOp1   = 1,
    termValue1 = "",
    termType2 = 1,
    termOp2   = 1,
    termValue2 = "",
    otag      = "",
  }
end

function handleRedeemCashoutDrop(obj)
  if not obj then return end
  local rawName = ""
  pcall(function() rawName = obj.getName() or "" end)
  if rawName == "" then
    broadcastToAll("[" .. self.getName() .. "] Redeem Cashout: invalid token.", {0.9, 0.3, 0.3})
    return
  end

  local firstName = rawName:match("^([^\n]*)") or rawName
  if not firstName:match("^T%d+%s*%-") then
    broadcastToAll("[" .. self.getName() .. "] Redeem Cashout: not a Cashout token — name must start like \"T2 - Bonus...\" or \"T1 - Mono Green Pack\".", {0.9, 0.3, 0.3})
    return
  end

  -- Check if this is a Merchant Pack cashout
  if firstName:match("Pack") then
    -- Extract pack name: "T1 - Mono Green Pack" -> "Mono Green Pack"
    local packName = firstName:match("T%d+%s*%-[%s]*(.+)$")
    if packName then
      packName = packName:gsub("^%s*", ""):gsub("%s*$", "")  -- Trim whitespace
      handleMerchantPackCashoutDrop(obj, packName)
      return
    end
  end

  -- Otherwise, handle as Bonus cashout
  -- Extract bonus type and name
  -- Expected formats: "T2 - Bonus Tavern", "T2 - Free Augment", etc.
  local bonusType, bonusName = firstName:match("T%d+%s*%-[%s]*([%w]+)[%s]+(.+)$")
  
  if not bonusType or not bonusName then
    broadcastToAll("[" .. self.getName() .. "] Redeem Cashout: could not parse token name.", {0.9, 0.3, 0.3})
    return
  end

  bonusName = bonusName:gsub("^%s*", ""):gsub("%s*$", "")  -- Trim whitespace

  -- Map special names to buildings or Blacksmith-specific action bonuses.
  -- "Mystic" and "Guild" are XP-gated (no limit)
  local buildingKey = nil
  if bonusName == "Augment" then
    buildingKey = "Blacksmith:Augment"
  elseif bonusName == "Upgrade" then
    buildingKey = "Blacksmith:Upgrade"
  elseif bonusName == "Mystic" then
    buildingKey = "Mystic"
  elseif bonusName == "Guild" then
    buildingKey = "Guild"
  else
    -- Check for specific building names
    for building, _ in pairs(BUILDING_LIMITS) do
      if building:lower() == bonusName:lower() then
        buildingKey = building
        break
      end
    end
  end
  
  if not buildingKey then
    broadcastToAll("[" .. self.getName() .. "] Redeem Cashout: \"" .. bonusName .. "\" is not a recognized building.", {0.9, 0.3, 0.3})
    return
  end
  
  bonusBuildingUsesByKey[buildingKey] = (bonusBuildingUsesByKey[buildingKey] or 0) + 1
  broadcastToAll("[" .. self.getName() .. "] Bonus Use granted: " .. buildingKey, {0.5, 0.8, 0.5})

  -- Destroy the cashout token
  ess_safeDestructObject(obj)

  -- Return to shop
  requestSync(DEBOUNCE_SECONDS)
  showShopScreen()
end

--==============================================================================
-- GUILD SCREEN
--==============================================================================
function showGuildScreen()
  activePack = "guild"
  local cost = applyTownCostModifiers(GUILD_ROLL_COST)
  local guildBonusChoices = getGuildCommanderChoiceBonusFromBrands()
  local recurrenceRanks = getBrandRankByName("Brand of Recurrence")
  local brandLine = (guildBonusChoices > 0)
    and ("\nBrand of the Conclave: +" .. tostring(guildBonusChoices) .. " commander choices")
    or ""
  if recurrenceRanks > 0 then
    brandLine = brandLine .. "\nBrand of Recurrence: " .. tostring(recurrenceRanks) .. " free reroll(s)"
  end
  openScreen("guild_input", nil, "Guild Hall")
  drawColorToggles(-0.35)
  trackButton({
    click_function = "click_guildRoll", function_owner = self,
    label = "Roll for Commanders!",
    tooltip = tostring(cost) .. " XP — Roll a d6, then receive Roll+2 random commanders matching your chosen color identity" .. brandLine,
    position = {0.3, 0.1, 0.6},
    width = 1200, height = 260, font_size = 90,
    color = {0.45, 0.35, 0.05}, font_color = {1, 0.95, 0.6},
  })
  trackButton({
    click_function = "click_guildBack", function_owner = self,
    label = "Back", position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end
function click_guildBack() showExperienceScreen() end

function buildGuildQuery()
  local parts = {"is:commander"}
  local c = colorString()
  if c ~= "" then table.insert(parts, "id" .. (packInput.colorOp or ":") .. c) end
  return table.concat(parts, "+")
end

function tryGamblersNeverQuit(baseCost)
  if baseCost <= 0 then return nil end
  if not isBuffEquipped("Gamblers never quit") then return nil end
  if gamblersNeverQuitUsedThisTown then return nil end
  -- Achievement requires the player to be able to afford double; otherwise it is skipped.
  if xp < baseCost * 2 then
    broadcastToAll("[" .. self.getName() .. "] Gamblers Never Quit: need "
      .. (baseCost * 2) .. " XP to gamble (have " .. xp .. ") — normal cost applies.", {0.9, 0.75, 0.3})
    return nil
  end
  gamblersNeverQuitUsedThisTown = true
  local win = (math.random(1, 2) == 1)
  if win then
    broadcastToAll("[" .. self.getName() .. "] Gamblers Never Quit: HEADS — this action is FREE!", {0.3, 1, 0.3})
    return 0
  else
    broadcastToAll("[" .. self.getName() .. "] Gamblers Never Quit: TAILS — this action costs DOUBLE ("
      .. (baseCost * 2) .. " XP)!", {1, 0.35, 0.35})
    return baseCost * 2
  end
end

function click_guildRoll()
  local baseCost = applyTownCostModifiers(GUILD_ROLL_COST)
  local gamblerResult = tryGamblersNeverQuit(baseCost)
  local cost = (gamblerResult ~= nil) and gamblerResult or baseCost
  if xp < cost then
    broadcastToAll("[" .. self.getName() .. "] Not enough XP for Guild roll (need " .. cost .. ", have "
      .. xp .. ").", {0.9, 0.3, 0.3})
    return
  end
  local guildBonusChoices = getGuildCommanderChoiceBonusFromBrands()
  local recurrenceRanks = getBrandRankByName("Brand of Recurrence")
  local roll  = math.random(1, 6)
  local bestRoll = roll
  for _ = 1, recurrenceRanks do
    local candidate = math.random(1, 6)
    if candidate > bestRoll then bestRoll = candidate end
  end
  roll = bestRoll
  local count = roll + 2 + guildBonusChoices
  local q     = buildGuildQuery()
  xp = math.max(XP_MIN, xp - cost)
  recordXPTransaction(-cost, "Guild Roll")
  notifyMasters()
  local bonusLabel = (guildBonusChoices > 0) and (" (+" .. guildBonusChoices .. " from Brand of the Conclave)") or ""
  local rerollLabel = (recurrenceRanks > 0) and (" [" .. recurrenceRanks .. " free reroll(s)]") or ""
  broadcastToAll("[" .. self.getName() .. "] Guild: rolled " .. roll .. "! Summoning "
    .. count .. " commanders" .. bonusLabel .. rerollLabel .. ". -" .. cost .. " XP (" .. xp .. " remaining).", {1, 0.85, 0.3})
  spawnParameterizedPack(q, count, cost)
  showExperienceScreen()
end

--==============================================================================
-- TOWN SCREENS  (Cathedral / Upgrade / Augment)
--==============================================================================

-- Hub screen ---------------------------------------------------------------
function showTownScreen()
  activePack = nil
  local cathedralBlocked = isTownActionBlocked("cathedral")
  local upgradeBlocked = isTownActionBlocked("upgrade")
  local augmentBlocked = isTownActionBlocked("augment")
  openScreen("town", nil, "Town")
  local upgradeCost, upgradeFree = getTownActionCost("upgrade")
  local augmentCost, augmentFree = getTownActionCost("augment")
  trackButton({
    click_function = cathedralBlocked and "xp_noop" or "click_townCathedral", function_owner = self,
    label = cathedralBlocked and "Cathedral\n(Blocked)" or "Cathedral\n(Free)",
    position = {-0.9, 0.1, 0.05},
    width = 800, height = 320, font_size = 78,
    color = cathedralBlocked and {0.28, 0.14, 0.14} or {0.1, 0.2, 0.35}, font_color = {0.8, 0.9, 1.0},
    tooltip = "Request a custom card from the host by description",
  })
  trackButton({
    click_function = upgradeBlocked and "xp_noop" or "click_townUpgrade", function_owner = self,
    label = upgradeBlocked and "Upgrade\n(Blocked)" or ("Upgrade\n(" .. (upgradeFree and "Free" or tostring(upgradeCost) .. " XP") .. ")"),
    position = {0.9, 0.1, 0.05},
    width = 800, height = 320, font_size = 78,
    color = upgradeBlocked and {0.28, 0.14, 0.14} or {0.15, 0.3, 0.12}, font_color = {0.8, 1.0, 0.7},
    tooltip = "Submit a card to be upgraded by the host",
  })
  trackButton({
    click_function = augmentBlocked and "xp_noop" or "click_townAugment", function_owner = self,
    label = augmentBlocked and "Augment\n(Blocked)" or ("Augment\n(" .. (augmentFree and "Free" or tostring(augmentCost) .. " XP") .. ")"),
    position = {0, 0.1, 0.75},
    width = 800, height = 320, font_size = 78,
    color = augmentBlocked and {0.28, 0.14, 0.14} or {0.28, 0.18, 0.08}, font_color = {1.0, 0.88, 0.55},
    tooltip = "Submit a card for a major augment by the host — host may return multiple versions",
  })
  trackButton({
    click_function = "click_townBack", function_owner = self,
    label = "Back", position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function click_townCathedral()
  local blocked, reason = isTownActionBlocked("cathedral")
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    return
  end
  showCathedralInput()
end
function click_townUpgrade()
  local blocked, reason = isTownActionBlocked("upgrade")
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    return
  end
  showUpgradeInput("upgrade")
end
function click_townAugment()
  local blocked, reason = isTownActionBlocked("augment")
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    return
  end
  showUpgradeInput("augment")
end
function click_townBack()      showExperienceScreen()      end

-- Cathedral input ----------------------------------------------------------
function showCathedralInput()
  local blocked, reason = isTownActionBlocked("cathedral")
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    showTownScreen()
    return
  end
  openScreen("cathedral_input", nil, "Cathedral")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Describe the card you want the host to provide:",
    position = {0, 0.1, -0.6},
    width = 1700, height = 185, font_size = 65,
    color = {0.1, 0.15, 0.22}, font_color = {0.8, 0.9, 1.0},
  })
  trackInput({
    input_function = "cathedralText_input", function_owner = self,
    label = "e.g. a red creature that deals damage on ETB...",
    value = "",
    position = {0, 0.1, 0.0},
    width = 1700, height = 300, font_size = 55,
    color = {0.1, 0.1, 0.15}, font_color = {1, 1, 1},
    char_limit = 200,
    validation = TTS_INPUT_VALIDATION_NONE,
    alignment = 1,
  })
  trackButton({
    click_function = "click_cathedralSubmit", function_owner = self,
    label = "Submit Request",
    position = {0.7, 0.1, 0.95},
    width = 1000, height = 230, font_size = 78,
    color = {0.12, 0.35, 0.22}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_townBack", function_owner = self,
    label = "Back", position = {-1.4, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function cathedralText_input(obj, color, value, stillEditing)
  cathedralTextValue = value or ""
end

function click_cathedralSubmit()
  local blocked, reason = isTownActionBlocked("cathedral")
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    showTownScreen()
    return
  end
  if cathedralTextValue == "" then
    broadcastToAll("[" .. self.getName() .. "] Please enter a description before submitting.", {0.9, 0.6, 0.3})
    return
  end
  submitTownAction("cathedral", cathedralTextValue, nil)
end

-- Upgrade / Augment input --------------------------------------------------
function showUpgradeInput(actionType)
  local blocked, reason = isTownActionBlocked(actionType)
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    showTownScreen()
    return
  end
  pendingTownCardObj    = nil
  pendingTownActionType = actionType
  townNoteValue         = ""
  local cost, freeAction = getTownActionCost(actionType)
  local typeLabel = actionType:sub(1,1):upper() .. actionType:sub(2)
  openScreen(actionType .. "_input", nil, typeLabel)
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = typeLabel .. "  —  " .. (freeAction and "Free" or (tostring(cost) .. " XP")),
    position = {0, 0.1, -0.7},
    width = 1700, height = 185, font_size = 80,
    color = {0.12, 0.18, 0.1}, font_color = {0.75, 1, 0.65},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Optional note:",
    position = {-1.3, 0.1, -0.2},
    width = 380, height = 165, font_size = 60,
    color = {0.92, 0.88, 0.78}, font_color = {0, 0, 0},
  })
  trackInput({
    input_function = "townNote_input", function_owner = self,
    label = "Describe desired changes...",
    value = "",
    position = {0.55, 0.1, -0.2},
    width = 1050, height = 165, font_size = 52,
    color = {0.14, 0.14, 0.2}, font_color = {1, 1, 1},
    char_limit = 200,
    validation = TTS_INPUT_VALIDATION_NONE,
    alignment = 1,
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Drop the card you want to " .. actionType .. " near this spawner",
    position = {0, 0.1, 0.45},
    width = 1700, height = 185, font_size = 62,
    color = {0.1, 0.15, 0.1}, font_color = {0.65, 1, 0.65},
  })
  trackButton({
    click_function = "click_upgradeAugmentBack", function_owner = self,
    label = "Back", position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end
function click_upgradeAugmentBack() showBlacksmithScreen() end

function townNote_input(obj, color, value, stillEditing)
  townNoteValue = value or ""
end

-- Town card drop confirm ---------------------------------------------------
function handleTownCardDrop(obj, actionType)
  local blocked, reason = isTownActionBlocked(actionType)
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    return
  end
  local tag = ""
  pcall(function() tag = obj.tag or "" end)
  if tag ~= "Card" then
    broadcastToAll("[" .. self.getName() .. "] Drop a single card, not a deck.", {0.9, 0.6, 0.3})
    return
  end
  local cost, _ = getTownActionCost(actionType)
  if cost > 0 and xp < cost then
    broadcastToAll("[" .. self.getName() .. "] Not enough XP for " .. actionType
      .. " (need " .. cost .. ", have " .. xp .. ").", {0.9, 0.3, 0.3})
    return
  end
  pendingTownCardObj    = obj
  pendingTownActionType = actionType
  local rawName = ""
  pcall(function() rawName = obj.getName() or "" end)
  local cardName = rawName:match("^([^\n]*)") or rawName
  if cardName == "" then cardName = "Unknown Card" end
  showTownCardConfirm(cardName, actionType)
end

function showTownCardConfirm(cardName, actionType)
  local blocked, reason = isTownActionBlocked(actionType)
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    showTownScreen()
    return
  end
  local cost, freeAction = getTownActionCost(actionType)
  local typeLabel = actionType:sub(1,1):upper() .. actionType:sub(2)
  openScreen("town_card_confirm", nil, typeLabel .. " — Confirm")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = cardName,
    position = {0, 0.1, -0.55},
    width = 1700, height = 220, font_size = 75,
    color = {0.14, 0.14, 0.2}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Cost: " .. (freeAction and "Free" or (tostring(cost) .. " XP")),
    position = {0, 0.1, 0.05},
    width = 1700, height = 185, font_size = 80,
    color = {0.1, 0.16, 0.1}, font_color = {0.7, 1, 0.7},
  })
  if townNoteValue ~= "" then
    trackButton({
      click_function = "xp_noop", function_owner = self,
      label = "Note: " .. townNoteValue,
      position = {0, 0.1, 0.58},
      width = 1700, height = 185, font_size = 58,
      color = {0.1, 0.1, 0.1}, font_color = {0.9, 0.9, 0.7},
      tooltip = townNoteValue,
    })
  end
  trackButton({
    click_function = "click_townCardConfirmOK", function_owner = self,
    label = "Confirm",
    position = {0.9, 0.1, 1.2},
    width = 700, height = 230, font_size = 85,
    color = {0.18, 0.42, 0.18}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_townCardConfirmCancel", function_owner = self,
    label = "Cancel",
    position = {-0.9, 0.1, 1.2},
    width = 700, height = 230, font_size = 85,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
end

function click_townCardConfirmOK()
  if not pendingTownCardObj or not pendingTownActionType then
    showTownScreen()
    return
  end
  local guid       = pendingTownCardObj.getGUID()
  local actionType = pendingTownActionType
  local note       = townNoteValue
  pendingTownCardObj    = nil
  pendingTownActionType = nil
  submitTownAction(actionType, note, guid)
end

function click_townCardConfirmCancel()
  local actionType = pendingTownActionType
  pendingTownCardObj    = nil
  pendingTownActionType = nil
  showUpgradeInput(actionType or "upgrade")
end

-- Submit to HostTownActions ------------------------------------------------
function submitTownAction(actionType, text, cardGuid)
  local blocked, reason = isTownActionBlocked(actionType)
  if blocked then
    broadcastToAll("[" .. self.getName() .. "] " .. reason, {0.95, 0.45, 0.2})
    return
  end
  local hostObjs = getObjectsWithTag(HOST_ACTIONS_TAG) or {}
  local hostObj  = hostObjs[1]
  if not hostObj then
    broadcastToAll("[" .. self.getName() .. "] HostTownActions object not found in scene. Ask the host to place it.", {0.9, 0.3, 0.3})
    return
  end

  local paidCost = nil
  local usedBonus = false
  if actionType == "upgrade" or actionType == "augment" then
    local cost, freeBonus = getTownActionCost(actionType)
    if not freeBonus then
      local gamblerResult = tryGamblersNeverQuit(cost)
      if gamblerResult ~= nil then cost = gamblerResult end
    else
      usedBonus = consumeBlacksmithBonusUse(actionType)
    end
    if cost > 0 then
      xp = math.max(XP_MIN, xp - cost)
      local typeLabel = actionType:sub(1,1):upper() .. actionType:sub(2)
      recordXPTransaction(-cost, typeLabel)
      notifyMasters()
      refreshXPDisplay()
    else
      recordXPTransaction(0, (actionType:sub(1,1):upper() .. actionType:sub(2)) .. " (Free)")
    end
    paidCost = cost
  end

  local submitted, requestId = pcall(function()
    return hostObj.call("submitAction", {
      type        = actionType,
      spawnerGuid = self.getGUID(),
      spawnerName = claimedPlayerName or self.getName(),
      text        = text or "",
      cardGuid    = cardGuid,
    })
  end)

  if not submitted then
    if paidCost and paidCost > 0 then
      refundXP(paidCost, (actionType:sub(1,1):upper() .. actionType:sub(2)) .. " Submit Refund")
    end
    if usedBonus then
      local bonusKey = getBlacksmithBonusUseKey(actionType)
      if bonusKey then
        bonusBuildingUsesByKey[bonusKey] = (bonusBuildingUsesByKey[bonusKey] or 0) + 1
      end
    end
    broadcastToAll("[" .. self.getName() .. "] Town action could not be queued with the host: " .. tostring(requestId), {0.9, 0.3, 0.3})
    showExperienceScreen()
    return
  end

  if actionType == "cathedral" then
    decrementBuildingUse("Cathedral")
  end
  addPendingTownAction({
    requestId = requestId,
    type = actionType,
    submittedAt = getTimeStr(),
    costPaid = paidCost,
    usedBonus = usedBonus,
  })
  townNoteValue     = ""
  cathedralTextValue = ""
  showTownAwaitScreen()
end

-- Await screen (after submission) ------------------------------------------
function showTownAwaitScreen()
  openScreen("town_await", nil, "Town")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = getPendingTownActionSummary() .. "\n\nWaiting for host...",
    position = {0, 0.1, 0.0},
    width = 1700, height = 380, font_size = 70,
    color = {0.08, 0.14, 0.1}, font_color = {0.65, 1, 0.65},
  })
  trackButton({
    click_function = "click_townAwaitBack", function_owner = self,
    label = "Back", position = {-1.6, 0.1, 1.3},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
    tooltip = "Return to main menu — your request stays queued",
  })
end

function click_townAwaitBack() showShopScreen() end

-- Result: Cathedral (Keep or Sacrifice) ------------------------------------
function showCathedralResult()
  openScreen("cathedral_result", nil, "Cathedral")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "A card has arrived from the Cathedral!",
    position = {0, 0.1, -0.55},
    width = 1700, height = 200, font_size = 72,
    color = {0.1, 0.18, 0.28}, font_color = {0.75, 0.88, 1.0},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Keep it, or Sacrifice for 2x its Mana Value in Essence",
    position = {0, 0.1, 0.05},
    width = 1700, height = 185, font_size = 60,
    color = {0.1, 0.1, 0.15}, font_color = {0.8, 0.8, 1.0},
  })
  trackButton({
    click_function = "click_cathedralKeep", function_owner = self,
    label = "Keep",
    position = {0.9, 0.1, 0.85},
    width = 700, height = 250, font_size = 90,
    color = {0.14, 0.38, 0.14}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_cathedralSacrifice", function_owner = self,
    label = "Sacrifice\n(2x CMC -> Essence)",
    position = {-0.9, 0.1, 0.85},
    width = 700, height = 250, font_size = 60,
    color = {0.32, 0.1, 0.42}, font_color = {1, 1, 1},
    tooltip = "Destruct the card and gain 2x its CMC in Essence",
  })
end

function click_cathedralKeep()
  townResultCards = nil
  showNextTownResultOrShop()
end

function click_cathedralSacrifice()
  if not townResultCards or not townResultCards.cardGuids
      or #townResultCards.cardGuids == 0 then
    townResultCards = nil
    showNextTownResultOrShop()
    return
  end
  local guid = townResultCards.cardGuids[1]
  local card = nil
  pcall(function() card = getObjectFromGUID(guid) end)
  if not card then
    broadcastToAll("[" .. self.getName() .. "] Cathedral card not found — keeping Essence.", {0.9, 0.6, 0.3})
    townResultCards = nil
    showNextTownResultOrShop()
    return
  end
  lookupCardCMC(card, function(cmc)
    if not cmc then
      broadcastToAll("[" .. self.getName() .. "] Couldn't determine CMC — card kept instead.", {0.9, 0.6, 0.3})
      townResultCards = nil
      showNextTownResultOrShop()
      return
    end
    local gain = cmc * 2
    applyEssenceDeltaTracked(gain, "Cathedral Sacrifice")
    broadcastToAll("[" .. self.getName() .. "] Cathedral Sacrifice: +"
      .. gain .. " Essence (CMC " .. cmc .. ").", {0.7, 0.5, 1.0})
    pcall(function() card.destruct() end)
    townResultCards = nil
    showNextTownResultOrShop()
  end)
end

-- Result: Upgrade / Augment (Keep one) -------------------------------------
function showUpgradeResult()
  if not townResultCards then showShopScreen() return end
  local cardGuids = townResultCards.cardGuids or {}
  local typeLabel = (townResultCards.type or "upgrade"):sub(1,1):upper()
    .. (townResultCards.type or "upgrade"):sub(2)

  if #cardGuids <= 1 then
    openScreen("upgrade_result", nil, typeLabel .. " Complete")
    trackButton({
      click_function = "xp_noop", function_owner = self,
      label = "Your card has been returned!",
      position = {0, 0.1, 0.0},
      width = 1700, height = 250, font_size = 80,
      color = {0.1, 0.18, 0.1}, font_color = {0.7, 1, 0.7},
    })
    trackButton({
      click_function = "click_upgradeResultOK", function_owner = self,
      label = "OK",
      position = {0, 0.1, 0.85},
      width = 700, height = 250, font_size = 90,
      color = {0.18, 0.42, 0.18}, font_color = {1, 1, 1},
    })
    return
  end

  openScreen("upgrade_result", nil, typeLabel .. " — Pick One")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Host returned " .. #cardGuids .. " versions — pick one to keep:",
    position = {0, 0.1, -0.75},
    width = 1700, height = 185, font_size = 65,
    color = {0.14, 0.14, 0.2}, font_color = {1, 1, 1},
  })

  -- Buttons spread horizontally using the same xStep HostTownActions used to
  -- fan the physical cards, so button[i] sits directly below card[i].
  local N      = math.min(#cardGuids, 4)
  local xStep  = townResultCards.xStep or 0.75   -- measured card width + spacer from HostTownActions
  local xStart = -(N - 1) * xStep / 2
  -- Scale button width to roughly match the card width in TTS button-units.
  -- Empirically: 1 TTS local unit ≈ 650 button-width units on this spawner card.
  local btnW   = math.floor(xStep * 620)
  btnW         = math.max(400, math.min(btnW, 1000))
  local fontByN = {[1]=82, [2]=76, [3]=70, [4]=64}
  local btnFnt  = fontByN[N] or 70

  for i = 1, N do
    local guid = cardGuids[i]
    local cardName = "Card " .. i
    local card = nil
    pcall(function() card = getObjectFromGUID(guid) end)
    if card then
      pcall(function()
        local raw = card.getName() or ""
        local n = raw:match("^([^\n]*)") or raw
        if n ~= "" then cardName = n end
      end)
    end
    local xPos     = xStart + (i - 1) * xStep
    local fnName   = "click_keepCard_" .. i
    local capturedGuid = guid
    local capturedAll  = cardGuids
    _G[fnName] = function() keepUpgradeCard(capturedGuid, capturedAll) end
    trackButton({
      click_function = fnName, function_owner = self,
      label = cardName,
      position = {xPos, 0.1, -0.3},
      width = btnW, height = 310, font_size = btnFnt,
      color = {0.22, 0.50, 0.12}, font_color = {1, 1, 1},
      tooltip = "Keep this version — remove the " .. (N - 1) .. " other(s)",
    })
  end
end

function click_upgradeResultOK()
  townResultCards = nil
  showNextTownResultOrShop()
end

function keepUpgradeCard(keptGuid, allGuids)
  for _, guid in ipairs(allGuids) do
    if guid ~= keptGuid then
      local card = nil
      pcall(function() card = getObjectFromGUID(guid) end)
      if card then pcall(function() card.destruct() end) end
    end
  end
  townResultCards = nil
  broadcastToAll("[" .. self.getName() .. "] Card selected, others removed.", {0.7, 1, 0.7})
  showNextTownResultOrShop()
end

-- Public API: called by HostTownActions ------------------------------------
function receiveTownActionResult(params)
  if type(params) ~= "table" then return end
  normalizeTownActionQueues()
  removePendingTownAction(params.requestId, params.type)
  if townResultCards then
    table.insert(townResultQueue, params)
    broadcastToAll("[" .. self.getName() .. "] Town result received and queued behind your current result.", {0.65, 1, 0.65})
    return
  end
  townResultCards = params

  -- Cards are already fanned above the spawner by HostTownActions (no re-spread needed)
  if params.type == "cathedral" then
    Wait.frames(showCathedralResult, 60)
  else
    Wait.frames(showUpgradeResult, 60)
  end
end

function receiveTownActionCancelled(params)
  if type(params) ~= "table" then return end
  normalizeTownActionQueues()
  local actionType = params.type or ""
  local pendingAction = removePendingTownAction(params.requestId, actionType)
  if actionType == "upgrade" then
    local refund = (pendingAction and pendingAction.costPaid) or applyTownCostModifiers(UPGRADE_COST)
    refundXP(refund, "Upgrade Cancel Refund")
    if pendingAction and pendingAction.usedBonus then
      local bonusKey = getBlacksmithBonusUseKey("upgrade")
      if bonusKey then
        bonusBuildingUsesByKey[bonusKey] = (bonusBuildingUsesByKey[bonusKey] or 0) + 1
      end
    end
    broadcastToAll("[" .. self.getName() .. "] Upgrade cancelled — "
      .. refund .. " XP refunded.", {0.9, 0.9, 0.5})
  elseif actionType == "augment" then
    local refund = (pendingAction and pendingAction.costPaid) or applyTownCostModifiers(AUGMENT_COST)
    refundXP(refund, "Augment Cancel Refund")
    if pendingAction and pendingAction.usedBonus then
      local bonusKey = getBlacksmithBonusUseKey("augment")
      if bonusKey then
        bonusBuildingUsesByKey[bonusKey] = (bonusBuildingUsesByKey[bonusKey] or 0) + 1
      end
    end
    broadcastToAll("[" .. self.getName() .. "] Augment cancelled — "
      .. refund .. " XP refunded.", {0.9, 0.9, 0.5})
  end
  showShopScreen()
end

function tryOpenPackInput(packName)
  if isMerchantPackLockedForTown(packName) then
    broadcastToAll("[" .. self.getName() .. "] " .. packName
      .. " pack is limited to once per town while Cursed Pumpkins is active.", {0.95, 0.45, 0.2})
    showBuyScreen()
    return
  end
  local cost = getMerchantPackCost(packName)
  if xp < cost then
    broadcastToAll("[" .. self.getName() .. "] Not enough XP for " .. packName
      .. " pack (have " .. xp .. ", need " .. cost .. ").", {0.9, 0.3, 0.3})
    return
  end
  if packName == "mystery" then
    attemptPurchase("mystery")
    return
  end
  openPackInput(packName)
end

function showSettingsScreen()
  activePack = nil
  openScreen("settings", nil, "Settings")
  local labelX, ctrlX = -1.4, 1.4
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Pack Size", position = {labelX, 0.1, -0.55},
    width = 800, height = 180, font_size = 90,
    color = LABEL_BG, font_color = {0, 0, 0},
    tooltip = "Mystery packs are exempt.",
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = tostring(getEffectiveStandardPackCount()),
    position = {ctrlX, 0.1, -0.55},
    width = 400, height = 180, font_size = 100,
    color = {1, 1, 1}, font_color = {0, 0, 0},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Auto-Splay", position = {labelX, 0.1, -0.15},
    width = 800, height = 180, font_size = 90,
    color = LABEL_BG, font_color = {0, 0, 0},
  })
  trackButton({
    click_function = "click_autoSplay", function_owner = self,
    label = settings.autoSplay and "ON" or "OFF",
    position = {ctrlX, 0.1, -0.15},
    width = 400, height = 180, font_size = 100,
    color = settings.autoSplay and {0.15, 0.5, 0.15} or {0.5, 0.15, 0.15},
    font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Splay Cols", position = {labelX, 0.1, 0.25},
    width = 800, height = 180, font_size = 90,
    color = LABEL_BG, font_color = {0, 0, 0},
  })
  trackInput({
    input_function = "splayCols_input", function_owner = self,
    label = "8", value = tostring(settings.splayCols),
    alignment = TTS_INPUT_ALIGN_RIGHT, validation = TTS_INPUT_VALIDATION_INT,
    position = {ctrlX, 0.1, 0.25},
    width = 400, height = 180, font_size = 100,
    color = {1, 1, 1}, font_color = {0, 0, 0},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Splay Rows", position = {labelX, 0.1, 0.65},
    width = 800, height = 180, font_size = 90,
    color = LABEL_BG, font_color = {0, 0, 0},
  })
  trackInput({
    input_function = "splayRows_input", function_owner = self,
    label = "3", value = tostring(settings.splayRows),
    alignment = TTS_INPUT_ALIGN_RIGHT, validation = TTS_INPUT_VALIDATION_INT,
    position = {ctrlX, 0.1, 0.65},
    width = 400, height = 180, font_size = 100,
    color = {1, 1, 1}, font_color = {0, 0, 0},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Admin Mode\n(White Only)", position = {labelX, 0.1, 1.05},
    width = 800, height = 180, font_size = 72,
    color = LABEL_BG, font_color = {0, 0, 0},
  })
  trackButton({
    click_function = "click_toggleAdmin", function_owner = self,
    label = adminMode and "ON" or "OFF",
    tooltip = "Only the White seat can toggle Admin Mode",
    position = {ctrlX, 0.1, 1.05},
    width = 400, height = 180, font_size = 100,
    color = adminMode and {0.55, 0.15, 0.15} or {0.25, 0.25, 0.25},
    font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_settingsBack", function_owner = self,
    label = "Back",
    position = {-1.6, 0.1, 1.4},
    width = 500, height = 200, font_size = 90,
    color = {0.3, 0.3, 0.3}, font_color = {1, 1, 1},
  })
end

function click_settingsBack() showShopScreen() end

function click_toggleAdmin(_, playerColor)
  if playerColor ~= "White" then
    broadcastToAll("[" .. self.getName() .. "] Admin Mode can only be toggled by the White seat.", {0.9, 0.4, 0.2})
    return
  end
  adminMode = not adminMode
  broadcastToAll("[" .. self.getName() .. "] Admin Mode " .. (adminMode and "ENABLED" or "DISABLED")
    .. " by " .. tostring(playerColor) .. ".", adminMode and {1, 0.6, 0.6} or {0.8, 0.8, 0.8})
  showSettingsScreen()
end

function click_autoSplay()
  settings.autoSplay = not settings.autoSplay
  showSettingsScreen()
end

function cardsPerPack_input(_, _, value)
  local n = tonumber(value)
  if n and n > 0 then
    local brandBonus = getPackChoiceBonusFromBrands()
    settings.cardsPerPack = math.max(1, math.floor(n - brandBonus))
  end
end
function splayRows_input(_, _, value)
  local n = tonumber(value)
  if n and n > 0 then settings.splayRows = math.floor(n) end
end
function splayCols_input(_, _, value)
  local n = tonumber(value)
  if n and n > 0 then settings.splayCols = math.floor(n) end
end

function resetPackInput()
  packInput.colors  = {W=false, U=false, B=false, R=false, G=false, C=false}
  packInput.colorOp = ":"
  packInput.termType1 = 1
  packInput.termOp1   = 1
  packInput.termValue1 = ""
  packInput.termType2 = 1
  packInput.termOp2   = 1
  packInput.termValue2 = ""
  packInput.otag = ""
end

function openPackInput(packName)
  if activePack ~= packName then resetPackInput() end
  activePack = packName
  openScreen("input", nil)
  
  local titles = {
    identity = "Identity Pack", pro = "Pro Pack",
    mythic = "Mythic Pack",     otag = "OTAG Pack",
  }
  
  -- Show "Cashout Redemption" instead of cost if this is a merchant pack cashout
  local titleText
  if pendingMerchantPackCashout then
    titleText = (titles[packName] or packName) .. " - Cashout Redemption"
  else
    local cost = PACK_COSTS[packName] or 0
    titleText = (titles[packName] or packName) .. " - " .. tostring(cost) .. " XP"
  end
  
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = titleText,
    position = {0.3, 0.1, -1.05},
    width = 750, height = 130, font_size = 70,
    color = LABEL_BG, font_color = {0, 0, 0},
  })
  if packName == "identity" then
    drawColorToggles(-0.35)
  elseif packName == "pro" then
    drawColorToggles(-0.35)
    drawTermSlot(1, 0.15)
  elseif packName == "mythic" then
    drawColorToggles(-0.45)
    drawTermSlot(1, 0.0)
    drawTermSlot(2, 0.5)
  elseif packName == "otag" then
    drawColorToggles(-0.35)
    drawOtagInput(0.15)
  end
  if PACK_MIN_POOL[packName] then
    poolSizeButtonIndex = trackButton({
      click_function = "xp_noop", function_owner = self,
      label          = "Pool: …",
      position       = {0, 0.1, 0.85},
      width = 1200, height = 150, font_size = 80,
      color = {0.15, 0.15, 0.25}, font_color = {1, 1, 1},
    })
    Wait.frames(doPoolCheck, 1)
  end
  trackButton({
    click_function = "click_inputCancel", function_owner = self,
    label = "Cancel", position = {-1.1, 0.1, 1.25},
    width = 500, height = 130, font_size = 80,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_inputEnter", function_owner = self,
    label = "Confirm", position = {1.1, 0.1, 1.25},
    width = 500, height = 130, font_size = 80,
    color = {0.15, 0.5, 0.15}, font_color = {1, 1, 1},
  })
end

function drawColorToggles(z)
  local op = packInput.colorOp or ":"
  trackButton({
    click_function = "click_toggleColorOp", function_owner = self,
    label = op,
    tooltip = (op == ":") and "id: (within identity)" or "id= (exact identity)",
    position = {1.95, 0.1, z},
    width = 230, height = 210, font_size = 130,
    color = (op == ":") and {0.2, 0.35, 0.5} or {0.45, 0.2, 0.45},
    font_color = {1, 1, 1},
  })
  local xs = {-2.0, -1.35, -0.7, -0.05, 0.6, 1.25}
  local letters  = {"W", "U", "B", "R", "G", "C"}
  local handlers = {"click_toggleColor_W","click_toggleColor_U","click_toggleColor_B","click_toggleColor_R","click_toggleColor_G","click_toggleColor_C"}
  local activeColors = {
    W = {0.95, 0.92, 0.7},
    U = {0.35, 0.5,  0.85},
    B = {0.25, 0.2,  0.25},
    R = {0.85, 0.3,  0.25},
    G = {0.2,  0.55, 0.3},
    C = {0.75, 0.75, 0.75},
  }
  for i, l in ipairs(letters) do
    local active = packInput.colors[l]
    trackButton({
      click_function = handlers[i], function_owner = self,
      label = l,
      position = {xs[i], 0.1, z},
      width = 195, height = 210, font_size = 130,
      color = active and activeColors[l] or {0.2, 0.2, 0.2},
      font_color = active and {0, 0, 0} or {1, 1, 1},
    })
  end
end

function click_toggleColorOp()
  packInput.colorOp = (packInput.colorOp == ":") and "=" or ":"
  if     activePack == "portal" then openPortalInput()
  elseif activePack == "guild"  then showGuildScreen()
  elseif activePack             then openPackInput(activePack) end
end
function toggleColor(l)
  packInput.colors[l] = not packInput.colors[l]
  if     activePack == "portal" then openPortalInput()
  elseif activePack == "guild"  then showGuildScreen()
  elseif activePack             then openPackInput(activePack) end
end
for _, l in ipairs({"W", "U", "B", "R", "G", "C"}) do
  _G["click_toggleColor_" .. l] = function() toggleColor(l) end
end

function drawTermSlot(slot, z)
  local termType  = (slot == 1) and TERM_TYPES[packInput.termType1] or TERM_TYPES[packInput.termType2]
  local opIdx     = (slot == 1) and packInput.termOp1 or packInput.termOp2
  local opList    = TERM_OPS[termType] or {":"}
  local termOp    = opList[opIdx] or opList[1]
  local termValue = (slot == 1) and packInput.termValue1 or packInput.termValue2
  local cycleH    = (slot == 1) and "click_cycleTerm1" or "click_cycleTerm2"
  local opH       = (slot == 1) and "click_cycleOp1"   or "click_cycleOp2"
  local inputH    = (slot == 1) and "termValue1_input" or "termValue2_input"
  trackButton({
    click_function = cycleH, function_owner = self,
    label = termType, position = {-1.65, 0.1, z},
    width = 460, height = 180, font_size = 80,
    color = {0.25, 0.25, 0.45}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = opH, function_owner = self,
    label = termOp, position = {-0.85, 0.1, z},
    width = 380, height = 180, font_size = 90,
    color = {0.45, 0.25, 0.45}, font_color = {1, 1, 1},
  })
  trackInput({
    input_function = inputH, function_owner = self,
    label = "value", value = termValue,
    alignment = TTS_INPUT_ALIGN_RIGHT, validation = TTS_INPUT_VALIDATION_NONE,
    position = {1.15, 0.1, z},
    width = 650, height = 180, font_size = 90,
    color = {1, 1, 1}, font_color = {0, 0, 0},
    char_limit = 0,
  })
end

function click_cycleTerm1()
  packInput.termType1 = (packInput.termType1 % #TERM_TYPES) + 1
  packInput.termOp1 = 1
  if activePack then openPackInput(activePack) end
end
function click_cycleTerm2()
  packInput.termType2 = (packInput.termType2 % #TERM_TYPES) + 1
  packInput.termOp2 = 1
  if activePack then openPackInput(activePack) end
end
function click_cycleOp1()
  local t = TERM_TYPES[packInput.termType1]
  local n = #(TERM_OPS[t] or {":"})
  packInput.termOp1 = (packInput.termOp1 % n) + 1
  if activePack then openPackInput(activePack) end
end
function click_cycleOp2()
  local t = TERM_TYPES[packInput.termType2]
  local n = #(TERM_OPS[t] or {":"})
  packInput.termOp2 = (packInput.termOp2 % n) + 1
  if activePack then openPackInput(activePack) end
end
function termValue1_input(_, _, v) packInput.termValue1 = v or "" schedulePoolCheck() end
function termValue2_input(_, _, v) packInput.termValue2 = v or "" schedulePoolCheck() end

function drawOtagInput(z)
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "OTAG", position = {-1.4, 0.1, z},
    width = 500, height = 180, font_size = 90,
    color = {0.92, 0.88, 0.78}, font_color = {0, 0, 0},
  })
  trackInput({
    input_function = "otag_input", function_owner = self,
    label = "e.g. ramp or mana-rock", value = packInput.otag,
    alignment = TTS_INPUT_ALIGN_RIGHT, validation = TTS_INPUT_VALIDATION_NONE,
    position = {0.90, 0.1, z},
    width = 1300, height = 180, font_size = 90,
    color = {1, 1, 1}, font_color = {0, 0, 0},
    char_limit = 0,
  })
end
function otag_input(_, _, v) packInput.otag = v or "" schedulePoolCheck() end

function click_inputCancel()
  if pendingMerchantPackCashout then
    if pendingMerchantPackCashout.object then
      ess_safeDestructObject(pendingMerchantPackCashout.object)
    end
    pendingMerchantPackCashout = nil
    showRedeemCashoutScreen()
  elseif activePack == "portal" then
    showExperienceScreen()
  else
    showBuyScreen()
  end
end
function click_inputEnter()
  if activePack == "portal" then attemptPortalPurchase() return end
  if not activePack then showBuyScreen() return end

  local minPool = PACK_MIN_POOL[activePack]
  if not minPool then
    attemptPurchase(activePack)
    return
  end

  local q
  if     activePack == "pro"    then q = buildProQuery()
  elseif activePack == "mythic" then q = buildMythicQuery()
  elseif activePack == "otag"   then q = buildOtagQuery() end

  if not q or q == "" then
    if activePack == "otag" then
      broadcastToAll("[" .. self.getName() .. "] Enter an OTAG before confirming.", {0.9, 0.6, 0.3})
      return
    end
    attemptPurchase(activePack)
    return
  end

  broadcastToAll("[" .. self.getName() .. "] Checking pool size…", {0.75, 0.75, 0.85})
  checkPoolSize(q, function(count)
    if count ~= nil and count < minPool then
      broadcastToAll(
        "[" .. self.getName() .. "] Pool too small — only " .. tostring(count) ..
        " matching card" .. (count == 1 and "" or "s") ..
        " (need at least " .. tostring(minPool) .. " for a " .. activePack ..
        " pack). Adjust your filters and try again.",
        {0.95, 0.55, 0.2}
      )
    else
      if count then
        broadcastToAll(
          "[" .. self.getName() .. "] Pool: " .. tostring(count) ..
          " cards — OK.",
          {0.5, 0.85, 0.5}
        )
      end
      attemptPurchase(activePack)
    end
  end)
end

--==============================================================================
-- Query builders
--==============================================================================
function colorString()
  local s = ""
  -- If C (colorless) is toggled, return "c" for Scryfall's colorless filter
  if packInput.colors.C then
    return "c"
  end
  -- Otherwise, build string from W, U, B, R, G
  for _, c in ipairs({"w","u","b","r","g"}) do
    if packInput.colors[c:upper()] then s = s .. c end
  end
  return s
end

function buildIdentityQuery()
  local op = packInput.colorOp or ":"
  local c = colorString()
  local parts = {}
  if c == "" then
    table.insert(parts, "id" .. op .. "c")
  else
    table.insert(parts, "id" .. op .. c)
  end
  table.insert(parts, "f:c")
  return table.concat(parts, "+")
end

function buildProQuery()
  local parts = {}
  local c = colorString()
  if c ~= "" then
    table.insert(parts, "id" .. (packInput.colorOp or ":") .. c)
  end
  if packInput.termValue1 ~= "" then
    local t = TERM_TYPES[packInput.termType1]
    local opList = TERM_OPS[t] or {":"}
    local op = opList[packInput.termOp1] or opList[1]
    table.insert(parts, t .. op .. packInput.termValue1)
  end
  table.insert(parts, "f:c")
  return table.concat(parts, "+")
end

function buildMythicQuery()
  local parts = {}
  local c = colorString()
  if c ~= "" then
    table.insert(parts, "id" .. (packInput.colorOp or ":") .. c)
  end
  for _, slot in ipairs({
    {TERM_TYPES[packInput.termType1], packInput.termOp1, packInput.termValue1},
    {TERM_TYPES[packInput.termType2], packInput.termOp2, packInput.termValue2},
  }) do
    local t, opIdx, v = slot[1], slot[2], slot[3]
    if v ~= "" then
      local opList = TERM_OPS[t] or {":"}
      local op = opList[opIdx] or opList[1]
      table.insert(parts, t .. op .. v)
    end
  end
  table.insert(parts, "f:c")
  return table.concat(parts, "+")
end

function normalizeOtagTerm(value)
  local s = tostring(value or "")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return "" end

  local prefix = "otag"
  local rawPrefix, rest = s:match("^%-?%s*([%a]+)%s*[:=]%s*(.+)$")
  if rawPrefix then
    local p = rawPrefix:lower()
    if p == "otag" or p == "oracletag" or p == "function" then
      prefix = p
      s = rest
    end
  end

  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  s = s:gsub("^[\"']+", ""):gsub("[\"']+$", "")
  s = s:gsub("[_+]+", " ")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return "" end

  s = s:lower()
  if s:find("%s") then
    s = "\"" .. s:gsub("\"", "") .. "\""
  end
  return prefix .. ":" .. s
end

function buildOtagQuery()
  local parts = {}
  local c = colorString()
  -- Keep OTAG first: Scryfall OTAG matching can under-return when OTAG is not the first clause.
  local otagTerm = normalizeOtagTerm(packInput.otag)
  if otagTerm == "" then return "" end
  table.insert(parts, otagTerm)
  if c ~= "" then table.insert(parts, "id" .. (packInput.colorOp or ":") .. c) end
  table.insert(parts, "f:c")
  return table.concat(parts, "+")
end

--==============================================================================
-- Purchase + spawn
--==============================================================================

function checkPoolSize(query, callback)
  if not query or query == "" then callback(nil) return end

  -- Pool checks are backend-first for all packs (pro/mythic/otag).
  -- If backend /search is unavailable (or returns a capped count), fall back to Scryfall.

  -- Adapt the spawner query syntax for the Scryfall public API:
  --   id=X   → id<=X   (within-identity; Scryfall uses <= for "can fit inside")
  --   <=     → %3C%3D  (must encode compound operators before singles)
  --   >=     → %3E%3D
  --   <      → %3C
  --   >      → %3E
  local function fallbackToScryfall()
    local adapted = query
    adapted = adapted:gsub("id=",  "id<=")
    adapted = adapted:gsub("<=",   "%%3C%%3D")
    adapted = adapted:gsub(">=",   "%%3E%%3D")
    adapted = adapted:gsub("<",    "%%3C")
    adapted = adapted:gsub(">",    "%%3E")

    local url = SCRYFALL_SEARCH_URL .. "?q=" .. adapted .. "&unique=cards&format=json"

    -- Scryfall requires a User-Agent header; WebRequest.get sends none and gets
    -- a 403 "client_update_required".  Use WebRequest.custom to supply one.
    WebRequest.custom(url, "GET", true, nil,
      {["User-Agent"] = "MTGRoguelikeSpawner/2.0 (TTS mod; contact mtd.danab@gmail.com)"},
      function(wr)
        if wr.is_error or not wr.text or wr.text == "" then
          callback(nil)
          return
        end
        -- Pattern-match total_cards directly; avoids JSON.decode on the full
        -- Scryfall payload (up to 175 card objects per page).
        local total = wr.text:match('"total_cards"%s*:%s*(%d+)')
        if total then
          callback(tonumber(total))
          return
        end
        -- Scryfall returns {code="not_found"} when the query is valid but matches
        -- zero cards — that is a real answer (0), not an API failure.
        if wr.text:match('"code"%s*:%s*"not_found"') then
          callback(0)
          return
        end
        callback(nil)
      end
    )
  end

  local backendQuery = tostring(query):gsub("%+", " ")
  local backendSearchURL = backendURL .. SEARCH_ENDPOINT_PATH
    .. "?q=" .. urlEncode(backendQuery)
    .. "&limit=" .. tostring(BACKEND_POOL_COUNT_LIMIT)
  WebRequest.custom(backendSearchURL, "GET", true, nil,
    {['Accept-Language'] = 'en'},
    function(wr)
      if not wr.is_error and wr.text and wr.text ~= "" then
        local total = wr.text:match('"total_cards"%s*:%s*(%d+)')
        if total then
          local totalNum = tonumber(total)
          if totalNum and totalNum < BACKEND_POOL_COUNT_LIMIT then
            callback(totalNum)
            return
          end
        end
        if wr.text:match('"code"%s*:%s*"not_found"') then
          callback(0)
          return
        end
      end
      fallbackToScryfall()
    end
  )
end

function attemptPurchase(packName)
  local isCashoutRedemption = (pendingMerchantPackCashout ~= nil)
  local cashoutToken = isCashoutRedemption and pendingMerchantPackCashout.object or nil
  local cashoutName = isCashoutRedemption and pendingMerchantPackCashout.packName or nil
  local paidXP = 0
  
  -- For cashout redemption, skip XP checks and locks
  if not isCashoutRedemption then
    if isMerchantPackLockedForTown(packName) then
      broadcastToAll("[" .. self.getName() .. "] " .. packName
        .. " pack is limited to once per town while Cursed Pumpkins is active.", {0.95, 0.45, 0.2})
      showBuyScreen()
      return
    end
    local baseCost = getMerchantPackCost(packName)
    local gamblerResult = tryGamblersNeverQuit(baseCost)
    local cost = (gamblerResult ~= nil) and gamblerResult or baseCost
    if xp < cost then
      broadcastToAll("[" .. self.getName() .. "] Not enough XP for " .. packName
        .. " pack (have " .. xp .. ", need " .. cost .. ").", {0.9, 0.3, 0.3})
      return
    end
    xp = math.max(XP_MIN, xp - cost)
    paidXP = cost
    markMerchantPackPurchased(packName)
    recordXPTransaction(-cost, packName:sub(1,1):upper() .. packName:sub(2) .. " Pack")
    notifyMasters()
    broadcastToAll("[" .. self.getName() .. "] Bought " .. packName .. " pack for "
      .. cost .. " XP (" .. xp .. " remaining).", {0.4, 0.85, 0.4})
  else
    broadcastToAll("[" .. self.getName() .. "] Redeeming Merchant Pack: " .. cashoutName, {0.5, 0.85, 0.5})
  end

  if packName == "mystery" then
    spawnMysteryPack(paidXP, packName)
    -- Destroy the cashout token and clear state for mystery redemptions.
    -- Without this, pendingMerchantPackCashout stays set and every subsequent
    -- mystery pack purchase is treated as a cashout, skipping XP deduction entirely.
    if isCashoutRedemption and cashoutToken then
      ess_safeDestructObject(cashoutToken)
      pendingMerchantPackCashout = nil
    end
  else
    local q
    if packName == "identity" then q = buildIdentityQuery()
    elseif packName == "pro"    then q = buildProQuery()
    elseif packName == "mythic" then q = buildMythicQuery()
    elseif packName == "otag"   then q = buildOtagQuery() end
    if not q or q == "" then
      if not isCashoutRedemption then
        broadcastToAll("[" .. self.getName() .. "] Empty pack query; refunding.", {0.9, 0.3, 0.3})
        refundXP(paidXP, packName .. " Pack Refund (empty query)")
        clearMerchantPackPurchased(packName)
      else
        broadcastToAll("[" .. self.getName() .. "] Merchant Pack: invalid filters, refunding token.", {0.9, 0.3, 0.3})
        if cashoutToken then
          ess_safeDestructObject(cashoutToken)
        end
        pendingMerchantPackCashout = nil
        showRedeemCashoutScreen()
        return
      end
    else
      local packCount = getEffectiveStandardPackCount()
      local refundCost = isCashoutRedemption and 0 or paidXP
      spawnParameterizedPack(q, packCount, refundCost, packName)
      
      -- If this was a cashout redemption, destroy the token
      if isCashoutRedemption and cashoutToken then
        ess_safeDestructObject(cashoutToken)
        pendingMerchantPackCashout = nil
      end
    end
  end
  
  if isCashoutRedemption then
    requestSync(DEBOUNCE_SECONDS)
    showRedeemCashoutScreen()
  elseif activePack and activePack == packName then
    openPackInput(activePack)
  else
    showBuyScreen()
  end
end

function spawnMysteryPack(refundCost, packName)
  nBooster = (nBooster or 0) + 1
  local boosterN = nBooster
  getDeckDat(getMysteryPackQueries(), boosterN)
  local delivered = false

  local function refundMystery(reason)
    if refundCost and refundCost > 0 then
      refundXP(refundCost, reason)
      clearMerchantPackPurchased(packName)
      refreshEssenceDisplay()
    end
  end

  Wait.condition(function()
    if delivered then return end
    delivered = true
    local dat = boosterDecks[boosterN]
    boosterDecks[boosterN] = nil
    if not dat then
      refundMystery("Mystery Pack Refund (fetch error)")
      broadcastToAll("[" .. self.getName() .. "] Mystery pack fetch failed.", {0.9, 0.3, 0.3})
      return
    end
    spawnPackDeck(dat)
  end, function() return boosterDecks[boosterN] ~= nil end)
  Wait.time(function()
    if delivered then return end
    delivered = true
    boosterDecks[boosterN] = nil
    refundMystery("Mystery Pack Refund (timeout)")
    broadcastToAll("[" .. self.getName() .. "] Mystery pack timed out.", {0.9, 0.3, 0.3})
  end, BOOSTER_BUILD_TIMEOUT + 5)
end

function spawnParameterizedPack(query, count, refundCost, packName)
  local lowerQuery = tostring(query or ""):lower()
  local isOtagQuery = lowerQuery:find("otag:", 1, true) ~= nil
    or lowerQuery:find("oracletag:", 1, true) ~= nil
    or lowerQuery:find("function:", 1, true) ~= nil

  local function refundWithMessage(message, reason)
    broadcastToAll(message, {0.9, 0.3, 0.3})
    if refundCost and refundCost > 0 then
      refundXP(refundCost, reason)
      clearMerchantPackPurchased(packName)
      refreshEssenceDisplay()
    end
  end

  local function requestRandomFallback(fromReason)
    local wantedCount = tonumber(count or settings.cardsPerPack) or 15
    local randomQuery = tostring(query):gsub("%+", " ")
    local randomUrl = backendURL .. RANDOM_LIST_ENDPOINT_PATH
      .. "?q=" .. urlEncode(randomQuery)
      .. "&count=" .. tostring(wantedCount)
      .. "&enforceCommander=true"

    WebRequest.custom(randomUrl, "GET", true, nil,
      {['Accept-Language'] = 'en'},
      function(wr)
        if wr.is_error or not wr.text or wr.text == "" then
          refundWithMessage(
            "[" .. self.getName() .. "] Pack fetch failed after fallback (" .. tostring(fromReason or "build") .. ", HTTP " .. tostring(wr.response_code) .. "). XP refunded.",
            "Pack Refund (fetch error)"
          )
          return
        end
        local deck = deckFromRandomListResponse(wr.text)
        if deck then
          spawnPackDeck(deck)
          return
        end
        refundWithMessage(
          "[" .. self.getName() .. "] Pack returned no cards after fallback (" .. tostring(fromReason or "build") .. "). XP refunded.",
          "Pack Refund (no cards)"
        )
      end
    )
  end

  local function requestBuild()
    postBuildNDJSON({
      q = query, count = count or settings.cardsPerPack,
      enforceCommander = true, forceApi = false, back = backURL,
    }, function(wr)
      if not wr.is_done then return end
      local hasError = wr.is_error or (wr.response_code and wr.response_code >= 400)
      if hasError or not wr.text or wr.text == "" then
        if isOtagQuery then
          requestRandomFallback("build_error")
          return
        end
        refundWithMessage(
          "[" .. self.getName() .. "] Pack fetch failed (HTTP " .. tostring(wr.response_code) .. "). XP refunded.",
          "Pack Refund (fetch error)"
        )
        return
      end

      local deck = firstDeckFromNDJSON(wr.text)
      if not deck then
        if isOtagQuery then
          requestRandomFallback("build_no_cards")
          return
        end
        refundWithMessage(
          "[" .. self.getName() .. "] Pack returned no cards. XP refunded.",
          "Pack Refund (no cards)"
        )
        return
      end

      spawnPackDeck(deck)
    end)
  end

  requestBuild()
end

function spawnPackDeck(deckDat)
  -- Edit note: Spawn packs slightly higher and start auto-splay after a much shorter settle window so packs animate promptly. Signed, Sirin.
  local pos = self.getPosition() + Vector(0, 4.0, 0)
  local rot = self.getRotation()
  spawnObjectData({
    data = deckDat,
    position = pos,
    rotation = {rot.x, rot.y, 180},
    callback_function = function(spawned)
      if settings.autoSplay and spawned then
        local triggered = false
        local function beginSplay()
          if triggered then return end
          triggered = true
          autoSplayDeck(spawned)
        end

        Wait.condition(beginSplay, function()
          local ready = false
          pcall(function()
            local velocity = spawned.getVelocity()
            local speed = math.abs(velocity.x) + math.abs(velocity.y) + math.abs(velocity.z)
            local hasStack = false
            if spawned.tag == "Deck" then
              hasStack = true
            else
              local objects = spawned.getObjects()
              hasStack = type(objects) == "table" and #objects > 0
            end
            ready = hasStack and speed < 0.2
          end)
          return ready
        end)
        Wait.frames(beginSplay, AUTOSPLAY_SPAWN_DELAY_FRAMES)
      end
    end,
  })
end

--==============================================================================
-- Auto-splay (callback-driven so the deck remainder stays in-sequence)
--==============================================================================
function autoSplayDeck(deck)
  if not deck then return end

  local s = {
    deck         = deck,
    cols         = math.max(1, settings.splayCols or 3),
    rows         = math.max(1, settings.splayRows or 5),
    spacer       = spacer,
    flip         = flip,
    heightOffset = heightOffset,
  }
  splayState = s

  local size = deck.getBoundsNormalized().size
  size = {x = size.x + s.spacer, y = size.y, z = size.z + s.spacer}
  local angle = math.rad(deck.getRotation().y - self.getRotation().y)
  local rx = math.abs(size.x * math.cos(angle)) + math.abs(size.z * math.sin(angle))
  local rz = math.abs(size.x * math.sin(angle)) + math.abs(size.z * math.cos(angle))
  s.cellSize = {x = rx, z = rz}

  local function placeSplayedCard(cardObj, targetPos, applyFlip)
    if not cardObj then return end
    pcall(function()
      cardObj.setPositionSmooth(targetPos, false, true)
      if applyFlip and cardObj.is_face_down then
        cardObj.flip()
      end
    end)
  end

  local function targetPosition(index)
    local zeroBased = index - 1
    local colStep = zeroBased % s.cols
    local rowStep = math.floor(zeroBased / s.cols)
    local pos_local = {
      x = -s.cellSize.x * (s.cols - 1) / 2 + s.cellSize.x * colStep,
      y = 1.5 + s.heightOffset,
      z = -s.cellSize.z - s.cellSize.z * rowStep,
    }
    return self.positionToWorld(pos_local)
  end

  local isCard = false
  pcall(function() isCard = deck.tag == "Card" end)
  if isCard then
    placeSplayedCard(deck, targetPosition(1), s.flip)
    return
  end

  local spreadCards = nil
  local spreadStarted = false
  pcall(function()
    local spreadDistance = math.max(0.25, math.min(s.cellSize.x, 1.0))
    spreadCards = deck.spread(spreadDistance)
    spreadStarted = type(spreadCards) == "table"
  end)

  if not spreadStarted then
    return
  end

  -- Edit note: Auto-splay now uses deck.spread for full-deck extraction, then smooth-moves all spawned cards into the target layout. Signed, Sirin.
  Wait.frames(function()
    for index, cardObj in ipairs(spreadCards) do
      if index > (s.cols * s.rows) then break end
      local destroyed = false
      pcall(function() destroyed = cardObj.isDestroyed() end)
      if not destroyed then
        placeSplayedCard(cardObj, targetPosition(index), s.flip)
      end
    end
  end, 1)
end

--==============================================================================
-- ESSENCE: helpers (ported from Doomblade)
--==============================================================================
PLACEHOLDER_DESC = "(Description pending - update later)"

function ess_trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function ess_parseNumber(input)
  if input == nil then return nil end
  local s = tostring(input)
  s = ess_trim(s)
  if s == "" then return nil end
  s = s:gsub(",", ""):gsub("%s+", "")
  return tonumber(s)
end

function ess_urlEncode(str)
  if str == nil then return "" end
  str = tostring(str)
  str = string.gsub(str, "[^%w _%%%-%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  str = string.gsub(str, " ", "+")
  return str
end

function ess_resolveSteamName(player_color)
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

function ess_resolvePlayerId(player_color)
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

function ess_toId(name)
  local id = string.lower(name or "")
  id = id:gsub("[^%w]+", "_")
  id = id:gsub("^_+", ""):gsub("_+$", "")
  return id
end

function ess_entryName(entry)
  if type(entry) == "table" then return entry.name end
  return entry
end

function ess_entryDesc(entry)
  if type(entry) == "table" then return entry.desc end
  return nil
end

function ess_entryIsRepeatable(entry)
  return type(entry) == "table" and entry.repeatable == true
end

function ess_getItemCount(item)
  if type(item) ~= "table" then return 0 end
  local count = tonumber(item.count)
  if count == nil then count = item.unlocked and 1 or 0 end
  return math.max(0, math.floor(count))
end

function ess_isItemUnlocked(item)
  return ess_getItemCount(item) > 0
end

function ess_incrementItemUnlock(item)
  if type(item) ~= "table" then return 0 end
  local count = ess_getItemCount(item)
  if item.repeatable then
    count = count + 1
  elseif count == 0 then
    count = 1
  end
  item.count = count
  item.unlocked = count > 0
  item.unlock_time = item.unlock_time or os.date("!%Y-%m-%dT%H:%M:%SZ")
  item.last_unlock_time = os.date("!%Y-%m-%dT%H:%M:%SZ")
  return count
end

function ess_decrementItemUnlock(item)
  if type(item) ~= "table" then return 0 end
  local count = math.max(0, ess_getItemCount(item) - 1)
  item.count   = count
  item.unlocked = count > 0
  return count
end

function isBuffEquipped(name)
  if not name then return nil end
  for i = 1, MAX_EQUIPPED do
    local b = equippedBuffs[i]
    if b and b.name == name then return i end
  end
  return nil
end

-- Emblem Ticket costs 3 slots; Vanguard Ticket costs 2; everything else costs 1.
local BUFF_SLOT_COSTS = { ["Emblem Ticket"] = 3, ["Vanguard Ticket"] = 2 }
function getBuffSlotCost(name) return BUFF_SLOT_COSTS[name] or 1 end

function countEquipped()
  local n = 0
  for i = 1, MAX_EQUIPPED do
    if equippedBuffs[i] then n = n + getBuffSlotCost(equippedBuffs[i].name) end
  end
  return n
end

function equipBuff(entry, category)
  if not entry then return end
  local name = entry.name or entry.id
  if isBuffEquipped(name) then
    broadcastToAll("[" .. self.getName() .. "] " .. name .. " is already equipped.", {0.9, 0.8, 0.4})
    return
  end
  local cost = getBuffSlotCost(name)
  local used = countEquipped()
  if used + cost > MAX_EQUIPPED then
    local free = MAX_EQUIPPED - used
    broadcastToAll("[" .. self.getName() .. "] Not enough buff slots — "
      .. name .. " needs " .. cost .. " slot" .. (cost > 1 and "s" or "")
      .. " but only " .. free .. " free.", {0.9, 0.5, 0.2})
    return
  end
  for i = 1, MAX_EQUIPPED do
    if not equippedBuffs[i] then
      equippedBuffs[i] = {name = name, category = category}
      broadcastToAll("[" .. self.getName() .. "] Equipped: " .. name, {0.7, 1, 0.7})
      return
    end
  end
end

function unequipSlot(idx)
  if not idx or not equippedBuffs[idx] then return end
  local name = equippedBuffs[idx].name
  equippedBuffs[idx] = nil
  broadcastToAll("[" .. self.getName() .. "] Unequipped: " .. tostring(name), {1, 0.85, 0.5})
end

function unequipByName(name)
  local idx = isBuffEquipped(name)
  if idx then unequipSlot(idx) end
end

function calcBuffBonus(buffName, amt)
  if amt <= 0 then return 0 end
  if not isBuffEquipped(buffName) then return 0 end
  return math.ceil(amt * 0.25)
end

function ess_normalizeName(s)
  s = string.lower(s or "")
  s = s:gsub("%[/?[biuBIU]%]", "")
  s = s:gsub("[“”]", '"')
  s = s:gsub("[’‘]", "'")
  s = s:gsub('"', ""):gsub("'", "")
  s = s:gsub("[–—]", "-")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  return s
end

function ess_stripBbcode(s)
  return (tostring(s or ""):gsub("%[/?[biuBIU]%]", ""))
end

function ess_parseCaptureTicketName(rawName)
  if rawName == nil then return nil end
  local plain = ess_stripBbcode(rawName)
  local lower = string.lower(plain)
  local idx = lower:find(string.lower(CAPTURE_TICKET_LABEL), 1, true)
  if not idx then return nil end
  local after = plain:sub(idx + #CAPTURE_TICKET_LABEL)
  local name = ess_trim(after)
  if name == "" then return nil end
  return name
end

function ess_markHandledObjectOnce(obj)
  if not obj then return false end
  local ok, guid = pcall(function() return obj.getGUID() end)
  if not ok or not guid or guid == "" then return false end
  if recentlyHandledGuids[guid] then return true end
  recentlyHandledGuids[guid] = true
  Wait.time(function() recentlyHandledGuids[guid] = nil end, 0.75)
  return false
end

function ess_safeDestructObject(obj)
  if not obj then return end
  Wait.frames(function()
    pcall(function() if obj.destruct then obj.destruct() end end)
  end, 1)
end

function ess_isPlaceholderDesc(desc, item)
  if desc == nil then return true end
  local s = ess_trim(tostring(desc))
  if s == "" then return true end
  local lower = string.lower(s)
  if lower == string.lower(PLACEHOLDER_DESC) then return true end
  if string.find(lower, "description pending", 1, true) then return true end
  if item then
    if s == item.name or s == item.id then return true end
  end
  return false
end

function ess_ensurePlaceholderDescriptions(cat)
  if type(cat) ~= "table" then return end
  for _, item in pairs(cat) do
    if type(item) == "table" then
      if item.desc == nil or tostring(item.desc) == "" or item.desc == item.name or item.desc == item.id then
        item.desc = PLACEHOLDER_DESC
      end
    end
  end
end

function initCategoryFromList(list)
  local t = {}
  for _, entry in ipairs(list or {}) do
    local name = ess_entryName(entry)
    if name and name ~= "" then
      local id = ess_toId(name)
      local desc = ess_entryDesc(entry) or PLACEHOLDER_DESC
      t[id] = {
        id = id, name = name, unlocked = false, count = 0,
        repeatable = ess_entryIsRepeatable(entry),
        unlock_time = nil, last_unlock_time = nil, desc = desc,
      }
    end
  end
  return t
end

function serializeCategory(cat)
  local parts = {}
  for id, item in pairs(cat or {}) do
    table.insert(parts, id .. ":" .. tostring(ess_getItemCount(item)))
  end
  return table.concat(parts, "|")
end

function deserializeCategory(serialized, template)
  local out = template and initCategoryFromList(template) or {}
  if not serialized or serialized == "" then return out end
  for pair in string.gmatch(serialized, "[^|]+") do
    local id, status = string.match(pair, "([^:]+):(%d+)")
    if id then
      if not out[id] then out[id] = { id = id, name = id, desc = PLACEHOLDER_DESC } end
      out[id].count = math.max(0, math.floor(tonumber(status) or 0))
      out[id].unlocked = out[id].count > 0
    end
  end
  ess_ensurePlaceholderDescriptions(out)
  return out
end

function mergeSavedCategory(savedTable, templateList)
  local out = initCategoryFromList(templateList or {})
  if type(savedTable) ~= "table" then
    ess_ensurePlaceholderDescriptions(out)
    return out
  end
  for id, savedItem in pairs(savedTable) do
    if out[id] and type(savedItem) == "table" then
      local savedCount = tonumber(savedItem.count)
      if savedCount == nil then savedCount = savedItem.unlocked and 1 or 0 end
      out[id].count = math.max(0, math.floor(savedCount))
      out[id].unlocked = out[id].count > 0
      out[id].unlock_time = savedItem.unlock_time or out[id].unlock_time
      out[id].last_unlock_time = savedItem.last_unlock_time or out[id].last_unlock_time
      if ess_isPlaceholderDesc(out[id].desc, out[id]) and not ess_isPlaceholderDesc(savedItem.desc, savedItem) then
        out[id].desc = savedItem.desc
      end
    end
  end
  ess_ensurePlaceholderDescriptions(out)
  return out
end

function ess_serializeCaptures(captures)
  return JSON.encode(captures or {})
end

function ess_sanitizeCaptureBagData(data)
  if type(data) ~= "table" then return nil end

  if data._schema == "capture_payload_v2" then
    return data
  end

  if hasContainedCardPayload(data) then
    local containedList = normalizeContainedObjectsList(data.ContainedObjects)
    local first = containedList[1]
    if type(first) ~= "table" then return nil end

    local compact = buildCapturePayloadFromSingleCardData(first)
    if not compact then return nil end
    if type(data.CustomMesh) == "table" and data.CustomMesh.DiffuseURL and data.CustomMesh.DiffuseURL ~= "" then
      compact.bagDiffuseURL = tostring(data.CustomMesh.DiffuseURL)
    elseif compact.bagDiffuseURL == "" and compact.card and compact.card.faceURL then
      compact.bagDiffuseURL = tostring(compact.card.faceURL)
    end
    return compact
  end

  return buildCapturePayloadFromSingleCardData(data)
end

function ess_normalizeCapturesTable(captures)
  local out = {}
  if type(captures) ~= "table" then return out end
  for key, item in pairs(captures) do
    if type(item) == "table" then
      local name = item.name or item.capture_name or item.title or (type(key) == "string" and key or "")
      if name and name ~= "" then
        local id = item.id or ess_toId(name)
        local url = item.url or item.imageUrl or item.image or ""
        local desc = item.desc or ("Capture ticket for " .. name .. ".")
        local bagData = ess_sanitizeCaptureBagData(item.bagData or item.bag_data)
        if url == "" and bagData then
          url = extractCaptureFaceUrlFromPayload(bagData)
        end
        out[id] = {
          id       = id,
          name     = name,
          unlocked = (item.unlocked ~= false),
          count    = tonumber(item.count) or (item.unlocked == false and 0) or 1,
          url      = url,
          bagData  = bagData,
          desc     = desc,
          unlock_time      = item.unlock_time,
          last_unlock_time = item.last_unlock_time,
        }
      end
    elseif type(item) == "string" and type(key) == "string" then
      local name = item
      local id = ess_toId(name)
      out[id] = { id = id, name = name, unlocked = true, count = 1, url = "",
                  desc = "Capture ticket for " .. name .. "." }
    end
  end
  return out
end

function ess_decodeCaptures(value)
  if value == nil then return {} end
  if type(value) == "string" then
    if value == "" then return {} end
    local ok, decoded = pcall(JSON.decode, value)
    if ok then return ess_normalizeCapturesTable(decoded) end
    return {}
  end
  if type(value) == "table" then
    return ess_normalizeCapturesTable(value)
  end
  return {}
end

function clampEssence(v)
  v = math.floor(tonumber(v) or 0)
  if v > MAX_VALUE then return MAX_VALUE end
  if v < 0 then return 0 end
  return v
end

function getNowSeconds()
  if Time and Time.time ~= nil then
    if type(Time.time) == "number" then return Time.time end
    if type(Time.time) == "function" then
      local ok, t = pcall(Time.time)
      if ok and type(t) == "number" then return t end
    end
  end
  return os.clock()
end

--==============================================================================
-- ESSENCE: cloud sync (ported verbatim from Doomblade — DO NOT MODIFY)
--==============================================================================
function queueSyncSend(delaySeconds)
  local delay = tonumber(delaySeconds) or DEBOUNCE_SECONDS
  if delay < 0 then delay = 0 end
  if pendingHandle then pcall(function() Wait.stop(pendingHandle) end) pendingHandle = nil end
  pendingHandle = Wait.time(function()
    pendingHandle = nil
    sendData()
  end, delay)
end

function markSyncFailed()
  lastSyncSignature = ""
  syncDirty = true
  if syncQueued then
    syncQueued = false
    queueSyncSend(DEBOUNCE_SECONDS)
  end
end

function requestSync(delaySeconds)
  syncDirty = true
  if not localPlayerKey or not isSyncEnabled then return end
  queueSyncSend(delaySeconds or DEBOUNCE_SECONDS)
end

function markDirty()
  requestSync(DEBOUNCE_SECONDS)
end

function fetchSavedValue()
  if not localPlayerKey then
    isSyncEnabled = true
    return
  end

  local function ensureStarterEssence()
    if essence < 200 then
      essence = 200
      print("[" .. self.getName() .. "] New profile detected. Granted starter Essence: " .. essence)
      refreshEssenceDisplay()
      if currentScreen == "essence" then showEssenceScreen() end
      notifyMasters()
    end
  end

  local url = WEB_URL .. "?playerKey=" .. ess_urlEncode(localPlayerKey)

  WebRequest.get(url, function(req)
    if req.is_error then
      isSyncEnabled = true
      return
    end

    if req.text == nil or req.text == "" then
      ensureStarterEssence()
      isSyncEnabled = true
      if localPlayerKey then sendData(true) end
      return
    end

    local ok, data = pcall(JSON.decode, req.text)
    if not ok then
      isSyncEnabled = true
      return
    end

    local hasProfileData = false
    if data.value ~= nil or data.achievements ~= nil or data.crypt ~= nil
      or data.tickets ~= nil or data.brands ~= nil or data.captures ~= nil then
      hasProfileData = true
    end
    if not hasProfileData then
      ensureStarterEssence()
      isSyncEnabled = true
      if localPlayerKey then sendData(true) end
      return
    end

    if data.value ~= nil then
      essence = clampEssence(ess_parseNumber(data.value) or 0)
      print("[" .. self.getName() .. "] Loaded Essence: " .. essence)
    end

    if data.achievements then
      essenceState.achievements = deserializeCategory(data.achievements, ACHIEVEMENTS_LIST)
    end
    if data.crypt then
      essenceState.crypt = deserializeCategory(data.crypt, CRYPT_REWARDS)
    end
    if data.tickets then
      essenceState.tickets = deserializeCategory(data.tickets, TICKETS_LIST)
    end
    if data.brands then
      essenceState.brands = deserializeCategory(data.brands, BRANDS_LIST)
    end
    if data.captures ~= nil then
      essenceState.captures = ess_decodeCaptures(data.captures)
    end

    syncDirty = false

    ess_ensurePlaceholderDescriptions(essenceState.achievements)
    ess_ensurePlaceholderDescriptions(essenceState.crypt)
    ess_ensurePlaceholderDescriptions(essenceState.tickets)
    ess_ensurePlaceholderDescriptions(essenceState.brands)

    refreshEssenceDisplay()
    if currentScreen == "essence" then showEssenceScreen() end
    notifyMasters()

    isSyncEnabled = true
  end)
end

function sendData(force)
  if not localPlayerKey then return end
  if not force and not syncDirty then return end
  if syncInFlight then
    syncQueued = true
    return
  end

  local desc = ess_trim(self.getDescription() or "")
  local payload = {
    playerKey    = localPlayerKey,
    timestamp    = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    name         = self.getName(),
    description  = desc,
    value        = essence,
    achievements = serializeCategory(essenceState.achievements),
    crypt        = serializeCategory(essenceState.crypt),
    tickets      = serializeCategory(essenceState.tickets),
    brands       = serializeCategory(essenceState.brands),
    captures     = ess_serializeCaptures(essenceState.captures),
  }

  local signature = table.concat({
    tostring(payload.playerKey or ""),
    tostring(payload.name or ""),
    tostring(payload.description or ""),
    tostring(payload.value or ""),
    tostring(payload.achievements or ""),
    tostring(payload.crypt or ""),
    tostring(payload.tickets or ""),
    tostring(payload.brands or ""),
    tostring(payload.captures or ""),
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

  lastSyncSignature = signature
  lastSyncSentAt = now
  syncInFlight = true

  WebRequest.post(WEB_URL, JSON.encode(payload), function(req)
    syncInFlight = false
    if req.is_error then
      print("[" .. self.getName() .. "] Sync request failed")
      markSyncFailed()
      return
    end

    local responseText = tostring(req.text or "")
    if responseText ~= "" then
      local okJ, responseData = pcall(JSON.decode, responseText)
      if okJ and type(responseData) == "table" then
        if responseData.error then
          print("[" .. self.getName() .. "] Sync failed: " .. tostring(responseData.error))
          if responseData.err then
            print("[" .. self.getName() .. "] Sync detail: " .. tostring(responseData.err))
          end
          markSyncFailed()
          return
        end
        if responseData.status and tostring(responseData.status) ~= "OK" then
          print("[" .. self.getName() .. "] Sync returned unexpected status: " .. tostring(responseData.status))
          markSyncFailed()
          return
        end
      else
        print("[" .. self.getName() .. "] Sync returned non-JSON response")
        markSyncFailed()
        return
      end
    end

    syncDirty = false
    if syncQueued then
      syncQueued = false
      queueSyncSend(DEBOUNCE_SECONDS)
    end
  end, { ["Content-Type"] = "application/json" })
end

function onPickUp(player_color)
  local desc = self.getDescription() or ""
  local pname = ess_resolveSteamName(player_color)
  local pid   = ess_resolvePlayerId(player_color)

  if string.find(desc, BAG_MARKER, 1, true) then
    if pname then self.setName(pname) end
    local cleaned = ess_trim(desc:gsub("%[from%-bag%]", ""))
    self.setDescription(cleaned)
  end

  local keyBase = pid or pname

  -- First pickup by any player with a resolvable Steam identity claims this card.
  -- The TTS object name is not required — a blank/unclaimed card still claims correctly.
  if not localPlayerKey and keyBase then
    localPlayerKey    = keyBase .. "_Essence"
    claimedPlayerName = pname or keyBase
    self.setName(claimedPlayerName)
    if currentScreen == "shop" then showShopScreen() end
  end

  if localPlayerKey and not isSyncEnabled then
    fetchSavedValue()
  end
end

function getEssence() return essence end

function receiveEssence(params)
  local amt, bypass = 0, false
  if type(params) == "number" then amt = params
  elseif type(params) == "table" and type(params.amount) == "number" then
    amt = params.amount
    bypass = params.bypassBuff == true
  end
  applyEssenceDeltaTracked(amt, bypass and "Reverted Essence" or "Received Essence", bypass)
  return essence
end

function applyEssenceDelta(amt, bypassBuff)
  amt = math.floor(tonumber(amt) or 0)
  if amt == 0 then return essence end
  if not localPlayerKey and amt ~= 0 then
    -- Mirror Doomblade: allow the change anyway so the host can grant/remove
    -- before anyone has claimed the card.
    if amt > 0 then
      broadcastToAll("[" .. self.getName() .. "] No player has claimed this Essence card yet. Change applied locally only.",
        {0.95, 0.75, 0.3})
    end
  end
  local bonus = 0
  if not bypassBuff then
    bonus = calcBuffBonus("Spiritual Guidance", amt)
    if bonus > 0 then
      broadcastToAll("[" .. self.getName() .. "] Spiritual Guidance: +" .. tostring(bonus) .. " bonus Essence!", {0.8, 0.6, 1})
    end
  end
  essence = clampEssence(essence + amt + bonus)
  refreshEssenceDisplay()
  if currentScreen == "essence" then showEssenceScreen() end
  notifyMasters()
  markDirty()
  return essence
end

function getCaptureCount()
  local n = 0
  for _ in pairs(essenceState.captures or {}) do n = n + 1 end
  return n
end

function getCapturePrice()
  return CAPTURE_BASE_COST + getCaptureCount() * CAPTURE_PRICE_STEP
end

function getBrandBaseCost(entry)
  if not entry or not entry.desc then return 0 end
  -- Parses "Base Cost: 1250 Essence" out of the description field.
  local cost = entry.desc:match("Base Cost:%s*(%d+)")
  return tonumber(cost) or 0
end

function getBrandNextPrice(entry)
  local baseCost = getBrandBaseCost(entry)
  if baseCost <= 0 then return 0 end
  local id = ess_toId(entry.name)
  local item = essenceState.brands and essenceState.brands[id]
  local count = item and ess_getItemCount(item) or 0
  return baseCost * (count + 1)
end

function getBrandRankByName(name)
  if not name or name == "" then return 0 end
  local id = ess_toId(name)
  local item = essenceState.brands and essenceState.brands[id]
  return item and ess_getItemCount(item) or 0
end

function getPackChoiceBonusFromBrands()
  return math.max(0, getBrandRankByName("Brand of the Open Hand"))
end

function getGuildCommanderChoiceBonusFromBrands()
  return math.max(0, getBrandRankByName("Brand of the Conclave"))
end

function showPurchaseConfirm(entry, tab)
  if not entry then return end
  pendingPurchase = {entry = entry, tab = tab}
  openScreen("confirm", nil)
  local price = (tab == "brands") and getBrandNextPrice(entry) or getBrandBaseCost(entry)
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Confirm Purchase?",
    position = {0, 0.1, -0.75},
    width = 1200, height = 170, font_size = 95,
    color = {0.2, 0.15, 0.3}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = entry.name,
    position = {0, 0.1, -0.1},
    width = 1400, height = 170, font_size = 72,
    color = {0.25, 0.2, 0.35}, font_color = {1, 1, 0.85},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Cost: " .. tostring(price) .. " Essence",
    position = {0, 0.1, 0.5},
    width = 1000, height = 150, font_size = 75,
    color = {0.18, 0.18, 0.3}, font_color = {0.75, 0.65, 1},
  })
  trackButton({
    click_function = "click_purchaseConfirmCancel", function_owner = self,
    label = "Cancel",
    position = {-1.0, 0.1, 1.2},
    width = 500, height = 150, font_size = 80,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_purchaseConfirmOK", function_owner = self,
    label = "Buy",
    position = {1.0, 0.1, 1.2},
    width = 500, height = 150, font_size = 80,
    color = {0.15, 0.5, 0.15}, font_color = {1, 1, 1},
  })
end

function click_purchaseConfirmCancel()
  pendingPurchase = nil
  showEssenceScreen()
end

function click_purchaseConfirmOK()
  local p = pendingPurchase
  pendingPurchase = nil
  if not p then showEssenceScreen() return end
  if p.tab == "brands"  then purchaseBrand(p.entry)  return end
  if p.tab == "tickets" then purchaseTicket(p.entry) return end
  showEssenceScreen()
end

function showSellCryptConfirm(entry)
  if not entry then return end
  pendingSell = entry
  openScreen("sell_confirm", nil)
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Sell Crypt Buff?",
    position = {0, 0.1, -0.75}, width = 1200, height = 170, font_size = 95,
    color = {0.3, 0.15, 0.1}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = entry.name,
    position = {0, 0.1, -0.1}, width = 1400, height = 170, font_size = 72,
    color = {0.25, 0.18, 0.12}, font_color = {1, 0.85, 0.6},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Refund: 250 Essence",
    position = {0, 0.1, 0.5}, width = 1000, height = 150, font_size = 75,
    color = {0.18, 0.18, 0.18}, font_color = {0.65, 1, 0.65},
  })
  trackButton({
    click_function = "click_sellCryptCancel", function_owner = self,
    label = "Cancel",
    position = {-1.0, 0.1, 1.2}, width = 500, height = 150, font_size = 80,
    color = {0.5, 0.15, 0.15}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_sellCryptOK", function_owner = self,
    label = "Sell",
    position = {1.0, 0.1, 1.2}, width = 500, height = 150, font_size = 80,
    color = {0.5, 0.35, 0.1}, font_color = {1, 1, 1},
  })
end

function click_sellCryptCancel()
  pendingSell = nil
  showEssenceScreen()
end

function click_sellCryptOK()
  local entry = pendingSell
  pendingSell = nil
  if not entry then showEssenceScreen() return end
  local id   = ess_toId(entry.name or entry.id or "")
  local item = essenceState.crypt and essenceState.crypt[id]
  if not item or ess_getItemCount(item) <= 0 then
    broadcastToAll("[" .. self.getName() .. "] " .. (entry.name or "?") .. " — not owned.", {0.9, 0.5, 0.2})
    showEssenceScreen()
    return
  end
  local equippedIdx = isBuffEquipped(entry.name or entry.id)
  if equippedIdx then unequipSlot(equippedIdx) end
  ess_decrementItemUnlock(item)
  applyEssenceDeltaTracked(250, "Sell Crypt: " .. (entry.name or "?"))
  broadcastToAll("[" .. self.getName() .. "] Sold " .. (entry.name or "?") .. " for 250 Essence.", {1, 0.85, 0.4})
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  showEssenceScreen()
end

-- For brands: each successive level costs baseCost*level, so the last level paid
-- is baseCost * currentCount.  For tickets: flat baseCost refund.
function refundBrand(entry)
  if not entry then return end
  if not localPlayerKey then
    broadcastToAll("[" .. self.getName() .. "] Pick up the card first.", {0.95, 0.75, 0.3})
    return
  end
  local id   = ess_toId(entry.name)
  local item = essenceState.brands and essenceState.brands[id]
  local count = item and ess_getItemCount(item) or 0
  if count <= 0 then
    broadcastToAll("[" .. self.getName() .. "] " .. (entry.name or "?") .. " — nothing to refund.", {0.9, 0.5, 0.2})
    return
  end
  local baseCost = getBrandBaseCost(entry)
  local refund   = baseCost * count
  ess_decrementItemUnlock(item)
  applyEssenceDeltaTracked(refund, "Refund Brand: " .. (entry.name or "?"))
  broadcastToAll("[" .. self.getName() .. "] Refunded: " .. (entry.name or "?")
    .. " (now x" .. tostring(count - 1) .. ")  +" .. tostring(refund) .. " Essence", {0.95, 0.9, 0.55})
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  showEssenceScreen()
end

function refundTicket(entry)
  if not entry then return end
  if not localPlayerKey then
    broadcastToAll("[" .. self.getName() .. "] Pick up the card first.", {0.95, 0.75, 0.3})
    return
  end
  local id   = ess_toId(entry.name)
  local item = essenceState.tickets and essenceState.tickets[id]
  local count = item and ess_getItemCount(item) or 0
  if count <= 0 then
    broadcastToAll("[" .. self.getName() .. "] " .. (entry.name or "?") .. " — not owned.", {0.9, 0.5, 0.2})
    return
  end
  local price = getBrandBaseCost(entry)
  ess_decrementItemUnlock(item)
  applyEssenceDeltaTracked(price, "Refund Ticket: " .. (entry.name or "?"))
  broadcastToAll("[" .. self.getName() .. "] Refunded: " .. (entry.name or "?")
    .. "  +" .. tostring(price) .. " Essence", {0.95, 0.9, 0.55})
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  showEssenceScreen()
end

function purchaseBrand(entry)
  if not entry then return end
  if not localPlayerKey then
    broadcastToAll("[" .. self.getName() .. "] Pick up the card first to claim it before purchasing brands.",
      {0.95, 0.75, 0.3})
    return
  end
  local price = getBrandNextPrice(entry)
  if price <= 0 then
    broadcastToAll("[" .. self.getName() .. "] " .. (entry.name or "?") .. " has no purchasable cost defined.",
      {0.9, 0.5, 0.2})
    return
  end
  if essence < price then
    broadcastToAll("[" .. self.getName() .. "] Not enough Essence — need " .. tostring(price)
      .. " (have " .. tostring(essence) .. ").", {0.9, 0.3, 0.3})
    return
  end
  applyEssenceDeltaTracked(-price, "Buy Brand: " .. (entry.name or "?"))
  local id = ess_toId(entry.name)
  local item = essenceState.brands and essenceState.brands[id]
  if item then ess_incrementItemUnlock(item) end
  local count = item and ess_getItemCount(item) or 1
  broadcastToAll("[" .. self.getName() .. "] Purchased: " .. (entry.name or "?")
    .. " (x" .. tostring(count) .. ")  -" .. tostring(price) .. " Essence", {0.7, 0.9, 0.7})
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  showEssenceScreen()
end

function purchaseTicket(entry)
  if not entry then return end
  if not localPlayerKey then
    broadcastToAll("[" .. self.getName() .. "] Pick up the card first to claim it before purchasing tickets.",
      {0.95, 0.75, 0.3})
    return
  end
  local id = ess_toId(entry.name)
  local item = essenceState.tickets and essenceState.tickets[id]
  if item and ess_getItemCount(item) > 0 then
    broadcastToAll("[" .. self.getName() .. "] Already own: " .. (entry.name or "?"), {0.7, 0.9, 0.7})
    return
  end
  local price = getBrandBaseCost(entry)
  if price <= 0 then
    broadcastToAll("[" .. self.getName() .. "] " .. (entry.name or "?") .. " has no purchasable cost defined.",
      {0.9, 0.5, 0.2})
    return
  end
  if essence < price then
    broadcastToAll("[" .. self.getName() .. "] Not enough Essence — need " .. tostring(price)
      .. " (have " .. tostring(essence) .. ").", {0.9, 0.3, 0.3})
    return
  end
  applyEssenceDeltaTracked(-price, "Buy Ticket: " .. (entry.name or "?"))
  if item then ess_incrementItemUnlock(item) end
  broadcastToAll("[" .. self.getName() .. "] Purchased: " .. (entry.name or "?")
    .. "  -" .. tostring(price) .. " Essence", {0.7, 0.9, 0.7})
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  showEssenceScreen()
end

-- Memoized: catalogs are static, so build once on first use.
ess_nameLookupCache = nil
function ess_buildNameLookup()
  if ess_nameLookupCache then return ess_nameLookupCache end
  local lut = {}
  local cats = {
    {key = "crypt",        list = CRYPT_REWARDS},
    {key = "achievements", list = ACHIEVEMENTS_LIST},
    {key = "tickets",      list = TICKETS_LIST},
    {key = "brands",       list = BRANDS_LIST},
  }
  for _, cat in ipairs(cats) do
    for _, entry in ipairs(cat.list) do
      local nm = ess_entryName(entry)
      if nm then
        lut[ess_normalizeName(nm)] = {category = cat.key, id = ess_toId(nm), name = nm}
      end
    end
  end
  ess_nameLookupCache = lut
  return lut
end

function isKnownReward(name)
  if not name or name == "" then return nil end
  local norm = ess_normalizeName(name)
  if ess_buildNameLookup()[norm] then return true end
  -- Capture tickets are intentionally excluded: they're created only through the
  -- purchase flow, never auto-detected from a drop.
  return false
end

function handleRewardDrop(obj)
  if not obj then return false end
  local name = ""
  pcall(function() name = obj.getName() or "" end)
  local norm = ess_normalizeName(name)
  local lut = ess_buildNameLookup()
  local hit = lut[norm]
  if not hit then return false end

  local item = essenceState[hit.category] and essenceState[hit.category][hit.id]
  if not item then return false end

  if ess_markHandledObjectOnce(obj) then return true end

  local function awardCryptBossEssence()
    if hit.category ~= "crypt" then return end
    applyEssenceDeltaTracked(CRYPT_BOSS_ESSENCE, "Crypt Boss Clear: " .. hit.name)
    broadcastToAll("[" .. self.getName() .. "] Crypt boss defeated: +"
      .. tostring(CRYPT_BOSS_ESSENCE) .. " Essence", {0.7, 0.5, 1.0})
  end

  if not item.repeatable and ess_isItemUnlocked(item) then
    applyEssenceDeltaTracked(DUPLICATE_REWARD_ESSENCE, "Duplicate Reward: " .. hit.name, true)
    awardCryptBossEssence()
    print("[" .. self.getName() .. "] Duplicate reward converted to +" .. tostring(DUPLICATE_REWARD_ESSENCE)
      .. " Essence: " .. hit.name)
    ess_safeDestructObject(obj)
    essenceTab = hit.category
    if currentScreen == "essence" then showEssenceScreen() end
    requestSync(DEBOUNCE_SECONDS)
    notifyMasters()
    return true
  end

  ess_incrementItemUnlock(item)
  awardCryptBossEssence()
  print("[" .. self.getName() .. "] Unlocked " .. hit.category .. ": " .. hit.name)
  ess_safeDestructObject(obj)
  essenceTab = hit.category
  if currentScreen == "essence" then showEssenceScreen() end
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  return true
end

--==============================================================================
-- ESSENCE SCREEN UI
--==============================================================================
function sortedCategoryEntries(catKey)
  local list = essenceState[catKey] or {}
  local entries = {}
  for _, item in pairs(list) do entries[#entries + 1] = item end
  table.sort(entries, function(a, b)
    return string.lower(a.name or a.id or "") < string.lower(b.name or b.id or "")
  end)
  return entries
end

function essencePageCount(catKey)
  local n = #sortedCategoryEntries(catKey)
  if n == 0 then return 1 end
  return math.ceil(n / PAGE_SIZE)
end

function showEssenceScreen()
  activePack = nil
  local pages = essencePageCount(essenceTab)
  if essencePage < 1 then essencePage = 1 end
  if essencePage > pages then essencePage = pages end
  openScreen("essence", "back", "Essence")
  drawEssenceTabs()
  drawEssenceGrid()
  drawEquippedSection()
  drawEssencePagination()
  if essenceTab == "captures" then
    drawCaptureShopButton()
  end
end

function click_essenceBack() showShopScreen() end

function drawCaptureShopButton()
  local price = getCapturePrice()
  local canAfford = (essence >= price)
  trackButton({
    click_function = "click_addCapture", function_owner = self,
    label = "Add Capture\n" .. tostring(price) .. " Essence",
    position = {1.5, 0.1, 0.65},
    width = 500, height = 200, font_size = 60,
    color = canAfford and {0.35, 0.2, 0.5} or {0.25, 0.15, 0.25},
    font_color = canAfford and {1, 1, 1} or {0.6, 0.6, 0.6},
  })
end

function drawEssenceTabs()
  -- ±1.85 (not ±2.2) keeps all 5 tabs within card bounds: right edge of tab 5
  -- = 1.85 + (380/2)/~600px ≈ 2.17.
  local xs = {-1.85, -0.925, 0, 0.925, 1.85}
  local handlers = {
    "click_essenceTab_crypt",
    "click_essenceTab_achievements",
    "click_essenceTab_tickets",
    "click_essenceTab_brands",
    "click_essenceTab_captures",
  }
  for i, key in ipairs(ESSENCE_TABS) do
    local active = (key == essenceTab)
    trackButton({
      click_function = handlers[i], function_owner = self,
      label = ESSENCE_TAB_LABELS[key],
      position = {xs[i], 0.1, -0.75},
      width = 380, height = 160, font_size = 60,
      color = active and {0.45, 0.25, 0.45} or {0.25, 0.25, 0.25},
      font_color = {1, 1, 1},
    })
  end
end

function click_essenceTab_crypt()        setEssenceTab("crypt")        end
function click_essenceTab_achievements() setEssenceTab("achievements") end
function click_essenceTab_tickets()      setEssenceTab("tickets")      end
function click_essenceTab_brands()       setEssenceTab("brands")       end
function click_essenceTab_captures()     setEssenceTab("captures")     end

function setEssenceTab(key)
  essenceTab = key
  essencePage = 1
  showEssenceScreen()
end

local GRID_COLOR_EMPTY      = {0.18, 0.18, 0.18}
local GRID_COLOR_LOCKED     = {0.3, 0.3, 0.3}
local GRID_COLOR_OWNED      = {0.2, 0.45, 0.2}
local GRID_COLOR_REPEATABLE = {0.25, 0.35, 0.5}
local GRID_COLOR_BUYABLE    = {0.3, 0.2, 0.45}
local GRID_COLOR_TOO_PRICY  = {0.2, 0.15, 0.25}
local GRID_COLOR_EQUIPPED   = {0.55, 0.42, 0.08}

function renderGridCell(entry, tab)
  if not entry then
    return { label = "---", color = GRID_COLOR_EMPTY, tooltip = nil }
  end

  local count    = ess_getItemCount(entry)
  local unlocked = count > 0
  local label, color

  if tab == "brands" then
    local nextPrice = getBrandNextPrice(entry)
    label = entry.name .. "\nx" .. tostring(count) .. "\n" .. tostring(nextPrice) .. " Ess"
    color = (essence >= nextPrice) and GRID_COLOR_BUYABLE or GRID_COLOR_TOO_PRICY
  elseif tab == "tickets" then
    local price = getBrandBaseCost(entry)
    if unlocked then
      label, color = entry.name .. "\nOwned", GRID_COLOR_OWNED
    elseif price > 0 and essence >= price then
      label, color = entry.name .. "\n" .. tostring(price) .. " Ess", GRID_COLOR_BUYABLE
    else
      label = entry.name .. "\n" .. (price > 0 and (tostring(price) .. " Ess") or "?")
      color = GRID_COLOR_TOO_PRICY
    end
  elseif entry.repeatable then
    label = entry.name .. "\nx" .. tostring(count)
    color = unlocked and GRID_COLOR_REPEATABLE or GRID_COLOR_LOCKED
  else
    label = entry.name
    color = unlocked and GRID_COLOR_OWNED or GRID_COLOR_LOCKED
  end

  -- Brands are purchase-only — never show the equipped colour for them.
  if tab ~= "brands" and isBuffEquipped(entry.name or entry.id) then
    color = GRID_COLOR_EQUIPPED
  end

  return { label = label, color = color, tooltip = entry.desc and tostring(entry.desc) or nil }
end

function drawEssenceGrid()
  local entries  = sortedCategoryEntries(essenceTab)
  local startIdx = (essencePage - 1) * PAGE_SIZE
  local xs = {-1.5, 0, 1.5}
  local zs = {-0.25, 0.25}
  for slot = 1, PAGE_SIZE do
    local row  = math.ceil(slot / 3)
    local col  = ((slot - 1) % 3) + 1
    local cell = renderGridCell(entries[startIdx + slot], essenceTab)
    trackButton({
      click_function = "click_essenceSlot_" .. slot,
      label   = cell.label,
      tooltip = cell.tooltip,
      position = {xs[col], 0.1, zs[row]},
      width = 680, height = 210, font_size = 34,
      color = cell.color, font_color = {1, 1, 1},
    })
  end
end

function essenceSlotEntry(slot)
  local entries = sortedCategoryEntries(essenceTab)
  return entries[(essencePage - 1) * PAGE_SIZE + slot]
end

function previewEssenceSlot(slot, playerColor, altClick)
  local entry = essenceSlotEntry(slot)
  if not entry then return end
  local name  = entry.name or entry.id
  local count = ess_getItemCount(entry)

  if altClick then
    -- Brands are not equippable; alt-click goes straight to admin refund or is a no-op.
    if essenceTab == "brands" then
      if adminMode then adminRemoveItem(entry) end
      return
    end
    -- Unequip beats admin-remove and sell, so equipped items can always be freed.
    local equippedIdx = isBuffEquipped(name)
    if equippedIdx then
      unequipSlot(equippedIdx)
      showEssenceScreen()
      return
    end
    if adminMode then
      adminRemoveItem(entry)
      return
    end
    if essenceTab == "crypt" and count > 0 then
      showSellCryptConfirm(entry)
      return
    end
    return
  end

  if adminMode and count == 0 then
    adminGrantItem(entry)
    return
  end

  if essenceTab == "brands" then
    -- Brands are purchase-only; clicking always opens the buy/upgrade confirm screen.
    showPurchaseConfirm(entry, "brands")
    return
  end

  if essenceTab == "tickets" then
    if count > 0 then
      local idx = isBuffEquipped(name)
      if idx then unequipSlot(idx) else equipBuff(entry, "tickets") end
      showEssenceScreen()
    else
      showPurchaseConfirm(entry, "tickets")
    end
    return
  end

  if count > 0 then
    local idx = isBuffEquipped(name)
    if idx then
      unequipSlot(idx)
    else
      equipBuff(entry, essenceTab)
    end
    showEssenceScreen()
    return
  end

  broadcastToAll("[" .. self.getName() .. "] " .. name .. " (locked)\n" .. tostring(entry.desc or ""),
    {0.85, 0.75, 0.95})
end

function adminGrantItem(entry)
  if not entry then return end
  if essenceTab == "captures" then
    broadcastToAll("[" .. self.getName() .. "] [Admin] Captures must be added via the Add Capture flow.", {0.9, 0.7, 0.3})
    return
  end
  local id   = ess_toId(entry.name or entry.id or "")
  local item = essenceState[essenceTab] and essenceState[essenceTab][id]
  if not item then return end
  local newCount = ess_incrementItemUnlock(item)
  broadcastToAll("[" .. self.getName() .. "] [Admin] Granted: " .. (entry.name or "?")
    .. (newCount > 1 and (" (x" .. newCount .. ")") or ""), {0.5, 1, 0.5})
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  showEssenceScreen()
end

function adminRemoveItem(entry)
  if not entry then return end
  if essenceTab == "brands" then
    refundBrand(entry)
    return
  elseif essenceTab == "tickets" then
    refundTicket(entry)
    return
  end
  if essenceTab == "crypt" or essenceTab == "achievements" then
    local id   = ess_toId(entry.name or entry.id or "")
    local item = essenceState[essenceTab] and essenceState[essenceTab][id]
    local cnt  = item and ess_getItemCount(item) or 0
    if cnt <= 0 then
      broadcastToAll("[" .. self.getName() .. "] [Admin] " .. (entry.name or "?") .. " — not unlocked.", {0.9, 0.5, 0.2})
      return
    end
    local equippedIdx = isBuffEquipped(entry.name or entry.id)
    if equippedIdx then unequipSlot(equippedIdx) end
    ess_decrementItemUnlock(item)
    broadcastToAll("[" .. self.getName() .. "] [Admin] Removed: " .. (entry.name or "?"), {1, 0.85, 0.5})
    requestSync(DEBOUNCE_SECONDS)
    notifyMasters()
    showEssenceScreen()
    return
  end
  -- Captures: nil out the entry and refund the price it would have cost at N captures.
  if essenceTab == "captures" then
    local id          = ess_toId(entry.name or entry.id or "")
    local captureList = essenceState.captures or {}
    if not captureList[id] then
      broadcastToAll("[" .. self.getName() .. "] [Admin] Capture not found.", {0.9, 0.5, 0.2})
      return
    end
    local equippedIdx = isBuffEquipped(entry.name or entry.id)
    if equippedIdx then unequipSlot(equippedIdx) end
    local refund = math.max(0, CAPTURE_BASE_COST + (getCaptureCount() - 1) * CAPTURE_PRICE_STEP)
    captureList[id] = nil
    applyEssenceDeltaTracked(refund, "[Admin] Remove Capture: " .. (entry.name or "?"))
    broadcastToAll("[" .. self.getName() .. "] [Admin] Removed capture: " .. (entry.name or "?")
      .. "  +" .. tostring(refund) .. " Essence", {1, 0.85, 0.5})
    requestSync(DEBOUNCE_SECONDS)
    notifyMasters()
    showEssenceScreen()
    return
  end
end

for i = 1, 6 do
  _G["click_essenceSlot_" .. i] = function(_, c, a) previewEssenceSlot(i, c, a) end
end

-- 4 slots left-aligned to leave room for the Add Capture button on the right.
function drawEquippedSection()
  local xs = {-1.8, -1.0, -0.2, 0.6}
  trackButton({
    click_function = "click_equippedHeader", function_owner = self,
    label = "Equipped Buffs",
    position = {-0.6, 0.1, 0.58},
    width = 900, height = 120, font_size = 60,
    color = {0.15, 0.12, 0.22}, font_color = {0.8, 0.7, 1},
    tooltip = "Click to spawn all equipped buff cards",
  })
  local display = buildEquippedDisplay()
  for i = 1, MAX_EQUIPPED do
    local d = display[i]
    local label = d and d.name or "—  empty  —"
    local col   = d and {0.45, 0.3, 0.6} or {0.15, 0.15, 0.2}
    trackButton({
      click_function = "click_equippedSlot_" .. i, function_owner = self,
      label    = label,
      tooltip  = d and "Left/right-click to unequip" or nil,
      position = {xs[i], 0.1, 0.88},
      width = 340, height = 155, font_size = 32,
      color = col, font_color = {1, 1, 1},
    })
  end
end

-- Returns a flat [1..4] visual-slot array; multi-slot items fill consecutive entries.
-- Each entry: {name, category, realIdx} pointing back to equippedBuffs index.
function buildEquippedDisplay()
  local display = {}
  local vslot = 1
  for i = 1, MAX_EQUIPPED do
    local b = equippedBuffs[i]
    if b and vslot <= MAX_EQUIPPED then
      local cost = getBuffSlotCost(b.name)
      for _ = 1, cost do
        if vslot <= MAX_EQUIPPED then
          display[vslot] = {name = b.name, category = b.category, realIdx = i}
          vslot = vslot + 1
        end
      end
    end
  end
  return display
end

function click_equippedHeader()
  local count = 0
  for i = 1, MAX_EQUIPPED do
    local b = equippedBuffs[i]
    if b then
      if b.category == "captures" then
        local captureItem = (essenceState.captures or {})[ess_toId(b.name)]
        if captureItem then
          spawnCaptureToken(captureItem)
        else
          broadcastToAll("[" .. self.getName() .. "] Capture '" .. b.name .. "' not found — re-add it.", {0.9, 0.5, 0.2})
        end
      else
        spawnRewardToken(b.name)
      end
      count = count + 1
    end
  end
  if count == 0 then
    broadcastToAll("[" .. self.getName() .. "] No buffs are currently equipped.", {0.9, 0.8, 0.4})
  end
end

local function unequipVisualSlot(vslot)
  local d = buildEquippedDisplay()[vslot]
  if d then unequipSlot(d.realIdx) end
  showEssenceScreen()
end
function click_equippedSlot_1(_, _, _) unequipVisualSlot(1) end
function click_equippedSlot_2(_, _, _) unequipVisualSlot(2) end
function click_equippedSlot_3(_, _, _) unequipVisualSlot(3) end
function click_equippedSlot_4(_, _, _) unequipVisualSlot(4) end

-- Pagination shares the Back-button row at z=1.3. Back is at x=-1.6 (right edge ≈ -1.18);
-- pagination starts at x≈-0.1 and stays within the card edge at x≈2.2.
function drawEssencePagination()
  local pages = essencePageCount(essenceTab)
  trackButton({
    click_function = "click_essencePrev", function_owner = self,
    label = "< Prev",
    position = {-0.1, 0.1, 1.3},
    width = 320, height = 200, font_size = 60,
    color = (essencePage > 1) and {0.3, 0.3, 0.3} or {0.15, 0.15, 0.15},
    font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Page " .. tostring(essencePage) .. " / " .. tostring(pages),
    position = {0.9, 0.1, 1.3},
    width = 460, height = 200, font_size = 60,
    color = {0.18, 0.18, 0.28}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "click_essenceNext", function_owner = self,
    label = "Next >",
    position = {1.8, 0.1, 1.3},
    width = 320, height = 200, font_size = 60,
    color = (essencePage < pages) and {0.3, 0.3, 0.3} or {0.15, 0.15, 0.15},
    font_color = {1, 1, 1},
  })
end

function click_essencePrev()
  if essencePage > 1 then essencePage = essencePage - 1 end
  showEssenceScreen()
end

function click_essenceNext()
  local pages = essencePageCount(essenceTab)
  if essencePage < pages then essencePage = essencePage + 1 end
  showEssenceScreen()
end

function click_addCapture()
  if not localPlayerKey then
    broadcastToAll("[" .. self.getName() .. "] Pick up the card first to claim it before purchasing captures.",
      {0.95, 0.75, 0.3})
    return
  end
  local price = getCapturePrice()
  if essence < price then
    broadcastToAll("[" .. self.getName() .. "] Not enough Essence — need " .. price
      .. " (have " .. tostring(essence) .. ").", {0.9, 0.3, 0.3})
    return
  end
  showCapturePromptScreen()
end

function showCapturePromptScreen()
  local price = getCapturePrice()
  openScreen("capture_prompt", "capture_cancel", "Add Capture")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Drop the Capture card\nonto this card to save it.",
    position = {0, 0.1, -0.2},
    width = 1800, height = 320, font_size = 80,
    color = {0.18, 0.18, 0.28}, font_color = {1, 1, 1},
  })
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Cost: " .. tostring(price) .. " Essence",
    position = {0, 0.1, 0.5},
    width = 900, height = 200, font_size = 85,
    color = {0.35, 0.2, 0.5}, font_color = {1, 1, 1},
  })
end

function click_captureCancel()
  essenceTab = "captures"
  showEssenceScreen()
end

function click_essShopBack()
  essenceTab = "captures"
  showEssenceScreen()
end

function buildCapturePayloadFromObjectData(data, fallbackName, fallbackUrl)
  if type(data) ~= "table" then return nil, fallbackUrl or "" end

  local payload = ess_sanitizeCaptureBagData(data)
  local faceUrl = extractCaptureFaceUrlFromPayload(payload)
  if faceUrl == "" then faceUrl = fallbackUrl or "" end
  if payload and payload._schema == "capture_payload_v2" and faceUrl ~= "" and (not payload.bagDiffuseURL or payload.bagDiffuseURL == "") then
    payload.bagDiffuseURL = faceUrl
  end
  return payload, faceUrl
end

function commitCapturePurchase(obj, name, captureUrl, bagData)
  if captureUrl == "" then
    pcall(function()
      local co = obj.getCustomObject()
      if co and co.diffuse and co.diffuse ~= "" then captureUrl = co.diffuse end
    end)
  end

  local price = getCapturePrice()
  if essence < price then
    broadcastToAll("[" .. self.getName() .. "] Not enough Essence! Need " .. price
      .. " (have " .. tostring(essence) .. ").", {0.9, 0.3, 0.3})
    essenceTab = "captures"
    showEssenceScreen()
    return
  end

  applyEssenceDeltaTracked(-price, "Capture: " .. name)

  local id = ess_toId(name)
  essenceState.captures[id] = essenceState.captures[id] or {
    id = id, name = name, unlocked = true, count = 0,
    url = captureUrl,
    desc = "Capture ticket for " .. name .. ".",
    unlock_time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
  }
  if captureUrl ~= "" and (essenceState.captures[id].url or "") == "" then
    essenceState.captures[id].url = captureUrl
  end
  if bagData then
    essenceState.captures[id].bagData = bagData
  end
  essenceState.captures[id].count = (essenceState.captures[id].count or 0) + 1
  essenceState.captures[id].unlocked = true
  essenceState.captures[id].last_unlock_time = os.date("!%Y-%m-%dT%H:%M:%SZ")

  ess_safeDestructObject(obj)

  local modeText = bagData and " as Infinite Bag" or ""
  broadcastToAll("[" .. self.getName() .. "] Captured: " .. name .. modeText
    .. "  (-" .. tostring(price) .. " Essence)", {0.7, 0.9, 0.7})

  essenceTab = "captures"
  requestSync(DEBOUNCE_SECONDS)
  notifyMasters()
  showEssenceScreen()
end

function finalizeCapturePurchase(obj, name, captureUrl)
  -- We defer here because obj.getData() on an Infinite Bag during the drop event
  -- can return only the bag shell. If that happens, consume one object from the
  -- Infinite Bag and serialize the actual contained card instead.
  local bagData = nil
  local data = nil
  local okData = pcall(function() data = obj.getData() end)
  if okData and type(data) == "table" then
    bagData, captureUrl = buildCapturePayloadFromObjectData(data, name, captureUrl)
  end

  local objName = ""
  if type(data) == "table" then objName = tostring(data.Name or "") end

  if not bagData and objName == "Custom_Model_Infinite_Bag" then
    local takePos = self.positionToWorld({0, 2.5, 0})
    local okTake = pcall(function()
      obj.takeObject({
        position = takePos,
        smooth = false,
        callback_function = function(cardObj)
          Wait.frames(function()
            local cardBagData = nil
            local cardUrl = captureUrl or ""
            local cardData = nil
            local okCardData = pcall(function() cardData = cardObj.getData() end)
            if okCardData and type(cardData) == "table" then
              cardBagData, cardUrl = buildCapturePayloadFromObjectData(cardData, name, cardUrl)
            end
            if cardUrl == "" then
              pcall(function()
                local co = cardObj.getCustomObject()
                if co and co.face and co.face ~= "" then cardUrl = co.face end
                if co and co.diffuse and co.diffuse ~= "" then cardUrl = co.diffuse end
              end)
            end
            ess_safeDestructObject(cardObj)
            commitCapturePurchase(obj, name, cardUrl, cardBagData)
          end, 2)
        end,
      })
    end)
    if okTake then return end
  end

  commitCapturePurchase(obj, name, captureUrl, bagData)
end

function handleCapturePurchase(obj)
  if not obj or obj == self then return end

  -- Guard against rapid double-drops landing after the screen has already changed.
  if currentScreen ~= "capture_prompt" then return end

  local rawDisplayName = ""
  pcall(function() rawDisplayName = obj.getName() or "" end)

  local name       = ""
  local captureUrl = ""

  pcall(function()
    local notes = obj.getGMNotes() or ""
    local lines = {}
    for line in (notes .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    if #lines >= 1 and ess_trim(lines[1]) == CAPTURE_NOTE_PREFIX then
      if #lines >= 2 then name       = ess_trim(lines[2]) end
      if #lines >= 3 then captureUrl = ess_trim(lines[3]) end
    end
  end)

  if name == "" then
    name = ess_parseCaptureTicketName(rawDisplayName) or ""
  end

  if name == "" then
    broadcastToAll("[" .. self.getName() .. "] That is not a Capture Ticket — drop a token whose name starts with \"" .. CAPTURE_TICKET_LABEL .. "\".", {0.9, 0.3, 0.3})
    return
  end

  currentScreen = "capture_processing"
  openScreen("capture_processing", nil, "Add Capture")
  trackButton({
    click_function = "xp_noop", function_owner = self,
    label = "Capturing ticket...",
    position = {0, 0.1, 0.0},
    width = 1600, height = 260, font_size = 90,
    color = {0.18, 0.18, 0.28}, font_color = {1, 1, 1},
  })

  Wait.frames(function()
    finalizeCapturePurchase(obj, name, captureUrl)
  end, 3)
end

function onCollisionEnter(info)
  local obj = info and info.collision_object
  if not obj then return end
  if obj == self then return end
  local name = ""
  pcall(function() name = obj.getName() or "" end)
  if name == "" then return end
  if isKnownReward(name) then handleRewardDrop(obj) end
end

function onObjectDropped(player_color, dropped_object)
  if not dropped_object or dropped_object == self then return end
  local okPos, pos = pcall(function() return dropped_object.getPosition() end)
  if not okPos or type(pos) ~= "table" then return end
  local my = self.getPosition()
  local dx = pos.x - my.x
  local dz = pos.z - my.z
  if (dx*dx + dz*dz) > (1.6 * 1.6) then return end

  if currentScreen == "upgrade_input" or currentScreen == "augment_input" then
    handleTownCardDrop(dropped_object, currentScreen:gsub("_input", ""))
    return
  end

  if currentScreen == "capture_prompt" then
    handleCapturePurchase(dropped_object)
    return
  end

  if currentScreen == "mystic_prompt" then
    handleMysticDrop(dropped_object)
    return
  end

  if currentScreen == "bazaar_cashout_prompt" then
    handleBazaarCashOutDrop(dropped_object)
    return
  end

  if currentScreen == "bazaar_cmc_prompt" then
    handleBazaarSellCMCDrop(dropped_object)
    return
  end

  if currentScreen == "sell_confirm" then
    handleSellModeDrop(dropped_object)
    return
  end

  if currentScreen == "end_session_deck" then
    handleEndSessionDeck(dropped_object)
    return
  end

  if currentScreen == "redeem_cashout_prompt" then
    handleRedeemCashoutDrop(dropped_object)
    return
  end

  local name = ""
  pcall(function() name = dropped_object.getName() or "" end)
  if name == "" then return end
  if isKnownReward(name) then handleRewardDrop(dropped_object) end
end

--==============================================================================
-- REWARD TOKEN SPAWNING (ported from Doomblade)
--==============================================================================

SPAWN_BUTTON_LOCAL = Vector{2, 0.2, 0}
SPAWN_HEIGHT_OFFSET = 2
SPAWN_LINE_SPACING = 1.35
SPAWN_LINE_RESET_SECONDS = 3
SPAWN_ABOVE_OFFSET = 2.5
SPAWN_UPRIGHT_FLIP = 0

rewardSpawnLineIndex = 0
rewardSpawnLineLastAt = 0

captureSpawnLineIndex = 0
captureSpawnLineLastAt = 0

lastAnchorPos = nil
lastAnchorRot = nil
lastAnchorWorld = nil

function getSpawnAnchor()
    local pos = self.getPosition()
    local rot = self.getRotation()

    local moved = (not lastAnchorPos) or math.abs(pos.x - lastAnchorPos.x) > 0.001 or math.abs(pos.y - lastAnchorPos.y) > 0.001 or math.abs(pos.z - lastAnchorPos.z) > 0.001
    local rotated = (not lastAnchorRot) or math.abs(rot.x - lastAnchorRot.x) > 0.001 or math.abs(rot.y - lastAnchorRot.y) > 0.001 or math.abs(rot.z - lastAnchorRot.z) > 0.001

    if moved or rotated or not lastAnchorWorld then
      local anchorLocal = Vector{SPAWN_BUTTON_LOCAL.x - 0.5, SPAWN_BUTTON_LOCAL.y + SPAWN_HEIGHT_OFFSET, SPAWN_BUTTON_LOCAL.z - SPAWN_ABOVE_OFFSET}
        lastAnchorWorld = self.positionToWorld(anchorLocal)
        lastAnchorPos = pos
        lastAnchorRot = rot
    end
    return lastAnchorWorld
end

  local function getLineSpawnAnchor(statePrefix)
    local now = os.time()
    local indexKey = statePrefix .. "SpawnLineIndex"
    local lastAtKey = statePrefix .. "SpawnLineLastAt"

    if _G[lastAtKey] == nil or (now - (_G[lastAtKey] or 0)) > SPAWN_LINE_RESET_SECONDS then
      _G[indexKey] = 0
    end

    local slot = _G[indexKey] or 0
    _G[indexKey] = slot + 1
    _G[lastAtKey] = now

    local localOffset = Vector{
      SPAWN_BUTTON_LOCAL.x - (slot * SPAWN_LINE_SPACING),
      SPAWN_BUTTON_LOCAL.y + SPAWN_HEIGHT_OFFSET,
      SPAWN_BUTTON_LOCAL.z - SPAWN_ABOVE_OFFSET,
    }

    return self.positionToWorld(localOffset)
  end

MESH_URL = "https://steamusercontent-a.akamaihd.net/ugc/1327949700692125593/FFAF751A7D6392C0A1C2A94727C7DA513B5F5960/"

BASE_SPAWN_TEMPLATE = {
    Name = "Custom_Model",
    Transform = {
        posX = 0, posY = 1, posZ = 0,
        rotX = 0, rotY = 0, rotZ = 0,
        scaleX = 0.7, scaleY = 0.7, scaleZ = 0.7,
    },
    Nickname = "", Description = "", GMNotes = "",
    ColorDiffuse = { r = 1, g = 1, b = 1 },
    Locked = false, Grid = false, Snap = false, Autoraise = true,
    Sticky = false, Tooltip = true, Hands = false, MaterialIndex = -1,
    MeshURL = MESH_URL,
    Rigidbody = { Mass = 0.5, Drag = 0.1, AngularDrag = 0.1, UseGravity = true, Freeze = false },
    CustomMesh = {
        MeshURL = MESH_URL, DiffuseURL = "", ColliderURL = MESH_URL,
        Convex = true, MaterialIndex = 3, TypeIndex = 1,
        CustomShader = { SpecularColor = { r=0, g=0, b=0 }, SpecularIntensity=0, SpecularSharpness=2, FresnelStrength=0 },
        CastShadows = true,
    },
}

CAPTURE_DEFAULT_BACK_URL = "https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/"

CAPTURE_BAG_TEMPLATE = {
    GUID = "", Name = "Custom_Model_Infinite_Bag",
    Transform = {
        posX = 0, posY = 0, posZ = 0, rotX = 0, rotY = 0, rotZ = 0,
        scaleX = 0.7, scaleY = 0.7, scaleZ = 0.7,
    },
    Nickname = "", Description = "", GMNotes = "",
    AltLookAngle = { x = 0, y = 0, z = 0 },
    ColorDiffuse = { r = 1, g = 1, b = 1 },
    LayoutGroupSortIndex = 0, Value = 0, Locked = false,
    Grid = true, Snap = false, IgnoreFoW = false, MeasureMovement = false,
    DragSelectable = true, Autoraise = true, Sticky = true, Tooltip = true,
    GridProjection = false, HideWhenFaceDown = false, Hands = false,
    MaterialIndex = -1, MeshIndex = -1,
    CustomMesh = {
        MeshURL = MESH_URL, DiffuseURL = "", NormalURL = "", ColliderURL = MESH_URL,
        Convex = true, MaterialIndex = 1, TypeIndex = 7,
        CustomShader = { SpecularColor = { r=224, g=208, b=191 }, SpecularIntensity=0, SpecularSharpness=2, FresnelStrength=0.107142858 },
        CastShadows = true,
    },
    LuaScript = "", LuaScriptState = "", XmlUI = "", ContainedObjects = {},
}

CAPTURE_CARD_TEMPLATE = {
    GUID = "", Name = "Card",
    Transform = { posX=0, posY=0, posZ=0, rotX=0, rotY=0, rotZ=0, scaleX=1, scaleY=1, scaleZ=1 },
    Nickname = "", Description = "", GMNotes = "", Memo = "",
    AltLookAngle = { x = 0, y = 0, z = 0 },
    ColorDiffuse = { r = 0.713235259, g = 0.713235259, b = 0.713235259 },
    LayoutGroupSortIndex = 0, Value = 0, Locked = false,
    Grid = true, Snap = true, IgnoreFoW = false, MeasureMovement = false,
    DragSelectable = true, Autoraise = true, Sticky = true, Tooltip = true,
    GridProjection = false, HideWhenFaceDown = true, Hands = true,
    CardID = 100, SidewaysCard = false,
    LuaScript = "", LuaScriptState = "", XmlUI = "", CustomDeck = {},
}

TREASURE_PIRATE_BAG_TEMPLATE = {
    Name = "Custom_Model_Infinite_Bag",
    Transform = { posX=0, posY=0, posZ=0, rotX=0, rotY=0, rotZ=0, scaleX=0.7, scaleY=0.7, scaleZ=0.7 },
    Nickname = "Treasure Pirate",
    Description = "At the beginning of every encounter, start with a Treasure token.\nUnlock: Beat Olivia, Opulent Outlaw.",
    GMNotes = "",
    AltLookAngle = { x = 0, y = 0, z = 0 },
    ColorDiffuse = { r = 1, g = 1, b = 1 },
    LayoutGroupSortIndex = 0, Value = 0, Locked = false,
    Grid = false, Snap = false, IgnoreFoW = false, MeasureMovement = false,
    DragSelectable = true, Autoraise = true, Sticky = false, Tooltip = true,
    GridProjection = false, HideWhenFaceDown = false, Hands = false,
    MaterialIndex = -1, MeshIndex = -1,
    CustomMesh = {
        MeshURL = MESH_URL,
        DiffuseURL = "https://api.mtginfo.org/image-proxy/normal/front/8/6/861b5889-0183-4bee-afeb-a4b2aa700a8e.jpg",
        NormalURL = "", ColliderURL = MESH_URL,
        Convex = true, MaterialIndex = 3, TypeIndex = 7,
        CustomShader = { SpecularColor = { r=0, g=0, b=0 }, SpecularIntensity=0, SpecularSharpness=2, FresnelStrength=0 },
        CastShadows = true,
    },
    LuaScript = "", LuaScriptState = "", XmlUI = "",
    Rigidbody = { Mass = 0.5, Drag = 0.1, AngularDrag = 0.1, UseGravity = true },
    ContainedObjects = {
        {
            Name = "Card",
            Transform = { posX=0, posY=0, posZ=0, rotX=0, rotY=0, rotZ=0, scaleX=1, scaleY=1, scaleZ=1 },
            Nickname = "Treasure\nToken Artifact - Treasure\n0CMC",
            Description = "{T}, Sacrifice this token: Add one mana of any color.",
            GMNotes = "", Memo = "3c549374-6c37-42e0-8d88-a8555d46732d",
            AltLookAngle = { x = 0, y = 0, z = 0 },
            ColorDiffuse = { r = 0.713235259, g = 0.713235259, b = 0.713235259 },
            LayoutGroupSortIndex = 0, Value = 0, Locked = false,
            Grid = true, Snap = true, IgnoreFoW = false, MeasureMovement = false,
            DragSelectable = true, Autoraise = true, Sticky = true, Tooltip = true,
            GridProjection = false, HideWhenFaceDown = true, Hands = true,
            CardID = 7400, SidewaysCard = false,
            LuaScript = "", LuaScriptState = "", XmlUI = "",
            CustomDeck = {
                ["74"] = {
                    FaceURL = "https://api.mtginfo.org/image-proxy/normal/front/b/2/b29d7556-9051-4451-812e-91513ef10e62.jpg",
                    BackURL = CAPTURE_DEFAULT_BACK_URL,
                    NumWidth = 1, NumHeight = 1,
                    BackIsHidden = true, UniqueBack = false, Type = 0,
                }
            }
        }
    }
}

SOL_RING_TICKET_BAG_TEMPLATE = {
    Name = "Custom_Model_Infinite_Bag",
    Transform = { posX=0, posY=0, posZ=0, rotX=0, rotY=0, rotZ=0, scaleX=0.7, scaleY=0.7, scaleZ=0.7 },
    Nickname = "Sol Ring Ticket",
    Description = "You get a Sol Ring Ticket. This allows you to have a free Sol Ring in your deck without it counting towards your 39.",
    GMNotes = "",
    AltLookAngle = { x = 0, y = 0, z = 0 },
    ColorDiffuse = { r = 1, g = 1, b = 1 },
    LayoutGroupSortIndex = 0, Value = 0, Locked = false,
    Grid = false, Snap = false, IgnoreFoW = false, MeasureMovement = false,
    DragSelectable = true, Autoraise = true, Sticky = false, Tooltip = true,
    GridProjection = false, HideWhenFaceDown = false, Hands = false,
    MaterialIndex = -1, MeshIndex = -1,
    CustomMesh = {
        MeshURL = MESH_URL,
        DiffuseURL = "https://api.mtginfo.org/image-proxy/normal/front/8/5/858e0b83-7927-4e34-ae25-6ad7a787ad97.jpg",
        NormalURL = "", ColliderURL = MESH_URL,
        Convex = true, MaterialIndex = 3, TypeIndex = 7,
        CustomShader = { SpecularColor = { r=0, g=0, b=0 }, SpecularIntensity=0, SpecularSharpness=2, FresnelStrength=0 },
        CastShadows = true,
    },
    LuaScript = "", LuaScriptState = "", XmlUI = "",
    Rigidbody = { Mass = 0.5, Drag = 0.1, AngularDrag = 0.1, UseGravity = true },
    ContainedObjects = {
        {
            Name = "Card",
            Transform = { posX=0, posY=0, posZ=0, rotX=0, rotY=0, rotZ=0, scaleX=1, scaleY=1, scaleZ=1 },
            Nickname = "Sol Ring\nArtifact\n1CMC",
            Description = "{T}: Add {C}{C}.",
            GMNotes = "", Memo = "6ad8011d-3471-4369-9d68-b264cc027487",
            AltLookAngle = { x = 0, y = 0, z = 0 },
            ColorDiffuse = { r = 0.713235259, g = 0.713235259, b = 0.713235259 },
            LayoutGroupSortIndex = 0, Value = 0, Locked = false,
            Grid = true, Snap = true, IgnoreFoW = false, MeasureMovement = false,
            DragSelectable = true, Autoraise = true, Sticky = true, Tooltip = true,
            GridProjection = false, HideWhenFaceDown = true, Hands = true,
            CardID = 55854500, SidewaysCard = false,
            LuaScript = "", LuaScriptState = "", XmlUI = "",
            CustomDeck = {
                ["558545"] = {
                    FaceURL = "https://api.mtginfo.org/image-proxy/normal/front/8/5/858e0b83-7927-4e34-ae25-6ad7a787ad97.jpg",
                    BackURL = CAPTURE_DEFAULT_BACK_URL,
                    NumWidth = 1, NumHeight = 1,
                    BackIsHidden = true, UniqueBack = false, Type = 0,
                }
            }
        }
    }
}

ARCANE_SIGNET_TICKET_BAG_TEMPLATE = {
    Name = "Custom_Model_Infinite_Bag",
    Transform = { posX=0, posY=0, posZ=0, rotX=0, rotY=0, rotZ=0, scaleX=0.7, scaleY=0.7, scaleZ=0.7 },
    Nickname = "Arcane Signet Ticket",
    Description = "You get a Arcane Signet Ticket. This allows you to have a free Arcane Signet in your deck without it counting towards your 39.",
    GMNotes = "",
    AltLookAngle = { x = 0, y = 0, z = 0 },
    ColorDiffuse = { r = 1, g = 1, b = 1 },
    LayoutGroupSortIndex = 0, Value = 0, Locked = false,
    Grid = false, Snap = false, IgnoreFoW = false, MeasureMovement = false,
    DragSelectable = true, Autoraise = true, Sticky = false, Tooltip = true,
    GridProjection = false, HideWhenFaceDown = false, Hands = false,
    MaterialIndex = -1, MeshIndex = -1,
    CustomMesh = {
        MeshURL = MESH_URL,
        DiffuseURL = "https://api.mtginfo.org/image-proxy/normal/front/1/f/1fc6b109-4657-4e9e-82f3-53ddd56aef1c.jpg",
        NormalURL = "", ColliderURL = MESH_URL,
        Convex = true, MaterialIndex = 3, TypeIndex = 7,
        CustomShader = { SpecularColor = { r=0, g=0, b=0 }, SpecularIntensity=0, SpecularSharpness=2, FresnelStrength=0 },
        CastShadows = true,
    },
    LuaScript = "", LuaScriptState = "", XmlUI = "",
    Rigidbody = { Mass = 0.5, Drag = 0.1, AngularDrag = 0.1, UseGravity = true },
    ContainedObjects = {
        {
            Name = "Card",
            Transform = { posX=0, posY=0, posZ=0, rotX=0, rotY=0, rotZ=0, scaleX=1, scaleY=1, scaleZ=1 },
            Nickname = "Arcane Signet\nArtifact\n2CMC",
            Description = "{T}: Add one mana of any color in your commander's color identity.",
            GMNotes = "", Memo = "0bc7f093-bef0-4f1a-852c-4b75ebf54838",
            AltLookAngle = { x = 0, y = 0, z = 0 },
            ColorDiffuse = { r = 0.713235259, g = 0.713235259, b = 0.713235259 },
            LayoutGroupSortIndex = 0, Value = 0, Locked = false,
            Grid = true, Snap = true, IgnoreFoW = false, MeasureMovement = false,
            DragSelectable = true, Autoraise = true, Sticky = true, Tooltip = true,
            GridProjection = false, HideWhenFaceDown = true, Hands = true,
            CardID = 15900, SidewaysCard = false,
            LuaScript = "", LuaScriptState = "", XmlUI = "",
            CustomDeck = {
                ["159"] = {
                    FaceURL = "https://api.mtginfo.org/image-proxy/normal/front/1/f/1fc6b109-4657-4e9e-82f3-53ddd56aef1c.jpg",
                    BackURL = CAPTURE_DEFAULT_BACK_URL,
                    NumWidth = 1, NumHeight = 1,
                    BackIsHidden = true, UniqueBack = false, Type = 0,
                }
            }
        }
    }
}

SPAWN_IMAGES = {
    -- Crypt Buffs
  ["Flame of Progress"] = "https://api.mtginfo.org/image-proxy/normal/front/c/3/c329ff2b-0331-4934-a8df-870dd7bf402b.jpg",
  ["Spiritual Guidance"] = "https://api.mtginfo.org/image-proxy/normal/front/5/0/504a69eb-3c2d-4bb1-b117-252b15acf0c2.jpg",
  ["Fickle Duplicant"] = "https://api.mtginfo.org/image-proxy/normal/front/4/c/4c8f2c0f-7ed8-4d72-8f94-33ad615bf21d.jpg",
  ["Undying Legionary"] = "https://api.mtginfo.org/image-proxy/normal/front/c/1/c160c1f7-714e-444a-ab74-c64c3a099a48.jpg",
  ["Treasure Pirate"] = "https://api.mtginfo.org/image-proxy/normal/front/8/6/861b5889-0183-4bee-afeb-a4b2aa700a8e.jpg",
  ["Finders Keepers"] = "https://api.mtginfo.org/image-proxy/normal/front/f/3/f340cbf7-5bbe-45b9-a4bf-d1caa500ff93.jpg",
  ["Quick Spell"] = "https://api.mtginfo.org/image-proxy/normal/front/6/7/67751745-61c9-488f-b5b3-310c0bafdda7.jpg",
  ["The God Trees Blessing"] = "https://api.mtginfo.org/image-proxy/normal/front/1/7/17315a12-a7f8-45ba-ac3b-a62c789e75d0.jpg",
  ["Respited Gift"] = "https://api.mtginfo.org/image-proxy/normal/front/2/7/275b4c56-e17e-49ec-8946-0e95a4bfa1ae.jpg",
  ["Might of Okaun"] = "https://api.mtginfo.org/image-proxy/normal/front/9/4/94eea6e3-20bc-4dab-90ba-3113c120fb90.jpg",
  ["Shapeshifter"] = "https://api.mtginfo.org/image-proxy/normal/front/d/7/d79f7ecc-c43b-48de-9d90-1085cf2bce5d.jpg",
  ["Unearthly Reach"] = "https://api.mtginfo.org/image-proxy/normal/front/3/c/3caa9c55-5e3b-436b-84a9-b7ccebf63799.jpg",
  ["Momentum Engine"] = "https://api.mtginfo.org/image-proxy/normal/front/6/a/6affd9c6-f7ab-488e-85fa-2a3a48383414.jpg",
  ["Eternal Servitude"] = "https://api.mtginfo.org/image-proxy/normal/front/2/9/29bf245f-e8e0-4d32-8cd7-06d832609910.jpg",
  ["Dark Beginnings"] = "https://api.mtginfo.org/image-proxy/normal/front/b/f/bf4708e8-2149-4990-987c-2ea55fc6c508.jpg",
  ["The Chosen Path"] = "https://api.mtginfo.org/image-proxy/normal/front/e/7/e7b44893-e6d1-48d0-ba69-06b9569e1e38.jpg",
  ["Paragon Adornments"] = "https://api.mtginfo.org/image-proxy/normal/front/2/b/2b432c64-e083-4386-86c1-49d746e7a8ea.jpg",
  ["Lucky Pull"] = "https://api.mtginfo.org/image-proxy/normal/front/4/8/48484d4d-6000-4e7b-87cf-cabfe4e19b0e.jpg",
  ["Upgrades, People, Upgrades"] = "https://api.mtginfo.org/image-proxy/normal/front/6/c/6c6d9ecc-2dd1-471a-8678-a2461b1084fa.jpg",

    -- Achievements
    ["Happy Fun Land"] = "https://api.mtginfo.org/image-proxy/normal/front/c/5/c52057f7-a78a-4edc-8e95-edaea6376e76.jpg",
    ["Nature's Blessing"] = "https://api.mtginfo.org/image-proxy/normal/front/b/e/be72862d-d71e-4b18-98a6-59019399f631.jpg",
    ["Dog's Best Friend"] = "https://api.mtginfo.org/image-proxy/normal/front/1/b/1bd8e61c-2ee8-4243-a848-7008810db8a0.jpg",
    ["Orzhov Identity Buff - Tithe and Toil"] = "https://api.mtginfo.org/image-proxy/normal/front/4/0/4029c3a0-a999-453a-a838-7adb81e481ee.jpg",
    ["Simic Identity Buff - Adaptive Pattern"] = "https://api.mtginfo.org/image-proxy/normal/front/f/6/f6d381eb-6cb6-4505-aebe-995c1ddc8527.jpg",
    ["Azorius Identity Buff - Law of Efficiency"] = "https://api.mtginfo.org/image-proxy/normal/front/3/0/30dc237e-b28a-4b65-9790-6b434828bf2e.jpg",
    ["Boros Identity Buff - Charge of Conviction"] = "https://api.mtginfo.org/image-proxy/normal/front/8/7/87e80447-9572-43a7-8487-3249cd9ce596.jpg",
    ["Changeling's Land Form"] = "https://api.mtginfo.org/image-proxy/normal/front/7/f/7f36775e-9e48-49cc-a771-d58481712edc.jpg",
    ["Golgari Identity Buff - Cycle of Rot"] = "https://api.mtginfo.org/image-proxy/normal/front/c/6/c6717954-35d8-4d7e-95aa-f7d26d15d4b2.jpg",
    ["Izzet Identity Buff - Experimental Sparks"] = "https://api.mtginfo.org/image-proxy/normal/front/0/6/06c9158c-064b-4d12-b860-d2c1450d1897.jpg",
    ["Dimir Identity Buff - Whisper Network"] = "https://api.mtginfo.org/image-proxy/normal/front/d/a/dac8975a-0d41-4538-8e49-a2de5d410b6c.jpg",
    ["Selesnya Identity Buff - Harmony's Bloom"] = "https://api.mtginfo.org/image-proxy/normal/front/3/4/34ea44f2-cb2f-4b86-83fc-fe507f05bb9d.jpg",
    ["Raccoon's Rage"] = "https://steamusercontent-a.akamaihd.net/ugc/9510145195220216105/C4209F043077BD6652279AF682ECAB7F75A505E3/",
    ["Gamblers never quit"] = "https://api.mtginfo.org/image-proxy/normal/front/5/6/567665f3-4227-4f3c-bfbe-4e9576f32b50.jpg",
    ["Stick it To Me"] = "https://api.mtginfo.org/image-proxy/normal/front/f/a/fa0c5716-a222-41a1-88cf-8b4aae87f92b.jpg",
    ["Gruul Identity Buff - Primal Fury"] = "https://api.mtginfo.org/image-proxy/normal/front/7/c/7c4a08e9-06c7-43e9-a855-4f507a35ae8b.jpg",
    ["Chaos"] = "https://api.mtginfo.org/image-proxy/normal/front/7/b/7b09ab3a-344c-42d0-9f71-e8374214cda1.jpg",
    ["Horse's Gallop"] = "https://steamusercontent-a.akamaihd.net/ugc/15336545532534506892/445376E890EA053549AB6A3FB3FD0DB5C729955A/",
    ["Victory lap"] = "https://api.mtginfo.org/image-proxy/normal/front/9/c/9cb27fb1-41b1-49b8-bb3b-2c8a011ae7a9.jpg",
    ["Dawn of Crabs"] = "https://steamusercontent-a.akamaihd.net/ugc/9481460801084540271/81770BACB89B63B59E1CD958E2458588805FC83D/",
    ["Rakdos Identity Buff - Showstopper's Encore"] = "https://api.mtginfo.org/image-proxy/normal/front/c/c/cc6fd2d5-8eb2-4265-a1bf-d4ae635285af.jpg",
    ["One with death"] = "https://api.mtginfo.org/image-proxy/normal/front/e/b/eb9963e0-a22a-4a64-aa0c-b7c67c5fee96.jpg",
    ["Compelling Madness"] = "https://api.mtginfo.org/image-proxy/normal/front/7/7/772306d4-63d1-4d90-8c1b-4e4d6edb9aab.jpg",
    ["Fish Pond"] = "https://api.mtginfo.org/image-proxy/normal/front/1/a/1a056620-f9a3-4643-bf4a-1b7cfe2fcb63.jpg",
    ["Construct's Salvation"] = "https://api.mtginfo.org/image-proxy/normal/front/0/f/0f93e8ad-8ef6-4cf1-a664-d1477f1ebae4.jpg",
    ["Scorpion's Nest"] = "https://steamusercontent-a.akamaihd.net/ugc/13833641350492110911/A0EA0189C890735A0A44F612BA4731B72D45CFAB/",

    -- Tickets
    ["Vanguard Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/8/f/8fb54be2-b9c5-4433-a198-4b935979718a.jpg",
    ["Color Combo Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/8/4/84238335-e08c-421c-b9b9-70a679ff2967.jpg",
    ["Emblem Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/3/2/327ddaaf-b6a7-4c80-9b38-5ab68181b3d6.jpg",
    ["Arcane Signet Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/1/f/1fc6b109-4657-4e9e-82f3-53ddd56aef1c.jpg",
    ["Sol Ring Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/8/5/858e0b83-7927-4e34-ae25-6ad7a787ad97.jpg",
    ["Conspiracy Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/1/6/167c6740-0625-4987-8fac-516aab564ca1.jpg",
    ["Trinket Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/a/5/a53baf25-1782-427b-a9dd-fc9b8dc6444f.jpg",
    ["Leyline Ticket"] = "https://api.mtginfo.org/image-proxy/normal/front/b/6/b6dc1f5a-a6cc-4ab4-8bb9-e216e24ca735.jpg",
}

-- Brands are intentionally omitted: they're never dropped as reward tokens,
-- only purchased via the Essence shop, so they shouldn't pick up a desc here.
function findRewardDescByName(reward_name)
    for _, list in ipairs({CRYPT_REWARDS, ACHIEVEMENTS_LIST, TICKETS_LIST}) do
        for _, entry in ipairs(list) do
            if entry.name == reward_name then return entry.desc end
        end
    end
    return nil
end

function getFirstCustomDeckInfo(customDeck)
    if type(customDeck) ~= "table" then return nil end
    local slots = {}
    for slotKey, deck in pairs(customDeck) do
        if type(deck) == "table" then
            local deckSlot = tonumber(slotKey)
            if deckSlot and deckSlot >= 1 then
                deckSlot = math.floor(deckSlot)
                slots[#slots + 1] = { slot = deckSlot, deck = deck }
            end
        end
    end

    table.sort(slots, function(a, b) return a.slot < b.slot end)
    if #slots > 0 then
        local deckSlot = slots[1].slot
        local deck = slots[1].deck
        return {
            deckSlot = deckSlot,
            deckKey = tostring(deckSlot),
            faceURL = tostring(deck.FaceURL or ""),
            backURL = tostring(deck.BackURL or ""),
            numWidth = tonumber(deck.NumWidth) or 1,
            numHeight = tonumber(deck.NumHeight) or 1,
            backIsHidden = (deck.BackIsHidden ~= false),
            uniqueBack = (deck.UniqueBack == true),
            deckType = tonumber(deck.Type) or 0,
        }
    end

    for _, deck in pairs(customDeck) do
        if type(deck) == "table" then
            return {
                deckSlot = 1,
                deckKey = "1",
                faceURL = tostring(deck.FaceURL or ""),
                backURL = tostring(deck.BackURL or ""),
                numWidth = tonumber(deck.NumWidth) or 1,
                numHeight = tonumber(deck.NumHeight) or 1,
                backIsHidden = (deck.BackIsHidden ~= false),
                uniqueBack = (deck.UniqueBack == true),
                deckType = tonumber(deck.Type) or 0,
            }
        end
    end
    return nil
end

function normalizeContainedObjectsList(contained)
    local out = {}
    if type(contained) ~= "table" then return out end
    local seen = {}
    for _, obj in ipairs(contained) do
        if type(obj) == "table" then
            out[#out + 1] = obj
            seen[obj] = true
        end
    end
    local keyed = {}
    for key, obj in pairs(contained) do
        if type(obj) == "table" then
            local index = tonumber(key)
            if index and index >= 1 then
                keyed[#keyed + 1] = { index = index, obj = obj }
            end
        end
    end
    table.sort(keyed, function(a, b) return a.index < b.index end)
    for _, entry in ipairs(keyed) do
        if not seen[entry.obj] then
            out[#out + 1] = entry.obj
            seen[entry.obj] = true
        end
    end
    return out
end

function hasContainedCardPayload(data)
    if type(data) ~= "table" then return false end
    local contained = normalizeContainedObjectsList(data.ContainedObjects)
    if #contained == 0 then return false end
    local first = contained[1]
    if type(first) ~= "table" then return false end
    if type(first.CustomDeck) == "table" then return true end
    if first.Name == "Card" then return true end
    return false
end

function buildCapturePayloadFromSingleCardData(data)
    if type(data) ~= "table" then return nil end
    if type(data.CustomDeck) ~= "table" then return nil end

    local deckInfo = getFirstCustomDeckInfo(data.CustomDeck)
    if not deckInfo or deckInfo.faceURL == "" then return nil end

    local stateTwoCompact = nil
    if type(data.States) == "table" then
        local rawStateTwo = data.States[2] or data.States["2"]
        if type(rawStateTwo) == "table" and type(rawStateTwo.CustomDeck) == "table" then
            local stateDeckInfo = getFirstCustomDeckInfo(rawStateTwo.CustomDeck)
            if stateDeckInfo and stateDeckInfo.faceURL ~= "" then
                stateTwoCompact = {
                    nickname = tostring(rawStateTwo.Nickname or ""),
                    description = tostring(rawStateTwo.Description or ""),
                    gmNotes = tostring(rawStateTwo.GMNotes or ""),
                    memo = tostring(rawStateTwo.Memo or ""),
                    cardID = tonumber(rawStateTwo.CardID) or ((stateDeckInfo.deckSlot or 2) * 100),
                    hideWhenFaceDown = (rawStateTwo.HideWhenFaceDown ~= false),
                    hands = (rawStateTwo.Hands ~= false),
                    sideways = (rawStateTwo.SidewaysCard == true),
                    faceURL = stateDeckInfo.faceURL,
                    backURL = stateDeckInfo.backURL,
                    numWidth = stateDeckInfo.numWidth or 1,
                    numHeight = stateDeckInfo.numHeight or 1,
                    backIsHidden = (stateDeckInfo.backIsHidden ~= false),
                    uniqueBack = (stateDeckInfo.uniqueBack == true),
                    deckType = stateDeckInfo.deckType or 0,
                    deckSlot = stateDeckInfo.deckSlot or 2,
                }
            end
        end
    end

    local compactPayload = {
        _schema = "capture_payload_v2",
        bagDiffuseURL = deckInfo.faceURL,
        card = {
            nickname = tostring(data.Nickname or ""),
            description = tostring(data.Description or ""),
            gmNotes = tostring(data.GMNotes or ""),
            memo = tostring(data.Memo or ""),
            cardID = tonumber(data.CardID) or ((deckInfo.deckSlot or 1) * 100),
            hideWhenFaceDown = (data.HideWhenFaceDown ~= false),
            hands = (data.Hands ~= false),
            sideways = (data.SidewaysCard == true),
            faceURL = deckInfo.faceURL,
            backURL = deckInfo.backURL,
            numWidth = deckInfo.numWidth or 1,
            numHeight = deckInfo.numHeight or 1,
            backIsHidden = (deckInfo.backIsHidden ~= false),
            uniqueBack = (deckInfo.uniqueBack == true),
            deckType = deckInfo.deckType or 0,
            deckSlot = deckInfo.deckSlot or 1,
        }
    }

    if stateTwoCompact then
        compactPayload.card.stateTwo = stateTwoCompact
    end

    return compactPayload
end

function extractCaptureFaceUrlFromPayload(payload)
    if type(payload) ~= "table" then return "" end
    if payload._schema == "capture_payload_v2" and type(payload.card) == "table" then
        if payload.card.faceURL and payload.card.faceURL ~= "" then
            return tostring(payload.card.faceURL)
        end
        if payload.bagDiffuseURL and payload.bagDiffuseURL ~= "" then
            return tostring(payload.bagDiffuseURL)
        end
    end
    if payload.DiffuseURL and payload.DiffuseURL ~= "" then
        return tostring(payload.DiffuseURL)
    end
    if payload.CustomMesh and payload.CustomMesh.DiffuseURL and payload.CustomMesh.DiffuseURL ~= "" then
        return tostring(payload.CustomMesh.DiffuseURL)
    end
    local contained = normalizeContainedObjectsList(payload.ContainedObjects)
    if #contained > 0 then
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
    return ""
end

function buildCaptureTicketName(captureName)
    return "[b]" .. CAPTURE_TICKET_LABEL .. "[/b]  " .. tostring(captureName or "")
end

function buildCaptureNotes(captureName, imageUrl)
    return CAPTURE_NOTE_PREFIX .. "\n" .. tostring(captureName or "") .. "\n" .. tostring(imageUrl or "")
end

function buildCaptureBagSpawnData(captureItem)
    if not captureItem or type(captureItem.bagData) ~= "table" then return nil end
    local payload = captureItem.bagData

    if payload._schema == "capture_payload_v2" and type(payload.card) == "table" then
        local card = payload.card
        local cardId = tonumber(card.cardID) or 100
        if cardId < 100 then cardId = 100 end
        local deckSlot = tonumber(card.deckSlot) or math.floor(cardId / 100)
        if deckSlot < 1 then deckSlot = 1 end
        local deckKey = tostring(deckSlot)

        local faceUrl = tostring(card.faceURL or "")
        if faceUrl == "" then
            faceUrl = tostring(payload.bagDiffuseURL or captureItem.url or "")
        end
        local backUrl = tostring(card.backURL or "")
        if backUrl == "" then backUrl = CAPTURE_DEFAULT_BACK_URL end

        local out = JSON.decode(JSON.encode(CAPTURE_BAG_TEMPLATE))
        out.Nickname = buildCaptureTicketName(captureItem.name)
        out.GMNotes = buildCaptureNotes(captureItem.name, faceUrl or "")
        out.CustomMesh.DiffuseURL = tostring(payload.bagDiffuseURL or faceUrl or "")

        local outCard = JSON.decode(JSON.encode(CAPTURE_CARD_TEMPLATE))
        outCard.Nickname = card.nickname or tostring(captureItem.name or "")
        outCard.Description = card.description or ""
        outCard.GMNotes = card.gmNotes or ""
        outCard.Memo = card.memo or ""
        outCard.CardID = cardId
        outCard.HideWhenFaceDown = (card.hideWhenFaceDown ~= false)
        outCard.Hands = (card.hands ~= false)
        outCard.SidewaysCard = (card.sideways == true)
        outCard.CustomDeck = {
            [deckKey] = {
                FaceURL = faceUrl,
                BackURL = backUrl,
                NumWidth = tonumber(card.numWidth) or 1,
                NumHeight = tonumber(card.numHeight) or 1,
                BackIsHidden = (card.backIsHidden ~= false),
                UniqueBack = (card.uniqueBack == true),
                Type = tonumber(card.deckType) or 0,
            }
        }

        if type(card.stateTwo) == "table" then
            local stateTwo = card.stateTwo
            local stateCardId = tonumber(stateTwo.cardID) or 200
            if stateCardId < 100 then stateCardId = 200 end
            local stateDeckSlot = tonumber(stateTwo.deckSlot) or math.floor(stateCardId / 100)
            if stateDeckSlot < 1 then stateDeckSlot = 2 end
            local stateDeckKey = tostring(stateDeckSlot)
            local stateFaceUrl = tostring(stateTwo.faceURL or "")
            if stateFaceUrl ~= "" then
                local stateBackUrl = tostring(stateTwo.backURL or "")
                if stateBackUrl == "" then stateBackUrl = CAPTURE_DEFAULT_BACK_URL end
                local outState = JSON.decode(JSON.encode(CAPTURE_CARD_TEMPLATE))
                outState.Nickname = stateTwo.nickname or ""
                outState.Description = stateTwo.description or ""
                outState.GMNotes = stateTwo.gmNotes or ""
                outState.Memo = stateTwo.memo or ""
                outState.CardID = stateCardId
                outState.HideWhenFaceDown = (stateTwo.hideWhenFaceDown ~= false)
                outState.Hands = (stateTwo.hands ~= false)
                outState.SidewaysCard = (stateTwo.sideways == true)
                outState.CustomDeck = {
                    [stateDeckKey] = {
                        FaceURL = stateFaceUrl,
                        BackURL = stateBackUrl,
                        NumWidth = tonumber(stateTwo.numWidth) or 1,
                        NumHeight = tonumber(stateTwo.numHeight) or 1,
                        BackIsHidden = (stateTwo.backIsHidden ~= false),
                        UniqueBack = (stateTwo.uniqueBack == true),
                        Type = tonumber(stateTwo.deckType) or 0,
                    }
                }
                outCard.States = { [2] = outState }
            end
        end

        out.ContainedObjects = { outCard }
        return out
    end

    if hasContainedCardPayload(payload) then
        local out = JSON.decode(JSON.encode(payload))
        local faceUrl = extractCaptureFaceUrlFromPayload(payload)
        out.Nickname = buildCaptureTicketName(captureItem.name)
        out.GMNotes = buildCaptureNotes(captureItem.name, faceUrl)
        if out.CustomMesh and (not out.CustomMesh.DiffuseURL or out.CustomMesh.DiffuseURL == "") then
            out.CustomMesh.DiffuseURL = faceUrl
        end
        return out
    end

    return nil
end

function spawnRewardToken(reward_name)
    if reward_name == "Treasure Pirate" then
        local spawnData = JSON.decode(JSON.encode(TREASURE_PIRATE_BAG_TEMPLATE))
    local spawnPos = getLineSpawnAnchor("reward")
        local counterRot = self.getRotation()
        spawnData.Transform.posX = spawnPos.x
        spawnData.Transform.posY = spawnPos.y
        spawnData.Transform.posZ = spawnPos.z
        spawnData.Transform.rotX = counterRot.x
        spawnData.Transform.rotY = counterRot.y
        spawnData.Transform.rotZ = counterRot.z
        local spawned = spawnObjectData({ data = spawnData })
        if spawned then
            spawned.setName(reward_name)
            local desc = findRewardDescByName(reward_name)
            if desc and desc ~= "" then spawned.setDescription(desc) end
            spawned.setLock(false)
        end
        return spawned
    end

    if reward_name == "Sol Ring Ticket" or reward_name == "Arcane Signet Ticket" then
        local ticketTemplate = (reward_name == "Arcane Signet Ticket") and ARCANE_SIGNET_TICKET_BAG_TEMPLATE or SOL_RING_TICKET_BAG_TEMPLATE
        local spawnData = JSON.decode(JSON.encode(ticketTemplate))
      local spawnPos = getLineSpawnAnchor("reward")
        local counterRot = self.getRotation()
        spawnData.Transform.posX = spawnPos.x
        spawnData.Transform.posY = spawnPos.y
        spawnData.Transform.posZ = spawnPos.z
        spawnData.Transform.rotX = counterRot.x
        spawnData.Transform.rotY = counterRot.y
        spawnData.Transform.rotZ = counterRot.z
        local spawned = spawnObjectData({ data = spawnData })
        if spawned then
            spawned.setName(reward_name)
            local desc = findRewardDescByName(reward_name)
            if desc and desc ~= "" then spawned.setDescription(desc) end
            spawned.setLock(false)
        end
        return spawned
    end

    local imageUrl = SPAWN_IMAGES[reward_name]
    if not imageUrl then return nil end

    local spawnData = JSON.decode(JSON.encode(BASE_SPAWN_TEMPLATE))
    local spawnPos = getLineSpawnAnchor("reward")
    local counterRot = self.getRotation()
    spawnData.Transform.posX = spawnPos.x
    spawnData.Transform.posY = spawnPos.y
    spawnData.Transform.posZ = spawnPos.z
    spawnData.Transform.rotX = counterRot.x
    spawnData.Transform.rotY = counterRot.y
    spawnData.Transform.rotZ = counterRot.z
    spawnData.CustomMesh.DiffuseURL = imageUrl

    local spawned = spawnObjectData({ data = spawnData })
    if spawned then
        spawned.setName(reward_name)
        local desc = findRewardDescByName(reward_name)
        if desc and desc ~= "" then spawned.setDescription(desc) end
        spawned.setLock(false)
    end
    return spawned
end

function spawnCaptureToken(captureItem)
    if not captureItem then return nil end
    if captureItem.bagData then
        local bagData = buildCaptureBagSpawnData(captureItem)
        if bagData then
      local spawnPos = getLineSpawnAnchor("capture")
            local counterRot = self.getRotation()
            bagData.Transform = bagData.Transform or {}
            bagData.Transform.posX = spawnPos.x
            bagData.Transform.posY = spawnPos.y
            bagData.Transform.posZ = spawnPos.z
            bagData.Transform.rotX = counterRot.x
            bagData.Transform.rotY = counterRot.y
            bagData.Transform.rotZ = counterRot.z

            local spawned = spawnObjectData({ data = bagData })
            if spawned then
                spawned.setLock(false)
                return spawned
            end
            print("[Spawner] spawnCaptureToken: bagData path failed to spawn for " .. tostring(captureItem.name))
        else
            print("[Spawner] spawnCaptureToken: buildCaptureBagSpawnData returned nil for " .. tostring(captureItem.name))
        end
    end

    local imageUrl = captureItem.url or ""
    if imageUrl == "" and captureItem.bagData then
        imageUrl = extractCaptureFaceUrlFromPayload(captureItem.bagData)
    end
    if imageUrl == "" then
        print("[Spawner] spawnCaptureToken: no url or bagData for " .. tostring(captureItem.name))
        return nil
    end

    local spawnData = JSON.decode(JSON.encode(BASE_SPAWN_TEMPLATE))
  local spawnPos = getLineSpawnAnchor("capture")
    local counterRot = self.getRotation()
    spawnData.Transform.posX = spawnPos.x
    spawnData.Transform.posY = spawnPos.y
    spawnData.Transform.posZ = spawnPos.z
    spawnData.Transform.rotX = counterRot.x
    spawnData.Transform.rotY = counterRot.y
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
