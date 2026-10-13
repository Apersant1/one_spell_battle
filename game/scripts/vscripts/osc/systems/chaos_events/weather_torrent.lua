-- Штормовое предупреждение: под героями появляются метки, и через
-- DELAY секунд из них бьёт поток Кунки — от него можно уйти
local cfg = OSC_CONFIG.CHAOS_ROUNDS.WEATHER.TORRENT

local function Erupt(position, source)
    OSC_Weather.PlayParticle(cfg.PARTICLE, position)
    OSC_Weather.PlaySound(cfg.SOUND, position, source)

    for _, hero in ipairs(OSC_Weather.HeroesInRadius(position, cfg.RADIUS)) do
        OSC_Weather.Hurt(hero, cfg.DAMAGE_PCT)
        -- подбрасывает вверх на месте, на время полёта герой оглушён
        hero:AddNewModifier(hero, nil, "modifier_knockback", {
            center_x = position.x,
            center_y = position.y,
            center_z = position.z,
            duration = cfg.LIFT_DURATION,
            knockback_duration = cfg.LIFT_DURATION,
            knockback_distance = 0,
            knockback_height = cfg.LIFT_HEIGHT,
            should_stun = 1,
        })
    end
end

OSC_ChaosEvents:Register({
    id = "weather_torrent",
    weight = cfg.WEIGHT,
    tick_interval = cfg.TICK,
    description_params = {
        damage_pct = cfg.DAMAGE_PCT,
        delay = OSC_Weather.FormatNumber(cfg.DELAY),
    },

    OnInterval = function(_, ctx)
        -- поток, который не успеет ударить до конца раунда, не ставим
        if ctx.remaining <= cfg.DELAY then return end
        for _, hero in ipairs(OSC_Weather.PickTargets(cfg.TARGETS)) do
            local position = hero:GetAbsOrigin()
            OSC_Weather.ShowWarning(position, cfg.RADIUS, cfg.DELAY)
            OSC_Weather.PlayParticle(cfg.WARN_PARTICLE, position)
            OSC_Weather.PlaySound(cfg.WARN_SOUND, position, hero)
            OSC_Weather.After(cfg.DELAY, function()
                Erupt(position, hero)
            end)
        end
    end,
})