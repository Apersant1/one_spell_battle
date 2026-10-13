-- Единое определение героя (OSC_Heroes) и единая точка событий (OSC_GameEvents)

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/core/heroes")
    require("osc/core/game_events")
end

-- Основной герой игрока 0 и его копии всех видов
local function family()
    local main = H.NewHero({ playerID = 0 })
    H.AddPlayer(0, main)
    return {
        main = main,
        illusion = H.NewHero({ playerID = 0, copy = "illusion" }),
        clone = H.NewHero({ playerID = 0, copy = "clone" }),
        tempest = H.NewHero({ playerID = 0, copy = "tempest" }),
    }
end

local function spawn(index, unit)
    H.entities[index] = unit
    H.FireGameEvent("npc_spawned", { entindex = index })
end

return {
    predicates_split_main_copies_and_combat = function()
        setup()
        local f = family()

        H.eq(OSC_Heroes.IsMainHero(f.main), true, "main hero")
        H.eq(OSC_Heroes.IsCopy(f.main), false, "main is not a copy")
        H.eq(OSC_Heroes.IsCombatHero(f.main), true, "main fights")

        for _, kind in ipairs({ "illusion", "clone", "tempest" }) do
            H.eq(OSC_Heroes.IsMainHero(f[kind]), false, kind .. " is not main")
            H.eq(OSC_Heroes.IsCopy(f[kind]), true, kind .. " is a copy")
        end
        H.eq(OSC_Heroes.IsCombatHero(f.clone), true, "Meepo clone has its own body")
        H.eq(OSC_Heroes.IsCombatHero(f.tempest), true, "Tempest Double has its own body")
        H.eq(OSC_Heroes.IsCombatHero(f.illusion), false, "illusion is not a combat hero")

        f.main._null = true
        H.eq(OSC_Heroes.IsMainHero(f.main), false, "removed entity rejected")
        H.eq(OSC_Heroes.IsCombatHero(nil), false, "nil rejected")
    end,

    copies_belong_to_owner_of_same_hero = function()
        setup()
        local f = family()
        local replica = H.NewHero({ name = "npc_dota_hero_lina", playerID = 0, copy = "illusion" })
        local foreign = H.NewHero({ playerID = 5, copy = "clone" })

        local found = {}
        OSC_Heroes.ForEachCopy(f.main, function(copy) found[copy] = true end)

        H.truthy(found[f.illusion] and found[f.clone] and found[f.tempest], "own copies found")
        H.eq(found[replica], nil, "Wall of Replica illusion is not a copy of this hero")
        H.eq(found[foreign], nil, "copy of another player skipped")
        H.eq(OSC_Heroes.GetCopyOwner(f.clone), f.main, "copy owner")
        H.eq(OSC_Heroes.GetCopyOwner(f.main), nil, "main hero has no owner")
    end,

    hero_spawned_fires_on_both_engine_events = function()
        setup()
        OSC_GameEvents.Init()
        local seen = {}
        OSC_GameEvents.Subscribe("hero_spawned", "test", function(_, source)
            table.insert(seen, source)
        end)
        local hero = H.NewHero({})
        local creep = H.NewHero({})
        creep.IsHero = function() return false end

        spawn(1, creep)
        H.eq(#seen, 0, "non-hero units ignored")

        spawn(2, hero)
        H.FireGameEvent("dota_on_hero_finish_spawn", { heroindex = 2 })
        H.eq(#seen, 2, "finish_spawn is a second chance, not swallowed")
        H.eq(seen[2], "dota_on_hero_finish_spawn", "source passed")

        spawn(2, hero)
        H.eq(#seen, 3, "respawn dispatched again")
    end,

    init_gets_second_chance_when_owner_set_late = function()
        setup()
        require("osc/systems/abilities")
        require("osc/systems/hero_lifecycle")
        OSC_GameEvents.Init()
        OSC_HeroLifecycle.Init()
        H.DefineAbility("test_a")
        OSC_ABILITY_POOL = { { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } } }
        local hero = H.NewHero({ playerID = 0 })

        -- На npc_spawned игроку ещё не назначен выбранный герой
        spawn(1, hero)
        H.eq(H.thinks.osc_init, nil, "not recognized as a main hero yet")

        H.AddPlayer(0, hero)
        H.FireGameEvent("dota_on_hero_finish_spawn", { heroindex = 1 })
        H.RunThink("osc_init")
        H.eq(OSC_HeroState.Get(hero).initialized, true, "initialized on the second event")

        spawn(1, hero)
        H.FireGameEvent("dota_on_hero_finish_spawn", { heroindex = 1 })
        H.eq(H.thinks.osc_init, nil, "repeated events do not initialize again")
    end,

    subscribers_are_idempotent = function()
        setup()
        require("osc/systems/abilities")
        require("osc/systems/hero_lifecycle")
        require("osc/systems/couriers")
        OSC_GameEvents.Init()
        OSC_HeroLifecycle.Init()
        OSC_Couriers.Init()
        H.DefineAbility("test_a")
        OSC_ABILITY_POOL = { { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } } }
        OSC_CONFIG.COURIERS.COUNT_PER_TEAM = 1
        H.byClass.ent_dota_fountain = { H.NewHero({ name = "ent_dota_fountain", playerID = 9 }) }
        local courier = H.NewHero({ name = "npc_dota_courier", playerID = 9 })
        H.byClass.npc_dota_courier = { courier }
        local f = family()

        for _ = 1, 2 do
            spawn(1, f.main)
            H.FireGameEvent("dota_on_hero_finish_spawn", { heroindex = 1 })
        end
        H.RunThink("osc_init")
        H.eq(OSC_HeroState.Get(f.main).init_attempts, 1, "initialized once")

        for _ = 1, 2 do
            spawn(2, f.clone)
            H.FireGameEvent("dota_on_hero_finish_spawn", { heroindex = 2 })
        end
        H.RunThink("osc_copy")
        local count = 0
        for index = 0, f.clone:GetAbilityCount() - 1 do
            local ability = f.clone:GetAbilityByIndex(index)
            if ability and ability.name == "test_a" then count = count + 1 end
        end
        H.eq(count, 1, "clone copied once")
        H.eq(courier.osc_courier_ai_initialized, true, "couriers started once")
    end,

    monkey_king_soldiers_are_ignored = function()
        setup()
        local king = H.NewHero({ name = "npc_dota_hero_monkey_king", playerID = 0 })
        H.AddPlayer(0, king)
        local soldier = H.NewHero({ name = "npc_dota_hero_monkey_king", playerID = 0 })
        soldier:AddNewModifier(soldier, nil, "modifier_monkey_king_fur_army_soldier", {})
        local plain = H.NewHero({ name = "npc_dota_hero_monkey_king", playerID = 0 })

        H.eq(OSC_Heroes.IsMainHero(king), true, "Monkey King himself")
        for _, unit in ipairs({ soldier, plain }) do
            H.eq(OSC_Heroes.IsMainHero(unit), false, "soldier is not the selected hero")
            H.eq(OSC_Heroes.IsCombatHero(unit), false, "soldier gets no chaos or weather")
            H.eq(OSC_Heroes.IsCopy(unit), false, "soldier is not a copy")
        end
        soldier.copy = "clone"
        H.eq(OSC_Heroes.IsCombatHero(soldier), false, "soldier modifier wins over clone flags")
    end,

    replica_illusion_has_no_owner = function()
        setup()
        local f = family()
        local replica = H.NewHero({ name = "npc_dota_hero_lina", playerID = 0, copy = "illusion" })

        H.eq(OSC_Heroes.GetCopyOwner(replica), nil, "illusion of another hero keeps its abilities")
        H.eq(OSC_Heroes.GetCopyOwner(f.illusion), f.main, "own illusion has an owner")
    end,

    game_started_fires_once = function()
        setup()
        OSC_GameEvents.Init()
        local count = 0
        OSC_GameEvents.Subscribe("game_started", "test", function() count = count + 1 end)

        H.state = DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
        H.FireGameEvent("game_rules_state_change", {})
        H.eq(count, 0, "not started during setup")

        H.state = DOTA_GAMERULES_STATE_GAME_IN_PROGRESS
        H.FireGameEvent("game_rules_state_change", {})
        H.FireGameEvent("game_rules_state_change", {})
        H.eq(count, 1, "started once")
        H.eq(OSC_GameEvents.IsGameStarted(), true, "state flag")
    end,

    subscribe_replaces_and_isolates_errors = function()
        setup()
        local calls = {}
        OSC_GameEvents.Subscribe("game_started", "a", function() table.insert(calls, "a1") end)
        OSC_GameEvents.Subscribe("game_started", "broken", function() error("boom") end)
        OSC_GameEvents.Subscribe("game_started", "b", function() table.insert(calls, "b") end)
        OSC_GameEvents.Subscribe("game_started", "a", function() table.insert(calls, "a2") end)

        OSC_GameEvents.Emit("game_started")

        H.eq(table.concat(calls, ","), "a2,b", "same id replaced, order kept, error isolated")
        H.truthy(H.logged("'broken' failed"), "handler error logged")
    end,

    engine_listeners_registered_once = function()
        setup()
        OSC_GameEvents.Init()
        OSC_GameEvents.Init()
        H.eq(#H.gameEvents.npc_spawned, 1, "single npc_spawned listener")
        H.eq(#H.gameEvents.game_rules_state_change, 1, "single state listener")
    end,

    chaos_effects_reach_clones_but_not_illusions = function()
        setup()
        require("osc/systems/chaos_events/registry")
        require("osc/systems/chaos_rounds")
        OSC_GameEvents.Init()
        OSC_ChaosRounds:Init()
        OSC_ChaosEvents:Register({ id = "test_buff", modifier = "modifier_test_buff" })
        local f = family()

        OSC_ChaosRounds:StartEvent(OSC_ChaosEvents:Get("test_buff"))

        H.truthy(f.main:HasModifier("modifier_test_buff"), "main hero buffed")
        H.truthy(f.clone:HasModifier("modifier_test_buff"), "Meepo clone buffed")
        H.truthy(f.tempest:HasModifier("modifier_test_buff"), "Tempest Double buffed")
        H.eq(f.illusion:HasModifier("modifier_test_buff"), false, "illusion skipped")

        -- Возрождение клона во время раунда
        f.clone:RemoveModifierByName("modifier_test_buff")
        spawn(4, f.clone)
        H.RunThink("osc_chaos_apply_on_spawn")
        H.truthy(f.clone:HasModifier("modifier_test_buff"), "respawned clone buffed again")

        OSC_ChaosRounds:EndEvent(true)
        H.eq(f.clone:HasModifier("modifier_test_buff"), false, "clone cleaned up at the end")
    end,

    weather_hits_same_heroes_as_chaos_effects = function()
        setup()
        require("osc/systems/chaos_events/weather_common")
        local f = family()

        local hit = {}
        for _, hero in ipairs(OSC_Weather.HeroesInRadius(Vector(0, 0, 0), 100)) do
            hit[hero] = true
        end

        H.truthy(hit[f.main] and hit[f.clone] and hit[f.tempest], "combat heroes hit")
        H.eq(hit[f.illusion], nil, "illusion not hit")
    end,

    rotation_starts_on_game_started = function()
        setup()
        require("osc/systems/abilities")
        require("osc/systems/rotation")
        OSC_GameEvents.Init()
        OSC_Rotation.Init()

        H.state = DOTA_GAMERULES_STATE_GAME_IN_PROGRESS
        H.FireGameEvent("game_rules_state_change", {})

        H.truthy(H.thinks.osc_rotation, "rotation timer started")
        H.eq(OSC_Rotation.timer_started, true, "timer flag")
    end,

    lifecycle_initializes_from_hub = function()
        setup()
        require("osc/systems/abilities")
        require("osc/systems/hero_lifecycle")
        OSC_GameEvents.Init()
        OSC_HeroLifecycle.Init()
        H.DefineAbility("test_a")
        OSC_ABILITY_POOL = { { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } } }
        local initialized = {}
        OSC_GameEvents.Subscribe("hero_initialized", "test", function(hero)
            table.insert(initialized, hero)
        end)
        local f = family()

        spawn(1, f.main)
        H.RunThink("osc_init")
        H.eq(OSC_HeroState.Get(f.main).initialized, true, "main hero initialized")
        H.eq(initialized[1], f.main, "hero_initialized emitted")

        spawn(2, f.clone)
        H.RunThink("osc_copy")
        H.truthy(f.clone:FindAbilityByName("test_a"), "clone copied ability of the owner")
        H.eq(OSC_HeroState.Get(f.clone).initialized, false, "clone is not initialized as a main hero")
    end,

    ultimate_reroll_only_for_main_hero = function()
        setup()
        require("osc/systems/abilities")
        require("osc/items/item_ultimate_reroll")
        local f = family()
        f.clone.level = 10
        local item = item_osc_ultimate_reroll()
        item.GetCaster = function() return f.clone end

        item:OnSpellStart()

        H.truthy(H.logged("requires a main hero"), "copy cannot reroll")
        H.eq(OSC_HeroState.Get(f.clone).ultimate, nil, "clone ultimate untouched")
    end,
}
