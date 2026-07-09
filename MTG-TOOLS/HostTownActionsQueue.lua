--==============================================================================
-- HostTownActions — Host queue manager for Cathedral / Upgrade / Augment
--==============================================================================
-- Tag this object: MTGHostTownActions
-- Spawners find it via getObjectsWithTag(HOST_ACTIONS_TAG)
--==============================================================================

HOST_ACTIONS_TAG = "MTGHostTownActions"
SPAWNER_TAG      = "MTGSpawner"

-- Queue display
QUEUE_PAGE_SIZE   = 5
QUEUE_ROW_Z_START = -0.5
QUEUE_ROW_Z_STEP  = 0.42

-- Card-collection radius when host clicks Done / Send
HOST_RETURN_RADIUS = 3.0

-- State
actionQueue      = {}    -- array of {id, type, spawnerGuid, spawnerName, text, cardGuid, status, submittedAt}
nextId           = 1
activeEntry      = nil   -- entry currently being processed
currentScreen    = "queue"
pendingReturnCard = nil  -- card dropped by host for Cathedral
queuePage        = 1

uiButtonIndices  = {}
uiInputIndices   = {}

--==============================================================================
-- onLoad / onSave
--==============================================================================
function onLoad(saved)
  if saved and saved ~= "" then
    local ok, data = pcall(JSON.decode, saved)
    if ok and type(data) == "table" then
      if type(data.actionQueue) == "table" then actionQueue = data.actionQueue end
      if type(data.nextId)      == "number" then nextId      = data.nextId      end
    end
  end
  self.addTag(HOST_ACTIONS_TAG)
  showQueueScreen()
end

function onSave()
  return JSON.encode({ actionQueue = actionQueue, nextId = nextId })
end

--==============================================================================
-- PUBLIC API — called by player spawners
--==============================================================================
function submitAction(params)
  if type(params) ~= "table" then return end
  local entry = {
    id          = nextId,
    type        = params.type        or "cathedral",
    spawnerGuid = params.spawnerGuid or "",
    spawnerName = params.spawnerName or "Unknown",
    text        = params.text        or "",
    cardGuid    = params.cardGuid,
    status      = "pending",
    submittedAt = getTimeStr(),
  }
  nextId = nextId + 1
  table.insert(actionQueue, entry)
  local typeLabel = entry.type:sub(1,1):upper() .. entry.type:sub(2)
  broadcastToAll("[Town] #" .. tostring(entry.id) .. " " .. entry.spawnerName
    .. " submitted a " .. typeLabel .. " request.", {0.8, 0.7, 0.5})
  if currentScreen == "queue" then showQueueScreen() end
  return entry.id
end

--==============================================================================
-- UI HELPERS
--==============================================================================
function trackButton(params)
  if params.function_owner == nil then params.function_owner = self end
  local existing = self.getButtons() or {}
  local idx = #existing
  self.createButton(params)
  table.insert(uiButtonIndices, idx)
  return idx
end

function clearAllUI()
  self.clearButtons()
  self.clearInputs()
  uiButtonIndices = {}
  uiInputIndices  = {}
end

function getTimeStr()
  local t = os.date("*t")
  return string.format("%02d:%02d:%02d", t.hour, t.min, t.sec)
end

function openScreen(name)
  clearAllUI()
  currentScreen = name
  drawHAHeader()
end

function drawHAHeader()
  trackButton({
    click_function = "ha_noop",
    label = "Town Actions Queue",
    position = {0, 0.1, -1.15},
    width = 1700, height = 230, font_size = 85,
    color = {0.08, 0.15, 0.1}, font_color = {0.7, 1.0, 0.75},
  })
end

function ha_noop() end

--==============================================================================
-- QUEUE SCREEN
--==============================================================================
function showQueueScreen()
  openScreen("queue")
  pendingReturnCard = nil

  -- Filter to non-done entries
  local entries = {}
  for _, e in ipairs(actionQueue) do
    if e.status ~= "done" then table.insert(entries, e) end
  end

  local total  = #entries
  local pages  = math.max(1, math.ceil(total / QUEUE_PAGE_SIZE))
  queuePage    = math.max(1, math.min(queuePage, pages))
  local startI = (queuePage - 1) * QUEUE_PAGE_SIZE + 1

  if total == 0 then
    trackButton({
      click_function = "ha_noop",
      label = "No pending actions",
      position = {0, 0.1, 0.1},
      width = 1700, height = 220, font_size = 80,
      color = {0.08, 0.12, 0.1}, font_color = {0.45, 0.65, 0.5},
    })
  else
    for i = 0, QUEUE_PAGE_SIZE - 1 do
      local entry = entries[startI + i]
      local z = QUEUE_ROW_Z_START + i * QUEUE_ROW_Z_STEP
      if entry then
        local typeLabel = entry.type:sub(1,1):upper() .. entry.type:sub(2)
        local snip = (entry.text or ""):sub(1, 28)
        if #(entry.text or "") > 28 then snip = snip .. "…" end
        local rowLabel = "#" .. tostring(entry.id) .. " [" .. typeLabel .. "]  " .. entry.spawnerName
          .. "    " .. entry.submittedAt .. "\n" .. snip
        local rowColor = (entry.status == "active") and {0.18, 0.32, 0.18}
                                                     or {0.12, 0.18, 0.12}
        local fnName = "ha_process_" .. entry.id
        _G[fnName] = function() processEntry(entry.id) end
        trackButton({
          click_function = fnName,
          label   = rowLabel,
          position = {0, 0.1, z},
          width = 1700, height = 185, font_size = 52,
          color = rowColor, font_color = {0.88, 1, 0.88},
          tooltip = "Click to process",
        })
      else
        trackButton({
          click_function = "ha_noop",
          label = "",
          position = {0, 0.1, z},
          width = 1700, height = 185, font_size = 52,
          color = {0.06, 0.08, 0.06}, font_color = {0.4, 0.4, 0.4},
        })
      end
    end
  end

  if pages > 1 then
    if queuePage > 1 then
      trackButton({
        click_function = "ha_queuePrev",
        label = "< Prev", position = {-0.9, 0.1, 1.22},
        width = 600, height = 190, font_size = 70,
        color = {0.22, 0.22, 0.22}, font_color = {1, 1, 1},
      })
    end
    trackButton({
      click_function = "ha_noop",
      label = tostring(queuePage) .. " / " .. tostring(pages),
      position = {0.3, 0.1, 1.22},
      width = 380, height = 190, font_size = 65,
      color = {0.1, 0.1, 0.1}, font_color = {0.75, 0.75, 0.75},
    })
    if queuePage < pages then
      trackButton({
        click_function = "ha_queueNext",
        label = "Next >", position = {1.5, 0.1, 1.22},
        width = 600, height = 190, font_size = 70,
        color = {0.22, 0.22, 0.22}, font_color = {1, 1, 1},
      })
    end
  end
end

function ha_queuePrev() queuePage = math.max(1, queuePage - 1); showQueueScreen() end
function ha_queueNext() queuePage = queuePage + 1;               showQueueScreen() end

function getEntryById(id)
  for _, e in ipairs(actionQueue) do
    if e.id == id then return e end
  end
end

function processEntry(id)
  local entry = getEntryById(id)
  if not entry then showQueueScreen() return end
  activeEntry   = entry
  entry.status  = "active"
  if entry.type == "cathedral" then
    showProcessCathedral()
  else
    showProcessUpgradeAugment()
  end
end

--==============================================================================
-- PROCESS CATHEDRAL
--==============================================================================
function showProcessCathedral()
  openScreen("process_cathedral")
  local entry = activeEntry
  if not entry then showQueueScreen() return end

  trackButton({
    click_function = "ha_noop",
    label = "Cathedral  —  " .. entry.spawnerName,
    position = {0, 0.1, -0.72},
    width = 1700, height = 185, font_size = 72,
    color = {0.1, 0.18, 0.28}, font_color = {0.75, 0.88, 1.0},
  })

  local displayText = (entry.text ~= "") and entry.text or "(no description)"
  trackButton({
    click_function = "ha_noop",
    label = displayText,
    position = {0, 0.1, -0.08},
    width = 1700, height = 280, font_size = 52,
    color = {0.08, 0.1, 0.14}, font_color = {1, 1, 0.82},
    tooltip = displayText,
  })

  trackButton({
    click_function = "ha_noop",
    label = "Drop a card here, then click Send",
    position = {0, 0.1, 0.52},
    width = 1700, height = 185, font_size = 62,
    color = {0.1, 0.17, 0.1}, font_color = {0.65, 1, 0.65},
  })

  trackButton({
    click_function = "ha_cathedralSend",
    label = "Send",
    position = {0.8, 0.1, 1.1},
    width = 700, height = 230, font_size = 88,
    color = {0.18, 0.42, 0.18}, font_color = {1, 1, 1},
    tooltip = "Send the dropped card to the player",
  })
  trackButton({
    click_function = "ha_processCancelCathedral",
    label = "Cancel",
    position = {-0.8, 0.1, 1.1},
    width = 700, height = 230, font_size = 88,
    color = {0.42, 0.12, 0.12}, font_color = {1, 1, 1},
    tooltip = "Leave entry pending and return to queue",
  })
end

function ha_cathedralSend()
  if not activeEntry then showQueueScreen() return end
  if not pendingReturnCard then
    broadcastToAll("[Town] Drop a card near the Town Actions object first.", {0.9, 0.6, 0.3})
    return
  end
  local entry      = activeEntry
  local spawnerObj = nil
  pcall(function() spawnerObj = getObjectFromGUID(entry.spawnerGuid) end)
  if not spawnerObj then
    broadcastToAll("[Town] Could not find " .. entry.spawnerName .. "'s spawner.", {0.9, 0.3, 0.3})
    return
  end

  local targetPos = spawnerObj.getPosition() + Vector(0, 2.5, 0)
  pcall(function() pendingReturnCard.setPositionSmooth(targetPos, false, true) end)
  local cardGuid = pendingReturnCard.getGUID()
  pendingReturnCard = nil

  Wait.frames(function()
    pcall(function()
      spawnerObj.call("receiveTownActionResult", {
        requestId = entry.id,
        type      = "cathedral",
        cardGuids = {cardGuid},
      })
    end)
  end, 35)

  entry.status = "done"
  activeEntry  = nil
  broadcastToAll("[Town] Cathedral card sent to " .. entry.spawnerName .. "!", {0.55, 1, 0.55})
  showQueueScreen()
end

function ha_processCancelCathedral()
  if pendingReturnCard then
    local white = Player["White"]
    if white and white.seated then
      pcall(function() white.addHandCard(pendingReturnCard) end)
    end
    pendingReturnCard = nil
  end
  if activeEntry then activeEntry.status = "pending" end
  activeEntry = nil
  showQueueScreen()
end

--==============================================================================
-- PROCESS UPGRADE / AUGMENT
--==============================================================================
function showProcessUpgradeAugment()
  openScreen("process_upgrade")
  local entry = activeEntry
  if not entry then showQueueScreen() return end

  local typeLabel = entry.type:sub(1,1):upper() .. entry.type:sub(2)
  trackButton({
    click_function = "ha_noop",
    label = typeLabel .. "  —  " .. entry.spawnerName,
    position = {0, 0.1, -0.72},
    width = 1700, height = 185, font_size = 72,
    color = {0.2, 0.15, 0.08}, font_color = {1, 0.88, 0.55},
  })

  local noteText = (entry.text ~= "") and entry.text or "(no note)"
  trackButton({
    click_function = "ha_noop",
    label = noteText,
    position = {0, 0.1, -0.08},
    width = 1700, height = 235, font_size = 52,
    color = {0.1, 0.08, 0.06}, font_color = {1, 1, 0.75},
    tooltip = noteText,
  })

  -- Teleport submitted card to near this object
  local cardFound = false
  if entry.cardGuid and entry.cardGuid ~= "" then
    local card = nil
    pcall(function() card = getObjectFromGUID(entry.cardGuid) end)
    if card then
      local myPos = self.getPosition()
      pcall(function()
        card.setPositionSmooth(Vector(myPos.x, myPos.y + 3.5, myPos.z + 1.2), false, true)
      end)
      cardFound = true
    end
  end

  local instrText = cardFound
    and "Card teleported nearby. Edit it, duplicate if needed, then click Done."
    or  "Card not found (may have been moved or removed)."
  local instrColor = cardFound and {0.1, 0.14, 0.1} or {0.25, 0.08, 0.08}
  trackButton({
    click_function = "ha_noop",
    label = instrText,
    position = {0, 0.1, 0.52},
    width = 1700, height = 185, font_size = 56,
    color = instrColor, font_color = {0.75, 1, 0.75},
  })

  trackButton({
    click_function = "ha_upgradeAugmentDone",
    label = "Done",
    position = {0.8, 0.1, 1.1},
    width = 700, height = 230, font_size = 88,
    color = {0.18, 0.42, 0.18}, font_color = {1, 1, 1},
    tooltip = "Collect cards within radius and send to player",
  })
  trackButton({
    click_function = "ha_processCancelUpgrade",
    label = "Cancel",
    position = {-0.8, 0.1, 1.1},
    width = 700, height = 230, font_size = 88,
    color = {0.42, 0.12, 0.12}, font_color = {1, 1, 1},
    tooltip = "Return original card to player with XP refund",
  })
end

function ha_upgradeAugmentDone()
  if not activeEntry then showQueueScreen() return end
  local entry      = activeEntry
  local spawnerObj = nil
  pcall(function() spawnerObj = getObjectFromGUID(entry.spawnerGuid) end)
  if not spawnerObj then
    broadcastToAll("[Town] Could not find " .. entry.spawnerName .. "'s spawner.", {0.9, 0.3, 0.3})
    return
  end

  local myPos = self.getPosition()
  local cards = findInRadiusBy(myPos, HOST_RETURN_RADIUS, function(o)
    if o == self then return false end
    local tag = ""
    pcall(function() tag = o.tag or "" end)
    return tag == "Card"
  end)

  if #cards == 0 then
    broadcastToAll("[Town] No cards found near Town Actions object. Place the card(s) nearby first.", {0.9, 0.6, 0.3})
    return
  end

  local cardGuids = {}
  local N         = math.min(#cards, 4)

  -- Measure card width from the first card, matching autoSplay_routine's getBoundsNormalized pattern
  local cardW = 0.7  -- fallback default
  pcall(function()
    local b = cards[1].getBoundsNormalized()
    cardW = b.size.x
  end)
  local spacer = 0.05
  local xStep  = cardW + spacer           -- same formula as auto-splay
  local xStart = -xStep * (N - 1) / 2    -- single row, N columns, centred

  for i, card in ipairs(cards) do
    local guid = card.getGUID()
    table.insert(cardGuids, guid)
    local xOff = xStart + (i - 1) * xStep
    -- Negate x: button local-x and positionToWorld local-x are visually mirrored
    -- for this spawner's physical orientation in TTS (z=180 face-up convention).
    -- card[1] at -xOff lands LEFT; button[1] at +xOff also reads LEFT. They match.
    local worldPos = spawnerObj.positionToWorld(Vector(-xOff, 2.5, 0))
    pcall(function() card.setPositionSmooth(worldPos, false, true) end)
  end

  Wait.frames(function()
    pcall(function()
      spawnerObj.call("receiveTownActionResult", {
        requestId = entry.id,
        type      = entry.type,
        cardGuids = cardGuids,
        xStep     = xStep,   -- pass measured step so spawner buttons align with cards
      })
    end)
  end, 45)

  local typeLabel = entry.type:sub(1,1):upper() .. entry.type:sub(2)
  entry.status = "done"
  activeEntry  = nil
  broadcastToAll("[Town] " .. typeLabel .. " result sent to " .. entry.spawnerName
    .. " (" .. #cards .. " card(s))!", {0.55, 1, 0.55})
  showQueueScreen()
end

function ha_processCancelUpgrade()
  if not activeEntry then showQueueScreen() return end
  local entry      = activeEntry
  local spawnerObj = nil
  pcall(function() spawnerObj = getObjectFromGUID(entry.spawnerGuid) end)

  -- Return original card to player
  if entry.cardGuid and entry.cardGuid ~= "" and spawnerObj then
    local card = nil
    pcall(function() card = getObjectFromGUID(entry.cardGuid) end)
    if card then
      local pos = spawnerObj.getPosition() + Vector(0, 2.5, 0)
      pcall(function() card.setPositionSmooth(pos, false, true) end)
    end
  end

  -- Notify spawner so it can refund XP and clear its pending state
  if spawnerObj then
    Wait.frames(function()
      pcall(function()
        spawnerObj.call("receiveTownActionCancelled", {
          requestId = entry.id,
          type      = entry.type,
          cardGuid  = entry.cardGuid,
        })
      end)
    end, 30)
  end

  entry.status = "done"
  activeEntry  = nil
  showQueueScreen()
end

--==============================================================================
-- CARD DROP DETECTION  (Cathedral only — upgrade/augment card is pre-submitted)
--==============================================================================
function onObjectDropped(player_color, dropped_object)
  if not dropped_object or dropped_object == self then return end
  local okPos, pos = pcall(function() return dropped_object.getPosition() end)
  if not okPos or type(pos) ~= "table" then return end
  local my = self.getPosition()
  local dx = pos.x - my.x
  local dz = pos.z - my.z
  if (dx * dx + dz * dz) > (HOST_RETURN_RADIUS * HOST_RETURN_RADIUS) then return end

  if currentScreen == "process_cathedral" then
    local tag = ""
    pcall(function() tag = dropped_object.tag or "" end)
    if tag == "Card" then
      pendingReturnCard = dropped_object
      broadcastToAll("[Town] Card staged for Cathedral. Click Send when ready.", {0.6, 1, 0.65})
    end
  end
end

--==============================================================================
-- PHYSICS HELPER
--==============================================================================
function findInRadiusBy(pos, radius, func)
  local objList = Physics.cast({
    origin       = pos,
    direction    = {0, 1, 0},
    type         = 2,
    size         = {radius, radius, radius},
    max_distance = 0,
  })
  local out = {}
  for _, obj in ipairs(objList) do
    if func == nil or func(obj.hit_object) then
      table.insert(out, obj.hit_object)
    end
  end
  return out
end
