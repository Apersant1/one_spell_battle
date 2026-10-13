require("osc/core/heroes")
require("osc/core/game_events")

local COURIER_CONFIG = OSC_CONFIG.COURIERS

OSC_Couriers = OSC_Couriers or {}
OSC_Couriers.Abilities = OSC_COURIER_ABILITY_POOL

local function IsValidEntity(entity)
    return entity and not entity:IsNull()
end

local function GetTeamHeroes(team)
    local heroes = {}
    OSC_Heroes.ForEachPlayerHero(function(hero)
        if hero:GetTeamNumber() == team then
            table.insert(heroes, hero)
        end
    end)
    return heroes
end

local function HasInventorySpace(hero)
    for slot = COURIER_CONFIG.INVENTORY_FIRST_SLOT, COURIER_CONFIG.INVENTORY_LAST_SLOT do
        if not hero:GetItemInSlot(slot) then
            return true
        end
    end
    return false
end

local function FindStashItem(hero)
    for slot = COURIER_CONFIG.STASH_FIRST_SLOT, COURIER_CONFIG.STASH_LAST_SLOT do
        local item = hero:GetItemInSlot(slot)
        if IsValidEntity(item) then
            return item
        end
    end
end

local function FindTeamFountain(team)
    for _, fountain in pairs(Entities:FindAllByClassname("ent_dota_fountain") or {}) do
        if IsValidEntity(fountain) and fountain:GetTeamNumber() == team then
            return fountain
        end
    end
end

-- Места курьеров перед фонтаном: пары справа/слева, каждая следующая
-- пара на HOME_ROW_SPACING дальше вперёд
function OSC_Couriers.GetHomePositions(origin, forward, right, count)
    local positions = {}
    for index = 1, count do
        local row = math.floor((index - 1) / 2)
        local side = index % 2 == 1 and 1 or -1
        positions[index] = origin
            + forward * (COURIER_CONFIG.HOME_FORWARD_OFFSET + row * COURIER_CONFIG.HOME_ROW_SPACING)
            + right * (COURIER_CONFIG.HOME_SIDE_OFFSET * side)
    end
    return positions
end

local function IssueMoveOrder(courier, position)
    courier.osc_last_move_order_time = GameRules:GetGameTime()
    ExecuteOrderFromTable({
        UnitIndex = courier:entindex(),
        OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION,
        Position = position,
        Queue = false,
    })
end

local function ApplyCourierAbility(courier, ability, suppressAnnouncement)
    local baseMoveSpeed = courier:GetBaseMoveSpeed()
    local modifier = courier:AddNewModifier(courier, nil, ability.modifier, {
        duration = ability.duration,
        slow_pct = ability.slow_pct,
        base_move_speed = baseMoveSpeed,
    })
    if not modifier or modifier:IsNull() then
        OSC_Logger.Error("Failed to apply courier modifier: " .. ability.modifier)
        return false
    end

    courier.osc_next_ability_time = GameRules:GetGameTime()
        + RandomInt(ability.interval_min, ability.interval_max)
    if not suppressAnnouncement then
        OSC_Notifications.CourierAbilityGained(
            courier:GetTeamNumber(),
            ability,
            ability.duration
        )
    end
    return true
end

local function StartDrunkAbility(courier)
    local abilities = OSC_Couriers.Abilities
    if #abilities == 0 then
        return
    end

    ApplyCourierAbility(courier, abilities[RandomInt(1, #abilities)])
end

-- Случайный живой союзник, кроме владельца предмета, у которого есть место
local function PickWrongRecipient(owner)
    local candidates = {}
    for _, teammate in ipairs(GetTeamHeroes(owner:GetTeamNumber())) do
        if teammate ~= owner and teammate:IsAlive() and HasInventorySpace(teammate) then
            table.insert(candidates, teammate)
        end
    end
    if #candidates == 0 then
        return nil
    end
    return candidates[RandomInt(1, #candidates)]
end

local function StartDelivery(courier, hero, item)
    local owner = hero
    -- Заблудший курьер везёт предмет не тому; если некому — везёт владельцу
    if courier:HasModifier("modifier_osc_courier_lost") then
        hero = PickWrongRecipient(owner) or owner
    end

    local removedItem = owner:TakeItem(item)
    if not removedItem then
        return false
    end

    local courierItem = courier:AddItem(removedItem)
    if not courierItem then
        owner:AddItem(removedItem)
        OSC_Logger.Error("Failed to move stash item into courier inventory")
        return false
    end

    courier.osc_delivery_hero = hero
    courier.osc_delivery_item = courierItem
    courier.osc_delivery_player_id = hero:GetPlayerOwnerID()
    courier.osc_delivery_owner = hero ~= owner and owner or nil
    courier.osc_returning_home = nil
    IssueMoveOrder(courier, hero:GetAbsOrigin())
    return true
end

local function FinishDelivery(courier, hero)
    local item = courier.osc_delivery_item
    if not IsValidEntity(item) then
        OSC_Logger.Error("Cannot finish courier delivery: item is unavailable")
        return false
    end

    local removedItem = courier:TakeItem(item)
    if not removedItem then
        OSC_Logger.Error("Failed to remove delivered item from courier")
        return false
    end

    local heroItem = hero:AddItem(removedItem)
    if not heroItem then
        courier:AddItem(removedItem)
        OSC_Logger.Error("Failed to add delivered item to hero inventory")
        return false
    end

    local owner = courier.osc_delivery_owner
    courier.osc_delivery_owner = nil
    if owner and not owner:IsNull() and owner ~= hero then
        OSC_Notifications.Notify("courier_wrong_delivery", {
            team = hero:GetTeamNumber(),
            owner = "#" .. owner:GetUnitName(),
            recipient = "#" .. hero:GetUnitName(),
            item = "#DOTA_Tooltip_Ability_" .. heroItem:GetAbilityName(),
        })
    end

    courier.osc_delivery_hero = nil
    courier.osc_delivery_item = nil
    courier.osc_delivery_player_id = nil
    courier.osc_returning_home = true
    IssueMoveOrder(courier, courier.osc_home_position)
    return true
end

local function ThinkReturnHome(courier, now)
    local home = courier.osc_home_position
    if not home then
        OSC_Logger.Error("Courier has no assigned home position")
        return
    end

    if (courier:GetAbsOrigin() - home):Length2D()
        <= COURIER_CONFIG.FOUNTAIN_ARRIVAL_DISTANCE then
        courier.osc_returning_home = nil
        return
    end

    if now - (courier.osc_last_move_order_time or 0) >= COURIER_CONFIG.MOVE_ORDER_INTERVAL then
        IssueMoveOrder(courier, home)
    end
end

local function ThinkCourier(courier)
    if not IsValidEntity(courier) then
        return nil
    end
    -- Мёртвый курьер ничего не берёт и не везёт; доставка продолжится после возрождения
    if not courier:IsAlive() then
        return COURIER_CONFIG.THINK_INTERVAL
    end

    local now = GameRules:GetGameTime()
    if courier.osc_next_ability_time and now >= courier.osc_next_ability_time then
        StartDrunkAbility(courier)
    end

    local item = courier.osc_delivery_item
    if item and not IsValidEntity(item) then
        courier.osc_delivery_item = nil
        courier.osc_delivery_hero = nil
        courier.osc_delivery_player_id = nil
        item = nil
    end

    if IsValidEntity(item) then
        local hero = courier.osc_delivery_hero
        if not IsValidEntity(hero) and PlayerResource:IsValidPlayerID(courier.osc_delivery_player_id) then
            hero = PlayerResource:GetSelectedHeroEntity(courier.osc_delivery_player_id)
            courier.osc_delivery_hero = hero
        end

        if IsValidEntity(hero) and hero:GetTeamNumber() == courier:GetTeamNumber()
            and hero:IsAlive() and HasInventorySpace(hero) then
            courier.osc_returning_home = nil
            if (courier:GetAbsOrigin() - hero:GetAbsOrigin()):Length2D()
                <= COURIER_CONFIG.HERO_DELIVERY_DISTANCE then
                FinishDelivery(courier, hero)
            elseif now - (courier.osc_last_move_order_time or 0)
                >= COURIER_CONFIG.MOVE_ORDER_INTERVAL then
                IssueMoveOrder(courier, hero:GetAbsOrigin())
            end
        else
            courier.osc_delivery_hero = nil
            courier.osc_returning_home = true
            ThinkReturnHome(courier, now)
        end
        return COURIER_CONFIG.THINK_INTERVAL
    end

    if courier.osc_returning_home then
        ThinkReturnHome(courier, now)
        return COURIER_CONFIG.THINK_INTERVAL
    end

    courier.osc_delivery_hero = nil
    do
        for _, teammate in ipairs(GetTeamHeroes(courier:GetTeamNumber())) do
            if HasInventorySpace(teammate) then
                local item = FindStashItem(teammate)
                if item and StartDelivery(courier, teammate, item) then
                    break
                end
            end
        end
    end

    return COURIER_CONFIG.THINK_INTERVAL
end

local function InitializeCourier(courier, homePosition)
    if courier.osc_courier_ai_initialized then
        return
    end

    courier.osc_courier_ai_initialized = true
    courier.osc_home_position = homePosition
    courier.osc_next_ability_time = GameRules:GetGameTime()
        + RandomInt(
            COURIER_CONFIG.INITIAL_ABILITY_INTERVAL_MIN,
            COURIER_CONFIG.INITIAL_ABILITY_INTERVAL_MAX
        )

    FindClearSpaceForUnit(courier, homePosition, true)
    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            courier:SetControllableByPlayer(playerID, false)
        end
    end

    courier:SetContextThink(
        "osc_courier_ai",
        function()
            return ThinkCourier(courier)
        end,
        COURIER_CONFIG.THINK_INTERVAL
    )
end

function OSC_Couriers.EnsureTeamCouriers(hero)
    local team = hero:GetTeamNumber()
    if team ~= DOTA_TEAM_GOODGUYS and team ~= DOTA_TEAM_BADGUYS then
        return
    end

    local fountain = FindTeamFountain(team)
    if not fountain then
        OSC_Logger.Error(
            "Could not find fountain for team " .. team .. "; couriers were not initialized"
        )
        return false
    end

    local homePositions = OSC_Couriers.GetHomePositions(
        fountain:GetAbsOrigin(),
        fountain:GetForwardVector(),
        fountain:GetRightVector(),
        COURIER_CONFIG.COUNT_PER_TEAM
    )
    local couriers = {}
    for _, courier in pairs(Entities:FindAllByClassname("npc_dota_courier") or {}) do
        if IsValidEntity(courier) and courier:GetTeamNumber() == team then
            table.insert(couriers, courier)
        end
    end

    for i = #couriers + 1, COURIER_CONFIG.COUNT_PER_TEAM do
        local courier = CreateUnitByName(
            "npc_dota_courier",
            homePositions[i],
            true,
            nil,
            nil,
            team
        )
        if not courier then
            OSC_Logger.Error("Failed to create team courier for team " .. team)
            return false
        end

        table.insert(couriers, courier)
    end

    for index = 1, math.min(#couriers, COURIER_CONFIG.COUNT_PER_TEAM) do
        InitializeCourier(couriers[index], homePositions[index])
    end
    return true
end

-- Курьеры команды запускаются, когда у неё появляется первый настоящий герой.
-- Если не вышло (нет фонтана), пробуем снова при следующем появлении.
local function OnHeroSpawned(unit)
    if not OSC_Heroes.IsMainHero(unit) then
        return
    end

    local team = unit:GetTeamNumber()
    if OSC_Couriers.ready_teams[team] then
        return
    end
    if OSC_Couriers.EnsureTeamCouriers(unit) then
        OSC_Couriers.ready_teams[team] = true
    end
end

function OSC_Couriers.Init()
    OSC_Couriers.ready_teams = {}
    OSC_GameEvents.Subscribe("hero_spawned", "couriers", OnHeroSpawned)
end

function OSC_Couriers.DebugAbility(team, abilityName)
    local ability
    for _, candidate in ipairs(OSC_Couriers.Abilities) do
        if candidate.name == abilityName then
            ability = candidate
            break
        end
    end
    if not ability then
        return false, "Unknown courier ability: " .. tostring(abilityName)
    end

    local appliedCount = 0
    for _, courier in pairs(Entities:FindAllByClassname("npc_dota_courier") or {}) do
        if IsValidEntity(courier) and courier:GetTeamNumber() == team then
            if not courier.osc_courier_ai_initialized and courier.osc_home_position then
                InitializeCourier(courier, courier.osc_home_position)
            end
            if not ApplyCourierAbility(courier, ability, true) then
                return false, "Could not apply courier ability: " .. ability.name
            end
            appliedCount = appliedCount + 1
        end
    end

    if appliedCount > 0 then
        OSC_Notifications.CourierAbilityGained(
            team,
            ability,
            ability.duration
        )
        return true, appliedCount
    end

    return false, "No courier found for team " .. tostring(team)
end