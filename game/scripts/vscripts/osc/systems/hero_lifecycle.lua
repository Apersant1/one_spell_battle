require("osc/core/heroes")
require("osc/core/game_events")
require("osc/core/hero_state")

OSC_HeroLifecycle = OSC_HeroLifecycle or {}

local MAX_INIT_ATTEMPTS = 3
local RETRY_DELAY = 1

local function InitializeHeroAbilities(hero, source)
    if not IsValidEntity(hero) then return end
    local state = OSC_HeroState.Get(hero)
    if state.initialized then return end
    if state.init_attempts >= MAX_INIT_ATTEMPTS then
        state.init_state = "failed"
        return
    end

    state.init_attempts = state.init_attempts + 1
    state.init_state = "initializing"
    OSC_Logger.Log("Init hero " .. hero:GetUnitName() .. " from " .. source
        .. " (attempt " .. state.init_attempts .. ")")

    hero:SetContextThink("osc_init", function()
        if not IsValidEntity(hero) then return nil end

        local ok, err = pcall(function()
            -- Каждая попытка — первичная выдача: после частичного успеха
            -- прошлой попытки способность не считается «сменой» (без
            -- перезарядки partial) и теги не пишутся в историю дважды
            OSC_HeroState.Reset(hero, { "ability", "ultimate", "recent_tags", "deferred" })
            OSC_Abilities.StripHero(hero)
            -- Порядок выдачи задаёт слоты: способность первой встаёт на Q,
            -- собственные способности героя (казино Огра) — следом на W
            OSC_Abilities.GiveRandom(hero, true)
            OSC_Abilities.SyncHeroExtras(hero)
            if hero:GetLevel() >= 6 then
                OSC_Abilities.GiveRandomUltimate(hero, true)
            end
        end)

        if ok then
            state.initialized = true
            state.init_state = nil
            OSC_GameEvents.Emit("hero_initialized", hero)
            return nil
        end

        OSC_Logger.Error("Hero initialization failed for " .. hero:GetUnitName()
            .. " on attempt " .. state.init_attempts .. ": " .. tostring(err))

        if state.init_attempts < MAX_INIT_ATTEMPTS then
            state.init_state = "retry_pending"
            hero:SetContextThink("osc_init_retry", function()
                if IsValidEntity(hero) and not state.initialized then
                    InitializeHeroAbilities(hero, source)
                end
                return nil
            end, RETRY_DELAY)
        else
            state.init_state = "failed"
            OSC_Logger.Error("Hero initialization exhausted retries for "
                .. hero:GetUnitName())
        end
        return nil
    end, 0.5)
end

-- Основной герой получает способности режима, копия (иллюзия, Tempest
-- Double, клон Meepo) — способности основного героя своего игрока
function OSC_HeroLifecycle.TryInitializeUnit(unit, source)
    if OSC_Heroes.IsCopy(unit) then
        local state = OSC_HeroState.Get(unit)
        if state.copy_done then return end

        -- Именованный think: повторное событие лишь переназначает его.
        -- Копия без владельца (Wall of Replica, владелец ещё не выставлен)
        -- не помечается — следующее событие даст ей второй шанс.
        unit:SetContextThink("osc_copy", function()
            local owner = OSC_Heroes.GetCopyOwner(unit)
            if owner and not state.copy_done then
                OSC_Abilities.CopyFromOwner(unit, owner)
                state.copy_done = true
            end
            return nil
        end, 0.1)
        return
    end

    if not OSC_Heroes.IsMainHero(unit) then return end
    local state = OSC_HeroState.Get(unit)
    if state.initialized or state.init_state then return end
    InitializeHeroAbilities(unit, source)
end

local function OnPlayerLevelUp(event)
    local hero
    if event.hero_entindex then
        hero = EntIndexToHScript(event.hero_entindex)
    else
        hero = PlayerResource:GetSelectedHeroEntity(event.player_id)
    end
    -- До инициализации уровни не трогаем: она сама выдаст ультимейт с 6-го уровня
    local state = OSC_HeroState.Peek(hero)
    if not IsValidEntity(hero) or not state or not state.initialized then return end

    local ok, err = pcall(function()
        local level = event.level or hero:GetLevel()
        if level >= 6 and not state.ultimate then
            OSC_Abilities.GiveRandomUltimate(hero, true)
        end

        for _, name in pairs({ state.ability, state.ultimate }) do
            local ability = hero:FindAbilityByName(name)
            if ability then
                OSC_Abilities.SetEntryLevel(hero, name, OSC_Abilities.CalcLevel(level, ability))
            end
        end

        OSC_Abilities.SyncCopies(hero)
    end)
    if not ok then
        OSC_Logger.Error("Level up handling failed for " .. hero:GetUnitName() .. ": " .. tostring(err))
    end
end

function OSC_HeroLifecycle.SyncExtras()
    OSC_Heroes.ForEachPlayerHero(function(hero, playerID)
        if OSC_HeroState.Get(hero).initialized then
            local ok, err = pcall(OSC_Abilities.SyncHeroExtras, hero)
            if not ok then
                OSC_Logger.Error("Extras sync for player " .. playerID .. ": " .. tostring(err))
            end
        end
    end)
end

function OSC_HeroLifecycle.Init()
    OSC_GameEvents.Subscribe("hero_spawned", "hero_lifecycle", function(unit, source)
        OSC_HeroLifecycle.TryInitializeUnit(unit, source)
    end)
    -- Итоги голосования могли включить или выключить собственные
    -- способности героев (казино), которые уже выданы при пике
    OSC_GameEvents.Subscribe("config_overrides_applied", "hero_lifecycle", function()
        OSC_HeroLifecycle.SyncExtras()
    end)
    ListenToGameEvent("dota_player_gained_level", OnPlayerLevelUp, nil)
end
