local ghost_timer = 0

-- Wrap player_api.set_textures to append opacity for dead players.
-- skinsdb calls this every time it sets a skin, so this ensures
-- the opacity modifier survives skin changes.
if minetest.global_exists("player_api") and player_api.set_textures then
    local _orig_set_textures = player_api.set_textures

    player_api.set_textures = function(player, textures)
        local name = player:get_player_name()
        local data = botc.ST.roles[name]
        if data and not data.alive then
            for i = 1, #textures do
                if textures[i] ~= "" and not textures[i]:find("opacity", 1, true) then
                    textures[i] = textures[i] .. botc.DEAD_TEXTURE_MOD
                end
            end
        end
        _orig_set_textures(player, textures)
    end
end

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
            player:set_nametag_attributes({
                color = { r = 128, g = 128, b = 128, a = 128 },
            })
        else
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
