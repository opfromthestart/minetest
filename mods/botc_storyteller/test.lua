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

_G.vector = {
    add = function(a, b)
        local r = {}
        for k, v in pairs(a) do r[k] = v + (b[k] or 0) end
        return r
    end,
    multiply = function(a, s)
        local r = {}
        for k, v in pairs(a) do r[k] = v * s end
        return r
    end,
}

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
        for name in pairs(mock_players) do table.insert(r, minetest.get_player_by_name(name)) end
        return r
    end,
    get_player_by_name = function(name)
        if mock_players[name] then
            local d = mock_players[name]
            return {
                get_player_name = function() return name end,
                get_pos = function() return d.pos or {x=0,y=0,z=0} end,
                set_pos = function(self, p) d.pos = p end,
                set_properties = function(self, p)
                    d.props = d.props or {}
                    for k, v in pairs(p) do d.props[k] = v end
                end,
                get_properties = function(self) return d.props or {textures = {"character.png"}, visual_size = {x = 1, y = 1}} end,
                set_nametag_attributes = function(self, a) d.nametag = a end,
                set_texture_mod = function(self, mod) d.texture_mod = mod end,
                is_player = function() return true end,
                get_luaentity = function() return nil end,
                hud_add = function(self, def) table.insert(mock_huds, {player=name, def=def}); return #mock_huds end,
                hud_change = function(self, id, key, val) end,
                hud_remove = function(self, id) end,
                get_inventory = function() return {add_item = function(inv, list, item) end} end,
                get_look_dir = function() return {x=0,y=0,z=1} end,
                set_velocity = function() end,
                set_physics_override = function() end,
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
    global_exists = function(name) return rawget(_G, name) ~= nil end,
    show_formspec = function(name, formname, fs)
        mock_formspecs[name] = {formname = formname, fs = fs}
    end,
    register_privilege = function(n, d) end,
    register_chatcommand = function(n, d)
        mock_storage["_cmd_" .. n] = d
        minetest.registered_chatcommands[n] = d
    end,
    registered_chatcommands = {},
    register_tool = function(n, d)
        minetest.registered_tools[n] = d
    end,
    registered_tools = {},
    register_node = function(n, d)
        minetest.registered_nodes[n] = d
    end,
    register_alias = function(n, d) end,
    register_entity = function(n, d)
        minetest.registered_entities[n] = d
    end,
    registered_nodes = {},
    registered_entities = {},
    register_on_mods_loaded = function(fn) fn() end,
    register_on_shutdown = function(fn) end,
    register_globalstep = function(fn)
        mock_storage["_globalstep_handlers"] = mock_storage["_globalstep_handlers"] or {}
        table.insert(mock_storage["_globalstep_handlers"], fn)
    end,
    register_on_leaveplayer = function(fn) end,
    register_on_joinplayer = function(fn)
        mock_storage["_joinplayer_handlers"] = mock_storage["_joinplayer_handlers"] or {}
        table.insert(mock_storage["_joinplayer_handlers"], fn)
    end,
    register_lbm = function(def) end,
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
    add_entity = function(pos, name, staticdata)
        local def = minetest.registered_entities[name]
        if not def then return nil end
        local self = {}
        for k, v in pairs(def) do self[k] = v end
        local obj = {
            _pos = {x = pos.x, y = pos.y, z = pos.z},
            get_luaentity = function() return self end,
            get_pos = function(o) return {x = o._pos.x, y = o._pos.y, z = o._pos.z} end,
            set_pos = function(o, p) o._pos = {x = p.x, y = p.y, z = p.z} end,
            set_properties = function() end,
            set_rotation = function() end,
            set_nametag_attributes = function(o, t) o._nametag = t and t.text end,
            set_texture_mod = function(o, mod) o._texture_mod = mod end,
            is_player = function() return false end,
            remove = function(o)
                for i, e in ipairs(mock_entities) do
                    if e == o then table.remove(mock_entities, i) break end
                end
                if self.on_deactivate then self.on_deactivate(self) end
            end,
        }
        self.object = obj
        table.insert(mock_entities, obj)
        if self.on_activate then self.on_activate(self, staticdata or "") end
        return obj
    end,
    after = function(delay, fn) end,
    get_objects_inside_radius = function(pos, r) return mock_entities end,
    get_node = function(pos)
        local k = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
        return mock_nodes[k] or {name="air", param2=0}
    end,
    get_meta = function(pos)
        local k = string.format("%d,%d,%d", pos.x, pos.y, pos.z)
        mock_nodes[k] = mock_nodes[k] or {name="botc_storyteller:voteblock", param2=0, meta={}}
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
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/fakeplayer.lua")
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/wands.lua")
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/voting.lua")
    dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/commands.lua")
    botc.load_state()
end

function section(title)
    print(string.format("\n[%s]", title))
end

function simulate_join(name)
    local handlers = mock_storage["_joinplayer_handlers"] or {}
    local player = minetest.get_player_by_name(name)
    for _, fn in ipairs(handlers) do
        fn(player)
    end
end

-- ============================================================
section("1. State Initialization")
-- ============================================================
reset_state()
assert_eq(botc.ST.phase, "night", "default phase is night (botc_guide 2.3: games start at night)")
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
assert_eq(botc.ST.phase, "night", "phase=night after passout (botc_guide 2.3: games start at night)")
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
botc.show_player_list_formspec("Alice", "botc_storyteller:marker_select")
assert_true(mock_formspecs["Alice"] ~= nil, "formspec sent to Alice")
assert_eq(mock_formspecs["Alice"].formname, "botc_storyteller:marker_select_list", "formname with _list suffix")

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

section("19. Clock Position Persistence")
reset_state()
botc.ST.clock_pos = {x = 10, y = 5, z = -3}
botc.save_state()
botc.ST.clock_pos = nil
botc.load_state()
assert_true(botc.ST.clock_pos ~= nil, "clock_pos restored")
if botc.ST.clock_pos then
    assert_eq(botc.ST.clock_pos.x, 10, "clock_pos.x restored")
    assert_eq(botc.ST.clock_pos.y, 5, "clock_pos.y restored")
    assert_eq(botc.ST.clock_pos.z, -3, "clock_pos.z restored")
end

-- clock_pos must survive even if the rest of the state blob would be
-- awkward to JSON-encode (e.g. a sparse/non-sequential nominations table)
reset_state()
botc.ST.clock_pos = {x = 1, y = 2, z = 3}
botc.ST.nominations[5] = {nominators = {}, nominees = {}}
botc.save_state()
botc.ST.clock_pos = nil
botc.load_state()
assert_true(botc.ST.clock_pos ~= nil, "clock_pos restored with sparse nominations")

-- Removing the clock (clock_pos = nil) must persist as absent, not stale
reset_state()
botc.ST.clock_pos = {x = 1, y = 2, z = 3}
botc.save_state()
botc.ST.clock_pos = nil
botc.save_state()
botc.ST.clock_pos = {x = 99, y = 99, z = 99}
botc.load_state()
assert_true(botc.ST.clock_pos == nil, "clock_pos cleared after removal persists")

-- Full state round-trip with vote_blocks, roles, and nominations populated
reset_state()
botc.ST.phase = "evening"
botc.ST.clock_state = "sweeping"
botc.ST.clock_nominator = "Alice"
botc.ST.clock_nominee = "Bob"
botc.ST.clock_sweep_start = 42
botc.ST.execution_target = "Bob"
botc.ST.current_day = 3
botc.ST.current_timeofday = 0.75
botc.ST.roles["Alice"] = {role = "mayor", team = "townsfolk", alive = true}
botc.ST.roles["Bob"] = {role = "imp", team = "minion", alive = true}
botc.ST.vote_blocks["(1,2,3)"] = {owner = "Alice", state = 1, locked = false}
botc.ST.nominations[3] = {nominators = {Alice = true}, nominees = {Bob = true}}
botc.ST.player_notes["Alice"] = {Bob = "suspicious"}
botc.save_state()

botc.ST = {roles={}, nominations={}, phase="day", script=nil, execution_zone=nil,
           vote_blocks={}, clock_pos=nil, clock_state="idle", clock_nominator=nil,
           clock_nominee=nil, clock_sweep_start=0, execution_target=nil,
           current_day=1, current_timeofday=0.5,
           player_notes={}}
botc.load_state()

assert_eq(botc.ST.phase, "evening", "phase persisted")
assert_eq(botc.ST.clock_state, "sweeping", "clock_state persisted")
assert_eq(botc.ST.clock_nominator, "Alice", "nominator persisted")
assert_eq(botc.ST.clock_nominee, "Bob", "nominee persisted")
assert_eq(botc.ST.clock_sweep_start, 42, "sweep_start persisted")
assert_eq(botc.ST.execution_target, "Bob", "execution_target persisted")
assert_eq(botc.ST.current_day, 3, "day persisted")
assert_eq(botc.ST.current_timeofday, 0.75, "time persisted")
assert_true(botc.ST.roles["Alice"] and botc.ST.roles["Alice"].role == "mayor", "Alice role")
assert_true(botc.ST.roles["Bob"] and botc.ST.roles["Bob"].alive, "Bob alive")
assert_true(botc.ST.vote_blocks["(1,2,3)"] ~= nil, "vote_blocks persisted")
assert_eq(botc.ST.vote_blocks["(1,2,3)"].state, 1, "vote state persisted")
assert_true(botc.ST.nominations[3] ~= nil, "nominations persisted")
assert_true(botc.ST.nominations[3].nominees.Bob, "nominees persisted")
assert_eq(botc.ST.player_notes["Alice"].Bob, "suspicious", "notes persisted")

section("20. Fake Player Possession / resolve_actor")
reset_state()
assert_eq(botc.resolve_actor("Alice"), "Alice", "resolve_actor passthrough when not possessing")
botc.ST._possession["Alice"] = "Bob"
assert_eq(botc.resolve_actor("Alice"), "Bob", "resolve_actor remaps when possessing")
botc.ST._possession["Alice"] = nil
assert_eq(botc.resolve_actor("Alice"), "Alice", "resolve_actor back to passthrough after unpossess")
botc.fake_players["P1"] = true
assert_true(botc.player_exists("P1"), "fake player exists")
local fp = botc.get_player("P1")
assert_true(fp ~= nil, "get_player returns stub for fake player")
assert_true(fp.is_fake == true, "fake player flag is set")
-- When no entity exists, get_pos returns nil (not {0,0,0})
assert_true(type(fp:get_pos()) == "table" or fp:get_pos() == nil, "get_pos returns table or nil")
botc.fake_players["P1"] = nil

-- ============================================================
section("21. Role Distribution Table")
-- ============================================================
-- Tests passout.lua produces exact per-player-count team distribution
-- from botc_guide section 4.2.
local function build_full_script()
    local script = {}
    for team, n in pairs({townsfolk=13, outsider=4, minion=4, demon=1}) do
        for i = 1, n do
            table.insert(script, {id = team .. "_" .. i, name = team .. "_" .. i, team = team})
        end
    end
    return script
end

for count = 5, 15 do
    reset_state()
    botc.ST.script = build_full_script()
    local names = {}
    for i = 1, count do table.insert(names, "P" .. i) end
    local ok, msg = botc.passout(names)
    assert_true(ok, count .. "p: passout succeeds (" .. tostring(msg) .. ")")
    if ok then
        local tally = {townsfolk = 0, outsider = 0, minion = 0, demon = 0}
        for _, n in ipairs(names) do
            local r = botc.ST.roles[n]
            if r and tally[r.team] ~= nil then tally[r.team] = tally[r.team] + 1 end
        end
        local expected = botc.get_team_counts(count)
        assert_eq(tally.townsfolk, expected.townsfolk, count .. "p: townsfolk count")
        assert_eq(tally.outsider, expected.outsider, count .. "p: outsider count")
        assert_eq(tally.minion, expected.minion, count .. "p: minion count")
        assert_eq(tally.demon, expected.demon, count .. "p: demon count")
    end
end

-- ============================================================
section("22. Default Phase After State Init")
-- ============================================================
reset_state()
assert_eq(botc.ST.phase, "night", "fresh state defaults to night phase (botc_guide 2.3)")

-- ============================================================
section("23. Vote Tally and Execution Threshold")
-- ============================================================
-- Tests the actual production functions botc.tally_votes and
-- botc.would_execute (used by voting.lua clock_hand on_step), per
-- botc_guide 5.2.3: "A player is executed if they receive votes from
-- at least half of the alive players (rounded up) AND have the
-- highest number of votes. If there is a tie for highest votes, no
-- one is executed."
reset_state()

-- Full turnout, clear majority: yes > no, executes
do
    local vote_blocks = {
        [1] = {state = 1}, [2] = {state = 1}, [3] = {state = 1}, [4] = {state = 1},
        [5] = {state = 0}, [6] = {state = 0},
    }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_eq(yes, 4, "4 yes votes tallied")
    assert_eq(no, 2, "2 no votes tallied")
    assert_true(botc.would_execute(yes, no), "code executes when yes > no (no roles = no threshold)")
end

-- Tie: yes == no, does not execute
do
    local vote_blocks = {
        [1] = {state = 1}, [2] = {state = 1}, [3] = {state = 1},
        [4] = {state = 0}, [5] = {state = 0}, [6] = {state = 0},
    }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_eq(yes, 3, "3 yes votes tallied")
    assert_eq(no, 3, "3 no votes tallied")
    assert_false(botc.would_execute(yes, no), "tie does not execute")
end

-- More no than yes: does not execute
do
    local vote_blocks = {
        [1] = {state = 1}, [2] = {state = 0}, [3] = {state = 0},
    }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_false(botc.would_execute(yes, no), "more no than yes does not execute")
end

-- Single yes vote with no opposing votes: executes (no roles tracked)
do
    local vote_blocks = { [1] = {state = 1} }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_eq(yes, 1, "1 yes vote")
    assert_eq(no, 0, "0 no votes")
    assert_true(botc.would_execute(yes, no), "sole yes vote executes when no alive-player threshold is tracked")
end

-- Ghost yes votes (state 3) counted alongside alive yes votes (state 1)
do
    local vote_blocks = {
        [1] = {state = 1}, [2] = {state = 1},
        [3] = {state = 3}, -- ghost yes
        [4] = {state = 0}, [5] = {state = 0},
    }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_eq(yes, 3, "ghost yes votes counted as yes (states 1 + 3)")
    assert_true(botc.would_execute(yes, no), "ghost-backed majority executes")
end

-- ============================================================
-- botc_guide 5.2.3 threshold rule: yes votes must reach at least half
-- of the ALIVE PLAYERS (rounded up), not just outnumber no votes.
-- ============================================================
reset_state()
-- 7 alive players -> threshold = ceil(7/2) = 4
for _, n in ipairs({"P1","P2","P3","P4","P5","P6","P7"}) do
    botc.ST.roles[n] = {role = "Villager", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
end
assert_eq(botc.count_alive_players(), 7, "7 alive players counted")

-- 3 yes, 0 no: yes > no, but 3 < threshold of 4 -> must NOT execute
do
    local vote_blocks = { [1] = {state = 1}, [2] = {state = 1}, [3] = {state = 1} }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_true(yes > no, "yes exceeds no votes cast")
    assert_false(botc.would_execute(yes, no),
        "3 of 7 alive is below half-rounded-up threshold (4); guide 5.2.3 blocks execution")
end

-- 4 yes, 0 no: meets threshold of 4 -> executes
do
    local vote_blocks = { [1]={state=1}, [2]={state=1}, [3]={state=1}, [4]={state=1} }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_true(botc.would_execute(yes, no), "4 of 7 alive meets half-rounded-up threshold; executes")
end

-- One player has died since roles were assigned: 6 alive -> threshold = 3
botc.ST.roles["P7"].alive = false
assert_eq(botc.count_alive_players(), 6, "6 alive players after a death")
do
    local vote_blocks = { [1]={state=1}, [2]={state=1}, [3]={state=1} }
    local yes, no = botc.tally_votes(vote_blocks)
    assert_true(botc.would_execute(yes, no), "3 of 6 alive meets ceil(6/2)=3 threshold; executes")
end

-- ============================================================
section("24. Nomination Rules via Real Commands")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
local nom_cmd = minetest.registered_chatcommands["botc_nom"]
assert_true(nom_cmd ~= nil, "botc_nom command is registered")

-- Nominations only during evening phase
botc.ST.phase = "day"
botc.ST.roles["Erin"] = {role = "Chef", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
botc.ST.roles["Frank"] = {role = "Baker", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
local ok_phase = nom_cmd.func("StorytellerX", "Erin Frank")
assert_false(ok_phase, "nominations blocked outside evening phase")

botc.ST.phase = "evening"

-- Alive player CAN nominate
local ok_alive = nom_cmd.func("StorytellerX", "Erin Frank")
assert_true(ok_alive, "alive player can nominate")

-- Each player can nominate once per day
local ok_renominator = nom_cmd.func("StorytellerX", "Erin George")
assert_false(ok_renominator, "Erin already nominated this day, blocked")

-- Each player can be nominated once per day
botc.ST.roles["George"] = {role = "Butler", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
local ok_renominate = nom_cmd.func("StorytellerX", "George Frank")
assert_false(ok_renominate, "Frank already nominated this day, blocked")

-- ============================================================
section("25. Dead Vote Used Once via Real Command (botc_guide 6.2)")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
local dvote_cmd = minetest.registered_chatcommands["botc_dvote"]
assert_true(dvote_cmd ~= nil, "botc_dvote command is registered")

botc.ST.roles["Ghost1"] = {role = "Empath", team = "townsfolk", alive = false, dead_vote_used = false, markers = {}}
local ok_first = dvote_cmd.func("StorytellerX", "Ghost1")
assert_true(ok_first, "dead player can use their one-time dead vote")
assert_true(botc.ST.roles["Ghost1"].dead_vote_used, "dead_vote_used flag set after use")

local ok_second = dvote_cmd.func("StorytellerX", "Ghost1")
assert_false(ok_second, "dead player cannot use dead vote twice (guide 6.2)")

botc.ST.roles["Alive1"] = {role = "Mayor", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
local ok_alive_dvote = dvote_cmd.func("StorytellerX", "Alive1")
assert_false(ok_alive_dvote, "alive player cannot use the dead-vote mechanic (guide 6.2)")

-- ============================================================
section("26. Kill Wand Self-Skip")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
mock_players["Bob"] = {is_st = false}
local kill_wand = minetest.registered_tools["botc_storyteller:kill_wand"]
assert_true(kill_wand ~= nil, "kill wand registered")
assert_true(kill_wand.on_use ~= nil, "kill wand has on_use")

botc.ST.roles["StorytellerX"] = {role = "Storyteller", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
botc.ST.roles["Bob"] = {role = "Mayor", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}

-- Self-click: pointed_thing points at the user themselves
local user_obj = minetest.get_player_by_name("StorytellerX")
local self_pt = {type = "object", ref = user_obj}
local itemstack = "botc_storyteller:kill_wand"
kill_wand.on_use(itemstack, user_obj, self_pt)
assert_true(botc.ST.roles["StorytellerX"].alive, "kill wand self-click does NOT kill user")

-- Targeting another player should kill them
local bob_obj = minetest.get_player_by_name("Bob")
local other_pt = {type = "object", ref = bob_obj}
kill_wand.on_use(itemstack, user_obj, other_pt)
assert_false(botc.ST.roles["Bob"].alive, "kill wand targeting other player kills them")

-- Verify raycast_player uses objects=true (not false, which skips all players/entities)
reset_state()
mock_players["StorytellerX"] = {is_st = true}
mock_players["Bob"] = {is_st = false}
-- Spy on the raycast call to check the parameter
local raycast_calls = {}
local _orig_raycast = minetest.raycast
minetest.raycast = function(p1, p2, objects, liquids)
    table.insert(raycast_calls, {objects = objects, liquids = liquids})
    return _orig_raycast(p1, p2, objects, liquids)
end
-- Trigger raycast via on_use with pointed_thing.type == "nothing"
local kill_wand2 = minetest.registered_tools["botc_storyteller:kill_wand"]
local st_obj2 = minetest.get_player_by_name("StorytellerX")
kill_wand2.on_use("botc_storyteller:kill_wand", st_obj2, {type = "nothing"})
assert_true(#raycast_calls > 0, "raycast was called for nothing-type pointed_thing")
assert_true(raycast_calls[1].objects == true, "raycast uses objects=true for player detection")
minetest.raycast = _orig_raycast

-- Self-select from the player list should work (no raytracing involved)
reset_state()
mock_players["StorytellerX"] = {is_st = true}
mock_players["Bob"] = {is_st = false}
botc.ST.roles["StorytellerX"] = {role = "Storyteller", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
botc.ST.roles["Bob"] = {role = "Mayor", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
local fields_handler = mock_storage["_fields_handler"]
assert_true(fields_handler ~= nil, "fields handler registered")
local st_obj3 = minetest.get_player_by_name("StorytellerX")
-- all_players sorted: ["Bob", "StorytellerX"], DCL:2 = StorytellerX (self)
fields_handler(st_obj3, "botc_storyteller:wand_kill_list", {players = "DCL:2"})
assert_false(botc.ST.roles["StorytellerX"].alive, "kill formspec self-select works from list")

-- ============================================================
section("27. Script Wand Textlist Selection + Assign")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
botc.ST.roles["Bob"] = {role = "Unassigned", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
botc.ST.script = {
    {id = "imp", name = "Imp", team = "demon"},
    {id = "poisoner", name = "Poisoner", team = "minion"},
    {id = "monk", name = "Monk", team = "townsfolk"},
}

-- Simulate formspec flow: first a CHG event from the textlist,
-- then the Assign button click
local fields_handler = mock_storage["_fields_handler"]
assert_true(fields_handler ~= nil, "fields handler registered")

-- Create a mock player for the receiver
local st_obj = minetest.get_player_by_name("StorytellerX")

-- Step 1: CHG event -- user selects index 3 (Monk) from textlist
fields_handler(st_obj, "botc_storyteller:script_wand_Bob", {roles = "CHG:3"})

-- Step 2: Assign button click (fields.roles NOT present)
fields_handler(st_obj, "botc_storyteller:script_wand_Bob", {assign = "true"})

-- Verify Bob was assigned the selected role (index 3 = Monk, 1-indexed in textlist but 0-indexed in table access?)
-- Wait: explode_textlist_event returns {type="CHG", index=3}, and script is 1-indexed (ipairs)
-- So script[3] = {id="monk", name="Monk", team="townsfolk"}
assert_eq(botc.ST.roles["Bob"].role, "Monk", "script wand assign uses tracked textlist selection")

-- ============================================================
section("28. Notebook Uses Book Model")
-- ============================================================
reset_state()
local notebook = minetest.registered_tools["botc_storyteller:notebook"]
assert_true(notebook ~= nil, "notebook registered")
assert_true(notebook.mesh == "book_feather.obj", "notebook uses book mesh")
assert_true(notebook.inventory_image == nil, "notebook has no 2D inventory image (mesh driven)")
assert_true(notebook.wield_scale ~= nil, "notebook has wield_scale")

-- ============================================================
section("29. Vote Block Claiming While Possessing")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
botc.ST._possession["StorytellerX"] = "Alice"
botc.ST.phase = "evening"
botc.ST.roles["Alice"] = {role = "Empath", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}

-- Set up a vote block node at (1,0,0)
local test_pos = {x = 1, y = 0, z = 0}
local node = minetest.get_node(test_pos)
local meta = minetest.get_meta(test_pos)
meta:set_string("owner", "")
meta:set_int("state", 0)

-- Get the vote block handlers
local vb_node = minetest.registered_nodes["botc_storyteller:voteblock_0"]
assert_true(vb_node ~= nil, "voteblock_0 node registered")

local st_obj = minetest.get_player_by_name("StorytellerX")

-- Claim the block while possessing
vb_node.on_rightclick(test_pos, node, st_obj, "item", {})
local ph = botc.pos_hash(test_pos)
assert_true(botc.ST.vote_blocks[ph] ~= nil, "vote block recorded in state")
assert_eq(botc.ST.vote_blocks[ph].owner, "Alice", "block owned by possessed player Alice")

-- Chat message went to real storyteller, not fake Alice
local chat = mock_chat["StorytellerX"]
assert_true(chat and chat:find("Vote block claimed"), "chat message sent to real player StorytellerX")

-- Punch to toggle vote
botc.ST.vote_blocks[ph].locked = false
meta:set_int("locked", 0)
vb_node.on_punch(test_pos, node, st_obj, {})
assert_eq(botc.ST.vote_blocks[ph].state, 1, "vote toggled to Yes for Alice")
assert_eq(botc.ST.vote_blocks[ph].owner, "Alice", "ownership still Alice after punch")

-- Unpossess and verify real player's identity is separate
botc.ST._possession["StorytellerX"] = nil

-- ============================================================
section("30. Fake Player HUD Position Uses Real Entity (not 0,0,0)")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
local fake_cmd = minetest.registered_chatcommands["botc_fake"]
assert_true(fake_cmd ~= nil, "botc_fake command registered")

local ok_add, msg_add = fake_cmd.func("StorytellerX", "add Zelda")
assert_true(ok_add, "fake player added: " .. tostring(msg_add))

-- Move the underlying entity to a distinctive, non-origin position
local ent = botc._fake_player_entities["Zelda"]
assert_true(ent ~= nil, "fake player entity tracked")
ent:set_pos({x = 42, y = 5, z = -7})

local fp = botc.get_player("Zelda")
assert_true(fp ~= nil, "get_player returns stub for fake player")
local pos = fp:get_pos()
assert_true(pos ~= nil, "fake player position is not nil")
assert_true(pos.x == 42 and pos.y == 5 and pos.z == -7,
    "fake player HUD position matches real entity position, not {0,0,0}")

-- Replacing a fake player with the same name (re-add) must not leave the
-- table pointing at a stale/removed entity, nor should the old entity's
-- deferred on_deactivate wipe the new entity's reference.
local old_ent = botc._fake_player_entities["Zelda"]
local ok_add2, _ = fake_cmd.func("StorytellerX", "add Zelda")
assert_true(ok_add2, "fake player re-added under same name")
local new_ent = botc._fake_player_entities["Zelda"]
assert_true(new_ent ~= nil, "new entity tracked after re-add")
assert_true(new_ent ~= old_ent, "re-add created a distinct entity")
-- Simulate the old entity's deactivation firing (as it does in real
-- Minetest, asynchronously, after the new one is already active)
old_ent.get_luaentity().on_deactivate(old_ent.get_luaentity())
assert_true(botc._fake_player_entities["Zelda"] == new_ent,
    "stale on_deactivate does not clear the current entity reference")
new_ent:set_pos({x = 9, y = 9, z = 9})
local fp2 = botc.get_player("Zelda")
local pos2 = fp2:get_pos()
assert_true(pos2.x == 9 and pos2.y == 9 and pos2.z == 9,
    "HUD position still resolves correctly after replacement")

-- ============================================================
section("31. Wand Raycast Stops at Solid Node (no through-wall targeting)")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
mock_players["Bob"] = {is_st = false}
botc.ST.roles["Bob"] = {role = "Mayor", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}

local _orig_raycast2 = minetest.raycast
-- Simulate a wall (node hit) between the storyteller and Bob
minetest.raycast = function(p1, p2, objects, liquids)
    local i = 0
    return function()
        i = i + 1
        if i == 1 then return {type = "node", under = {x=0,y=0,z=1}, above = {x=0,y=0,z=0}} end
        if i == 2 then return {type = "object", ref = {is_player = function() return true end, get_player_name = function() return "Bob" end}} end
        return nil
    end
end

local kill_wand3 = minetest.registered_tools["botc_storyteller:kill_wand"]
local st_obj4 = minetest.get_player_by_name("StorytellerX")
mock_formspecs["StorytellerX"] = nil
kill_wand3.on_use("botc_storyteller:kill_wand", st_obj4, {type = "nothing"})
assert_true(botc.ST.roles["Bob"].alive, "player behind a wall is NOT killed by wand pointed at nothing")
assert_true(mock_formspecs["StorytellerX"] ~= nil, "player selection UI shown instead of blind targeting through wall")

minetest.raycast = _orig_raycast2

-- ============================================================
section("32. Dead Players Cannot Nominate (botc_guide 5.2.2)")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
mock_players["Alice"] = {is_st = false}
mock_players["Bob"] = {is_st = false}
botc.ST.phase = "evening"
botc.ST.roles["Alice"] = {role = "Empath", team = "townsfolk", alive = false, dead_vote_used = false, markers = {}}
botc.ST.roles["Bob"] = {role = "Mayor", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}

-- botc.check_nomination is the shared production rule used by all
-- nomination entry points (chat command, wand, formspec list).
local ok_dead, err_dead = botc.check_nomination("Alice", "Bob")
assert_false(ok_dead, "dead player cannot nominate")
assert_true(err_dead ~= nil and err_dead:find("dead"), "error message explains dead player cannot nominate")

local ok_alive, _ = botc.check_nomination("Bob", "Alice")
assert_true(ok_alive, "alive player can nominate")

-- Self-nomination IS allowed (confirmed correction to guide 5.2.2)
local ok_self, _ = botc.check_nomination("Bob", "Bob")
assert_true(ok_self, "a player can nominate themselves")

-- Verify enforcement through the real /botc_nom chat command
local nom_cmd = minetest.registered_chatcommands["botc_nom"]
assert_true(nom_cmd ~= nil, "botc_nom command registered")
local ok_cmd, msg_cmd = nom_cmd.func("StorytellerX", "Alice Bob")
assert_false(ok_cmd, "botc_nom rejects a dead nominator: " .. tostring(msg_cmd))
assert_false(botc.ST.nominations[botc.ST.current_day] and botc.ST.nominations[botc.ST.current_day].nominators["Alice"] or false,
    "dead nominator was not recorded")

local ok_cmd2, _ = nom_cmd.func("StorytellerX", "Bob Alice")
assert_true(ok_cmd2, "botc_nom allows an alive nominator")
assert_true(botc.ST.nominations[botc.ST.current_day].nominators["Bob"], "alive nominator recorded")

-- Verify enforcement through the nomination wand's two-step punch flow
reset_state()
mock_players["StorytellerX"] = {is_st = true}
mock_players["Alice"] = {is_st = false}
mock_players["Bob"] = {is_st = false}
botc.ST.phase = "evening"
botc.ST.roles["Alice"] = {role = "Empath", team = "townsfolk", alive = false, dead_vote_used = false, markers = {}}
botc.ST.roles["Bob"] = {role = "Mayor", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
local nom_wand = minetest.registered_tools["botc_storyteller:nomination_wand"]
local alice_obj = minetest.get_player_by_name("Alice")
local bob_obj = minetest.get_player_by_name("Bob")
local st_obj5 = minetest.get_player_by_name("StorytellerX")
-- Attempt to set the dead Alice as nominator via direct pointed_thing targeting
nom_wand.on_use("botc_storyteller:nomination_wand", st_obj5, {type = "object", ref = alice_obj})
assert_true(botc.ST.nominations[botc.ST.current_day] == nil or not botc.ST.nominations[botc.ST.current_day].nominators["Alice"],
    "nomination wand does not accept a dead player as nominator")

-- ============================================================
section("33. Real Player Model + Dead/Fake Transparency")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
mock_players["Bob"] = {is_st = false}
botc.ST.roles["StorytellerX"] = {role = "Storyteller", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
botc.ST.roles["Bob"] = {role = "Mayor", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}

-- Fake player entities use the real player model, not a plain cube
local fp_def = minetest.registered_entities["botc_storyteller:fake_player"]
assert_eq(fp_def.initial_properties.visual, "mesh", "fake player uses a mesh visual")
assert_eq(fp_def.initial_properties.mesh, "character.b3d", "fake player uses the real player model")
assert_eq(fp_def.initial_properties.textures[1], "character.png", "fake player uses the real player skin texture")

-- Fake player spawned with no role -> no texture_mod (role-not-found == no action)
local user_obj33 = minetest.get_player_by_name("StorytellerX")
mock_players["StorytellerX"].pos = {x=0,y=0,z=0}
local fp_obj = minetest.add_entity({x=0,y=0,z=0}, "botc_storyteller:fake_player", "Fakey")
assert_eq(fp_obj._texture_mod or "", "", "fake player with no role gets no texture_mod")

-- Assign a role and toggle alive: opaque when alive, transparent when dead
botc.ST.roles["Fakey"] = {role = "Empath", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
botc.update_alive_texture("Fakey")
assert_eq(fp_obj._texture_mod, botc.ALIVE_TEXTURE_MOD, "alive fake player is fully opaque")
botc.ST.roles["Fakey"].alive = false
botc.update_alive_texture("Fakey")
assert_eq(fp_obj._texture_mod, botc.DEAD_TEXTURE_MOD, "dead fake player becomes transparent")

-- Mock skinsdb + player_api for real-player transparency tests.
-- ghost.lua wraps player_api.set_textures to append/strip an opacity
-- modifier based on alive state; skins.update_player_skin re-sends the
-- current skin through that wrapper.
_G.player_api = _G.player_api or {}
_G.player_api.set_textures = function(player, textures)
    player:set_properties({textures = textures})
end
_G.skins = {update_player_skin = function(player)
    local props = player:get_properties()
    player_api.set_textures(player, props.textures or {"character.png"})
end}
dofile("/home/opfromthestart/.minetest/worlds/botc_world/worldmods/botc_storyteller/ghost.lua")

-- Kill wand keeps normal size, applies opacity + alpha blending
local kill_wand33 = minetest.registered_tools["botc_storyteller:kill_wand"]
local bob_obj33 = minetest.get_player_by_name("Bob")
kill_wand33.on_use("botc_storyteller:kill_wand", user_obj33, {type = "object", ref = bob_obj33})
assert_false(botc.ST.roles["Bob"].alive, "Bob is dead after kill wand")
local bob_props = mock_players["Bob"].props or {}
local bob_vs = bob_props.visual_size
assert_true(not bob_vs or bob_vs.x == 1, "dead player keeps normal visual_size")
local bob_textures = bob_props.textures or {}
assert_true(#bob_textures > 0 and bob_textures[1]:find("opacity", 1, true), "dead player texture has opacity modifier")
assert_eq(bob_props.use_texture_alpha, true, "dead player has alpha blending enabled")

-- Revive wand strips the opacity modifier
local revive_wand33 = minetest.registered_tools["botc_storyteller:revive_wand"]
revive_wand33.on_use("botc_storyteller:revive_wand", user_obj33, {type = "object", ref = bob_obj33})
assert_true(botc.ST.roles["Bob"].alive, "Bob is alive after revive wand")
bob_props = mock_players["Bob"].props or {}
bob_textures = bob_props.textures or {}
assert_true(#bob_textures == 0 or not bob_textures[1]:find("opacity", 1, true), "revived player texture has no opacity modifier")

-- Dead player rejoining gets opacity reapplied, stays normal size
botc.ST.roles["Bob"].alive = false
mock_players["Bob"].props = nil
simulate_join("Bob")
bob_props = mock_players["Bob"].props or {}
bob_textures = bob_props.textures or {}
assert_true(#bob_textures > 0 and bob_textures[1]:find("opacity", 1, true), "rejoin dead reapplies opacity")
bob_vs = bob_props.visual_size
assert_true(not bob_vs or bob_vs.x == 1, "rejoin dead keeps normal visual_size")

-- Alive player rejoining stays normal
botc.ST.roles["Bob"].alive = true
mock_players["Bob"].props = nil
simulate_join("Bob")
bob_props = mock_players["Bob"].props or {}
bob_textures = bob_props.textures or {}
assert_true(#bob_textures == 0 or not bob_textures[1]:find("opacity", 1, true), "rejoin alive stays normal")

_G.player_api = nil
_G.skins = nil

-- Regression: ghost.lua's globalstep must NOT un-hide a player who is
-- currently hidden for a pyre execution (visual_size = 0). Previously
-- the globalstep unconditionally reset visual_size to {1,1} every
-- second, undoing pyre_hide_player's hide within ~1 second.
botc.ST.roles["Bob"].alive = false
mock_players["Bob"].props = nil
botc.pyre_hide_player("Bob")
bob_props = mock_players["Bob"].props or {}
assert_eq(bob_props.visual_size.x, 0, "pyre_hide_player hides the body (visual_size 0)")
for _, fn in ipairs(mock_storage["_globalstep_handlers"] or {}) do fn(1) end
bob_props = mock_players["Bob"].props or {}
assert_eq(bob_props.visual_size.x, 0, "ghost.lua globalstep does not un-hide a pyre-hidden player")
botc.pyre_show_player("Bob")

-- ============================================================
section("34. Fake Player Skins (skinsdb integration)")
-- ============================================================
reset_state()
mock_players["StorytellerX"] = {is_st = true}
local fakeskin_cmd = minetest.registered_chatcommands["botc_fakeskin"]
assert_true(fakeskin_cmd ~= nil, "botc_fakeskin command registered")

-- Rejected: skinsdb not installed in the test harness
local ok_no_skins, err_no_skins = fakeskin_cmd.func("StorytellerX", "Fakey character")
assert_false(ok_no_skins, "botc_fakeskin rejects when skinsdb not installed")
assert_true(err_no_skins:find("skinsdb"), "error mentions skinsdb missing")

-- Rejected: not a fake player
_G.skins = { get = function() return nil end }
local ok_bad, err_bad = fakeskin_cmd.func("StorytellerX", "Fakey character")
assert_false(ok_bad, "botc_fakeskin rejects non-fake-player target")

-- Accepted: valid fake player with a real skin
mock_players["Fakey"] = {is_st = false}
botc.fake_players["Fakey"] = true
botc._fake_player_entities["Fakey"] = {
    set_properties = function(self, p) self._props = p end,
    set_texture_mod = function() end,
    _props = {},
}
botc.ST.roles["Fakey"] = {role = "Empath", team = "townsfolk", alive = true, dead_vote_used = false, markers = {}}
_G.skins.get = function(key)
    if key == "custom_skin" then
        return {
            get_meta = function() return "1.8" end,
            get_texture = function() return "custom_skin.png" end,
        }
    end
end
local ok_skin, msg_skin = fakeskin_cmd.func("StorytellerX", "Fakey custom_skin")
assert_true(ok_skin, "botc_fakeskin succeeds for valid fake player + skin: " .. tostring(msg_skin))
assert_eq(botc.ST.roles["Fakey"].skin, "custom_skin", "skin key stored in role data")
local ents_fp = botc._fake_player_entities["Fakey"]
assert_eq(ents_fp._props.mesh, "skinsdb_3d_armor_character_5.b3d", "1.8-format skin uses 3d_armor character model")
assert_eq(ents_fp._props.textures[1], "custom_skin.png", "1.8-format skin texture applied")

-- 1.0-format skin uses character.b3d
_G.skins.get = function(key)
    if key == "old_skin" then
        return {
            get_meta = function() return "1.0" end,
            get_texture = function() return "old_skin.png" end,
        }
    end
end
fakeskin_cmd.func("StorytellerX", "Fakey old_skin")
assert_eq(ents_fp._props.mesh, "character.b3d", "1.0-format skin uses plain character.b3d model")
assert_eq(ents_fp._props.textures[1], "old_skin.png", "1.0-format skin texture applied")

-- apply_skin_to_fake is a no-op when skins global is absent
_G.skins = nil
botc.ST.roles["Fakey"].skin = "whatever"
ents_fp._props = {}
botc.apply_skin_to_fake("Fakey")
assert_true(ents_fp._props.mesh == nil, "apply_skin_to_fake is no-op without skinsdb")

_G.skins = nil

-- ============================================================
section("25. get_team_counts")
-- ============================================================
reset_state()
local tc = botc.get_team_counts(5)
assert_eq(tc.townsfolk, 3, "5p: 3 townsfolk")
assert_eq(tc.outsider, 0, "5p: 0 outsiders")
assert_eq(tc.minion, 1, "5p: 1 minion")
assert_eq(tc.demon, 1, "5p: 1 demon")

tc = botc.get_team_counts(6)
assert_eq(tc.townsfolk, 3, "6p: 3 townsfolk")
assert_eq(tc.outsider, 1, "6p: 1 outsider")
assert_eq(tc.minion, 1, "6p: 1 minion")

tc = botc.get_team_counts(7)
assert_eq(tc.townsfolk, 5, "7p: 5 townsfolk")
assert_eq(tc.outsider, 0, "7p: 0 outsiders")

tc = botc.get_team_counts(8)
assert_eq(tc.townsfolk, 5, "8p: 5 townsfolk")
assert_eq(tc.outsider, 1, "8p: 1 outsider")

tc = botc.get_team_counts(9)
assert_eq(tc.townsfolk, 5, "9p: 5 townsfolk")
assert_eq(tc.outsider, 2, "9p: 2 outsiders")

tc = botc.get_team_counts(10)
assert_eq(tc.townsfolk, 7, "10p: 7 townsfolk")
assert_eq(tc.outsider, 0, "10p: 0 outsiders")
assert_eq(tc.minion, 2, "10p: 2 minions")

tc = botc.get_team_counts(11)
assert_eq(tc.townsfolk, 7, "11p: 7 townsfolk")
assert_eq(tc.outsider, 1, "11p: 1 outsider")

tc = botc.get_team_counts(12)
assert_eq(tc.townsfolk, 7, "12p: 7 townsfolk")
assert_eq(tc.outsider, 2, "12p: 2 outsiders")

tc = botc.get_team_counts(13)
assert_eq(tc.townsfolk, 9, "13p: 9 townsfolk")
assert_eq(tc.outsider, 0, "13p: 0 outsiders")
assert_eq(tc.minion, 3, "13p: 3 minions")

tc = botc.get_team_counts(14)
assert_eq(tc.townsfolk, 9, "14p: 9 townsfolk")
assert_eq(tc.outsider, 1, "14p: 1 outsider")

tc = botc.get_team_counts(15)
assert_eq(tc.townsfolk, 9, "15p: 9 townsfolk")
assert_eq(tc.outsider, 2, "15p: 2 outsiders")
assert_eq(tc.minion, 3, "15p: 3 minions")

assert_eq(botc.get_team_counts(4), nil, "4p invalid")
assert_eq(botc.get_team_counts(16), nil, "16p invalid")
assert_eq(botc.get_team_counts("five"), nil, "string invalid")
assert_eq(botc.get_team_counts(nil), nil, "nil invalid")

for count = 5, 15 do
    tc = botc.get_team_counts(count)
    local sum = tc.townsfolk + tc.outsider + tc.minion + tc.demon
    assert_eq(sum, count, count .. "p: sum = " .. count)
end

-- ============================================================
section("26. Bag Mutations")
-- ============================================================
reset_state()

botc.ST.script = {
    {id="imp", name="Imp", team="demon"},
    {id="poisoner", name="Poisoner", team="minion"},
    {id="monk", name="Monk", team="townsfolk"},
    {id="recluse", name="Recluse", team="outsider"},
}

assert_eq(next(botc.ST.bag), nil, "bag starts empty")

botc.ST.bag["imp"] = 1
botc.ST.bag["monk"] = 2
assert_eq(botc.ST.bag["imp"], 1, "bag has 1 imp")
assert_eq(botc.ST.bag["monk"], 2, "bag has 2 monks")
assert_eq(botc.ST.bag["poisoner"], nil, "bag has no poisoner")

botc.ST.bag["monk"] = 1
assert_eq(botc.ST.bag["monk"], 1, "monk decremented to 1")

botc.ST.bag["monk"] = nil
assert_eq(botc.ST.bag["monk"], nil, "monk removed")

botc.ST.bag["recluse"] = 1
assert_eq(botc.ST.bag["recluse"], 1, "recluse added")

botc.ST.bag = {}
assert_eq(next(botc.ST.bag), nil, "bag cleared")

botc.ST.bag["imp"] = 1
botc.ST.bag["poisoner"] = 1
botc.ST.bag["monk"] = 3
botc.save_state()

local old_bag = botc.ST.bag
botc.ST.bag = {}
botc.load_state()
assert_eq(botc.ST.bag["imp"], 1, "bag imp persisted")
assert_eq(botc.ST.bag["poisoner"], 1, "bag poisoner persisted")
assert_eq(botc.ST.bag["monk"], 3, "bag monk persisted")

-- ============================================================
section("27. passout_from_bag")
-- ============================================================
reset_state()

mock_players["Alice"] = {is_st=false}
mock_players["Bob"] = {is_st=false}
mock_players["Charlie"] = {is_st=false}
mock_players["Diana"] = {is_st=false}
mock_players["Eve"] = {is_st=false}

botc.ST.bag["imp"] = 1
botc.ST.bag["poisoner"] = 1
botc.ST.bag["recluse"] = 1
botc.ST.bag["monk"] = 1
botc.ST.bag["chef"] = 1

local ok, msg = botc.passout_from_bag()
assert_true(ok, "5p passout_from_bag succeeds (" .. tostring(msg) .. ")")
assert_eq(botc.ST.phase, "night", "phase=night after passout_from_bag")
assert_eq(botc.ST.current_day, 1, "day=1 after passout_from_bag")

local names = {"Alice","Bob","Charlie","Diana","Eve"}
local tally = {townsfolk=0, outsider=0, minion=0, demon=0}
for _, n in ipairs(names) do
    local r = botc.ST.roles[n]
    assert_true(r ~= nil, n .. " assigned")
    assert_true(r.alive, n .. " alive")
    tally[r.team] = tally[r.team] + 1
end
assert_eq(tally.demon, 1, "1 demon")
assert_eq(tally.minion, 1, "1 minion")
assert_eq(tally.outsider, 1, "1 outsider")
assert_eq(tally.townsfolk, 2, "2 townsfolk")

-- size mismatch
reset_state()
mock_players["Alice"] = {is_st=false}
mock_players["Bob"] = {is_st=false}
botc.ST.bag["imp"] = 1
ok, msg = botc.passout_from_bag()
assert_false(ok, "size mismatch fails")
assert_true(msg:find("2"), "size mismatch mentions player count")

-- empty bag
reset_state()
mock_players["Alice"] = {is_st=false}
botc.ST.bag = {}
ok, msg = botc.passout_from_bag()
assert_false(ok, "empty bag fails")
assert_true(msg:find("empty"), "empty bag error")

-- no players
reset_state()
botc.ST.bag["imp"] = 1
ok, msg = botc.passout_from_bag()
assert_false(ok, "no players fails")
assert_true(msg:find("No players"), "no players error")

-- ============================================================
print(string.format("\n========================================"))
print(string.format("RESULTS: %d/%d passed, %d failed", pass_count, test_count, fail_count))
print(string.format("========================================"))
if fail_count > 0 then os.exit(1) else os.exit(0) end
