require("osc/core/client_commands")

OSC_Casino = OSC_Casino or {}

-- Символы барабанов; исходы CASINO_OUTCOMES могут использовать только их
local SYMBOLS = { "circle", "diamond", "star", "seven" }

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
    if not hero:IsAlive() then
        return false, "osc_casino_err_dead"
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

-- Красная подсказка внизу экрана, как у стандартных ошибок Dota.
-- Сервер не может вызвать её напрямую: шлём своё событие, а клиент
-- (osc_casino.js, OnHudError) превращает его в стандартную ошибку HUD.
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
        item_bets = OSC_CONFIG.CASINO_ITEM_BETS ~= false,
        item_value_factor = OSC_CONFIG.CASINO_ITEM_VALUE_FACTOR or 0.5,
        gold = hero:GetGold(),
        lifetime = OSC_CONFIG.CASINO_MACHINE_LIFETIME,
        -- Анимацию продолжает только тот, кто сам крутит; остальные видят автомат свободным
        spinning = machine.osc_casino_is_spinning == true
            and machine.osc_casino_spinner_id == playerID,
    })
end

-- Проверяет таблицу исходов: целые шансы > 0, множители >= 0, известные
-- символы без повторов, сумма шансов не больше 100. При успехе вторым
-- значением возвращает ожидаемую выплату в долях ставки.
function OSC_Casino.ValidateOutcomes(outcomes)
    if type(outcomes) ~= "table" or #outcomes == 0 then
        return false, "no outcomes configured"
    end

    local known = {}
    for _, symbol in ipairs(SYMBOLS) do
        known[symbol] = true
    end

    local seen, totalChance, expected = {}, 0, 0
    for index, outcome in ipairs(outcomes) do
        local where = "outcome #" .. index
        local chance, multiplier = outcome.chance, outcome.multiplier
        if type(chance) ~= "number" or chance <= 0 or chance ~= math.floor(chance) then
            return false, where .. ": chance must be a positive integer"
        end
        if type(multiplier) ~= "number" or multiplier < 0 then
            return false, where .. ": multiplier must be a non-negative number"
        end
        if not known[outcome.symbol] then
            return false, where .. ": unknown symbol " .. tostring(outcome.symbol)
        end
        if seen[outcome.symbol] then
            return false, where .. ": duplicate symbol " .. outcome.symbol
        end
        seen[outcome.symbol] = true
        totalChance = totalChance + chance
        expected = expected + chance / 100 * multiplier
    end

    if totalChance > 100 then
        return false, "chances add up to " .. totalChance .. "%, must be at most 100"
    end
    return true, expected
end

function OSC_Casino.Init()
    local valid, result = OSC_Casino.ValidateOutcomes(OSC_CONFIG.CASINO_OUTCOMES)
    if valid then
        OSC_Logger.Log(string.format(
            "Casino expected payout %.2f of the stake (house edge %.0f%%)",
            result, (1 - result) * 100))
    else
        OSC_Logger.Error("Casino outcomes are invalid: " .. result)
    end

    -- Клиенту нужен радиус, чтобы рисовать зону действия по Alt
    CustomNetTables:SetTableValue("osc_state", "casino", {
        use_distance = OSC_CONFIG.CASINO_USE_DISTANCE or 450,
    })
    CustomGameEventManager:RegisterListener("osc_casino_spin", OSC_Casino.OnSpin)
    CustomGameEventManager:RegisterListener("osc_casino_reopen", OSC_Casino.OnReopen)
end

function OSC_Casino.OnReopen(sourceIndex, event)
    local ok, cmd = OSC_ClientCommands.Check(sourceIndex, event, {
        hero = true,
        args = { { name = "machine_entindex", check = OSC_ClientCommands.Integer() } },
    })
    if not ok then return end

    local playerID, hero = cmd.player_id, cmd.hero
    local machine = EntIndexToHScript(cmd.args.machine_entindex)
    local canUse, reason = CanUseMachine(hero, playerID, machine)
    if not canUse then
        -- Клиент повторяет запрос, пока герой идёт к автомату; такие повторы
        -- приходят с quiet = 1, и подсказку на них не показываем
        if tonumber(event.quiet) ~= 1 then
            OSC_Logger.Log("Casino reopen refused for player " .. tostring(playerID)
                .. ": " .. tostring(reason))
            ShowHudError(cmd.player, reason)
        end
        return
    end

    local player, ownerPlayerID = GetHeroPlayer(hero)
    if not player or ownerPlayerID ~= playerID then return end

    SendOpen(player, playerID, hero, machine)
end

-- Только для DEVELOPMENT_MODE: следующие спины всегда дают тройку этого символа
-- ("seven" — джекпот); nil — обычный случайный результат
function OSC_Casino.DebugForceSymbol(symbol)
    if symbol == nil then
        OSC_Casino.debug_forced_symbol = nil
        return true
    end
    for _, outcome in ipairs(OSC_CONFIG.CASINO_OUTCOMES) do
        if outcome.symbol == symbol then
            OSC_Casino.debug_forced_symbol = symbol
            return true
        end
    end
    return false, "unknown casino symbol: " .. tostring(symbol)
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
            ShowHudError(playerID and PlayerResource:GetPlayer(playerID), "osc_casino_err_spinning")
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

-- ================= Ставка предметом =================

-- Сколько золота стоит предмет как ставка: доля цены покупки, как при продаже
local function GetItemStakeValue(item)
    local factor = OSC_CONFIG.CASINO_ITEM_VALUE_FACTOR or 0.5
    return math.floor(item:GetCost() * factor)
end

-- Предмет можно поставить, только если он лежит в основном инвентаре героя,
-- куплен этим игроком и продаётся. Минимальная ставка проверяется по сумме
-- всех поставленных предметов. Возвращает предмет или nil и ключ ошибки.
local function ValidateStakeItem(hero, itemIndex)
    if OSC_CONFIG.CASINO_ITEM_BETS == false then
        return nil, "osc_casino_err_item_disabled"
    end

    local item = EntIndexToHScript(itemIndex)
    if not item or item:IsNull() or not item.IsItem or not item:IsItem() then
        return nil, "osc_casino_err_bad_item"
    end

    local inInventory = false
    for slot = 0, 5 do -- шесть основных слотов инвентаря
        if hero:GetItemInSlot(slot) == item then
            inInventory = true
            break
        end
    end
    if not inInventory then
        return nil, "osc_casino_err_bad_item"
    end

    if item:GetPurchaser() ~= hero then
        return nil, "osc_casino_err_item_not_yours"
    end
    if not item:IsSellable() or GetItemStakeValue(item) <= 0 then
        return nil, "osc_casino_err_item_unsellable"
    end
    return item
end

-- Индексы предметов из события: "12,34,56" (item_entindices) или один item_entindex
local function ParseItemIndices(event)
    local result = {}
    local seen = {}
    local raw = event and event.item_entindices
    if raw == nil and event and event.item_entindex ~= nil then
        raw = tostring(event.item_entindex)
    end
    for part in string.gmatch(tostring(raw or ""), "[^,]+") do
        local index = tonumber(part)
        if index and index >= 0 and index == math.floor(index) and not seen[index] then
            seen[index] = true
            table.insert(result, index)
        end
    end
    return result
end

function OSC_Casino.OnSpin(sourceIndex, event)
    local ok, cmd, refusal = OSC_ClientCommands.Check(sourceIndex, event, {
        hero = true,
        args = { { name = "machine_entindex", check = OSC_ClientCommands.Integer({ min = 0 }) } },
    })
    local player, playerID, hero = cmd.player, cmd.player_id, cmd.hero
    if not player then return end

    local function SendResult(data)
        OSC_Notifications.PlayerEvent(player, "osc_casino_result", data)
    end

    if not ok then
        SendResult({
            error = refusal == "no_hero" and "osc_casino_err_unavailable"
                or "osc_casino_err_bad_machine",
        })
        return
    end

    local machine = EntIndexToHScript(cmd.args.machine_entindex)
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

    -- Ставка золотом или предметами (item_entindices), предметы оцениваются
    -- по стоимости продажи и складываются
    local stake
    local stakeItems = {}
    local itemIndices = ParseItemIndices(event)
    if #itemIndices > 0 then
        if #itemIndices > 6 then
            SendResult({ error = "osc_casino_err_bad_item", gold = hero:GetGold() })
            return
        end
        stake = 0
        for _, itemIndex in ipairs(itemIndices) do
            local item, itemError = ValidateStakeItem(hero, itemIndex)
            if not item then
                SendResult({ error = itemError, gold = hero:GetGold() })
                return
            end
            table.insert(stakeItems, item)
            stake = stake + GetItemStakeValue(item)
        end
        if stake < OSC_CONFIG.CASINO_MIN_SPIN_COST then
            SendResult({ error = "osc_casino_err_item_cheap", gold = hero:GetGold() })
            return
        end
    else
        stake = event and tonumber(event.stake)
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
    end
    local stakeItemNames = {}
    for _, item in ipairs(stakeItems) do
        table.insert(stakeItemNames, item:GetAbilityName())
    end
    local isItemStake = #stakeItems > 0

    local spent = stake
    local reliableSpent = 0
    if isItemStake then
        -- Забираем предметы из инвентаря; до расчёта они хранятся «в автомате».
        -- Если какой-то не забрался — возвращаем уже взятые и отменяем спин.
        local taken = {}
        for _, item in ipairs(stakeItems) do
            local removed = hero:TakeItem(item)
            if not removed then
                for _, back in ipairs(taken) do
                    hero:AddItem(back)
                end
                SendResult({ error = "osc_casino_err_not_charged", gold = hero:GetGold() })
                return
            end
            table.insert(taken, removed)
        end
        stakeItems = taken
    else
        local goldBefore = PlayerResource:GetGold(playerID)
        local reliableBefore = PlayerResource:GetReliableGold(playerID)
        PlayerResource:SpendGold(playerID, stake, DOTA_ModifyGold_Unspecified)
        spent = goldBefore - PlayerResource:GetGold(playerID)
        reliableSpent = math.max(0, reliableBefore - PlayerResource:GetReliableGold(playerID))
    end

    local function ReturnGold(amount)
        local reliablePart = math.min(amount, reliableSpent)
        if reliablePart > 0 then
            PlayerResource:ModifyGold(playerID, reliablePart, true, DOTA_ModifyGold_Unspecified)
        end
        if amount > reliablePart then
            PlayerResource:ModifyGold(playerID, amount - reliablePart, false, DOTA_ModifyGold_Unspecified)
        end
    end

    -- Возвращает предметы-ставку герою; что не влезло — кладёт рядом с ним
    -- (или у автомата, если героя нет)
    local function GiveItemsBack()
        local owner = PlayerResource:GetSelectedHeroEntity(playerID)
        local ownerValid = owner and not owner:IsNull()
        for _, item in ipairs(stakeItems) do
            if not item:IsNull() and not (ownerValid and owner:AddItem(item)) then
                local position = ownerValid and owner:GetAbsOrigin()
                    or (not machine:IsNull() and machine:GetAbsOrigin())
                if position then
                    CreateItemOnPositionSync(position, item)
                end
            end
        end
        stakeItems = {}
    end

    local function RefundStake()
        if isItemStake then
            GiveItemsBack()
        else
            ReturnGold(stake)
        end
    end

    -- Выплата: золото по множителю. Предметы при ×1 возвращаются как есть,
    -- в остальных случаях сгорают (при выигрыше — вместо них золото)
    local function PayOut(payout, multiplier)
        if not isItemStake then
            ReturnGold(payout)
            return
        end
        if multiplier == 1 then
            GiveItemsBack()
            return
        end
        for _, item in ipairs(stakeItems) do
            if not item:IsNull() then
                UTIL_Remove(item)
            end
        end
        stakeItems = {}
        if payout > 0 then
            PlayerResource:ModifyGold(playerID, payout, false, DOTA_ModifyGold_Unspecified)
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
    local multiplier = 0
    local reels
    local forced = OSC_Casino.debug_forced_symbol
    for _, outcome in ipairs(OSC_CONFIG.CASINO_OUTCOMES) do
        -- Режим разработки: команда -casino <символ> подкручивает результат
        if (forced and outcome.symbol == forced)
            or (not forced and roll <= outcome.chance) then
            reels = { outcome.symbol, outcome.symbol, outcome.symbol }
            payout = stake * outcome.multiplier
            multiplier = outcome.multiplier
            break
        end
        roll = roll - outcome.chance
    end

    if not reels then
        local first = SYMBOLS[RandomInt(1, #SYMBOLS)]
        local second = SYMBOLS[RandomInt(1, #SYMBOLS)]
        local third = SYMBOLS[RandomInt(1, #SYMBOLS)]
        while first == second and second == third do
            third = SYMBOLS[RandomInt(1, #SYMBOLS)]
        end
        reels = { first, second, third }
    end

    GameRules:GetGameModeEntity():SetContextThink(
        "osc_casino_settle_" .. machine:entindex(),
        function()
            local ok, currentGold, failureReason = pcall(function()
                local currentHero = PlayerResource:GetSelectedHeroEntity(playerID)
                if not currentHero or currentHero:IsNull() then
                    RefundStake()
                    stakePending = false
                    stakeRefunded = true
                    SetMachineSpinState(false)
                    return nil, "hero is unavailable"
                end

                PayOut(payout, multiplier)
                stakePending = false
                SetMachineSpinState(false)
                return currentHero:GetGold()
            end)

            if not ok or failureReason then
                local reason = failureReason or tostring(currentGold)
                OSC_Logger.Error("Casino settlement failed: " .. reason)
                if stakePending then
                    RefundStake()
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
                multiplier = multiplier,
                items = isItemStake and table.concat(stakeItemNames, ",") or nil,
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