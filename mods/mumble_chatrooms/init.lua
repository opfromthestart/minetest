local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

local storage = minetest.get_mod_storage()
local chatrooms = {}
local default_context = storage:get_string("default_context") or "luanti"
local channel = minetest.mod_channel_join("mumble:context")

local function area_contains(pos1, pos2, pos)
	return pos.x >= pos1.x and pos.x <= pos2.x
	   and pos.y >= pos1.y and pos.y <= pos2.y
	   and pos.z >= pos1.z and pos.z <= pos2.z
end

local function get_chatroom_for_pos(pos)
	for name, room in pairs(chatrooms) do
		if area_contains(room.pos1, room.pos2, pos) then
			return name
		end
	end
	return nil
end

local ZONE_BLOCK = "mumble_chatrooms:zone_block"
local ZONE_ENTITY = "mumble_chatrooms:zone_box"

local zone_blocks = {}

local function zone_box_contains(block_pos, hx, hy, hz, player_pos)
	local dx = player_pos.x - (block_pos.x + 0.5)
	local dy = player_pos.y - (block_pos.y + 0.5)
	local dz = player_pos.z - (block_pos.z + 0.5)
	return math.abs(dx) <= hx and math.abs(dy) <= hy and math.abs(dz) <= hz
end

local function get_zone_context_for_pos(pos)
	for pstr, zone in pairs(zone_blocks) do
		if zone.context and zone.context ~= "" then
			local bpos = minetest.string_to_pos(pstr)
			if bpos and zone_box_contains(bpos, zone.hx, zone.hy, zone.hz, pos) then
				return zone.context
			end
		end
	end
	return nil
end

local function get_zone_entry_for_pos(pos)
	for pstr, zone in pairs(zone_blocks) do
		local bpos = minetest.string_to_pos(pstr)
		if bpos and zone_box_contains(bpos, zone.hx, zone.hy, zone.hz, pos) then
			return zone
		end
	end
	return nil
end

local player_zone_touched = {}

local function zone_spawn_box(bpos, hx, hy, hz, visible)
	local ent_pos = {x = bpos.x + 0.5, y = bpos.y + 0.5, z = bpos.z + 0.5}
	local obj = minetest.add_entity(ent_pos, ZONE_ENTITY)
	if not obj then return nil end
	if visible then
		obj:set_properties({
			visual_size = {x = hx * 2, y = hy * 2, z = hz * 2},
		})
	end
	return obj
end

minetest.register_entity(ZONE_ENTITY, {
	initial_properties = {
		visual = "cube",
		visual_size = {x = 0, y = 0, z = 0},
		textures = {"blank.png^[colorize:#00cccc:64"},
		physical = false,
		collide_with_objects = false,
		static_save = false,
		pointable = false,
		glow = 14,
	},
})

local player_context = {}

local function set_player_context(player_name, context)
	player_context[player_name] = context
	channel:send_all(player_name .. "\t" .. context)
end

minetest.register_globalstep(function(dtime)
	local players = minetest.get_connected_players()
	for _, player in ipairs(players) do
		local name = player:get_player_name()
		local pos = player:get_pos()
		local zone = get_zone_entry_for_pos(pos)
		if zone then
			player_zone_touched[name] = true
			local context
			if zone.context and zone.context ~= "" then
				context = zone.context
			else
				context = default_context
			end
			if player_context[name] ~= context then
				local old = player_context[name] or "(none)"
				player_context[name] = context
				set_player_context(name, context)
				minetest.log("action", "[mumble] " .. name .. " entered zone, context: \"" .. old .. "\" -> \"" .. context .. "\"")
			end
		elseif player_zone_touched[name] then
			-- sticky: context unchanged until next zone entry
		else
			local room = get_chatroom_for_pos(vector.round(pos))
			local context
			if room then
				context = default_context .. "." .. room
			else
				context = default_context
			end
			if player_context[name] ~= context then
				local old = player_context[name] or "(none)"
				player_context[name] = context
				set_player_context(name, context)
				minetest.log("action", "[mumble] " .. name .. " context: \"" .. old .. "\" -> \"" .. context .. "\"")
			end
		end
	end

	for name in pairs(player_context) do
		if not minetest.get_player_by_name(name) then
			player_context[name] = nil
		end
	end
end)

minetest.register_on_leaveplayer(function(player)
	local name = player:get_player_name()
	player_context[name] = nil
	player_zone_touched[name] = nil
end)

minetest.register_chatcommand("chatroom", {
	params = "<add|remove|list|default> [name]",
	description = "Manage Mumble chatrooms",
	privs = {server = true},
	func = function(name, param)
		local cmd, arg = param:match("^(%S+)%s*(.*)")
		if not cmd then
			cmd = param
			arg = ""
		end

		if cmd == "add" then
			if arg == "" then
				return false, "Usage: /chatroom add <name> (use WorldEdit pos1/pos2)"
			end
			local player = minetest.get_player_by_name(name)
			if not player then
				return false, "Player not found"
			end
			local pos1 = worldedit and worldedit.pos1 and worldedit.pos1[name]
			local pos2 = worldedit and worldedit.pos2 and worldedit.pos2[name]
			if not pos1 or not pos2 then
				return false, "Set pos1 and pos2 with WorldEdit first"
			end
			local p1 = vector.new(
				math.min(pos1.x, pos2.x),
				math.min(pos1.y, pos2.y),
				math.min(pos1.z, pos2.z))
			local p2 = vector.new(
				math.max(pos1.x, pos2.x),
				math.max(pos1.y, pos2.y),
				math.max(pos1.z, pos2.z))
			chatrooms[arg] = {pos1 = p1, pos2 = p2}
			storage:set_string("chatrooms", minetest.write_json(chatrooms))
			return true, "Chatroom \"" .. arg .. "\" added"
		elseif cmd == "remove" then
			if arg == "" then
				return false, "Usage: /chatroom remove <name>"
			end
			if not chatrooms[arg] then
				return false, "No chatroom named \"" .. arg .. "\""
			end
			chatrooms[arg] = nil
			storage:set_string("chatrooms", minetest.write_json(chatrooms))
			return true, "Chatroom \"" .. arg .. "\" removed"
		elseif cmd == "list" then
			local list = {}
			for name_ in pairs(chatrooms) do
				table.insert(list, name_)
			end
			if #list == 0 then
				return true, "No chatrooms defined"
			end
			table.sort(list)
			return true, "Chatrooms: " .. table.concat(list, ", ")
		elseif cmd == "default" then
			if arg ~= "" then
				default_context = arg
				storage:set_string("default_context", default_context)
				return true, "Default context set to \"" .. default_context .. "\""
			else
				return true, "Default context: \"" .. default_context .. "\""
			end
		else
			return false, "Usage: /chatroom add|remove|list|default [name] (requires server priv)"
		end
	end,
})

minetest.register_on_mods_loaded(function()
	local saved = storage:get_string("chatrooms")
	if saved and saved ~= "" then
		local parsed = minetest.parse_json(saved)
		if parsed then
			chatrooms = parsed
		end
	end
end)

minetest.register_lbm({
	name = "mumble_chatrooms:zone_block_init",
	nodenames = {ZONE_BLOCK},
	run_at_every_load = true,
	action = function(pos, node)
		local pstr = minetest.pos_to_string(pos)
		local meta = minetest.get_meta(pos)
		local context = meta:get_string("context")
		local hx = tonumber(meta:get_string("hx")) or 2
		local hy = tonumber(meta:get_string("hy")) or 50
		local hz = tonumber(meta:get_string("hz")) or 2
		local visible = meta:get_string("visible") == "true"

		if zone_blocks[pstr] and zone_blocks[pstr].entity then
			local ok, got = pcall(function()
				return zone_blocks[pstr].entity:get_pos()
			end)
			if ok and got then
				zone_blocks[pstr].context = context
				zone_blocks[pstr].hx = hx
				zone_blocks[pstr].hy = hy
				zone_blocks[pstr].hz = hz
				zone_blocks[pstr].visible = visible
				return
			end
		end

		local obj = zone_spawn_box(pos, hx, hy, hz, visible)
		zone_blocks[pstr] = {
			context = context,
			hx = hx, hy = hy, hz = hz,
			visible = visible,
			entity = obj,
		}
	end,
})

local function zone_formspec(pos, context, hx, hy, hz, visible)
	local pstr = minetest.pos_to_string(pos)
	local has_ctx = context and context ~= ""
	return "size[6,7]" ..
		"label[0.5,0.3;Zone Block at " .. minetest.formspec_escape(pstr) .. "]" ..
		"dropdown[0.5,1.2;5;ctx_mode;Custom,Default;" .. (has_ctx and "1" or "2") .. "]" ..
		"field[0.5,2.6;5,0.8;context;Context;" .. minetest.formspec_escape(context or "") .. "]" ..
		"field[0.5,3.8;1.5,0.8;hx;Half X;" .. (hx or 2) .. "]" ..
		"field[2.2,3.8;1.5,0.8;hy;Half Y;" .. (hy or 50) .. "]" ..
		"field[3.9,3.8;1.5,0.8;hz;Half Z;" .. (hz or 2) .. "]" ..
		"dropdown[0.5,5;3;visible;Hidden,Visible;" .. (visible and "2" or "1") .. "]" ..
		"button[1.5,6;3,0.8;save;Save]"
end

minetest.register_node(ZONE_BLOCK, {
	description = "Chatroom Zone Block",
	tiles = {"blank.png^[colorize:#00cccc:200"},
	paramtype = "light",
	groups = {oddly_breakable_by_hand = 1},
	on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
		local meta = minetest.get_meta(pos)
		local context = meta:get_string("context")
		local hx = meta:get_string("hx") or "2"
		local hy = meta:get_string("hy") or "50"
		local hz = meta:get_string("hz") or "2"
		local visible = meta:get_string("visible") == "true"
		minetest.show_formspec(clicker:get_player_name(),
			"mumble_chatrooms:zone_" .. minetest.pos_to_string(pos),
			zone_formspec(pos, context, hx, hy, hz, visible))
		return itemstack
	end,
	after_place_node = function(pos, placer)
		local pstr = minetest.pos_to_string(pos)
		local meta = minetest.get_meta(pos)
		meta:set_string("context", "")
		meta:set_string("hx", "2")
		meta:set_string("hy", "50")
		meta:set_string("hz", "2")
		meta:set_string("visible", "false")
		local obj = zone_spawn_box(pos, 2, 50, 2, false)
		zone_blocks[pstr] = {context = "", hx = 2, hy = 50, hz = 2, visible = false, entity = obj}
		minetest.show_formspec(placer:get_player_name(),
			"mumble_chatrooms:zone_" .. pstr,
			zone_formspec(pos, "", 2, 50, 2, false))
	end,
	after_dig_node = function(pos, oldnode, oldmetadata, digger)
		local pstr = minetest.pos_to_string(pos)
		if zone_blocks[pstr] then
			if zone_blocks[pstr].entity then
				pcall(function() zone_blocks[pstr].entity:remove() end)
			end
			zone_blocks[pstr] = nil
		end
	end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
	if not formname:match("^mumble_chatrooms:zone_") then
		return
	end
	local pstr = formname:match("^mumble_chatrooms:zone_(.+)$")
	local pos = minetest.string_to_pos(pstr)
	if not pos then return end
	local node = minetest.get_node(pos)
	if node.name ~= ZONE_BLOCK then return end
	if fields.save then
		local meta = minetest.get_meta(pos)
		local context = ""
		if fields.ctx_mode == "Custom" then
			context = fields.context or ""
		end
		meta:set_string("context", context)
		local hx = tonumber(fields.hx) or 2
		local hy = tonumber(fields.hy) or 50
		local hz = tonumber(fields.hz) or 2
		meta:set_string("hx", tostring(hx))
		meta:set_string("hy", tostring(hy))
		meta:set_string("hz", tostring(hz))
		local want_visible = (fields.visible == "Visible")
		meta:set_string("visible", want_visible and "true" or "false")

		local zone = zone_blocks[pstr]
		if not zone then
			zone = {entity = nil}
		end
		if want_visible then
			if zone.entity then
				local ok, _ = pcall(function() return zone.entity:get_pos() end)
				if ok then
					zone.entity:set_properties({
						visual_size = {x = hx * 2, y = hy * 2, z = hz * 2},
					})
				else
					zone.entity = zone_spawn_box(pos, hx, hy, hz, true)
				end
			else
				zone.entity = zone_spawn_box(pos, hx, hy, hz, true)
			end
		else
			if zone.entity then
				local ok, _ = pcall(function() return zone.entity:get_pos() end)
				if ok then
					zone.entity:set_properties({
						visual_size = {x = 0, y = 0, z = 0},
					})
				end
			end
		end

		zone.context = context
		zone.hx = hx
		zone.hy = hy
		zone.hz = hz
		zone.visible = want_visible
		zone_blocks[pstr] = zone

		minetest.chat_send_player(player:get_player_name(),
			"Zone block updated: context=\"" .. context ..
			"\", hx=" .. hx .. ", hy=" .. hy .. ", hz=" .. hz ..
			", visible=" .. tostring(want_visible))
	end
end)


mumble_chatrooms.player_context = player_context
