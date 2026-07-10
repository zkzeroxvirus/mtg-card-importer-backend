-- Drop-to-fix Object Script for TTS
-- Put this script on a single object. Drop a Card/Deck onto it to rewrite
-- Scryfall image URLs through your proxy.

IMAGE_PROXY_BASE = "https://api.mtginfo.org/image-proxy"
local pendingFixByGuid = {}

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

local function isFixableObjectType(objType)
  return objType == "Card" or objType == "Deck" or objType == "DeckCustom"
end

local function getObjectType(obj)
  return safeEval(function()
    return obj.type
  end)
end

local function isScryfallImageURL(url)
  return type(url) == "string" and url:find("^https?://cards%.scryfall%.io/") ~= nil
end

local function urlEncode(s)
  if type(s) ~= "string" then
    return ""
  end

  return (s:gsub("([^%w%-_%.~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
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

local function stripQueryAndHash(url)
  if type(url) ~= "string" then
    return ""
  end

  local trimmed = url:gsub("#.*$", "")
  trimmed = trimmed:gsub("%?.*$", "")
  return trimmed
end

local function stripKnownImageSuffix(url)
  if type(url) ~= "string" then
    return ""
  end

  local cleaned = url
  local extensions = {"jpg", "jpeg", "png", "webp", "webm", "mp4"}
  
  -- Keep stripping extensions until none are found (handles .jpg.jpg.jpg cases)
  local changed = true
  while changed do
    changed = false
    for _, ext in ipairs(extensions) do
      local before = cleaned
      cleaned = cleaned:gsub("%." .. ext .. "$", "")
      if cleaned ~= before then
        changed = true
      end
    end
  end

  return cleaned
end

local function getProxyFileExtension(url)
  local pathOnly = stripQueryAndHash(url)
  local ext = pathOnly:match("%.([A-Za-z0-9]+)$")
  if not ext then
    return "jpg"
  end

  ext = string.lower(ext)
  if ext == "jpeg" then
    return "jpg"
  end

  if ext == "jpg" or ext == "png" or ext == "webp" or ext == "webm" or ext == "mp4" then
    return ext
  end

  return "jpg"
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
  encoded = stripKnownImageSuffix(encoded)

  local decoded = urlDecode(encoded)
  if isScryfallImageURL(decoded) then
    return decoded
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

local function normalizeScryfallSize(url)
  if type(url) ~= "string" then
    return url
  end

  -- Force the more stable/consistent "normal" asset size.
  return url:gsub("(https?://cards%.scryfall%.io/)(large)(/)", "%1normal%3")
end

local function proxyImageURL(url)
  if type(url) ~= "string" or url == "" then
    return url
  end

  local sourceUrl = getScryfallSourceURL(url)
  if not sourceUrl then
    return url
  end

  -- Drop Scryfall cache-buster query strings; they can produce malformed
  -- extension suffixes when repeatedly re-proxied.
  sourceUrl = stripQueryAndHash(sourceUrl)
  if sourceUrl == "" then
    return url
  end

  sourceUrl = normalizeScryfallSize(sourceUrl)

  local ext = getProxyFileExtension(sourceUrl)
  return IMAGE_PROXY_BASE .. "/" .. urlEncode(sourceUrl) .. "." .. ext
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

local function rewriteObjectData(objData, changed)
  if type(objData) ~= "table" then
    return changed
  end

  changed = rewriteCustomDeck(objData.CustomDeck, changed)

  if objData.ContainedObjects then
    for _, child in ipairs(objData.ContainedObjects) do
      changed = rewriteObjectData(child, changed)
    end
  end

  if objData.States then
    for _, stateData in pairs(objData.States) do
      changed = rewriteObjectData(stateData, changed)
    end
  end

  return changed
end

local function objectDataHasDirectScryfall(objData)
  if type(objData) ~= "table" then
    return false
  end

  if type(objData.CustomDeck) == "table" then
    for _, cd in pairs(objData.CustomDeck) do
      if isScryfallImageURL(cd.FaceURL) or isScryfallImageURL(cd.BackURL) then
        return true
      end
    end
  end

  if objData.ContainedObjects then
    for _, child in ipairs(objData.ContainedObjects) do
      if objectDataHasDirectScryfall(child) then
        return true
      end
    end
  end

  if objData.States then
    for _, stateData in pairs(objData.States) do
      if objectDataHasDirectScryfall(stateData) then
        return true
      end
    end
  end

  return false
end

local function fixDroppedObjectInternal(obj, playerColor, allowRetry)
  local objType = getObjectType(obj)
  if not isObjectUsable(obj) or not isFixableObjectType(objType) then
    notify("Drop a Card or Deck onto this tool.", playerColor, {1, 0.6, 0.2})
    return false
  end

  if objectHasAttachments(obj) then
    notify("Unequip attached cards before running the image fixer.", playerColor, {1, 0.6, 0.2})
    return false
  end

  local objectData = safeEval(function()
    return obj.getData()
  end)
  if type(objectData) ~= "table" then
    notify("Could not read dropped object data.", playerColor, {1, 0.3, 0.3})
    return false
  end

  local changed = rewriteObjectData(objectData, 0)

  if changed == 0 then
    notify("No Scryfall image URLs found to update.", playerColor, {1, 0.6, 0.2})
    return false
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
    return false
  end

  safeEval(function()
    destroyObject(obj)
  end)
  local spawned = spawnObjectData({data = objectData, position = pos, rotation = rot, scale = scale})

  notify("Fixed " .. tostring(changed) .. " image URL(s) through the proxy.", playerColor, {0.4, 1, 0.4})

  if allowRetry and spawned then
    local spawnedGuid = safeEval(function()
      return spawned.getGUID()
    end)

    Wait.condition(function()
      local spawnedObj = getObjectFromGuid(spawnedGuid)
      if spawnedObj and isObjectSettled(spawnedObj) then
        local spawnedData = safeEval(function()
          return spawnedObj.getData()
        end)
        if objectDataHasDirectScryfall(spawnedData) then
          notify("Running one more image-fix pass...", playerColor, {0.9, 0.9, 0.2})
          fixDroppedObjectInternal(spawnedObj, playerColor, false)
        end
      end
    end, function()
      local spawnedObj = getObjectFromGuid(spawnedGuid)
      if not isObjectUsable(spawnedObj) then
        return true
      end
      return isObjectSettled(spawnedObj)
    end, 2)
  end

  return true
end

function fixDroppedObject(obj, playerColor)
  return fixDroppedObjectInternal(obj, playerColor, true)
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

function onObjectDrop(playerColor, droppedObject)
  -- Some TTS setups fire this hook broadly; require real overlap with this tool.
  local droppedType = getObjectType(droppedObject)
  if not isObjectUsable(droppedObject) or not isFixableObjectType(droppedType) then
    return
  end

  local guid = safeEval(function()
    return droppedObject.getGUID()
  end)
  if not guid or guid == "" then
    return
  end
  if pendingFixByGuid[guid] then
    return
  end

  pendingFixByGuid[guid] = true

  Wait.condition(function()
    local obj = getObjectFromGuid(guid)
    if obj and isObjectOnTool(obj) then
      fixDroppedObject(obj, playerColor)
    end
    pendingFixByGuid[guid] = nil
  end, function()
    local obj = getObjectFromGuid(guid)
    if not isObjectUsable(obj) then
      return true
    end

    return isObjectSettled(obj)
  end, 2)

  -- Failsafe: clear debounce if object never reaches "ready" state.
  if guid then
    Wait.time(function()
      pendingFixByGuid[guid] = nil
    end, 15)
  end
end

function onLoad()
  self.setName("Deck Image Fix Tool")
  self.setDescription("Drop a Card or Deck on this object to rewrite Scryfall image URLs through the proxy.")
end
