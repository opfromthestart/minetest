local ghost_timer = 0

local function apply_dead_transparency(player)
    local props = player:get_properties()
    local textures = props and props.textures or {}
    if #textures == 0 then return end
    if textures[1]:find("opacity", 1, true) then return end
    for i = 1, #textures do
        if textures[i] ~= "" then
            textures[i] = textures[i] .. botc.DEAD_TEXTURE_MOD
        end
    end
    player:set_properties({textures = textures})
end

local function remove_dead_transparency(player)
    local props = player:get_properties()
    local textures = props and props.textures or {}
    if #textures == 0 then return end
    if not textures[1]:find("opacity", 1, true) then return end
    for i = 1, #textures do
        textures[i] = textures[i]:gsub("%^%[opacity:[0-9]+", "")
    end
    player:set_properties({textures = textures})
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
            apply_dead_transparency(player)
        else
            player:set_nametag_attributes({
                color = { r = 255, g = 255, b = 255, a = 255 },
            })
            remove_dead_transparency(player)
        end

        -- Hide storyteller nametag during night to prevent cheating
        if is_st and is_night then
            player:set_nametag_attributes({text = ""})
        elseif is_st then
            player:set_nametag_attributes({text = name})
        end
    end
end)
