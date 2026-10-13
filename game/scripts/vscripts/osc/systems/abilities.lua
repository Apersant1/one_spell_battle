-- Выдача способностей: замена способности в слоте героя, отложенное
-- удаление старой, связанные подспособности, синхронизация копий героя.
-- Что выдавать, решает OSC_AbilitySelection.

require("osc/core/heroes")
require("osc/core/hero_state")
require("osc/systems/ability_selection")

OSC_Abilities = OSC_Abilities or {}

-- Слот способности на панели задают AddAbility (первый свободный слот) и
-- SwapAbilities; SetAbilityIndex в игре способности не переставляет.

local function FindEntry(name)
    return OSC_AbilitySelection.FindEntry(name)
end

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

-- Полная перезарядка способности на её текущем уровне с учётом снижения
-- перезарядки у героя — столько он ждал бы после каста
local function FullCooldown(ability)
    local levelIndex = ability:GetLevel() - 1
    if ability.GetEffectiveCooldown then
        return ability:GetEffectiveCooldown(levelIndex) or 0
    end
    return ability:GetCooldown(levelIndex) or 0
end

-- Перезарядка способности, пришедшей на смену прежней (NEW_ABILITY_COOLDOWN_MODE)
local function ApplyNewAbilityCooldown(ability)
    local mode = OSC_CONFIG.NEW_ABILITY_COOLDOWN_MODE or "ready"
    if mode == "ready" then return end
    if mode ~= "partial" then
        OSC_Logger.Error("Unknown NEW_ABILITY_COOLDOWN_MODE: " .. tostring(mode))
        return
    end

    local fraction = OSC_CONFIG.NEW_ABILITY_COOLDOWN_FRACTION
    if type(fraction) ~= "number" or fraction < 0 or fraction > 1 then
        OSC_Logger.Error("NEW_ABILITY_COOLDOWN_FRACTION must be between 0 and 1, got "
            .. tostring(fraction))
        return
    end

    local cooldown = FullCooldown(ability) * fraction
    if cooldown > 0 then
        ability:StartCooldown(cooldown)
    end
end

-- Новая способность добавляется до снятия старой (если движок её не выдал,
-- у героя остаётся прежняя) и через SwapAbilities встаёт в слот старой.
-- slot — "ability" или "ultimate" (поле состояния героя).
local function SwapEntry(hero, slot, entry)
    ClearRetired(hero, entry.name)
    for _, link in ipairs(entry.linked or {}) do
        ClearRetired(hero, link.name)
    end

    local ability = hero:AddAbility(entry.name)
    if not ability then
        OSC_Logger.Error("Failed to add ability: " .. entry.name)
        return false
    end

    local state = OSC_HeroState.Get(hero)
    local oldName = state[slot]
    local old = oldName and hero:FindAbilityByName(oldName)
    if old then
        hero:SwapAbilities(oldName, entry.name, false, true)
        RetireAbility(hero, old)
    end
    RetireLinked(hero, oldName)

    PlaceEntry(hero, entry, ability, OSC_Abilities.CalcLevel(hero:GetLevel(), ability))
    ability:EndCooldown()
    if oldName then
        ApplyNewAbilityCooldown(ability)
    end
    state[slot] = entry.name
    OSC_AbilitySelection.Remember(hero, slot, entry)
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
    -- Копия не получает готовую способность, пока у владельца она на
    -- перезарядке (в том числе частичной после смены)
    local remaining = source and source:GetCooldownTimeRemaining() or 0
    if remaining > 0 then
        ability:StartCooldown(remaining)
    end
    return name
end

function OSC_Abilities.CopyFromOwner(unit, owner)
    OSC_Abilities.StripHero(unit)
    local state, ownerState = OSC_HeroState.Get(unit), OSC_HeroState.Get(owner)
    state.ability = CopyEntry(unit, owner, ownerState.ability)
    state.ultimate = CopyEntry(unit, owner, ownerState.ultimate)
end

local function HasAbility(unit, name)
    return name == nil or unit:FindAbilityByName(name) ~= nil
end

-- Копия с теми же способностями только догоняет уровни: пересоздание
-- сбросило бы её перезарядки (клоны Meepo живут всю игру)
local function SyncCopy(unit, owner)
    local state, ownerState = OSC_HeroState.Get(unit), OSC_HeroState.Get(owner)
    local mainName, ultimateName = ownerState.ability, ownerState.ultimate
    local unchanged = state.ability == mainName
        and state.ultimate == ultimateName
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
    OSC_Heroes.ForEachCopy(owner, function(unit)
        local ok, err = pcall(SyncCopy, unit, owner)
        if not ok then
            OSC_Logger.Error("Copy sync failed for " .. owner:GetUnitName() .. ": " .. tostring(err))
        end
    end)
end

local function ApplyGive(hero, slot, entry, notify)
    if not SwapEntry(hero, slot, entry) then
        return nil
    end

    if notify then
        OSC_Notifications.AbilityChanged(hero, entry)
    end
    OSC_Abilities.SyncCopies(hero)
    return entry
end

-- Способность слота (или её подспособность) в фазе каста: скрытие или
-- удаление в этот момент может сорвать каст
local function IsInCastPhase(hero, slot)
    local name = OSC_HeroState.Get(hero)[slot]
    if not name then return false end

    local names = { name }
    local entry = FindEntry(name)
    for _, link in ipairs(entry and entry.linked or {}) do
        table.insert(names, link.name)
    end
    for _, abilityName in ipairs(names) do
        local ability = hero:FindAbilityByName(abilityName)
        if ability and ability.IsInAbilityPhase and ability:IsInAbilityPhase() then
            return true
        end
    end
    return false
end

local function CanDefer()
    return OSC_CONFIG.ROTATION_CAST_PHASE_DEFER == true
        and type(OSC_CONFIG.ROTATION_MAX_DEFER) == "number"
        and OSC_CONFIG.ROTATION_MAX_DEFER > 0
        and type(OSC_CONFIG.ROTATION_DEFER_STEP) == "number"
        and OSC_CONFIG.ROTATION_DEFER_STEP > 0
end

-- Шаг таймера отложенной замены (таймер на самом герое). Возвращает задержку
-- до следующей проверки или nil, когда замена выполнена или отменена.
function OSC_Abilities.ProcessDeferred(hero, slot)
    if hero:IsNull() then return nil end
    local state = OSC_HeroState.Get(hero)
    local pending = state.deferred[slot]
    if not pending then return nil end

    if IsInCastPhase(hero, slot) and GameRules:GetGameTime() < pending.deadline then
        return OSC_CONFIG.ROTATION_DEFER_STEP
    end

    state.deferred[slot] = nil
    local ok, err = pcall(ApplyGive, hero, slot, pending.entry, pending.notify)
    if not ok then
        OSC_Logger.Error("Deferred " .. slot .. " change failed for "
            .. hero:GetUnitName() .. ": " .. tostring(err))
    end
    return nil
end

-- Выдаёт основному герою запись пула в слот ("ability" или "ultimate"):
-- заменяет прежнюю способность слота, уведомляет и обновляет копии.
-- Если прежняя способность в фазе каста, замена (вместе с уведомлением и
-- копиями) откладывается до конца фазы, но не дольше ROTATION_MAX_DEFER.
-- Возвращает запись (в том числе отложенную) или nil, если движок не выдал
-- способность.
function OSC_Abilities.Give(hero, slot, entry, notify)
    OSC_AbilitySelection.GetPool(slot) -- неизвестный слот — ошибка
    local state = OSC_HeroState.Get(hero)

    -- Пока замена ждёт, новая запрошенная замена встаёт вместо неё;
    -- срок ожидания остаётся прежним
    local pending = state.deferred[slot]
    if pending then
        pending.entry = entry
        pending.notify = pending.notify or notify
        return entry
    end

    if CanDefer() and IsInCastPhase(hero, slot) then
        state.deferred[slot] = {
            entry = entry,
            notify = notify,
            deadline = GameRules:GetGameTime() + OSC_CONFIG.ROTATION_MAX_DEFER,
        }
        OSC_Logger.Log("Deferred " .. slot .. " change for " .. hero:GetUnitName()
            .. ": " .. tostring(state[slot]) .. " is in cast phase")
        hero:SetContextThink("osc_deferred_" .. slot, function()
            return OSC_Abilities.ProcessDeferred(hero, slot)
        end, OSC_CONFIG.ROTATION_DEFER_STEP)
        return entry
    end

    return ApplyGive(hero, slot, entry, notify)
end

function OSC_Abilities.GiveRandomUltimate(hero, notify)
    return OSC_Abilities.Give(hero, "ultimate", OSC_AbilitySelection.Pick(hero, "ultimate"), notify)
end

function OSC_Abilities.GiveRandom(hero, notify)
    return OSC_Abilities.Give(hero, "ability", OSC_AbilitySelection.Pick(hero, "ability"), notify)
end
