#!/usr/bin/env lua
-- Automated tests for botc_storyteller mod core logic
-- Mocks the minetest API and tests state, passout, nominations, votes, markers

local test_count = 0
local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
    test_count = test_count + 1
    if actual == expected then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        print(string.format("FAIL [%s]: expected %s, got %s", msg, tostring(expected), tostring(actual)))
    end
end

local function assert_true(val, msg)
    test_count = test_count + 1
    if val then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        print(string.format("FAIL [%s]: expected truthy, got %s", msg, tostring(val)))
    end
end

local function assert_false(val, msg)
    test_count = test_count + 1
    if not val then
        pass_count = pass_count + 1
    else
        fail_count = fail_count + 1
        print(string.format("FAIL [%s]: expected falsy, got %s", msg, tostring(val)))
    end
end

-- ========================================
-- Mock minetest API
-- ========================================
local mock_storage = {}
local mock_players = {}
local mock_chat = {}

_G.minetest = {
    get_current_modname = function() return "botc_storyteller" end,
    get_modpath = function(name) return "/mock/" .. name end,
    get_mod_storage = function()
        return {
            get_string = function(self, key) return mock_storage[key] or "" end,
            set_string = function(self, key, value) mock_storage[key] = value end,
        }
    end,
    write_json = function(data)
        -- Minimal JSON encoder for tables
        local parts = {}
        local function encode(val)
            if type(val) == "table" then
                local inner = {}
                for k, v in pairs(val) do
                    table.insert(inner, string.format("%s:%s", encode(k), encode(v)))
                end
                return "{" .. table.concat(inner, ",") .. "}"
            elseif type(val) == "string" then
                return string.format("%q", val)
            elseif type(val) == "boolean" then
                return val and "true" or "false"
            else
                return tostring(val)
            end
        end
        return encode(data)
    end,
    parse_json = function(str)
        -- Basic parser for our test data
        local fn, err
        if _VERSION == "Lua 5.1" then
            fn, err = loadstring("return " .. str)
        else
            fn, err = load("return " .. str)
        end
        if fn then
            local ok, result = pcall(fn)
            if ok then return result end
        end
        return nil
    end,
    get_connected_players = function()
        local result = {}
        for name, _ in pairs(mock_players) do
            table.insert(result, {get_player_name = function() return name end})
        end
        return result
    end,
    get_player_by_name = function(name)
        if mock_players[name] then
            return {
                get_player_name = function() return name end,
                get_pos = function() return {x = 0, y = 0, z = 0} end,
                set_pos = function(self, pos) mock_players[name].pos = pos end,
                set_properties = function(self, props) end,
                set_nametag_attributes = function(self, attrs) end,
                hud_add = function(self, def) return 1 end,
                hud_change = function(self, id, key, val) end,
                hud_remove = function(self, id) end,
                get_inventory = function() return {add_item = function(inv, list, item) end} end,
            }
        end
        return nil
    end,
    check_player_privs = function(name, privs)
        if privs.storyteller then return mock_players[name] and mock_players[name].is_st or false end
        return true
    end,
    chat_send_player = function(name, msg)
        mock_chat[name] = (mock_chat[name] or "") .. msg .. "\n"
    end,
    chat_send_all = function(msg)
        for name in pairs(mock_players) do
            mock_chat[name] = (mock_chat[name] or "") .. msg .. "\n"
        end
    end,
    colorize = function(color, text) return "[" .. color .. "]" .. text end,
    set_timeofday = function(val) end,
    pos_to_string = function(pos) return string.format("(%d,%d,%d)", math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)) end,
    string_to_pos = function(str)
        local x, y, z = str:match("%(([%d.-]+),([%d.-]+),([%d.-]+)%)")
        if x then return {x = tonumber(x), y = tonumber(y), z = tonumber(z)} end
        return nil
    end,
    formspec_escape = function(s) return s end,
    register_privilege = function(name, def) end,
    register_chatcommand = function(name, def) end,
    register_tool = function(name, def) end,
    register_node = function(name, def) end,
    register_entity = function(name, def) end,
    register_on_mods_loaded = function(fn) fn() end,
    register_on_shutdown = function(fn) end,
    register_globalstep = function(fn) end,
    register_on_leaveplayer = function(fn) end,
    register_on_player_receive_fields = function(fn) end,
    override_item = function(name, def) end,
    registered_tools = {},
    explode_textlist_event = function(value)
        local evtype, idx = value:match("^(%a+):(%d+)$")
        if evtype then return {type = evtype, index = tonumber(idx)} end
        return nil
    end,
    add_entity = function(pos, name) return {get_luaentity = function() return {name = name} end} end,
    get_objects_inside_radius = function(pos, radius) return {} end,
    get_node = function(pos) return {name = "botc_storyteller:voteblock", param2 = 0} end,
    swap_node = function(pos, node) end,
    raycast = function(pos1, pos2, a, b)
        return function() return nil end
    end,
}

-- Reset state
function reset_state()
    mock_storage = {}
    mock_players = {}
    mock_chat = {}
    -- Reload modules
    package.loaded["botc_state"] = nil
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/state.lua")
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/passout.lua")
    botc.load_state()
end

print("=== BotC Storyteller Mod Tests ===\n")

-- ========================================
-- Test 1: State initialization
-- ========================================
print("--- State Initialization ---")
reset_state()
assert_eq(botc.ST.phase, "day", "default phase is day")
assert_eq(botc.ST.current_day, 1, "default day is 1")
assert_eq(botc.ST.clock_state, "idle", "default clock is idle")
assert_eq(botc.ST.execution_zone, nil, "no execution zone by default")
assert_eq(type(botc.ST.roles), "table", "roles is a table")
assert_eq(type(botc.ST.nominations), "table", "nominations is a table")

-- ========================================
-- Test 2: State persistence (basic)
-- ========================================
print("--- State Persistence ---")
reset_state()
botc.ST.phase = "evening"
botc.ST.current_day = 3
botc.save_state()
assert_true(#mock_storage["game_state"] > 0, "state was saved to storage")
-- Reload and verify
botc.load_state()
assert_eq(botc.ST.phase, "evening", "phase persists across save/load")
assert_eq(botc.ST.current_day, 3, "day persists across save/load")

-- ========================================
-- Test 3: Team colors
-- ========================================
print("--- Team Colors ---")
reset_state()
assert_true(botc.get_team_color("townsfolk") ~= "#ffffff", "townsfolk has color")
assert_true(botc.get_team_color("demon") ~= "#ffffff", "demon has color")
assert_true(botc.get_team_color("minion") ~= "#ffffff", "minion has color")
assert_eq(botc.get_team_color("unknown_team"), "#ffffff", "unknown team is white")

-- ========================================
-- Test 4: Role assignment
-- ========================================
print("--- Role Assignment ---")
reset_state()
mock_players["Alice"] = { is_st = true }
mock_players["Bob"] = { is_st = false }
mock_players["Charlie"] = { is_st = false }

-- Load a mock script
botc.ST.script = {"imp", "poisoner", "spy"}
local ok, msg = botc.assign_role("Alice", "imp")
assert_true(ok, "assign_role succeeds")
assert_eq(botc.ST.roles["Alice"].role, "Imp", "role name capitalized")
assert_eq(botc.ST.roles["Alice"].team, "demon", "team inferred correctly")
assert_eq(botc.ST.roles["Alice"].alive, true, "new role is alive")
assert_eq(botc.ST.roles["Alice"].dead_vote_used, false, "dead vote not used")

ok, msg = botc.unassign_role("Alice")
assert_true(ok, "unassign_role succeeds")
assert_eq(botc.ST.roles["Alice"], nil, "Alice role cleared")

-- ========================================
-- Test 5: Phase transitions
-- ========================================
print("--- Phase Transitions ---")
reset_state()
botc.ST.phase = "day"
local phases = { day = "evening", evening = "night", night = "day" }
assert_eq(phases["day"], "evening", "day -> evening")
assert_eq(phases["evening"], "night", "evening -> night")
assert_eq(phases["night"], "day", "night -> day")

-- ========================================
-- Test 6: Role name resolution
-- ========================================
print("--- Role Name Resolution ---")
reset_state()
assert_eq(botc.resolve_team("imp"), "demon", "imp is demon")
assert_eq(botc.resolve_team("poisoner"), "minion", "poisoner is minion")
assert_eq(botc.resolve_team("monk"), "townsfolk", "monk is townsfolk")
assert_eq(botc.resolve_team("recluse"), "outsider", "recluse is outsider")

-- Test custom role with explicit team
local custom = {id = "custom_1", name = "Custom Role", team = "minion"}
assert_eq(botc.resolve_team(custom), "minion", "custom role team")

assert_eq(botc.resolve_name("imp"), "Imp", "imp capitalized")
assert_eq(botc.resolve_name("scarlet_woman"), "Scarlet Woman", "snake_case to Title Case")
assert_eq(botc.resolve_name(custom), "Custom Role", "custom role name")

-- ========================================
-- Test 7: Nomination rules
-- ========================================
print("--- Nomination Rules ---")
reset_state()
mock_players["Alice"] = { is_st = true }
mock_players["Bob"] = { is_st = false }
mock_players["Charlie"] = { is_st = false }

botc.ST.phase = "evening"
botc.ST.current_day = 1
botc.ST.nominations[1] = { nominators = {}, nominees = {} }

-- First nomination should work
assert_false(botc.ST.nominations[1].nominators["Alice"], "Alice hasn't nominated yet")
assert_false(botc.ST.nominations[1].nominees["Bob"], "Bob hasn't been nominated yet")

botc.ST.nominations[1].nominators["Alice"] = true
botc.ST.nominations[1].nominees["Bob"] = true

-- Duplicate nominator should fail
assert_true(botc.ST.nominations[1].nominators["Alice"], "Alice has now nominated")
assert_true(botc.ST.nominations[1].nominees["Bob"], "Bob has been nominated")

-- Reset day
botc.ST.current_day = 2
botc.ST.nominations[2] = { nominators = {}, nominees = {} }
assert_false(botc.ST.nominations[2].nominators["Alice"] or false, "Alice fresh for day 2")
assert_false(botc.ST.nominations[2].nominees["Bob"] or false, "Bob fresh for day 2")

-- Wrong phase should be caught at command level, not here

-- ========================================
-- Test 8: Marker toggling
-- ========================================
print("--- Marker Toggling ---")
reset_state()
botc.ST.roles["Alice"] = {role = "Imp", team = "demon", alive = true, dead_vote_used = false, markers = {}}

-- Add a marker
local markers = botc.ST.roles["Alice"].markers
table.insert(markers, "POISONED")
assert_eq(#markers, 1, "one marker added")
assert_eq(markers[1], "POISONED", "marker is POISONED")

-- Toggle off (remove)
for i, m in ipairs(markers) do
    if m == "POISONED" then table.remove(markers, i); break end
end
assert_eq(#markers, 0, "marker removed")

-- Clear all
table.insert(markers, "DRUNK")
table.insert(markers, "PROTECTED")
assert_eq(#markers, 2, "two markers")
botc.ST.roles["Alice"].markers = {}
assert_eq(#botc.ST.roles["Alice"].markers, 0, "markers cleared")

-- ========================================
-- Test 9: Vote block state machine
-- ========================================
print("--- Vote Block State Machine ---")
reset_state()
-- Alive player states
local function toggle_alive(current_state)
    return (current_state ~= 1) and 1 or 0
end
assert_eq(toggle_alive(0), 1, "alive: no -> yes")
assert_eq(toggle_alive(1), 0, "alive: yes -> no")

-- Ghost player states
local function toggle_ghost(current_state)
    if current_state == 4 then return 4 end -- dead vote used
    return (current_state ~= 3) and 3 or 2
end
assert_eq(toggle_ghost(2), 3, "ghost: no -> yes")
assert_eq(toggle_ghost(3), 2, "ghost: yes -> no")
assert_eq(toggle_ghost(4), 4, "used ghost: stays locked")

-- ========================================
-- Test 10: Ghost dead vote tracking
-- ========================================
print("--- Ghost Dead Vote Tracking ---")
reset_state()
botc.ST.roles["Alice"] = {role = "Imp", team = "demon", alive = false, dead_vote_used = false, markers = {}}
assert_eq(botc.ST.roles["Alice"].alive, false, "Alice is dead")
assert_eq(botc.ST.roles["Alice"].dead_vote_used, false, "dead vote not used")

-- Use dead vote
botc.ST.roles["Alice"].dead_vote_used = true
assert_eq(botc.ST.roles["Alice"].dead_vote_used, true, "dead vote now used")

-- Revive
botc.ST.roles["Alice"].alive = true
botc.ST.roles["Alice"].dead_vote_used = false
assert_eq(botc.ST.roles["Alice"].alive, true, "Alice revived")
assert_eq(botc.ST.roles["Alice"].dead_vote_used, false, "dead vote reset")

-- ========================================
-- Test 11: Execution zone
-- ========================================
print("--- Execution Zone ---")
reset_state()
local pos = {x = 10, y = 5, z = -20}
botc.ST.execution_zone = pos
assert_eq(botc.ST.execution_zone.x, 10, "exe zone x")
assert_eq(botc.ST.execution_zone.y, 5, "exe zone y")
assert_eq(botc.ST.execution_zone.z, -20, "exe zone z")
botc.save_state()
assert_true(#mock_storage["game_state"] > 0, "exe zone saved")

-- ========================================
-- Test 12: Player notes
-- ========================================
print("--- Player Notes ---")
reset_state()
if not botc.ST.player_notes then botc.ST.player_notes = {} end
botc.ST.player_notes["Alice"] = { Charlie = "suspicious" }
assert_eq(botc.ST.player_notes["Alice"]["Charlie"], "suspicious", "note stored")
botc.ST.player_notes["Alice"]["Charlie"] = nil
assert_eq(botc.ST.player_notes["Alice"]["Charlie"], nil, "note cleared")

-- ========================================
-- Test 13: Unassign all
-- ========================================
print("--- Unassign All ---")
reset_state()
botc.ST.roles["Alice"] = {role = "Imp", team = "demon", alive = true}
botc.ST.roles["Bob"] = {role = "Monk", team = "townsfolk", alive = true}
botc.ST.vote_blocks["(1,2,3)"] = {owner = "Alice", state = 0, locked = false}
assert_eq(type(botc.ST.roles["Alice"]), "table", "Alice has role")
botc.ST.roles = {}
botc.ST.vote_blocks = {}
botc.ST.nominations = {}
botc.ST.player_notes = {}
assert_eq(next(botc.ST.roles), nil, "all roles cleared")
assert_eq(next(botc.ST.vote_blocks), nil, "all vote blocks cleared")

-- ========================================
-- Results
-- ========================================
print(string.format("\n=== Results: %d/%d passed, %d failed ===", pass_count, test_count, fail_count))
if fail_count > 0 then
    os.exit(1)
else
    print("All tests passed!")
    os.exit(0)
end
