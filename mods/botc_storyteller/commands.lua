local function require_st(name)
    if not minetest.check_player_privs(name, {storyteller = true}) then
        return false, "You need the storyteller privilege."
    end
    return true
end

minetest.register_chatcommand("botc_script", {
    params = "<filename.json>",
    description = "Load a role script",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param == "" then return false, "Usage: /botc_script <filename.json>" end
        return botc.load_script(param)
    end,
})

minetest.register_chatcommand("botc_deal", {
    params = "[player1 player2 ...]",
    description = "Deal roles from loaded script",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local args = {}
        if param ~= "" then
            for w in param:gmatch("%S+") do table.insert(args, w) end
        end
        local ok2, msg = botc.passout(args)
        return ok2, msg
    end,
})

minetest.register_chatcommand("botc_assign", {
    params = "<player> <role>",
    description = "Assign a role to a player",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local player, role = param:match("^(%S+)%s+(.+)$")
        if not player then return false, "Usage: /botc_assign <player> <role>" end
        if not botc.ST.script then return false, "No script loaded" end
        for _, entry in ipairs(botc.ST.script) do
            if botc.resolve_name(entry):lower() == role:lower() then
                return botc.assign_role(player, entry)
            end
        end
        return false, "Role '" .. role .. "' not found in script"
    end,
})

minetest.register_chatcommand("botc_clear", {
    params = "[player]",
    description = "Clear a player's role (or all if no player given)",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param == "" then
            botc.ST.roles = {}
            botc.ST.vote_blocks = {}
            botc.ST.nominations = {}
            botc.ST.player_notes = {}
            botc.ST.nomination_votes = {}
            botc.save_state()
            return true, "All assignments cleared"
        end
        return botc.unassign_role(param)
    end,
})

minetest.register_chatcommand("botc_clearvotes", {
    params = "",
    description = "Deregister ownership of all vote blocks",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local count = 0
        for _ in pairs(botc.ST.vote_blocks) do count = count + 1 end
        botc.ST.vote_blocks = {}
        botc.save_state()
        return true, count .. " vote blocks deregistered"
    end,
})

minetest.register_chatcommand("botc_check", {
    description = "Check for incomplete night steps (VISIT markers, meta steps, required tokens)",
    privs = { storyteller = true },
    func = function(name, param)
        local lines = {}
        local visited = {}
        for pname, data in pairs(botc.ST.roles) do
            if data.alive and data.markers then
                for _, m in ipairs(data.markers) do
                    if m == "VISIT" then
                        table.insert(visited, pname)
                        break
                    end
                end
            end
        end
        if #visited > 0 then
            table.insert(lines, "VISIT remaining: " .. table.concat(visited, ", "))
        end
        local meta_steps = botc.get_meta_steps(botc.ST.current_day)
        local incomplete = {}
        for _, step in ipairs(meta_steps) do
            if not (botc.ST.meta_steps_done or {})[step] then
                table.insert(incomplete, step)
            end
        end
        if #incomplete > 0 then
            table.insert(lines, "Meta steps incomplete: " .. table.concat(incomplete, ", "))
        end
        local missing = botc.check_required_tokens()
        if missing then
            local msgs = {}
            for _, m in ipairs(missing) do
                table.insert(msgs, m.token .. " (need " .. m.needed .. ", have " .. m.have .. ")")
            end
            table.insert(lines, "Missing tokens: " .. table.concat(msgs, ", "))
        end
        if #lines == 0 then
            return true, "All checks passed."
        end
        return true, "=== botc_check ===\n" .. table.concat(lines, "\n")
    end,
})

minetest.register_chatcommand("botc_meta_done", {
    description = "Mark a meta step as complete (dusk, minioninfo, demoninfo, dawn)",
    privs = { storyteller = true },
    func = function(name, param)
        local valid = {dusk=true, minioninfo=true, demoninfo=true, dawn=true}
        local step = param:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if not valid[step] then
            return false, "Invalid step. Valid steps: dusk, minioninfo, demoninfo, dawn"
        end
        botc.ST.meta_steps_done = botc.ST.meta_steps_done or {}
        botc.ST.meta_steps_done[step] = true
        botc.save_state()
        return true, "Meta step '" .. step .. "' marked complete."
    end,
})

minetest.register_chatcommand("botc_list", {
    params = "",
    description = "List all assigned players",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local lines = {}
        for pname, data in pairs(botc.ST.roles) do
            local status = data.alive and "ALIVE" or "DEAD"
            local dv = data.dead_vote_used and " [vote used]" or ""
            table.insert(lines, string.format("%s: %s (%s) %s%s", pname, data.role, data.team, status, dv))
        end
        if #lines == 0 then return true, "No roles assigned" end
        table.sort(lines)
        return true, table.concat(lines, "\n")
    end,
})

minetest.register_chatcommand("botc_zone", {
    params = "",
    description = "Set execution zone at your position",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        local pos = vector.round(player:get_pos())
        botc.ST.execution_zone = pos
        botc.save_state()
        return true, "Execution zone set at " .. minetest.pos_to_string(pos)
    end,
})

minetest.register_chatcommand("botc_nom", {
    params = "<nominator> <nominee>",
    description = "Nominate a player",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local nominator, nominee = param:match("^(%S+)%s+(%S+)$")
        if not nominator then return false, "Usage: /botc_nom <nominator> <nominee>" end
        if botc.ST.phase ~= "evening" then return false, "Nominations only during evening phase" end
        local nom_ok, nom_err = botc.check_nomination(nominator, nominee)
        if not nom_ok then return false, nom_err end
        local day = botc.ST.current_day
        if not botc.ST.nominations[day] then
            botc.ST.nominations[day] = { nominators = {}, nominees = {} }
        end
        if botc.ST.nominations[day].nominators[nominator] then
            return false, nominator .. " has already nominated today"
        end
        if botc.ST.nominations[day].nominees[nominee] then
            return false, nominee .. " has already been nominated today"
        end
        botc.ST.nominations[day].nominators[nominator] = true
        botc.ST.nominations[day].nominees[nominee] = true
        botc.ST.clock_nominator = nominator
        botc.ST.clock_nominee = nominee
        botc.ST.clock_state = "nominating"
        botc.save_state()
        botc.manage_clock_hand()
        minetest.chat_send_all(minetest.colorize("#ffaa00", nominator .. " nominates " .. nominee .. " for execution!"))
        return true
    end,
})

minetest.register_chatcommand("botc_vote", {
    params = "",
    description = "Start the vote sweep",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if botc.ST.phase ~= "evening" then return false, "Voting only during evening phase" end
        if botc.ST.clock_state ~= "nominating" then return false, "No active nomination" end
        botc.ST.clock_state = "sweeping"
        botc.ST.clock_sweep_start = botc.compute_sweep_start()
        botc.ST.clock_angle = botc.ST.clock_sweep_start
        botc.save_state()
        botc.manage_clock_hand()
        return true, "Vote started!"
    end,
})

minetest.register_chatcommand("botc_end_noms", {
    params = "",
    description = "End nominations and finalize execution",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if not next(botc.ST.nomination_votes) then
            return false, "No nominations recorded today"
        end
        local winner = botc.finalize_executions()
        if winner then
            return true, winner .. " is marked for execution"
        end
        return true, "No execution today"
    end,
})

minetest.register_chatcommand("botc_clock", {
    params = "",
    description = "Reset the clock to idle",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        botc.ST.clock_state = "idle"
        botc.ST.clock_nominator = nil
        botc.ST.clock_nominee = nil
        botc.ST.clock_angle = nil
        botc.ST.execution_target = nil
        for _, vb in pairs(botc.ST.vote_blocks) do
            if vb.state ~= 4 then vb.locked = false end
        end
        botc.save_state()
        return true, "Clock reset"
    end,
})

minetest.register_chatcommand("botc_dvote", {
    params = "<player>",
    description = "Use a ghost's dead vote",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param == "" then return false, "Usage: /botc_dvote <player>" end
        local data = botc.ST.roles[param]
        if not data then return false, "Player has no role" end
        if data.alive then return false, "Player is still alive" end
        if data.dead_vote_used then return false, "Dead vote already used" end
        data.dead_vote_used = true
        for ph, vb in pairs(botc.ST.vote_blocks) do
            if vb.owner == param then
                vb.state = 4
                vb.locked = true
                local pos = minetest.string_to_pos(ph)
                if pos then
                    minetest.swap_node(pos, { name = "botc_storyteller:voteblock_4" })
                    local meta = minetest.get_meta(pos)
                    if meta then
                        meta:set_int("state", 4)
                        meta:set_int("locked", 1)
                    end
                end
            end
        end
        botc.save_state()
        return true, param .. "'s dead vote used"
    end,
})

minetest.register_chatcommand("botc_time", {
    params = "<day|evening|night>",
    description = "Set time of day",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param ~= "day" and param ~= "evening" and param ~= "night" then
            return false, "Usage: /botc_time <day|evening|night>"
        end
        botc.ST.phase = param
        if param == "day" then
            botc.ST.current_day = botc.ST.current_day + 1
            botc.ST.nominations[botc.ST.current_day] = { nominators = {}, nominees = {} }
            botc.ST.clock_state = "idle"
            botc.ST.execution_target = nil
            botc.ST.nomination_votes = {}
            botc.ST.current_timeofday = 0.50
            botc.refill_chests()
        elseif param == "evening" then
            botc.ST.nomination_votes = {}
            botc.ST.current_timeofday = 0.783
        elseif param == "night" then
            botc.ST.execution_target = nil
            botc.ST.nomination_votes = {}
            botc.ST.current_timeofday = 0.0
            botc.ST.meta_steps_done = {}
            local night_roles = botc.get_night_order_roles(botc.ST.current_day)
            local night_set = {}
            for _, r in ipairs(night_roles) do
                night_set[r] = true
            end
            for pname, data in pairs(botc.ST.roles) do
                if data.alive then
                    local rid = botc.normalize_role_id(data.role)
                    if night_set[rid] then
                        data.markers = data.markers or {}
                        local has_visit = false
                        for _, m in ipairs(data.markers) do
                            if m == "VISIT" then has_visit = true; break end
                        end
                        if not has_visit then
                            table.insert(data.markers, "VISIT")
                        end
                    end
                end
            end
        end
        botc.save_state()
        minetest.chat_send_all(minetest.colorize("#ffaa00", "Time is now: " .. param:upper()))
    end,
})

minetest.register_chatcommand("botc_wand", {
    params = "<script|nom|exe|kill|revive|marker|time>",
    description = "Give yourself a wand",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local wands = {
            script = "botc_storyteller:script_wand",
            nom = "botc_storyteller:nomination_wand",
            exe = "botc_storyteller:execution_wand",
            kill = "botc_storyteller:kill_wand",
            revive = "botc_storyteller:revive_wand",
            marker = "botc_storyteller:marker_wand",
            time = "botc_storyteller:time_wand",
        }
        local item = wands[param]
        if not item then return false, "Usage: /botc_wand <script|nom|exe|kill|revive|marker|time>" end
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        player:get_inventory():add_item("main", item)
        return true, "Wand given: " .. param
    end,
})

minetest.register_chatcommand("botc_note", {
    params = "",
    description = "Get a notebook",
    privs = {},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        player:get_inventory():add_item("main", "botc_storyteller:notebook")
        return true, "Notebook given"
    end,
})

minetest.register_chatcommand("fadd", {
    params = "<name>",
    description = "Add a fake player for testing",
    privs = {storyteller=true},
    func = function(name, param)
        if param == "" then return false, "Usage: /fadd <name>" end
        botc.fake_players[param] = true
        minetest.chat_send_player(name, "Fake player '" .. param .. "' added (" .. #botc.all_players() .. " total)")
        return true
    end,
})

minetest.register_chatcommand("fremove", {
    params = "<name>",
    description = "Remove a fake player",
    privs = {storyteller=true},
    func = function(name, param)
        if param == "" then return false, "Usage: /fremove <name>" end
        botc.fake_players[param] = nil
        botc.ST.roles[param] = nil
        minetest.chat_send_player(name, "Fake player '" .. param .. "' removed")
        return true
    end,
})

minetest.register_chatcommand("fclear", {
    params = "",
    description = "Remove all fake players",
    privs = {storyteller=true},
    func = function(name, param)
        botc.fake_players = {}
        minetest.chat_send_player(name, "All fake players cleared")
        return true
    end,
})

minetest.register_chatcommand("flist", {
    params = "",
    description = "List all players (real + fake)",
    privs = {storyteller = true},
    func = function(name, param)
        local all = botc.all_players()
        if #all == 0 then return true, "No players" end
        return true, "Players: " .. table.concat(all, ", ")
    end,
})

minetest.register_chatcommand("botc_debug_texture", {
    params = "<player>",
    description = "Debug: print a real player's current texture properties",
    privs = {storyteller = true},
    func = function(name, param)
        param = param:trim()
        if param == "" then return false, "Usage: /botc_debug_texture <player>" end
        local p = minetest.get_player_by_name(param)
        if not p then return false, param .. " is not a connected real player" end
        local props = p:get_properties()
        local textures = props.textures or {}
        local lines = {}
        table.insert(lines, "use_texture_alpha=" .. tostring(props.use_texture_alpha))
        table.insert(lines, "visual=" .. tostring(props.visual) .. " mesh=" .. tostring(props.mesh))
        table.insert(lines, "visual_size=" .. tostring(props.visual_size and props.visual_size.x))
        for i, t in ipairs(textures) do
            table.insert(lines, "textures[" .. i .. "]=" .. tostring(t))
        end
        local data = botc.ST.roles[param]
        table.insert(lines, "botc alive=" .. tostring(data and data.alive))
        for _, l in ipairs(lines) do
            minetest.chat_send_player(name, l)
        end
        return true
    end,
})

minetest.register_chatcommand("botc_refill", {
    params = "<set|clear|list>",
    description = "Mark a chest to refill its contents each day, or clear the mark",
    privs = {storyteller = true},
    func = function(name, param)
        local args = param:trim():split(" ")
        local action = args[1] or ""

        local function get_pointed_node(player)
            local pos = player:get_pos()
            pos.y = pos.y + 1.5
            local dir = player:get_look_dir()
            local endpos = vector.add(pos, vector.multiply(dir, 8))
            local ray = minetest.raycast(pos, endpos, false, false)
            for pt in ray do
                if pt.type == "node" then return pt.under end
            end
            return nil
        end

        if action == "list" then
            local count = 0
            for _ in pairs(botc.ST.refill_chests) do count = count + 1 end
            if count == 0 then
                return true, "No refill chests marked"
            end
            local lines = {}
            for phash, _ in pairs(botc.ST.refill_chests) do
                local p = minetest.string_to_pos(phash)
                if p then
                    table.insert(lines, minetest.pos_to_string(p))
                end
            end
            return true, count .. " refill chest(s):\n" .. table.concat(lines, "\n")
        end

        local p = minetest.get_player_by_name(name)
        if not p then return false, "You must be in-game" end

        if action == "set" then
            local pointed = get_pointed_node(p)
            if not pointed then
                return false, "Point at a chest to mark it"
            end
            local node = minetest.get_node_or_nil(pointed)
            if not node then return false, "No node found" end
            local meta = minetest.get_meta(pointed)
            local inv = meta:get_inventory()
            if not inv then
                return false, "That's not a container"
            end
            local listname = "main"
            local list = inv:get_list("main")
            if not list then
                local lists = inv:get_lists()
                for k, v in pairs(lists) do
                    if type(v) == "table" and #v > 0 then
                        listname = k
                        list = v
                        break
                    end
                end
                if not list then
                    return false, "No inventory list found"
                end
            end
            local phash = minetest.pos_to_string(pointed)
            local snapshot = {}
            for slot, item in ipairs(list) do
                if not item:is_empty() then
                    snapshot[slot] = item:to_string()
                end
            end
            botc.ST.refill_chests[phash] = {pos = pointed, inv = snapshot, listname = listname}
            botc.save_state()
            local item_count = 0
            for _ in pairs(snapshot) do item_count = item_count + 1 end
            return true, "Chest at " .. phash .. " marked for daily refill (" .. #list .. " slots, " .. item_count .. " items)"
        elseif action == "clear" then
            local pointed = get_pointed_node(p)
            if not pointed then
                return false, "Point at a marked chest to clear it"
            end
            local phash = minetest.pos_to_string(pointed)
            if botc.ST.refill_chests[phash] then
                botc.ST.refill_chests[phash] = nil
                botc.save_state()
                return true, "Chest at " .. phash .. " no longer marked for refill"
            else
                return false, "That chest is not marked"
            end
        end

        return false, "Usage: /botc_refill <set|clear|list>"
    end,
})
