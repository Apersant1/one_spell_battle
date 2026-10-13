require("osc/core/heroes")
require("osc/core/game_events")
require("osc/core/hero_state")

OSC_HeroLifecycle = OSC_HeroLifecycle or {}

local MAX_INIT_ATTEMPTS = 3
local RETRY_DELAY = 1

local function InitializeHeroAbilities(hero, source)
    if not OSC_Heroes.IsValid(hero) then return end
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
        if not OSC_Heroes.IsValid(hero) then return nil end

        local ok, err = pcall(function()
            OSC_Abilities.StripHero(hero)
            -- Порядок выдачи задаёт слоты: способность первой встаёт на Q,
            -- собственные способности героя (казино Огра) — следом на W
            OSC_Abilities.GiveRandom(hero, true)
            OSC_Abilities.GrantHeroExtras(hero)
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
                if OSC_Heroes.IsValid(hero) and not state.initialized then
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
        state.copy_done = true

        unit:SetContextThink("osc_copy", function()
            local owner = OSC_Heroes.GetCopyOwner(unit)
            if owner then
                OSC_Abilities.CopyFromOwner(unit, owner)
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
    if not OSC_Heroes.IsValid(hero) or not state or not state.initialized then return end

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

function OSC_HeroLifecycle.Init()
    OSC_GameEvents.Subscribe("hero_spawned", "hero_lifecycle", function(unit, source)
        OSC_HeroLifecycle.TryInitializeUnit(unit, source)
    end)
    ListenToGameEvent("dota_player_gained_level", OnPlayerLevelUp, nil)
end
