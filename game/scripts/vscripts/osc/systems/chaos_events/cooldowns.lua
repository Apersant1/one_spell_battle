require("osc/core/runtime_config")
OSC_ChaosEvents:Register({
    id = "cooldowns",
    weight = 10,
    modifier = "modifier_osc_chaos_cooldowns",
    description_params = function()
        return {
            cooldown_reduction_pct = OSC_Config.Get("CHAOS_ROUNDS.COOLDOWN_REDUCTION_PCT"),
        }
    end,
})