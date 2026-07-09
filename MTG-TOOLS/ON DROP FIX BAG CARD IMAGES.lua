-- Drop-to-fix Bag Contents Image Script for TTS
-- Put this script on a single object. Drop a bag/container onto it and any
-- contained Card/Deck objects with Scryfall-backed images will be rewritten
-- through your image proxy.

IMAGE_PROXY_BASE = "https://api.mtginfo.org/image-proxy"
local pendingFixByGuid = {}
local tableScanInProgress = false

local function notify(message, playerColor, color)
  if playerColor and playerColor ~= "" and Player[playerColor] then
    broadcastToColor(message, playerColor, color)
  else
    broadcastToAll(message, color)
  end
end

local function safeEval(fn)
  local ok, value = pcall(fn)
  if ok then
    return value
  end
  return nil
end

local function getObjectFromGuid(guid)
  if type(guid) ~= "string" or guid == "" then
    return nil
  end
  return safeEval(function()
    return getObjectFromGUID(guid)
  end)
end

local function isObjectUsable(obj)
  if not obj then
    return false
  end

  local guid = safeEval(function()
    return obj.getGUID()
  end)

  return guid ~= nil and guid ~= ""
end

local function isObjectSettled(obj)
  if not isObjectUsable(obj) then
    return false
  end

  local spawning = safeEval(function()
    return obj.spawning
  end)
  local resting = safeEval(function()
    return obj.resting
  end)
  local smoothMoving = safeEval(function()
    return obj.isSmoothMoving()
  end)

  if spawning == nil or resting == nil or smoothMoving == nil then
    return false
  end

  return (not spawning) and resting and (not smoothMoving)
end

local function getObjectType(obj)
  return safeEval(function()
    return obj.type
  end)
end

local function isCardOrDeckData(objData)
  if type(objData) ~= "table" then
    return false
  end

  return objData.Name == "Card" or objData.Name == "Deck" or objData.Name == "DeckCustom"
end

local function isBagLikeData(objData)
  if type(objData) ~= "table" then
    return false
  end

  if type(objData.ContainedObjects) ~= "table" then
    return false
  end

  local name = tostring(objData.Name or "")
  return name == "Bag" or name == "Infinite_Bag" or name == "Custom_Model_Bag" or name == "Custom_Model_Infinite_Bag" or name:find("Bag") ~= nil
end

local function isBagLikeObject(obj)
  local objType = tostring(getObjectType(obj) or "")
  if objType == "Bag" or objType == "Infinite" or objType == "Infinite_Bag" then
    return true
  end

  local objData = safeEval(function()
    return obj.getData()
  end)
  return isBagLikeData(objData)
end

local function isScryfallImageURL(url)
  return type(url) == "string" and url:find("^https?://cards%.scryfall%.io/") ~= nil
end

local function urlDecode(s)
  if type(s) ~= "string" then
    return ""
  end

  return (s:gsub("%%(%x%x)", function(hex)
    local value = tonumber(hex, 16)
    if value then
      return string.char(value)
    end
    return string.format("%%%s", hex)
  end))
end

local function stripProxyPathSuffix(url)
  if type(url) ~= "string" then
    return ""
  end

  local extensions = {"jpg", "jpeg", "png", "webp", "webm", "mp4"}
  for _, ext in ipairs(extensions) do
    local cleaned = url:gsub("%." .. ext .. "$", "")
    if cleaned ~= url then
      return cleaned
    end
  end

  return url
end

local function getScryfallImageProxyPath(url)
  if type(url) ~= "string" then
    return nil
  end

  return url:match("^https?://cards%.scryfall%.io(/.+)$")
end

local function normalizeWeservSource(url)
  local nested = url:match("[?&]url=([^&]+)")
  if not nested then
    return nil
  end

  local decoded = urlDecode(nested)
  if decoded:match("^cards%.scryfall%.io/") then
    decoded = "https://" .. decoded
  end

  if isScryfallImageURL(decoded) then
    return decoded
  end

  return nil
end

local function normalizeLegacyProxyQuerySource(url)
  local nested = url:match("[?&]url=([^&]+)")
  if not nested then
    return nil
  end

  local decoded = urlDecode(nested)
  if isScryfallImageURL(decoded) then
    return decoded
  end

  return nil
end

local function normalizePathProxySource(url)
  local encoded = url:match("/image%-proxy/(.+)$")
  if not encoded then
    return nil
  end

  encoded = encoded:gsub("[?#].*$", "")
  encoded = stripProxyPathSuffix(encoded)

  local decoded = urlDecode(encoded)
  if isScryfallImageURL(decoded) then
    return decoded
  end

  local scryfallPath = url:match("/image%-proxy(/.+)$")
  if scryfallPath then
    scryfallPath = scryfallPath:gsub("[?#].*$", "")
    local imageKind = scryfallPath:match("^/([^/]+)/")
    if imageKind == "small" or imageKind == "normal" or imageKind == "large" or imageKind == "png" or imageKind == "art_crop" or imageKind == "border_crop" then
      return "https://cards.scryfall.io" .. scryfallPath
    end
  end

  local id = decoded:match("([0-9a-fA-F%-]+)$")
  if id and id:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    id = string.lower(id)
    return "https://cards.scryfall.io/normal/front/" .. id:sub(1, 1) .. "/" .. id:sub(2, 2) .. "/" .. id .. ".jpg"
  end

  return nil
end

local function getScryfallSourceURL(url)
  if not (type(url) == "string" and url ~= "") then
    return nil
  end

  if isScryfallImageURL(url) then
    return url
  end

  if url:find("images%.weserv%.nl") then
    return normalizeWeservSource(url)
  end

  if url:find("/image%-proxy%?") then
    return normalizeLegacyProxyQuerySource(url)
  end

  if url:find("/image%-proxy/") then
    return normalizePathProxySource(url)
  end

  return nil
end

local function normalizeScryfallImageURL(url)
  if type(url) ~= "string" then
    return url
  end

  local prefix, imageKind, face, firstShard, secondShard, id, ext, query = url:match("^(https?://cards%.scryfall%.io/)([^/]+)/([^/]+)/([0-9a-fA-F])/([0-9a-fA-F])/([0-9a-fA-F%-]+)%.([A-Za-z0-9]+)(.*)$")
  if not prefix or not id then
    return url
  end

  if imageKind ~= "small" and imageKind ~= "normal" and imageKind ~= "large" and imageKind ~= "png" and imageKind ~= "art_crop" and imageKind ~= "border_crop" then
    return url
  end

  if face ~= "front" and face ~= "back" then
    return url
  end

  id = string.lower(id)
  return prefix .. "normal/" .. face .. "/" .. id:sub(1, 1) .. "/" .. id:sub(2, 2) .. "/" .. id .. ".jpg" .. (query or "")
end

local function proxyImageURL(url)
  if type(url) ~= "string" or url == "" then
    return url
  end

  local sourceUrl = getScryfallSourceURL(url)
  if not sourceUrl then
    return url
  end

  sourceUrl = normalizeScryfallImageURL(sourceUrl)
  local pathAndQuery = getScryfallImageProxyPath(sourceUrl)
  if not pathAndQuery then
    return url
  end

  return IMAGE_PROXY_BASE .. pathAndQuery
end

local function rewriteCustomDeck(customDeck, changed)
  if type(customDeck) ~= "table" then
    return changed
  end

  for _, cd in pairs(customDeck) do
    local oldFace = cd.FaceURL
    local oldBack = cd.BackURL

    cd.FaceURL = proxyImageURL(oldFace)
    cd.BackURL = proxyImageURL(oldBack)

    if cd.FaceURL ~= oldFace then
      changed = changed + 1
    end
    if cd.BackURL ~= oldBack then
      changed = changed + 1
    end
  end

  return changed
end

local function rewriteCardOrDeckData(objData, changed)
  if type(objData) ~= "table" then
    return changed
  end

  changed = rewriteCustomDeck(objData.CustomDeck, changed)

  if type(objData.ContainedObjects) == "table" then
    for _, child in ipairs(objData.ContainedObjects) do
      changed = rewriteCardOrDeckData(child, changed)
    end
  end

  if type(objData.States) == "table" then
    for _, stateData in pairs(objData.States) do
      changed = rewriteCardOrDeckData(stateData, changed)
    end
  end

  return changed
end

local function rewriteBagContents(objData, changed)
  if type(objData) ~= "table" then
    return changed
  end

  if isCardOrDeckData(objData) then
    return rewriteCardOrDeckData(objData, changed)
  end

  if type(objData.ContainedObjects) == "table" then
    for _, child in ipairs(objData.ContainedObjects) do
      changed = rewriteBagContents(child, changed)
    end
  end

  return changed
end

local function fixBagInternal(obj, playerColor, options)
  local opts = options or {}

  if not isObjectUsable(obj) or not isBagLikeObject(obj) then
    if not opts.silentNoChange then
      notify("Drop a bag containing Cards or Decks onto this tool.", playerColor, {1, 0.6, 0.2})
    end
    return 0
  end

  local objectData = safeEval(function()
    return obj.getData()
  end)
  if not isBagLikeData(objectData) then
    if not opts.silentNoChange then
      notify("Could not read bag contents.", playerColor, {1, 0.3, 0.3})
    end
    return 0
  end

  local changed = rewriteBagContents(objectData, 0)
  if changed == 0 then
    if not opts.silentNoChange then
      notify("No contained Card/Deck Scryfall image URLs found to update.", playerColor, {1, 0.6, 0.2})
    end
    return 0
  end

  local pos = safeEval(function()
    return obj.getPosition()
  end)
  local rot = safeEval(function()
    return obj.getRotation()
  end)
  local scale = safeEval(function()
    return obj.getScale()
  end)
  if not pos or not rot or not scale then
    notify("Could not read bag transform.", playerColor, {1, 0.3, 0.3})
    return 0
  end

  safeEval(function()
    destroyObject(obj)
  end)
  spawnObjectData({data = objectData, position = pos, rotation = rot, scale = scale})

  if not opts.suppressSuccess then
    notify("Fixed " .. tostring(changed) .. " contained Card/Deck image URL(s) through the proxy.", playerColor, {0.4, 1, 0.4})
  end
  return changed
end

local function isObjectOnTool(obj)
  if not isObjectUsable(obj) then
    return false
  end

  local toolBounds = safeEval(function()
    return self.getBounds()
  end)
  if not toolBounds or not toolBounds.center or not toolBounds.size then
    return false
  end

  local pos = safeEval(function()
    return obj.getPosition()
  end)
  if not pos then
    return false
  end

  local halfX = (toolBounds.size.x or 0) * 0.5
  local halfZ = (toolBounds.size.z or 0) * 0.5
  local pad = 0.35

  local withinX = math.abs(pos.x - toolBounds.center.x) <= (halfX + pad)
  local withinZ = math.abs(pos.z - toolBounds.center.z) <= (halfZ + pad)
  return withinX and withinZ
end

function fixDroppedBag(obj, playerColor)
  return fixBagInternal(obj, playerColor) > 0
end

local function runTableScanStep(objects, index, playerColor, summary)
  if index > #objects then
    tableScanInProgress = false

    if summary.bagsFixed > 0 then
      notify(
        "Bag scan complete: fixed " .. tostring(summary.bagsFixed) .. " bag(s) and rewrote " .. tostring(summary.urlsFixed) .. " contained Card/Deck image URL(s).",
        playerColor,
        {0.4, 1, 0.4}
      )
    else
      notify("Bag scan complete: no contained Card/Deck Scryfall image URLs found.", playerColor, {1, 0.6, 0.2})
    end

    return
  end

  local obj = objects[index]
  if isObjectUsable(obj) and obj ~= self and isObjectSettled(obj) and isBagLikeObject(obj) then
    summary.bagsScanned = summary.bagsScanned + 1

    local guid = safeEval(function()
      return obj.getGUID()
    end)

    if guid and not pendingFixByGuid[guid] then
      pendingFixByGuid[guid] = true

      local changed = fixBagInternal(obj, playerColor, {
        silentNoChange = true,
        suppressSuccess = true,
      })

      if changed > 0 then
        summary.bagsFixed = summary.bagsFixed + 1
        summary.urlsFixed = summary.urlsFixed + changed
      end

      pendingFixByGuid[guid] = nil
    end
  end

  Wait.frames(function()
    runTableScanStep(objects, index + 1, playerColor, summary)
  end, 1)
end

local function startTableScan(playerColor)
  if tableScanInProgress then
    notify("Bag image-fix scan already running.", playerColor, {1, 0.6, 0.2})
    return
  end

  tableScanInProgress = true
  notify("Scanning all table bags for contained Card/Deck images...", playerColor, {0.9, 0.9, 0.2})

  local objects = getAllObjects()
  runTableScanStep(objects, 1, playerColor, {
    bagsScanned = 0,
    bagsFixed = 0,
    urlsFixed = 0,
  })
end

function onDropped(playerColor)
  startTableScan(playerColor)
end

function onObjectDrop(playerColor, droppedObject)
  if not isObjectUsable(droppedObject) or not isBagLikeObject(droppedObject) then
    return
  end

  local guid = safeEval(function()
    return droppedObject.getGUID()
  end)
  if not guid or guid == "" or pendingFixByGuid[guid] then
    return
  end

  pendingFixByGuid[guid] = true

  Wait.condition(function()
    local obj = getObjectFromGuid(guid)
    if obj and isObjectOnTool(obj) then
      fixDroppedBag(obj, playerColor)
    end
    pendingFixByGuid[guid] = nil
  end, function()
    local obj = getObjectFromGuid(guid)
    if not isObjectUsable(obj) then
      return true
    end

    return isObjectSettled(obj)
  end, 2)

  Wait.time(function()
    pendingFixByGuid[guid] = nil
  end, 15)
end

function onLoad()
  self.setName("Bag Card Image Fix Tool")
  self.setDescription("Drop a bag on this object to rewrite contained Card/Deck Scryfall image URLs through the proxy.")
end
