local ghost_timer = 0

minetest.register_globalstep(function(dtime)
    ghost_timer = ghost_timer + dtime
    if ghost_timer < 1 then return end
    ghost_timer = 0

    local is_night = botc.ST.phase == "night"

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local is_st = minetest.check_player_privs(name, {storyteller = true})
        local data = botc.ST.roles[name]

        if data and not data.alive then
            player:set_properties({
                visual_size = { x = 0.7, y = 0.7 },
            })
            player:set_nametag_attributes({
                color = { r = 100, g = 150, b = 255, a = 255 },
            })
        else
            player:set_properties({
                visual_size = { x = 1, y = 1 },
            })
            player:set_nametag_attributes({
                color = { r = 255, g = 255, b = 255, a = 255 },
            })
        end

        -- Hide storyteller nametag during night to prevent cheating
        if is_st and is_night then
            player:set_nametag_attributes({text = ""})
        elseif is_st then
            player:set_nametag_attributes({text = name})
        end
    end
end)
