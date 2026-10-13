-- Гроза: молнии Зевса бьют по случайным героям
local cfg = OSC_CONFIG.CHAOS_ROUNDS.WEATHER.STORM

OSC_ChaosEvents:Register({
    id = "weather_storm",
    weight = cfg.WEIGHT,
    tick_interval = cfg.TICK,
    description_params = {
        damage_pct = cfg.DAMAGE_PCT,
        tick = OSC_Weather.FormatNumber(cfg.TICK)
    },

    OnInterval = function(_, ctx)
        if ctx.remaining <= 0 then return end
        for _, hero in ipairs(OSC_Weather.PickTargets(cfg.TARGETS)) do
            local position = hero:GetAbsOrigin()
            -- точка 0 — земля, точка 1 — небо, откуда бьёт молния
            local particle = ParticleManager:CreateParticle(cfg.PARTICLE, PATTACH_WORLDORIGIN, nil)
            ParticleManager:SetParticleControl(particle, 0, position)
            ParticleManager:SetParticleControl(particle, 1, position + Vector(0, 0, 2000))
            ParticleManager:ReleaseParticleIndex(particle)
            OSC_Weather.PlaySound(cfg.SOUND, position, hero)

            OSC_Weather.Hurt(hero, cfg.DAMAGE_PCT)
            OSC_Weather.Stun(hero, cfg.STUN)
        end
    end,
})