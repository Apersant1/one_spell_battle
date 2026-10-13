-- 1.2: перезарядка способности, пришедшей на смену прежней

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    H.DefineAbility("test_a")
    -- Перезарядка по уровням 20/16/12/8; герою 5-го уровня достаётся 3-й уровень
    H.DefineAbility("test_b", { cooldown = { 20, 16, 12, 8 } })
    OSC_ABILITY_POOL = {
        { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } },
        { name = "test_b", hero = "npc_dota_hero_axe", label = "B", tags = { "disable" } },
    }
    local hero = H.NewHero({ abilities = { "test_a" }, level = 5 })
    H.AddPlayer(0, hero)
    OSC_HeroState.Get(hero).ability = "test_a"
    return hero
end

local function newAbility(hero)
    return hero:FindAbilityByName("test_b")
end

return {
    ready_by_default = function()
        local hero = setup()
        H.eq(OSC_CONFIG.NEW_ABILITY_COOLDOWN_MODE, "ready", "default mode")

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)

        H.eq(newAbility(hero):GetCooldownTimeRemaining(), 0, "new ability ready")
    end,

    partial_takes_fraction_of_current_level = function()
        local hero = setup()
        OSC_CONFIG.NEW_ABILITY_COOLDOWN_MODE = "partial"
        OSC_CONFIG.NEW_ABILITY_COOLDOWN_FRACTION = 0.5

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)

        H.eq(newAbility(hero):GetLevel(), 3, "level for hero level 5")
        H.eq(newAbility(hero):GetCooldownTimeRemaining(), 6, "half of 12 s at level 3")
    end,

    partial_skips_first_ability = function()
        local hero = setup()
        OSC_HeroState.Get(hero).ability = nil
        OSC_CONFIG.NEW_ABILITY_COOLDOWN_MODE = "partial"

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)

        H.eq(newAbility(hero):GetCooldownTimeRemaining(), 0, "first ability of the hero is ready")
    end,

    invalid_fraction_logged_and_ready = function()
        local hero = setup()
        OSC_CONFIG.NEW_ABILITY_COOLDOWN_MODE = "partial"
        OSC_CONFIG.NEW_ABILITY_COOLDOWN_FRACTION = 2

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)

        H.eq(newAbility(hero):GetCooldownTimeRemaining(), 0, "falls back to ready")
        H.truthy(H.logged("NEW_ABILITY_COOLDOWN_FRACTION"), "config error logged")
    end,

    copies_inherit_cooldown_of_owner = function()
        local hero = setup()
        OSC_CONFIG.NEW_ABILITY_COOLDOWN_MODE = "partial"
        OSC_CONFIG.NEW_ABILITY_COOLDOWN_FRACTION = 0.5
        local clone = H.NewHero({ abilities = { "test_a" }, copy = "clone" })
        OSC_HeroState.Get(clone).ability = "test_a"

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)

        H.eq(clone:FindAbilityByName("test_b"):GetCooldownTimeRemaining(), 6,
            "Meepo clone does not get a free cast")
    end,

    copies_get_ready_ability_in_ready_mode = function()
        local hero = setup()
        hero:FindAbilityByName("test_a").cooldown = 0
        local clone = H.NewHero({ abilities = { "test_a" }, copy = "clone" })
        OSC_HeroState.Get(clone).ability = "test_a"
        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        hero:FindAbilityByName("test_b"):StartCooldown(9) -- владелец уже скастовал

        local illusion = H.NewHero({ copy = "illusion" })
        OSC_Abilities.CopyFromOwner(illusion, hero)

        H.eq(clone:FindAbilityByName("test_b"):GetCooldownTimeRemaining(), 0, "clone ready as before")
        H.eq(illusion:FindAbilityByName("test_b"):GetCooldownTimeRemaining(), 0,
            "new copy does not inherit the owner cooldown in ready mode")
    end,
}
