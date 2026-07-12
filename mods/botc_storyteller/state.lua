local modname = minetest.get_current_modname()
local storage = minetest.get_mod_storage()

botc = {}
botc.ST = {
    roles = {},           -- { [playername] = {role, team, alive, dead_vote_used, markers} }
    nominations = {},     -- { [day] = { nominators = {}, nominees = {} } }
    phase = "day",
    script = nil,         -- { {id, name, team}, ... }
    execution_zone = nil, -- {x, y, z}
    vote_blocks = {},     -- { [pos_hash] = {owner, state} }
    clock_pos = nil,      -- {x, y, z}
    clock_state = "idle", -- "idle" | "nominating" | "sweeping"
    clock_nominator = nil,
    clock_nominee = nil,
    current_day = 1,
    player_notes = {},    -- { [author] = { [target] = "text" } }
}

local TEAM_COLORS = { townsfolk = "#4488ff", outsider = "#44aaff", minion = "#ff4444", demon = "#ff2222", storyteller = "#ffaa00" }

function botc.save_state()
    local data = minetest.write_json(botc.ST)
    storage:set_string("game_state", data)
end

function botc.load_state()
    local data = storage:get_string("game_state")
    if data ~= "" then
        local parsed = minetest.parse_json(data)
        if parsed then
            for k, v in pairs(parsed) do
                botc.ST[k] = v
            end
        end
    end
end

function botc.get_team_color(team)
    return TEAM_COLORS[team] or "#ffffff"
end

function botc.pos_hash(pos)
    return minetest.pos_to_string(pos)
end
