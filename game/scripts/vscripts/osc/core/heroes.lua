-- Единое определение «какой герой нам нужен». Все системы проверяют героев
-- только через эти функции, чтобы правила не расходились.
--
-- Виды героев в матче:
--   основной герой — выбранный герой игрока: сам юнит, который возвращает
--     PlayerResource:GetSelectedHeroEntity(его игрок). Солдаты Monkey King
--     (Wukong's Command) тоже IsRealHero, но выбранным героем не являются.
--     Его инициализирует hero_lifecycle, его меняет ротация, ему принадлежат
--     предметы режима и курьеры команды.
--   копия — иллюзия, Tempest Double или клон Meepo. Своих способностей режима
--     не получает: копирует способности основного героя своего игрока.
--   боевое тело — всё, у чего своё здоровье, мана и перезарядки: основной
--     герой, клоны Meepo и Tempest Double. Иллюзии сюда не входят.
--
-- Клоны Meepo и Tempest Double — боевые тела: хаос-эффекты (перезарядки,
-- бесплатная мана) и погода действуют на них так же, как на основного героя.
-- Солдаты Monkey King — ни основной герой, ни копия, ни боевое тело.

OSC_Heroes = OSC_Heroes or {}

function OSC_Heroes.IsHeroUnit(unit)
    return IsValidEntity(unit) and unit.IsHero ~= nil and unit:IsHero() == true
end

-- Солдат Wukong's Command: у него модификатор
-- modifier_monkey_king_fur_army_soldier* (имя зависит от состояния солдата)
local SOLDIER_MODIFIER = "monkey_king_fur_army_soldier"

function OSC_Heroes.IsFurArmySoldier(unit)
    if not unit.GetModifierCount or not unit.GetModifierNameByIndex then
        return false
    end
    for index = 0, unit:GetModifierCount() - 1 do
        local name = unit:GetModifierNameByIndex(index)
        if name and string.find(name, SOLDIER_MODIFIER, 1, true) then
            return true
        end
    end
    return false
end

local function IsCloneOrDouble(unit)
    return (unit.IsTempestDouble and unit:IsTempestDouble())
        or (unit.IsClone and unit:IsClone())
        or false
end

-- Иллюзия, Tempest Double или клон Meepo
function OSC_Heroes.IsCopy(unit)
    if not OSC_Heroes.IsHeroUnit(unit) or OSC_Heroes.IsFurArmySoldier(unit) then
        return false
    end
    return (unit.IsIllusion and unit:IsIllusion()) or IsCloneOrDouble(unit)
end

-- Основной герой игрока: тот самый юнит, который выбран игроком-владельцем
function OSC_Heroes.IsMainHero(unit)
    if not OSC_Heroes.IsHeroUnit(unit)
        or unit.IsRealHero == nil or unit:IsRealHero() ~= true
        or OSC_Heroes.IsCopy(unit) then
        return false
    end
    local playerID = unit.GetPlayerOwnerID and unit:GetPlayerOwnerID()
    return playerID ~= nil and OSC_Heroes.GetPlayerHero(playerID) == unit
end

-- Боевое тело: основной герой, клон Meepo или Tempest Double (не иллюзия,
-- не солдат Monkey King)
function OSC_Heroes.IsCombatHero(unit)
    if OSC_Heroes.IsMainHero(unit) then
        return true
    end
    return OSC_Heroes.IsCopy(unit) and IsCloneOrDouble(unit)
end

-- Основной герой игрока или nil
function OSC_Heroes.GetPlayerHero(playerID)
    if playerID == nil or not PlayerResource:IsValidPlayerID(playerID) then
        return nil
    end
    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    if IsValidEntity(hero) then
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

-- Основной герой, способности которого копирует копия: герой её игрока с
-- тем же именем юнита (иллюзия чужого героя под контролем игрока — Wall of
-- Replica — копией его героя не считается), как в ForEachCopy
function OSC_Heroes.GetCopyOwner(copy)
    if not OSC_Heroes.IsCopy(copy) then return nil end
    local owner = OSC_Heroes.GetPlayerHero(copy:GetPlayerOwnerID())
    if owner and owner ~= copy and owner:GetUnitName() == copy:GetUnitName() then
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
