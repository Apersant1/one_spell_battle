-- Выдача способностей: замена способности в слоте героя, отложенное
-- удаление старой, связанные подспособности, синхронизация копий героя.
-- Что выдавать, решает OSC_AbilitySelection.

require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/game_events")
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

-- Запись OSC_HERO_EXTRA_ABILITIES: имя или { name, enabled_by }
local function ExtraName(extra)
    return type(extra) == "table" and extra.name or extra
end

local function IsExtraEnabled(extra)
    return type(extra) ~= "table" or extra.enabled_by == nil
        or OSC_Config.Get(extra.enabled_by) == true
end

local function IsHeroExtra(hero, name)
    for _, extra in ipairs(HeroExtras(hero)) do
        if ExtraName(extra) == name then
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

-- Выдаёт герою его способности из OSC_HERO_EXTRA_ABILITIES (казино Огра);
-- см. SyncHeroExtras ниже
function OSC_Abilities.GrantHeroExtras(hero)
    return OSC_Abilities.SyncHeroExtras(hero)
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
    end, OSC_Config.Get("ROTATION_OLD_ABILITY_LIFETIME"))
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

-- Приводит собственные способности героя (OSC_HERO_EXTRA_ABILITIES) к
-- флагам конфига с учётом переопределений: недостающие включённые выдаёт,
-- выключенные снимает через RetireAbility. Выданная позже встаёт сразу за
-- основной способностью (казино — на W), как при инициализации: слот
-- задаёт SwapAbilities, SetAbilityIndex в игре не работает.
function OSC_Abilities.SyncHeroExtras(hero)
    local state = OSC_HeroState.Get(hero)
    local main = state.ability and hero:FindAbilityByName(state.ability)
    local mainIndex = main and main:GetAbilityIndex() or nil
    local position = 0

    for _, extra in ipairs(HeroExtras(hero)) do
        local name = ExtraName(extra)
        local ability = hero:FindAbilityByName(name)
        if IsExtraEnabled(extra) then
            position = position + 1
            if not ability or ability.osc_retired then
                ClearRetired(hero, name)
                ability = hero:AddAbility(name)
                if not ability then
                    error("[OSC] Failed to add hero ability " .. name)
                end
                local wanted = mainIndex and hero:GetAbilityByIndex(mainIndex + position)
                if wanted and wanted ~= ability then
                    hero:SwapAbilities(wanted:GetAbilityName(), name, not wanted:IsHidden(), true)
                end
            end
            if ability:GetLevel() < 1 then
                ability:SetLevel(1)
            end
            ability:SetHidden(false)
        elseif ability and not ability.osc_retired then
            RetireAbility(hero, ability)
        end
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
    local mode = OSC_Config.Get("NEW_ABILITY_COOLDOWN_MODE")
    if mode == "ready" then return end
    if mode ~= "partial" then
        OSC_Logger.Error("Unknown NEW_ABILITY_COOLDOWN_MODE: " .. tostring(mode))
        return
    end

    local fraction = OSC_Config.Get("NEW_ABILITY_COOLDOWN_FRACTION")
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

-- ================= Отсрочка на время фазы каста =================

local function CanDefer()
    return OSC_Config.Get("ROTATION_CAST_PHASE_DEFER") == true
        and type(OSC_Config.Get("ROTATION_MAX_DEFER")) == "number"
        and OSC_Config.Get("ROTATION_MAX_DEFER") > 0
        and type(OSC_Config.Get("ROTATION_DEFER_STEP")) == "number"
        and OSC_Config.Get("ROTATION_DEFER_STEP") > 0
end

-- Способность слота юнита (или её подспособность) в фазе каста: скрытие или
-- удаление в этот момент может сорвать каст
local function IsInCastPhase(unit, slot)
    local name = OSC_HeroState.Get(unit)[slot]
    if not name then return false end

    local names = { name }
    local entry = FindEntry(name)
    for _, link in ipairs(entry and entry.linked or {}) do
        table.insert(names, link.name)
    end
    for _, abilityName in ipairs(names) do
        local ability = unit:FindAbilityByName(abilityName)
        if ability and ability.IsInAbilityPhase and ability:IsInAbilityPhase() then
            return true
        end
    end
    return false
end

local function Now()
    return GameRules:GetGameTime()
end

-- Ставит отложенную замену слота юнита; thinkFn(unit, slot) — шаг таймера
local function Defer(unit, slot, pending, thinkName)
    pending.deadline = Now() + OSC_Config.Get("ROTATION_MAX_DEFER")
    OSC_HeroState.Get(unit).deferred[slot] = pending
    OSC_Logger.Log("Deferred " .. slot .. " change for " .. unit:GetUnitName()
        .. ": " .. tostring(OSC_HeroState.Get(unit)[slot]) .. " is in cast phase")
    unit:SetContextThink("osc_deferred_" .. slot, function()
        return OSC_Abilities[thinkName](unit, slot)
    end, OSC_Config.Get("ROTATION_DEFER_STEP"))
end

-- ================= Замена в слоте =================

-- Новая способность добавляется до снятия старой (если движок её не выдал,
-- у юнита остаётся прежняя) и через SwapAbilities встаёт в слот старой;
-- старая снимается через RetireAbility. slot — "ability" или "ultimate"
-- (поле состояния). levelOf(ability) — уровень новой способности.
-- Возвращает новую способность и имя прежней или nil.
local function SwapEntry(unit, slot, entry, levelOf)
    ClearRetired(unit, entry.name)
    for _, link in ipairs(entry.linked or {}) do
        ClearRetired(unit, link.name)
    end

    local ability = unit:AddAbility(entry.name)
    if not ability then
        OSC_Logger.Error("Failed to add ability: " .. entry.name)
        return nil
    end

    local state = OSC_HeroState.Get(unit)
    local oldName = state[slot]
    local old = oldName and unit:FindAbilityByName(oldName)
    if old and old ~= ability then
        unit:SwapAbilities(oldName, entry.name, false, true)
        RetireAbility(unit, old)
    end
    RetireLinked(unit, oldName)

    PlaceEntry(unit, entry, ability, levelOf(ability))
    ability:EndCooldown()
    state[slot] = entry.name
    return ability, oldName
end

-- Замена у основного героя: уровень по уровню героя, перезарядка по
-- NEW_ABILITY_COOLDOWN_MODE (только если была прежняя), теги в историю
local function SwapOwnerEntry(hero, slot, entry)
    local ability, oldName = SwapEntry(hero, slot, entry, function(added)
        return OSC_Abilities.CalcLevel(hero:GetLevel(), added)
    end)
    if not ability then
        return false
    end
    if oldName then
        ApplyNewAbilityCooldown(ability)
    end
    OSC_AbilitySelection.Remember(hero, slot, entry)
    return true, oldName
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

-- ================= Копии =================

-- В режиме partial копия получает способность с оставшейся перезарядкой
-- владельца, иначе у клона был бы бесплатный каст. В режиме ready копия,
-- как и раньше, получает способность готовой.
local function InheritCooldown(ability, source)
    if OSC_Config.Get("NEW_ABILITY_COOLDOWN_MODE") ~= "partial" then return end
    local remaining = source and source:GetCooldownTimeRemaining() or 0
    if remaining > 0 then
        ability:StartCooldown(remaining)
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
    InheritCooldown(ability, source)
    return name
end

-- Полное копирование при появлении копии: у неё ещё нет кастов режима
function OSC_Abilities.CopyFromOwner(unit, owner)
    OSC_Abilities.StripHero(unit)
    local state, ownerState = OSC_HeroState.Get(unit), OSC_HeroState.Get(owner)
    state.ability = CopyEntry(unit, owner, ownerState.ability)
    state.ultimate = CopyEntry(unit, owner, ownerState.ultimate)
end

local function HasAbility(unit, name)
    return name == nil or unit:FindAbilityByName(name) ~= nil
end

-- Ставит копии способность слота владельца так же, как герою: в слот
-- прежней, прежняя доживает скрытой (RetireAbility)
local function SwapCopyEntry(unit, owner, slot)
    local state = OSC_HeroState.Get(unit)
    local name = OSC_HeroState.Get(owner)[slot]
    if not name then
        local oldName = state[slot]
        local old = oldName and unit:FindAbilityByName(oldName)
        if old then
            RetireAbility(unit, old)
        end
        RetireLinked(unit, oldName)
        state[slot] = nil
        return
    end

    local source = owner:FindAbilityByName(name)
    local ability = SwapEntry(unit, slot, FindEntry(name) or { name = name }, function()
        return source and source:GetLevel() or 1
    end)
    if ability then
        InheritCooldown(ability, source)
    end
end

-- Слот копии догоняет владельца. Та же способность — только уровни
-- (пересоздание сбросило бы перезарядки: клоны Meepo живут всю игру).
-- Другая — замена; если способность копии в фазе каста, замена этой копии
-- откладывается так же, как у героя. force — срок ожидания вышел.
local function SyncCopySlot(unit, owner, slot, force)
    local state = OSC_HeroState.Get(unit)
    local name = OSC_HeroState.Get(owner)[slot]
    -- Нужная способность уже есть у копии (например, движок скопировал её
    -- сам) — запоминаем её, а не добавляем вторую
    local existing = name and unit:FindAbilityByName(name)
    if existing and not existing.osc_retired and state[slot] ~= name then
        local oldName = state[slot]
        local old = oldName and unit:FindAbilityByName(oldName)
        if old then
            RetireAbility(unit, old)
        end
        RetireLinked(unit, oldName)
        state[slot] = name
    end
    if state[slot] == name and HasAbility(unit, name) then
        local source = name and owner:FindAbilityByName(name)
        if source then
            OSC_Abilities.SetEntryLevel(unit, name, source:GetLevel())
        end
        return
    end

    local pending = state.deferred[slot]
    if pending and not force then
        -- Ожидающая замена возьмёт актуальную способность владельца сама;
        -- если её таймер пропал, срок всё равно ограничен
        if Now() < pending.deadline then
            return
        end
        force = true
    end
    state.deferred[slot] = nil

    if not force and CanDefer() and IsInCastPhase(unit, slot) then
        Defer(unit, slot, { copy = true }, "ProcessCopyDeferred")
        return
    end
    SwapCopyEntry(unit, owner, slot)
end

-- Шаг таймера отложенной замены у копии
function OSC_Abilities.ProcessCopyDeferred(unit, slot)
    if unit:IsNull() then return nil end
    local state = OSC_HeroState.Get(unit)
    local pending = state.deferred[slot]
    if not pending then return nil end

    if IsInCastPhase(unit, slot) and Now() < pending.deadline then
        return OSC_Config.Get("ROTATION_DEFER_STEP")
    end

    state.deferred[slot] = nil
    local owner = OSC_Heroes.GetCopyOwner(unit)
    if owner then
        local ok, err = pcall(SyncCopySlot, unit, owner, slot, true)
        if not ok then
            OSC_Logger.Error("Deferred copy sync failed for " .. unit:GetUnitName() .. ": " .. tostring(err))
        end
    end
    return nil
end

local function SyncCopy(unit, owner)
    SyncCopySlot(unit, owner, "ability")
    SyncCopySlot(unit, owner, "ultimate")
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

-- ================= Выдача основному герою =================

local function ApplyGive(hero, slot, entry, notify)
    local ok, previous = SwapOwnerEntry(hero, slot, entry)
    if not ok then
        return nil
    end

    -- Здесь же проходит и отложенная выдача (ProcessDeferred): объявление
    -- уходит в момент фактической смены, один раз
    if notify then
        local rarity = OSC_AbilitySelection.GetRarity(entry)
        OSC_Notifications.AbilityChanged(hero, entry, rarity)
        if rarity == "legendary" then
            OSC_Notifications.LegendaryAbility(hero, entry)
        end
    end
    OSC_Abilities.SyncCopies(hero)
    OSC_GameEvents.Emit("ability_changed", {
        hero = hero,
        player_id = hero:GetPlayerOwnerID(),
        slot = slot,
        ability = entry.name,
        previous = previous,
    })
    return entry
end

-- Шаг таймера отложенной замены (таймер на самом герое). Возвращает задержку
-- до следующей проверки или nil, когда замена выполнена или отменена.
function OSC_Abilities.ProcessDeferred(hero, slot)
    if hero:IsNull() then return nil end
    local state = OSC_HeroState.Get(hero)
    local pending = state.deferred[slot]
    if not pending then return nil end

    if IsInCastPhase(hero, slot) and Now() < pending.deadline then
        return OSC_Config.Get("ROTATION_DEFER_STEP")
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
    -- срок ожидания остаётся прежним. Срок вышел (например, таймер пропал) —
    -- применяем сразу, иначе слот завис бы навсегда.
    local pending = state.deferred[slot]
    if pending then
        pending.notify = pending.notify or notify
        if Now() < pending.deadline then
            pending.entry = entry
            return entry
        end
        state.deferred[slot] = nil
        return ApplyGive(hero, slot, entry, pending.notify)
    end

    if CanDefer() and IsInCastPhase(hero, slot) then
        Defer(hero, slot, { entry = entry, notify = notify }, "ProcessDeferred")
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
