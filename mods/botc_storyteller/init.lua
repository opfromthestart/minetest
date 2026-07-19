local modname = minetest.get_current_modname()
local modpath = minetest.get_modpath(modname)

minetest.register_privilege("storyteller", {
    description = "Can use BotC storyteller tools",
    give_to_singleplayer = true,
})

dofile(modpath .. "/state.lua")
dofile(modpath .. "/passout.lua")
dofile(modpath .. "/commands.lua")
dofile(modpath .. "/fakeplayer.lua")
dofile(modpath .. "/wands.lua")
dofile(modpath .. "/hud.lua")
dofile(modpath .. "/voting.lua")
dofile(modpath .. "/ghost.lua")
dofile(modpath .. "/gametest.lua")

minetest.register_on_mods_loaded(function()
    botc.load_state()
    botc.ST.current_timeofday = botc.ST.current_timeofday or 0.0
    if botc.ST.clock_pos then
        botc.manage_clock_hand()
    end
end)

minetest.register_globalstep(function(dtime)
    if botc.ST.current_timeofday then
        minetest.set_timeofday(botc.ST.current_timeofday)
    end
end)

minetest.register_on_shutdown(function()
    botc.save_state()
end)
