local function raycast_player(user)
    local pos = user:get_pos()
    pos.y = pos.y + 1.5 -- eye level
    local dir = user:get_look_dir()
    local endpos = vector.add(pos, vector.multiply(dir, 20))
    local ray = minetest.raycast(pos, endpos, false, false)
    for pt in ray do
        if pt.type == "object" and pt.ref:is_player() then
            return pt.ref:get_player_name()
        end
    end
    return nil
end

local QUICK_MARKERS = { "POISONED", "DRUNK", "PROTECTED", "FALSE INFO", "RED HERRING", "DEAD" }

function botc.show_marker_formspec(viewer, target)
    local data = botc.ST.roles[target]
    local current = data and data.markers and table.concat(data.markers, ", ") or ""
    local fs = "size[8,7]label[0.5,0.3;Markers for " .. target .. ": " .. minetest.formspec_escape(current) .. "]"
    local y = 1.2
    for i, m in ipairs(QUICK_MARKERS) do
        local x = (i - 1) % 3
        local row = math.floor((i - 1) / 3)
        fs = fs .. "button[" .. (0.5 + x * 2.5) .. "," .. (y + row * 1) .. ";2.3,0.8;marker_" .. m .. ";" .. m .. "]"
    end
    fs = fs .. "button[0.5,3.5;2.3,0.8;marker_clear;CLEAR]"
    fs = fs .. "field[0.5,4.7;7,0.8;mad_as;MAD AS;]"
    fs = fs .. "button[3,4.7;2,0.8;marker_mad_as;Set MAD]"
    fs = fs .. "field[0.5,5.9;7,0.8;custom_marker;Custom;]"
    fs = fs .. "button[3,5.9;2,0.8;marker_custom;Set Custom]"
    fs = fs .. "button_exit[2,6.7;3,0.8;close;Close]"
    minetest.show_formspec(viewer, "botc_storyteller:marker_" .. target, fs)
end

function botc.show_player_list_formspec(viewer, formname_prefix)
    local players = minetest.get_connected_players()
    local items = {}
    for _, p in ipairs(players) do
        table.insert(items, p:get_player_name())
    end
    table.sort(items)
    if #items == 0 then
        minetest.chat_send_player(viewer, "No players online")
        return
    end
    local fs = "size[6,8]label[0.5,0.3;Select a player (double-click):]textlist[0.5,1;5,7;players;" .. table.concat(items, ",") .. "]"
    minetest.show_formspec(viewer, formname_prefix .. "_list", fs)
end

function botc.show_notebook_formspec(viewer, target)
    local notes = botc.ST.player_notes[viewer] or {}
    local current = notes[target] or ""
    local fs = "size[8,5]label[0.5,0.3;Notes for " .. minetest.formspec_escape(target) .. "]"
    fs = fs .. "textarea[0.5,1;7,3;note_text;;" .. minetest.formspec_escape(current) .. "]"
    fs = fs .. "button[0.5,4.2;2.5,0.8;note_save;Save]"
    fs = fs .. "button[3.5,4.2;2.5,0.8;note_clear;Clear]"
    fs = fs .. "button_exit[6.5,4.2;1.5,0.8;close;Close]"
    fs = fs .. "field_close_on_enter[note_text;false]"
    minetest.show_formspec(viewer, "botc_storyteller:notebook_" .. target, fs)
end

local WAND_TEXTURES = {
    script_wand = "default_stick.png^[colorize:#ffaa00:128",
    nomination_wand = "default_stick.png^[colorize:#4488ff:128",
    execution_wand = "default_stick.png^[colorize:#ff2222:128",
    kill_wand = "default_stick.png^[colorize:#666666:128",
    revive_wand = "default_stick.png^[colorize:#44ff44:128",
    marker_wand = "default_stick.png^[colorize:#ff44ff:128",
    time_wand = "default_stick.png^[colorize:#ffff44:128",
}

local function get_target(user, pointed_thing)
    if pointed_thing.type == "object" then
        local ref = pointed_thing.ref
        if ref and ref:is_player() then
            return ref:get_player_name()
        end
    elseif pointed_thing.type == "nothing" then
        return raycast_player(user)
    end
    return nil
end

local nomination_step1 = {} -- { [username] = nominator }

-- Script wand
minetest.register_tool("botc_storyteller:script_wand", {
    description = "Script Wand",
    inventory_image = WAND_TEXTURES.script_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        local target = get_target(user, pointed_thing)
        if not target then return itemstack end
        if not botc.ST.script then
            minetest.chat_send_player(name, "No script loaded. Use /botc_loadscript first.")
            return itemstack
        end
        -- Build formspec
        local fs = "size[8,10]label[0.5,0.5;Assign role to " .. target .. "]textlist[0.5,1;7,8;roles;"
        local items = {}
        for _, entry in ipairs(botc.ST.script) do
            table.insert(items, botc.resolve_name(entry))
        end
        fs = fs .. table.concat(items, ",") .. "]"
        fs = fs .. "button[0.5,9.2;3,1;assign;Assign]button[4,9.2;3,1;cancel;Cancel]"
        fs = fs .. "field_close_on_enter[roles;false]"
        minetest.show_formspec(name, "botc_storyteller:script_wand_" .. target, fs)
        return itemstack
    end,
    on_place = function(itemstack, user, pointed_thing)
        return itemstack -- right-click does nothing
    end,
})

minetest.register_tool("botc_storyteller:nomination_wand", {
    description = "Nomination Wand",
    inventory_image = WAND_TEXTURES.nomination_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        if botc.ST.phase ~= "evening" then
            minetest.chat_send_player(name, "Nominations only during evening phase")
            return itemstack
        end
        local day = botc.ST.current_day
        if not botc.ST.nominations[day] then
            botc.ST.nominations[day] = { nominators = {}, nominees = {} }
        end
        local target = get_target(user, pointed_thing)
        if not target then return itemstack end

        if nomination_step1[name] then
            -- Step 2: the nominee
            local nominator = nomination_step1[name]
            nomination_step1[name] = nil
            if botc.ST.nominations[day].nominators[nominator] then
                minetest.chat_send_player(name, nominator .. " has already nominated today")
                return itemstack
            end
            if botc.ST.nominations[day].nominees[target] then
                minetest.chat_send_player(name, target .. " has already been nominated today")
                return itemstack
            end
            botc.ST.nominations[day].nominators[nominator] = true
            botc.ST.nominations[day].nominees[target] = true
            botc.ST.clock_nominator = nominator
            botc.ST.clock_nominee = target
            botc.ST.clock_state = "nominating"
            botc.save_state()
            minetest.chat_send_all(minetest.colorize("#ffaa00", nominator .. " nominates " .. target .. " for execution!"))
        else
            -- Step 1: the nominator
            nomination_step1[name] = target
            minetest.chat_send_player(name, "Nominator set: " .. target .. ". Now punch the nominee.")
        end
        return itemstack
    end,
})

minetest.register_tool("botc_storyteller:execution_wand", {
    description = "Execution Wand",
    inventory_image = WAND_TEXTURES.execution_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        local target = get_target(user, pointed_thing)
        if not target then return itemstack end
        if not botc.ST.execution_zone then
            minetest.chat_send_player(name, "No execution zone set. Use /botc_exezone set")
            return itemstack
        end
        local player = minetest.get_player_by_name(target)
        if not player then
            minetest.chat_send_player(name, "Player " .. target .. " not online")
            return itemstack
        end
        player:set_pos(botc.ST.execution_zone)
        minetest.chat_send_player(name, target .. " summoned to execution zone")
        return itemstack
    end,
})

minetest.register_tool("botc_storyteller:kill_wand", {
    description = "Kill Wand",
    inventory_image = WAND_TEXTURES.kill_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        local target = get_target(user, pointed_thing)
        if not target then return itemstack end
        local data = botc.ST.roles[target]
        if not data then
            minetest.chat_send_player(name, target .. " has no role assigned")
            return itemstack
        end
        data.alive = false
        botc.save_state()
        minetest.chat_send_all(minetest.colorize("#ff4444", target .. " has been executed!"))
        return itemstack
    end,
})

minetest.register_tool("botc_storyteller:revive_wand", {
    description = "Revive Wand",
    inventory_image = WAND_TEXTURES.revive_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        local target = get_target(user, pointed_thing)
        if not target then return itemstack end
        local data = botc.ST.roles[target]
        if not data then
            minetest.chat_send_player(name, target .. " has no role assigned")
            return itemstack
        end
        data.alive = true
        data.dead_vote_used = false
        botc.save_state()
        minetest.chat_send_all(minetest.colorize("#44ff44", target .. " has been revived!"))
        return itemstack
    end,
})

minetest.register_tool("botc_storyteller:marker_wand", {
    description = "Marker Wand",
    inventory_image = WAND_TEXTURES.marker_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        local target = get_target(user, pointed_thing)
        if target then
            botc.show_marker_formspec(name, target)
        else
            botc.show_player_list_formspec(name, "botc_storyteller:marker_select")
        end
        return itemstack
    end,
})

minetest.register_tool("botc_storyteller:time_wand", {
    description = "Time Wand",
    inventory_image = WAND_TEXTURES.time_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        local phases = { day = "evening", evening = "night", night = "day" }
        local new_phase = phases[botc.ST.phase]
        botc.ST.phase = new_phase
        if new_phase == "day" then
            botc.ST.current_day = botc.ST.current_day + 1
            botc.ST.nominations[botc.ST.current_day] = { nominators = {}, nominees = {} }
            botc.ST.clock_state = "idle"
            botc.ST.clock_nominator = nil
            botc.ST.clock_nominee = nil
            minetest.set_timeofday(0.5)
        elseif new_phase == "evening" then
            minetest.set_timeofday(0.75)
        elseif new_phase == "night" then
            minetest.set_timeofday(0.2)
        end
        botc.save_state()
        minetest.chat_send_all(minetest.colorize("#ffaa00", "Time is now: " .. new_phase:upper()))
        return itemstack
    end,
})

minetest.register_tool("botc_storyteller:notebook", {
    description = "Player Notebook",
    inventory_image = "default_book.png",
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        local target = get_target(user, pointed_thing)
        if target then
            botc.show_notebook_formspec(name, target)
        else
            botc.show_player_list_formspec(name, "botc_storyteller:notebook")
        end
        return itemstack
    end,
})

minetest.register_on_player_receive_fields(function(player, formname, fields)
    local name = player:get_player_name()
    local is_st = minetest.check_player_privs(name, {storyteller = true})

    -- Notebook formspec (no priv needed)
    if formname:match("^botc:notebook_") then
        local target = formname:match("^botc:notebook_(.+)$")
        if fields.note_save then
            if not botc.ST.player_notes[name] then botc.ST.player_notes[name] = {} end
            botc.ST.player_notes[name][target] = fields.note_text or ""
            botc.save_state()
            minetest.chat_send_player(name, "Note saved for " .. target)
        end
        if fields.note_clear then
            if botc.ST.player_notes[name] then
                botc.ST.player_notes[name][target] = nil
            end
            botc.save_state()
            minetest.chat_send_player(name, "Note cleared for " .. target)
        end
        return true
    end

    -- Notebook player list selection (no priv needed)
    if formname == "botc_storyteller:notebook_list" then
        if fields.select and fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and selected.type == "CHG" then
                local players = minetest.get_connected_players()
                local names = {}
                for _, p in ipairs(players) do table.insert(names, p:get_player_name()) end
                table.sort(names)
                if selected.index and names[selected.index] then
                    botc.show_notebook_formspec(name, names[selected.index])
                end
            end
        end
        return true
    end

    -- Remaining formspecs require storyteller priv
    if not is_st then return end

    -- Script wand assign
    if formname:match("^botc:script_wand_") then
        local target = formname:match("^botc:script_wand_(.+)$")
        if fields.assign and fields.roles then
            local selected = minetest.explode_textlist_event(fields.roles)
            if selected and selected.type == "CHG" then
                local idx = selected.index
                if idx and botc.ST.script and botc.ST.script[idx] then
                    local ok, msg = botc.assign_role(target, botc.ST.script[idx])
                    minetest.chat_send_player(name, msg)
                end
            end
        end
        return true
    end

    -- Marker formspec
    if formname:match("^botc:marker_") then
        local target = formname:match("^botc:marker_(.+)$")
        if not botc.ST.roles[target] then return true end
        local markers = botc.ST.roles[target].markers or {}

        for _, m in ipairs(QUICK_MARKERS) do
            local field = "marker_" .. m
            if fields[field] then
                local found = false
                for i, existing in ipairs(markers) do
                    if existing == m then table.remove(markers, i); found = true; break end
                end
                if not found then table.insert(markers, m) end
                botc.ST.roles[target].markers = markers
                botc.save_state()
                botc.show_marker_formspec(name, target)
                return true
            end
        end

        if fields.marker_clear then
            botc.ST.roles[target].markers = {}
            botc.save_state()
            botc.show_marker_formspec(name, target)
            return true
        end

        if fields.marker_mad_as then
            local mad_text = fields.mad_as or ""
            if mad_text ~= "" then
                local mad_marker = "MAD AS " .. mad_text
                table.insert(markers, mad_marker)
                botc.ST.roles[target].markers = markers
                botc.save_state()
            end
            botc.show_marker_formspec(name, target)
            return true
        end

        if fields.marker_custom then
            local custom = fields.custom_marker or ""
            if custom ~= "" then
                table.insert(markers, custom)
                botc.ST.roles[target].markers = markers
                botc.save_state()
            end
            botc.show_marker_formspec(name, target)
            return true
        end
        return true
    end

    -- Marker player list selection (double-click)
    if formname == "botc_storyteller:marker_select_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL" or selected.type == "CHG") then
                local players = minetest.get_connected_players()
                local names = {}
                for _, p in ipairs(players) do table.insert(names, p:get_player_name()) end
                table.sort(names)
                if selected.index and names[selected.index] then
                    botc.show_marker_formspec(name, names[selected.index])
                end
            end
        end
        return true
    end
            end
        end
        return true
    end

    -- Notebook formspec
    if formname:match("^botc:notebook_") then
        local target = formname:match("^botc:notebook_(.+)$")
        if fields.note_save then
            if not botc.ST.player_notes[name] then botc.ST.player_notes[name] = {} end
            botc.ST.player_notes[name][target] = fields.note_text or ""
            botc.save_state()
            minetest.chat_send_player(name, "Note saved for " .. target)
        end
        if fields.note_clear then
            if botc.ST.player_notes[name] then
                botc.ST.player_notes[name][target] = nil
            end
            botc.save_state()
            minetest.chat_send_player(name, "Note cleared for " .. target)
        end
        return true
    end

    -- Notebook player list selection (double-click)
    if formname == "botc_storyteller:notebook_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL" or selected.type == "CHG") then
                local players = minetest.get_connected_players()
                local names = {}
                for _, p in ipairs(players) do table.insert(names, p:get_player_name()) end
                table.sort(names)
                if selected.index and names[selected.index] then
                    botc.show_notebook_formspec(name, names[selected.index])
                end
            end
        end
        return true
    end
            end
        end
        return true
    end
end)

-- Make all wands work with right-click too
minetest.override_item("botc_storyteller:script_wand", { on_place = minetest.registered_tools["botc_storyteller:script_wand"].on_use })
minetest.override_item("botc_storyteller:nomination_wand", { on_place = minetest.registered_tools["botc_storyteller:nomination_wand"].on_use })
minetest.override_item("botc_storyteller:execution_wand", { on_place = minetest.registered_tools["botc_storyteller:execution_wand"].on_use })
minetest.override_item("botc_storyteller:kill_wand", { on_place = minetest.registered_tools["botc_storyteller:kill_wand"].on_use })
minetest.override_item("botc_storyteller:revive_wand", { on_place = minetest.registered_tools["botc_storyteller:revive_wand"].on_use })
minetest.override_item("botc_storyteller:marker_wand", { on_place = minetest.registered_tools["botc_storyteller:marker_wand"].on_use })
minetest.override_item("botc_storyteller:time_wand", { on_place = minetest.registered_tools["botc_storyteller:time_wand"].on_use })
minetest.override_item("botc_storyteller:notebook", { on_place = minetest.registered_tools["botc_storyteller:notebook"].on_use })
