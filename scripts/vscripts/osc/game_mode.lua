if OneSpellChaos == nil then
    OneSpellChaos = class({})
end

--------------------------------------------------------------------
-- Инициализация
--------------------------------------------------------------------
function OneSpellChaos:Init()
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_GOODGUYS, 5)
    GameRules:SetCustomGameTeamMaxPlayers(DOTA_TEAM_BADGUYS, 5)
    GameRules:SetCustomGameSetupAutoLaunchDelay(15)

    self.timerStarted = false

    ListenToGameEvent("npc_spawned",               Dynamic_Wrap(OneSpellChaos, "OnNPCSpawned"),      self)
    ListenToGameEvent("dota_on_hero_finish_spawn", Dynamic_Wrap(OneSpellChaos, "OnHeroFinishSpawn"), self)
    ListenToGameEvent("dota_player_gained_level",  Dynamic_Wrap(OneSpellChaos, "OnPlayerLevelUp"),   self)
    ListenToGameEvent("game_rules_state_change",   Dynamic_Wrap(OneSpellChaos, "OnStateChange"),     self)

    Convars:RegisterCommand("osc_strip", function()
        local player = Convars:GetCommandClient()
        local hero = player and player:GetAssignedHero()
        if hero then
            OSC_Abilities.StripHero(hero)
            OSC_Abilities.GiveRandom(hero, true)
            print("[OSC] Manual strip done")
        else
            print("[OSC] No hero found")
        end
    end, "Strip abilities", FCVAR_CHEAT)

    self:PublishTimer()

    print("[OSC] One Spell Chaos loaded")
end

--------------------------------------------------------------------
-- Спавн героя
--------------------------------------------------------------------
function OneSpellChaos:OnNPCSpawned(event)
    self:TryInitHero(EntIndexToHScript(event.entindex), "npc_spawned")
end

function OneSpellChaos:OnHeroFinishSpawn(event)
    self:TryInitHero(EntIndexToHScript(event.heroindex), "dota_on_hero_finish_spawn")
end

function OneSpellChaos:TryInitHero(unit, source)
    if not unit or unit:IsNull() then return end
    if not unit.IsHero or not unit:IsHero() then return end

    -- Иллюзии, Tempest Double и клоны Meepo копируют способность владельца
    local isCopy = unit:IsIllusion()
        or (unit.IsTempestDouble and unit:IsTempestDouble())
        or (unit.IsClone and unit:IsClone())

    if isCopy then
        if unit.osc_copy_done then return end
        unit.osc_copy_done = true

        -- Задержка: движок выставляет иллюзии способности уже после спавна
        unit:SetContextThink("osc_copy", function()
            local owner = PlayerResource:GetSelectedHeroEntity(unit:GetPlayerOwnerID())
            if owner and owner ~= unit then
                OSC_Abilities.CopyFromOwner(unit, owner)
            end
            return nil
        end, 0.1)
        return
    end

    if not unit:IsRealHero() then return end
    if unit.osc_initialized then return end
    unit.osc_initialized = true

    print("[OSC] Init hero " .. unit:GetUnitName() .. " from " .. source)

    unit:SetContextThink("osc_init", function()
        local ok, err = pcall(function()
            OSC_Abilities.StripHero(unit)
            OSC_Abilities.GiveRandom(unit, true)
        end)
        if not ok then
            print("[OSC] ERROR: " .. tostring(err))
        end
        return nil
    end, 0.5)
end

--------------------------------------------------------------------
-- Уровень героя -> уровень способности
--------------------------------------------------------------------
function OneSpellChaos:OnPlayerLevelUp(event)
    local hero
    if event.hero_entindex then
        hero = EntIndexToHScript(event.hero_entindex)
    else
        hero = PlayerResource:GetSelectedHeroEntity(event.player_id)
    end
    if not hero or not hero.osc_current_ability then return end

    local ability = hero:FindAbilityByName(hero.osc_current_ability)
    if ability then
        local newLevel = OSC_Abilities.CalcLevel(event.level or hero:GetLevel(), ability)
        ability:SetLevel(math.max(ability:GetLevel(), newLevel))
    end
end

--------------------------------------------------------------------
-- Таймер смены способностей
--------------------------------------------------------------------
function OneSpellChaos:OnStateChange()
    if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        self:StartRotationTimer()
    end
end

function OneSpellChaos:StartRotationTimer()
    if self.timerStarted then return end
    self.timerStarted = true

    self.nextRotationTime = GameRules:GetGameTime() + OSC_CONFIG.ROTATION_INTERVAL
    
    self.warned = false
    self:PublishTimer()
    print("[OSC] Rotation timer started")
    GameRules:GetGameModeEntity():SetThink("RotationThink", self, "osc_rotation", 0.5)
end

function OneSpellChaos:RotationThink()
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
        return nil
    end

    local timeLeft = self.nextRotationTime - GameRules:GetGameTime()

    if not self.warned and timeLeft <= OSC_CONFIG.WARNING_TIME then
        self.warned = true
        OSC_Abilities.AnnounceWarning(OSC_CONFIG.WARNING_TIME)
    end

    if timeLeft <= 0 then
        self:RotateAll()
        self.nextRotationTime = self.nextRotationTime + OSC_CONFIG.ROTATION_INTERVAL
        self.warned = false
        self:PublishTimer()
    end

    return 0.5
end

function OneSpellChaos:RotateAll()
    OSC_Abilities.AnnounceRotation()

    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            local hero = PlayerResource:GetSelectedHeroEntity(playerID)
            if hero and hero.osc_initialized then
                OSC_Abilities.GiveRandom(hero, true)
            end
        end
    end
end

function OneSpellChaos:PublishTimer()
    CustomNetTables:SetTableValue("osc_state", "timer", {
        next_rotation = self.nextRotationTime or -1,
    })
end