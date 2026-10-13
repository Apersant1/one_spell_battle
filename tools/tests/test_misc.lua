-- Курьеры, отложенные удары погоды, перемещение игроков между командами

local function setupCouriers()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/couriers")
end

local function setupWeather()
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/systems/chaos_events/weather_common")
    OSC_ChaosRounds = { event = { id = "weather_storm" }, endTime = 30 }
end

-- Запускает единственный отложенный удар погоды
local function runWeatherDelay()
    for name in pairs(H.thinks) do
        if string.find(name, "osc_weather_delay", 1, true) then
            return H.RunThink(name)
        end
    end
    error("no weather delay scheduled")
end

return {
    home_positions_keep_first_two = function()
        setupCouriers()
        local positions = OSC_Couriers.GetHomePositions(Vector(0, 0, 0), Vector(1, 0, 0), Vector(0, 1, 0), 2)
        H.eq(#positions, 2, "count")
        H.eq(positions[1], Vector(250, 160, 0), "first")
        H.eq(positions[2], Vector(250, -160, 0), "second")
    end,

    home_positions_support_four = function()
        setupCouriers()
        local positions = OSC_Couriers.GetHomePositions(Vector(0, 0, 0), Vector(1, 0, 0), Vector(0, 1, 0), 4)
        H.eq(#positions, 4, "count")
        H.eq(positions[3], Vector(450, 160, 0), "third: next row")
        H.eq(positions[4], Vector(450, -160, 0), "fourth: next row")
    end,

    dead_courier_leaves_stash_alone = function()
        setupCouriers()
        OSC_CONFIG.COURIERS.COUNT_PER_TEAM = 1
        local hero = H.NewHero({})
        H.AddPlayer(0, hero)
        local item = H.NewItem("item_branches")
        hero.items[9] = item
        local fountain = H.NewHero({ name = "ent_dota_fountain" })
        local courier = H.NewHero({ name = "npc_dota_courier", alive = false })
        H.byClass.ent_dota_fountain = { fountain }
        H.byClass.npc_dota_courier = { courier }

        OSC_Couriers.EnsureTeamCouriers(hero)
        H.RunThink("osc_courier_ai")

        H.eq(hero.items[9], item, "item stays in stash while courier is dead")
        H.eq(courier.osc_delivery_item, nil, "no delivery started")
    end,

    after_skips_when_round_changed = function()
        setupWeather()
        local called = false
        OSC_Weather.After(1, function() called = true end)
        OSC_ChaosRounds.event = nil

        runWeatherDelay()

        H.eq(called, false, "strike skipped after the round ended")
    end,

    after_runs_when_round_same = function()
        setupWeather()
        local called = false
        OSC_Weather.After(1, function() called = true end)

        runWeatherDelay()

        H.eq(called, true, "strike runs while the round goes on")
    end,

    team_move_rejects_unknown_team = function()
        require("osc/systems/team_shuffle")
        H.state = DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
        H.AddPlayer(0, nil, { team = DOTA_TEAM_GOODGUYS })

        OSC_TeamShuffle:OnMove({ PlayerID = 0, player_id = 0, team = 6 })
        H.eq(H.assignments[0], nil, "custom team rejected")

        OSC_TeamShuffle:OnMove({ PlayerID = 0, player_id = 0, team = DOTA_TEAM_BADGUYS })
        H.eq(H.assignments[0], DOTA_TEAM_BADGUYS, "Dire accepted")
    end,
}
