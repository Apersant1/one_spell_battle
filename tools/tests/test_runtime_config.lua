-- Чтение конфига через OSC_Config.Get с рантайм-переопределениями

local function setup()
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/core/runtime_config")
end

return {
    get_reads_base_and_nested_paths = function()
        setup()
        H.eq(OSC_Config.Get("ROTATION_INTERVAL"), OSC_CONFIG.ROTATION_INTERVAL, "top level")
        H.eq(OSC_Config.Get("CHAOS_ROUNDS.WEATHER.STORM.TICK"), OSC_CONFIG.CHAOS_ROUNDS.WEATHER.STORM.TICK,
            "nested path")
        H.eq(OSC_Config.Get("NO_SUCH_KEY"), nil, "unknown key")
        H.eq(OSC_Config.Get("ROTATION_INTERVAL.DEEPER"), nil, "path through a number")
    end,

    override_does_not_touch_config = function()
        setup()
        local original = OSC_CONFIG.ROTATION_INTERVAL

        OSC_Config.SetOverride("ROTATION_INTERVAL", 30)
        OSC_Config.SetOverride("CHAOS_ROUNDS.INTERVAL", 120)

        H.eq(OSC_Config.Get("ROTATION_INTERVAL"), 30, "override read")
        H.eq(OSC_Config.Get("CHAOS_ROUNDS.INTERVAL"), 120, "nested override read")
        H.eq(OSC_CONFIG.ROTATION_INTERVAL, original, "OSC_CONFIG untouched")
        H.eq(OSC_CONFIG.CHAOS_ROUNDS.INTERVAL, 200, "nested OSC_CONFIG untouched")

        OSC_Config.ClearOverride("ROTATION_INTERVAL")
        H.eq(OSC_Config.Get("ROTATION_INTERVAL"), original, "override cleared")
    end,

    override_rejects_typos_and_wrong_types = function()
        setup()
        local ok = pcall(OSC_Config.SetOverride, "ROTATION_INTERVL", 30)
        H.eq(ok, false, "unknown path rejected")
        ok = pcall(OSC_Config.SetOverride, "ROTATION_INTERVAL", "30")
        H.eq(ok, false, "string for a number rejected")
        H.eq(next(OSC_Config.Overrides()), nil, "nothing stored")
    end,

    overrides_survive_reload = function()
        setup()
        OSC_Config.SetOverride("ROTATION_INTERVAL", 90)

        for _, name in ipairs({ "osc/config/config", "osc/core/runtime_config" }) do
            package.loaded[name] = nil
            require(name)
        end

        H.eq(OSC_Config.Get("ROTATION_INTERVAL"), 90, "override kept after reload")
        H.eq(OSC_CONFIG.ROTATION_INTERVAL, 60, "config re-read from file")
    end,

    rotation_timer_uses_override = function()
        setup()
        require("osc/core/notifications")
        require("osc/systems/abilities")
        require("osc/systems/rotation")
        OSC_GameEvents.Init()
        OSC_Rotation.Init()

        OSC_Config.SetOverride("ROTATION_INTERVAL", 30)
        H.state = DOTA_GAMERULES_STATE_GAME_IN_PROGRESS
        H.FireGameEvent("game_rules_state_change", {})

        H.eq(OSC_Rotation.next_time, 30, "first rotation after the overridden interval")
        H.eq(H.netTables.timer.interval, 30, "HUD gets the overridden interval")
    end,

    chaos_reads_values_on_use = function()
        setup()
        require("osc/core/notifications")
        require("osc/systems/chaos_events/registry")
        require("osc/systems/chaos_events/weather_common")
        require("osc/systems/chaos_events/weather_storm")
        require("osc/systems/chaos_rounds")
        OSC_ChaosRounds:Init()
        local storm = OSC_ChaosEvents:Get("weather_storm")

        OSC_Config.SetOverride("CHAOS_ROUNDS.WEATHER.STORM.WEIGHT", 0)
        OSC_Config.SetOverride("CHAOS_ROUNDS.WEATHER.STORM.TICK", 4)
        OSC_Config.SetOverride("CHAOS_ROUNDS.DURATION", 12)

        H.eq(OSC_ChaosEvents:Weight(storm), 0, "weight read after registration")
        H.eq(OSC_ChaosEvents:TickInterval(storm), 4, "tick read on use")
        H.eq(OSC_ChaosEvents:DescriptionParams(storm).tick, "4", "description follows the override")
        H.eq(OSC_ChaosEvents:PickRandom(nil, 0), nil, "zero weight disables the event")

        OSC_ChaosRounds:StartEvent(storm)
        H.eq(OSC_ChaosRounds.endTime, 12, "duration from the override")
    end,
}
