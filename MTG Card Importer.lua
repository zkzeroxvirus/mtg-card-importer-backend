-- MTG Card Importer (Example)
-- Minimal Tabletop Simulator script that talks to the backend

mod_name, version = 'MTG Card Importer (Example)', 0.1
self.setName('[' .. mod_name .. '] v' .. version)

-- Backend Configuration (point to your server)
local BaseURL = 'http://localhost:3000'
local DEFAULT_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'

-- Utilities
local function log(msg)
  printToAll('[MTG Importer] ' .. tostring(msg), {0.7, 0.9, 1})
end

local function urlEncode(str)
  return str:gsub("([^%w%-%.%_%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
end

local function split_lines(resp)
  local lines = {}
  for s in resp:gmatch('[^\r\n]+') do
    table.insert(lines, s)
  end
  return lines
end

local function getJSON(url, cb)
  WebRequest.get(url, cb)
end

local function postJSON(url, req, cb)
  WebRequest.custom(url, 'POST', true, JSON.encode(req), {
    Accept = 'application/x-ndjson',
    ['Content-Type'] = 'application/json'
  }, cb)
end

-- Build and spawn from decklist (multiline "count name")
function spawnDeckList(decktext, color)
  local player = Player[color]
  local hand = player and player.getHandTransform and player:getHandTransform(1)
  if hand == nil then
    broadcastToColor('Sit at the table to spawn cards.', color, 'Red')
    return
  end

  broadcastToColor('[MTG] Building deck...', color, 'Yellow')

  postJSON(BaseURL .. '/build', { data = decktext, back = DEFAULT_BACK }, function(resp)
    if resp.error then
      broadcastToColor('[MTG Error] ' .. (resp.error or 'Server unreachable'), color, 'Red')
      return
    end
    if not resp.is_done then return end

    local cardCount = 0
    for _, line in ipairs(split_lines(resp.text or '')) do
      if line ~= '' then
        spawnObjectJSON({ json = line })
        cardCount = cardCount + 1
      end
    end

    if cardCount > 0 then
      broadcastToColor('[MTG] Spawned ' .. cardCount .. ' card(s).', color, 'Green')
    else
      broadcastToColor('[MTG] No cards spawned. Check decklist format.', color, 'Orange')
    end
  end)
end

-- Spawn a single card by wrapping it as a 1-line decklist
function spawnSingleCard(cardName, color)
  spawnDeckList('1 ' .. cardName, color)
end

-- Random cards (uses /random, then spawns names via /build)
function spawnRandomCards(query, color)
  local count = 1
  local qparam = ''

  local numStart = query:match('^(%d+)')
  local numEnd = query:match('(%d+)$')
  if numStart then
    count = tonumber(numStart)
    query = query:gsub('^%d+%s*', '')
  elseif numEnd then
    count = tonumber(numEnd)
    query = query:gsub('%s*%d+$', '')
  end

  if query:find('%?q=') then
    qparam = query:match('%?q=(.+)') or ''
    qparam = qparam:gsub('%s+%d+$', '')
  elseif query ~= '' and not query:match('^%d+$') then
    qparam = query
  end

  local url = BaseURL .. '/random?count=' .. count
  if qparam ~= '' then url = url .. '&q=' .. urlEncode(qparam) end

  broadcastToColor('Fetching ' .. count .. ' random card(s)...', color, 'Yellow')

  getJSON(url, function(resp)
    if resp.error or resp.is_error then
      broadcastToColor('[MTG Error] ' .. (resp.error or 'Server error'), color, 'Red')
      return
    end
    if not resp.is_done then return end

    local ok, data = pcall(function() return JSON.decode(resp.text) end)
    if not ok or not data then
      broadcastToColor('[MTG Error] Could not parse random response', color, 'Red')
      return
    end

    local cards = {}
    if data.object == 'list' and data.data then
      cards = data.data
    else
      table.insert(cards, data)
    end

    if #cards == 0 then
      broadcastToColor('[MTG] No cards found for that query.', color, 'Orange')
      return
    end

    local decklist = ''
    for _, card in ipairs(cards) do
      if card.name then decklist = decklist .. '1 ' .. card.name .. '\n' end
    end

    if decklist ~= '' then
      spawnDeckList(decklist, color)
    else
      broadcastToColor('[MTG] No valid card names returned.', color, 'Orange')
    end
  end)
end

-- Search cards (spawns up to 100 matches by name)
function searchCards(query, color)
  if query == '' then
    broadcastToColor('Usage: sf search <query>', color, 'Red')
    return
  end

  local url = BaseURL .. '/search?q=' .. urlEncode(query)
  broadcastToColor('Searching: ' .. query, color, 'Yellow')

  getJSON(url, function(resp)
    if resp.error or resp.is_error then
      broadcastToColor('[MTG Error] ' .. (resp.error or 'Server error'), color, 'Red')
      return
    end
    if not resp.is_done then return end

    local ok, data = pcall(function() return JSON.decode(resp.text) end)
    if not ok or not data or data.object ~= 'list' then
      broadcastToColor('[MTG Error] Could not parse search results', color, 'Red')
      return
    end

    local cards = data.data or {}
    if #cards == 0 then
      broadcastToColor('[MTG] No results.', color, 'Orange')
      return
    end

    local decklist = ''
    local limit = math.min(#cards, 100)
    for i = 1, limit do
      local card = cards[i]
      if card and card.name then
        decklist = decklist .. '1 ' .. card.name .. '\n'
      end
    end

    if decklist ~= '' then
      spawnDeckList(decklist, color)
    else
      broadcastToColor('[MTG] No valid card names returned.', color, 'Orange')
    end
  end)
end

-- Chat command router
function onChat(msg, player)
  local lower_msg = msg:lower()
  local prefix = lower_msg:match('^[!/]?(sf)[%s]')
  if not prefix then return end

  local cmd_text = msg:match('^[!/]?sf%s+(.+)$')
  if not cmd_text then return end

  local color = player.color
  local first = cmd_text:match('^(%S+)') or ''
  local rest = cmd_text:match('^%S+%s+(.+)$') or ''
  local first_lower = first:lower()

  if first_lower == 'help' then
    showHelp()
    return false
  elseif first_lower == 'random' or cmd_text:match('^random%?') then
    spawnRandomCards(rest, color)
    return false
  elseif first_lower == 'search' then
    searchCards(rest, color)
    return false
  end

  -- Multiline input = decklist
  if cmd_text:find('\n') then
    spawnDeckList(cmd_text, color)
    return false
  end

  -- Default: treat as single card name
  spawnSingleCard(cmd_text, color)
  return false
end

function onLoad()
  self.createButton({
    label = '?',
    click_function = 'showHelp',
    function_owner = self,
    position = {0, 0.2, -0.5},
    height = 200,
    width = 200,
    font_size = 150,
    tooltip = 'MTG Importer Help'
  })
end

function showHelp()
  log('===== MTG Card Importer (Example) =====')
  log('Prefix: sf')
  log('sf <card>           - spawn one card')
  log('sf <decklist...>    - spawn multiline decklist')
  log('sf random [n] [?q=] - random cards (Scryfall query optional)')
  log('sf search <query>   - spawn up to 100 results')
  log('Backend: ' .. BaseURL)
end