-- Drop-to-fix Object Script for TTS
-- Put this script on a single object. Drop any object onto it and, if that
-- object contains Scryfall-backed images anywhere in its data, they will be
-- rewritten through your image proxy.

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

local function isObjectUsable(obj)
  if not obj then
    return false
  end

  local guid = safeEval(function()
    return obj.getGUID()
  end)

  return guid ~= nil and guid ~= ""
end

local function objectHasAttachments(obj)
  if not isObjectUsable(obj) then
    return false
  end

  local attachments = safeEval(function()
    return obj.getAttachments()
  end)

  return type(attachments) == "table" and #attachments > 0
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

local function isCardOrDeckType(objType)
  return objType == "Card" or objType == "Deck" or objType == "DeckCustom"
end

local function isCardOrDeckData(objData)
  if type(objData) ~= "table" then
    return false
  end

  return objData.Name == "Card" or objData.Name == "Deck" or objData.Name == "DeckCustom"
end

local function shouldSkipObject(obj)
  return isCardOrDeckType(getObjectType(obj))
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

  local pathAndQuery = url:match("^https?://cards%.scryfall%.io(/.+)$")
  return pathAndQuery
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
  if sourceUrl == "" then
    return url
  end

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

local function rewriteAnyValue(value, changed)
  local valueType = type(value)
  if valueType == "string" then
    local rewritten = proxyImageURL(value)
    if rewritten ~= value then
      changed = changed + 1
      return rewritten, changed
    end

    return value, changed
  end

  if valueType ~= "table" then
    return value, changed
  end

  if value.CustomDeck then
    changed = rewriteCustomDeck(value.CustomDeck, changed)
  end

  for key, child in pairs(value) do
    if key ~= "CustomDeck" then
      local rewrittenChild
      rewrittenChild, changed = rewriteAnyValue(child, changed)
      value[key] = rewrittenChild
    end
  end

  return value, changed
end

local function rewriteObjectData(objData, changed)
  if type(objData) ~= "table" then
    return changed
  end

  changed = changed or 0

  local rewrittenData
  rewrittenData, changed = rewriteAnyValue(objData, changed)
  return changed
end

local function objectDataHasScryfall(objData)
  if type(objData) ~= "table" then
    return false
  end

  local function valueHasScryfall(value)
    local valueType = type(value)
    if valueType == "string" then
      return isScryfallImageURL(getScryfallSourceURL(value) or value)
    end

    if valueType ~= "table" then
      return false
    end

    for _, child in pairs(value) do
      if valueHasScryfall(child) then
        return true
      end
    end

    return false
  end

  return valueHasScryfall(objData)
end

local function fixDroppedObjectInternal(obj, playerColor, allowRetry, options)
  local opts = options or {}

  if not isObjectUsable(obj) then
    notify("Drop an object onto this tool.", playerColor, {1, 0.6, 0.2})
    return 0
  end

  if objectHasAttachments(obj) then
    if not opts.silentNoChange then
      notify("Unequip attached cards before running the image fixer.", playerColor, {1, 0.6, 0.2})
    end
    return 0
  end

  if shouldSkipObject(obj) then
    if not opts.silentNoChange then
      notify("Skipped card/deck object.", playerColor, {1, 0.6, 0.2})
    end
    return 0
  end

  local objectData = safeEval(function()
    return obj.getData()
  end)
  if type(objectData) ~= "table" then
    notify("Could not read dropped object data.", playerColor, {1, 0.3, 0.3})
    return 0
  end

  if isCardOrDeckData(objectData) then
    if not opts.silentNoChange then
      notify("Skipped card/deck object.", playerColor, {1, 0.6, 0.2})
    end
    return 0
  end

  local changed = rewriteObjectData(objectData, 0)
  if changed == 0 then
    if not opts.silentNoChange then
      notify("No Scryfall image URLs found on this object.", playerColor, {1, 0.6, 0.2})
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
    notify("Could not read dropped object transform.", playerColor, {1, 0.3, 0.3})
    return 0
  end

  safeEval(function()
    destroyObject(obj)
  end)
  local spawned = spawnObjectData({data = objectData, position = pos, rotation = rot, scale = scale})

  if not opts.suppressSuccess then
    notify("Fixed " .. tostring(changed) .. " image URL(s) through the proxy.", playerColor, {0.4, 1, 0.4})
  end

  if allowRetry and spawned then
    Wait.condition(function()
      if isObjectSettled(spawned) then
        local spawnedData = safeEval(function()
          return spawned.getData()
        end)
        if objectDataHasScryfall(spawnedData) then
          notify("Running one more image-fix pass...", playerColor, {0.9, 0.9, 0.2})
          fixDroppedObjectInternal(spawned, playerColor, false)
        end
      end
    end, function()
      return not isObjectUsable(spawned) or isObjectSettled(spawned)
    end, 2)
  end

  return changed
end

function fixDroppedObject(obj, playerColor)
  return fixDroppedObjectInternal(obj, playerColor, true) > 0
end

local function getObjectData(obj)
  return safeEval(function()
    return obj.getData()
  end)
end

local function runTableScanStep(objects, index, playerColor, summary)
  if index > #objects then
    tableScanInProgress = false

    if summary.objectsFixed > 0 then
      notify(
        "Scan complete: fixed " .. tostring(summary.objectsFixed) .. " object(s) and rewrote " .. tostring(summary.urlsFixed) .. " image URL(s).",
        playerColor,
        {0.4, 1, 0.4}
      )
    else
      notify("Scan complete: no direct Scryfall image URLs found.", playerColor, {1, 0.6, 0.2})
    end

    return
  end

  local obj = objects[index]
  if isObjectUsable(obj) and obj ~= self and isObjectSettled(obj) and not shouldSkipObject(obj) then
    summary.objectsScanned = summary.objectsScanned + 1

    local objectData = getObjectData(obj)
    if not isCardOrDeckData(objectData) and objectDataHasScryfall(objectData) then
      local guid = safeEval(function()
        return obj.getGUID()
      end)

      if guid and not pendingFixByGuid[guid] then
        pendingFixByGuid[guid] = true

        local changed = fixDroppedObjectInternal(obj, playerColor, true, {
          silentNoChange = true,
          suppressSuccess = true,
        })

        if changed > 0 then
          summary.objectsFixed = summary.objectsFixed + 1
          summary.urlsFixed = summary.urlsFixed + changed
        end

        pendingFixByGuid[guid] = nil
      end
    end
  end

  Wait.frames(function()
    runTableScanStep(objects, index + 1, playerColor, summary)
  end, 1)
end

local function startTableScan(playerColor)
  if tableScanInProgress then
    notify("Image-fix scan already running.", playerColor, {1, 0.6, 0.2})
    return
  end

  tableScanInProgress = true
  notify("Scanning all table objects for Scryfall images...", playerColor, {0.9, 0.9, 0.2})

  local objects = getAllObjects()
  runTableScanStep(objects, 1, playerColor, {
    objectsScanned = 0,
    objectsFixed = 0,
    urlsFixed = 0,
  })
end

function onDropped(playerColor)
  startTableScan(playerColor)
end

function onObjectDrop(playerColor, droppedObject)
  local droppedGuid = safeEval(function()
    return droppedObject.getGUID()
  end)
  local selfGuid = safeEval(function()
    return self.getGUID()
  end)

  if droppedGuid ~= nil and selfGuid ~= nil and droppedGuid == selfGuid then
    startTableScan(playerColor)
  end
end

function onLoad()
  self.setName("Image Fix Tool (Any Object)")
  self.setDescription("Pick up and drop this tool to scan all table objects and rewrite any Scryfall-backed images through the proxy.")
end
