-- 1.5: предмет «Якорь» пропускает ближайшие ротации (rotations по уровню),
-- заряды стакаются, два одного уровня сливаются в следующий

local POOL = { "test_a", "test_b", "test_c", "test_d", "test_e" }
local TAGS = { "damage", "disable", "mobility", "passive", "support" }

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    require("osc/systems/rotation")
    require("osc/items/item_anchor")
    OSC_ABILITY_POOL = {}
    for index, name in ipairs(POOL) do
        H.DefineAbility(name)
        table.insert(OSC_ABILITY_POOL, { name = name, hero = "npc_dota_hero_axe",
            label = name, tags = { TAGS[index] } })
    end
    OSC_Rotation.Init()
    OSC_Rotation.timer_started = true
    OSC_Rotation.next_time = 60

    local hero = H.NewHero({ abilities = { "test_a" }, level = 3 })
    H.AddPlayer(0, hero)
    local state = OSC_HeroState.Get(hero)
    state.ability = "test_a"
    state.initialized = true
    return hero
end

-- Предмет в инвентаре героя; OnSpellStart() применяет его
local function anchorItem(hero, caster, rotations, charges)
    local item = item_osc_anchor()
    item.charges = charges or 1
    item.GetCaster = function() return caster or hero end
    item.GetSpecialValueFor = function(_, key) return key == "rotations" and (rotations or 1) or 0 end
    item.GetCurrentCharges = function(self) return self.charges end
    item.SetCurrentCharges = function(self, value) self.charges = value end
    hero.items[0] = item
    return item
end

local function stack(name, charges)
    local item = H.NewItem(name)
    item.charges = charges
    return item
end

local function warn()
    H.time = OSC_Rotation.next_time - 10
    OSC_Rotation.Think()
end

local function rotate()
    H.time = OSC_Rotation.next_time
    OSC_Rotation.Think()
end

local function count(name)
    local result = 0
    for _, event in ipairs(H.events) do
        if event.name == name then result = result + 1 end
    end
    return result
end

return {
    activation_spends_the_charge_once = function()
        local hero = setup()
        local item = anchorItem(hero)

        item:OnSpellStart()

        H.eq(OSC_HeroState.Get(hero).anchor_rotations, 1, "anchor set")
        H.eq(item._removed, true, "charge spent")
        H.eq(H.netTables.anchor_0.active, 1, "HUD badge on")

        local second = anchorItem(hero)
        second:OnSpellStart()

        H.eq(second._removed, nil, "second anchor keeps its charge")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_anchor_err_active", "player warned")
    end,

    copy_cannot_use_it = function()
        local hero = setup()
        local double = H.NewHero({ playerID = 0, copy = "tempest" })
        local item = anchorItem(hero, double)

        item:OnSpellStart()

        H.eq(OSC_HeroState.Get(hero).anchor_rotations, 0, "owner not anchored")
        H.eq(OSC_HeroState.Get(double).anchor_rotations, 0, "double not anchored")
        H.eq(item._removed, nil, "charge kept")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_anchor_err_main_hero", "reason")
    end,

    keeps_ability_for_exactly_one_rotation = function()
        local hero = setup()
        anchorItem(hero):OnSpellStart()

        warn()
        H.eq(count("osc_rotation_choice_offer"), 0, "no choice while anchored")
        rotate()

        H.eq(OSC_HeroState.Get(hero).ability, "test_a", "ability kept")
        H.eq(OSC_HeroState.Get(hero).anchor_rotations, 0, "anchor used up")
        H.eq(H.netTables.anchor_0.active, 0, "HUD badge off")

        warn()
        H.eq(count("osc_rotation_choice_offer"), 1, "choice offered again")
        rotate()
        H.eq(OSC_HeroState.Get(hero).ability == "test_a", false, "next rotation changes it")
    end,

    anchor_after_offer_cancels_choice = function()
        local hero = setup()
        warn()
        local options = OSC_HeroState.Get(hero).pending_choices.options
        H.listeners.osc_rotation_choice_pick(1, { PlayerID = 0, round = 1, ability = options[1] })

        anchorItem(hero):OnSpellStart()

        local closed = H.lastEvent("osc_rotation_choice_closed")
        H.truthy(closed, "choice closed")
        H.eq(closed.data.chosen, "test_a", "current ability stays")
        H.eq(next(H.netTables.choice_0.options), nil, "options cleared")
        H.eq(OSC_HeroState.Get(hero).pending_choices, nil, "pending cleared")

        rotate()
        H.eq(OSC_HeroState.Get(hero).ability, "test_a", "pick ignored, ability kept")
        H.eq(count("osc_rotation_choice_closed"), 1, "no second close")
    end,

    works_without_choice_of_three = function()
        local hero = setup()
        OSC_CONFIG.ROTATION_CHOICE_ENABLED = false
        anchorItem(hero):OnSpellStart()

        warn()
        rotate()

        H.eq(OSC_HeroState.Get(hero).ability, "test_a", "ability kept")
        H.eq(OSC_HeroState.Get(hero).anchor_rotations, 0, "anchor used up")
    end,

    disabled_by_flag = function()
        local hero = setup()
        OSC_CONFIG.ANCHOR_ENABLED = false
        local item = anchorItem(hero)

        item:OnSpellStart()

        H.eq(OSC_HeroState.Get(hero).anchor_rotations, 0, "not anchored")
        H.eq(item._removed, nil, "charge kept")
    end,

    higher_level_skips_several_rotations = function()
        local hero = setup()
        anchorItem(hero, nil, 3):OnSpellStart()
        H.eq(H.netTables.anchor_0.rotations, 3, "HUD shows rotations")

        for round = 1, 3 do
            warn()
            H.eq(count("osc_rotation_choice_offer"), 0, "no choice on anchored round " .. round)
            rotate()
            H.eq(OSC_HeroState.Get(hero).ability, "test_a", "ability kept on round " .. round)
        end
        H.eq(OSC_HeroState.Get(hero).anchor_rotations, 0, "anchor used up")
        H.eq(H.netTables.anchor_0.active, 0, "HUD badge off")

        warn()
        H.eq(count("osc_rotation_choice_offer"), 1, "choice offered again")
    end,

    stacked_item_spends_one_charge = function()
        local hero = setup()
        local item = anchorItem(hero, nil, 1, 3)

        item:OnSpellStart()

        H.eq(item.charges, 2, "one charge spent")
        H.eq(item._removed, nil, "stack stays in inventory")
    end,

    two_of_a_level_merge_into_the_next = function()
        local hero = setup()
        hero.items[1] = stack("item_x", 1)
        hero.items[3] = stack("item_osc_anchor", 2)

        OSC_Anchor.Merge(hero)

        H.eq(hero.items[3]:GetAbilityName(), "item_osc_anchor_2", "level 2 in the merged slot")
        H.eq(hero.items[3].charges, 1, "one level 2 charge")
        H.eq(hero.items[1]:GetAbilityName(), "item_x", "other items untouched")
    end,

    merge_chains_and_keeps_the_rest = function()
        local hero = setup()
        hero.items[0] = stack("item_osc_anchor_2", 1)
        hero.items[2] = stack("item_osc_anchor", 3)

        OSC_Anchor.Merge(hero)

        H.eq(hero.items[0]:GetAbilityName(), "item_osc_anchor_3", "chain merged into level 3")
        H.eq(hero.items[2]:GetAbilityName(), "item_osc_anchor", "odd level 1 charge stays")
        H.eq(hero.items[2].charges, 1, "one level 1 charge left")
    end,

    top_level_only_stacks = function()
        local hero = setup()
        hero.items[0] = stack("item_osc_anchor_3", 4)

        OSC_Anchor.Merge(hero)

        H.eq(hero.items[0].charges, 4, "level 3 never merges")
    end,

    merge_runs_after_an_anchor_enters_inventory = function()
        local hero = setup()
        local filter
        GameRules:GetGameModeEntity().SetItemAddedToInventoryFilter = function(_, fn) filter = fn end
        OSC_Anchor.Init()
        hero.items[0] = stack("item_osc_anchor", 2)
        hero.entindex = function() return 7 end
        H.entities[7] = hero

        H.eq(filter(nil, { item_entindex_const = hero.items[0]:entindex(), inventory_parent_entindex_const = 7 }),
            true, "item is let in")
        H.thinks.osc_anchor_merge.fn()

        H.eq(hero.items[0]:GetAbilityName(), "item_osc_anchor_2", "merged on the next frame")
    end,
}
