-- Проверка самого стенда: модули грузятся, мок героя работает с текущим кодом
return {
    give_random_replaces_current_ability = function()
        require("osc/config/config")
        require("osc/core/logger")
        require("osc/core/notifications")
        require("osc/systems/abilities")
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = {
            { name = "test_a", hero = "npc_dota_hero_axe", label = "A" },
            { name = "test_b", hero = "npc_dota_hero_axe", label = "B" },
        }
        local hero = H.NewHero({ abilities = { "test_a" }, level = 3 })
        hero.osc_current_ability = "test_a"

        OSC_Abilities.GiveRandom(hero, false)

        H.eq(hero.osc_current_ability, "test_b", "current ability")
        H.eq(hero:GetAbilityByIndex(0).name, "test_b", "slot 0")
        H.eq(hero:FindAbilityByName("test_a"):IsHidden(), true, "old ability hidden")
        H.eq(hero:GetAbilityByIndex(0).level, 2, "level for hero level 3")
    end,
}
