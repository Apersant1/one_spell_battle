-- Атака дронов: ракеты Клокверка падают в случайные точки возле героев.
-- Место падения видно заранее, взрыв задевает всех рядом.

require("osc/core/runtime_config")

local function cfg(key)
    return OSC_Config.Get("CHAOS_ROUNDS.WEATHER.DRONES." .. key)
end

local function Explode(position, source)
    -- у взрыва ракеты центр может задаваться в точке 3 — ставим обе
    OSC_Weather.PlayParticle(cfg("PARTICLE"), position, { 3 })
    OSC_Weather.PlaySound(cfg("SOUND"), position, source)
    for _, hero in ipairs(OSC_Weather.HeroesInRadius(position, cfg("RADIUS"))) do
        OSC_Weather.Hurt(hero, cfg("DAMAGE_PCT"))
    end
end

OSC_ChaosEvents:Register({
    id = "weather_drones",
    weight = function() return cfg("WEIGHT") end,
    tick_interval = function() return cfg("TICK") end,
    description_params = function()
        return {
            damage_pct = cfg("DAMAGE_PCT"),
        }
    end,

    OnInterval = function(_, ctx)
        if ctx.remaining <= cfg("DELAY") then return end
        for _, hero in ipairs(OSC_Weather.PickTargets(cfg("TARGETS"))) do
            local offset = RandomVector(RandomFloat(0, cfg("SPREAD")))
            local position = GetGroundPosition(hero:GetAbsOrigin() + offset, nil)
            OSC_Weather.ShowWarning(position, cfg("RADIUS"), cfg("DELAY"))
            OSC_Weather.After(cfg("DELAY"), function()
                Explode(position, hero)
            end)
        end
    end,
})