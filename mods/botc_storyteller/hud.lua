local player_huds = {} -- { [viewer] = { [target] = hud_id } }

local function update_hud_for_player(viewer_name)
    local player = minetest.get_player_by_name(viewer_name)
    if not player then return end

    local is_st = minetest.check_player_privs(viewer_name, {storyteller = true})
    local viewer_data = botc.ST.roles[viewer_name]
    local viewer_team = viewer_data and viewer_data.team or nil
    local is_evil = viewer_team == "minion" or viewer_team == "demon"

    -- Clean up old HUD elements
    if not player_huds[viewer_name] then player_huds[viewer_name] = {} end
    local seen = {}
    for target, hud_id in pairs(player_huds[viewer_name]) do
        seen[target] = true
    end

    -- Add/update waypoints for each assigned player
    for target, data in pairs(botc.ST.roles) do
        local target_player = minetest.get_player_by_name(target)
        if target_player then
            local pos = target_player:get_pos()
            pos.y = pos.y + 2.0 -- above head

            local texts = {}
            local color = "#ffffff"

            -- Storyteller sees role name + markers
            if is_st then
                color = botc.get_team_color(data.team)
                table.insert(texts, data.role)
                if data.markers and #data.markers > 0 then
                    table.insert(texts, "[" .. table.concat(data.markers, ",") .. "]")
                end
            end

            -- Evil team sees EVIL above other evil players
            if not is_st and is_evil and (data.team == "minion" or data.team == "demon") and target ~= viewer_name then
                color = "#ff2222"
                table.insert(texts, "EVIL")
            end

            -- Player notes (viewer's own notes for target)
            local notes = botc.ST.player_notes[viewer_name]
            if notes and notes[target] then
                table.insert(texts, notes[target])
            end

            if #texts > 0 then
                local text = table.concat(texts, " ")
                if player_huds[viewer_name][target] then
                    -- Update existing waypoint
                    local id = player_huds[viewer_name][target]
                    player:hud_change(id, "text", text)
                    player:hud_change(id, "world_pos", pos)
                else
                    -- Create new waypoint
                    local id = player:hud_add({
                        hud_elem_type = "waypoint",
                        world_pos = pos,
                        text = text,
                        number = tonumber(color:gsub("#", "0x"), 16) or 0xFFFFFF,
                        scale = {x = 1, y = 1},
                    })
                    player_huds[viewer_name][target] = id
                end
                seen[target] = nil
            end
        end
    end

    -- Remove waypoints for players no longer visible
    for target in pairs(seen) do
        if player_huds[viewer_name][target] then
            player:hud_remove(player_huds[viewer_name][target])
            player_huds[viewer_name][target] = nil
        end
    end
end

local hud_timer = 0
minetest.register_globalstep(function(dtime)
    hud_timer = hud_timer + dtime
    if hud_timer < 0.5 then return end
    hud_timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        update_hud_for_player(player:get_player_name())
    end

    -- Update vote block visuals
    for phash, vb in pairs(botc.ST.vote_blocks) do
        local pos = minetest.string_to_pos(phash)
        if pos then
            local node = minetest.get_node(pos)
            if node.name == "botc:voteblock" then
                local colors = { [0] = "#333333", [1] = "#44ff44", [2] = "#444444", [3] = "#88ff88", [4] = "#222222" }
                node.param2 = vb.state -- store state in param2 for visual
                minetest.swap_node(pos, node)
            end
        end
    end

    botc.manage_clock_hand()
end)

minetest.register_on_leaveplayer(function(player)
    local name = player:get_player_name()
    player_huds[name] = nil
end)
