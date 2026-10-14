-- Состояние героя в одном месте, dev-команда -hero_state, выдача конкретной записи

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/core/hero_state")
    require("osc/systems/abilities")
end

local function entry(name)
    return { name = name, hero = "npc_dota_hero_axe", label = name, tags = { "damage" } }
end

return {
    state_created_with_every_field = function()
        setup()
        local hero = H.NewHero({})
        H.eq(OSC_HeroState.Peek(hero), nil, "no state before first use")

        local state = OSC_HeroState.Get(hero)

        H.eq(OSC_HeroState.Get(hero), state, "same table on repeat")
        H.eq(state.initialized, false, "initialized default")
        H.eq(state.init_attempts, 0, "attempts default")
        H.eq(state.anchored, false, "anchor default")
        H.eq(state.pending_choices, nil, "no choices yet")
        local names = {}
        for _, field in ipairs(OSC_HeroState.Fields()) do names[field.name] = true end
        for _, required in ipairs({ "ability", "ultimate", "anchored", "pending_choices" }) do
            H.truthy(names[required], "field described: " .. required)
        end
    end,

    describe_lists_state_abilities_and_modifiers = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b") }
        local hero = H.NewHero({ abilities = { "test_a" }, level = 3 })
        OSC_HeroState.Get(hero).ability = "test_a"
        hero:AddNewModifier(hero, nil, "modifier_test", {})

        OSC_Abilities.GiveRandom(hero, false)
        local text = table.concat(OSC_HeroState.Describe(hero), "\n")

        H.truthy(string.find(text, "ability = test_b", 1, true), "current ability shown")
        H.truthy(string.find(text, "anchored = false", 1, true), "every field shown")
        H.truthy(string.find(text, "pending_choices = nil", 1, true), "nil fields shown too")
        H.truthy(string.find(text, "abilities: 2 (hidden 1, retired 1)", 1, true),
            "retired hidden ability counted: " .. text)
        H.truthy(string.find(text, "modifiers: 1", 1, true), "modifier count")
    end,

    dev_command_prints_state = function()
        setup()
        require("osc/core/commands")
        OSC_Commands.Init()
        local hero = H.NewHero({})
        H.AddPlayer(0, hero)
        OSC_CONFIG.DEVELOPMENT_MODE = false

        H.FireGameEvent("player_chat", { text = "-hero_state", playerid = 0 })
        H.eq(H.logged("Hero state:"), false, "ignored outside development mode")

        OSC_CONFIG.DEVELOPMENT_MODE = true
        H.FireGameEvent("player_chat", { text = "-hero_state", playerid = 0 })
        H.truthy(H.logged("Hero state: npc_dota_hero_axe"), "state logged")
        H.truthy(H.logged("modifiers:"), "modifier count logged")
    end,

    dev_command_win_kills_enemy_ancient = function()
        setup()
        require("osc/core/commands")
        OSC_Commands.Init()
        H.AddPlayer(0, H.NewHero({}))
        H.players[0].team = DOTA_TEAM_BADGUYS
        local killed = {}
        local function fort(team)
            return {
                GetTeamNumber = function() return team end,
                ForceKill = function() table.insert(killed, team) end,
            }
        end
        H.byClass["npc_dota_fort"] = { fort(DOTA_TEAM_GOODGUYS), fort(DOTA_TEAM_BADGUYS) }
        OSC_CONFIG.DEVELOPMENT_MODE = false

        H.FireGameEvent("player_chat", { text = "-win", playerid = 0 })
        H.eq(#killed, 0, "ignored outside development mode")

        OSC_CONFIG.DEVELOPMENT_MODE = true
        H.FireGameEvent("player_chat", { text = "-win", playerid = 0 })
        H.eq(#killed, 1, "one ancient killed")
        H.eq(killed[1], DOTA_TEAM_GOODGUYS, "enemy ancient")
        H.byClass["npc_dota_fort"] = nil
    end,

    give_puts_chosen_entry = function()
        setup()
        H.DefineAbility("test_a")
        H.DefineAbility("test_b")
        H.DefineAbility("test_c")
        OSC_ABILITY_POOL = { entry("test_a"), entry("test_b"), entry("test_c") }
        local hero = H.NewHero({ abilities = { "test_a" }, level = 3 })
        OSC_HeroState.Get(hero).ability = "test_a"

        local given = OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[3], false)

        H.eq(given.name, "test_c", "returned entry")
        H.eq(OSC_HeroState.Get(hero).ability, "test_c", "state updated")
        H.eq(hero:GetAbilityByIndex(0).name, "test_c", "in the old slot")
    end,

    casino_machine_lives_in_hero_state = function()
        setup()
        require("osc/systems/casino")
        local ogre = H.NewHero({ name = "npc_dota_hero_ogre_magi" })
        H.AddPlayer(0, ogre)
        local machine = H.NewHero({ name = "npc_osc_casino_test_object" })
        machine.index = 42
        machine.SetMaterialGroup = function() end
        machine.SetHullRadius = function() end
        machine.SetForwardVector = function() end
        CreateUnitByName = function() return machine end

        OSC_Casino.SpawnMachine(ogre)

        H.eq(OSC_HeroState.Get(ogre).casino_machine, machine, "machine stored in hero state")
        H.eq(ogre.osc_casino_machine, nil, "no loose field on the hero")
        local text = table.concat(OSC_HeroState.Describe(ogre), "\n")
        H.truthy(string.find(text, "casino_machine = <npc_osc_casino_test_object #42>", 1, true),
            "shown by -hero_state: " .. text)
    end,
}
