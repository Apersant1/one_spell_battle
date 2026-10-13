-- 1.5: предмет «Якорь» пропускает ровно одну ротацию

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

-- Предмет в инвентаре героя; use() применяет его
local function anchorItem(hero, caster)
    local item = item_osc_anchor()
    item.GetCaster = function() return caster or hero end
    hero.items[0] = item
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

        H.eq(OSC_HeroState.Get(hero).anchored, true, "anchor set")
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

        H.eq(OSC_HeroState.Get(hero).anchored, false, "owner not anchored")
        H.eq(OSC_HeroState.Get(double).anchored, false, "double not anchored")
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
        H.eq(OSC_HeroState.Get(hero).anchored, false, "anchor used up")
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
        H.eq(OSC_HeroState.Get(hero).anchored, false, "anchor used up")
    end,

    disabled_by_flag = function()
        local hero = setup()
        OSC_CONFIG.ANCHOR_ENABLED = false
        local item = anchorItem(hero)

        item:OnSpellStart()

        H.eq(OSC_HeroState.Get(hero).anchored, false, "not anchored")
        H.eq(item._removed, nil, "charge kept")
    end,
}
