-- script_reload перезапускает файлы модулей. Таблица модуля должна остаться
-- той же: на неё ссылаются уже запущенные таймеры и подписки на события.

local MODULES = {
    { file = "osc/core/logger", global = "OSC_Logger" },
    { file = "osc/core/notifications", global = "OSC_Notifications" },
    { file = "osc/core/commands", global = "OSC_Commands" },
    { file = "osc/core/heroes", global = "OSC_Heroes" },
    { file = "osc/core/game_events", global = "OSC_GameEvents" },
    { file = "osc/core/client_commands", global = "OSC_ClientCommands" },
    { file = "osc/core/hero_state", global = "OSC_HeroState" },
    { file = "osc/core/anchor", global = "OSC_Anchor" },
    { file = "osc/systems/ability_selection", global = "OSC_AbilitySelection" },
    { file = "osc/systems/abilities", global = "OSC_Abilities" },
    { file = "osc/systems/casino", global = "OSC_Casino" },
    { file = "osc/systems/couriers", global = "OSC_Couriers" },
    { file = "osc/systems/hero_lifecycle", global = "OSC_HeroLifecycle" },
    { file = "osc/systems/rotation_choice", global = "OSC_RotationChoice" },
    { file = "osc/systems/rotation", global = "OSC_Rotation" },
    { file = "osc/systems/team_shuffle", global = "OSC_TeamShuffle" },
    { file = "osc/systems/chaos_events/registry", global = "OSC_ChaosEvents" },
    { file = "osc/systems/chaos_rounds", global = "OSC_ChaosRounds" },
}

return {
    modules_keep_their_table_on_reload = function()
        require("osc/config/config")
        require("osc/config/ability_pools")
        local before = {}
        for _, module in ipairs(MODULES) do
            require(module.file)
            before[module.global] = _G[module.global]
        end

        local replaced = {}
        for _, module in ipairs(MODULES) do
            package.loaded[module.file] = nil
            require(module.file)
            if _G[module.global] ~= before[module.global] then
                table.insert(replaced, module.global)
            end
        end

        H.eq(table.concat(replaced, ", "), "", "modules recreated on reload")
    end,

    hero_state_gets_new_fields_after_reload = function()
        require("osc/core/hero_state")
        local hero = H.NewHero({})
        local state = OSC_HeroState.Get(hero)
        state.ability = "test_a"
        state.anchored = nil -- как будто поле добавили после создания состояния

        package.loaded["osc/core/hero_state"] = nil
        require("osc/core/hero_state")

        H.eq(OSC_HeroState.Get(hero), state, "same state table")
        H.eq(state.ability, "test_a", "values kept")
        H.eq(state.anchored, false, "new field filled with its default")
    end,

    rotation_state_survives_reload = function()
        require("osc/config/config")
        require("osc/systems/rotation")
        OSC_Rotation.timer_started = true
        OSC_Rotation.next_time = 123

        package.loaded["osc/systems/rotation"] = nil
        require("osc/systems/rotation")

        H.eq(OSC_Rotation.timer_started, true, "timer flag kept")
        H.eq(OSC_Rotation.next_time, 123, "next rotation time kept")
    end,
}
