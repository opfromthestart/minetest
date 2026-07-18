local modpath = minetest.get_modpath("botc_storyteller")

-- Built-in role → team mapping from allroles.txt
local DEFAULT_TEAMS = {
    -- Townsfolk
    washerwoman = "townsfolk", librarian = "townsfolk", investigator = "townsfolk",
    chef = "townsfolk", empath = "townsfolk", fortune_teller = "townsfolk",
    undertaker = "townsfolk", monk = "townsfolk", ravenkeeper = "townsfolk",
    virgin = "townsfolk", slayer = "townsfolk", soldier = "townsfolk",
    mayor = "townsfolk", acrobat = "townsfolk", alchemist = "townsfolk",
    alsaahir = "townsfolk", amnesiac = "townsfolk", artist = "townsfolk",
    atheist = "townsfolk", balloonist = "townsfolk", banshee = "townsfolk",
    bounty_hunter = "townsfolk", cannibal = "townsfolk", chambermaid = "townsfolk",
    choirboy = "townsfolk", clockmaker = "townsfolk", courtier = "townsfolk",
    cult_leader = "townsfolk", dreamer = "townsfolk", engineer = "townsfolk",
    exorcist = "townsfolk", farmer = "townsfolk", fisherman = "townsfolk",
    flowergirl = "townsfolk", fool = "townsfolk", gambler = "townsfolk",
    general = "townsfolk", gossip = "townsfolk", grandmother = "townsfolk",
    high_priestess = "townsfolk", huntsman = "townsfolk", innkeeper = "townsfolk",
    juggler = "townsfolk", king = "townsfolk", knight = "townsfolk",
    lycanthrope = "townsfolk", magician = "townsfolk", mathematician = "townsfolk",
    minstrel = "townsfolk", nightwatchman = "townsfolk", noble = "townsfolk",
    oracle = "townsfolk", pacifist = "townsfolk", philosopher = "townsfolk",
    pixie = "townsfolk", poppy_grower = "townsfolk", preacher = "townsfolk",
    princess = "townsfolk", professor = "townsfolk", sage = "townsfolk",
    sailor = "townsfolk", savant = "townsfolk", seamstress = "townsfolk",
    shugenja = "townsfolk", snake_charmer = "townsfolk", steward = "townsfolk",
    tea_lady = "townsfolk", town_crier = "townsfolk", village_idiot = "townsfolk",
    -- Outsiders
    butler = "outsider", drunk = "outsider", recluse = "outsider",
    saint = "outsider", barber = "outsider", damsel = "outsider",
    golem = "outsider", goon = "outsider", hatter = "outsider",
    heretic = "outsider", hermit = "outsider", klutz = "outsider",
    lunatic = "outsider", moonchild = "outsider", mutant = "outsider",
    ogre = "outsider", plague_doctor = "outsider", politician = "outsider",
    puzzlemaster = "outsider", snitch = "outsider", sweetheart = "outsider",
    tinker = "outsider", zealot = "outsider",
    -- Minions
    poisoner = "minion", spy = "minion", baron = "minion",
    scarlet_woman = "minion", assassin = "minion", boffin = "minion",
    boomdandy = "minion", cerenovus = "minion", devils_advocate = "minion",
    evil_twin = "minion", fearmonger = "minion", goblin = "minion",
    godfather = "minion", harpy = "minion", marionette = "minion",
    mastermind = "minion", mezepheles = "minion", organ_grinder = "minion",
    pit_hag = "minion", psychopath = "minion", summoner = "minion",
    vizier = "minion", widow = "minion", witch = "minion",
    wizard = "minion", wraith = "minion", xaan = "minion",
    -- Demons
    imp = "demon", al_hadikhia = "demon", fang_gu = "demon",
    kazali = "demon", legion = "demon", leviathan = "demon",
    lil_monsta = "demon", lleech = "demon", lord_of_typhon = "demon",
    no_dashii = "demon", ojo = "demon", po = "demon",
    pukka = "demon", riot = "demon", shabaloth = "demon",
    vigormortis = "demon", vortox = "demon", yaggababble = "demon",
    zombuul = "demon",
}

function botc.resolve_team(role_entry)
    if type(role_entry) == "table" and role_entry.team then
        return role_entry.team
    end
    local id = type(role_entry) == "table" and role_entry.id or role_entry
    local name = type(role_entry) == "table" and (role_entry.name or role_entry.id) or role_entry
    return DEFAULT_TEAMS[name:lower():gsub("[ -]", "_")] or DEFAULT_TEAMS[id:lower():gsub("[ -]", "_")] or "townsfolk"
end

function botc.resolve_name(role_entry)
    if type(role_entry) == "table" and role_entry.name then
        return role_entry.name
    end
    local name = type(role_entry) == "table" and (role_entry.id or "Unknown") or role_entry
    return name:gsub("_", " "):gsub("(%a)([%w_']*)", function(first, rest) return first:upper() .. rest end)
end

local TEAM_COUNTS_TABLE = {
    [5]  = {townsfolk=3, outsider=0, minion=1, demon=1},
    [6]  = {townsfolk=3, outsider=1, minion=1, demon=1},
    [7]  = {townsfolk=5, outsider=0, minion=1, demon=1},
    [8]  = {townsfolk=5, outsider=1, minion=1, demon=1},
    [9]  = {townsfolk=5, outsider=2, minion=1, demon=1},
    [10] = {townsfolk=7, outsider=0, minion=2, demon=1},
    [11] = {townsfolk=7, outsider=1, minion=2, demon=1},
    [12] = {townsfolk=7, outsider=2, minion=2, demon=1},
    [13] = {townsfolk=9, outsider=0, minion=3, demon=1},
    [14] = {townsfolk=9, outsider=1, minion=3, demon=1},
    [15] = {townsfolk=9, outsider=2, minion=3, demon=1},
}

function botc.get_team_counts(player_count)
    if type(player_count) ~= "number" or player_count < 5 or player_count > 15 then
        return nil
    end
    return TEAM_COUNTS_TABLE[player_count]
end

function botc.load_script(filename)
    local f = io.open(modpath .. "/" .. filename, "r")
    if not f then return false, "File not found: " .. filename end
    local raw = f:read("*all")
    f:close()
    local ok, script = pcall(minetest.parse_json, raw)
    if not ok then return false, "Invalid JSON: " .. tostring(script) end
    if type(script) ~= "table" then return false, "JSON root must be an array" end

    local roles = {}
    for _, entry in ipairs(script) do
        if type(entry) == "table" and entry.id == "_meta" then
            -- skip metadata
        else
            table.insert(roles, entry)
        end
    end
    botc.ST.script = roles
    botc.save_state()
    return true, "Script loaded: " .. filename .. " (" .. #roles .. " roles)"
end

function botc.assign_role(playername, role_entry)
    local name = botc.resolve_name(role_entry)
    local team = botc.resolve_team(role_entry)
    botc.ST.roles[playername] = {
        role = name,
        team = team,
        alive = true,
        dead_vote_used = false,
        markers = {},
    }
    botc.save_state()
    return true, "Assigned " .. playername .. " as " .. name .. " (" .. team .. ")"
end

function botc.unassign_role(playername)
    botc.ST.roles[playername] = nil
    botc.save_state()
    return true, "Cleared role for " .. playername
end

function botc.passout(player_list)
    if not botc.ST.script then return false, "No script loaded. Use /botc_loadscript first." end

    -- Separate roles by team
    local teams = { townsfolk = {}, outsider = {}, minion = {}, demon = {}, unknown = {} }
    for _, entry in ipairs(botc.ST.script) do
        local team = botc.resolve_team(entry)
        if teams[team] then
            table.insert(teams[team], entry)
        else
            table.insert(teams.unknown, entry)
        end
    end

    local players
    if player_list and #player_list > 0 then
        players = player_list
    else
        players = botc.all_players()
    end

    local count = #players
    if count < 5 then return false, "Need at least 5 players (got " .. count .. ")" end

    local team_counts = botc.get_team_counts(count)
    local demon_count = team_counts.demon
    local minion_count = team_counts.minion
    local outsider_count = team_counts.outsider
    local townsfolk_count = team_counts.townsfolk
    if townsfolk_count < 1 then return false, "Not enough players for the required roles" end

    -- Verify script has enough roles
    if #teams.demon < demon_count then return false, "Script needs " .. demon_count .. " Demon(s), has " .. #teams.demon end
    if #teams.minion < minion_count then return false, "Script needs " .. minion_count .. " Minion(s), has " .. #teams.minion end
    if #teams.outsider < outsider_count then return false, "Script needs " .. outsider_count .. " Outsider(s), has " .. #teams.outsider end
    if #teams.townsfolk < townsfolk_count then return false, "Script needs " .. townsfolk_count .. " Townsfolk, has " .. #teams.townsfolk end

    -- Shuffle players
    local shuffled = {}
    for _, p in ipairs(players) do table.insert(shuffled, p) end
    for i = #shuffled, 2, -1 do
        local j = math.random(i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    -- Shuffle role pools
    local function shuffle_t(t)
        for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
        return t
    end

    local pool = {}
    for i = 1, demon_count do table.insert(pool, {role = teams.demon[i], team = "demon"}) end
    for i = 1, minion_count do table.insert(pool, {role = teams.minion[i], team = "minion"}) end
    for i = 1, outsider_count do table.insert(pool, {role = teams.outsider[i], team = "outsider"}) end
    for i = 1, townsfolk_count do table.insert(pool, {role = teams.townsfolk[i], team = "townsfolk"}) end
    shuffle_t(pool)

    -- Assign
    local assigned = {}
    for i, playername in ipairs(shuffled) do
        local pkg = pool[i]
        botc.ST.roles[playername] = {
            role = botc.resolve_name(pkg.role),
            team = pkg.team,
            alive = true,
            dead_vote_used = false,
            markers = {},
        }
        table.insert(assigned, playername .. " = " .. botc.ST.roles[playername].role)
    end

    botc.ST.current_day = 1
    botc.ST.nominations = {}
    botc.ST.phase = "night" -- games start at night (botc_guide 2.3)
    botc.ST.current_timeofday = 0.0
    botc.ST.vote_blocks = {}
    botc.save_state()

    return true, "Passed out " .. count .. " roles:\n" .. table.concat(assigned, "\n")
end
