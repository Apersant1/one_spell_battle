OSC_Casino = {}

local function GetPlayer(sourceIndex, event)
    -- Движок сам кладёт ID отправителя в event.PlayerID. sourceIndex — индекс
    -- сущности игрока (обычно PlayerID + 1), его нельзя считать ID игрока.
    local playerID = event and tonumber(event.PlayerID)
    if playerID == nil then
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

local function GetHeroPlayer(hero)
    local playerID = hero:GetPlayerOwnerID()
    local player = PlayerResource:IsValidPlayerID(playerID)
        and PlayerResource:GetPlayer(playerID)
        or nil

    if player then
        return player, playerID
    end

    local owner = hero:GetPlayerOwner()
    if owner and not owner:IsNull() then
        if not PlayerResource:IsValidPlayerID(playerID) and owner.GetPlayerID then
            playerID = owner:GetPlayerID()
        end
        OSC_Logger.Log("Casino using hero owner fallback: player_id="
            .. tostring(playerID) .. ", team=" .. hero:GetTeamNumber())
        return owner, playerID
    end

    return nil, playerID
end

-- Клиент собирает строку правил из этих данных, чтобы шансы не дублировались в тексте
local function BuildOutcomes()
    local outcomes = {}
    local loseChance = 100
    for index, outcome in ipairs(OSC_CONFIG.CASINO_OUTCOMES) do
        outcomes[tostring(index)] = {
            symbol = outcome.symbol,
            chance = outcome.chance,
            multiplier = outcome.multiplier,
        }
        loseChance = loseChance - outcome.chance
    end
    return outcomes, math.max(0, loseChance)
end

-- Кто может играть, задаёт CASINO_ACCESS: "owner" — только Огр,
-- "team" — Огр и его союзники, "all" — все игроки. Вторым значением
-- возвращает ключ локализации с причиной отказа.
local function CanUseMachine(hero, playerID, machine)
    if not machine or machine:IsNull() or machine.osc_casino_owner_player_id == nil then
        return false, "osc_casino_err_bad_machine"
    end
    if not hero or hero:IsNull() then
        return false, "osc_casino_err_unavailable"
    end

    local isOwner = machine.osc_casino_owner_player_id == playerID
    if isOwner and hero.osc_casino_machine ~= machine then
        return false, "osc_casino_err_unavailable"
    end
    if not isOwner then
        local access = OSC_CONFIG.CASINO_ACCESS or "team"
        if access == "owner" then
            return false, "osc_casino_err_owner_only"
        end
        if access == "team" and hero:GetTeamNumber() ~= machine:GetTeamNumber() then
            return false, "osc_casino_err_wrong_team"
        end
    end

    local distance = (hero:GetAbsOrigin() - machine:GetAbsOrigin()):Length2D()
    if distance > (OSC_CONFIG.CASINO_USE_DISTANCE or 450) then
        return false, "osc_casino_err_too_far"
    end
    return true
end

-- Красная подсказка внизу экрана, как у стандартных ошибок Dota
local function ShowHudError(player, token)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, "osc_hud_error", {
            message = token,
        })
    end
end

local function SendOpen(player, playerID, hero, machine)
    local outcomes, loseChance = BuildOutcomes()
    -- Запоминаем, кому показано окно, чтобы всем сообщить о закрытии автомата
    machine.osc_casino_viewers = machine.osc_casino_viewers or {}
    machine.osc_casino_viewers[playerID] = true
    OSC_Notifications.PlayerEvent(player, "osc_casino_open", {
        outcomes = outcomes,
        lose_chance = loseChance,
        machine_entindex = machine:entindex(),
        min_stake = OSC_CONFIG.CASINO_MIN_SPIN_COST,
        default_stake = OSC_CONFIG.CASINO_DEFAULT_STAKE,
        gold = hero:GetGold(),
        lifetime = OSC_CONFIG.CASINO_MACHINE_LIFETIME,
        -- Анимацию продолжает только тот, кто сам крутит; остальные видят автомат свободным
        spinning = machine.osc_casino_is_spinning == true
            and machine.osc_casino_spinner_id == playerID,
    })
end

function OSC_Casino.Init()
    -- Клиенту нужен радиус, чтобы рисовать зону действия по Alt
    CustomNetTables:SetTableValue("osc_state", "casino", {
        use_distance = OSC_CONFIG.CASINO_USE_DISTANCE or 450,
    })
    CustomGameEventManager:RegisterListener("osc_casino_spin", OSC_Casino.OnSpin)
    CustomGameEventManager:RegisterListener("osc_casino_reopen", OSC_Casino.OnReopen)
end

function OSC_Casino.OnReopen(sourceIndex, event)
    local _, playerID = GetPlayer(sourceIndex, event)
    if not playerID then return end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local machineIndex = event and tonumber(event.machine_entindex)
    if not hero or not machineIndex or machineIndex ~= math.floor(machineIndex) then
        return
    end

       local machine = EntIndexToHScript(machineIndex)
    local canUse, reason = CanUseMachine(hero, playerID, machine)
    if not canUse then
        -- Клиент повторяет запрос, пока герой идёт к автомату; такие повторы
        -- приходят с quiet = 1, и подсказку на них не показываем
        if tonumber(event.quiet) ~= 1 then
            OSC_Logger.Log("Casino reopen refused for player " .. tostring(playerID)
                .. ": " .. tostring(reason))
            ShowHudError(PlayerResource:GetPlayer(playerID), reason)
        end
        return
    end

    local player, ownerPlayerID = GetHeroPlayer(hero)
    if not player or ownerPlayerID ~= playerID then return end

    SendOpen(player, playerID, hero, machine)
end

-- Вспышка и звук на автомате при выигрыше; джекпот — эффект побольше
local function PlayWinEffects(machine, isJackpot)
    if not machine or machine:IsNull() then return end

    local particleName = isJackpot and OSC_CONFIG.CASINO_JACKPOT_PARTICLE
        or OSC_CONFIG.CASINO_WIN_PARTICLE
    local soundName = isJackpot and OSC_CONFIG.CASINO_JACKPOT_SOUND
        or OSC_CONFIG.CASINO_WIN_SOUND

    if particleName and particleName ~= "" then
        local particle = ParticleManager:CreateParticle(
            particleName, PATTACH_ABSORIGIN_FOLLOW, machine)
        -- Некоторые эффекты (Midas) летят от точки 0 к точке 1: ставим обе на автомат
        ParticleManager:SetParticleControlEnt(particle, 1, machine,
            PATTACH_ABSORIGIN_FOLLOW, nil, machine:GetAbsOrigin(), true)
        ParticleManager:ReleaseParticleIndex(particle)
    end
    if soundName and soundName ~= "" then
        EmitSoundOn(soundName, machine)
    end
end

-- Убирает автомат и закрывает окно у всех, кто в нём сидел
local function RemoveMachine(machine)
    if not machine or machine:IsNull() then return end

    for viewerID in pairs(machine.osc_casino_viewers or {}) do
        local viewer = PlayerResource:GetPlayer(viewerID)
        if viewer then
            OSC_Notifications.PlayerEvent(viewer, "osc_casino_closed", {
                machine_entindex = machine:entindex(),
            })
        end
    end

    local owner = machine.osc_casino_owner_hero
    if owner and not owner:IsNull() and owner.osc_casino_machine == machine then
        owner.osc_casino_machine = nil
    end
    UTIL_Remove(machine)
end

-- Способность Огра только ставит автомат. Окно открывается кликом по автомату
-- (клиент шлёт osc_casino_reopen, см. OnReopen). Повторное применение
-- переносит автомат на новое место, если на нём сейчас не крутят барабаны.
function OSC_Casino.SpawnMachine(hero)
    local _, playerID = GetHeroPlayer(hero)

    local oldMachine = hero.osc_casino_machine
    if oldMachine and not oldMachine:IsNull() then
        if oldMachine.osc_casino_is_spinning then
            ShowHudError(PlayerResource:GetPlayer(playerID), "osc_casino_err_spinning")
            return false
        end
        RemoveMachine(oldMachine)
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
        OSC_Logger.Error("Failed to spawn casino object")
        return false
    end

    machine:SetMaterialGroup("base")                                              -- фикс материала
    machine:SetHullRadius(OSC_CONFIG.CASINO_HULL_RADIUS)

    FindClearSpaceForUnit(machine, origin, true)
    machine:SetForwardVector(hero:GetForwardVector() * -1)
    machine:AddNewModifier(machine, nil, "modifier_invulnerable", {})
    machine.osc_casino_owner_player_id = playerID
    machine.osc_casino_owner_hero = hero
    machine.osc_casino_is_spinning = false
    hero.osc_casino_machine = machine

    machine:SetContextThink("osc_casino_expire", function()
        if machine:IsNull() then return nil end
        -- Идёт спин: ждём результата, чтобы ставка не пропала
        if machine.osc_casino_is_spinning then
            return 0.5
        end
        RemoveMachine(machine)
        return nil
    end, OSC_CONFIG.CASINO_MACHINE_LIFETIME)

    OSC_Logger.Log("Spawned casino for player " .. tostring(playerID)
        .. " on team " .. hero:GetTeamNumber())
    return true
end

function OSC_Casino.OnSpin(sourceIndex, event)
    local player, playerID = GetPlayer(sourceIndex, event)
    if not player then return end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local function SendResult(data)
        OSC_Notifications.PlayerEvent(player, "osc_casino_result", data)
    end

    if not hero or hero:IsNull() then
        SendResult({ error = "osc_casino_err_unavailable" })
        return
    end

    local machineIndex = event and tonumber(event.machine_entindex)
    if not machineIndex or machineIndex < 0 or machineIndex ~= math.floor(machineIndex) then
        SendResult({ error = "osc_casino_err_bad_machine" })
        return
    end

    local machine = EntIndexToHScript(machineIndex)
    local canUse, reason = CanUseMachine(hero, playerID, machine)
    if not canUse then
        SendResult({ error = reason })
        return
    end

    if machine.osc_casino_is_spinning then
        SendResult({ error = "osc_casino_err_spinning" })
        return
    end

    if GameRules:GetGameTime() < (machine.osc_casino_next_spin_time or 0) then
        SendResult({ error = "osc_casino_err_cooldown" })
        return
    end

    local stake = event and tonumber(event.stake)
    if not stake or stake ~= math.floor(stake)
        or stake < OSC_CONFIG.CASINO_MIN_SPIN_COST
        or stake > hero:GetGold() then
        SendResult({
            error = "osc_casino_err_stake",
            min_stake = OSC_CONFIG.CASINO_MIN_SPIN_COST,
            gold = hero:GetGold(),
        })
        return
    end

    local goldBefore = PlayerResource:GetGold(playerID)
    local reliableBefore = PlayerResource:GetReliableGold(playerID)
    PlayerResource:SpendGold(playerID, stake, DOTA_ModifyGold_Unspecified)
    local spent = goldBefore - PlayerResource:GetGold(playerID)
    local reliableSpent = math.max(0, reliableBefore - PlayerResource:GetReliableGold(playerID))

    local function ReturnGold(amount)
        local reliablePart = math.min(amount, reliableSpent)
        if reliablePart > 0 then
            PlayerResource:ModifyGold(playerID, reliablePart, true, DOTA_ModifyGold_Unspecified)
        end
        if amount > reliablePart then
            PlayerResource:ModifyGold(playerID, amount - reliablePart, false, DOTA_ModifyGold_Unspecified)
        end
    end

    -- Ставка должна списаться целиком, иначе выигрыш был бы считан с недоплаты
    if spent ~= stake then
        if spent > 0 then ReturnGold(spent) end
        OSC_Logger.Error("Casino stake was not charged: expected " .. stake .. ", got " .. spent)
        SendResult({ error = "osc_casino_err_not_charged", gold = hero:GetGold() })
        return
    end

    machine.osc_casino_is_spinning = true
    machine.osc_casino_spinner_id = playerID
    machine.osc_casino_stake_pending = true
    machine.osc_casino_next_spin_time = GameRules:GetGameTime() + 1
    local stakeRefunded = false
    local stakePending = true

    local function SetMachineSpinState(isSpinning)
        if not machine:IsNull() then
            machine.osc_casino_is_spinning = isSpinning
            if not isSpinning then
                machine.osc_casino_spinner_id = nil
            end
            machine.osc_casino_stake_pending = stakePending
        end
    end

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

    GameRules:GetGameModeEntity():SetContextThink(
        "osc_casino_settle_" .. machine:entindex(),
        function()
            local ok, currentGold, failureReason = pcall(function()
                local currentHero = PlayerResource:GetSelectedHeroEntity(playerID)
                if not currentHero or currentHero:IsNull() then
                    ReturnGold(stake)
                    stakePending = false
                    stakeRefunded = true
                    SetMachineSpinState(false)
                    return nil, "hero is unavailable"
                end

                ReturnGold(payout)
                stakePending = false
                SetMachineSpinState(false)
                return currentHero:GetGold()
            end)

            if not ok or failureReason then
                local reason = failureReason or tostring(currentGold)
                OSC_Logger.Error("Casino settlement failed: " .. reason)
                if stakePending then
                    ReturnGold(stake)
                    stakePending = false
                    stakeRefunded = true
                end
                SetMachineSpinState(false)
                SendResult({
                    error = stakeRefunded
                        and "osc_casino_err_settle_refunded"
                        or "osc_casino_err_settle_failed",
                })
                return nil
            end

            if payout > 0 then
                PlayWinEffects(machine, reels[1] == "seven")
            end
            SendResult({
                stake = stake,
                payout = payout,
                net = payout - stake,
                reel1 = reels[1],
                reel2 = reels[2],
                reel3 = reels[3],
                gold = currentGold,
            })
            return nil
        end,
        2.4
    )
end