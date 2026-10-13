OSC_Abilities = {}

local MAIN_SLOT = 0
local ULTIMATE_SLOT = 5
-- Слоты для связанных подспособностей: между казино Огра (1) и ультимейтом (5)
local LINKED_SLOTS = { 2, 3, 4 }

local function IsInnateAbility(ability)
    local abilityData = GetAbilityKeyValuesByName(ability:GetAbilityName())
    return abilityData and (
        abilityData.Innate == "1"
        or abilityData.Innate == 1
        or abilityData.Innate == true
    )
end

local function ShouldKeep(ability)
    local name = ability:GetAbilityName()
    if OSC_KEEP_ABILITIES[name] then
        return true
    end
    if string.sub(name, 1, 14) == "special_bonus_" then
        return true
    end
    return IsInnateAbility(ability)
end

local SCEPTER_ABILITY = "ogre_magi_unrefined_fireblast"

local function PreserveScepterAbilitySlot(hero, preferredIndex)
    local scepterAbility = hero:FindAbilityByName(SCEPTER_ABILITY)
    if not scepterAbility or hero:GetAbilityByIndex(preferredIndex) ~= scepterAbility then
        return
    end

    local lastVisibleIndex = math.min(hero:GetAbilityCount() - 1, 5)
    for index = 0, lastVisibleIndex do
        if index ~= preferredIndex and not hero:GetAbilityByIndex(index) then
            scepterAbility:SetAbilityIndex(index)
            return
        end
    end

    error("[OSC] No free ability slot to preserve " .. SCEPTER_ABILITY)
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
        if ability and not ShouldKeep(ability) then
            table.insert(toRemove, ability:GetAbilityName())
        end
    end

    for _, name in ipairs(toRemove) do
        hero:RemoveAbility(name)
    end
end

function OSC_Abilities.EnsureOgreCasinoAbility(hero)
    if hero:GetUnitName() ~= "npc_dota_hero_ogre_magi" then return end

    local ability = hero:FindAbilityByName("ogre_magi_casino")
    if not ability then
        ability = hero:AddAbility("ogre_magi_casino")
    end
    if not ability then
        error("[OSC] Failed to add Ogre casino ability")
    end

    ability:SetAbilityIndex(1)
    ability:SetLevel(1)
    ability:SetHidden(false)
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
        for index = #pool.list, 1, -1 do
            local entry = pool.list[index]
            local reason
            if not GetAbilityKeyValuesByName(entry.name) then
                reason = "ability not found"
            elseif not IsValidWeight(entry.weight) then
                reason = "invalid weight " .. tostring(entry.weight)
            end

            if reason then
                OSC_Logger.Error(pool.name .. ": removed " .. tostring(entry.name)
                    .. " (" .. reason .. ")")
                table.remove(pool.list, index)
                removed = removed + 1
            else
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
            OSC_Logger.Error(pool.name .. " is empty after validation")
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

local function RemoveAbilityHandle(unit, ability)
    if ability:IsChanneling() then
        unit:InterruptChannel()
    end
    -- Включённый тоггл оставил бы свой эффект на герое
    if ability:GetToggleState() then
        ability:ToggleAbility()
    end
    unit:RemoveAbilityByHandle(ability)
end

-- Убирает способность и её связанные подспособности
local function RemoveEntryAbilities(unit, name)
    if not name then return end

    local ability = unit:FindAbilityByName(name)
    if ability then
        RemoveAbilityHandle(unit, ability)
    end

    local entry = FindEntry(name)
    for _, link in ipairs(entry and entry.linked or {}) do
        local sub = unit:FindAbilityByName(link.name)
        if sub then
            RemoveAbilityHandle(unit, sub)
        end
    end
end

local function LinkedLevel(sub, level)
    return math.max(1, math.min(sub:GetMaxLevel(), level))
end

local function FindFreeSlot(unit, slots)
    for _, index in ipairs(slots) do
        if index < unit:GetAbilityCount() and not unit:GetAbilityByIndex(index) then
            return index
        end
    end
end

-- Ставит уже добавленную способность записи в слот и выдаёт её связанные
-- подспособности (например, Ethereal Jaunt к Illusory Orb)
local function PlaceEntry(unit, entry, ability, slot, level)
    PreserveScepterAbilitySlot(unit, slot)
    ability:SetAbilityIndex(slot)
    ability:SetLevel(level)
    ability:SetHidden(false)

    for _, link in ipairs(entry.linked or {}) do
        local sub = unit:FindAbilityByName(link.name) or unit:AddAbility(link.name)
        if sub then
            local freeSlot = FindFreeSlot(unit, LINKED_SLOTS)
            if freeSlot then
                sub:SetAbilityIndex(freeSlot)
            end
            sub:SetLevel(LinkedLevel(sub, level))
            sub:SetHidden(link.hidden == true)
        else
            OSC_Logger.Error("Failed to add linked ability " .. link.name .. " for " .. entry.name)
        end
    end
end

-- Новая способность добавляется до удаления старой: если движок её не выдал,
-- у героя остаётся прежняя
local function SwapEntry(hero, field, entry, slot)
    local ability = hero:AddAbility(entry.name)
    if not ability then
        OSC_Logger.Error("Failed to add ability: " .. entry.name)
        return false
    end

    RemoveEntryAbilities(hero, hero[field])
    PlaceEntry(hero, entry, ability, slot, OSC_Abilities.CalcLevel(hero:GetLevel(), ability))
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

local function CopyEntry(unit, owner, name, slot)
    if not name then return nil end

    local ability = unit:AddAbility(name)
    if not ability then
        OSC_Logger.Error("Failed to copy ability: " .. name)
        return nil
    end

    local source = owner:FindAbilityByName(name)
    PlaceEntry(unit, FindEntry(name) or { name = name }, ability, slot,
        source and source:GetLevel() or 1)
    return name
end

function OSC_Abilities.CopyFromOwner(unit, owner)
    OSC_Abilities.StripHero(unit)
    unit.osc_current_ability = CopyEntry(unit, owner, owner.osc_current_ability, MAIN_SLOT)
    unit.osc_current_ultimate = CopyEntry(unit, owner, owner.osc_current_ultimate, ULTIMATE_SLOT)
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
            local ok, err = pcall(OSC_Abilities.CopyFromOwner, unit, owner)
            if not ok then
                OSC_Logger.Error("Copy sync failed for " .. unitName .. ": " .. tostring(err))
            end
        end
    end
end

function OSC_Abilities.GiveRandomUltimate(hero, notify)
    local entry = OSC_Abilities.PickRandomUltimate(hero.osc_current_ultimate, hero)
    if not SwapEntry(hero, "osc_current_ultimate", entry, ULTIMATE_SLOT) then
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
    if not SwapEntry(hero, "osc_current_ability", entry, MAIN_SLOT) then
        return nil
    end

    if notify then
        OSC_Notifications.AbilityChanged(hero, entry)
    end
    OSC_Abilities.SyncCopies(hero)
    return entry
end
