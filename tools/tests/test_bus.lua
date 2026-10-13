-- Шина событий режима: ability_changed, chaos_started/ended, casino_spin_resolved

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/core/game_events")
end

-- Все полезные нагрузки события по порядку
local function record(eventName)
    local seen = {}
    OSC_GameEvents.Subscribe(eventName, "test_" .. eventName, function(payload)
        table.insert(seen, payload)
    end)
    return seen
end

return {
    ability_changed_after_real_change = function()
        setup()
        require("osc/systems/abilities")
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = {
            { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } },
            { name = "test_b", hero = "npc_dota_hero_axe", label = "B", tags = { "support" } },
        }
        local hero = H.NewHero({ playerID = 3, level = 3 })
        H.AddPlayer(3, hero)
        local seen = record("ability_changed")

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[1], false)
        H.eq(#seen, 1, "first grant published")
        H.eq(seen[1].player_id, 3, "player")
        H.eq(seen[1].slot, "ability", "slot")
        H.eq(seen[1].ability, "test_a", "ability")
        H.eq(seen[1].previous, nil, "no previous on the first grant")
        H.eq(seen[1].hero, hero, "hero")

        hero:FindAbilityByName("test_a").in_phase = true
        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        H.eq(#seen, 1, "deferred change not published yet")

        hero:FindAbilityByName("test_a").in_phase = false
        H.RunThink("osc_deferred_ability")
        H.eq(#seen, 2, "published after the real change")
        H.eq(seen[2].previous, "test_a", "previous ability")
        H.eq(seen[2].ability, "test_b", "new ability")
    end,

    chaos_round_start_and_end = function()
        setup()
        require("osc/systems/chaos_events/registry")
        require("osc/systems/chaos_rounds")
        OSC_ChaosRounds:Init()
        OSC_ChaosEvents:Register({ id = "test_event", duration = 20 })
        local started, ended = record("chaos_started"), record("chaos_ended")
        H.time = 5

        OSC_ChaosRounds:StartEvent(OSC_ChaosEvents:Get("test_event"))
        H.eq(started[1].event_id, "test_event", "start published")
        H.eq(started[1].start_time, 5, "start time")
        H.eq(started[1].end_time, 25, "end time")

        H.time = 25
        OSC_ChaosRounds:Think()
        H.eq(ended[1].event_id, "test_event", "end published")
        H.eq(ended[1].stopped, false, "ended on time")

        OSC_ChaosRounds:StartEvent(OSC_ChaosEvents:Get("test_event"))
        OSC_ChaosRounds:EndEvent(true)
        H.eq(ended[2].stopped, true, "stopped early")
    end,

    casino_spin_resolved_with_net = function()
        setup()
        require("osc/systems/casino")
        OSC_CONFIG.CASINO_ACCESS = "all"
        local hero = H.NewHero({ playerID = 0 })
        H.AddPlayer(0, hero, { gold = 1000 })
        local machine = H.NewHero({ name = "npc_osc_casino_test_object", playerID = 5 })
        machine.index = 100
        machine.osc_casino_owner_player_id = 5
        H.entities[100] = machine
        OSC_Casino.DebugForceSymbol("diamond")
        local seen = record("casino_spin_resolved")

        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, stake = 100 })
        H.eq(#seen, 0, "not published before settlement")
        H.RunThink("osc_casino_settle_100")

        H.eq(#seen, 1, "published once")
        H.eq(seen[1].player_id, 0, "player")
        H.eq(seen[1].stake, 100, "stake")
        H.eq(seen[1].payout, 200, "payout")
        H.eq(seen[1].net, 100, "net")
        H.eq(seen[1].multiplier, 2, "multiplier")
        H.eq(seen[1].item_stake, false, "gold stake")
        H.eq(H.players[0].gold, 1100, "gold paid out")
    end,

    refunded_spin_not_published = function()
        setup()
        require("osc/systems/casino")
        OSC_CONFIG.CASINO_ACCESS = "all"
        local hero = H.NewHero({ playerID = 0 })
        H.AddPlayer(0, hero, { gold = 1000 })
        local machine = H.NewHero({ name = "npc_osc_casino_test_object", playerID = 5 })
        machine.index = 100
        machine.osc_casino_owner_player_id = 5
        H.entities[100] = machine
        local seen = record("casino_spin_resolved")

        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, stake = 100 })
        H.players[0].hero = nil -- герой пропал до расчёта: ставка возвращается
        H.RunThink("osc_casino_settle_100")

        H.eq(#seen, 0, "refund is not a resolved spin")
        H.eq(H.players[0].gold, 1000, "stake refunded")
    end,
}
