local modname = minetest.get_current_modname()
local storage = minetest.get_mod_storage()

home_deco = {}

home_deco.home_owners = {}
home_deco.home_inventories = {}
home_deco.player_home_state = {}
home_deco.saved_player_inventory = {}
home_deco._deco_page = {}
home_deco._deco_search = {}
home_deco._deco_variant = {}  -- base item name when viewing variants, nil otherwise
home_deco._last_context = {}  -- last known zone context per player, persisted
home_deco._item_map = {}      -- {[playername] = {[btn_idx] = item_name}} for button decode

local function load_state()
    local owners = storage:get_string("home_owners")
    if owners ~= "" then
        local parsed = minetest.parse_json(owners)
        if parsed then home_deco.home_owners = parsed end
    end
    local invs = storage:get_string("home_inventories")
    if invs ~= "" then
        local parsed = minetest.parse_json(invs)
        if parsed then home_deco.home_inventories = parsed end
    end
    local ctxs = storage:get_string("last_contexts")
    if ctxs ~= "" then
        local parsed = minetest.parse_json(ctxs)
        if parsed then home_deco._last_context = parsed end
    end
end

local function save_state()
    storage:set_string("home_owners", minetest.write_json(home_deco.home_owners))
    storage:set_string("home_inventories", minetest.write_json(home_deco.home_inventories))
    storage:set_string("last_contexts", minetest.write_json(home_deco._last_context))
end

local function serialize_list(list)
    local out = {}
    for _, stack in ipairs(list) do
        table.insert(out, stack:to_string())
    end
    return out
end

local function deserialize_list(strings)
    local out = {}
    if strings then
        for _, s in ipairs(strings) do
            table.insert(out, s)
        end
    end
    return out
end

minetest.register_chatcommand("home_deco", {
    params = "<claim|unclaim|list> [arg]",
    description = "Manage home decoration assignments",
    privs = {server = true},
    func = function(name, param)
        local cmd, arg = param:match("^(%S+)%s*(.*)")
        if not cmd then
            return false, "Usage: /home_deco claim <player> | unclaim <home_name> | list"
        end

        if cmd == "claim" then
            if arg == "" then
                return false, "Usage: /home_deco claim <player>"
            end
            local context
            local player = minetest.get_player_by_name(name)
            if player then
                local pos = player:get_pos()
                local node = minetest.get_node(pos)
                if node.name == "mumble_chatrooms:zone_block" then
                    local meta = minetest.get_meta(pos)
                    context = meta:get_string("context")
                end
            end
            if not context or context == "" then
                context = mumble_chatrooms.player_context[arg]
                if not context or context == "" then
                    return false, "No zone block at your position and " .. arg .. " has no current context"
                end
            end
            home_deco.home_owners[context] = arg
            save_state()
            return true, "Home \"" .. context .. "\" claimed for " .. arg
        elseif cmd == "unclaim" then
            if arg == "" then
                return false, "Usage: /home_deco unclaim <home_name>"
            end
            home_deco.home_owners[arg] = nil
            save_state()
            return true, "Home \"" .. arg .. "\" unclaimed"
        elseif cmd == "list" then
            local lines = {}
            for h, p in pairs(home_deco.home_owners) do
                table.insert(lines, h .. " -> " .. p)
            end
            if #lines == 0 then
                return true, "No homes claimed"
            end
            table.sort(lines)
            return true, table.concat(lines, "\n")
        else
            return false, "Usage: /home_deco claim <player> | unclaim <home_name> | list"
        end
    end,
})

minetest.register_on_mods_loaded(function()
    load_state()
end)

-- Tool registrations (fallback if default tools unavailable)
if not minetest.registered_tools["default:pick_steel"] then
    minetest.register_tool("home_deco:pickaxe", {
        description = "Home Pickaxe",
        inventory_image = "default_tool_steelpick.png",
        tool_capabilities = {
            full_punch_interval = 1.0,
            max_drop_level = 3,
            groupcaps = {
                cracky = {times = {[1]=4.0, [2]=1.6, [3]=0.8}, uses=30, maxlevel=3},
            },
            damage_groups = {fleshy = 4},
        },
    })
end

if not minetest.registered_tools["default:shovel_steel"] then
    minetest.register_tool("home_deco:shovel", {
        description = "Home Shovel",
        inventory_image = "default_tool_steelshovel.png",
        tool_capabilities = {
            full_punch_interval = 1.0,
            max_drop_level = 3,
            groupcaps = {
                crumbly = {times = {[1]=1.6, [2]=0.8, [3]=0.4}, uses=30, maxlevel=3},
            },
            damage_groups = {fleshy = 3},
        },
    })
end

if not minetest.registered_tools["default:axe_steel"] then
    minetest.register_tool("home_deco:axe", {
        description = "Home Axe",
        inventory_image = "default_tool_steelaxe.png",
        tool_capabilities = {
            full_punch_interval = 1.0,
            max_drop_level = 3,
            groupcaps = {
                choppy = {times = {[1]=3.0, [2]=1.6, [3]=0.8}, uses=30, maxlevel=3},
            },
            damage_groups = {fleshy = 4},
        },
    })
end

local TOOL_NAMES = {"default:pick_steel", "default:shovel_steel", "default:axe_steel"}
if not minetest.registered_tools["default:pick_steel"] then
    TOOL_NAMES = {"home_deco:pickaxe", "home_deco:shovel", "home_deco:axe"}
end

-- sfinv creative block picker page
local NODES_PER_PAGE = 24

local SHAPE_PREFIXES = {
    "stair_", "slab_", "slope_", "micro_", "panel_",
    "inner_stair_", "outer_stair_",
}
-- Must be sorted longest-first so we strip the most specific suffix
table.sort(SHAPE_PREFIXES, function(a, b) return #a > #b end)

local SHAPE_SUFFIXES = {
    "_two_sides", "_alt_2", "_alt_1", "_alt",
    "_outer", "_inner", "_half",
    "_15", "_14", "_12", "_10", "_8", "_6", "_4", "_2", "_1",
}

local function is_shape_variant(name)
    local base = name:gsub("^[^:]*:", "")
    for _, prefix in ipairs(SHAPE_PREFIXES) do
        if base:find("^" .. prefix) then
            return true
        end
    end
    return false
end

local function extract_material(name)
    local base = name:gsub("^[^:]*:", "")
    local had_shape = false
    for _, prefix in ipairs(SHAPE_PREFIXES) do
        local stripped = base:gsub("^" .. prefix, "")
        if stripped ~= base then
            base = stripped
            had_shape = true
            break
        end
    end
    if had_shape then
        for _, suffix in ipairs(SHAPE_SUFFIXES) do
            if base:find(suffix .. "$") then
                base = base:gsub(suffix .. "$", "")
                break
            end
        end
    end
    return base
end

local function get_node_list(base_name)
    local nodes = {}
    for name, def in pairs(minetest.registered_nodes) do
        local is_hidden = def.groups.not_in_creative_inventory and def.groups.not_in_creative_inventory ~= 0
        if base_name then
            -- Use prefix matching with a word boundary (_ or EOS) so that
            -- e.g. "wood" matches "wood_tile" but NOT "wooden" or "woodframed".
            local mat = extract_material(name)
            if mat == base_name or mat:find("^" .. base_name .. "_") then
                table.insert(nodes, {name = name, desc = def.description or name})
            end
        else
            if not is_hidden then
                if not is_shape_variant(name) then
                    table.insert(nodes, {name = name, desc = def.description or name})
                end
            end
        end
    end
    table.sort(nodes, function(a, b) return a.desc:lower() < b.desc:lower() end)
    return nodes
end

local function build_deco_formspec(player, context)
    local name = player:get_player_name()
    local variant = home_deco._deco_variant[name]
    local nodes = get_node_list(variant)
    local search = home_deco._deco_search[name] or ""

    if variant then
        search = ""
    end
    if search ~= "" then
        local lower = search:lower()
        local filtered = {}
        for _, n in ipairs(nodes) do
            if n.name:lower():find(lower, 1, true) or n.desc:lower():find(lower, 1, true) then
                table.insert(filtered, n)
            end
        end
        nodes = filtered
    end

    local page = home_deco._deco_page[name] or 0
    local total_pages = math.floor(#nodes / NODES_PER_PAGE)
    local start_idx = page * NODES_PER_PAGE + 1
    local end_idx = math.min(start_idx + NODES_PER_PAGE - 1, #nodes)
    local row = 0
    local col = 0
    local fs = ""
    local y_offset = 0.8

    if variant then
        local var_desc = variant:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
        fs = fs .. "label[1.5,0.1;" .. minetest.formspec_escape("Variants: " .. var_desc) .. "]"
        fs = fs .. "button[0,0;1.5,0.7;hdd_variant_back;< Back]"
        y_offset = 0.8
    else
        fs = fs .. "field[0,0.1;6,0.7;hdd_search;;" .. minetest.formspec_escape(search) .. "]"
        fs = fs .. "button[5.5,0.1;1,0.7;hdd_search_btn;Search]"
        fs = fs .. "field_close_on_enter[hdd_search;false]"
        if search ~= "" then
            fs = fs .. "button[6.5,0.1;1,0.7;hdd_search_clr;Clear]"
            fs = fs .. "label[0,0.8;" .. minetest.formspec_escape(#nodes .. " matches") .. "]"
            y_offset = 1.3
        end
    end

    if #nodes == 0 then
        fs = fs .. "label[0," .. y_offset .. ";No items to show.]"
        return fs
    end

    local item_map = {}
    local btn_idx = 0
    for i = start_idx, end_idx do
        local n = nodes[i]
        local btn_name = "hdd_item_" .. btn_idx
        item_map[tostring(btn_idx)] = n.name
        btn_idx = btn_idx + 1
        fs = fs .. "item_image_button[" .. col .. "," .. (y_offset + row) .. ";1,1;" .. n.name .. ";" .. btn_name .. ";]"
        fs = fs .. "tooltip[" .. btn_name .. ";" .. minetest.formspec_escape(n.desc) .. "]"
        col = col + 1
        if col >= 8 then
            col = 0
            row = row + 1
        end
    end
    home_deco._item_map[name] = item_map

    if page > 0 then
        fs = fs .. "button[0," .. (y_offset + 3.2) .. ";2,0.8;hdd_page_prev;<< Prev]"
    end
    if page < total_pages then
        fs = fs .. "button[6," .. (y_offset + 3.2) .. ";2,0.8;hdd_page_next;Next >>]"
    end
    if total_pages >= 0 then
        fs = fs .. "label[2.5," .. (y_offset + 3.4) .. ";" .. (page + 1) .. " / " .. (total_pages + 1) .. "]"
    end

    return fs
end

sfinv.register_page("home_deco:deco", {
    title = "Home Decorations",
    is_in_nav = function(self, player, context)
        local name = player:get_player_name()
        return home_deco.player_home_state[name] and true or false
    end,
    get = function(self, player, context)
        local content = build_deco_formspec(player, context)
        return sfinv.make_formspec(player, context, content, true, nil)
    end,
    on_player_receive_fields = function(self, player, context, fields)
        local name = player:get_player_name()
        if fields.hdd_variant_back then
            home_deco._deco_variant[name] = nil
            home_deco._deco_page[name] = 0
            home_deco._deco_search[name] = ""
            sfinv.set_player_inventory_formspec(player, context)
            return true
        end
        if fields.hdd_search_clr then
            home_deco._deco_search[name] = ""
            home_deco._deco_page[name] = 0
            sfinv.set_player_inventory_formspec(player, context)
            return true
        end
        if fields.hdd_search_btn or fields.key_enter_field == "hdd_search" then
            home_deco._deco_search[name] = fields.hdd_search or ""
            home_deco._deco_page[name] = 0
            sfinv.set_player_inventory_formspec(player, context)
            return true
        end
        if fields.hdd_page_next then
            home_deco._deco_page[name] = (home_deco._deco_page[name] or 0) + 1
            sfinv.set_player_inventory_formspec(player, context)
            return true
        end
        if fields.hdd_page_prev then
            home_deco._deco_page[name] = math.max(0, (home_deco._deco_page[name] or 1) - 1)
            sfinv.set_player_inventory_formspec(player, context)
            return true
        end
        for fname, _ in pairs(fields) do
            local btn_suffix = fname:match("^hdd_item_(.+)$")
            if btn_suffix then
                local item_map = home_deco._item_map[name] or {}
                local clean_name = item_map[btn_suffix]
                if not clean_name then
                    sfinv.set_player_inventory_formspec(player, context)
                    return true
                end
                local variant = home_deco._deco_variant[name]
                if variant then
                    -- In variant view: add the item to inventory
                    player:get_inventory():add_item("main", clean_name .. " 99")
                    minetest.log("action", name .. " takes " .. clean_name .. " from home_deco creative inventory")
                    sfinv.set_player_inventory_formspec(player, context)
                else
                    -- In main view: open variant view for this item
                    home_deco._deco_variant[name] = extract_material(clean_name)
                    home_deco._deco_page[name] = 0
                    home_deco._deco_search[name] = ""
                    sfinv.set_player_inventory_formspec(player, context)
                end
                return true
            end
        end
        return false
    end,
})

-- Inventory swap and zone detection
function home_deco.enter_home(player)
    local name = player:get_player_name()
    if home_deco.player_home_state[name] then return end
    local context = mumble_chatrooms.player_context[name]
    if not context then return end
    if home_deco.home_owners[context] ~= name then return end

    local inv = player:get_inventory()

    home_deco.saved_player_inventory[name] = {
        main = serialize_list(inv:get_list("main")),
        craft = serialize_list(inv:get_list("craft")),
    }

    local saved = home_deco.home_inventories[name]
    if saved then
        inv:set_list("main", deserialize_list(saved.main))
        inv:set_list("craft", deserialize_list(saved.craft))
    else
        inv:set_list("main", {})
        inv:set_list("craft", {})
    end

    for _, toolname in ipairs(TOOL_NAMES) do
        local stack = ItemStack(toolname)
        if stack:is_known() then
            stack:get_meta():set_string("home_deco_tool", "1")
            inv:add_item("main", stack)
        end
    end

    home_deco.player_home_state[name] = true
    sfinv.set_player_inventory_formspec(player)
end

function home_deco.exit_home(player)
    local name = player:get_player_name()
    if not home_deco.player_home_state[name] then return end

    local inv = player:get_inventory()
    local main_list = inv:get_list("main")
    local craft_list = inv:get_list("craft")

    local clean_main = {}
    for _, stack in ipairs(main_list) do
        if not stack:is_empty() then
            local meta = stack:get_meta()
            if meta:get_string("home_deco_tool") ~= "1" then
                table.insert(clean_main, stack:to_string())
            end
        end
    end
    home_deco.home_inventories[name] = {
        main = clean_main,
        craft = serialize_list(craft_list),
    }

    local saved = home_deco.saved_player_inventory[name]
    if saved then
        inv:set_list("main", deserialize_list(saved.main))
        inv:set_list("craft", deserialize_list(saved.craft))
    end
    home_deco.saved_player_inventory[name] = nil

    home_deco.player_home_state[name] = false
    home_deco._deco_page[name] = nil
    home_deco._deco_search[name] = nil
    home_deco._deco_variant[name] = nil
    sfinv.set_player_inventory_formspec(player)
end

minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local context = mumble_chatrooms.player_context[name]
        local in_home = home_deco.player_home_state[name]

        if context then
            home_deco._last_context[name] = context
        end

        if in_home then
            local owner = home_deco.home_owners[context or ""]
            if owner ~= name then
                home_deco.exit_home(player)
                save_state()
            end
        else
            local owner = home_deco.home_owners[context or ""]
            if owner == name then
                home_deco.enter_home(player)
            end
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if home_deco.player_home_state[name] then
        local inv = player:get_inventory()
        local main_list = inv:get_list("main")
        local craft_list = inv:get_list("craft")

        -- Save the creative home inventory for next session
        local clean_main = {}
        for _, stack in ipairs(main_list) do
            if not stack:is_empty() then
                local meta = stack:get_meta()
                if meta:get_string("home_deco_tool") ~= "1" then
                    table.insert(clean_main, stack:to_string())
                end
            end
        end
        home_deco.home_inventories[name] = {
            main = clean_main,
            craft = serialize_list(craft_list),
        }

        -- Restore the player's real survival inventory NOW so that
        -- Minetest saves the correct items to the player file on disconnect.
        -- If we don't do this, the swapped creative inventory gets
        -- permanently written to the player's save file.
        local saved = home_deco.saved_player_inventory[name]
        if saved then
            inv:set_list("main", deserialize_list(saved.main))
            inv:set_list("craft", deserialize_list(saved.craft))
        end

        home_deco.player_home_state[name] = false
        home_deco.saved_player_inventory[name] = nil
        home_deco._deco_page[name] = nil
        home_deco._deco_search[name] = nil
        home_deco._deco_variant[name] = nil
        save_state()
    end
end)

minetest.register_on_shutdown(function()
    for name in pairs(home_deco.player_home_state) do
        if home_deco.player_home_state[name] then
            local player = minetest.get_player_by_name(name)
            if player then
                local inv = player:get_inventory()
                local main_list = inv:get_list("main")
                local craft_list = inv:get_list("craft")
                local clean_main = {}
                for _, stack in ipairs(main_list) do
                    if not stack:is_empty() then
                        local meta = stack:get_meta()
                        if meta:get_string("home_deco_tool") ~= "1" then
                            table.insert(clean_main, stack:to_string())
                        end
                    end
                end
                home_deco.home_inventories[name] = {
                    main = clean_main,
                    craft = serialize_list(craft_list),
                }
                local saved = home_deco.saved_player_inventory[name]
                if saved then
                    inv:set_list("main", deserialize_list(saved.main))
                    inv:set_list("craft", deserialize_list(saved.craft))
                end
            end
            home_deco.player_home_state[name] = false
            home_deco.saved_player_inventory[name] = nil
        end
    end
    save_state()
end)

minetest.register_on_joinplayer(function(player)
    sfinv.set_player_inventory_formspec(player)
    local name = player:get_player_name()
    local ctx = home_deco._last_context[name]
    if ctx and home_deco.home_owners[ctx] == name then
        home_deco.enter_home(player)
    end
end)

minetest.register_on_placenode(function(pos, newnode, placer, oldnode, itemstack, pointed_thing)
    if not placer then return end
    local name = placer:get_player_name()
    if not home_deco.player_home_state[name] then return end
    -- Restore the placed item so blocks are never consumed
    local inv = placer:get_inventory()
    inv:add_item("main", newnode.name)
end)
