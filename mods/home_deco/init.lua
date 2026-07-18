local modname = minetest.get_current_modname()
local storage = minetest.get_mod_storage()

home_deco = {}

home_deco.home_owners = {}
home_deco.home_inventories = {}
home_deco.player_home_state = {}
home_deco.saved_player_inventory = {}
home_deco._deco_page = {}

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
end

local function save_state()
    storage:set_string("home_owners", minetest.write_json(home_deco.home_owners))
    storage:set_string("home_inventories", minetest.write_json(home_deco.home_inventories))
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
    for _, s in ipairs(strings) do
        table.insert(out, s)
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

local function get_node_list()
    local nodes = {}
    for name, def in pairs(minetest.registered_nodes) do
        if not def.groups.not_in_creative_inventory or def.groups.not_in_creative_inventory == 0 then
            local desc = def.description or name
            table.insert(nodes, {name = name, desc = desc})
        end
    end
    table.sort(nodes, function(a, b) return a.desc:lower() < b.desc:lower() end)
    return nodes
end

local function build_deco_formspec(player, context)
    local name = player:get_player_name()
    local nodes = get_node_list()
    local page = home_deco._deco_page[name] or 0
    local total_pages = math.floor(#nodes / NODES_PER_PAGE)
    local start_idx = page * NODES_PER_PAGE + 1
    local end_idx = math.min(start_idx + NODES_PER_PAGE - 1, #nodes)
    local row = 0
    local col = 0
    local fs = ""

    for i = start_idx, end_idx do
        local n = nodes[i]
        local btn_name = "hdd_item_" .. n.name:gsub(":", "_")
        fs = fs .. "item_image_button[" .. col .. "," .. row .. ";1,1;" .. n.name .. ";" .. btn_name .. ";]"
        fs = fs .. "tooltip[" .. btn_name .. ";" .. minetest.formspec_escape(n.desc) .. "]"
        col = col + 1
        if col >= 8 then
            col = 0
            row = row + 1
        end
    end

    if page > 0 then
        fs = fs .. "button[0,3.2;2,0.8;hdd_page_prev;<< Prev]"
    end
    if page < total_pages then
        fs = fs .. "button[6,3.2;2,0.8;hdd_page_next;Next >>]"
    end
    fs = fs .. "label[2.5,3.4;" .. (page + 1) .. " / " .. (total_pages + 1) .. "]"

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
        return sfinv.make_formspec(player, context, content, false, nil)
    end,
    on_player_receive_fields = function(self, player, context, fields)
        local name = player:get_player_name()
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
            local itemname = fname:match("^hdd_item_(.+)$")
            if itemname then
                local clean_name = itemname:gsub("_", ":")
                player:get_inventory():add_item("main", clean_name)
                sfinv.set_player_inventory_formspec(player, context)
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
    sfinv.set_player_inventory_formspec(player)
end

minetest.register_globalstep(function(dtime)
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local context = mumble_chatrooms.player_context[name]
        local in_home = home_deco.player_home_state[name]

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

    for name in pairs(home_deco.player_home_state) do
        if not minetest.get_player_by_name(name) then
            if home_deco.player_home_state[name] then
                home_deco.player_home_state[name] = false
            end
            home_deco.saved_player_inventory[name] = nil
        end
    end
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    if home_deco.player_home_state[name] then
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
        save_state()
    end
end)

minetest.register_on_joinplayer(function(player)
    sfinv.set_player_inventory_formspec(player)
end)
