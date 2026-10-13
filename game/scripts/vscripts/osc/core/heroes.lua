-- Единое определение «какой герой нам нужен». Все системы проверяют героев
-- только через эти функции, чтобы правила не расходились.
--
-- Виды героев в матче:
--   основной герой — выбранный герой игрока (PlayerResource:GetSelectedHeroEntity).
--     Его инициализирует hero_lifecycle, его меняет ротация, ему принадлежат
--     предметы режима и курьеры команды.
--   копия — иллюзия, Tempest Double или клон Meepo. Своих способностей режима
--     не получает: копирует способности основного героя своего игрока.
--   боевое тело — всё, у чего своё здоровье, мана и перезарядки: основной
--     герой, клоны Meepo и Tempest Double. Иллюзии сюда не входят.
--
-- Клоны Meepo и Tempest Double — боевые тела: хаос-эффекты (перезарядки,
-- бесплатная мана) и погода действуют на них так же, как на основного героя.

OSC_Heroes = OSC_Heroes or {}

function OSC_Heroes.IsValid(entity)
    return entity ~= nil and not entity:IsNull()
end

function OSC_Heroes.IsHeroUnit(unit)
    return OSC_Heroes.IsValid(unit) and unit.IsHero ~= nil and unit:IsHero() == true
end

-- Иллюзия, Tempest Double или клон Meepo
function OSC_Heroes.IsCopy(unit)
    if not OSC_Heroes.IsHeroUnit(unit) then return false end
    return (unit.IsIllusion and unit:IsIllusion())
        or (unit.IsTempestDouble and unit:IsTempestDouble())
        or (unit.IsClone and unit:IsClone())
        or false
end

-- Основной герой игрока: не копия
function OSC_Heroes.IsMainHero(unit)
    return OSC_Heroes.IsHeroUnit(unit)
        and unit.IsRealHero ~= nil and unit:IsRealHero() == true
        and not OSC_Heroes.IsCopy(unit)
end

-- Боевое тело: основной герой, клон Meepo или Tempest Double (не иллюзия)
function OSC_Heroes.IsCombatHero(unit)
    return OSC_Heroes.IsHeroUnit(unit)
        and unit.IsRealHero ~= nil and unit:IsRealHero() == true
        and not (unit.IsIllusion and unit:IsIllusion())
end

-- Основной герой игрока или nil
function OSC_Heroes.GetPlayerHero(playerID)
    if playerID == nil or not PlayerResource:IsValidPlayerID(playerID) then
        return nil
    end
    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    if OSC_Heroes.IsValid(hero) then
        return hero
    end
    return nil
end

-- callback(hero, playerID) для основного героя каждого игрока
function OSC_Heroes.ForEachPlayerHero(callback)
    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        local hero = OSC_Heroes.GetPlayerHero(playerID)
        if hero then
            callback(hero, playerID)
        end
    end
end

-- callback(hero) для каждого боевого тела на карте
function OSC_Heroes.ForEachCombatHero(callback)
    for _, hero in pairs(HeroList:GetAllHeroes() or {}) do
        if OSC_Heroes.IsCombatHero(hero) then
            callback(hero)
        end
    end
end

-- Основной герой, способности которого копирует копия
function OSC_Heroes.GetCopyOwner(copy)
    if not OSC_Heroes.IsCopy(copy) then return nil end
    local owner = OSC_Heroes.GetPlayerHero(copy:GetPlayerOwnerID())
    if owner and owner ~= copy then
        return owner
    end
    return nil
end

-- callback(copy) для живых копий основного героя. Иллюзии чужих героев под
-- контролем того же игрока (Wall of Replica) копиями этого героя не считаются.
function OSC_Heroes.ForEachCopy(owner, callback)
    if not OSC_Heroes.IsMainHero(owner) then return end
    local playerID = owner:GetPlayerOwnerID()
    local unitName = owner:GetUnitName()
    for _, unit in pairs(HeroList:GetAllHeroes() or {}) do
        if unit ~= owner and OSC_Heroes.IsCopy(unit)
            and unit:GetPlayerOwnerID() == playerID
            and unit:GetUnitName() == unitName then
            callback(unit)
        end
    end
end
