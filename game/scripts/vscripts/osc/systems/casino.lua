OSC_Casino = {}

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

local function SendOpen(player, hero, machine, spinning)
    OSC_Notifications.PlayerEvent(player, "osc_casino_open", {
        machine_entindex = machine:entindex(),
        min_stake = OSC_CONFIG.CASINO_MIN_SPIN_COST,
        default_stake = OSC_CONFIG.CASINO_DEFAULT_STAKE,
        gold = hero:GetGold(),
        lifetime = OSC_CONFIG.CASINO_MACHINE_LIFETIME,
        spinning = spinning,
    })
end

function OSC_Casino.Init()
    CustomGameEventManager:RegisterListener("osc_casino_spin", OSC_Casino.OnSpin)
    CustomGameEventManager:RegisterListener("osc_casino_reopen", OSC_Casino.OnReopen)
end

function OSC_Casino.OnReopen(sourceIndex, event)
    local playerID = event and event.PlayerID
    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        return
    end

    local player = PlayerResource:GetPlayer(playerID)
    if not player then
        return
    end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local machineIndex = event and tonumber(event.machine_entindex)
    if not hero or hero:GetUnitName() ~= "npc_dota_hero_ogre_magi"
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

    local player, ownerPlayerID = GetHeroPlayer(hero)
    if not player or ownerPlayerID ~= playerID then return end

    SendOpen(player, hero, machine, machine.osc_casino_is_spinning)
end

function OSC_Casino.OpenCasino(hero)
    local player, playerID = GetHeroPlayer(hero)
    if not player then
        OSC_Logger.Error("Cannot open casino: no player handle for hero "
            .. hero:GetUnitName() .. ", player_id=" .. tostring(playerID)
            .. ", team=" .. hero:GetTeamNumber())
        return
    end

    local oldMachine = hero.osc_casino_machine
    if oldMachine and not oldMachine:IsNull() then
        SendOpen(player, hero, oldMachine, oldMachine.osc_casino_is_spinning)
        OSC_Logger.Log("Reopened casino for player " .. tostring(playerID)
            .. " on team " .. hero:GetTeamNumber())
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
        OSC_Logger.Error("Failed to spawn casino test object")
        return
    end

    machine:SetMaterialGroup("base") -- фикс материала
    machine:AddNewModifier(machine, nil, "modifier_osc_casino_visual_offset", {}) -- фикс origin

    FindClearSpaceForUnit(machine, origin, true)
    machine:SetForwardVector(hero:GetForwardVector() * -1)
    machine:AddNewModifier(machine, nil, "modifier_invulnerable", {})
    machine.osc_casino_owner_player_id = playerID
    machine.osc_casino_is_spinning = false
    hero.osc_casino_machine = machine

    machine:SetContextThink("osc_casino_expire", function()
        if not machine:IsNull() and machine.osc_casino_is_spinning then
            return 0.5
        end

        if not machine:IsNull() then
            local ownerPlayer = PlayerResource:GetPlayer(playerID)
            if ownerPlayer then
                OSC_Notifications.PlayerEvent(ownerPlayer, "osc_casino_closed", {
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

    SendOpen(player, hero, machine)
    OSC_Logger.Log("Opened casino for player " .. tostring(playerID)
        .. " on team " .. hero:GetTeamNumber())
end

function OSC_Casino.OnSpin(sourceIndex, event)
    local playerID = event and event.PlayerID
    if not playerID or not PlayerResource:IsValidPlayerID(playerID) then
        return
    end

    local player = PlayerResource:GetPlayer(playerID)
    if not player then
        return
    end

    local hero = PlayerResource:GetSelectedHeroEntity(playerID)
    local function SendResult(data)
        OSC_Notifications.PlayerEvent(player, "osc_casino_result", data)
    end

    if not hero or hero:GetUnitName() ~= "npc_dota_hero_ogre_magi" then
        SendResult({ error = "#osc_casino_err_not_ogre" })
        return
    end

    local machineIndex = event and tonumber(event.machine_entindex)
    if not machineIndex or machineIndex < 0 or machineIndex ~= math.floor(machineIndex) then
        SendResult({ error = "#osc_casino_err_bad_machine" })
        return
    end

    local machine = EntIndexToHScript(machineIndex)
    if not machine or machine:IsNull()
        or machine.osc_casino_owner_player_id ~= playerID
        or hero.osc_casino_machine ~= machine
        or (hero:GetAbsOrigin() - machine:GetAbsOrigin()):Length2D() > 450 then
        SendResult({ error = "#osc_casino_err_unavailable" })
        return
    end

    if machine.osc_casino_is_spinning then
        SendResult({ error = "#osc_casino_err_busy" })
        return
    end

    if GameRules:GetGameTime() < (machine.osc_casino_next_spin_time or 0) then
        SendResult({ error = "#osc_casino_err_cooldown" })
        return
    end

    local stake = event and tonumber(event.stake)
    local playerGold = PlayerResource:GetGold(playerID)
    if not stake or stake ~= math.floor(stake)
        or stake < OSC_CONFIG.CASINO_MIN_SPIN_COST
        or stake > playerGold then
        SendResult({
            error = "#osc_casino_err_stake",
            min_stake = OSC_CONFIG.CASINO_MIN_SPIN_COST,
            max_stake = playerGold,
            gold = playerGold,
        })
        return
    end

    local goldBefore = PlayerResource:GetGold(playerID)
    PlayerResource:SpendGold(playerID, stake, DOTA_ModifyGold_Unspecified)
    local goldAfter = PlayerResource:GetGold(playerID)
    local expectedGoldAfter = goldBefore - stake
    if goldAfter ~= expectedGoldAfter then
        local delta = expectedGoldAfter - goldAfter
        PlayerResource:ModifyGold(playerID, delta, false, DOTA_ModifyGold_Unspecified)
        local reason = "Casino stake validation failed for player "
            .. tostring(playerID)
            .. ": before=" .. tostring(goldBefore)
            .. ", expected_after=" .. tostring(expectedGoldAfter)
            .. ", actual_after=" .. tostring(goldAfter)
            .. ", delta=" .. tostring(delta)
        OSC_Logger.Error(reason)
        SendResult({
            error = "#osc_casino_err_settle",
            gold = PlayerResource:GetGold(playerID),
        })
        return
    end

    machine.osc_casino_is_spinning = true
    machine.osc_casino_stake_pending = true
    machine.osc_casino_next_spin_time = GameRules:GetGameTime() + 1
    local stakeRefunded = false
    local stakePending = true

    local function SetMachineSpinState(isSpinning)
        if not machine:IsNull() then
            machine.osc_casino_is_spinning = isSpinning
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
                    PlayerResource:ModifyGold(
                        playerID,
                        stake,
                        false,
                        DOTA_ModifyGold_Unspecified
                    )
                    stakePending = false
                    stakeRefunded = true
                    SetMachineSpinState(false)
                    return nil, "#osc_casino_err_hero_missing"
                end

                -- Refunds and payouts intentionally use unreliable gold so the
                -- slot machine remains a pure gamble while the initial stake is
                -- deducted from the combined balance via SpendGold().
                PlayerResource:ModifyGold(
                    playerID,
                    payout,
                    false,
                    DOTA_ModifyGold_Unspecified
                )
                stakePending = false
                SetMachineSpinState(false)
                return currentHero:GetGold()
            end)

            if not ok or failureReason then
                local reason = failureReason
                    or ("#osc_casino_err_settle")
                OSC_Logger.Error("Casino settlement failed: " .. tostring(reason))
                if stakePending then
                    PlayerResource:ModifyGold(
                        playerID,
                        stake,
                        false,
                        DOTA_ModifyGold_Unspecified
                    )
                    stakePending = false
                    stakeRefunded = true
                end
                SetMachineSpinState(false)
                SendResult({
                    error = reason,
                    gold = PlayerResource:GetGold(playerID),
                    stake_refunded = stakeRefunded,
                })
                return nil
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
