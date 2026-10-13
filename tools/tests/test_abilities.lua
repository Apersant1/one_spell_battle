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
        local subSlot = slotOf(hero, "test_b_sub")
        H.truthy(subSlot >= 2 and subSlot <= 4, "linked ability in slots 2-4, got " .. tostring(subSlot))
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
        H.eq(hero:FindAbilityByName("test_b"), nil, "old ability removed")
        H.eq(hero:FindAbilityByName("test_b_sub"), nil, "old linked ability removed")
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

        H.eq(old.toggled, false, "toggle switched off")
        H.eq(hero:FindAbilityByName("test_a"), nil, "old ability removed")
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
}
