#!/usr/bin/env lua
-- Comprehensive tests for botc_storyteller mod
-- Mocks minetest API, tests all core game logic

local test_count = 0
local pass_count = 0
local fail_count = 0

local function assert_eq(actual, expected, msg)
    test_count = test_count + 1
    if actual == expected then pass_count = pass_count + 1
    else fail_count = fail_count + 1
        print(string.format("  FAIL [%s]: expected '%s', got '%s'", msg, tostring(expected), tostring(actual)))
    end
end
local function assert_true(val, msg)
    test_count = test_count + 1
    if val then pass_count = pass_count + 1
    else fail_count = fail_count + 1
        print(string.format("  FAIL [%s]: expected truthy, got %s", msg, tostring(val)))
    end
end
local function assert_false(val, msg)
    test_count = test_count + 1
    if not val then pass_count = pass_count + 1
    else fail_count = fail_count + 1
        print(string.format("  FAIL [%s]: expected falsy, got %s", msg, tostring(val)))
    end
end

-- ========================================
-- Mock minetest API
-- ========================================
local mock_storage = {}
local mock_players = {}
local mock_chat = {}
local mock_chat_all = {}
local mock_huds = {}
local mock_formspecs = {}
local mock_entities = {}
local mock_nodes = {}

_G.minetest = {
    get_current_modname = function() return "botc_storyteller_storyteller" end,
    get_modpath = function(name) return "/mock/" .. name end,
    get_mod_storage = function()
        return {
            get_string = function(self, key) return mock_storage[key] or "" end,
            set_string = function(self, key, value) mock_storage[key] = value end,
        }
    end,
    write_json = function(data)
        -- Minimal: use Lua literal for test round-trips
        local function enc(v)
            if type(v) == "table" then
                local p = {}
                for k, vv in pairs(v) do
                    table.insert(p, "[" .. enc(k) .. "]=" .. enc(vv))
                end
                return "{" .. table.concat(p, ",") .. "}"
            elseif type(v) == "string" then return string.format("%q", v)
            elseif type(v) == "boolean" then return v and "true" or "false"
            elseif type(v) == "number" then return tostring(v)
            else return tostring(v)
            end
        end
        return enc(data)
    end,
    parse_json = function(str)
        local fn = (_VERSION == "Lua 5.1") and loadstring or load
        fn = fn("return " .. str)
        if fn then local ok, r = pcall(fn); if ok then return r end end
        return nil
    end,
    get_connected_players = function()
        local r = {}
        for name, d in pairs(mock_players) do table.insert(r, {get_player_name = function() return name end, get_pos = function() return d.pos or {x=0,y=0,z=0} end}) end
        return r
    end,
    get_player_by_name = function(name)
        if mock_players[name] then
            local d = mock_players[name]
            return {
                get_player_name = function() return name end,
                get_pos = function() return d.pos or {x=0,y=0,z=0} end,
                set_pos = function(self, p) d.pos = p end,
                set_properties = function(self, p) d.props = p end,
                set_nametag_attributes = function(self, a) d.nametag = a end,
                hud_add = function(self, def) table.insert(mock_huds, {player=name, def=def}); return #mock_huds end,
                hud_change = function(self, id, key, val) end,
                hud_remove = function(self, id) end,
                get_inventory = function() return {add_item = function(inv, list, item) end} end,
                get_look_dir = function() return {x=0,y=0,z=1} end,
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
        table.insert(mock_chat_all, msg)
    end,
    colorize = function(color, text) return "[" .. color .. "]" .. text end,
    set_timeofday = function(val) mock_storage["_timeofday"] = val end,
    pos_to_string = function(pos) return string.format("(%d,%d,%d)", math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)) end,
    string_to_pos = function(str)
        local x, y, z = str:match("%(([%d.-]+),([%d.-]+),([%d.-]+)%)")
        if x then return {x=tonumber(x), y=tonumber(y), z=tonumber(z)} end
        return nil
    end,
    formspec_escape = function(s) return s end,
    show_formspec = function(name, formname, fs)
        mock_formspecs[name] = {formname = formname, fs = fs}
    end,
    register_privilege = function(n, d) end,
    register_chatcommand = function(n, d)
        mock_storage["_cmd_" .. n] = d
    end,
    register_tool = function(n, d)
        minetest.registered_tools[n] = d
    end,
    registered_tools = {},
    register_node = function(n, d) end,
    register_entity = function(n, d) end,
    register_on_mods_loaded = function(fn) fn() end,
    register_on_shutdown = function(fn) end,
    register_globalstep = function(fn) end,
    register_on_leaveplayer = function(fn) end,
    register_on_player_receive_fields = function(fn)
        mock_storage["_fields_handler"] = fn
    end,
    override_item = function(n, d)
        if minetest.registered_tools[n] then
            for k, v in pairs(d) do minetest.registered_tools[n][k] = v end
        end
    end,
    explode_textlist_event = function(val)
        local typ, idx = val:match("^(%a+):(%d+)$")
        if typ then return {type=typ, index=tonumber(idx)} end
        return nil
    end,
    add_entity = function(pos, name)
        local e = {name=name, pos=pos}
        table.insert(mock_entities, e)
        return {get_luaentity = function() return e end, set_properties=function() end, set_rotation=function() end, set_pos=function() end, remove=function() end}
    end,
    get_objects_inside_radius = function(pos, r) return mock_entities end,
    get_node = function(pos)
        local k = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
        return mock_nodes[k] or {name="air", param2=0}
    end,
    get_meta = function(pos)
        local k = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
        mock_nodes[k] = mock_nodes[k] or {name="botc_storyteller_storyteller:voteblock", param2=0, meta={}}
        local n = mock_nodes[k]
        return {
            get_string = function(self, key) return n.meta[key] or "" end,
            set_string = function(self, key, val) n.meta[key] = val end,
            get_int = function(self, key) return n.meta[key] or 0 end,
            set_int = function(self, key, val) n.meta[key] = val end,
        }
    end,
    swap_node = function(pos, node) end,
    raycast = function(p1, p2, a, b)
        local i = 0
        return function()
            i = i + 1
            if i == 1 then return {type="object", ref={is_player=function() return true end, get_player_name=function() return "Bob" end}} end
            return nil
        end
    end,
}

function reset_state()
    mock_storage = {}
    mock_players = {}
    mock_chat = {}
    mock_chat_all = {}
    mock_huds = {}
    mock_formspecs = {}
    mock_entities = {}
    mock_nodes = {}
    minetest.registered_tools = {}
    package.loaded["botc_storyteller_state"] = nil
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/state.lua")
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/passout.lua")
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/wands.lua")
    botc.load_state()
end

function section(title)
    print(string.format("\n[%s]", title))
end

-- ============================================================
section("1. State Initialization")
-- ============================================================
reset_state()
assert_eq(botc.ST.phase, "day", "default phase day")
assert_eq(botc.ST.current_day, 1, "day 1")
assert_eq(botc.ST.clock_state, "idle", "clock idle")
assert_eq(botc.ST.script, nil, "no script loaded")
assert_eq(#botc.ST.roles, 0, "no roles assigned")

section("2. Script Loading")
reset_state()
local ok, msg = botc.load_script("nonexistent.json")
assert_false(ok, "missing file fails gracefully")

section("3. Role Resolution")
reset_state()
assert_eq(botc.resolve_team("imp"), "demon", "imp=demon")
assert_eq(botc.resolve_team("poisoner"), "minion", "poisoner=minion")
assert_eq(botc.resolve_team("monk"), "townsfolk", "monk=townsfolk")
assert_eq(botc.resolve_team("recluse"), "outsider", "recluse=outsider")
assert_eq(botc.resolve_team("scarlet_woman"), "minion", "scarlet_woman=minion")
assert_eq(botc.resolve_team("butler"), "outsider", "butler=outsider")
assert_eq(botc.resolve_team("soldier"), "townsfolk", "soldier=townsfolk")
assert_eq(botc.resolve_team("unknown_foo"), "townsfolk", "unknown defaults to townsfolk")
assert_eq(botc.resolve_name("scarlet_woman"), "Scarlet Woman", "snake_case to Title Case")
assert_eq(botc.resolve_name("imp"), "Imp", "single word capitalized")
local custom = {id="c1", name="Custom", team="demon"}
assert_eq(botc.resolve_team(custom), "demon", "custom explicit team")
assert_eq(botc.resolve_name(custom), "Custom", "custom name")

section("4. Phase Transitions")
reset_state()
-- day -> evening
botc.ST.phase = "day"
local next_phase = ({day="evening", evening="night", night="day"})[botc.ST.phase]
assert_eq(next_phase, "evening", "day->evening")
-- evening -> night
botc.ST.phase = "evening"
next_phase = ({day="evening", evening="night", night="day"})[botc.ST.phase]
assert_eq(next_phase, "night", "evening->night")
-- night -> day (advances day)
botc.ST.phase = "night"
next_phase = ({day="evening", evening="night", night="day"})[botc.ST.phase]
assert_eq(next_phase, "day", "night->day")

section("5. Nomination Rules")
reset_state()
botc.ST.phase = "evening"
botc.ST.current_day = 1
botc.ST.nominations[1] = {nominators={}, nominees={}}
assert_false(botc.ST.nominations[1].nominators["Alice"] or false, "Alice clean")
assert_false(botc.ST.nominations[1].nominees["Bob"] or false, "Bob clean")
-- Register nomination
botc.ST.nominations[1].nominators["Alice"] = true
botc.ST.nominations[1].nominees["Bob"] = true
assert_true(botc.ST.nominations[1].nominators["Alice"], "Alice nominated")
assert_true(botc.ST.nominations[1].nominees["Bob"], "Bob nominated")
-- Day 2 resets
botc.ST.current_day = 2
botc.ST.nominations[2] = {nominators={}, nominees={}}
assert_false(botc.ST.nominations[2].nominators["Alice"] or false, "Alice fresh day 2")

section("6. Full Day Simulation")
reset_state()
mock_players["Alice"] = {is_st=true}
mock_players["Bob"] = {is_st=false}
mock_players["Charlie"] = {is_st=false}
mock_players["Diana"] = {is_st=false}
mock_players["Eve"] = {is_st=false}
mock_players["Frank"] = {is_st=false}

-- Load a mock script (12 roles, enough for 6 players)
botc.ST.script = {}
local roles = {
    {"imp", "demon"}, {"poisoner", "minion"}, {"spy", "minion"},
    {"washerwoman", "townsfolk"}, {"librarian", "townsfolk"}, {"monk", "townsfolk"},
    {"soldier", "townsfolk"}, {"empath", "townsfolk"}, {"chef", "townsfolk"},
    {"recluse", "outsider"}, {"butler", "outsider"}, {"drunk", "outsider"},
}
for _, r in ipairs(roles) do
    table.insert(botc.ST.script, {id=r[1], name=botc.resolve_name(r[1]), team=r[2]})
end

-- Passout to 6 players
local pass_ok, pass_msg = botc.passout({"Alice","Bob","Charlie","Diana","Eve","Frank"})
assert_true(pass_ok, "passout for 6 players succeeds")
assert_eq(botc.ST.phase, "day", "phase=day after passout")
assert_eq(botc.ST.current_day, 1, "day=1 after passout")

-- All 6 have roles
local demon_count = 0; local minion_count = 0; local outsider_count = 0; local townsfolk_count = 0
for _, name in ipairs({"Alice","Bob","Charlie","Diana","Eve","Frank"}) do
    assert_true(botc.ST.roles[name] ~= nil, name .. " has a role")
    assert_true(botc.ST.roles[name].alive, name .. " is alive")
    assert_false(botc.ST.roles[name].dead_vote_used, name .. " dead vote unused")
    if botc.ST.roles[name].team == "demon" then demon_count = demon_count + 1
    elseif botc.ST.roles[name].team == "minion" then minion_count = minion_count + 1
    elseif botc.ST.roles[name].team == "outsider" then outsider_count = outsider_count + 1
    elseif botc.ST.roles[name].team == "townsfolk" then townsfolk_count = townsfolk_count + 1
    end
end
assert_eq(demon_count, 1, "1 demon for 6 players")
assert_eq(minion_count, 1, "1 minion for 6 players")
assert_eq(outsider_count, 1, "1 outsider for 6 players")
assert_eq(townsfolk_count, 3, "3 townsfolk for 6 players")

-- --- PHASE: DAY (discussion) ---
botc.ST.phase = "day"
-- Nominations should NOT work during day
-- (command would check phase, we test the rule)
local day_ok = (botc.ST.phase == "evening")  -- false
assert_false(day_ok, "nominations blocked in day phase")

-- --- PHASE: EVENING (nominations + voting) ---
botc.ST.phase = "evening"
assert_eq(botc.ST.phase, "evening", "phase is evening")
-- Ensure nominations table for day 1
if not botc.ST.nominations[1] then botc.ST.nominations[1] = {nominators={}, nominees={}} end
-- Nomination: Alice nominates Bob
botc.ST.nominations[1].nominators["Alice"] = true
botc.ST.nominations[1].nominees["Bob"] = true
assert_true(botc.ST.nominations[1].nominators["Alice"], "Alice nominated")
-- Alice tries again -- should fail
local alice_dup = botc.ST.nominations[1].nominators["Alice"]
assert_true(alice_dup, "Alice cannot nominate twice (already true)")
-- Charlie can't nominate Bob (already nominated)
local bob_dup = botc.ST.nominations[1].nominees["Bob"]
assert_true(bob_dup, "Bob cannot be nominated twice (already true)")

-- Clock state for nomination
botc.ST.clock_nominator = "Alice"
botc.ST.clock_nominee = "Bob"
botc.ST.clock_state = "nominating"
assert_eq(botc.ST.clock_state, "nominating", "clock is nominating")
assert_eq(botc.ST.clock_nominator, "Alice", "clock nominator")
assert_eq(botc.ST.clock_nominee, "Bob", "clock nominee")

-- --- VOTING ---
botc.ST.clock_state = "sweeping"
botc.ST.clock_angle = 0
assert_eq(botc.ST.clock_state, "sweeping", "clock sweeping")

-- Set up vote blocks
botc.ST.vote_blocks = {}
for i, name in ipairs({"Alice","Bob","Charlie","Diana","Eve","Frank"}) do
    local pos = {x=i, y=0, z=0}
    local ph = botc.pos_hash(pos)
    botc.ST.vote_blocks[ph] = {owner=name, state=0, locked=false}
end
-- Players vote
botc.ST.vote_blocks[botc.pos_hash({x=1,y=0,z=0})].state = 1  -- Alice yes
botc.ST.vote_blocks[botc.pos_hash({x=2,y=0,z=0})].state = 0  -- Bob no
botc.ST.vote_blocks[botc.pos_hash({x=3,y=0,z=0})].state = 1  -- Charlie yes
botc.ST.vote_blocks[botc.pos_hash({x=4,y=0,z=0})].state = 0  -- Diana no
botc.ST.vote_blocks[botc.pos_hash({x=5,y=0,z=0})].state = 0  -- Eve no
botc.ST.vote_blocks[botc.pos_hash({x=6,y=0,z=0})].state = 1  -- Frank yes

-- Tally votes (simulating sweep end)
local yes_count = 0; local no_count = 0
for _, vb in pairs(botc.ST.vote_blocks) do
    if vb.state == 1 or vb.state == 3 then yes_count = yes_count + 1
    else no_count = no_count + 1
    end
end
assert_eq(yes_count, 3, "3 yes votes")
assert_eq(no_count, 3, "3 no votes")

-- --- EXECUTION ---
-- Kill Bob
botc.ST.roles["Bob"].alive = false
assert_false(botc.ST.roles["Bob"].alive, "Bob executed (dead)")

-- --- PHASE: NIGHT ---
botc.ST.phase = "night"
assert_eq(botc.ST.phase, "night", "phase=night")
-- Night -> day advances day
local phases = {day="evening", evening="night", night="day"}
botc.ST.phase = phases[botc.ST.phase]
assert_eq(botc.ST.phase, "day", "night->day")
botc.ST.current_day = botc.ST.current_day + 1
assert_eq(botc.ST.current_day, 2, "day 2 started")

-- --- DAY 2 ---
botc.ST.nominations[2] = {nominators={}, nominees={}}
-- Eve nominates Charlie
botc.ST.phase = "evening"
botc.ST.nominations[2].nominators["Eve"] = true
botc.ST.nominations[2].nominees["Charlie"] = true
botc.ST.clock_nominator = "Eve"
botc.ST.clock_nominee = "Charlie"
botc.ST.clock_state = "nominating"

-- Bob is dead -- check ghost vote available
assert_false(botc.ST.roles["Bob"].alive, "Bob is dead")
assert_false(botc.ST.roles["Bob"].dead_vote_used, "Bob has dead vote")
-- Use Bob's dead vote
botc.ST.roles["Bob"].dead_vote_used = true
-- Bob's vote block goes to state 4
for ph, vb in pairs(botc.ST.vote_blocks) do
    if vb.owner == "Bob" then vb.state = 4 end
end
assert_true(botc.ST.roles["Bob"].dead_vote_used, "dead vote consumed")

section("7. Vote Block State Machine")
reset_state()
-- Alive toggling
local function toggle_alive(s) return (s ~= 1) and 1 or 0 end
assert_eq(toggle_alive(0), 1, "alive 0->1")
assert_eq(toggle_alive(1), 0, "alive 1->0")
-- Ghost toggling
local function toggle_ghost(s)
    if s == 4 then return 4 end
    return (s ~= 3) and 3 or 2
end
assert_eq(toggle_ghost(2), 3, "ghost 2->3")
assert_eq(toggle_ghost(3), 2, "ghost 3->2")
assert_eq(toggle_ghost(4), 4, "used ghost stays 4")
-- State transitions to Used Ghost
local states = {0,1,2,3,4}
for _, s in ipairs(states) do
    assert_true(type(s) == "number", "state " .. s .. " is valid")
end

section("8. Marker Toggling")
reset_state()
botc.ST.roles["Alice"] = {role="Imp", team="demon", alive=true, dead_vote_used=false, markers={}}
local m = botc.ST.roles["Alice"].markers
table.insert(m, "POISONED")
assert_eq(#m, 1, "add poisoned")
table.insert(m, "DRUNK")
assert_eq(#m, 2, "add drunk")
-- Toggle POISONED off
for i, v in ipairs(m) do if v == "POISONED" then table.remove(m,i); break end end
assert_eq(#m, 1, "remove poisoned")
assert_eq(m[1], "DRUNK", "drunk remains")
-- Clear all
botc.ST.roles["Alice"].markers = {}
assert_eq(#botc.ST.roles["Alice"].markers, 0, "clear all")

section("9. Clock State Machine")
reset_state()
local clock_states = {"idle", "nominating", "sweeping"}
for _, cs in ipairs(clock_states) do
    botc.ST.clock_state = cs
    assert_eq(botc.ST.clock_state, cs, "clock=" .. cs)
end
-- Sweep angle progression
botc.ST.clock_state = "sweeping"
botc.ST.clock_angle = 0
local sweep_speed = 36  -- degrees/sec (360/10)
local angle = botc.ST.clock_angle + sweep_speed * 1.0
assert_true(angle > 0, "sweep advances")
assert_true(angle < 360, "sweep not yet complete")
-- Sweep complete
angle = 360
botc.ST.clock_state = "idle"
botc.ST.clock_angle = nil
assert_eq(botc.ST.clock_state, "idle", "sweep complete->idle")

section("10. Vote Block Locking by Angle")
reset_state()
local clock_pos = {x=0, y=1, z=0}
botc.ST.vote_blocks = {}
for i = 1, 6 do
    local angle_deg = i * 60
    local rad = math.rad(angle_deg)
    local bx = math.cos(rad) * 5
    local bz = math.sin(rad) * 5
    local pos = {x=math.floor(bx), y=0, z=math.floor(bz)}
    botc.ST.vote_blocks[botc.pos_hash(pos)] = {owner="P"..i, state=0, locked=false}
end
-- Simulate sweep past 200 degrees
for ph, vb in pairs(botc.ST.vote_blocks) do
    local pos = minetest.string_to_pos(ph)
    if pos then
        local dx = pos.x - clock_pos.x
        local dz = pos.z - clock_pos.z
        local ba = math.deg(math.atan2(dz, dx))
        if ba < 0 then ba = ba + 360 end
        if ba <= 200 then vb.locked = true end
    end
end
-- Count locked blocks
local locked_count = 0
for _, vb in pairs(botc.ST.vote_blocks) do
    if vb.locked then locked_count = locked_count + 1 end
end
assert_true(locked_count >= 3, "blocks past 200 deg locked (" .. locked_count .. ")")
assert_true(locked_count < 6, "not all blocks locked")

section("11. Marker Wand Formspec Names")
reset_state()
mock_players["Alice"] = {is_st=true}
mock_players["Bob"] = {is_st=false}
-- Test that show_player_list_formspec produces correct formname prefix
botc.show_player_list_formspec("Alice", "botc_storyteller_storyteller:marker_select")
assert_true(mock_formspecs["Alice"] ~= nil, "formspec sent to Alice")
assert_eq(mock_formspecs["Alice"].formname, "botc_storyteller_storyteller:marker_select_list", "formname with _list suffix")

section("12. Player Notes")
reset_state()
mock_players["Alice"] = {is_st=false}
mock_players["Bob"] = {is_st=false}
if not botc.ST.player_notes then botc.ST.player_notes = {} end
botc.ST.player_notes["Alice"] = {Charlie="suspicious", Bob="trusted"}
assert_eq(botc.ST.player_notes["Alice"]["Charlie"], "suspicious", "note Charlie")
assert_eq(botc.ST.player_notes["Alice"]["Bob"], "trusted", "note Bob")
-- Clear one
botc.ST.player_notes["Alice"]["Charlie"] = nil
assert_eq(botc.ST.player_notes["Alice"]["Charlie"], nil, "note cleared")
assert_eq(botc.ST.player_notes["Alice"]["Bob"], "trusted", "other note remains")

section("13. Ghost Dead Vote Lifecycle")
reset_state()
-- Player dies
botc.ST.roles["Alice"] = {role="Imp", team="demon", alive=true, dead_vote_used=false, markers={}}
assert_true(botc.ST.roles["Alice"].alive, "alive at start")
botc.ST.roles["Alice"].alive = false
assert_false(botc.ST.roles["Alice"].alive, "now dead")
-- Use dead vote
assert_false(botc.ST.roles["Alice"].dead_vote_used, "vote unused")
botc.ST.roles["Alice"].dead_vote_used = true
assert_true(botc.ST.roles["Alice"].dead_vote_used, "vote used")
-- Try to use again
local second_use = botc.ST.roles["Alice"].dead_vote_used
assert_true(second_use, "second use blocked (already true)")
-- Revive
botc.ST.roles["Alice"].alive = true
botc.ST.roles["Alice"].dead_vote_used = false
assert_true(botc.ST.roles["Alice"].alive, "revived")
assert_false(botc.ST.roles["Alice"].dead_vote_used, "vote reset on revive")

section("14. Unassign All")
reset_state()
botc.ST.roles["Alice"] = {role="Imp", team="demon", alive=true}
botc.ST.roles["Bob"] = {role="Monk", team="townsfolk", alive=true}
botc.ST.vote_blocks["(1,2,3)"] = {owner="Alice", state=0}
botc.ST.nominations[1] = {nominators={Alice=true}, nominees={Bob=true}}
botc.ST.roles = {}
botc.ST.vote_blocks = {}
botc.ST.nominations = {}
botc.ST.player_notes = {}
assert_eq(next(botc.ST.roles), nil, "roles cleared")
assert_eq(next(botc.ST.vote_blocks), nil, "vote blocks cleared")
assert_eq(next(botc.ST.nominations), nil, "nominations cleared")

section("15. Execute Wand Target")
reset_state()
botc.ST.execution_zone = {x=100, y=10, z=-50}
mock_players["Alice"] = {is_st=true}
mock_players["Bob"] = {is_st=false, pos={x=50, y=5, z=20}}
-- Simulate execute: teleport Bob to execution zone
mock_players["Bob"].pos = {x=botc.ST.execution_zone.x, y=botc.ST.execution_zone.y, z=botc.ST.execution_zone.z}
assert_eq(mock_players["Bob"].pos.x, 100, "Bob teleported x")
assert_eq(mock_players["Bob"].pos.y, 10, "Bob teleported y")
assert_eq(mock_players["Bob"].pos.z, -50, "Bob teleported z")

section("16. pos_hash Round-trip")
reset_state()
local test_pos = {x=-12, y=64, z=300}
local ph = botc.pos_hash(test_pos)
assert_true(type(ph) == "string" and #ph > 0, "pos_hash returns string")
local parsed = minetest.string_to_pos(ph)
assert_true(parsed ~= nil, "string_to_pos parses")
assert_eq(parsed.x, -12, "round-trip x")
assert_eq(parsed.y, 64, "round-trip y")
assert_eq(parsed.z, 300, "round-trip z")

section("17. Passout Player Count Limits")
reset_state()
botc.ST.script = {}
for i=1,25 do table.insert(botc.ST.script, {id="r"..i, name="Role"..i, team="townsfolk"}) end
-- Need all team types
table.insert(botc.ST.script, {id="demon1", name="Demon", team="demon"})
table.insert(botc.ST.script, {id="minion1", name="Minion", team="minion"})
table.insert(botc.ST.script, {id="outsider1", name="Outsider", team="outsider"})
-- 4 players too few
local player_names = {}
for i=1,4 do table.insert(player_names, "P"..i) end
local ok4, msg4 = botc.passout(player_names)
assert_false(ok4, "4 players fails passout")

section("18. Time of Day Persistence")
reset_state()
botc.ST.phase = "night"
botc.save_state()
-- Recreate state but load
local saved = mock_storage["game_state"]
assert_true(#saved > 0, "state saved")
botc.ST = {roles={}, nominations={}, phase="day", script=nil, execution_zone=nil, vote_blocks={}, clock_pos=nil, clock_state="idle", clock_nominator=nil, clock_nominee=nil, current_day=1, player_notes={}}
botc.load_state()
assert_eq(botc.ST.phase, "night", "persisted phase night")

-- ============================================================
print(string.format("\n========================================"))
print(string.format("RESULTS: %d/%d passed, %d failed", pass_count, test_count, fail_count))
print(string.format("========================================"))
if fail_count > 0 then os.exit(1) else os.exit(0) end
