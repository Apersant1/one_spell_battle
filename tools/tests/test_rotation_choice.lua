-- 1.4: выбор из трёх на ротации

local POOL = { "test_a", "test_b", "test_c", "test_d", "test_e", "test_f" }
local TAGS = { "damage", "disable", "mobility", "passive", "support", "damage" }

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    require("osc/systems/rotation")
    OSC_ABILITY_POOL = {}
    for index, name in ipairs(POOL) do
        H.DefineAbility(name)
        table.insert(OSC_ABILITY_POOL, { name = name, hero = "npc_dota_hero_axe",
            label = "Label " .. name, tags = { TAGS[index] } })
    end
    OSC_Rotation.Init()
    OSC_Rotation.timer_started = true
    OSC_Rotation.next_time = 60
end

local function addHero(playerID, ability)
    local hero = H.NewHero({ abilities = { ability }, playerID = playerID, level = 3 })
    H.AddPlayer(playerID, hero)
    local state = OSC_HeroState.Get(hero)
    state.ability = ability
    state.initialized = true
    return hero
end

local function warn()
    H.time = 50
    OSC_Rotation.Think()
end

local function rotate()
    H.time = 60
    OSC_Rotation.Think()
end

local function eventsFor(playerID, name)
    local result = {}
    for _, event in ipairs(H.events) do
        if event.name == name and event.player and event.player.id == playerID then
            table.insert(result, event.data)
        end
    end
    return result
end

local function optionNames(hero)
    return OSC_HeroState.Get(hero).pending_choices.options
end

local function contains(list, value)
    for _, item in ipairs(list) do
        if item == value then return true end
    end
    return false
end

local function pick(playerID, round, ability)
    H.listeners.osc_rotation_choice_pick(playerID + 1, { PlayerID = playerID, round = round, ability = ability })
end

-- Способность пула, которой нет среди вариантов героя
local function notOffered(hero)
    local options = optionNames(hero)
    for _, name in ipairs(POOL) do
        if not contains(options, name) and name ~= OSC_HeroState.Get(hero).ability then
            return name
        end
    end
end

return {
    every_player_gets_own_offer = function()
        setup()
        local first = addHero(0, "test_a")
        local second = addHero(1, "test_b")

        warn()

        for playerID, hero in pairs({ [0] = first, [1] = second }) do
            local offers = eventsFor(playerID, "osc_rotation_choice_offer")
            H.eq(#offers, 1, "one offer for player " .. playerID)
            local offer = offers[1]
            H.eq(offer.round, 1, "round")
            H.eq(offer.deadline, 60, "deadline is the rotation time")
            H.eq(offer.duration, 10, "seconds from offer to deadline")
            H.eq(#offer.options, 3, "three options")
            H.eq(offer.options[1].label, "Label " .. offer.options[1].name, "label sent")
            H.eq(contains(optionNames(hero), OSC_HeroState.Get(hero).ability), false,
                "current ability not offered")
            local net = H.netTables["choice_" .. playerID]
            H.eq(net.round, 1, "net table round")
            H.eq(net.picked, "", "nothing picked yet")
            H.eq(#net.options, 3, "net table options")
        end
    end,

    pick_is_given_on_rotation = function()
        setup()
        local hero = addHero(0, "test_a")
        local clone = H.NewHero({ abilities = { "test_a" }, playerID = 0, copy = "clone" })
        OSC_HeroState.Get(clone).ability = "test_a"
        warn()
        local options = optionNames(hero)

        pick(0, 1, options[1])
        pick(0, 1, options[2]) -- выбор можно менять до дедлайна
        H.eq(H.netTables.choice_0.picked, options[2], "picked published")

        rotate()

        H.eq(OSC_HeroState.Get(hero).ability, options[2], "picked ability given")
        H.truthy(clone:FindAbilityByName(options[2]), "clone copies the owner")
        local closed = eventsFor(0, "osc_rotation_choice_closed")
        H.eq(#closed, 1, "closed sent")
        H.eq(closed[1].round, 1, "closed round")
        H.eq(closed[1].chosen, options[2], "closed chosen")
        H.eq(next(H.netTables.choice_0.options), nil, "options cleared")
        H.eq(H.netTables.choice_0.picked, options[2], "picked kept after the change")
        H.eq(OSC_HeroState.Get(hero).pending_choices, nil, "pending cleared")
    end,

    forged_picks_are_refused = function()
        setup()
        local hero = addHero(0, "test_a")
        addHero(1, "test_b")
        H.AddPlayer(2, nil)
        warn()
        local options = optionNames(hero)
        local foreign = notOffered(hero)

        pick(0, 1, foreign)                                      -- не из своего списка
        pick(0, 2, options[1])                                   -- неверный раунд
        pick(0, 1, 42)                                           -- не строка
        pick(2, 1, options[1])                                   -- нет героя
        H.listeners.osc_rotation_choice_pick(1, { PlayerID = 9, round = 1, ability = options[1] })
        -- player_id в теле события не подменяет отправителя
        H.listeners.osc_rotation_choice_pick(2, { PlayerID = 1, player_id = 0, round = 1,
            ability = foreign })

        H.eq(OSC_HeroState.Get(hero).pending_choices.picked, nil, "nothing accepted for player 0")
        H.eq(H.netTables.choice_0.picked, "", "net table shows no pick")

        rotate()
        H.truthy(contains(options, OSC_HeroState.Get(hero).ability), "one of own three given")
        H.eq(OSC_HeroState.Get(hero).ability == foreign, false, "forged ability not given")
    end,

    pick_accepted_until_the_offer_closes = function()
        setup()
        local hero = addHero(0, "test_a")
        warn()
        local options = optionNames(hero)

        -- Часы клиента отстают на пинг: клик после deadline, но до смены
        H.time = 60.1
        pick(0, 1, options[2])
        H.eq(OSC_HeroState.Get(hero).pending_choices.picked, options[2], "late click accepted")

        OSC_Rotation.Think()
        H.eq(OSC_HeroState.Get(hero).ability, options[2], "late pick given")

        local before = H.netTables.choice_0
        pick(0, 1, options[1])
        H.eq(H.netTables.choice_0, before, "pick after close refused, net table untouched")
    end,

    refusals_do_not_republish_or_spam_the_log = function()
        setup()
        local hero = addHero(0, "test_a")
        warn()
        local published = H.netTables.choice_0
        local foreign = notOffered(hero)

        for _ = 1, 20 do
            pick(0, 1, foreign)
            pick(0, 7, optionNames(hero)[1])
        end

        H.eq(H.netTables.choice_0, published, "net table not rewritten on refusals")
        local lines = 0
        for _, line in ipairs(H.logs) do
            if string.find(line, "Rotation choice of player 0 refused", 1, true) then
                lines = lines + 1
            end
        end
        H.eq(lines, 1, "refusals logged once per interval")

        H.time = H.time + OSC_CONFIG.CLIENT_REFUSAL_LOG_INTERVAL
        pick(0, 1, foreign)
        H.truthy(H.logged("(+39 more refused)"), "suppressed count reported later")
    end,

    no_pick_gives_one_of_three = function()
        setup()
        local hero = addHero(0, "test_a")
        warn()
        local options = optionNames(hero)

        rotate()

        H.truthy(contains(options, OSC_HeroState.Get(hero).ability), "random one of the three")
        H.eq(eventsFor(0, "osc_rotation_choice_closed")[1].chosen, OSC_HeroState.Get(hero).ability,
            "closed tells what was given")
    end,

    stale_pick_falls_back = function()
        setup()
        local hero = addHero(0, "test_a")
        warn()
        local options = optionNames(hero)
        pick(0, 1, options[1])
        -- Выбранная способность пропала из пула (например, после проверки KV)
        for index, entry in ipairs(OSC_ABILITY_POOL) do
            if entry.name == options[1] then table.remove(OSC_ABILITY_POOL, index) break end
        end

        rotate()

        local given = OSC_HeroState.Get(hero).ability
        H.eq(given == options[1], false, "invalid pick not given")
        H.truthy(contains(options, given), "another offered option given")
    end,

    disabled_flag_keeps_old_rotation = function()
        setup()
        OSC_CONFIG.ROTATION_CHOICE_ENABLED = false
        local hero = addHero(0, "test_a")

        warn()
        rotate()

        H.eq(#eventsFor(0, "osc_rotation_choice_offer"), 0, "no offer")
        H.eq(#eventsFor(0, "osc_rotation_choice_closed"), 0, "no close")
        H.eq(H.netTables.choice_0, nil, "no net table")
        H.eq(OSC_HeroState.Get(hero).ability == "test_a", false, "random rotation as before")
    end,

    hero_ready_after_warning_rotates_randomly = function()
        setup()
        warn()
        local hero = addHero(0, "test_a")

        rotate()

        H.eq(#eventsFor(0, "osc_rotation_choice_closed"), 0, "nothing to close")
        H.eq(OSC_HeroState.Get(hero).ability == "test_a", false, "random rotation")
    end,

    anchored_hero_gets_no_offer = function()
        setup()
        local hero = addHero(0, "test_a")
        OSC_HeroState.Get(hero).anchor_rotations = 1

        warn()

        H.eq(#eventsFor(0, "osc_rotation_choice_offer"), 0, "no offer while anchored")
        H.eq(OSC_HeroState.Get(hero).pending_choices, nil, "no pending choices")
    end,

    reload_in_the_middle_keeps_choice = function()
        setup()
        local hero = addHero(0, "test_a")
        warn()
        local options = optionNames(hero)

        for _, name in ipairs({ "osc/core/hero_state", "osc/systems/ability_selection",
            "osc/systems/abilities", "osc/systems/rotation_choice", "osc/systems/rotation" }) do
            package.loaded[name] = nil
            require(name)
        end
        pick(0, 1, options[3])
        rotate()

        H.eq(OSC_Rotation.round, 1, "round kept")
        H.eq(OSC_HeroState.Get(hero).ability, options[3], "pick made after reload is given")
    end,
}
