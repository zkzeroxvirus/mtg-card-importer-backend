--[[--

moon-mtg-equip

handles equipment attaching

awawa!
made by stella + Lilith
stella.lifeless.space

--]]--

prop_id = "moon-mtg-equip"
version = "1.0.0"
local did_load = false
local deck_ctx_var = "moon-mtg-equip-ctx"

--[[--
feel free to copy this snippet, it's *really* useful for encoder api stuff

translates enc.doXYZ(args) into enc.call("doXYZ", args)
--]]--
local encoder
do
	local mt = {
		__index = function(self, index)
			return function(args) return rawget(self, "object").call("API" .. index, args) end
		end
	}

	encoder = function()
		local object = Global.getVar("Encoder")
		return object ~= nil and setmetatable({ object = object }, mt) or nil
	end
end

-- logic

local function register_module()
	local enc = encoder()
	if enc == nil then return end

	if tonumber(enc.object.getVar("version"):match("%d+%.%d+")) < 4.4 then
		broadcastToAll("encoder version must be >=4.4", { 1, 0, 0, 1 })
		error("bad encoder version")
	end

	enc.registerProperty {
		propID = prop_id,
		name = "Manage Equipment",
		values = { "moon_mtg_equip" },
		tags = "basic,counter",
		visible = false,
		visible_in_hand = 0,

		funcOwner = self,
		activateFunc = "",
	}

	enc.registerValue {
		valueID = "moon_mtg_equip",
		validType = "nil",
		desc = "who up describing they values (when are these ever used)",
		default = {},
	}
end

local function init_card(card)
	if card == nil then return end
	if card.tag ~= "Card" then return end
	if card.getVar('noencode') ~= nil and card.getVar('noencode') == true then return end

	local enc = encoder()
	if enc == nil then return end

	if not enc.objectExists { obj = card } then enc.encodeObject { obj = card } end

	if not enc.propertyExists { propID = prop_id } then return end

	if not enc.objIsPropEnabled { obj = card, propID = prop_id } then
		enc.objEnableProp { obj = card, propID = prop_id }

		enc.rebuildButtons { obj = card }
	end
end

local function equip_data_for(card)
	local enc = encoder()
	if enc == nil then return nil end
	if card == nil or not enc.objectExists { obj = card } then return nil end
	if not enc.propertyExists { propID = prop_id } then return nil end

	local data = enc.objGetPropData { obj = card, propID = prop_id } or {}
	if type(data.moon_mtg_equip) ~= "table" then
		data.moon_mtg_equip = {}
	end
	return data
end

local function equipped_offset(i)
	local col = math.floor(i / 3)
	local row = i % 3
	return Vector(-1.65 - 1.15 * col, 0.05 + row * (-0.05 / 3), -0.75 + row * (2.2 / 3))
end

local function equip_to(deck, to)
	local enc = encoder()
	if enc == nil then return end

	local data = equip_data_for(to)
	if data == nil then return end
	local origin, angles = to.getPosition(), to.getRotation()

	while deck ~= nil and (deck.tag == "Card" or (deck.getObjects ~= nil and #deck.getObjects() > 0)) do
		local card
		if deck.tag == "Card" then
			card = deck
			deck = nil
		else
			card = deck.takeObject {
				position = deck.getPosition(),
				top = true,
				smooth = false,
			}
			deck = deck.remainder or deck
		end

		card.setPosition(to.positionToWorld(equipped_offset(#data.moon_mtg_equip)))
		card.setRotation(angles, false, false)
		card.setScale({ 0.475, 0.475, 0.475 })
		card.locked = true
		to.addAttachment(card)

		local attachments = to.getAttachments() or {}
		table.insert(data.moon_mtg_equip, #attachments)
	end

    enc.objSetPropData { obj = to, propID = prop_id, data = data }
	enc.rebuildButtons { obj = to, immediate = true }
end

-- a little odd way to ensure deduplication
-- but hey, it works :tm:
local function setup_deck_ctx(obj, force)
	if obj == nil then return end
	if obj.getVar(deck_ctx_var) and not force then return end

	obj.addContextMenuItem("equip all to top", function(plycol, objpos, deck)
		if deck.tag ~= "Deck" then return end

		local card = deck.takeObject {
			position = deck.getPosition() + Vector(0, 1, 0),
			top = true,
		}
		deck = deck.remainder or deck

		init_card(card)
		equip_to(deck, card)
	end)

	obj.setVar(deck_ctx_var, true)
end

local function setup_all_deck_ctx(force)
	for _, obj in pairs(getObjects()) do
		if obj.tag == "Deck" then
			setup_deck_ctx(obj, force)
		end
	end
end

local function clean_deck_ctx()
	for _, obj in pairs(getObjects()) do
		if obj.tag == "Deck" then
			obj.clearContextMenu()
			obj.setVar(deck_ctx_var, false)
			setup_deck_ctx(obj, true)
		end
	end
end

-- api calls

function createButtons(params)
	local enc = encoder()
	if enc == nil then return end

	local flip = enc.getFlip { obj = params.obj } or 1
	if flip == -1 then return end

	local equipped = equip_data_for(params.obj)
	if equipped == nil then return end
	if #equipped.moon_mtg_equip == 0 then return end

	params.obj.createButton {
		label = "unequip all",

		position = { 0, 0.28, 0 },
		rotation = { 0, 0, 0 },
		scale = { 0.5, 0.5, 0.5 },
		width = 800,
		height = 300,

		font_size = 125,
		font_color = { 1, 1, 1 },
		color = { 0.1, 0.1, 0.1 },

		tooltip = "unequip all",

		click_function = 'unequip_all',
		function_owner = self,
	}
end

function unequip_all(obj, ply)
	local enc = encoder()
	if enc == nil then return end

	local equipped = equip_data_for(obj)
	if equipped == nil then return end
	if #equipped.moon_mtg_equip == 0 then return end

	local origin = obj.getPosition()
	obj.setPosition(origin + Vector(0, #equipped.moon_mtg_equip + 1, 0))

	for i = #equipped.moon_mtg_equip, 1, -1 do
		local index = tonumber(equipped.moon_mtg_equip[i])
		local new = index and obj.removeAttachment(index - 1) or nil
		if new ~= nil then
			new.setPosition(origin + Vector(0, #equipped.moon_mtg_equip - i + 1, 0))
			new.setScale({ 1, 1, 1 })
			new.locked = false
		end
	end

	enc.objSetPropData { obj = obj, propID = prop_id, data = { moon_mtg_equip = {} } }
	enc.rebuildButtons { obj = obj, immediate = true }
end

-- events

local function load_module()
	if did_load then return end
	did_load = true

	self.addContextMenuItem("Register Module", register_module)
	self.addContextMenuItem("Clean Deck Equip Menus", clean_deck_ctx)
	Wait.condition(register_module, function() return Global.getVar("Encoder") ~= nil end, 30)

	setup_all_deck_ctx(false)
end

function onLoad()
	load_module()
end

function onload()
	load_module()
end

local function handle_object_dropped(ply, obj)
	init_card(obj)
end

function onObjectDrop(ply, obj)
	handle_object_dropped(ply, obj)
end

function onObjectDropped(ply, obj)
	handle_object_dropped(ply, obj)
end

function onObjectSpawn(obj)
	if obj == nil then return end
	if obj.tag ~= "Card" and obj.tag ~= "Deck" then return end

	Wait.frames(function()
		if obj == nil then return end
		if obj.tag == "Card" then
			init_card(obj)
		elseif obj.tag == "Deck" then
			setup_deck_ctx(obj, false)
		end
	end, 10)
end

function onObjectEnterContainer(container, obj)
	if container.tag ~= "Deck" or obj.tag ~= "Card" then return end

	setup_deck_ctx(container)
end

function onObjectEnterZone(zone,obj)
	if obj == nil or not (obj.tag == "Card" or obj.tag == "Deck") then return end
	if obj.getName():lower():find('planechase') then return end

	if obj.tag == "Deck" then
		Wait.frames(function() setup_deck_ctx(obj, false) end, 10)
	end
end

function onObjectLeaveZone(zone, obj)
	if obj == nil or not (obj.tag == "Card" or obj.tag == "Deck") then return end
	if obj.getName():lower():find('planechase') then return end

	if obj.tag == "Deck" then
		Wait.frames(function() setup_deck_ctx(obj, false) end, 10)
	end
end
