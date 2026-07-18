local player_huds = {}
local timer_hud_ids = {}  -- [playername] = hud_id

local function update_hud_for_player(viewer_name)
    local player = minetest.get_player_by_name(viewer_name)
    if not player then return end

    local is_st = minetest.check_player_privs(viewer_name, {storyteller = true})
    local viewer_data = botc.ST.roles[viewer_name]
    local viewer_team = viewer_data and viewer_data.team or nil
    local is_evil = viewer_team == "minion" or viewer_team == "demon"

    if not player_huds[viewer_name] then player_huds[viewer_name] = {} end
    local seen = {}
    for target, hud_id in pairs(player_huds[viewer_name]) do
        seen[target] = true
    end

    for target, data in pairs(botc.ST.roles) do
        local target_player = botc.get_player(target)
        if target_player then
            local pos = target_player:get_pos()
            if pos then
            pos.y = pos.y + 3.0

            local texts = {}
            local color = "#ffffff"

            if is_st then
                color = botc.get_team_color(data.team)
                table.insert(texts, data.role)
                if data.markers and #data.markers > 0 then
                    table.insert(texts, "[" .. table.concat(data.markers, ",") .. "]")
                end
            end

            if not is_st and is_evil and (data.team == "minion" or data.team == "demon") and target ~= viewer_name then
                color = "#ff2222"
                table.insert(texts, "EVIL")
            end

            local notes = botc.ST.player_notes[viewer_name]
            if notes and notes[target] then
                local entry = notes[target]
                if type(entry) == "table" then
                    if entry.public and entry.public ~= "" then
                        table.insert(texts, entry.public)
                    end
                    if entry.color then
                        color = entry.color
                    end
                elseif entry ~= "" then
                    table.insert(texts, entry)
                end
            end

            if #texts > 0 then
                local text = table.concat(texts, " ")
                local waypoint_number = tonumber(color:gsub("#", "0x"), 16) or 0xFFFFFF
                if player_huds[viewer_name][target] then
                    local id = player_huds[viewer_name][target]
                    player:hud_change(id, "text", text)
                    player:hud_change(id, "world_pos", pos)
                    player:hud_change(id, "number", waypoint_number)
                else
                    local id = player:hud_add({
                        type = "waypoint",
                        world_pos = pos,
                        text = text,
                        number = waypoint_number,
                    })
                    player_huds[viewer_name][target] = id
                end
                seen[target] = nil
            end
            end
        end
    end

    for target in pairs(seen) do
        if player_huds[viewer_name][target] then
            player:hud_remove(player_huds[viewer_name][target])
            player_huds[viewer_name][target] = nil
        end
    end
end

local function entity_alive(obj)
    if not obj then return false end
    if not obj:get_luaentity() then return false end
    return true
end

local function update_indicators()
    local day = botc.ST.current_day
    local nominees = {}
    if botc.ST.nominations[day] then
        for name, _ in pairs(botc.ST.nominations[day].nominees) do
            nominees[name] = true
        end
    end
    local exe_target = botc.ST.execution_target

    -- Manage nominated indicators
    botc.ST._nominated_indicators = botc.ST._nominated_indicators or {}
    for name, entity in pairs(botc.ST._nominated_indicators) do
        if not nominees[name] or not entity_alive(entity)
           or botc.ST.clock_state == "idle" or botc.ST.clock_state == "night" then
            if entity_alive(entity) then entity:remove() end
            botc.ST._nominated_indicators[name] = nil
        end
    end
    for name, _ in pairs(nominees) do
        if botc.ST.clock_state == "idle" or botc.ST.clock_state == "night" then
            break
        end
        if not botc.ST._nominated_indicators[name] or not entity_alive(botc.ST._nominated_indicators[name]) then
            local tp = botc.get_player(name)
            if tp then
                local pos = tp:get_pos()
                if pos then
                    local obj = minetest.add_entity({ x = pos.x, y = pos.y + 1.9, z = pos.z }, "botc_storyteller:indicator_nominated")
                    if obj then
                        local entity = obj:get_luaentity()
                        if entity then entity.target_player = name end
                        botc.ST._nominated_indicators[name] = obj
                    end
                end
            end
        else
            local tp = botc.get_player(name)
            if tp then
                local pos = tp:get_pos()
                if pos then
                    botc.ST._nominated_indicators[name]:set_pos({ x = pos.x, y = pos.y + 1.9, z = pos.z })
                end
            end
        end
    end

    -- Manage execution indicator
    local exec_entity = botc.ST._execution_indicator
    if exec_entity then
        if not exe_target or not entity_alive(exec_entity) then
            if entity_alive(exec_entity) then exec_entity:remove() end
            botc.ST._execution_indicator = nil
        end
    end
    if exe_target then
        if not botc.ST._execution_indicator or not entity_alive(botc.ST._execution_indicator) then
            local tp = botc.get_player(exe_target)
            if tp then
                local pos = tp:get_pos()
                if pos then
                    local obj = minetest.add_entity({ x = pos.x, y = pos.y + 2.4, z = pos.z }, "botc_storyteller:indicator_execution")
                    if obj then
                        local entity = obj:get_luaentity()
                        if entity then entity.target_player = exe_target end
                        botc.ST._execution_indicator = obj
                    end
                end
            end
        else
            local tp = botc.get_player(exe_target)
            if tp then
                local pos = tp:get_pos()
                if pos then
                    botc.ST._execution_indicator:set_pos({ x = pos.x, y = pos.y + 2.4, z = pos.z })
                end
            end
        end
    end
end
local hud_timer = 0

local function update_timer_hud(name, player)
    if not botc.ST.timer_active and not timer_hud_ids[name] then
        return
    end
    if not botc.ST.timer_active then
        if timer_hud_ids[name] then
            player:hud_remove(timer_hud_ids[name])
            timer_hud_ids[name] = nil
        end
        return
    end

    local remaining = math.max(0, botc.ST.timer_duration - botc.ST.timer_elapsed)
    local mins = math.floor(remaining / 60)
    local secs = math.floor(remaining % 60)
    local paused = (botc.ST.clock_state == "nominating" or botc.ST.clock_state == "sweeping")
    local text = (botc.ST.timer_name ~= "" and botc.ST.timer_name or "Timer") .. ": " ..
                 string.format("%d:%02d", mins, secs)
    if paused then
        text = text .. " PAUSED"
    end

    if timer_hud_ids[name] then
        player:hud_change(timer_hud_ids[name], "text", text)
    else
        local id = player:hud_add({
            type = "text",
            text = text,
            position = {x = 0.85, y = 0.92},
            alignment = {x = 0, y = 0},
            size = {x = 4, y = 1},
            number = 0xFFAA00,
        })
        timer_hud_ids[name] = id
    end
end

minetest.register_globalstep(function(dtime)
    hud_timer = hud_timer + dtime
    if hud_timer < 0.15 then return end
    hud_timer = 0

    -- Update timer: advance unless paused by nomination
    if botc.ST.timer_active then
        local paused = (botc.ST.clock_state == "nominating" or botc.ST.clock_state == "sweeping")
        if not paused then
            botc.ST.timer_elapsed = botc.ST.timer_elapsed + 0.15
            if botc.ST.timer_elapsed >= botc.ST.timer_duration then
                botc.ST.timer_active = false
                botc.ST.timer_elapsed = 0
                botc.save_state()
                minetest.chat_send_all(minetest.colorize("#ffaa00", "Timer finished: " .. (botc.ST.timer_name ~= "" and botc.ST.timer_name or "Unnamed")))
            end
        end
    end

    -- Update timer HUD for all players
    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        update_timer_hud(name, player)
    end

    for _, player in ipairs(minetest.get_connected_players()) do
        update_hud_for_player(player:get_player_name())
    end

    for phash, vb in pairs(botc.ST.vote_blocks) do
        local pos = minetest.string_to_pos(phash)
        if pos then
            local node = minetest.get_node(pos)
            local expected = "botc_storyteller:voteblock_" .. vb.state
            if node.name ~= expected then
                minetest.swap_node(pos, { name = expected })
            end
        end
    end

    update_indicators()

    botc.manage_clock_hand()
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player_huds[name] = nil
    timer_hud_ids[name] = nil
end)
