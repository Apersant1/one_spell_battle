-- Выбор способностей: пулы, их проверка и случайный выбор записи для героя.
-- Сам ничего герою не выдаёт — это делает OSC_Abilities.

require("osc/core/heroes")
require("osc/core/hero_state")

OSC_AbilitySelection = OSC_AbilitySelection or {}

local DEFAULT_WEIGHT = 4

-- Слоты способностей режима: поле состояния героя совпадает с именем слота
local SLOTS = {
    ability = function() return OSC_ABILITY_POOL or {} end,
    ultimate = function() return OSC_ULTIMATE_POOL or {} end,
}

function OSC_AbilitySelection.GetPool(slot)
    local pool = SLOTS[slot]
    if not pool then
        error("[OSC] Unknown ability slot: " .. tostring(slot))
    end
    return pool()
end

local function IsValidWeight(weight)
    return weight == nil
        or (type(weight) == "number" and weight > 0 and weight == math.floor(weight))
end

local function GetWeight(entry)
    local weight = entry.weight == nil and DEFAULT_WEIGHT or entry.weight
    if not IsValidWeight(weight) then
        error("[OSC] Invalid weight for ability: " .. tostring(entry.name))
    end
    return weight
end

-- Запись пула по имени способности (основной или ультимейта)
function OSC_AbilitySelection.FindEntry(name)
    if not name then return nil end
    for _, pool in ipairs({ OSC_ABILITY_POOL or {}, OSC_ULTIMATE_POOL or {} }) do
        for _, entry in ipairs(pool) do
            if entry.name == name then
                return entry
            end
        end
    end
end

-- ================= Проверка пулов =================

-- Убирает из пулов способности, которых нет в KV (например, после патча Dota)
-- или с неверным весом, а из linked — отсутствующие подспособности.
-- Возвращает, сколько записей и подспособностей убрано.
function OSC_AbilitySelection.ValidatePools()
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

-- ================= Выбор =================

local function PickRandomFromPool(pool, excludeName, isAllowed)
    local candidates = {}
    local totalWeight = 0

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

local function GetAlliedUltimateCount(hero, abilityName)
    local count = 0
    local team = hero:GetTeamNumber()

    OSC_Heroes.ForEachPlayerHero(function(teammate)
        local state = OSC_HeroState.Peek(teammate)
        if teammate ~= hero and teammate:GetTeamNumber() == team
            and state and state.ultimate == abilityName then
            count = count + 1
        end
    end)

    return count
end

-- Случайная запись пула для слота героя ("ability" или "ultimate"), кроме
-- текущей. Ультимейт ограничен числом таких же у союзников.
function OSC_AbilitySelection.Pick(hero, slot)
    local current = OSC_HeroState.Get(hero)[slot]
    local pool = OSC_AbilitySelection.GetPool(slot)
    if slot ~= "ultimate" then
        return PickRandomFromPool(pool, current)
    end

    local maxDuplicates = OSC_CONFIG.MAX_DUPLICATE_ULTIMATES_PER_TEAM
    if type(maxDuplicates) ~= "number" or maxDuplicates < 1 then
        error("[OSC] MAX_DUPLICATE_ULTIMATES_PER_TEAM must be at least 1")
    end
    return PickRandomFromPool(pool, current, function(entry)
        return GetAlliedUltimateCount(hero, entry.name) < maxDuplicates
    end)
end
