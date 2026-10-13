-- Обработка повышения уровня героя

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    require("osc/systems/couriers")
    require("osc/systems/hero_lifecycle")
    OSC_HeroLifecycle.Init()
    H.DefineAbility("test_a")
    H.DefineAbility("test_ult", { ultimate = true })
    OSC_ABILITY_POOL = { { name = "test_a", hero = "npc_dota_hero_axe", label = "A" } }
    OSC_ULTIMATE_POOL = { { name = "test_ult", hero = "npc_dota_hero_axe", label = "U" } }
end

local function levelUp(hero, level)
    hero.level = level
    H.entities[1] = hero
    H.gameEvents["dota_player_gained_level"].fn({ hero_entindex = 1, level = level })
end

return {
    level_up_skips_uninitialized_hero = function()
        setup()
        local hero = H.NewHero({ abilities = { "test_a" } })
        H.AddPlayer(0, hero)

        levelUp(hero, 6)

        H.eq(hero.osc_current_ultimate, nil, "no ultimate before initialization")
    end,

    level_up_raises_copy_levels = function()
        setup()
        local hero = H.NewHero({ abilities = { "test_a" } })
        hero.osc_current_ability = "test_a"
        hero.osc_initialized = true
        H.AddPlayer(0, hero)
        local clone = H.NewHero({ abilities = { "test_a" }, copy = "clone" })

        levelUp(hero, 5)

        H.eq(hero:FindAbilityByName("test_a"):GetLevel(), 3, "owner ability level")
        H.eq(clone:FindAbilityByName("test_a"):GetLevel(), 3, "clone ability level")
    end,
}
