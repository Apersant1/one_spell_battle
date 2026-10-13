-- Общая проверка команд клиента и её использование в казино и командах

local function setup()
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/core/heroes")
    require("osc/core/client_commands")
end

local function machineSpec()
    return {
        hero = true,
        args = { { name = "machine_entindex", check = OSC_ClientCommands.Integer({ min = 0 }) } },
    }
end

return {
    check_rejects_unknown_player = function()
        setup()
        local ok, cmd, reason = OSC_ClientCommands.Check(nil, { PlayerID = 3 }, {})
        H.eq(ok, false, "unknown player")
        H.eq(reason, "invalid_player", "reason")
        H.eq(cmd.player, nil, "no player in context")

        ok, _, reason = OSC_ClientCommands.Check(nil, {}, {})
        H.eq(reason, "invalid_player", "missing PlayerID and source")
    end,

    check_uses_source_entity_as_fallback = function()
        setup()
        H.AddPlayer(2, nil)
        H.entities[3] = { IsNull = function() return false end, GetPlayerID = function() return 2 end }

        local ok, cmd = OSC_ClientCommands.Check(3, {}, {})

        H.eq(ok, true, "accepted")
        H.eq(cmd.player_id, 2, "player from source entity")
    end,

    check_requires_hero_and_keeps_player = function()
        setup()
        H.AddPlayer(0, nil)

        local ok, cmd, reason = OSC_ClientCommands.Check(nil, { PlayerID = 0 }, machineSpec())

        H.eq(ok, false, "no hero")
        H.eq(reason, "no_hero", "reason")
        H.truthy(cmd.player, "player kept so the handler can answer")
    end,

    check_validates_args_in_order = function()
        setup()
        local hero = H.NewHero({})
        H.AddPlayer(0, hero)
        local function check(value)
            local ok, cmd, reason = OSC_ClientCommands.Check(nil,
                { PlayerID = 0, machine_entindex = value }, machineSpec())
            return ok, cmd, reason
        end

        local ok, cmd = check("12")
        H.eq(ok, true, "numeric string accepted")
        H.eq(cmd.args.machine_entindex, 12, "normalized to number")
        H.eq(cmd.hero, hero, "hero in context")

        for _, bad in ipairs({ -1, 1.5, "abc" }) do
            local badOk, _, reason = check(bad)
            H.eq(badOk, false, "rejected " .. tostring(bad))
            H.eq(reason, "invalid_machine_entindex", "reason for " .. tostring(bad))
        end
    end,

    integer_one_of_and_player_id = function()
        setup()
        H.AddPlayer(4, nil)
        local team = OSC_ClientCommands.Integer({ one_of = { 2, 3 } })
        H.eq(team("3"), true, "allowed value")
        H.eq(team(6), false, "value outside the list")

        local playerID = OSC_ClientCommands.PlayerID()
        H.eq(playerID(4), true, "existing player")
        H.eq(playerID(5), false, "unknown player")

        local name = OSC_ClientCommands.OneOf({ "a", "b" })
        H.eq(name("b"), true, "allowed string")
        H.eq(name("c"), false, "unknown string")
    end,

    casino_spin_answers_like_before = function()
        setup()
        require("osc/systems/casino")
        H.AddPlayer(0, nil)
        local hero = H.NewHero({ playerID = 1 })
        H.AddPlayer(1, hero)

        OSC_Casino.OnSpin(1, { PlayerID = 9, machine_entindex = 100, stake = 100 })
        H.eq(H.lastEvent("osc_casino_result"), nil, "unknown player gets no answer")

        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, stake = 100 })
        H.eq(H.lastEvent("osc_casino_result").data.error, "osc_casino_err_unavailable", "no hero")

        OSC_Casino.OnSpin(1, { PlayerID = 1, machine_entindex = -5, stake = 100 })
        H.eq(H.lastEvent("osc_casino_result").data.error, "osc_casino_err_bad_machine", "bad machine index")

        OSC_Casino.OnSpin(1, { PlayerID = 1, machine_entindex = 100, stake = 100 })
        H.eq(H.lastEvent("osc_casino_result").data.error, "osc_casino_err_bad_machine", "no machine there")
    end,

    casino_reopen_ignores_bad_requests = function()
        setup()
        require("osc/systems/casino")
        H.AddPlayer(0, nil)

        OSC_Casino.OnReopen(1, { PlayerID = 0, machine_entindex = 100 })
        OSC_Casino.OnReopen(1, { PlayerID = 7, machine_entindex = 100 })

        H.eq(#H.events, 0, "nothing sent without a hero or a player")
    end,

    team_move_requires_host_for_others = function()
        setup()
        require("osc/systems/team_shuffle")
        H.state = DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
        H.AddPlayer(0, nil, { team = DOTA_TEAM_GOODGUYS })
        H.AddPlayer(1, nil, { team = DOTA_TEAM_GOODGUYS, host = true })

        OSC_TeamShuffle:OnMove({ PlayerID = 0, player_id = 1, team = DOTA_TEAM_BADGUYS })
        H.eq(H.assignments[1], nil, "non-host cannot move others")

        OSC_TeamShuffle:OnMove({ PlayerID = 1, player_id = 9, team = DOTA_TEAM_BADGUYS })
        H.eq(H.assignments[9], nil, "unknown target rejected")

        OSC_TeamShuffle:OnMove({ PlayerID = 1, player_id = 0, team = DOTA_TEAM_BADGUYS })
        H.eq(H.assignments[0], DOTA_TEAM_BADGUYS, "host moves another player")
    end,

    team_shuffle_only_by_host = function()
        setup()
        require("osc/systems/team_shuffle")
        H.state = DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
        H.AddPlayer(0, nil, { team = DOTA_TEAM_GOODGUYS })
        H.AddPlayer(1, nil, { team = DOTA_TEAM_GOODGUYS, host = true })

        OSC_TeamShuffle:OnShuffle({ PlayerID = 0 })
        H.eq(next(H.assignments), nil, "non-host shuffle ignored")

        OSC_TeamShuffle:OnShuffle({ PlayerID = 1 })
        H.truthy(H.assignments[0] and H.assignments[1], "host shuffle assigns everyone")
    end,
}
