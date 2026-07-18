local ghost_timer = 0

-- Wrap player_api.set_textures so that whenever skinsdb (or anything else)
-- sets a player's skin textures, we re-apply the dead-transparency modifier
-- if the player is currently dead. This is necessary because skinsdb can
-- overwrite textures independently of our own globalstep.
if minetest.global_exists("player_api") and player_api.set_textures then
    local _orig_set_textures = player_api.set_textures

    player_api.set_textures = function(player, textures)
        local name = player:get_player_name()
        local data = botc.ST.roles[name]
        local modded = {}
        for i = 1, #textures do
            -- Strip any previously-applied opacity modifier first so we
            -- don't stack it or leave it behind when reviving.
            local base = textures[i]
            if base ~= "" then
                base = base:gsub("%^%[opacity:%d+", "")
            end
            if data and not data.alive and base ~= "" then
                modded[i] = base .. botc.DEAD_TEXTURE_MOD
            else
                modded[i] = base
            end
        end
        _orig_set_textures(player, modded)
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

        -- Don't touch players currently hidden for a pyre execution
        -- (visual_size = 0) - that's a distinct, temporary visual state
        -- managed by voting.lua and must not be fought over here.
        if not (data and data._pyre_hidden) then
            -- use_texture_alpha must be enabled or the engine treats any
            -- transparency as a binary alpha-test, which makes the whole
            -- model disappear instead of rendering it semi-transparent.
            player:set_properties({
                use_texture_alpha = true,
            })

            if data and not data.alive then
                player:set_nametag_attributes({
                    color = { r = 100, g = 150, b = 255, a = 255 },
                })
            else
                player:set_nametag_attributes({
                    color = { r = 255, g = 255, b = 255, a = 255 },
                })
            end
        end

        -- Hide storyteller nametag during night to prevent cheating
        if is_st and is_night then
            player:set_nametag_attributes({text = ""})
        elseif is_st then
            player:set_nametag_attributes({text = name})
        end
    end
end)
