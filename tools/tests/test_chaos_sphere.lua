-- Сфера хаоса: выпадение с Рошана, предложение, оба режима, отмена и отказы

local ULTS = { "test_ult_a", "test_ult_b", "test_ult_c", "test_ult_d" }
local BASICS = { "test_q1", "test_q2", "test_q3" }
local TAGS = { "damage", "disable", "mobility", "support" }

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    require("osc/systems/chaos_sphere")
    require("osc/items/item_chaos_sphere")
    OSC_ABILITY_POOL, OSC_ULTIMATE_POOL = {}, {}
    for index, name in ipairs(BASICS) do
        H.DefineAbility(name)
        table.insert(OSC_ABILITY_POOL, { name = name, hero = "npc_dota_hero_axe",
            label = name, tags = { TAGS[index] } })
    end
    for index, name in ipairs(ULTS) do
        H.DefineAbility(name, { ultimate = true })
        table.insert(OSC_ULTIMATE_POOL, { name = name, hero = "npc_dota_hero_axe",
            label = "Label " .. name, tags = { TAGS[index] }, rarity = "legendary" })
    end
    OSC_ChaosSphere.Init()
end

-- Основной герой игрока с основной способностью test_q1
local function addHero(playerID, team, opts)
    opts = opts or {}
    local hero = H.NewHero({ playerID = playerID, team = team, level = opts.level or 6,
        abilities = { "test_q1" } })
    H.AddPlayer(playerID, hero)
    local state = OSC_HeroState.Get(hero)
    state.ability = "test_q1"
    state.initialized = true
    state.anchor_rotations = opts.anchored and 1 or 0
    return hero
end

local function giveSphere(hero)
    local item = H.NewItem("item_osc_chaos_sphere")
    hero.items[0] = item
    return item
end

local function pick(playerID, mode, ability)
    H.listeners.osc_sphere_pick(playerID + 1, { PlayerID = playerID, mode = mode, ability = ability })
end

local function kill(index, unitName)
    H.entities[index] = {
        IsNull = function() return false end,
        GetUnitName = function() return unitName end,
        GetAbsOrigin = function() return Vector(100, 200, 0) end,
    }
    H.FireGameEvent("entity_killed", { entindex_killed = index })
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

-- Ультимейт пула, которого нет среди вариантов
local function notOffered(hero)
    for _, name in ipairs(ULTS) do
        if not contains(OSC_HeroState.Get(hero).sphere_offer.options, name) then
            return name
        end
    end
end

return {
    roshan_drops_sphere = function()
        setup()
        kill(50, "npc_dota_roshan")
        H.eq(#H.drops, 1, "one item dropped")
        H.eq(H.drops[1].item.name, "item_osc_chaos_sphere", "sphere")
        H.eq(H.drops[1].position, Vector(100 + OSC_CONFIG.CHAOS_SPHERE_DROP_OFFSET, 200, 0),
            "next to Roshan")
        H.eq(H.lastEvent("osc_notification").data.token, "#osc_notify_chaos_sphere_dropped",
            "announced")
    end,

    other_unit_drops_nothing = function()
        setup()
        kill(51, "npc_dota_neutral_kobold")
        H.eq(#H.drops, 0, "no sphere from a kobold")
    end,

    disabled_drops_nothing = function()
        setup()
        OSC_CONFIG.CHAOS_SPHERE_ENABLED = false
        kill(50, "npc_dota_roshan")
        H.eq(#H.drops, 0, "flag off")
    end,

    use_item_sends_offer = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        item.GetCaster = function() return hero end

        item_osc_chaos_sphere.OnSpellStart(item)

        local offer = OSC_HeroState.Get(hero).sphere_offer
        H.truthy(offer, "offer stored")
        H.eq(offer.item, item.index, "item entindex")
        H.eq(#offer.options, OSC_CONFIG.CHAOS_SPHERE_ULTIMATE_CHOICES, "three options")
        H.eq(offer.ultimate_allowed, true, "level 6 allowed")
        local event = H.lastEvent("osc_sphere_offer")
        H.eq(event.player.id, 0, "sent to the owner")
        H.eq(event.data.ultimate_allowed, 1, "allowed flag for the client")
        H.eq(event.data.min_level, OSC_CONFIG.CHAOS_SPHERE_MIN_LEVEL, "min level")
        H.eq(#event.data.options, 3, "client options")
        H.truthy(contains(ULTS, event.data.options[1].name), "an ultimate")
        H.eq(event.data.options[1].label, "Label " .. event.data.options[1].name, "label")
        H.truthy(event.data.options[1].rarity, "rarity")
        H.eq(hero.items[0], item, "item not consumed by use")
    end,

    offer_prefers_legendary_ultimates = function()
        setup()
        OSC_ULTIMATE_POOL[1].rarity, OSC_ULTIMATE_POOL[2].rarity = nil, nil -- a, b — обычные
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        -- Легендарок две (c, d): третий вариант добирается из остальных
        for _ = 1, 10 do
            OSC_ChaosSphere.Offer(hero, giveSphere(hero))
            local options = H.lastEvent("osc_sphere_offer").data.options
            local legendary = 0
            for _, option in ipairs(options) do
                if option.rarity == "legendary" then legendary = legendary + 1 end
            end
            H.eq(#options, 3, "three options")
            H.eq(legendary, 2, "both legendary taken")
        end
    end,

    low_level_offer_disallows_ultimate = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS, { level = 5 })
        OSC_ChaosSphere.Offer(hero, giveSphere(hero))
        H.eq(OSC_HeroState.Get(hero).sphere_offer.ultimate_allowed, false, "state")
        H.eq(H.lastEvent("osc_sphere_offer").data.ultimate_allowed, 0, "client")
    end,

    not_main_hero_refused = function()
        setup()
        addHero(0, DOTA_TEAM_GOODGUYS)
        local illusion = H.NewHero({ playerID = 0, copy = "illusion", level = 6 })

        local ok = OSC_ChaosSphere.Offer(illusion, giveSphere(illusion))

        H.eq(ok, false, "refused")
        H.eq(OSC_HeroState.Get(illusion).sphere_offer, nil, "no offer state")
        H.eq(H.lastEvent("osc_sphere_offer"), nil, "no offer event")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_sphere_err_main_hero", "error shown")
    end,

    ultimate_pick_gives_and_consumes = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)
        local chosen = OSC_HeroState.Get(hero).sphere_offer.options[2]

        pick(0, "ultimate", chosen)

        H.eq(OSC_HeroState.Get(hero).ultimate, chosen, "ultimate given")
        H.eq(hero.items[0], nil, "sphere removed from inventory")
        H.eq(item._removed, true, "item removed")
        H.eq(OSC_HeroState.Get(hero).sphere_offer, nil, "offer closed")
    end,

    ultimate_not_offered_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "ultimate", notOffered(hero))

        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "nothing given")
        H.eq(hero.items[0], item, "sphere kept")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: not offered"), "refusal logged")
    end,

    ultimate_low_level_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS, { level = 5 })
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "ultimate", OSC_HeroState.Get(hero).sphere_offer.options[1])

        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "nothing given")
        H.eq(hero.items[0], item, "sphere kept")
        H.truthy(OSC_HeroState.Get(hero).sphere_offer, "offer stays: enemies still possible")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_sphere_err_level", "error shown")
    end,

    enemies_get_new_ability = function()
        setup()
        local owner = addHero(0, DOTA_TEAM_GOODGUYS)
        local ally = addHero(1, DOTA_TEAM_GOODGUYS)
        local enemy = addHero(2, DOTA_TEAM_BADGUYS)
        local anchored = addHero(3, DOTA_TEAM_BADGUYS, { anchored = true })
        local item = giveSphere(owner)
        OSC_ChaosSphere.Offer(owner, item)

        pick(0, "enemies")

        H.truthy(OSC_HeroState.Get(enemy).ability ~= "test_q1", "enemy got a new ability")
        H.eq(OSC_HeroState.Get(anchored).ability, "test_q1", "anchored enemy untouched")
        H.eq(OSC_HeroState.Get(anchored).anchor_rotations, 1, "anchor not spent")
        H.eq(OSC_HeroState.Get(ally).ability, "test_q1", "ally untouched")
        H.eq(OSC_HeroState.Get(owner).ability, "test_q1", "owner untouched")
        H.eq(item._removed, true, "sphere consumed")
        local feed = H.lastEvent("osc_notification")
        H.eq(feed.data.token, "#osc_notify_chaos_sphere_enemies", "announced")
        H.eq(feed.player, nil, "to everyone")
        H.eq(feed.data.params.player_id, "0", "owner named")
    end,

    cancel_keeps_item = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "cancel")
        H.eq(OSC_HeroState.Get(hero).sphere_offer, nil, "offer closed")
        H.eq(hero.items[0], item, "sphere kept")

        pick(0, "ultimate", ULTS[1])
        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "no pick after cancel")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: no offer"), "refusal logged")
    end,

    pick_without_offer_refused = function()
        setup()
        addHero(0, DOTA_TEAM_GOODGUYS)
        local enemy = addHero(2, DOTA_TEAM_BADGUYS)

        pick(0, "enemies")

        H.eq(OSC_HeroState.Get(enemy).ability, "test_q1", "enemy untouched")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: no offer"), "refusal logged")
    end,

    pick_without_item_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        OSC_ChaosSphere.Offer(hero, giveSphere(hero))
        hero.items[0] = nil -- сферу переложили в тайник, продали или выкинули

        pick(0, "ultimate", OSC_HeroState.Get(hero).sphere_offer.options[1])

        H.eq(OSC_HeroState.Get(hero).ultimate, nil, "nothing given")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_sphere_err_no_item", "error shown")
    end,

    forged_mode_refused = function()
        setup()
        local hero = addHero(0, DOTA_TEAM_GOODGUYS)
        local item = giveSphere(hero)
        OSC_ChaosSphere.Offer(hero, item)

        pick(0, "everything")

        H.eq(hero.items[0], item, "sphere kept")
        H.truthy(OSC_HeroState.Get(hero).sphere_offer, "offer kept")
        H.truthy(H.logged("Chaos sphere pick of player 0 refused: invalid_mode"), "refusal logged")
    end,
}
