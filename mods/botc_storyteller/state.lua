local modname = minetest.get_current_modname()
local storage = minetest.get_mod_storage()

botc = {}
botc.ST = {
    roles = {},           -- { [playername] = {role, team, alive, dead_vote_used, markers} }
    nominations = {},     -- { [day] = { nominators = {}, nominees = {} } }
    phase = "night",      -- games start at night (botc_guide 2.3)
    script = nil,         -- { {id, name, team}, ... }
    execution_zone = nil, -- {x, y, z}
    vote_blocks = {},     -- { [pos_hash] = {owner, state} }
    clock_pos = nil,      -- {x, y, z}
    clock_state = "idle", -- "idle" | "nominating" | "sweeping"
    clock_nominator = nil,
    clock_nominee = nil,
    clock_sweep_start = 0,
    execution_target = nil, -- player marked for execution after successful vote
    _possession = {},       -- { [storyteller_name] = {name = fake_player_name, track = bool} }
    current_day = 1,
    current_timeofday = 0.0,
    player_notes = {},    -- { [author] = { [target] = "text" } }
    bag = {},             -- { [role_id] = count, ... } — custom role bag
    timer_active = false,
    timer_duration = 0,   -- total seconds set by ST
    timer_elapsed = 0,    -- elapsed seconds (frozen when clock is nominating/sweeping)
    timer_name = "",      -- display label
}

botc.fake_players = {}  -- { name = true }

function botc.all_players()
    local names = {}
    local seen = {}
    for _, p in ipairs(minetest.get_connected_players()) do
        local n = p:get_player_name()
        names[#names+1] = n
        seen[n] = true
    end
    for n, _ in pairs(botc.fake_players) do
        if not seen[n] then
            names[#names+1] = n
        end
    end
    return names
end

function botc.player_exists(name)
    if minetest.get_player_by_name(name) then return true end
    return botc.fake_players[name] == true
end

-- botc_guide 5.2.2: "Any alive player may nominate any other player
-- (alive or dead) for execution. Dead players cannot nominate."
-- Note: a player CAN nominate themselves.
function botc.check_nomination(nominator, nominee)
    local ndata = botc.ST.roles[nominator]
    if ndata and not ndata.alive then
        return false, nominator .. " is dead and cannot nominate"
    end
    return true
end

function botc.count_alive_players()
    local count = 0
    for _, data in pairs(botc.ST.roles) do
        if data.alive then count = count + 1 end
    end
    return count
end

-- Counts yes/no votes across vote blocks. States 1 (alive yes) and 3
-- (ghost yes) both count as "yes"; everything else counts as "no".
function botc.tally_votes(vote_blocks)
    local yes_count, no_count = 0, 0
    for _, vb in pairs(vote_blocks) do
        if vb.state == 1 or vb.state == 3 then
            yes_count = yes_count + 1
        else
            no_count = no_count + 1
        end
    end
    return yes_count, no_count
end

-- botc_guide 5.2.3: "A player is executed if they receive votes from at
-- least half of the alive players (rounded up) AND have the highest
-- number of votes. If there is a tie for highest votes, no one is
-- executed."
function botc.would_execute(yes_count, no_count)
    local alive = botc.count_alive_players()
    local threshold = math.ceil(alive / 2)
    return yes_count >= threshold and yes_count > no_count
end

-- Dead players are rendered partially transparent (~40% opacity) so
-- they're visually distinct. Applied via a texture modifier that
-- layers on top of whatever skin/texture is already in use.
botc.DEAD_TEXTURE_MOD = "^[opacity:102" -- ~0.4 alpha, ghostly but visible
botc.ALIVE_TEXTURE_MOD = ""

function botc.update_alive_texture(name)
    local data = botc.ST.roles[name]
    if not data then return end
    -- Fake player entities manage transparency on the entity ObjectRef,
    -- not through the player-proxy stub.
    local ent = botc._fake_player_entities[name]
    if ent then
        if data.alive then
            ent:set_texture_mod(botc.ALIVE_TEXTURE_MOD)
        else
            ent:set_texture_mod(botc.DEAD_TEXTURE_MOD)
        end
        return
    end
    local p = botc.get_player(name)
    if p and p.is_player and p:is_player() then
        -- Enable alpha blending so the opacity modifier actually renders
        -- as semi-transparent instead of being alpha-tested to invisible.
        p:set_properties({use_texture_alpha = true})
        if minetest.global_exists("skins") and skins.update_player_skin then
            -- Re-send the skin through player_api.set_textures, which
            -- ghost.lua wraps to add/remove the dead opacity modifier.
            skins.update_player_skin(p)
        elseif minetest.global_exists("player_api") and player_api.set_textures then
            -- No skinsdb: re-apply the current textures through the
            -- wrapped set_textures so the modifier is added/removed.
            local props = p:get_properties()
            player_api.set_textures(p, props.textures or {})
        end
    end
end

function botc.get_player(name)
    local p = minetest.get_player_by_name(name)
    if p then return p end
    -- Fake players are handled by fakeplayer.lua, which overrides this
    -- function with an entity-aware version. This base version only
    -- knows about real connected players.
    return nil
end

local TEAM_COLORS = { townsfolk = "#4488ff", outsider = "#aa44ff", minion = "#ff7700", demon = "#ff2222", storyteller = "#ffaa00" }

function botc.save_state()
    if botc.ST.clock_pos then
        storage:set_string("clock_pos", minetest.pos_to_string(botc.ST.clock_pos))
    else
        storage:set_string("clock_pos", "")
    end

    -- Filter each field through a JSON write/parse round-trip so only
    -- values that actually survive serialization end up in the saved
    -- blob.  This prevents one non-serializable field from blocking the
    -- entire state save.
    local safe = {}
    for k, v in pairs(botc.ST) do
        local ok, j = pcall(minetest.write_json, v)
        if ok and j then
            local p = minetest.parse_json(j)
            if p ~= nil then
                safe[k] = p
            end
        else
            minetest.log("warning", "[botc_storyteller] Skipping field '" .. tostring(k) .. "' during save")
        end
    end

    local ok, data = pcall(minetest.write_json, safe)
    if ok and data then
        storage:set_string("game_state", data)
    else
        minetest.log("error", "[botc_storyteller] Failed to serialize game state: " .. tostring(data))
    end
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

    local clock_pos_str = storage:get_string("clock_pos")
    if clock_pos_str and clock_pos_str ~= "" then
        botc.ST.clock_pos = minetest.string_to_pos(clock_pos_str)
    else
        botc.ST.clock_pos = nil
    end
end

function botc.get_team_color(team)
    return TEAM_COLORS[team] or "#ffffff"
end

function botc.pos_hash(pos)
    return minetest.pos_to_string(pos)
end

function botc.sync_vote_block_for_player(playername)
    local phash, vb
    for ph, v in pairs(botc.ST.vote_blocks) do
        if v.owner == playername then
            phash = ph
            vb = v
            break
        end
    end
    if not phash then return end

    local data = botc.ST.roles[playername]
    local is_ghost = data and not data.alive
    local old_state = vb.state

    if is_ghost then
        if old_state == 0 then vb.state = 2
        elseif old_state == 1 then vb.state = 3 end
    else
        if old_state == 2 or old_state == 4 then vb.state = 0
        elseif old_state == 3 then vb.state = 1 end
    end

    local pos = minetest.string_to_pos(phash)
    if pos and vb.state ~= old_state then
        minetest.swap_node(pos, { name = "botc_storyteller:voteblock_" .. vb.state })
        local meta = minetest.get_meta(pos)
        if meta then
            meta:set_int("state", vb.state)
            if not is_ghost and old_state == 4 then
                meta:set_int("locked", 0)
                vb.locked = false
            end
        end
    end
end

-- Re-apply the dead/alive transparency when a player (re)joins, since a
-- freshly connected ObjectRef always starts fully opaque regardless of
-- their tracked alive state.
minetest.register_on_joinplayer(function(player)
    local name = player:get_player_name()
    botc.update_alive_texture(name)
end)
