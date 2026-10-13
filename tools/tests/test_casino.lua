-- Серверная часть казино: проверка конфига исходов, отказ мёртвым, dev-команда

local function setup()
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/casino")
end

local function outcome(chance, symbol, multiplier)
    return { chance = chance, symbol = symbol, multiplier = multiplier }
end

return {
    validate_outcomes_current_config_ev = function()
        setup()
        local ok, ev = OSC_Casino.ValidateOutcomes(OSC_CONFIG.CASINO_OUTCOMES)
        H.eq(ok, true, "current config is valid")
        H.truthy(math.abs(ev - 0.9) < 1e-9, "expected payout 0.9, got " .. tostring(ev))
    end,

    validate_outcomes_rejects_over_100 = function()
        setup()
        local ok, err = OSC_Casino.ValidateOutcomes({
            outcome(60, "circle", 1), outcome(50, "star", 2),
        })
        H.eq(ok, false, "sum over 100 rejected")
        H.truthy(string.find(err, "100", 1, true), "error mentions 100: " .. tostring(err))
    end,

    validate_outcomes_rejects_unknown_symbol = function()
        setup()
        local ok = OSC_Casino.ValidateOutcomes({ outcome(10, "cherry", 2) })
        H.eq(ok, false, "unknown symbol rejected")
    end,

    validate_outcomes_rejects_duplicate_symbol = function()
        setup()
        local ok = OSC_Casino.ValidateOutcomes({ outcome(10, "star", 2), outcome(5, "star", 5) })
        H.eq(ok, false, "duplicate symbol rejected")
    end,

    validate_outcomes_rejects_fractional_chance = function()
        setup()
        local ok = OSC_Casino.ValidateOutcomes({ outcome(0.5, "seven", 30) })
        H.eq(ok, false, "fractional chance rejected")
    end,

    init_logs_expected_payout = function()
        setup()
        OSC_Casino.Init()
        H.truthy(H.logged("expected payout 0.90"), "EV logged")
    end,

    init_logs_invalid_outcomes = function()
        setup()
        OSC_CONFIG.CASINO_OUTCOMES = { outcome(150, "seven", 2) }
        OSC_Casino.Init()
        H.truthy(H.logged("ERROR: Casino outcomes"), "config error logged")
    end,

    spin_refused_when_dead = function()
        setup()
        local hero = H.NewHero({ alive = false })
        H.AddPlayer(0, hero, { gold = 1000 })
        local machine = H.NewHero({ name = "npc_osc_casino_test_object" })
        machine.osc_casino_owner_player_id = 0
        hero.osc_casino_machine = machine
        H.entities[100] = machine

        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, stake = 100 })

        local result = H.lastEvent("osc_casino_result")
        H.truthy(result, "result sent")
        H.eq(result.data.error, "osc_casino_err_dead", "error key")
        H.eq(H.players[0].gold, 1000, "gold untouched")
    end,

    dev_command_forces_symbol = function()
        setup()
        require("osc/core/commands")
        OSC_CONFIG.DEVELOPMENT_MODE = true
        H.AddPlayer(0, H.NewHero({}))
        OSC_Commands.Init()
        local function chat(data) H.FireGameEvent("player_chat", data) end

        chat({ text = "-casino seven", playerid = 0 })
        H.eq(OSC_Casino.debug_forced_symbol, "seven", "forced symbol")

        chat({ text = "-casino off", playerid = 0 })
        H.eq(OSC_Casino.debug_forced_symbol, nil, "forcing disabled")
    end,
}
