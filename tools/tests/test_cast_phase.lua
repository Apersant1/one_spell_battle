-- 1.1: замена откладывается, пока старая способность в фазе каста

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    H.DefineAbility("test_a")
    H.DefineAbility("test_b")
    H.DefineAbility("test_c")
    OSC_ABILITY_POOL = {
        { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } },
        { name = "test_b", hero = "npc_dota_hero_axe", label = "B", tags = { "disable" } },
        { name = "test_c", hero = "npc_dota_hero_axe", label = "C", tags = { "support" } },
    }
    local hero = H.NewHero({ abilities = { "test_a" }, level = 3 })
    H.AddPlayer(0, hero)
    OSC_HeroState.Get(hero).ability = "test_a"

    local notified = {}
    OSC_Notifications.AbilityChanged = function(_, entry) table.insert(notified, entry.name) end
    return hero, notified
end

local function casting(hero)
    local ability = hero:FindAbilityByName("test_a")
    ability.in_phase = true
    return ability
end

return {
    replaces_at_once_without_cast_phase = function()
        local hero = setup()

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], true)

        H.eq(OSC_HeroState.Get(hero).ability, "test_b", "replaced right away")
        H.eq(H.thinks.osc_deferred_ability, nil, "no timer")
    end,

    waits_for_cast_phase_then_replaces_and_syncs_copies = function()
        local hero, notified = setup()
        local old = casting(hero)
        local clone = H.NewHero({ abilities = { "test_a" }, copy = "clone" })
        OSC_HeroState.Get(clone).ability = "test_a"

        local result = OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], true)

        H.eq(result.name, "test_b", "chosen entry returned")
        H.eq(OSC_HeroState.Get(hero).ability, "test_a", "old ability kept during the cast")
        H.eq(old:IsHidden(), false, "old ability not hidden")
        H.eq(#notified, 0, "no notification yet")
        H.eq(H.thinks.osc_deferred_ability.delay, OSC_CONFIG.ROTATION_DEFER_STEP, "step from config")

        H.time = 0.25
        H.eq(H.RunThink("osc_deferred_ability"), OSC_CONFIG.ROTATION_DEFER_STEP, "still casting: wait")
        H.eq(OSC_HeroState.Get(hero).ability, "test_a", "still old")

        old.in_phase = false
        H.time = 0.5
        H.eq(H.RunThink("osc_deferred_ability"), nil, "timer finishes itself")
        H.eq(OSC_HeroState.Get(hero).ability, "test_b", "replaced after the cast")
        H.eq(hero:GetAbilityByIndex(0).name, "test_b", "in the old slot")
        H.eq(notified[1], "test_b", "notified after the real change")
        H.truthy(clone:FindAbilityByName("test_b"), "copy synced after the real change")
        H.eq(OSC_HeroState.Get(hero).deferred.ability, nil, "pending change cleared")
    end,

    forced_after_max_defer = function()
        local hero = setup()
        casting(hero)

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        H.time = OSC_CONFIG.ROTATION_MAX_DEFER - 0.1
        H.RunThink("osc_deferred_ability")
        H.eq(OSC_HeroState.Get(hero).ability, "test_a", "waiting before the limit")

        H.time = OSC_CONFIG.ROTATION_MAX_DEFER
        H.eq(H.RunThink("osc_deferred_ability"), nil, "no more waiting")
        H.eq(OSC_HeroState.Get(hero).ability, "test_b", "forced change at the limit")
    end,

    new_request_replaces_pending_keeps_deadline = function()
        local hero = setup()
        casting(hero)

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        H.time = 2
        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[3], false)

        local pending = OSC_HeroState.Get(hero).deferred.ability
        H.eq(pending.entry.name, "test_c", "latest request wins")
        H.eq(pending.deadline, OSC_CONFIG.ROTATION_MAX_DEFER, "deadline from the first request")

        H.time = OSC_CONFIG.ROTATION_MAX_DEFER
        H.RunThink("osc_deferred_ability")
        H.eq(OSC_HeroState.Get(hero).ability, "test_c", "latest entry given")
    end,

    disabled_by_flag = function()
        local hero = setup()
        casting(hero)
        OSC_CONFIG.ROTATION_CAST_PHASE_DEFER = false

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)

        H.eq(OSC_HeroState.Get(hero).ability, "test_b", "old behaviour: replaced at once")
    end,

    timer_stops_when_hero_removed = function()
        local hero = setup()
        casting(hero)

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        hero._null = true

        H.eq(H.RunThink("osc_deferred_ability"), nil, "timer ends with the hero")
    end,

    clone_in_cast_phase_waits_for_its_own_cast = function()
        local hero = setup()
        local clone = H.NewHero({ abilities = { "test_a" }, copy = "clone" })
        OSC_HeroState.Get(clone).ability = "test_a"
        local cloneOld = clone:FindAbilityByName("test_a")
        cloneOld.in_phase = true

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)

        H.eq(OSC_HeroState.Get(hero).ability, "test_b", "owner changed at once")
        H.eq(clone:FindAbilityByName("test_a"), cloneOld, "clone keeps the ability it is casting")
        H.eq(cloneOld:IsHidden(), false, "and it is not hidden")
        H.eq(clone:FindAbilityByName("test_b"), nil, "clone change waits")

        cloneOld.in_phase = false
        H.RunThink("osc_deferred_ability")
        H.truthy(clone:FindAbilityByName("test_b"), "clone changed after its cast")
        H.eq(cloneOld:IsHidden(), true, "old clone ability retired, not removed")
        H.truthy(clone:FindAbilityByName("test_a"), "old clone ability lives for its projectiles")
    end,

    clone_change_forced_after_max_defer = function()
        local hero = setup()
        local clone = H.NewHero({ abilities = { "test_a" }, copy = "clone" })
        OSC_HeroState.Get(clone).ability = "test_a"
        clone:FindAbilityByName("test_a").in_phase = true

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        H.time = OSC_CONFIG.ROTATION_MAX_DEFER
        H.RunThink("osc_deferred_ability")

        H.truthy(clone:FindAbilityByName("test_b"), "forced at the limit")
        H.eq(OSC_HeroState.Get(clone).deferred.ability, nil, "pending cleared")
    end,

    lost_timer_does_not_freeze_the_slot = function()
        local hero = setup()
        casting(hero)
        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        H.thinks.osc_deferred_ability = nil -- таймер пропал

        H.time = OSC_CONFIG.ROTATION_MAX_DEFER
        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[3], false)

        H.eq(OSC_HeroState.Get(hero).ability, "test_c", "applied at once after the deadline")
        H.eq(OSC_HeroState.Get(hero).deferred.ability, nil, "nothing pending")
    end,
}
