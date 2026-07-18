local ghost_timer = 0

local OPACITY_MOD = "^[opacity:102"

local function apply_dead_transparency(player)
    local props = player:get_properties()
    local textures = props and props.textures or {}
    if #textures == 0 then return end
    if textures[1]:find(OPACITY_MOD, 1, true) then return end
    textures[1] = textures[1] .. OPACITY_MOD
    player:set_properties({textures = textures})
end

local function remove_dead_transparency(player)
    local props = player:get_properties()
    local textures = props and props.textures or {}
    if #textures == 0 then return end
    if not textures[1]:find(OPACITY_MOD, 1, true) then return end
    textures[1] = textures[1]:gsub(OPACITY_MOD, "")
    player:set_properties({textures = textures})
end

minetest.register_globalstep(function(dtime)
    ghost_timer = ghost_timer + dtime
    if ghost_timer < 1 then return end
    ghost_timer = 0

    for _, player in ipairs(minetest.get_connected_players()) do
        local name = player:get_player_name()
        local data = botc.ST.roles[name]
        if data and not data.alive then
            player:set_nametag_attributes({
                color = { r = 128, g = 128, b = 128, a = 128 },
            })
            apply_dead_transparency(player)
        else
            player:set_nametag_attributes({
                color = { r = 255, g = 255, b = 255, a = 255 },
            })
            remove_dead_transparency(player)
        end
    end
end)
