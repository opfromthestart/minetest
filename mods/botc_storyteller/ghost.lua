local ghost_timer = 0

minetest.register_globalstep(function(dtime)
    ghost_timer = ghost_timer + dtime
    if ghost_timer < 1 then return end
    ghost_timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local data = botc.ST.roles[name]
        if data and not data.alive then
            player:set_properties({
                visual_size = { x = 0.8, y = 0.8 },
            })
            player:set_nametag_attributes({
                color = { r = 128, g = 128, b = 128, a = 128 },
            })
        else
            player:set_properties({
                visual_size = { x = 1, y = 1 },
            })
            player:set_nametag_attributes({
                color = { r = 255, g = 255, b = 255, a = 255 },
            })
        end
    end
end)
