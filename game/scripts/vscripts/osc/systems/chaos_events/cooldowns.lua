OSC_ChaosEvents:Register({
    id = "cooldowns",
    weight = 10,
    modifier = "modifier_osc_chaos_cooldowns",
    description_params = {
        cooldown_reduction_pct = OSC_CONFIG.CHAOS_ROUNDS.COOLDOWN_REDUCTION_PCT,
    },
})