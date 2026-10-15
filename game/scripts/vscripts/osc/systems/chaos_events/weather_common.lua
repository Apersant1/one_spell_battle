-- Общие функции для «погодных» хаос-событий (гроза, потоки, дроны).
-- Урон считается от максимального здоровья и никогда не добивает героя.

require("osc/core/runtime_config")
require("osc/core/heroes")

OSC_Weather = OSC_Weather or {}



-- Бьём боевые тела (основные герои, клоны Meepo, Tempest Double) — те же,
-- на кого действуют остальные хаос-эффекты; иллюзии не трогаем
local function IsValidTarget(hero)
    return OSC_Heroes.IsCombatHero(hero)
        and hero:IsAlive()
        and not hero:IsInvulnerable()
        and not hero:IsMagicImmune()
        -- у своего фонтана не бьём: там возрождаются и закупаются
        and not hero:HasModifier("modifier_fountain_aura_buff")
end

function OSC_Weather.FormatNumber(value)
    local text = string.format("%.1f", value)
    return (string.gsub(text, "%.0$", ""))
end


-- До count случайных живых героев обеих команд, по которым можно бить
function OSC_Weather.PickTargets(count)
    local candidates = {}
    for _, hero in pairs(HeroList:GetAllHeroes() or {}) do
        if IsValidTarget(hero) then
            table.insert(candidates, hero)
        end
    end
    local result = {}
    while #result < count and #candidates > 0 do
        table.insert(result, table.remove(candidates, RandomInt(1, #candidates)))
    end
    return result
end

-- Урон в процентах от максимума здоровья, но не ниже 1 HP: погода не убивает
-- и никому не даёт золота за убийство
function OSC_Weather.Hurt(hero, damagePct)
    if not IsValidTarget(hero) then return end
    local damage = math.floor(hero:GetMaxHealth() * damagePct / 100)
    local health = hero:GetHealth()
    damage = math.min(damage, health - 1)
    if damage > 0 then
        hero:SetHealth(health - damage)
    end
end

function OSC_Weather.Stun(hero, duration)
    if duration and duration > 0 and IsValidTarget(hero) then
        hero:AddNewModifier(hero, nil, "modifier_stunned", { duration = duration })
    end
end

-- Частица в точке мира; extraPoints — номера контрольных точек, куда тоже
-- ставим эту позицию (у некоторых эффектов центр задаётся не в точке 0).
-- lifetime — для зацикленных эффектов (пузыри Torrent): сами они не гаснут,
-- уничтожаем через lifetime секунд
function OSC_Weather.PlayParticle(name, position, extraPoints, lifetime)
    if not name or name == "" then return end
    local particle = ParticleManager:CreateParticle(name, PATTACH_WORLDORIGIN, nil)
    ParticleManager:SetParticleControl(particle, 0, position)
    for _, point in ipairs(extraPoints or {}) do
        ParticleManager:SetParticleControl(particle, point, position)
    end
    if not lifetime then
        ParticleManager:ReleaseParticleIndex(particle)
        return
    end
    GameRules:GetGameModeEntity():SetContextThink(
        DoUniqueString("osc_weather_particle"),
        function()
            ParticleManager:DestroyParticle(particle, false)
            ParticleManager:ReleaseParticleIndex(particle)
            return nil
        end,
        lifetime
    )
end

-- Звук в точке; соседний герой нужен движку как «источник» звука
function OSC_Weather.PlaySound(name, position, source)
    if name and name ~= "" and IsValidEntity(source) then
        EmitSoundOnLocationWithCaster(position, name, source)
    end
end

-- Круг-предупреждение на земле: показываем, куда сейчас прилетит
function OSC_Weather.ShowWarning(position, radius, duration)
    local name = OSC_Config.Get("CHAOS_ROUNDS.WEATHER.WARNING_RING")
    if not name or name == "" then return end
    local particle = ParticleManager:CreateParticle(name, PATTACH_WORLDORIGIN, nil)
    ParticleManager:SetParticleControl(particle, 0, position)
    ParticleManager:SetParticleControl(particle, 1, Vector(radius, 0, 0))
    GameRules:GetGameModeEntity():SetContextThink(
        DoUniqueString("osc_weather_warning"),
        function()
            ParticleManager:DestroyParticle(particle, false)
            ParticleManager:ReleaseParticleIndex(particle)
            return nil
        end,
        duration
    )
end

-- Все живые герои в радиусе от точки (обеих команд)
function OSC_Weather.HeroesInRadius(position, radius)
    local result = {}
    for _, hero in pairs(HeroList:GetAllHeroes() or {}) do
        if IsValidTarget(hero)
            and (hero:GetAbsOrigin() - position):Length2D() <= radius then
            table.insert(result, hero)
        end
    end
    return result
end

-- Выполнить fn через delay секунд, если тот же хаос-раунд ещё идёт
-- (раунд мог закончиться досрочно через -chaos_stop или смениться)
function OSC_Weather.After(delay, fn)
    local rounds = OSC_ChaosRounds
    local event = rounds and rounds.event
    local endTime = rounds and rounds.endTime
    GameRules:GetGameModeEntity():SetContextThink(
        DoUniqueString("osc_weather_delay"),
        function()
            if rounds and (rounds.event ~= event or rounds.endTime ~= endTime) then
                return nil
            end
            local ok, err = pcall(fn)
            if not ok then
                OSC_Logger.Error("[Weather] " .. tostring(err))
            end
            return nil
        end,
        delay
    )
end