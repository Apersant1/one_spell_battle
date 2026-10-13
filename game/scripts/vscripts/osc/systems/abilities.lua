OSC_Abilities = OSC_Abilities or {}

-- Слот способности на панели задают AddAbility (первый свободный слот) и
-- SwapAbilities; SetAbilityIndex в игре способности не переставляет.

local function IsInnateAbility(ability)
    local abilityData = GetAbilityKeyValuesByName(ability:GetAbilityName())
    return abilityData and (
        abilityData.Innate == "1"
        or abilityData.Innate == 1
        or abilityData.Innate == true
    )
end

local function HeroExtras(hero)
    return (OSC_HERO_EXTRA_ABILITIES or {})[hero:GetUnitName()] or {}
end

local function IsHeroExtra(hero, name)
    for _, extra in ipairs(HeroExtras(hero)) do
        if extra == name then
            return true
        end
    end
    return false
end

local function ShouldKeep(hero, ability)
    local name = ability:GetAbilityName()
    if OSC_KEEP_ABILITIES[name] or IsHeroExtra(hero, name) then
        return true
    end
    if string.sub(name, 1, 14) == "special_bonus_" then
        return true
    end
    return IsInnateAbility(ability)
end

-- Иллюзия, Tempest Double или клон (Meepo): копирует способности владельца
function OSC_Abilities.IsCopy(unit)
    return (unit.IsIllusion and unit:IsIllusion())
        or (unit.IsTempestDouble and unit:IsTempestDouble())
        or (unit.IsClone and unit:IsClone())
        or false
end

function OSC_Abilities.StripHero(hero)
    -- Сначала собираем имена, потом удаляем, чтобы не сбить индексы
    local toRemove = {}
    for i = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(i)
        if ability and not ShouldKeep(hero, ability) then
            table.insert(toRemove, ability:GetAbilityName())
        end
    end

    for _, name in ipairs(toRemove) do
        hero:RemoveAbility(name)
    end
end

-- Выдаёт герою его способности из OSC_HERO_EXTRA_ABILITIES (казино Огра)
function OSC_Abilities.GrantHeroExtras(hero)
    for _, name in ipairs(HeroExtras(hero)) do
        local ability = hero:FindAbilityByName(name) or hero:AddAbility(name)
        if not ability then
            error("[OSC] Failed to add hero ability " .. name)
        end
        if ability:GetLevel() < 1 then
            ability:SetLevel(1)
        end
        ability:SetHidden(false)
    end
end

-- ================= Пулы =================

local function IsValidWeight(weight)
    return weight == nil
        or (type(weight) == "number" and weight > 0 and weight == math.floor(weight))
end

local function FindEntry(name)
    if not name then return nil end
    for _, pool in ipairs({ OSC_ABILITY_POOL or {}, OSC_ULTIMATE_POOL or {} }) do
        for _, entry in ipairs(pool) do
            if entry.name == name then
                return entry
            end
        end
    end
end

-- Убирает из пулов способности, которых нет в KV (например, после патча Dota)
-- или с неверным весом, а из linked — отсутствующие подспособности.
-- Возвращает, сколько записей и подспособностей убрано.
function OSC_Abilities.ValidatePools()
    local removed = 0
    local pools = {
        { name = "OSC_ABILITY_POOL", list = OSC_ABILITY_POOL },
        { name = "OSC_ULTIMATE_POOL", list = OSC_ULTIMATE_POOL },
    }

    for _, pool in ipairs(pools) do
        local reasons, invalidCount = {}, 0
        for index, entry in ipairs(pool.list) do
            if not GetAbilityKeyValuesByName(entry.name) then
                reasons[index] = "ability not found"
            elseif not IsValidWeight(entry.weight) then
                reasons[index] = "invalid weight " .. tostring(entry.weight)
            end
            if reasons[index] then
                invalidCount = invalidCount + 1
            end
        end

        -- Если не прошла ни одна запись, скорее сломана сама проверка, чем пул:
        -- пустой пул остановил бы режим, поэтому оставляем его как есть
        local skip = #pool.list > 0 and invalidCount == #pool.list
        if skip then
            OSC_Logger.Error(pool.name .. ": validation skipped, no entry passed the KV check")
        end

        for index = #pool.list, 1, -1 do
            local entry = pool.list[index]
            local reason = not skip and reasons[index]
            if reason then
                OSC_Logger.Error(pool.name .. ": removed " .. tostring(entry.name)
                    .. " (" .. reason .. ")")
                table.remove(pool.list, index)
                removed = removed + 1
            elseif not skip then
                local linked = entry.linked or {}
                for linkIndex = #linked, 1, -1 do
                    local link = linked[linkIndex]
                    if not GetAbilityKeyValuesByName(link.name) then
                        OSC_Logger.Error(pool.name .. ": removed linked " .. tostring(link.name)
                            .. " of " .. entry.name .. " (ability not found)")
                        table.remove(linked, linkIndex)
                        removed = removed + 1
                    end
                end
            end
        end

        if #pool.list == 0 then
            OSC_Logger.Error(pool.name .. " is empty")
        end
    end

    return removed
end

local function PickRandomFromPool(pool, excludeName, isAllowed)
    local candidates = {}
    local totalWeight = 0

    local function GetWeight(entry)
        local weight = entry.weight == nil and 4 or entry.weight
        if not IsValidWeight(weight) then
            error("[OSC] Invalid weight for ability: " .. tostring(entry.name))
        end
        return weight
    end

    for _, entry in ipairs(pool) do
        if entry.name ~= excludeName and (not isAllowed or isAllowed(entry)) then
            table.insert(candidates, entry)
            totalWeight = totalWeight + GetWeight(entry)
        end
    end

    if #candidates == 0 then
        if isAllowed then
            error("[OSC] No eligible abilities in pool")
        end
        candidates = pool
        for _, entry in ipairs(candidates) do
            totalWeight = totalWeight + GetWeight(entry)
        end
    end

    if totalWeight == 0 then
        error("[OSC] Ability pool is empty")
    end

    local roll = RandomInt(1, totalWeight)
    for _, entry in ipairs(candidates) do
        roll = roll - GetWeight(entry)
        if roll <= 0 then
            return entry
        end
    end
end

function OSC_Abilities.PickRandom(excludeName)
    return PickRandomFromPool(OSC_ABILITY_POOL, excludeName)
end

local function GetAlliedUltimateCount(hero, abilityName)
    local count = 0
    local team = hero:GetTeamNumber()

    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            local teammate = PlayerResource:GetSelectedHeroEntity(playerID)
            if teammate and teammate ~= hero and teammate:GetTeamNumber() == team
                and teammate.osc_current_ultimate == abilityName then
                count = count + 1
            end
        end
    end

    return count
end

function OSC_Abilities.PickRandomUltimate(excludeName, hero)
    local maxDuplicates = OSC_CONFIG.MAX_DUPLICATE_ULTIMATES_PER_TEAM
    if type(maxDuplicates) ~= "number" or maxDuplicates < 1 then
        error("[OSC] MAX_DUPLICATE_ULTIMATES_PER_TEAM must be at least 1")
    end

    return PickRandomFromPool(OSC_ULTIMATE_POOL, excludeName, function(entry)
        return GetAlliedUltimateCount(hero, entry.name) < maxDuplicates
    end)
end

function OSC_Abilities.CalcLevel(heroLevel, ability)
    local target
    if ability:GetAbilityType() == ABILITY_TYPE_ULTIMATE then
        if heroLevel >= 18 then
            target = 3
        elseif heroLevel >= 12 then
            target = 2
        else
            target = 1
        end
    else
        target = math.ceil(heroLevel / 2)
    end

    return math.max(1, math.min(ability:GetMaxLevel(), target))
end

-- ================= Выдача и удаление =================

local function RemoveNow(unit, ability)
    if ability:IsNull() then return end
    if ability:IsChanneling() then
        unit:InterruptChannel()
    end
    -- Включённый тоггл оставил бы свой эффект на герое
    if ability:GetToggleState() then
        ability:ToggleAbility()
    end
    unit:RemoveAbilityByHandle(ability)
end

-- Снимает способность с панели. Пассивку удаляем сразу: скрытая, она
-- продолжала бы работать. Активную прячем и удаляем позже — её снаряды и
-- эффекты (Illusory Orb, Static Remnant) без живой способности не доигрывают
-- и остаются висеть на карте. Начатый ченнел при этом не обрывается.
local function RetireAbility(unit, ability)
    if ability:IsPassive() then
        RemoveNow(unit, ability)
        return
    end

    if ability:GetToggleState() then
        ability:ToggleAbility()
    end
    ability:SetHidden(true)
    ability.osc_retired = true
    unit:SetContextThink(DoUniqueString("osc_retire_ability"), function()
        if not unit:IsNull() then
            RemoveNow(unit, ability)
        end
        return nil
    end, OSC_CONFIG.ROTATION_OLD_ABILITY_LIFETIME)
end

-- Снимает подспособности записи (Ethereal Jaunt и т. п.)
local function RetireLinked(unit, name)
    local entry = FindEntry(name)
    for _, link in ipairs(entry and entry.linked or {}) do
        local sub = unit:FindAbilityByName(link.name)
        if sub and not sub.osc_retired then
            RetireAbility(unit, sub)
        end
    end
end

-- Если та же способность ещё ждёт удаления после прошлой смены, убираем её
-- сразу, чтобы у героя не оказалось двух одинаковых
local function ClearRetired(unit, name)
    local ability = unit:FindAbilityByName(name)
    if ability and ability.osc_retired then
        RemoveNow(unit, ability)
    end
end

local function LinkedLevel(sub, level)
    return math.max(1, math.min(sub:GetMaxLevel(), level))
end

-- Настраивает уже добавленную способность записи и выдаёт её связанные
-- подспособности (например, Ethereal Jaunt к Illusory Orb)
local function PlaceEntry(unit, entry, ability, level)
    ability:SetLevel(level)
    ability:SetHidden(false)

    for _, link in ipairs(entry.linked or {}) do
        local sub = unit:FindAbilityByName(link.name) or unit:AddAbility(link.name)
        if sub then
            sub:SetLevel(LinkedLevel(sub, level))
            sub:SetHidden(link.hidden == true)
        else
            OSC_Logger.Error("Failed to add linked ability " .. link.name .. " for " .. entry.name)
        end
    end
end

-- Новая способность добавляется до снятия старой (если движок её не выдал,
-- у героя остаётся прежняя) и через SwapAbilities встаёт в слот старой
local function SwapEntry(hero, field, entry)
    ClearRetired(hero, entry.name)
    for _, link in ipairs(entry.linked or {}) do
        ClearRetired(hero, link.name)
    end

    local ability = hero:AddAbility(entry.name)
    if not ability then
        OSC_Logger.Error("Failed to add ability: " .. entry.name)
        return false
    end

    local oldName = hero[field]
    local old = oldName and hero:FindAbilityByName(oldName)
    if old then
        hero:SwapAbilities(oldName, entry.name, false, true)
        RetireAbility(hero, old)
    end
    RetireLinked(hero, oldName)

    PlaceEntry(hero, entry, ability, OSC_Abilities.CalcLevel(hero:GetLevel(), ability))
    ability:EndCooldown()
    hero[field] = entry.name
    return true
end

-- Повышает уровень способности и её связанных подспособностей (не понижает)
function OSC_Abilities.SetEntryLevel(hero, name, level)
    local ability = name and hero:FindAbilityByName(name)
    if not ability then return end

    local newLevel = math.max(ability:GetLevel(), level)
    ability:SetLevel(newLevel)

    local entry = FindEntry(name)
    for _, link in ipairs(entry and entry.linked or {}) do
        local sub = hero:FindAbilityByName(link.name)
        if sub then
            sub:SetLevel(math.max(sub:GetLevel(), LinkedLevel(sub, newLevel)))
        end
    end
end

local function CopyEntry(unit, owner, name)
    if not name then return nil end

    local ability = unit:AddAbility(name)
    if not ability then
        OSC_Logger.Error("Failed to copy ability: " .. name)
        return nil
    end

    local source = owner:FindAbilityByName(name)
    PlaceEntry(unit, FindEntry(name) or { name = name }, ability,
        source and source:GetLevel() or 1)
    return name
end

function OSC_Abilities.CopyFromOwner(unit, owner)
    OSC_Abilities.StripHero(unit)
    unit.osc_current_ability = CopyEntry(unit, owner, owner.osc_current_ability)
    unit.osc_current_ultimate = CopyEntry(unit, owner, owner.osc_current_ultimate)
end

local function HasAbility(unit, name)
    return name == nil or unit:FindAbilityByName(name) ~= nil
end

-- Копия с теми же способностями только догоняет уровни: пересоздание
-- сбросило бы её перезарядки (клоны Meepo живут всю игру)
local function SyncCopy(unit, owner)
    local mainName, ultimateName = owner.osc_current_ability, owner.osc_current_ultimate
    local unchanged = unit.osc_current_ability == mainName
        and unit.osc_current_ultimate == ultimateName
        and HasAbility(unit, mainName)
        and HasAbility(unit, ultimateName)
    if not unchanged then
        OSC_Abilities.CopyFromOwner(unit, owner)
        return
    end

    for _, name in pairs({ mainName, ultimateName }) do
        local source = owner:FindAbilityByName(name)
        if source then
            OSC_Abilities.SetEntryLevel(unit, name, source:GetLevel())
        end
    end
end

-- Обновляет живые копии владельца (клоны Meepo, иллюзии, Tempest Double).
-- Иллюзии чужих героев под контролем игрока (Wall of Replica) не трогаем.
function OSC_Abilities.SyncCopies(owner)
    if not owner or owner:IsNull() or OSC_Abilities.IsCopy(owner) then return end

    local playerID = owner:GetPlayerOwnerID()
    local unitName = owner:GetUnitName()
    for _, unit in pairs(HeroList:GetAllHeroes() or {}) do
        if unit ~= owner and not unit:IsNull()
            and OSC_Abilities.IsCopy(unit)
            and unit:GetPlayerOwnerID() == playerID
            and unit:GetUnitName() == unitName then
            local ok, err = pcall(SyncCopy, unit, owner)
            if not ok then
                OSC_Logger.Error("Copy sync failed for " .. unitName .. ": " .. tostring(err))
            end
        end
    end
end

function OSC_Abilities.GiveRandomUltimate(hero, notify)
    local entry = OSC_Abilities.PickRandomUltimate(hero.osc_current_ultimate, hero)
    if not SwapEntry(hero, "osc_current_ultimate", entry) then
        return nil
    end

    if notify then
        OSC_Notifications.AbilityChanged(hero, entry)
    end
    OSC_Abilities.SyncCopies(hero)
    return entry
end

function OSC_Abilities.GiveRandom(hero, notify)
    local entry = OSC_Abilities.PickRandom(hero.osc_current_ability)
    if not SwapEntry(hero, "osc_current_ability", entry) then
        return nil
    end

    if notify then
        OSC_Notifications.AbilityChanged(hero, entry)
    end
    OSC_Abilities.SyncCopies(hero)
    return entry
end
