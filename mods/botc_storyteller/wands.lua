local function raycast_player(user)
    local user_name = user:get_player_name()
    local pos = user:get_pos()
    pos.y = pos.y + 1.5
    local dir = user:get_look_dir()
    pos = vector.add(pos, vector.multiply(dir, 0.6))
    local endpos = vector.add(pos, vector.multiply(dir, 20))
    local ray = minetest.raycast(pos, endpos, true, false)
    for pt in ray do
        if pt.type == "node" then
            return nil
        elseif pt.type == "object" then
            if pt.ref:is_player() then
                local name = pt.ref:get_player_name()
                if name ~= user_name then return name end
            else
                local luaent = pt.ref:get_luaentity()
                if luaent and luaent.name == "botc_storyteller:fake_player" and luaent.fake_name ~= "" then
                    if luaent.fake_name ~= user_name then return luaent.fake_name end
                end
            end
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
    local items = botc.all_players()
    table.sort(items)
    if #items == 0 then
        minetest.chat_send_player(viewer, "No players online")
        return
    end
    local fs = "size[6,8]label[0.5,0.3;Select a player (double-click):]textlist[0.5,1;5,7;players;" .. table.concat(items, ",") .. ";0]"
    minetest.show_formspec(viewer, formname_prefix .. "_list", fs)
end

local NOTE_COLORS = {"White", "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "Pink", "Gray"}
local NOTE_COLOR_HEX = {
    White = "#ffffff", Red = "#ff4444", Orange = "#ff7700",
    Yellow = "#ffcc00", Green = "#44cc44", Cyan = "#44cccc",
    Blue = "#4444ff", Purple = "#aa44ff", Pink = "#ff88cc", Gray = "#888888",
}

function botc.show_notebook_formspec(viewer, target)
    local notes = botc.ST.player_notes[viewer] or {}
    local entry = notes[target]
    local pub_text = ""
    local priv_text = ""
    local current_color = ""
    if type(entry) == "table" then
        pub_text = entry.public or ""
        priv_text = entry.private or ""
        current_color = entry.color or ""
    elseif type(entry) == "string" then
        priv_text = entry
    end
    local color_idx = 0
    if current_color ~= "" then
        for i, name in ipairs(NOTE_COLORS) do
            if NOTE_COLOR_HEX[name] == current_color then
                color_idx = i - 1
                break
            end
        end
    end
    local fs = "size[8,10]label[0.5,0.3;Notes for " .. minetest.formspec_escape(target) .. "]"
    fs = fs .. "label[0.5,0.8;Public (shown over player's head)]"
    fs = fs .. "textarea[0.5,1.2;7,1;note_public;;" .. minetest.formspec_escape(pub_text) .. "]"
    fs = fs .. "label[0.5,2.7;Private (notebook only)]"
    fs = fs .. "textarea[0.5,3.1;7,3;note_private;;" .. minetest.formspec_escape(priv_text) .. "]"
    fs = fs .. "label[0.5,6.5;Color]"
    fs = fs .. "dropdown[1.5,6.4;5,0.5;note_color;White,Red,Orange,Yellow,Green,Cyan,Blue,Purple,Pink,Gray;" .. color_idx .. "]"
    fs = fs .. "button[0.5,7.5;2.5,0.8;note_save;Save]"
    fs = fs .. "button[3.5,7.5;2.5,0.8;note_clear;Clear]"
    fs = fs .. "button_exit[6.5,7.5;1.5,0.8;close;Close]"
    fs = fs .. "field_close_on_enter[note_public;false]field_close_on_enter[note_private;false]"
    minetest.show_formspec(viewer, "botc_storyteller:notebook_" .. target, fs)
end

function botc.show_script_assign_formspec(name, target)
    if not botc.ST.script then
        minetest.chat_send_player(name, "No script loaded")
        return
    end
    local fs = "size[8,12]label[0.5,0.5;Assign role to " .. target .. "]textlist[0.5,1;7,8;roles;"
    local items = {}
    for _, entry in ipairs(botc.ST.script) do
        local rname = botc.resolve_name(entry)
        if rname then
            table.insert(items, rname)
        end
    end
    fs = fs .. table.concat(items, ",") .. "]"
    fs = fs .. "button[0.5,9.2;3,1;assign;Assign]button[4,9.2;3,1;cancel;Cancel]"
    fs = fs .. "button[0.5,10.5;7,1;build_bag;Build Bag]"
    minetest.show_formspec(name, "botc_storyteller:script_wand_" .. target, fs)
end

function botc.show_bag_formspec(pname)
    if not botc.ST.script then
        minetest.show_formspec(pname, "botc_storyteller:bag",
            "size[8,4]" ..
            "label[0.5,1;Load a script first (/botc_script filename.json)]" ..
            "button[2.5,2.5;3,1;bag_close;Close]"
        )
        return
    end

    local teams = {townsfolk={}, outsider={}, minion={}, demon={}}
    for _, entry in ipairs(botc.ST.script) do
        local team = botc.resolve_team(entry)
        local name = botc.resolve_name(entry)
        if teams[team] then
            table.insert(teams[team], {id = entry.id, name = name})
        end
    end
    local team_order = {"townsfolk", "outsider", "minion", "demon"}
    local team_labels = {townsfolk="Townsfolk", outsider="Outsiders", minion="Minions", demon="Demons"}

    local left_entries = {}
    for _, team in ipairs(team_order) do
        local roles = teams[team]
        if #roles > 0 then
            table.insert(left_entries, "#" .. team_labels[team])
            for _, r in ipairs(roles) do
                table.insert(left_entries, r.name)
            end
        end
    end

    local right_entries = {}
    for _, team in ipairs(team_order) do
        local has_any = false
        for _, r in ipairs(teams[team]) do
            local count = botc.ST.bag[r.id] or 0
            if count > 0 then
                if not has_any then
                    table.insert(right_entries, "#" .. team_labels[team])
                    has_any = true
                end
                table.insert(right_entries, count .. "x " .. r.name)
            end
        end
    end
    if #right_entries == 0 then
        table.insert(right_entries, "(empty)")
    end

    local player_count = 0
    for _, p in ipairs(minetest.get_connected_players()) do
        local pn = p:get_player_name()
        if not pn:find("^#") and not minetest.check_player_privs(pn, {storyteller=true}) then
            player_count = player_count + 1
        end
    end
    local base = botc.get_team_counts(player_count) or {townsfolk=0, outsider=0, minion=0, demon=0}

    local actual = {townsfolk=0, outsider=0, minion=0, demon=0}
    for id, count in pairs(botc.ST.bag) do
        local team = botc.resolve_team(id)
        if actual[team] then
            actual[team] = actual[team] + count
        end
    end

    local stats = string.format("Town: %d/%d  Outsiders: %d/%d  Minions: %d/%d  Demon: %d/%d",
        actual.townsfolk, base.townsfolk,
        actual.outsider, base.outsider,
        actual.minion, base.minion,
        actual.demon, base.demon)

    minetest.show_formspec(pname, "botc_storyteller:bag",
        "size[12,12]" ..
        "label[0.5,0.5;Available Roles (click to add)]" ..
        "label[6.5,0.5;Bag (click to select, then Remove)]" ..
        "textlist[0.5,1;5,8;bag_roles;" .. table.concat(left_entries, ",") .. ";0]" ..
        "textlist[6.5,1;5,6;bag_contents;" .. table.concat(right_entries, ",") .. ";0]" ..
        "button[6.5,7.5;2.5,1;bag_remove;Remove Selected]" ..
        "label[0.5,9.5;" .. minetest.formspec_escape(stats) .. "]" ..
        "button[3,10.5;2.5,1;bag_passout;Pass Out Roles]" ..
        "button[6.5,10.5;2.5,1;bag_close;Close]" ..
        "button[9.5,10.5;2.5,1;bag_clear;Clear]"
    )
end

function botc.show_timer_formspec(pname)
    local remaining = math.max(0, botc.ST.timer_duration - botc.ST.timer_elapsed)
    local status
    if botc.ST.timer_active then
        status = "Running: " .. string.format("%d:%02d", math.floor(remaining / 60), math.floor(remaining % 60))
    else
        status = "Inactive"
    end
    minetest.show_formspec(pname, "botc_storyteller:timer",
        "size[8,5]" ..
        "label[0.5,0.5;" .. minetest.formspec_escape("Status: " .. status) .. "]" ..
        "label[0.5,1.3;Duration (seconds):]" ..
        "field[5,1;2,1;timer_dur;;" .. minetest.formspec_escape(tostring(botc.ST.timer_duration)) .. "]" ..
        "label[0.5,2.3;Timer name:]" ..
        "field[5,2;2,1;timer_name;;" .. minetest.formspec_escape(botc.ST.timer_name) .. "]" ..
        "button[0.5,3.5;2.5,1;timer_start;Start]" ..
        "button[3.5,3.5;2.5,1;timer_stop;Stop]" ..
        "button[6.5,3.5;1.5,1;timer_close;Close]"
    )
end

local WAND_TEXTURES = {
    script_wand = "Wandselectscript.png",
    nomination_wand = "Wandndemblemnominated.png",
    execution_wand = "Wandandemblemexicute.png",
    kill_wand = "wandkill.png",
    revive_wand = "Wandresurect1.png",
    marker_wand = "wandstorytellernotes.png",
    time_wand = "WandTime.png",
}

local function get_target(user, pointed_thing)
    local user_name = user:get_player_name()
    local result
    if pointed_thing.type == "object" then
        local ref = pointed_thing.ref
        if ref:is_player() then
            local name = ref:get_player_name()
            if name ~= user_name then result = name end
        end
        if not result then
            local luaent = ref:get_luaentity()
            if luaent and luaent.name == "botc_storyteller:fake_player" and luaent.fake_name ~= "" then
                if luaent.fake_name ~= user_name then result = luaent.fake_name end
            end
        end
    elseif pointed_thing.type == "nothing" then
        result = raycast_player(user)
    end
    if result == user_name then return nil end
    return result
end

local nomination_step1 = {} -- { [username] = nominator }
local script_selection = {}  -- { [formname] = selected_index } for textlist+button pattern

-- Script wand
minetest.register_tool("botc_storyteller:script_wand", {
    description = "Script Wand",
    inventory_image = WAND_TEXTURES.script_wand,
    on_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        local target = get_target(user, pointed_thing)
        if not target then
            if not botc.ST.script then
                minetest.chat_send_player(name, "No script loaded. Use /botc_loadscript first.")
            else
                botc.show_player_list_formspec(name, "botc_storyteller:wand_script")
            end
            return itemstack
        end
        if not botc.ST.script then
            minetest.chat_send_player(name, "No script loaded. Use /botc_loadscript first.")
            return itemstack
        end
        botc.show_script_assign_formspec(name, target)
        return itemstack
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
        if not target then
            botc.show_player_list_formspec(name, "botc_storyteller:wand_nomination")
            return itemstack
        end

        local actor = botc.resolve_actor(name)
        if nomination_step1[actor] then
            local nominator = nomination_step1[actor]
            nomination_step1[actor] = nil
            local nom_ok, nom_err = botc.check_nomination(nominator, target)
            if not nom_ok then
                minetest.chat_send_player(name, nom_err)
                return itemstack
            end
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
            botc.manage_clock_hand()
            minetest.chat_send_all(minetest.colorize("#ffaa00", nominator .. " nominates " .. target .. " for execution!"))
        else
            -- Step 1: the nominator
            local ndata = botc.ST.roles[target]
            if ndata and not ndata.alive then
                minetest.chat_send_player(name, target .. " is dead and cannot nominate")
                return itemstack
            end
            nomination_step1[actor] = target
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
        if not target then
            botc.show_player_list_formspec(name, "botc_storyteller:wand_execution")
            return itemstack
        end
        if not botc.ST.execution_zone then
            minetest.chat_send_player(name, "No execution zone set. Use /botc_exezone set")
            return itemstack
        end
        local player = botc.get_player(target)
        if not player then
            minetest.chat_send_player(name, "Player " .. target .. " not online")
            return itemstack
        end
        local ez = botc.ST.execution_zone
        local epos = {x = ez.x, y = ez.y, z = ez.z}
        if botc.is_execution_zone_pyre() then
            epos = {x = ez.x + -0.4, y = ez.y, z = ez.z}
            botc.pyre_spawn_fire(ez)
            if minetest.get_player_by_name(target) then
                player:set_physics_override({gravity = 0, speed = 0, jump = 0})
            end
            minetest.after(13.5, function()
                local data = botc.ST.roles[target]
                if data and data.alive then
                    data.alive = false
                    botc.sync_vote_block_for_player(target)
                    botc.update_alive_texture(target)
                    botc.save_state()
                    minetest.chat_send_all(minetest.colorize("#ff4444", target .. " has been executed!"))
                end
            end)
            minetest.after(17, function()
                local p = minetest.get_player_by_name(target)
                if p then
                    p:set_physics_override({gravity = 1, speed = 1, jump = 1})
                end
            end)
        end
        player:set_pos(epos)
        player:set_velocity({x = 0, y = 0, z = 0})
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
        if not target then
            botc.show_player_list_formspec(name, "botc_storyteller:wand_kill")
            return itemstack
        end
        local data = botc.ST.roles[target]
        if not data then
            minetest.chat_send_player(name, target .. " has no role assigned")
            return itemstack
        end
        data.alive = false
        botc.sync_vote_block_for_player(target)
        botc.update_alive_texture(target)
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
        if not target then
            botc.show_player_list_formspec(name, "botc_storyteller:wand_revive")
            return itemstack
        end
        local data = botc.ST.roles[target]
        if not data then
            minetest.chat_send_player(name, target .. " has no role assigned")
            return itemstack
        end
        data.alive = true
        data.dead_vote_used = false
        if data._pyre_hidden then
            botc.pyre_show_player(target)
        end
        botc.sync_vote_block_for_player(target)
        botc.update_alive_texture(target)
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
            botc.ST.execution_target = nil
            botc.ST.current_timeofday = 0.50
        elseif new_phase == "evening" then
            botc.ST.current_timeofday = 0.783
        elseif new_phase == "night" then
            botc.ST.execution_target = nil
            botc.ST.current_timeofday = 0.0
        end
        botc.save_state()
        minetest.chat_send_all(minetest.colorize("#ffaa00", "Time is now: " .. new_phase:upper()))
        return itemstack
    end,
    on_place = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        botc.show_timer_formspec(name)
        return itemstack
    end,
    on_secondary_use = function(itemstack, user, pointed_thing)
        local name = user:get_player_name()
        if not minetest.check_player_privs(name, {storyteller = true}) then return itemstack end
        botc.show_timer_formspec(name)
        return itemstack
    end,
})

minetest.register_tool("botc_storyteller:notebook", {
    description = "Player Notebook",
    wield_scale = {x = 2, y = 2, z = 2},
    mesh = "book_feather.obj",
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
    if formname:match("^botc_storyteller:notebook_") and formname ~= "botc_storyteller:notebook_list" then
        local target = formname:match("^botc_storyteller:notebook_(.+)$")
        if fields.note_save then
            if not botc.ST.player_notes[name] then botc.ST.player_notes[name] = {} end
            local selected_color = fields.note_color
            botc.ST.player_notes[name][target] = {
                public = fields.note_public or "",
                private = fields.note_private or "",
                color = NOTE_COLOR_HEX[selected_color],
            }
            botc.save_state()
            minetest.chat_send_player(name, "Notes saved for " .. target)
        end
        if fields.note_clear then
            if botc.ST.player_notes[name] then
                botc.ST.player_notes[name][target] = nil
            end
            botc.save_state()
            minetest.chat_send_player(name, "Notes cleared for " .. target)
        end
        return true
    end

    -- Notebook player list selection (no priv needed)
    if formname == "botc_storyteller:notebook_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL") then
                                local names = botc.all_players()
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

    -- Wand player list selection: script
    if formname == "botc_storyteller:wand_script_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL") then
                                local names = botc.all_players()
                                table.sort(names)
                if selected.index and names[selected.index] then
                    botc.show_script_assign_formspec(name, names[selected.index])
                end
            end
        end
        return true
    end

    -- Wand player list selection: nomination
    if formname == "botc_storyteller:wand_nomination_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL") then
                                local names = botc.all_players()
                                table.sort(names)
                if selected.index and names[selected.index] then
                    local target = names[selected.index]
                    local day = botc.ST.current_day
                    if not botc.ST.nominations[day] then
                        botc.ST.nominations[day] = { nominators = {}, nominees = {} }
                    end
                    if nomination_step1[name] then
                        local nominator = nomination_step1[name]
                        nomination_step1[name] = nil
                        local nom_ok, nom_err = botc.check_nomination(nominator, target)
                        if not nom_ok then
                            minetest.chat_send_player(name, nom_err)
                        elseif botc.ST.nominations[day].nominators[nominator] then
                            minetest.chat_send_player(name, nominator .. " has already nominated today")
                        elseif botc.ST.nominations[day].nominees[target] then
                            minetest.chat_send_player(name, target .. " has already been nominated today")
                        else
                            botc.ST.nominations[day].nominators[nominator] = true
                            botc.ST.nominations[day].nominees[target] = true
                            botc.ST.clock_nominator = nominator
                            botc.ST.clock_nominee = target
                            botc.ST.clock_state = "nominating"
                            botc.save_state()
                            botc.manage_clock_hand()
                            minetest.chat_send_all(minetest.colorize("#ffaa00", nominator .. " nominates " .. target .. " for execution!"))
                        end
                    else
                        local ndata = botc.ST.roles[target]
                        if ndata and not ndata.alive then
                            minetest.chat_send_player(name, target .. " is dead and cannot nominate")
                        else
                            nomination_step1[name] = target
                            minetest.chat_send_player(name, "Nominator set: " .. target .. ". Now select the nominee.")
                        end
                    end
                end
            end
        end
        return true
    end

    -- Wand player list selection: execution
    if formname == "botc_storyteller:wand_execution_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL") then
                                local names = botc.all_players()
                                table.sort(names)
                if selected.index and names[selected.index] then
                    local target = names[selected.index]
                    if not botc.ST.execution_zone then
                        minetest.chat_send_player(name, "No execution zone set. Use /botc_exezone set")
                    else
                        local player = botc.get_player(target)
                        if player then
                            local ez = botc.ST.execution_zone
                            local epos = {x = ez.x, y = ez.y, z = ez.z}
                            if botc.is_execution_zone_pyre() then
                                epos = {x = ez.x + -0.4, y = ez.y, z = ez.z}
                                botc.pyre_spawn_fire(ez)
                                if minetest.get_player_by_name(target) then
                                    player:set_physics_override({gravity = 0, speed = 0, jump = 0})
                                end
                                minetest.after(13.5, function()
                                    local data = botc.ST.roles[target]
                                    if data and data.alive then
                                        data.alive = false
                                        botc.sync_vote_block_for_player(target)
                                        botc.update_alive_texture(target)
                                        botc.save_state()
                                        minetest.chat_send_all(minetest.colorize("#ff4444", target .. " has been executed!"))
                                    end
                                end)
                                minetest.after(17, function()
                                    local p = minetest.get_player_by_name(target)
                                    if p then
                                        p:set_physics_override({gravity = 1, speed = 1, jump = 1})
                                    end
                                end)
                            end
                            player:set_pos(epos)
                            player:set_velocity({x = 0, y = 0, z = 0})
                            minetest.chat_send_player(name, target .. " summoned to execution zone")
                        end
                    end
                end
            end
        end
        return true
    end

    -- Wand player list selection: kill
    if formname == "botc_storyteller:wand_kill_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL") then
                                local names = botc.all_players()
                                table.sort(names)
                if selected.index and names[selected.index] then
                    local target = names[selected.index]
                    local data = botc.ST.roles[target]
                    if not data then
                        minetest.chat_send_player(name, target .. " has no role assigned")
                    else
                        data.alive = false
                        botc.sync_vote_block_for_player(target)
                        botc.update_alive_texture(target)
                        botc.save_state()
                        minetest.chat_send_all(minetest.colorize("#ff4444", target .. " has been killed!"))
                    end
                end
            end
        end
        return true
    end

    -- Wand player list selection: revive
    if formname == "botc_storyteller:wand_revive_list" then
        if fields.players then
            local selected = minetest.explode_textlist_event(fields.players)
            if selected and (selected.type == "DCL") then
                                local names = botc.all_players()
                                table.sort(names)
                if selected.index and names[selected.index] then
                    local target = names[selected.index]
                    local data = botc.ST.roles[target]
                    if not data then
                        minetest.chat_send_player(name, target .. " has no role assigned")
                    else
                        data.alive = true
                        data.dead_vote_used = false
                        if data._pyre_hidden then
                            botc.pyre_show_player(target)
                        end
                        botc.sync_vote_block_for_player(target)
                        botc.update_alive_texture(target)
                        botc.save_state()
                        minetest.chat_send_all(minetest.colorize("#44ff44", target .. " has been revived!"))
                    end
                end
            end
        end
        return true
    end

    -- Script wand assign
    if formname:match("^botc_storyteller:script_wand_") then
        local target = formname:match("^botc_storyteller:script_wand_(.+)$")
        if not botc.ST.script then return true end
        if fields.build_bag then
            botc.show_bag_formspec(name)
            return true
        end
        if fields.roles then
            local ev = minetest.explode_textlist_event(fields.roles)
            if ev and ev.type == "CHG" and ev.index then
                script_selection[formname] = ev.index
            end
        end
        if fields.assign then
            local idx = script_selection[formname]
            if idx and botc.ST.script[idx] then
                local ok, msg = botc.assign_role(target, botc.ST.script[idx])
                minetest.chat_send_player(name, msg)
                script_selection[formname] = nil
            else
                minetest.chat_send_player(name, "Select a role from the list first")
            end
        end
        return true
    end

    -- Marker formspec
    if formname:match("^botc_storyteller:marker_") then
        local target = formname:match("^botc_storyteller:marker_(.+)$")
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
            if selected and (selected.type == "DCL") then
                                local names = botc.all_players()
                                table.sort(names)
                if selected.index and names[selected.index] then
                    botc.show_marker_formspec(name, names[selected.index])
                end
            end
        end
        return true
    end

    -- Bag formspec
    if formname == "botc_storyteller:bag" then
        if fields.bag_close or fields.quit then
            return true
        end

        local refresh = false

        if fields.bag_roles then
            local ev = minetest.explode_textlist_event(fields.bag_roles)
            if ev.type == "CHG" and ev.index then
                local entries = {}
                local team_order = {"townsfolk", "outsider", "minion", "demon"}
                local grouped = {townsfolk={}, outsider={}, minion={}, demon={}}
                for _, entry in ipairs(botc.ST.script) do
                    local team = botc.resolve_team(entry)
                    if grouped[team] then
                        table.insert(grouped[team], entry)
                    end
                end
                for _, team in ipairs(team_order) do
                    for _, r in ipairs(grouped[team]) do
                        table.insert(entries, r)
                    end
                end
                if ev.index <= #entries then
                    local role = entries[ev.index]
                    botc.ST.bag[role.id] = (botc.ST.bag[role.id] or 0) + 1
                    botc.save_state()
                    refresh = true
                end
            end
        end

        if fields.bag_remove then
            local ev = fields.bag_contents and minetest.explode_textlist_event(fields.bag_contents)
            if ev and ev.type == "CHG" and ev.index then
                local bag_flat = {}
                local team_order = {"townsfolk", "outsider", "minion", "demon"}
                local grouped = {townsfolk={}, outsider={}, minion={}, demon={}}
                for _, entry in ipairs(botc.ST.script) do
                    local team = botc.resolve_team(entry)
                    if grouped[team] then
                        table.insert(grouped[team], entry)
                    end
                end
                for _, team in ipairs(team_order) do
                    for _, r in ipairs(grouped[team]) do
                        local count = botc.ST.bag[r.id] or 0
                        if count > 0 then
                            table.insert(bag_flat, r)
                        end
                    end
                end
                if ev.index <= #bag_flat then
                    local role = bag_flat[ev.index]
                    botc.ST.bag[role.id] = botc.ST.bag[role.id] - 1
                    if botc.ST.bag[role.id] <= 0 then
                        botc.ST.bag[role.id] = nil
                    end
                    botc.save_state()
                    refresh = true
                end
            end
        end

        if fields.bag_clear then
            botc.ST.bag = {}
            botc.save_state()
            refresh = true
        end

        if fields.bag_passout then
            local ok, msg = botc.passout_from_bag()
            if ok then
                minetest.chat_send_player(name, "Passed out roles from bag.")
            else
                minetest.chat_send_player(name, "Error: " .. msg)
            end
            return true
        end

        if refresh then
            botc.show_bag_formspec(name)
        end
        return true
    end

    -- Timer formspec
    if formname == "botc_storyteller:timer" then
        if fields.timer_close or fields.quit then
            return true
        end
        if fields.timer_name then
            botc.ST.timer_name = fields.timer_name
            botc.save_state()
        end
        if fields.timer_dur then
            local d = tonumber(fields.timer_dur)
            if d and d > 0 then
                botc.ST.timer_duration = d
                botc.save_state()
            end
        end
        if fields.timer_start then
            botc.ST.timer_elapsed = 0
            botc.ST.timer_active = true
            botc.save_state()
            minetest.chat_send_all(minetest.colorize("#ffaa00", "Timer started: " .. (botc.ST.timer_name ~= "" and botc.ST.timer_name or "Unnamed") .. " (" .. botc.ST.timer_duration .. "s)"))
        end
        if fields.timer_stop then
            botc.ST.timer_active = false
            botc.ST.timer_elapsed = 0
            botc.save_state()
            minetest.chat_send_all(minetest.colorize("#ffaa00", "Timer stopped."))
        end
        botc.show_timer_formspec(name)
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
minetest.override_item("botc_storyteller:notebook", { on_place = minetest.registered_tools["botc_storyteller:notebook"].on_use })
minetest.override_item("botc_storyteller:notebook", { on_place = minetest.registered_tools["botc_storyteller:notebook"].on_use })
