local function require_st(name)
    if not minetest.check_player_privs(name, {storyteller = true}) then
        return false, "You need the storyteller privilege."
    end
    return true
end

minetest.register_chatcommand("botc_loadscript", {
    params = "<filename.json>",
    description = "Load a role script from the mod folder",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param == "" then return false, "Usage: /botc_loadscript <filename.json>" end
        local ok2, msg = botc.load_script(param)
        return ok2, msg
    end,
})

minetest.register_chatcommand("botc_passout", {
    params = "[player1 player2 ...]",
    description = "Randomly assign roles from loaded script to all online or named players",
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
    description = "Manually assign a role to a player",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local player, role = param:match("^(%S+)%s+(.+)$")
        if not player then return false, "Usage: /botc_assign <player> <role>" end
        if not botc.ST.script then return false, "No script loaded" end
        -- Find role in script
        for _, entry in ipairs(botc.ST.script) do
            if botc.resolve_name(entry):lower() == role:lower() then
                return botc.assign_role(player, entry)
            end
        end
        return false, "Role '" .. role .. "' not found in script"
    end,
})

minetest.register_chatcommand("botc_unassign", {
    params = "<player>",
    description = "Clear a player's role",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param == "" then return false, "Usage: /botc_unassign <player>" end
        return botc.unassign_role(param)
    end,
})

minetest.register_chatcommand("botc_unassign_all", {
    params = "",
    description = "Clear all role assignments and vote block claims",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        botc.ST.roles = {}
        botc.ST.vote_blocks = {}
        botc.ST.nominations = {}
        botc.ST.player_notes = {}
        botc.save_state()
        return true, "All assignments cleared"
    end,
})

minetest.register_chatcommand("botc_list", {
    params = "",
    description = "List all assigned players with role/team/status",
    privs = {},
    func = function(name, param)
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

minetest.register_chatcommand("botc_exezone", {
    params = "set",
    description = "Set the execution zone at your position",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param ~= "set" then return false, "Usage: /botc_exezone set" end
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        local pos = vector.round(player:get_pos())
        botc.ST.execution_zone = pos
        botc.save_state()
        return true, "Execution zone set at " .. minetest.pos_to_string(pos)
    end,
})

minetest.register_chatcommand("botc_nominate", {
    params = "<nominator> <nominee>",
    description = "Nominate a player for execution",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local nominator, nominee = param:match("^(%S+)%s+(%S+)$")
        if not nominator then return false, "Usage: /botc_nominate <nominator> <nominee>" end
        if botc.ST.phase ~= "evening" then return false, "Nominations only during evening phase" end
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
        minetest.chat_send_all(minetest.colorize("#ffaa00", nominator .. " nominates " .. nominee .. " for execution!"))
        return true
    end,
})

minetest.register_chatcommand("botc_startvote", {
    params = "",
    description = "Start the clock sweep for the current vote",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if botc.ST.phase ~= "evening" then return false, "Voting only during evening phase" end
        if botc.ST.clock_state ~= "nominating" then return false, "No active nomination" end
        botc.ST.clock_state = "sweeping"
        botc.ST.clock_angle = 0
        botc.save_state()
        return true, "Vote started!"
    end,
})

minetest.register_chatcommand("botc_resetclock", {
    params = "",
    description = "Reset the clock to idle",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        botc.ST.clock_state = "idle"
        botc.ST.clock_nominator = nil
        botc.ST.clock_nominee = nil
        botc.ST.clock_angle = nil
        -- Unlock all vote blocks
        for _, vb in pairs(botc.ST.vote_blocks) do
            if vb.state ~= 4 then -- don't unlock used ghost votes
                vb.locked = false
            end
        end
        botc.save_state()
        return true, "Clock reset"
    end,
})

minetest.register_chatcommand("botc_deadvote", {
    params = "<player>",
    description = "Use a dead player's ghost vote",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        if param == "" then return false, "Usage: /botc_deadvote <player>" end
        local data = botc.ST.roles[param]
        if not data then return false, "Player has no role" end
        if data.alive then return false, "Player is still alive" end
        if data.dead_vote_used then return false, "Dead vote already used" end
        data.dead_vote_used = true
        -- Lock their vote block to state 4
        for _, vb in pairs(botc.ST.vote_blocks) do
            if vb.owner == param then
                vb.state = 4
                vb.locked = true
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
            minetest.set_timeofday(0.5)
        elseif param == "evening" then
            minetest.set_timeofday(0.75)
        elseif param == "night" then
            minetest.set_timeofday(0.2)
        end
        botc.save_state()
        minetest.chat_send_all(minetest.colorize("#ffaa00", "Time is now: " .. param:upper()))
    end,
})

minetest.register_chatcommand("botc_wand", {
    params = "<script|nomination|execution|kill|revive|marker|time>",
    description = "Give yourself a storyteller wand",
    privs = {},
    func = function(name, param)
        local ok, err = require_st(name) if not ok then return false, err end
        local wands = {
            script = "botc_storyteller:script_wand",
            nomination = "botc_storyteller:nomination_wand",
            execution = "botc_storyteller:execution_wand",
            kill = "botc_storyteller:kill_wand",
            revive = "botc_storyteller:revive_wand",
            marker = "botc_storyteller:marker_wand",
            time = "botc_storyteller:time_wand",
        }
        local item = wands[param]
        if not item then return false, "Unknown wand type. Options: script, nomination, execution, kill, revive, marker, time" end
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        player:get_inventory():add_item("main", item)
        return true, "Wand given: " .. param
    end,
})

minetest.register_chatcommand("botc_notebook", {
    params = "",
    description = "Get a player notebook",
    privs = {},
    func = function(name, param)
        local player = minetest.get_player_by_name(name)
        if not player then return false, "Player not found" end
        player:get_inventory():add_item("main", "botc_storyteller:notebook")
        return true, "Notebook given"
    end,
})
