-- Замена способностей, связанные подспособности, копии героя, проверка пулов

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
end

local function entry(name, extra)
    local result = { name = name, hero = "npc_dota_hero_axe", label = name }
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

-- Герой игрока 0 с текущей способностью name в слоте 0
local function heroWith(name, opts)
    opts = opts or {}
    local hero = H.NewHero({ abilities = { name }, level = opts.level or 3, copy = opts.copy })
    hero.osc_current_ability = name
    return hero
end

local function slotOf(hero, name)
    local ability = hero:FindAbilityByName(name)
    return ability and hero:IndexOf(ability)
end

return {
    validate_removes_unknown = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_ult", { ultimate = true })
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_missing") }
        OSC_ULTIMATE_POOL = { entry("test_ult") }

        local removed = OSC_Abilities.ValidatePools()

        H.eq(removed, 1, "removed count")
        H.eq(#OSC_ABILITY_POOL, 1, "pool size")
        H.eq(OSC_ABILITY_POOL[1].name, "test_a", "kept entry")
        H.eq(#OSC_ULTIMATE_POOL, 1, "ultimate pool untouched")
        H.truthy(H.logged("test_missing"), "missing ability is logged")
    end,

    validate_removes_bad_weight = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b", { weight = 0 }) }
        OSC_ULTIMATE_POOL = {}

        OSC_Abilities.ValidatePools()

        H.eq(#OSC_ABILITY_POOL, 1, "pool size")
        H.eq(OSC_ABILITY_POOL[1].name, "test_a", "kept entry")
    end,

    validate_drops_missing_linked = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_sub_ok")
        OSC_ABILITY_POOL = {
            entry("test_a", { linked = { { name = "test_sub_ok" }, { name = "test_sub_missing" } } }),
        }
        OSC_ULTIMATE_POOL = {}

        local removed = OSC_Abilities.ValidatePools()

        H.eq(removed, 1, "removed count")
        H.eq(#OSC_ABILITY_POOL[1].linked, 1, "linked size")
        H.eq(OSC_ABILITY_POOL[1].linked[1].name, "test_sub_ok", "kept linked")
        H.truthy(H.logged("test_sub_missing"), "missing linked is logged")
    end,

    give_random_keeps_old_when_add_fails = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b") }
        local hero = heroWith("test_a")
        H.failAdd.test_b = true

        local result = OSC_Abilities.GiveRandom(hero, false)

        H.eq(result, nil, "no entry returned")
        H.truthy(hero:FindAbilityByName("test_a"), "old ability kept")
        H.eq(hero.osc_current_ability, "test_a", "current ability unchanged")
    end,

    give_random_adds_linked = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        H.DefineAbility("test_b_sub", { maxLevel = 1 })
        OSC_ABILITY_POOL = {
            entry("test_a"),
            entry("test_b", { linked = { { name = "test_b_sub", hidden = true } } }),
        }
        local hero = heroWith("test_a", { level = 5 })

        OSC_Abilities.GiveRandom(hero, false)

        H.eq(slotOf(hero, "test_b"), 0, "main ability slot")
        local sub = hero:FindAbilityByName("test_b_sub")
        H.truthy(sub, "linked ability added")
        H.eq(sub:IsHidden(), true, "linked ability hidden")
        H.eq(sub:GetLevel(), 1, "linked level capped by its max level")
    end,

    give_random_removes_old_linked = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        H.DefineAbility("test_b_sub")
        OSC_ABILITY_POOL = {
            entry("test_a"),
            entry("test_b", { linked = { { name = "test_b_sub" } } }),
        }
        local hero = heroWith("test_b")
        hero:AddAbility("test_b_sub")

        OSC_Abilities.GiveRandom(hero, false)

        H.eq(hero.osc_current_ability, "test_a", "new ability")
        H.eq(hero:FindAbilityByName("test_b"):IsHidden(), true, "old ability hidden")
        H.eq(hero:FindAbilityByName("test_b_sub"):IsHidden(), true, "old linked ability hidden")

        H.RunThinksMatching("osc_retire_ability")

        H.eq(hero:FindAbilityByName("test_b"), nil, "old ability removed after delay")
        H.eq(hero:FindAbilityByName("test_b_sub"), nil, "old linked ability removed after delay")
    end,

    toggle_turned_off_before_removal = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b") }
        local hero = heroWith("test_a")
        local old = hero:FindAbilityByName("test_a")
        old.toggled = true

        OSC_Abilities.GiveRandom(hero, false)

        H.eq(old.toggled, false, "toggle switched off right away")
    end,

    sync_copies_updates_clone = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b") }
        local owner = heroWith("test_a")
        H.AddPlayer(0, owner)
        local clone = heroWith("test_a", { copy = "clone" })
        local enemyClone = heroWith("test_a", { copy = "clone" })
        enemyClone.playerID = 5
        -- Иллюзия чужого героя под контролем этого игрока (Wall of Replica)
        local replica = heroWith("test_a", { copy = "illusion" })
        replica.name = "npc_dota_hero_lina"

        OSC_Abilities.GiveRandom(owner, false)

        H.truthy(replica:FindAbilityByName("test_a"), "illusion of another hero untouched")

        H.eq(owner.osc_current_ability, "test_b", "owner ability")
        H.truthy(clone:FindAbilityByName("test_b"), "clone got new ability")
        H.eq(clone:FindAbilityByName("test_a"), nil, "clone lost old ability")
        H.truthy(enemyClone:FindAbilityByName("test_a"), "other player's copy untouched")
    end,

    set_entry_level_raises_linked = function()
        setup()
        H.DefineAbility("test_b")
        H.DefineAbility("test_b_sub")
        OSC_ABILITY_POOL = { entry("test_b", { linked = { { name = "test_b_sub" } } }) }
        local hero = heroWith("test_b")
        hero:AddAbility("test_b_sub"):SetLevel(1)

        OSC_Abilities.SetEntryLevel(hero, "test_b", 3)

        H.eq(hero:FindAbilityByName("test_b"):GetLevel(), 3, "main level")
        H.eq(hero:FindAbilityByName("test_b_sub"):GetLevel(), 3, "linked level")

        OSC_Abilities.SetEntryLevel(hero, "test_b", 2)
        H.eq(hero:FindAbilityByName("test_b"):GetLevel(), 3, "level never lowered")
    end,
    sync_copies_keeps_unchanged_ability = function()
        setup()
        H.DefineAbility("test_a")
        OSC_ABILITY_POOL = { entry("test_a") }
        local owner = heroWith("test_a")
        owner:FindAbilityByName("test_a"):SetLevel(3)
        H.AddPlayer(0, owner)
        local clone = heroWith("test_a", { copy = "clone" })
        local cloneAbility = clone:FindAbilityByName("test_a")
        cloneAbility.cooldown = 12

        OSC_Abilities.SyncCopies(owner)

        H.eq(clone:FindAbilityByName("test_a"), cloneAbility, "same ability handle kept")
        H.eq(cloneAbility.cooldown, 12, "cooldown not reset")
        H.eq(cloneAbility:GetLevel(), 3, "level synced")
    end,

    validate_keeps_pool_when_everything_missing = function()
        setup()
        OSC_ABILITY_POOL = { entry("test_x"), entry("test_y") }
        OSC_ULTIMATE_POOL = {}

        OSC_Abilities.ValidatePools()

        H.eq(#OSC_ABILITY_POOL, 2, "pool left intact")
        H.truthy(H.logged("validation skipped"), "skip is logged")
    end,
    rotation_puts_new_ability_into_old_slot = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        H.DefineAbility("test_casino")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b") }
        local hero = H.NewHero({ abilities = { "test_a", "test_casino" }, level = 3 })
        hero.osc_current_ability = "test_a"

        OSC_Abilities.GiveRandom(hero, false)

        H.eq(slotOf(hero, "test_b"), 0, "new ability takes the old slot (Q)")
        H.eq(slotOf(hero, "test_casino"), 1, "other abilities stay in place")
        H.eq(hero:FindAbilityByName("test_b"):IsHidden(), false, "new ability visible")
    end,

    active_old_ability_kept_hidden_until_delay = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b") }
        local hero = heroWith("test_a")

        OSC_Abilities.GiveRandom(hero, false)

        local old = hero:FindAbilityByName("test_a")
        H.truthy(old, "old ability still exists so its projectiles finish")
        H.eq(old:IsHidden(), true, "old ability hidden")
        local think
        for name, value in pairs(H.thinks) do
            if string.find(name, "osc_retire_ability", 1, true) then think = value end
        end
        H.truthy(think, "removal scheduled")
        H.eq(think.delay, OSC_CONFIG.ROTATION_OLD_ABILITY_LIFETIME, "removal delay from config")

        H.RunThinksMatching("osc_retire_ability")
        H.eq(hero:FindAbilityByName("test_a"), nil, "old ability removed after delay")
    end,

    passive_old_ability_removed_at_once = function()
        setup()
        H.DefineAbility("test_passive", { passive = true })
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_passive"), entry("test_b") }
        local hero = heroWith("test_passive")

        OSC_Abilities.GiveRandom(hero, false)

        H.eq(hero:FindAbilityByName("test_passive"), nil, "hidden passive would keep working, so it goes now")
    end,

    reroll_back_to_retired_ability = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b") }
        local hero = heroWith("test_a")

        OSC_Abilities.GiveRandom(hero, false)
        OSC_Abilities.GiveRandom(hero, false)

        H.eq(hero.osc_current_ability, "test_a", "current ability")
        local count = 0
        for index = 0, hero:GetAbilityCount() - 1 do
            local ability = hero:GetAbilityByIndex(index)
            if ability and ability.name == "test_a" then count = count + 1 end
        end
        H.eq(count, 1, "single test_a on the hero")
        H.eq(hero:FindAbilityByName("test_a"):IsHidden(), false, "it is the visible one")
        H.eq(slotOf(hero, "test_a"), 0, "in slot Q")

        H.RunThinksMatching("osc_retire_ability")
        H.truthy(hero:FindAbilityByName("test_a"), "pending removal does not take the new ability")
    end,
    hero_extras_granted_from_config = function()
        setup()
        H.DefineAbility("test_extra", { maxLevel = 1 })
        OSC_HERO_EXTRA_ABILITIES = { npc_dota_hero_lina = { "test_extra" } }
        local lina = H.NewHero({ name = "npc_dota_hero_lina" })
        local axe = H.NewHero({ name = "npc_dota_hero_axe" })

        OSC_Abilities.GrantHeroExtras(lina)
        OSC_Abilities.GrantHeroExtras(axe)

        local extra = lina:FindAbilityByName("test_extra")
        H.truthy(extra, "extra ability granted")
        H.eq(extra:GetLevel(), 1, "extra ability learned")
        H.eq(extra:IsHidden(), false, "extra ability visible")
        H.eq(axe:FindAbilityByName("test_extra"), nil, "other heroes do not get it")
    end,

    hero_extras_survive_strip = function()
        setup()
        H.DefineAbility("test_extra")
        OSC_HERO_EXTRA_ABILITIES = { npc_dota_hero_lina = { "test_extra" } }
        local lina = H.NewHero({ name = "npc_dota_hero_lina", abilities = { "test_extra", "lina_dragon_slave" } })

        OSC_Abilities.StripHero(lina)

        H.truthy(lina:FindAbilityByName("test_extra"), "extra ability kept")
        H.eq(lina:FindAbilityByName("lina_dragon_slave"), nil, "regular ability stripped")
    end,
}
