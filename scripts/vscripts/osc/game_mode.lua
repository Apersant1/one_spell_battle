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
    ListenToGameEvent("player_chat",               Dynamic_Wrap(OneSpellChaos, "OnPlayerChat"),      self)
    CustomGameEventManager:RegisterListener("osc_casino_spin", function(sourceIndex, event)
        self:OnCasinoSpin(sourceIndex, event)
    end)
    CustomGameEventManager:RegisterListener("osc_casino_reopen", function(sourceIndex, event)
        self:OnCasinoReopen(sourceIndex, event)
    end)

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

function OneSpellChaos:GetCasinoPlayer(sourceIndex)
    local playerID
    if PlayerResource:IsValidPlayerID(sourceIndex) then
        playerID = sourceIndex
    else
        local source = sourceIndex and EntIndexToHScript(sourceIndex)
        if source and not source:IsNull() and source.GetPlayerID then
            playerID = source:GetPlayerID()
        end
    end

    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        return nil
    end

    return PlayerResource:GetPlayer(playerID), playerID
end

function OneSpellChaos:OnCasinoReopen(sourceIndex, event)
    local player, playerID = self:GetCasinoPlayer(sourceIndex)
    if not player then return end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local machineIndex = event and tonumber(event.machine_entindex)
    if not hero or hero:GetUnitName() ~= "npc_dota_hero_ogre_magi" or not hero:HasScepter()
        or not machineIndex or machineIndex ~= math.floor(machineIndex) then
        return
    end

    local machine = EntIndexToHScript(machineIndex)
    if not machine or machine:IsNull()
        or machine.osc_casino_owner_player_id ~= playerID
        or hero.osc_casino_machine ~= machine
        or (hero:GetAbsOrigin() - machine:GetAbsOrigin()):Length2D() > 450 then
        return
    end

    CustomGameEventManager:Send_ServerToPlayer(player, "osc_casino_open", {
        machine_entindex = machine:entindex(),
        min_stake = OSC_CONFIG.CASINO_MIN_SPIN_COST,
        default_stake = OSC_CONFIG.CASINO_DEFAULT_STAKE,
        gold = hero:GetGold(),
        lifetime = OSC_CONFIG.CASINO_MACHINE_LIFETIME,
        spinning = machine.osc_casino_is_spinning,
    })
end

function OneSpellChaos:OpenCasino(hero)
    local playerID = hero:GetPlayerOwnerID()
    local player = PlayerResource:GetPlayer(playerID)
    if not player then return end

    local oldMachine = hero.osc_casino_machine
    if oldMachine and not oldMachine:IsNull() then
        CustomGameEventManager:Send_ServerToPlayer(player, "osc_casino_open", {
            machine_entindex = oldMachine:entindex(),
            min_stake = OSC_CONFIG.CASINO_MIN_SPIN_COST,
            default_stake = OSC_CONFIG.CASINO_DEFAULT_STAKE,
            gold = hero:GetGold(),
            lifetime = OSC_CONFIG.CASINO_MACHINE_LIFETIME,
        })
        return
    end

    local origin = hero:GetAbsOrigin() + hero:GetForwardVector() * 180
    local machine = CreateUnitByName(
        "npc_osc_casino_test_object",
        origin,
        true,
        hero,
        hero,
        hero:GetTeamNumber()
    )
    if not machine then
        print("[OSC] Failed to spawn casino test object")
        return
    end

    FindClearSpaceForUnit(machine, origin, true)
    machine:SetForwardVector(hero:GetForwardVector() * -1)
    machine:AddNewModifier(machine, nil, "modifier_invulnerable", {})
    machine.osc_casino_owner_player_id = playerID
    machine.osc_casino_is_spinning = false
    hero.osc_casino_machine = machine

    machine:SetContextThink("osc_casino_expire", function()
        if not machine:IsNull() then
            local ownerPlayer = PlayerResource:GetPlayer(playerID)
            if ownerPlayer then
                CustomGameEventManager:Send_ServerToPlayer(ownerPlayer, "osc_casino_closed", {
                    machine_entindex = machine:entindex(),
                })
            end
            UTIL_Remove(machine)
        end
        if hero.osc_casino_machine == machine then
            hero.osc_casino_machine = nil
        end
        return nil
    end, OSC_CONFIG.CASINO_MACHINE_LIFETIME)

    CustomGameEventManager:Send_ServerToPlayer(player, "osc_casino_open", {
        machine_entindex = machine:entindex(),
        min_stake = OSC_CONFIG.CASINO_MIN_SPIN_COST,
        default_stake = OSC_CONFIG.CASINO_DEFAULT_STAKE,
        gold = hero:GetGold(),
        lifetime = OSC_CONFIG.CASINO_MACHINE_LIFETIME,
    })
end

function OneSpellChaos:OnCasinoSpin(sourceIndex, event)
    local player, playerID = self:GetCasinoPlayer(sourceIndex)
    if not player then return end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local function SendResult(data)
        CustomGameEventManager:Send_ServerToPlayer(player, "osc_casino_result", data)
    end

    if not hero or hero:GetUnitName() ~= "npc_dota_hero_ogre_magi" or not hero:HasScepter() then
        SendResult({ error = "Казино доступно только Огр Маги с Aghanim's Scepter" })
        return
    end

    local machineIndex = event and tonumber(event.machine_entindex)
    if not machineIndex or machineIndex < 0 or machineIndex ~= math.floor(machineIndex) then
        SendResult({ error = "Некорректный автомат" })
        return
    end

    local machine = machineIndex and EntIndexToHScript(machineIndex)
    if not machine or machine:IsNull()
        or machine.osc_casino_owner_player_id ~= playerID
        or hero.osc_casino_machine ~= machine
        or (hero:GetAbsOrigin() - machine:GetAbsOrigin()):Length2D() > 450 then
        SendResult({ error = "Автомат недоступен: подойдите ближе и вызовите его снова" })
        return
    end

    if machine.osc_casino_is_spinning then
        SendResult({ error = "Автомат уже запущен" })
        return
    end

    if GameRules:GetGameTime() < (machine.osc_casino_next_spin_time or 0) then
        SendResult({ error = "Подождите, пока автомат подготовится" })
        return
    end

    local stake = event and tonumber(event.stake)
    if not stake or stake ~= math.floor(stake)
        or stake < OSC_CONFIG.CASINO_MIN_SPIN_COST
        or stake > hero:GetGold() then
        SendResult({
            error = "Ставка должна быть не меньше " .. OSC_CONFIG.CASINO_MIN_SPIN_COST
                .. " и не больше вашего запаса золота",
            gold = hero:GetGold(),
        })
        return
    end

    machine.osc_casino_is_spinning = true
    machine.osc_casino_next_spin_time = GameRules:GetGameTime() + 1

    local roll = RandomInt(1, 100)
    local payout = 0
    local reels
    for _, outcome in ipairs(OSC_CONFIG.CASINO_OUTCOMES) do
        if roll <= outcome.chance then
            reels = { outcome.symbol, outcome.symbol, outcome.symbol }
            payout = stake * outcome.multiplier
            break
        end
        roll = roll - outcome.chance
    end

    if not reels then
        local symbols = { "circle", "diamond", "star", "seven" }
        local first = symbols[RandomInt(1, #symbols)]
        local second = symbols[RandomInt(1, #symbols)]
        local third = symbols[RandomInt(1, #symbols)]
        while first == second and second == third do
            third = symbols[RandomInt(1, #symbols)]
        end
        reels = { first, second, third }
    end

    machine:SetContextThink("osc_casino_settle", function()
        if machine:IsNull() then return nil end

        local currentHero = PlayerResource:GetSelectedHeroEntity(playerID)
        if not currentHero or currentHero:IsNull() then
            machine.osc_casino_is_spinning = false
            SendResult({ error = "Не удалось завершить ставку: герой недоступен" })
            return nil
        end

        if currentHero:GetGold() < stake then
            machine.osc_casino_is_spinning = false
            SendResult({
                error = "Недостаточно золота для списания ставки после вращения",
                gold = currentHero:GetGold(),
            })
            return nil
        end

        local net = payout - stake
        if net ~= 0 then
            currentHero:ModifyGold(net, false, DOTA_ModifyGold_Unspecified)
        end
        machine.osc_casino_is_spinning = false

        SendResult({
            stake = stake,
            payout = payout,
            net = net,
            reel1 = reels[1],
            reel2 = reels[2],
            reel3 = reels[3],
            gold = currentHero:GetGold(),
        })
        return nil
    end, 2.4)
end

function OneSpellChaos:OnPlayerChat(event)
    local text = string.lower(string.match(event.text or "", "^%s*(.-)%s*$"))
    if text ~= "-reroll" then return end

    local playerID = event.playerid
    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        print("[OSC] -reroll ignored: invalid player")
        return
    end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    if not hero or not hero.osc_initialized then
        print("[OSC] -reroll ignored: player has no initialized hero")
        return
    end

    OSC_Abilities.GiveRandom(hero, true)
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
            if unit:GetLevel() >= 6 then
                OSC_Abilities.GiveRandomUltimate(unit, true)
            end
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
    if not hero then return end

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