local VOTE_BLOCK_STATES = {
    [0] = { desc = "Normal No",  tile = "botc_vote_no.png" },
    [1] = { desc = "Normal Yes", tile = "botc_vote_yes.png" },
    [2] = { desc = "Ghost No",   tile = "botc_vote_ghost_no.png" },
    [3] = { desc = "Ghost Yes",  tile = "botc_vote_ghost_yes.png" },
    [4] = { desc = "Used Ghost", tile = "botc_vote_used.png" },
}

-- Fallback: use colorized default textures since we don't have custom images
-- In production, replace with actual textures
local function vote_block_tile(state)
    local colors = {
        [0] = "#333333", [1] = "#44ff44", [2] = "#444444", [3] = "#88ff88", [4] = "#222222"
    }
    return "default_wood.png^[colorize:" .. (colors[state] or "#333333") .. ":128"
end

minetest.register_node("botc:voteblock", {
    description = "Vote Block",
    tiles = {
        "default_wood.png^[colorize:#333333:128",
        "default_wood.png^[colorize:#333333:128",
        "default_wood.png^[colorize:#333333:128",
        "default_wood.png^[colorize:#333333:128",
        "default_wood.png^[colorize:#333333:128",
        "default_wood.png^[colorize:#333333:128",
    },
    groups = { cracky = 2, oddly_breakable_by_hand = 2 },
    paramtype2 = "facedir",
    on_construct = function(pos)
        local meta = minetest.get_meta(pos)
        meta:set_string("owner", "")
        meta:set_int("state", 0)
        meta:set_int("locked", 0)
    end,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local name = clicker:get_player_name()
        local meta = minetest.get_meta(pos)
        local owner = meta:get_string("owner")

        -- Check if player already owns another block
        for phash, vb in pairs(botc.ST.vote_blocks) do
            if vb.owner == name and phash ~= botc.pos_hash(pos) then
                -- Unclaim old block
                local oldpos = minetest.string_to_pos(phash)
                if oldpos then
                    local oldmeta = minetest.get_meta(oldpos)
                    oldmeta:set_string("owner", "")
                    oldmeta:set_int("state", 0)
                    botc.ST.vote_blocks[phash] = nil
                end
            end
        end

        if owner == "" or owner == name then
            meta:set_string("owner", name)
            meta:set_int("state", 0)
            meta:set_int("locked", 0)
            local ph = botc.pos_hash(pos)
            botc.ST.vote_blocks[ph] = { owner = name, state = 0, locked = false }
            botc.save_state()
            minetest.chat_send_player(name, "Vote block claimed!")
        else
            minetest.chat_send_player(name, "This block belongs to " .. owner)
        end
        return itemstack
    end,
    on_punch = function(pos, node, puncher, pointed_thing)
        local name = puncher:get_player_name()
        if not name then return end
        local meta = minetest.get_meta(pos)
        local owner = meta:get_string("owner")
        if owner ~= name then
            minetest.chat_send_player(name, "Not your vote block")
            return
        end
        if botc.ST.phase ~= "evening" then
            minetest.chat_send_player(name, "Voting only during evening phase")
            return
        end
        if meta:get_int("locked") == 1 then
            minetest.chat_send_player(name, "Vote locked")
            return
        end

        local state = meta:get_int("state")
        local data = botc.ST.roles[name]
        local is_ghost = data and not data.alive

        if not is_ghost then
            -- Alive: toggle 0 <-> 1
            state = (state ~= 1) and 1 or 0
        else
            -- Ghost: toggle 2 <-> 3
            if state == 4 then
                minetest.chat_send_player(name, "Dead vote already used")
                return
            end
            state = (state ~= 3) and 3 or 2
        end

        meta:set_int("state", state)
        local ph = botc.pos_hash(pos)
        botc.ST.vote_blocks[ph] = { owner = name, state = state, locked = false }
        botc.save_state()
        minetest.chat_send_player(name, "Vote: " .. (VOTE_BLOCK_STATES[state] and VOTE_BLOCK_STATES[state].desc or "?"))
    end,
})

minetest.register_node("botc:clock", {
    description = "BotC Clock",
    tiles = { "default_steel_block.png", "default_steel_block.png", "default_steel_block.png",
              "default_steel_block.png", "default_steel_block.png", "default_steel_block.png" },
    groups = { cracky = 2 },
    on_construct = function(pos)
        botc.ST.clock_pos = pos
        botc.save_state()
    end,
    on_destruct = function(pos)
        botc.ST.clock_pos = nil
        botc.ST.clock_state = "idle"
        botc.save_state()
    end,
})

minetest.register_entity("botc:clock_hand", {
    initial_properties = {
        visual = "cube",
        visual_size = { x = 2, y = 0.1, z = 0.1 },
        textures = { "default_gold_block.png", "default_gold_block.png", "default_gold_block.png",
                     "default_gold_block.png", "default_gold_block.png", "default_gold_block.png" },
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    sweep_speed = 360 / 10, -- 360 degrees over 10 seconds
    on_activate = function(self, staticdata)
        if staticdata and staticdata ~= "" then
            self.object:remove()
        end
    end,
    on_step = function(self, dtime)
        local pos = botc.ST.clock_pos
        if not pos then
            self.object:remove()
            return
        end

        if botc.ST.clock_state == "idle" or botc.ST.clock_state == "night" then
            -- Hand hidden (set to very small)
            self.object:set_properties({ visual_size = { x = 0, y = 0, z = 0 } })
            self.object:set_pos(pos)
            return
        end

        if botc.ST.clock_state == "nominating" then
            -- Point hand at nominee
            self.object:set_properties({ visual_size = { x = 1.5, y = 0.08, z = 0.08 } })
            local nominee_name = botc.ST.clock_nominee
            if nominee_name then
                local nominee = minetest.get_player_by_name(nominee_name)
                if nominee then
                    local npos = nominee:get_pos()
                    local angle = math.atan2(npos.z - pos.z, npos.x - pos.x)
                    self.object:set_rotation({ x = 0, y = angle, z = 0 })
                end
            end
            self.object:set_pos({ x = pos.x, y = pos.y + 0.6, z = pos.z })
            return
        end

        if botc.ST.clock_state == "sweeping" then
            -- Full rotation sweep
            self.object:set_properties({ visual_size = { x = 1.5, y = 0.08, z = 0.08 } })
            local angle = (botc.ST.clock_angle or 0) + (self.sweep_speed * dtime)
            if angle >= 360 then
                angle = 360
                -- Sweep complete: tally and reset
                local yes_count = 0
                local no_count = 0
                for _, vb in pairs(botc.ST.vote_blocks) do
                    if vb.state == 1 or vb.state == 3 then
                        yes_count = yes_count + 1
                    else
                        no_count = no_count + 1
                    end
                end
                minetest.chat_send_all(minetest.colorize("#ffaa00", "Votes: " .. yes_count .. " Yes / " .. no_count .. " No"))
                botc.ST.clock_state = "idle"
                botc.ST.clock_angle = nil
                botc.ST.clock_nominator = nil
                botc.ST.clock_nominee = nil
                botc.save_state()
                self.object:set_properties({ visual_size = { x = 0, y = 0, z = 0 } })
                return
            end

            self.object:set_rotation({ x = 0, y = math.rad(angle), z = 0 })

            -- Lock vote blocks as hand passes their angular position
            for phash, vb in pairs(botc.ST.vote_blocks) do
                if not vb.locked then
                    local block_pos = minetest.string_to_pos(phash)
                    if block_pos then
                        local dx = block_pos.x - pos.x
                        local dz = block_pos.z - pos.z
                        local block_angle = math.deg(math.atan2(dz, dx))
                        -- Normalize angles to 0-360
                        if block_angle < 0 then block_angle = block_angle + 360 end
                        if block_angle <= angle then
                            vb.locked = true
                            -- Also update the node meta
                            local meta = minetest.get_meta(block_pos)
                            if meta then
                                meta:set_int("locked", 1)
                            end
                        end
                    end
                end
            end

            botc.ST.clock_angle = angle
            self.object:set_pos({ x = pos.x, y = pos.y + 0.6, z = pos.z })
            return
        end
    end,
})

-- Spawn clock hand when clock state activates, remove when idle
-- Called from hud.lua globalstep
function botc.manage_clock_hand()
    local pos = botc.ST.clock_pos
    if not pos then return end

    local entities = minetest.get_objects_inside_radius(pos, 2)
    local hand_exists = false
    for _, obj in ipairs(entities) do
        if obj and obj:get_luaentity() and obj:get_luaentity().name == "botc:clock_hand" then
            hand_exists = true
            break
        end
    end

    if not hand_exists and (botc.ST.clock_state == "nominating" or botc.ST.clock_state == "sweeping") then
        minetest.add_entity({ x = pos.x, y = pos.y + 0.6, z = pos.z }, "botc:clock_hand")
    end
end
