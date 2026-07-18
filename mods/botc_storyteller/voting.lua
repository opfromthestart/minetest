local VOTE_STATE_DESC = {
    [0] = "Normal No",
    [1] = "Normal Yes",
    [2] = "Ghost No",
    [3] = "Ghost Yes",
    [4] = "Used Ghost",
}

-- The clock hand OBJ models are exported with their long axis along local Z,
-- but the yaw math below computes angles assuming a model whose forward
-- axis is +X. Apply a corrective offset so the mesh points the right way.
local MESH_HAND_YAW_OFFSET = math.pi / 2

function botc.compute_sweep_start()
    local nominee = botc.ST.clock_nominee
    if not nominee or not botc.ST.clock_pos then
        return 0
    end
    for ph, vb in pairs(botc.ST.vote_blocks) do
        if vb.owner == nominee then
            local bpos = minetest.string_to_pos(ph)
            if bpos then
                local dx = bpos.x - botc.ST.clock_pos.x
                local dz = bpos.z - botc.ST.clock_pos.z
                local block_angle = math.deg(math.atan2(dz, dx))
                if block_angle < 0 then block_angle = block_angle + 360 end
                return (block_angle + 1) % 360
            end
        end
    end
    return 0
end

local function vote_node_name(state)
    return "botc_storyteller:voteblock_" .. state
end

local function make_vote_handlers(state)
    return {
        on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
            local real_name = clicker:get_player_name()
            local name = botc.resolve_actor(real_name)
            local meta = minetest.get_meta(pos)
            local owner = meta:get_string("owner")

            for phash, vb in pairs(botc.ST.vote_blocks) do
                if vb.owner == name and phash ~= botc.pos_hash(pos) then
                    local oldpos = minetest.string_to_pos(phash)
                    if oldpos then
                        local oldmeta = minetest.get_meta(oldpos)
                        oldmeta:set_string("owner", "")
                        oldmeta:set_int("state", 0)
                        botc.ST.vote_blocks[phash] = nil
                        minetest.swap_node(oldpos, { name = vote_node_name(0) })
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
                minetest.swap_node(pos, { name = vote_node_name(0) })
                minetest.chat_send_player(real_name, "Vote block claimed!")
            else
                minetest.chat_send_player(real_name, "This block belongs to " .. owner)
            end
            return itemstack
        end,
        on_punch = function(pos, node, puncher, pointed_thing)
            local real_name = puncher:get_player_name()
            if not real_name then return end
            local name = botc.resolve_actor(real_name)
            local meta = minetest.get_meta(pos)
            local owner = meta:get_string("owner")
            if owner ~= name then
                minetest.chat_send_player(real_name, "Not your vote block")
                return
            end
            if botc.ST.phase ~= "evening" then
                minetest.chat_send_player(real_name, "Voting only during evening phase")
                return
            end
            if meta:get_int("locked") == 1 then
                minetest.chat_send_player(real_name, "Vote locked")
                return
            end

            local state = meta:get_int("state")
            local data = botc.ST.roles[name]
            local is_ghost = data and not data.alive

            if not is_ghost then
                state = (state ~= 1) and 1 or 0
            else
                if state == 4 then
                    minetest.chat_send_player(real_name, "Dead vote already used")
                    return
                end
                state = (state ~= 3) and 3 or 2
            end

            meta:set_int("state", state)
            local ph = botc.pos_hash(pos)
            botc.ST.vote_blocks[ph] = { owner = name, state = state, locked = false }
            botc.save_state()
            minetest.swap_node(pos, { name = vote_node_name(state) })
            minetest.chat_send_player(real_name, "Vote: " .. VOTE_STATE_DESC[state])
        end,
        on_destruct = function(pos)
            local ph = botc.pos_hash(pos)
            if botc.ST.vote_blocks[ph] then
                botc.ST.vote_blocks[ph] = nil
                botc.save_state()
            end
        end,
    }
end

for state = 0, 4 do
    local handlers = make_vote_handlers(state)
    minetest.register_node(vote_node_name(state), {
        description = "Vote Block (" .. VOTE_STATE_DESC[state] .. ")",
        drawtype = "mesh",
        mesh = "vote_" .. state .. ".obj",
        tiles = { "vote_" .. state .. ".png" },
        visual_scale = 0.6,
        use_texture_alpha = true,
        backface_culling = false,
        groups = { cracky = 2, oddly_breakable_by_hand = 2, not_in_creative_inventory = (state ~= 0) and 1 or 0 },
        light_source = (state == 1 or state == 3) and 7 or 0,
        paramtype2 = "facedir",
        on_construct = function(pos)
            local meta = minetest.get_meta(pos)
            meta:set_string("owner", "")
            meta:set_int("state", state)
            meta:set_int("locked", 0)
        end,
        on_rightclick = handlers.on_rightclick,
        on_punch = handlers.on_punch,
        on_destruct = handlers.on_destruct,
        drop = "botc_storyteller:voteblock_0",
    })
end

minetest.register_alias("botc_storyteller:voteblock", "botc_storyteller:voteblock_0")

minetest.register_node("botc_storyteller:clock", {
    description = "BotC Clock",
    drawtype = "mesh",
    mesh = "clock_base.obj",
    tiles = { "clock_base.png" },
    visual_scale = 1.25,
    use_texture_alpha = true,
    backface_culling = false,
    paramtype2 = "facedir",
    groups = { cracky = 2 },
    on_construct = function(pos)
        botc.ST.clock_pos = { x = pos.x, y = pos.y, z = pos.z }
        botc.save_state()
        botc.manage_clock_hand()
    end,
    on_destruct = function(pos)
        botc.ST.clock_pos = nil
        botc.ST.clock_state = "idle"
        botc.save_state()
    end,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local name = clicker:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        if botc.ST.clock_rightclick_lock then return itemstack end
        if botc.ST.clock_state == "nominating" then
            botc.ST.clock_state = "sweeping"
            botc.ST.clock_sweep_start = botc.compute_sweep_start()
            botc.ST.clock_angle = botc.ST.clock_sweep_start
            botc.ST.clock_rightclick_lock = true
            botc.save_state()
            botc.manage_clock_hand()
            minetest.chat_send_all(minetest.colorize("#ffaa00", "Vote started!"))
            minetest.after(1.0, function()
                botc.ST.clock_rightclick_lock = false
            end)
        elseif botc.ST.clock_state == "sweeping" then
            botc.ST.clock_state = "idle"
            botc.ST.clock_angle = nil
            botc.ST.execution_target = nil
            botc.ST.clock_nominator = nil
            botc.ST.clock_nominee = nil
            botc.save_state()
            minetest.chat_send_player(name, "Vote cancelled.")
        end
        return itemstack
    end,
})

minetest.register_entity("botc_storyteller:clock_hand", {
    initial_properties = {
        visual = "mesh",
        mesh = "clock_big_hand.obj",
        textures = { "clock_big_hand.png" },
        visual_size = { x = 8, y = 8, z = 8 },
        backface_culling = false,
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    sweep_speed = 360 / 10,
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
            self.object:set_properties({ visual_size = { x = 0, y = 0, z = 0 } })
            self.object:set_pos(pos)
            return
        end

        if botc.ST.clock_state == "nominating" then
            self.object:set_properties({ visual_size = { x = 8, y = 8, z = 8 } })
            local nominee_name = botc.ST.clock_nominee
            if nominee_name then
                local nominee = botc.get_player(nominee_name)
                if nominee then
                    local npos = nominee:get_pos()
                    if npos then
                        local angle = math.atan2(npos.z - pos.z, npos.x - pos.x)
                        self.object:set_rotation({ x = 0, y = angle + MESH_HAND_YAW_OFFSET, z = 0 })
                    end
                end
            end
            self.object:set_pos({ x = pos.x, y = pos.y + 0.6, z = pos.z })
            return
        end

        if botc.ST.clock_state == "sweeping" then
            self.object:set_properties({ visual_size = { x = 8, y = 8, z = 8 } })
            local sweep_start = botc.ST.clock_sweep_start or 0
            local angle = (botc.ST.clock_angle or 0) + (self.sweep_speed * dtime)
            if angle >= sweep_start + 360 then
                angle = sweep_start + 360
                local yes_count, no_count = botc.tally_votes(botc.ST.vote_blocks)
                for ph, vb in pairs(botc.ST.vote_blocks) do
                    if vb.state == 3 then
                        vb.state = 4
                        vb.locked = true
                        local data = botc.ST.roles[vb.owner]
                        if data then
                            data.dead_vote_used = true
                        end
                        local bpos = minetest.string_to_pos(ph)
                        if bpos then
                            minetest.swap_node(bpos, { name = "botc_storyteller:voteblock_4" })
                            local meta = minetest.get_meta(bpos)
                            if meta then
                                meta:set_int("state", 4)
                                meta:set_int("locked", 1)
                            end
                        end
                    end
                end
                minetest.chat_send_all(minetest.colorize("#ffaa00", "Votes: " .. yes_count .. " Yes / " .. no_count .. " No"))
                local nom = botc.ST.clock_nominee
                if nom and botc.would_execute(yes_count, no_count) then
                    botc.ST.execution_target = nom
                    minetest.chat_send_all(minetest.colorize("#ff2222", nom .. " is marked for execution!"))
                end
                botc.ST.clock_state = "idle"
                botc.ST.clock_angle = nil
                botc.ST.clock_sweep_start = 0
                botc.ST.clock_nominator = nil
                botc.ST.clock_nominee = nil
                botc.save_state()
                self.object:set_properties({ visual_size = { x = 0, y = 0, z = 0 } })
                return
            end

            self.object:set_rotation({ x = 0, y = math.rad(angle) + MESH_HAND_YAW_OFFSET, z = 0 })

            local hand_travel = angle - sweep_start
            for phash, vb in pairs(botc.ST.vote_blocks) do
                if not vb.locked then
                    local block_pos = minetest.string_to_pos(phash)
                    if block_pos then
                        local dx = block_pos.x - pos.x
                        local dz = block_pos.z - pos.z
                        local block_angle = math.deg(math.atan2(dz, dx))
                        if block_angle < 0 then block_angle = block_angle + 360 end
                        local dist_to_block = (block_angle - sweep_start + 360) % 360
                        if dist_to_block <= hand_travel then
                            vb.locked = true
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

minetest.register_entity("botc_storyteller:clock_little_hand", {
    initial_properties = {
        visual = "mesh",
        mesh = "clock_little_hand.obj",
        textures = { "clock_little_hand.png" },
        visual_size = { x = 8, y = 8, z = 8 },
        backface_culling = false,
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    sweep_speed = 360 / 12,
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
            self.object:set_properties({ visual_size = { x = 0, y = 0, z = 0 } })
            self.object:set_pos(pos)
            return
        end

        if botc.ST.clock_state == "nominating" then
            self.object:set_properties({ visual_size = { x = 8, y = 8, z = 8 } })
            local nominator_name = botc.ST.clock_nominator
            if nominator_name then
                local nominator = botc.get_player(nominator_name)
                if nominator then
                    local npos = nominator:get_pos()
                    if npos then
                        local angle = math.atan2(npos.z - pos.z, npos.x - pos.x)
                        self.object:set_rotation({ x = 0, y = angle + MESH_HAND_YAW_OFFSET, z = 0 })
                    end
                end
            end
            self.object:set_pos({ x = pos.x, y = pos.y + 0.65, z = pos.z })
            return
        end

        if botc.ST.clock_state == "sweeping" then
            self.object:set_properties({ visual_size = { x = 8, y = 8, z = 8 } })
            local nominator_name = botc.ST.clock_nominator
            if nominator_name then
                local nominator = botc.get_player(nominator_name)
                if nominator then
                    local npos = nominator:get_pos()
                    if npos then
                        local angle = math.atan2(npos.z - pos.z, npos.x - pos.x)
                        self.object:set_rotation({ x = 0, y = angle + MESH_HAND_YAW_OFFSET, z = 0 })
                    end
                end
            end
            self.object:set_pos({ x = pos.x, y = pos.y + 0.65, z = pos.z })
            return
        end
    end,
})

minetest.register_entity("botc_storyteller:indicator_nominated", {
    initial_properties = {
        visual = "sprite",
        textures = { "raisedhand.png" },
        visual_size = { x = 0.6, y = 0.6, z = 0.6 },
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    on_activate = function(self, staticdata)
        if staticdata and staticdata ~= "" then
            self.object:remove()
        end
    end,
    target_player = nil,
})

minetest.register_entity("botc_storyteller:indicator_execution", {
    initial_properties = {
        visual = "sprite",
        textures = { "Wandandemblemexicute.png" },
        visual_size = { x = 0.6, y = 0.6, z = 0.6 },
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    on_activate = function(self, staticdata)
        if staticdata and staticdata ~= "" then
            self.object:remove()
        end
    end,
    target_player = nil,
})

function botc.manage_clock_hand()
    local pos = botc.ST.clock_pos
    if not pos then return end

    local entities = minetest.get_objects_inside_radius(pos, 2) or {}
    local big_hand_exists = false
    local little_hand_exists = false
    for _, obj in ipairs(entities) do
        if obj and obj:get_luaentity() then
            local name = obj:get_luaentity().name
            if name == "botc_storyteller:clock_hand" then
                big_hand_exists = true
            elseif name == "botc_storyteller:clock_little_hand" then
                little_hand_exists = true
            end
        end
    end

    if not big_hand_exists then
        minetest.add_entity({ x = pos.x, y = pos.y + 0.7, z = pos.z }, "botc_storyteller:clock_hand")
    end
    if not little_hand_exists then
        minetest.add_entity({ x = pos.x, y = pos.y + 0.75, z = pos.z }, "botc_storyteller:clock_little_hand")
    end
end

-- ============================================================
-- Fire Pyre – execution staging area
-- ============================================================

local PYRE_LOGS = {
    -- inner ring (close to shaft, lower)
    {p={0.35, -0.35, 0.0}},
    {p={-0.35, -0.35, 0.0}},
    {p={0.0, -0.35, 0.35}},
    {p={0.0, -0.35,-0.35}},
    -- middle ring
    {p={0.55, -0.15, 0.2}},
    {p={-0.55, -0.15,-0.2}},
    {p={0.2, -0.15, 0.55}},
    {p={-0.2, -0.15,-0.55}},
    {p={-0.45, -0.15, -0.45}},
    {p={-0.45, -0.15, 0.45}},
    -- outer ring (farther out, higher)
    {p={0.8, 0.05, 0.0}},
    {p={-0.8, 0.05, 0.0}},
    {p={0.0, 0.05, 0.8}},
    {p={0.0, 0.05,-0.8}},
    {p={0.55, 0.05, 0.55}},
    {p={-0.55, 0.05,-0.55}},
}

local PYRE_PLANKS = {
    {p={0.5, -0.2, 0.0}},
    {p={-0.5, -0.2, 0.0}},
    {p={0.0, -0.2, 0.5}},
    {p={0.0, -0.2,-0.5}},
    {p={0.35, -0.1, 0.35}},
    {p={-0.35, -0.1,-0.35}},
    {p={0.7, 0.0, 0.0}},
    {p={-0.7, 0.0, 0.0}},
    {p={0.0, 0.0, 0.7}},
    {p={0.0, 0.0,-0.7}},
}

botc._pyre_entities = {} -- {pos_hash -> [obj, obj, ...]}

minetest.register_entity("botc_storyteller:pyre_shaft", {
    initial_properties = {
        visual = "cube",
        visual_size = {x = 0.4, y = 3.5, z = 0.4},
        textures = {"default_tree_top.png", "default_tree_top.png", "default_tree.png", "default_tree.png", "default_tree.png", "default_tree.png"},
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
    end,
})

minetest.register_entity("botc_storyteller:pyre_log", {
    initial_properties = {
        visual = "cube",
        visual_size = {x = 1.4, y = 0.25, z = 0.25},
        textures = {"default_tree_top.png", "default_tree_top.png", "default_tree.png", "default_tree.png", "default_tree.png", "default_tree.png"},
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
    end,
})

minetest.register_entity("botc_storyteller:pyre_plank", {
    initial_properties = {
        visual = "cube",
        visual_size = {x = 1.2, y = 0.15, z = 0.6},
        textures = {"default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png", "default_wood.png"},
        physical = false,
        collide_with_objects = false,
        pointable = false,
        static_save = false,
    },
    on_activate = function(self)
        self.object:set_armor_groups({immortal = 1})
    end,
})

local function pyre_spawn_visuals(pos)
    local ents = {}
    -- shaft centered 1.25 above ground so its bottom sits 0.5 below ground,
    -- which sinks it into the earth like a real pyre
    local shaft = minetest.add_entity({x=pos.x, y=pos.y+1.25, z=pos.z}, "botc_storyteller:pyre_shaft")
    if shaft then table.insert(ents, shaft) end
    for _, def in ipairs(PYRE_LOGS) do
        local log = minetest.add_entity(
            {x=pos.x+def.p[1], y=pos.y+def.p[2], z=pos.z+def.p[3]},
            "botc_storyteller:pyre_log"
        )
        if log then
            local yaw = math.atan2(def.p[3], def.p[1]) + (math.random()-0.5)*1.2
            local lean = math.rad(20 + math.random() * 15)
            log:set_rotation({x=0, y=yaw, z=lean})
            table.insert(ents, log)
        end
    end
    for _, def in ipairs(PYRE_PLANKS) do
        local plank = minetest.add_entity(
            {x=pos.x+def.p[1], y=pos.y+def.p[2], z=pos.z+def.p[3]},
            "botc_storyteller:pyre_plank"
        )
        if plank then
            local yaw = math.atan2(def.p[3], def.p[1]) -- face outward
            local lean = math.rad(25 + math.random() * 10) -- tilt inward, form cone
            plank:set_rotation({x=0, y=yaw, z=lean})
            table.insert(ents, plank)
        end
    end
    return ents
end

local function pyre_remove_visuals(pos)
    local ph = minetest.pos_to_string(pos)
    local ents = botc._pyre_entities[ph]
    if ents then
        for _, obj in ipairs(ents) do
            if obj then obj:remove() end
        end
        botc._pyre_entities[ph] = nil
    end
    -- Also sweep for orphaned pyre entities at this position
    for _, obj in ipairs(minetest.get_objects_inside_radius(pos, 3)) do
        if obj and not obj:is_player() then
            local lua = obj:get_luaentity()
            if lua and (lua.name == "botc_storyteller:pyre_shaft"
                     or lua.name == "botc_storyteller:pyre_log"
                     or lua.name == "botc_storyteller:pyre_plank") then
                local op = obj:get_pos()
                if op and math.abs(op.x - pos.x) < 1.5
                        and math.abs(op.y - pos.y) < 0.5
                        and math.abs(op.z - pos.z) < 1.5 then
                    obj:remove()
                end
            end
        end
    end
end

minetest.register_node("botc_storyteller:fire_pyre", {
    description = "Fire Pyre",
    drawtype = "airlike",
    pointable = true,
    walkable = false,
    buildable_to = false,
    sunlight_propagates = true,
    tiles = {"default_tree.png"},
    paramtype = "light",
    light_source = 12,
    groups = {cracky = 2, oddly_breakable_by_hand = 2},
    on_construct = function(pos)
        pyre_remove_visuals(pos)
        local ents = pyre_spawn_visuals(pos)
        botc._pyre_entities[minetest.pos_to_string(pos)] = ents
    end,
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
        local name = clicker:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        botc.ST.execution_zone = pos
        botc.save_state()
        minetest.chat_send_player(name, "Execution zone set at fire pyre")
        return itemstack
    end,
    on_destruct = function(pos)
        if botc.ST.execution_zone
           and botc.ST.execution_zone.x == pos.x
           and botc.ST.execution_zone.y == pos.y
           and botc.ST.execution_zone.z == pos.z then
            botc.ST.execution_zone = nil
            botc.save_state()
        end
        pyre_remove_visuals(pos)
    end,
})

-- Re-spawn pyre visual entities on world load, since on_construct
-- only fires at placement time.
minetest.register_lbm({
    label = "Respawn fire pyre entities",
    name = "botc_storyteller:pyre_respawn",
    nodenames = {"botc_storyteller:fire_pyre"},
    run_at_every_load = true,
    action = function(pos, node)
        pyre_remove_visuals(pos)
        local ents = pyre_spawn_visuals(pos)
        botc._pyre_entities[minetest.pos_to_string(pos)] = ents
    end,
})

minetest.register_entity("botc_storyteller:fire_pyre_effect", {
    initial_properties = {
        visual = "sprite",
        visual_size = {x = 0, y = 0, z = 0},
        textures = {"blank.png"},
        physical = false,
        collide_with_objects = false,
        static_save = false,
        glow = 14,
    },
    elapsed = 0,
    on_step = function(self, dtime)
        self.elapsed = self.elapsed + dtime
        local pos = self.object:get_pos()
        local half = 3.5
        local intensity
        if self.elapsed <= half then
            local t = self.elapsed / half
            intensity = t * t
        elseif self.elapsed <= half * 2 then
            local t = (self.elapsed - half) / half
            intensity = (1 - t) * (1 - t)
        else
            self.object:remove()
            return
        end
        local base = math.floor(intensity * 60)
        local extra = (math.random() < (intensity * 60 - base)) and 1 or 0
        local anum = base + extra
        for _ = 1, anum do
            local ox = (math.random() - 0.5) * 2.4
            local oy = math.random() * 3.5
            local oz = (math.random() - 0.5) * 2.4
            minetest.add_particle({
                pos = {x = pos.x + ox, y = pos.y + oy, z = pos.z + oz},
                velocity = {x = (math.random()-0.5)*2, y = math.random()*4+1, z = (math.random()-0.5)*2},
                acceleration = {x = 0, y = 1, z = 0},
                expirationtime = 0.6 + math.random() * 1.2,
                size = 1.5 + math.random() * 2.0,
                collisiondetection = false,
                texture = "default_furnace_fire_fg.png",
                glow = 14,
            })
        end
        if anum > 0 then
            minetest.add_particle({
                pos = {x = pos.x, y = pos.y + 1.75, z = pos.z},
                velocity = {x = 0, y = 1, z = 0},
                acceleration = {x = 0, y = 0, z = 0},
                expirationtime = 2,
                size = 4.0,
                collisiondetection = false,
                texture = "default_furnace_fire_fg.png",
                glow = 14,
            })
        end
    end,
})

function botc.pyre_spawn_fire(pos)
    minetest.after(10, function()
        minetest.add_entity({x = pos.x, y = pos.y - 0.5, z = pos.z}, "botc_storyteller:fire_pyre_effect")
    end)
end

function botc.is_execution_zone_pyre()
    if not botc.ST.execution_zone then return false end
    local node = minetest.get_node(botc.ST.execution_zone)
    return node.name == "botc_storyteller:fire_pyre"
end

function botc.pyre_hide_player(target)
    local p = minetest.get_player_by_name(target)
    if not p then return end
    local data = botc.ST.roles[target]
    if not data then return end
    -- Save original position so we can restore on revive
    local orig = p:get_pos()
    data._pyre_hidden_pos = {x = orig.x, y = orig.y, z = orig.z}
    data._pyre_hidden = true
    p:set_properties({visual_size = {x = 0, y = 0, z = 0}})
    p:set_nametag_attributes({text = ""})
    p:set_velocity({x = 0, y = 0, z = 0})
end

function botc.pyre_show_player(target)
    local data = botc.ST.roles[target]
    if not data or not data._pyre_hidden then return end
    local p = minetest.get_player_by_name(target)
    if not p then
        data._pyre_hidden = false
        return
    end
    local restore_pos = data._pyre_hidden_pos or botc.ST.execution_zone
    p:set_physics_override({gravity = 1, speed = 1, jump = 1})
    p:set_pos(restore_pos)
    p:set_velocity({x = 0, y = 0, z = 0})
    p:set_properties({visual_size = {x = 1, y = 1, z = 1}})
    p:set_nametag_attributes({text = target})
    data._pyre_hidden = false
    data._pyre_hidden_pos = nil
end
