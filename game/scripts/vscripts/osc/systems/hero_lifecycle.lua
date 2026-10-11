OSC_HeroLifecycle = {}

local MAX_INIT_ATTEMPTS = 3
local RETRY_DELAY = 1

local function IsValidEntity(entity)
    return entity and not entity:IsNull()
end

local function InitializeHeroAbilities(hero, source)
    if not IsValidEntity(hero) or hero.osc_initialized then return end
    if hero.osc_init_attempts and hero.osc_init_attempts >= MAX_INIT_ATTEMPTS then
        hero.osc_init_state = "failed"
        return
    end

    hero.osc_init_attempts = (hero.osc_init_attempts or 0) + 1
    hero.osc_init_state = "initializing"
    OSC_Logger.Log("Init hero " .. hero:GetUnitName() .. " from " .. source
        .. " (attempt " .. hero.osc_init_attempts .. ")")

    hero:SetContextThink("osc_init", function()
        if not IsValidEntity(hero) then return nil end

        local ok, err = pcall(function()
            OSC_Abilities.StripHero(hero)
            OSC_Abilities.EnsureOgreCasinoAbility(hero)
            OSC_Abilities.GiveRandom(hero, true)
            if hero:GetLevel() >= 6 then
                OSC_Abilities.GiveRandomUltimate(hero, true)
            end
        end)

        if ok then
            hero.osc_initialized = true
            hero.osc_init_state = nil
            return nil
        end

        OSC_Logger.Error("Hero initialization failed for " .. hero:GetUnitName()
            .. " on attempt " .. hero.osc_init_attempts .. ": " .. tostring(err))

        if hero.osc_init_attempts < MAX_INIT_ATTEMPTS then
            hero.osc_init_state = "retry_pending"
            hero:SetContextThink("osc_init_retry", function()
                if IsValidEntity(hero) and not hero.osc_initialized then
                    InitializeHeroAbilities(hero, source)
                end
                return nil
            end, RETRY_DELAY)
        else
            hero.osc_init_state = "failed"
            OSC_Logger.Error("Hero initialization exhausted retries for "
                .. hero:GetUnitName())
        end
        return nil
    end, 0.5)
end

function OSC_HeroLifecycle.TryInitializeUnit(unit, source)
    if not IsValidEntity(unit) or not unit.IsHero or not unit:IsHero() then return end

    local isCopy = unit:IsIllusion()
        or (unit.IsTempestDouble and unit:IsTempestDouble())
        or (unit.IsClone and unit:IsClone())

    if isCopy then
        if unit.osc_copy_done then return end
        unit.osc_copy_done = true

        unit:SetContextThink("osc_copy", function()
            if not IsValidEntity(unit) then return nil end
            local owner = PlayerResource:GetSelectedHeroEntity(unit:GetPlayerOwnerID())
            if IsValidEntity(owner) and owner ~= unit then
                OSC_Abilities.CopyFromOwner(unit, owner)
            end
            return nil
        end, 0.1)
        return
    end

    if not unit:IsRealHero() then return end
    OSC_Couriers.EnsureTeamCouriers(unit)
    if unit.osc_initialized or unit.osc_init_state then return end
    InitializeHeroAbilities(unit, source)
end

local function OnNPCSpawned(event)
    OSC_HeroLifecycle.TryInitializeUnit(
        EntIndexToHScript(event.entindex),
        "npc_spawned"
    )
end

local function OnHeroFinishSpawn(event)
    OSC_HeroLifecycle.TryInitializeUnit(
        EntIndexToHScript(event.heroindex),
        "dota_on_hero_finish_spawn"
    )
end

local function OnPlayerLevelUp(event)
    local hero
    if event.hero_entindex then
        hero = EntIndexToHScript(event.hero_entindex)
    else
        hero = PlayerResource:GetSelectedHeroEntity(event.player_id)
    end
    if not IsValidEntity(hero) then return end

    local level = event.level or hero:GetLevel()
    if level >= 6 and not hero.osc_current_ultimate then
        OSC_Abilities.GiveRandomUltimate(hero, true)
    end

    local ability = hero.osc_current_ability and hero:FindAbilityByName(hero.osc_current_ability)
    if ability then
        local newLevel = OSC_Abilities.CalcLevel(level, ability)
        ability:SetLevel(math.max(ability:GetLevel(), newLevel))
    end

    local ultimate = hero.osc_current_ultimate and hero:FindAbilityByName(hero.osc_current_ultimate)
    if ultimate then
        local newLevel = OSC_Abilities.CalcLevel(level, ultimate)
        ultimate:SetLevel(math.max(ultimate:GetLevel(), newLevel))
    end
end

function OSC_HeroLifecycle.Init()
    ListenToGameEvent("npc_spawned", OnNPCSpawned, nil)
    ListenToGameEvent("dota_on_hero_finish_spawn", OnHeroFinishSpawn, nil)
    ListenToGameEvent("dota_player_gained_level", OnPlayerLevelUp, nil)
end
