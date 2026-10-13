-- Выбор способностей: пулы, их проверка и случайный выбор записей для героя
-- по правилам режима. Сам ничего герою не выдаёт — это делает OSC_Abilities,
-- он же сообщает о выданной записи через Remember.
--
-- Правила отбора кандидатов для слота героя:
--   жёсткие — ультимейт не чаще MAX_DUPLICATE_ULTIMATES_PER_TEAM у союзников;
--   обычные — не текущая способность слота;
--   мягкие — серия тегов (MAX_SAME_TAG_STREAK): ослабляется, если
--     кандидатов не хватает.

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

local function KnownTags()
    local known = {}
    for _, tag in ipairs(OSC_ABILITY_TAGS or {}) do
        known[tag] = true
    end
    return known
end

-- Причина, по которой теги записи неверны, или nil
local function InvalidTagsReason(entry, known)
    local tags = entry.tags
    if type(tags) ~= "table" or #tags == 0 then
        return "no tags"
    end
    local seen = {}
    for _, tag in ipairs(tags) do
        if not known[tag] then
            return "unknown tag " .. tostring(tag)
        end
        if seen[tag] then
            return "duplicate tag " .. tag
        end
        seen[tag] = true
    end
    return nil
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

-- Убирает из пулов способности, которых нет в KV (например, после патча Dota),
-- с неверным весом или тегами (нет тегов, тег не из OSC_ABILITY_TAGS,
-- повтор), а из linked — отсутствующие подспособности.
-- Возвращает, сколько записей и подспособностей убрано.
function OSC_AbilitySelection.ValidatePools()
    local removed = 0
    local pools = {
        { name = "OSC_ABILITY_POOL", list = OSC_ABILITY_POOL },
        { name = "OSC_ULTIMATE_POOL", list = OSC_ULTIMATE_POOL },
    }

    local knownTags = KnownTags()

    for _, pool in ipairs(pools) do
        local reasons, invalidCount = {}, 0
        for index, entry in ipairs(pool.list) do
            local tagsReason = InvalidTagsReason(entry, knownTags)
            if not GetAbilityKeyValuesByName(entry.name) then
                reasons[index] = "ability not found"
            elseif not IsValidWeight(entry.weight) then
                reasons[index] = "invalid weight " .. tostring(entry.weight)
            elseif tagsReason then
                reasons[index] = "invalid tags: " .. tagsReason
            end
            if reasons[index] then
                invalidCount = invalidCount + 1
            end
        end

        -- Если не прошла ни одна запись, скорее сломана сама проверка, чем пул:
        -- пустой пул остановил бы режим, поэтому оставляем его как есть
        local skip = #pool.list > 0 and invalidCount == #pool.list
        if skip then
            OSC_Logger.Error(pool.name .. ": validation skipped, no entry passed the check")
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

-- ================= Серия тегов =================

local function StreakLimit()
    if OSC_CONFIG.ABILITY_TAG_STREAK_ENABLED ~= true then
        return nil
    end
    local limit = OSC_CONFIG.MAX_SAME_TAG_STREAK
    if type(limit) ~= "number" or limit < 1 or limit ~= math.floor(limit) then
        OSC_Logger.Error("MAX_SAME_TAG_STREAK must be a positive integer, got " .. tostring(limit))
        return nil
    end
    return limit
end

local function HasTag(tags, tag)
    for _, current in ipairs(tags or {}) do
        if current == tag then
            return true
        end
    end
    return false
end

-- Теги, которые уже limit раз подряд были у способностей слота: следующая
-- способность с любым из них продлила бы серию сверх лимита
local function ExhaustedTags(hero, slot, limit)
    local history = OSC_HeroState.Get(hero).recent_tags[slot] or {}
    local exhausted = {}
    if #history < limit then
        return exhausted
    end
    for _, tag in ipairs(history[#history]) do
        local streak = 0
        for index = #history, 1, -1 do
            if not HasTag(history[index], tag) then
                break
            end
            streak = streak + 1
        end
        if streak >= limit then
            exhausted[tag] = true
        end
    end
    return exhausted
end

-- Запись не продлевает ни одну исчерпанную серию
local function KeepsStreak(entry, exhausted)
    for _, tag in ipairs(entry.tags or {}) do
        if exhausted[tag] then
            return false
        end
    end
    return true
end

-- Запоминает теги записи, фактически выданной герою (вызывает OSC_Abilities)
function OSC_AbilitySelection.Remember(hero, slot, entry)
    local recent = OSC_HeroState.Get(hero).recent_tags
    local history = recent[slot] or {}
    recent[slot] = history

    local tags = {}
    for _, tag in ipairs(entry.tags or {}) do
        table.insert(tags, tag)
    end
    table.insert(history, tags)

    -- Для проверки серии нужны только последние MAX_SAME_TAG_STREAK записей
    local keep = OSC_CONFIG.MAX_SAME_TAG_STREAK
    keep = type(keep) == "number" and keep >= 1 and math.floor(keep) or 1
    while #history > keep do
        table.remove(history, 1)
    end
end

-- ================= Выбор =================

local function GetAlliedUltimateCount(hero, abilityName)
    local count = 0
    local team = hero:GetTeamNumber()

    -- Ультимейт, ожидающий конца фазы каста, тоже считается: через пару
    -- секунд он будет у союзника
    OSC_Heroes.ForEachPlayerHero(function(teammate)
        local state = OSC_HeroState.Peek(teammate)
        if teammate ~= hero and teammate:GetTeamNumber() == team and state then
            local pending = state.deferred and state.deferred.ultimate
            if state.ultimate == abilityName
                or (pending and pending.entry and pending.entry.name == abilityName) then
                count = count + 1
            end
        end
    end)

    return count
end

-- Ступени отбора от строгой к мягкой; каждая — фильтр записей пула
local function BuildTiers(hero, slot, exclude)
    local current = OSC_HeroState.Get(hero)[slot]

    local isAllowed = function() return true end
    if slot == "ultimate" then
        local maxDuplicates = OSC_CONFIG.MAX_DUPLICATE_ULTIMATES_PER_TEAM
        if type(maxDuplicates) ~= "number" or maxDuplicates < 1 then
            error("[OSC] MAX_DUPLICATE_ULTIMATES_PER_TEAM must be at least 1")
        end
        isAllowed = function(entry)
            return GetAlliedUltimateCount(hero, entry.name) < maxDuplicates
        end
    end

    local function Base(entry)
        return not exclude[entry.name] and entry.name ~= current and isAllowed(entry)
    end

    local tiers = {}
    local limit = StreakLimit()
    if limit then
        local exhausted = ExhaustedTags(hero, slot, limit)
        if next(exhausted) then
            table.insert(tiers, {
                name = "tag streak",
                accepts = function(entry) return Base(entry) and KeepsStreak(entry, exhausted) end,
            })
        end
    end
    table.insert(tiers, { name = "base", accepts = Base })
    -- Основной слот, где кроме текущей способности ничего нет, получает её
    -- же снова (пул из одной записи), но только если других кандидатов нет
    -- совсем; у ультимейта это ошибка
    if slot ~= "ultimate" then
        table.insert(tiers, {
            name = "whole pool",
            only_if_empty = true,
            accepts = function(entry) return not exclude[entry.name] end,
        })
    end
    return tiers
end

-- Индекс случайной записи с учётом весов
local function PickWeighted(candidates)
    local totalWeight = 0
    for _, entry in ipairs(candidates) do
        totalWeight = totalWeight + GetWeight(entry)
    end
    if totalWeight == 0 then
        return nil
    end

    local roll = RandomInt(1, totalWeight)
    for index, entry in ipairs(candidates) do
        roll = roll - GetWeight(entry)
        if roll <= 0 then
            return index
        end
    end
end

-- До count разных записей пула для слота героя ("ability" или "ultimate")
-- по правилам режима, взвешенный выбор без повторов. Сначала берутся
-- кандидаты самой строгой ступени, недостающие — из следующих: так
-- ослабляется правило серии тегов. opts.exclude — имена, которые не
-- предлагать (например, уже показанные игроку).
-- Ошибка, если не нашлось ни одной записи.
function OSC_AbilitySelection.PickCandidates(hero, slot, count, opts)
    opts = opts or {}
    local pool = OSC_AbilitySelection.GetPool(slot)
    local exclude = {}
    for _, name in ipairs(opts.exclude or {}) do
        exclude[name] = true
    end

    local chosen, chosenNames = {}, {}
    for tierIndex, tier in ipairs(BuildTiers(hero, slot, exclude)) do
        if #chosen >= count or (tier.only_if_empty and #chosen > 0) then
            break
        end
        local candidates = {}
        for _, entry in ipairs(pool) do
            if not chosenNames[entry.name] and tier.accepts(entry) then
                table.insert(candidates, entry)
            end
        end
        if tierIndex > 1 and #candidates > 0 then
            OSC_Logger.Log("Ability pick for " .. hero:GetUnitName() .. " (" .. slot
                .. ") relaxed to rule '" .. tier.name .. "'")
        end
        while #chosen < count and #candidates > 0 do
            local index = PickWeighted(candidates)
            if not index then
                break
            end
            local entry = table.remove(candidates, index)
            chosenNames[entry.name] = true
            table.insert(chosen, entry)
        end
    end

    if #chosen == 0 then
        error("[OSC] No eligible abilities in pool for slot " .. tostring(slot))
    end
    return chosen
end

-- Одна случайная запись пула для слота героя по правилам режима
function OSC_AbilitySelection.Pick(hero, slot)
    return OSC_AbilitySelection.PickCandidates(hero, slot, 1)[1]
end
