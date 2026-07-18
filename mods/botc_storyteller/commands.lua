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
            botc.save_state()
            return true, "All assignments cleared"
        end
        return botc.unassign_role(param)
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
            botc.ST.current_timeofday = 0.50
        elseif param == "evening" then
            botc.ST.current_timeofday = 0.783
        elseif param == "night" then
            botc.ST.execution_target = nil
            botc.ST.current_timeofday = 0.0
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
