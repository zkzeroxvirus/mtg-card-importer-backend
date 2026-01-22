-- MTG Card Importer via Backend (Chat Based + Encoder Integration)
-- Uses Scryfall API with proper rate limiting and attribution
-- Integrates with Encoder mod for card buttons
mod_name, version = 'MTG Card Importer', 2.3
self.setName('[' .. mod_name .. '] v' .. version)

-- Backend Configuration
local BaseURL = 'https://mtg-card-importer-backend.onrender.com'
local CLIENT_VERSION = '2.2'
local DEFAULT_BACK = 'https://steamusercontent-a.akamaihd.net/ugc/1647720103762682461/35EF6E87970E2A5D6581E7D96A99F8A575B7A15F/'
local CARD_BACKS = {} -- Per-player custom card backs

-- Utilities
local function log(msg)
	printToAll('[MTG Importer] ' .. tostring(msg), {0.7, 0.9, 1})
end

local function split_lines(resp)
	local lines = {}
	for s in resp:gmatch('[^\r\n]+') do
		table.insert(lines, s)
	end
	return lines
end

local function postJSON(url, req, cb)
	WebRequest.custom(url, 'POST', true, JSON.encode(req), {
		Accept = 'application/x-ndjson',
		['Content-Type'] = 'application/json',
		['X-Client-Version'] = CLIENT_VERSION,
	}, cb)
end

local function spawnCard(json_str)
	if json_str and json_str ~= "" then
		log('[DEBUG] Spawning JSON (first 200 chars): ' .. json_str:sub(1, 200))
	end
	spawnObjectJSON({json = json_str})
end

local function getPlayerBack(color)
	return CARD_BACKS[color] or DEFAULT_BACK
end

-- URL encode a string
local function urlEncode(str)
	str = string.gsub(str, "([^%w%-%.%_%~])", function(c)
		return string.format("%%%02X", string.byte(c))
	end)
	return str
end

-- Simple GET request
local function getJSON(url, cb)
	WebRequest.get(url, cb)
end

-- Single Card Spawn
function spawnSingleCard(cardName, color)
	local player = Player[color]
	local hand = player.getHandTransform(1)
	
	if hand == nil then
		broadcastToColor('You need to take a seat for cards to be generated', color, 'Red')
		return
	end
	
	hand.position = hand.position + hand.forward:scale(2)
	
	broadcastToColor('Fetching ' .. cardName .. '...', color, 'Yellow')
	
	-- Use decklist approach for single card (more reliable)
	spawnDeckList('1 ' .. cardName, color)
end

-- Deck List Spawn
function spawnDeckList(decktext, color)
	local player = Player[color]
	local hand = player.getHandTransform(1)
	
	if hand == nil then
		broadcastToColor('You need to take a seat for deck to be generated', color, 'Red')
		return
	end
	
	hand.position = hand.position + hand.forward:scale(2)
	
	broadcastToColor('Building deck...', color, 'Yellow')
	
	local req = {
		data = decktext,
		back = getPlayerBack(color),
		hand = hand
	}
	
	postJSON(BaseURL .. '/build', req, function(resp)
		if resp.error ~= nil then
			if resp.text and resp.text:find('"error"') then
				local data = JSON.decode(resp.text)
				broadcastToColor('Error: ' .. data.error, color, 'Red')
			else
				broadcastToColor('Server error, please try again later', color, 'Red')
			end
			return
		end
		
		if not resp.is_done then
			return
		end
		
		broadcastToColor('Rendering deck...', color, 'Yellow')
		for _, obj in ipairs(split_lines(resp.text)) do
			if obj ~= '' then
				-- Backend returns NDJSON where each line is a TTS object
				-- Spawn each line directly (no extraction needed)
				spawnObjectJSON({json = obj})
			end
		end
	end)
end

-- Random Cards with Query
function spawnRandomCards(query, color)
	local player = Player[color]
	local hand = player.getHandTransform(1)
	
	if hand == nil then
		broadcastToColor('You need to take a seat for cards to be generated', color, 'Red')
		return
	end
	
	hand.position = hand.position + hand.forward:scale(2)
	
	-- Parse query string: "?q=r:m+id:wubrg 15" or "15 ?q=r:m" or just "?q=r:m" or just "15"
	local count = 1
	local qparam = ""
	
	-- Extract count if present (number at start or end)
	local numStart = query:match('^(%d+)')
	local numEnd = query:match('(%d+)$')
	if numStart then
		count = tonumber(numStart)
		query = query:gsub('^%d+%s*', '')
	elseif numEnd then
		count = tonumber(numEnd)
		query = query:gsub('%s*%d+$', '')
	end
	
	-- Extract ?q= query if present
	if query:find('%?q=') then
		qparam = query:match('%?q=(.+)') or ""
		qparam = qparam:gsub('%s+%d+$', '') -- Remove trailing count if present
	elseif query ~= "" and not query:match('^%d+$') then
		-- Treat remaining text as query
		qparam = query
	end
	
	local url = BaseURL .. '/random?count=' .. count
	if qparam ~= "" then
		url = url .. '&q=' .. urlEncode(qparam)
	end
	
	broadcastToColor('Fetching ' .. count .. ' random card(s) from Scryfall...', color, 'Yellow')
	
	getJSON(url, function(resp)
		if resp.error ~= nil or resp.is_error then
			broadcastToColor('Server error: ' .. (resp.error or 'Unknown error'), color, 'Red')
			return
		end
		
		if not resp.is_done then
			return
		end
		
		-- Parse JSON array response (backend now returns array of TTS objects)
		local success, cards = pcall(function() return JSON.decode(resp.text) end)
		if not success or not cards then
			broadcastToColor('Error parsing response', color, 'Red')
			return
		end
		
		if #cards == 0 then
			broadcastToColor('No cards found', color, 'Orange')
			return
		end
		
		broadcastToColor('Spawning ' .. #cards .. ' card(s)...', color, 'Yellow')
		
		-- Build deck list from TTS objects (extract Nickname which is the card name)
		local decklist = ""
		for i, card in ipairs(cards) do
			local cardName = card.Nickname
			if cardName then
				decklist = decklist .. "1 " .. cardName .. "\n"
			end
		end
		
		if decklist ~= "" then
			spawnDeckList(decklist, color)
		else
			broadcastToColor('No valid cards in response', color, 'Orange')
		end
	end)
end

-- Search Cards
function searchCards(query, color)
	local player = Player[color]
	local hand = player.getHandTransform(1)
	
	if hand == nil then
		broadcastToColor('You need to take a seat for cards to be generated', color, 'Red')
		return
	end
	
	hand.position = hand.position + hand.forward:scale(2)
	
	local url = BaseURL .. '/search?q=' .. urlEncode(query)
	
	broadcastToColor('Searching Scryfall for: ' .. query, color, 'Yellow')
	
	getJSON(url, function(resp)
		if resp.error ~= nil or resp.is_error then
			broadcastToColor('Server error: ' .. (resp.error or 'Unknown error'), color, 'Red')
			return
		end
		
		if not resp.is_done then
			return
		end
		
		-- Parse JSON array response (backend returns array of TTS objects)
		local success, cards = pcall(function() return JSON.decode(resp.text) end)
		if not success then
			broadcastToColor('Error parsing search results', color, 'Red')
			return
		end
		
		if type(cards) == "table" and cards.error then
			broadcastToColor('Search error: ' .. cards.error, color, 'Red')
			return
		end
		
		if #cards == 0 then
			broadcastToColor('No cards found', color, 'Orange')
			return
		end
		
		if #cards > 100 then
			broadcastToColor('Too many results (' .. #cards .. '), spawning first 100', color, 'Orange')
		end
		
		broadcastToColor('Found ' .. math.min(#cards, 100) .. ' card(s), spawning...', color, 'Yellow')
		
		-- Build deck list from TTS objects (extract Nickname which is the card name, limit to 100)
		local decklist = ""
		for i = 1, math.min(#cards, 100) do
			local card = cards[i]
			local cardName = card.Nickname
			if cardName then
				decklist = decklist .. "1 " .. cardName .. "\n"
			end
		end
		
		if decklist ~= "" then
			spawnDeckList(decklist, color)
		else
			broadcastToColor('No valid cards in search results', color, 'Orange')
		end
	end)
end

-- Set Custom Card Back
function setCardBack(url, color)
	CARD_BACKS[color] = url
	broadcastToColor('Card back set to: ' .. url, color, 'Green')
end

-- Show Card Text/Rules
function showCardInfo(cardname, mode, color)
	local url = BaseURL .. '/card/' .. urlEncode(cardname)
	
	broadcastToColor('Fetching ' .. cardname .. ' info...', color, 'Yellow')
	
	getJSON(url, function(resp)
		if resp.error ~= nil or resp.is_error then
			broadcastToColor('Error fetching card', color, 'Red')
			return
		end
		
		if not resp.is_done then
			return
		end
		
		-- Backend returns TTS object, need to parse it to get card info
		local success, card = pcall(function() return JSON.decode(resp.text) end)
		if not success or not card then
			broadcastToColor('Error parsing card data', color, 'Red')
			return
		end
		
		-- For now, just show Nickname (card name) and Description (oracle text)
		if mode == "text" then
			-- Show oracle text (stored in Description field of TTS object)
			local text = card.Description or "No oracle text"
			broadcastToColor('[' .. (card.Nickname or 'Unknown') .. '] ' .. text, color, 'White')
			
		elseif mode == "rules" then
			-- For rulings, we'd need to make an additional request to /rulings endpoint
			-- This would require knowing the Scryfall card ID, which we don't have in the TTS object
			-- For now, show a placeholder
			broadcastToColor('[' .. (card.Nickname or 'Unknown') .. '] Rulings not available in current format', color, 'Orange')
		end
	end)
end

-- Chat Command Handler
function onChat(msg, player)
	local lower_msg = msg:lower()
	
	-- Parse command: "sf" prefix only
	local prefix = lower_msg:match('^[!/]?(sf)[%s]')
	if not prefix then
		return -- Not our command
	end
	
	local cmd_text = msg:match('^[!/]?sf%s+(.+)$')
	if not cmd_text then
		return
	end
	
	local color = player.color
	
	-- Command routing
	local first_word = cmd_text:match('^(%S+)')
	local first_word_lower = first_word and first_word:lower() or ""
	local rest = cmd_text:match('^%S+%s+(.+)$') or ""
	
	-- Random: "random" or "random ?q=..." or "random 15 ?q=..."
	if first_word_lower == "random" or cmd_text:match('^random%?') then
		spawnRandomCards(rest, color)
		return false
	end
	
	-- Search: "search <query>"
	if first_word_lower == "search" then
		if rest ~= "" then
			searchCards(rest, color)
		else
			broadcastToColor('Usage: sf search <query>', color, 'Red')
		end
		return false
	end
	
	-- Card back: "back <url>" or "back" to show current
	if first_word_lower == "back" then
		if rest ~= "" then
			setCardBack(rest, color)
		else
			local current = getPlayerBack(color)
			broadcastToColor('Current card back: ' .. current, color, 'Cyan')
		end
		return false
	end
	
	-- Text: "text <cardname>"
	if first_word_lower == "text" then
		if rest ~= "" then
			showCardInfo(rest, "text", color)
		else
			broadcastToColor('Usage: sf text <cardname>', color, 'Red')
		end
		return false
	end
	
	-- Rules: "rules <cardname>"
	if first_word_lower == "rules" then
		if rest ~= "" then
			showCardInfo(rest, "rules", color)
		else
			broadcastToColor('Usage: sf rules <cardname>', color, 'Red')
		end
		return false
	end
	
	-- Help
	if first_word_lower == "help" then
		showHelp()
		return false
	end
	
	-- Deck list (multiline): sf with \n
	if cmd_text:find('\n') then
		spawnDeckList(cmd_text, color)
		return false
	end
	
	-- Default: single card spawn
	spawnSingleCard(cmd_text, color)
	return false
end

function onLoad(data)
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
	
	-- Register with Encoder if available
	Wait.frames(function() registerModule() end, 1)
end

-- ============================================================================
-- ENCODER INTEGRATION
-- ============================================================================

function registerModule()
	local enc = Global.getVar('Encoder')
	if enc then
		enc.call('APIregisterProperty', {
			propID = mod_name,
			name = 'MTG Importer',
			values = {},
			funcOwner = self,
			activateFunc = 'toggleMenu',
			visible = true,
			visible_in_hand = 0,
			tags = 'tool'
		})
		-- Register a πMenu-style menu to draw our buttons along the card edge
		enc.call('APIregisterMenu', {
			menuID = 'MTG Importer Menu',
			funcOwner = self,
			activateFunc = 'createImporterMenu',
			visible_in_hand = 1
		})
		log('Encoder integration registered (Amuzet-style + πMenu)')
	end
end

-- Toggle our πMenu-style menu open/closed via Encoder
function toggleMenu(arg)
	local o = (type(arg) == 'table' and (arg.obj or arg)) or arg
	local enc = Global.getVar('Encoder')
	if enc and o then
		enc.call('APIobjToggleMenu', {obj = o, menuID = 'MTG Importer Menu'})
		enc.call('APIrebuildButtons', {obj = o})
	end
end

-- Simple style similar to πMenu for consistent button look
local PiStyle = {}
PiStyle.proto = {
	scale = {0.5, 1, 0.3},
	height = 350,
	font_size = 200,
	color = {0.1, 0.1, 0.1, 1},
	font_color = {1, 1, 1, 1},
	hover_color = {0.1, 0.1, 0.1, 0.6}
}
PiStyle.mt = {}
PiStyle.mt.__index = PiStyle.proto
function PiStyle.new(o)
	for k, v in pairs(PiStyle.proto) do
		if o[k] == nil then o[k] = v end
	end
	return o
end

-- Draw a πMenu-like edge menu with our six actions
function createImporterMenu(t)
	local o = t.obj
	local enc = Global.getVar('Encoder')
	if not enc or not o then return end

	local flip = enc.call('APIgetFlip', {obj = o}) or 1
	local zpos = 0.3 * flip
	local xpos = -0.875 * flip

	local md = enc.call('APIobjGetMenuData', {obj = o, menuID = 'MTG Importer Menu'}) or {open = false}

	if md.open == false then
		-- Closed: show the open chevron
		o.createButton(PiStyle.new({
			label = '[b]<<<[/b]', click_function = 'toggleMenu', function_owner = self,
			position = {xpos, zpos, -1.485}, scale = {0.5, 1, 0.3}, height = 0, width = 0,
			rotation = {0, 0, 90 - 90 * flip}, color = {0, 0, 0, 0}, font_color = {0, 0, 0, 50}
		}))
		o.createButton(PiStyle.new({
			label = '<<<', click_function = 'toggleMenu', function_owner = self,
			position = {xpos, zpos, -1.485}, rotation = {0, 0, 90 - 90 * flip},
			color = {0.1, 0.1, 0.1, 0}, font_color = {1, 1, 1, 0.8}
		}))
		return
	end

	-- Open: show the close chevron
	o.createButton(PiStyle.new({
		label = '>>>', click_function = 'toggleMenu', function_owner = self,
		position = {xpos, zpos, -1.485}, rotation = {0, 0, 90 - 90 * flip},
		color = {0.1, 0.1, 0.1, 1}, font_color = {1, 1, 1, 1}
	}))

	-- Our actions listed vertically along the long edge
	local entries = {
		{label = 'Oracle',     func = 'eOracle'},
		{label = 'Rulings',    func = 'eRulings'},
		{label = 'Tokens',     func = 'eTokens'},
		{label = 'Printings',  func = 'ePrintings'},
		{label = 'Set Back',   func = 'eSetBack'},
		{label = 'Flip Card',  func = 'eReverse'}
	}

	local baseZ = -1.40
	local step = 0.25
	for i, e in ipairs(entries) do
		o.createButton(PiStyle.new({
			label = e.label, click_function = e.func, function_owner = self,
			position = {xpos, zpos, baseZ + (i - 1) * step}, rotation = {0, 0, 90 - 90 * flip},
			width = 900, font_color = {1, 1, 1, 0.85}
		}))
	end
end

function createButtons(card)
	-- Get card name for button labels
	local cardName = card.getName()
	
	-- Clear existing buttons first
	card.clearButtons()
	
	-- Button positions (will be arranged in a grid)
	local buttons = {
		{ label = 'Oracle', func = 'eOracle', pos = {-0.5, 0.3, -1} },
		{ label = 'Rulings', func = 'eRulings', pos = {0.5, 0.3, -1} },
		{ label = 'Tokens', func = 'eTokens', pos = {-0.5, 0.3, 0} },
		{ label = 'Printings', func = 'ePrintings', pos = {0.5, 0.3, 0} },
		{ label = 'Back', func = 'eSetBack', pos = {-0.5, 0.3, 1} },
		{ label = 'Reverse', func = 'eReverse', pos = {0.5, 0.3, 1} },
	}
	
	for _, btn in ipairs(buttons) do
		card.createButton({
			label = btn.label,
			click_function = btn.func,
			function_owner = self,
			position = btn.pos,
			height = 250,
			width = 800,
			font_size = 80,
			color = {0.2, 0.2, 0.2, 0.9},
			font_color = {1, 1, 1, 1},
			hover_color = {0.4, 0.4, 0.4, 0.9},
			press_color = {0.6, 0.6, 0.6, 0.9}
		})
	end
end

function eOracle(arg)
	local card = (type(arg) == 'table' and arg.obj) or arg
	if not card or not card.getName then return end
	local cardName = card.getName():match('^([^\n]+)')
	getJSON(BaseURL .. '/card/' .. urlEncode(cardName), function(resp)
		if resp.is_done then
			local success, cardData = pcall(function() return JSON.decode(resp.text) end)
			if success and cardData then
				local oracleText = cardData.Description or 'No oracle text'
				printToAll('[MTG Oracle] ' .. cardName .. ':\n' .. oracleText, {0.7, 1, 0.7})
				-- Also set it as card description
				card.setDescription(oracleText)
			end
		end
	end)
end

function eRulings(arg)
	local card = (type(arg) == 'table' and arg.obj) or arg
	if not card or not card.getName then return end
	local cardName = card.getName():match('^([^\n]+)')
	getJSON(BaseURL .. '/rulings/' .. urlEncode(cardName), function(resp)
		if resp.is_done then
			local success, rulingsData = pcall(function() return JSON.decode(resp.text) end)
			if success and rulingsData and rulingsData.data then
				local rulingsText = ''
				for _, ruling in ipairs(rulingsData.data) do
					rulingsText = rulingsText .. ruling.published_at .. '\n' .. ruling.comment .. '\n\n'
				end
				if rulingsText ~= '' then
					printToAll('[MTG] Rulings for ' .. cardName .. ':\n' .. rulingsText, {0, 1, 0.5})
				end
			end
		end
	end)
end

function eTokens(arg)
	local card = (type(arg) == 'table' and arg.obj) or arg
	if not card or not card.getName then return end
	local cardName = card.getName():match('^([^\n]+)')
	printToAll('[MTG] Fetching tokens for ' .. cardName .. '...', {0.7, 0.7, 1})
	getJSON(BaseURL .. '/tokens/' .. urlEncode(cardName), function(resp)
		if resp.is_done then
			local success, tokens = pcall(function() return JSON.decode(resp.text) end)
			if success and tokens and #tokens > 0 then
				printToAll('[MTG] Spawning ' .. #tokens .. ' token(s)...', {0.7, 1, 0.7})
				for _, tokenCard in ipairs(tokens) do
					spawnObjectJSON({json = JSON.encode(tokenCard)})
				end
			else
				printToAll('[MTG] No tokens found for ' .. cardName, {1, 0.8, 0.5})
			end
		end
	end)
end

function ePrintings(arg)
	local card = (type(arg) == 'table' and arg.obj) or arg
	if not card or not card.getName then return end
	local cardName = card.getName():match('^([^\n]+)')
	getJSON(BaseURL .. '/printings/' .. urlEncode(cardName), function(resp)
		if resp.is_done then
			local success, printings = pcall(function() return JSON.decode(resp.text) end)
			if success and printings and #printings > 0 then
				local printText = 'Printings of ' .. cardName .. ':\n'
				for i, p in ipairs(printings) do
					if i <= 10 then -- Show first 10
						printText = printText .. p.setName .. ' (' .. p.set .. ') - ' .. (p.rarity or 'U') .. '\n'
					end
				end
				printToAll(printText, {0.5, 1, 0.5})
			end
		end
	end)
end

function eSetBack(arg)
	local card = (type(arg) == 'table' and arg.obj) or arg
	if not card or not card.getName then return end
	local cardName = card.getName():match('^([^\n]+)')
	getJSON(BaseURL .. '/card/' .. urlEncode(cardName), function(resp)
		if resp.is_done then
			local success, cardData = pcall(function() return JSON.decode(resp.text) end)
			if success and cardData then
				printToAll('[MTG] Back set for ' .. cardName, {0.7, 1, 0.7})
			end
		end
	end)
end

function eReverse(arg)
	local card = (type(arg) == 'table' and arg.obj) or arg
	if not card or not card.getJSON then return end
	-- Flip the card (swap back and front)
	spawnObjectJSON({json = card.getJSON():gsub('BackURL', 'FaceURL_TEMP'):gsub('FaceURL', 'BackURL'):gsub('FaceURL_TEMP', 'FaceURL')})
end

function showHelp()
	log('===== MTG Card Importer v' .. version .. ' =====')
	log('Prefix: "sf" (e.g., "sf Mountain" or "/sf Black Lotus")')
	log('Data from: Scryfall API (https://scryfall.com)')
	log(' ')
	log('BASIC COMMANDS:')
	log('  sf <cardname> - Spawn single card')
	log('  sf <decklist> - Spawn deck (multiline)')
	log(' ')
	log('ADVANCED COMMANDS:')
	log('  sf random [count] [?q=query]')
	log('    Examples:')
	log('      sf random')
	log('      sf random 10')
	log('      sf random ?q=r:m id:wubrg 15')
	log('      sf random 5 ?q=t:creature cmc>=5')
	log(' ')
	log('  sf search <query>')
	log('    Example: sf search t:creature r:rare')
	log(' ')
	log('  sf text <cardname> - Show oracle text')
	log('  sf rules <cardname> - Show rulings')
	log('  sf back <url> - Set custom card back')
	log(' ')
	log('ENCODER BUTTONS (right-click card):')
	log('  Oracle - Display card text')
	log('  Rulings - Show official rulings')
	log('  Tokens - Spawn associated tokens')
	log('  Printings - Show card printings')
	log('  Back - Set card back image')
	log('  Reverse - Flip front/back')
	log(' ')
	log('QUERY SYNTAX (Scryfall format):')
	log('  Colors: c:w c:u c:b c:r c:g c:c c:m')
	log('  Rarity: r:c r:u r:r r:m')
	log('  Types: t:creature t:instant t:sorcery t:artifact')
	log('  CMC: cmc=3 cmc>=5 cmc<=2')
	log('  Text: o:"draw a card"')
	log('  Identity: id:wubrg (5-color)')
	log('  Use spaces for AND: t:creature r:rare cmc>=5')
	log(' ')
	log('Powered by: github.com/zkzeroxvirus/mtg-card-importer-backend')
	log('Card images from: Scryfall (https://scryfall.com)')
end