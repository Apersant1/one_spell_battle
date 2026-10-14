-- Выбор из трёх (часть системы ротации, флаг ROTATION_CHOICE_ENABLED).
--
-- Протокол с HUD (osc_rotation_choice.js):
--   сервер -> игрок  osc_rotation_choice_offer  { round, deadline, duration, options }
--   сервер -> игрок  osc_rotation_choice_closed { round, chosen }
--   игрок -> сервер  osc_rotation_choice_pick   { round, ability }
--   net table osc_state/choice_<playerID> = { round, deadline, duration, options, picked }
--     options = { [1] = { name, label, rarity }, ... }; после смены options = {},
--     picked — выданная способность; picked = "" — игрок ещё не выбрал.
--
-- Кандидаты лежат в состоянии героя: pending_choices =
--   { round, deadline, duration, options = { имена }, picked = имя | nil }.

require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/hero_state")
require("osc/core/client_commands")
require("osc/core/game_events")
require("osc/systems/ability_selection")

OSC_RotationChoice = OSC_RotationChoice or {}

local SLOT = "ability"

function OSC_RotationChoice.IsEnabled()
    return OSC_Config.Get("ROTATION_CHOICE_ENABLED") == true
end

local function NetTableKey(hero)
    return "choice_" .. hero:GetPlayerOwnerID()
end

local function ClientOptions(names)
    local options = {}
    for index, name in ipairs(names) do
        local entry = OSC_AbilitySelection.FindEntry(name)
        options[index] = {
            name = name,
            label = entry and entry.label or name,
            rarity = OSC_AbilitySelection.GetRarity(entry),
        }
    end
    return options
end

-- closedWith — итоговая способность закрытого предложения (options = {})
local function Publish(hero, pending, closedWith)
    CustomNetTables:SetTableValue("osc_state", NetTableKey(hero), {
        round = pending.round,
        deadline = pending.deadline,
        duration = pending.duration,
        options = closedWith and {} or ClientOptions(pending.options),
        picked = closedWith or pending.picked or "",
    })
end

local function SendToOwner(hero, eventName, data)
    local player = PlayerResource:GetPlayer(hero:GetPlayerOwnerID())
    if player then
        OSC_Notifications.PlayerEvent(player, eventName, data)
    end
end

-- Кандидаты основному герою на ротацию round, которая наступит в deadline.
-- Возвращает true, если предложение отправлено.
function OSC_RotationChoice.Offer(hero, round, deadline)
    local state = OSC_HeroState.Get(hero)
    if not OSC_Heroes.IsMainHero(hero) or not state.initialized or state.anchor_rotations > 0 then
        return false
    end

    local count = OSC_Config.Get("ROTATION_CHOICE_COUNT")
    if type(count) ~= "number" or count < 1 then
        error("[OSC] ROTATION_CHOICE_COUNT must be at least 1")
    end

    local names = {}
    for _, entry in ipairs(OSC_AbilitySelection.PickCandidates(hero, SLOT, math.floor(count))) do
        table.insert(names, entry.name)
    end

    local duration = math.max(0, deadline - GameRules:GetGameTime())
    local pending = {
        round = round,
        deadline = deadline,
        duration = duration,
        options = names,
    }
    state.pending_choices = pending

    SendToOwner(hero, "osc_rotation_choice_offer", {
        round = round,
        deadline = deadline,
        duration = duration,
        options = ClientOptions(names),
    })
    Publish(hero, pending)
    return true
end

function OSC_RotationChoice.OfferAll(round, deadline)
    if not OSC_RotationChoice.IsEnabled() then return end
    OSC_Heroes.ForEachPlayerHero(function(hero, playerID)
        local ok, err = pcall(OSC_RotationChoice.Offer, hero, round, deadline)
        if not ok then
            OSC_Logger.Error("Rotation choice offer for player " .. playerID .. ": " .. tostring(err))
        end
    end)
end

local function Contains(list, value)
    for _, item in ipairs(list or {}) do
        if item == value then
            return true
        end
    end
    return false
end

local function LogRefusal(senderKey, message)
    OSC_ClientCommands.LogRefusal("Rotation choice", senderKey, message)
end

-- Выбор игрока: принимается только вариант из выданного ему списка в
-- текущем раунде, пока предложение открыто (до смены способностей, а не до
-- deadline: часы клиента отстают на пинг). При отказе net table не
-- переписывается — иначе подделанный клиент вызывал бы поток репликаций;
-- HUD сам вернёт подсветку, сверяясь с picked.
function OSC_RotationChoice.OnPick(sourceIndex, event)
    local ok, cmd, reason = OSC_ClientCommands.Check(sourceIndex, event, {
        hero = true,
        args = { { name = "round", check = OSC_ClientCommands.Integer({ min = 0 }) } },
    })
    if not ok then
        LogRefusal(tostring(cmd.player_id or (event and event.PlayerID)), tostring(reason))
        return
    end

    local pending = OSC_HeroState.Get(cmd.hero).pending_choices
    local ability = event and event.ability
    local refusal
    if not pending then
        refusal = "no offer"
    elseif pending.round ~= cmd.args.round then
        refusal = "wrong round"
    elseif type(ability) ~= "string" or not Contains(pending.options, ability) then
        refusal = "not offered: " .. tostring(ability)
    end

    if refusal then
        LogRefusal(tostring(cmd.player_id), refusal)
        return
    end

    pending.picked = ability
    Publish(cmd.hero, pending)
end

-- Запись, которую герой получит на ротации round: выбранная игроком или
-- случайная из предложенных. nil — предложения не было (герой появился
-- после предупреждения, выбор выключен) или ни один вариант больше не годится:
-- тогда ротация выдаёт случайную способность как обычно.
function OSC_RotationChoice.TakeEntry(hero, round)
    local state = OSC_HeroState.Get(hero)
    local pending = state.pending_choices
    if not pending or pending.round ~= round then
        return nil
    end

    local pool = OSC_AbilitySelection.GetPool(SLOT)
    local function Valid(name)
        if not name or name == state[SLOT] then return nil end
        for _, entry in ipairs(pool) do
            if entry.name == name then
                return entry
            end
        end
        return nil
    end

    local picked = Valid(pending.picked)
    if picked then
        return picked
    end

    local valid = {}
    for _, name in ipairs(pending.options) do
        local entry = Valid(name)
        if entry then
            table.insert(valid, entry)
        end
    end
    if #valid == 0 then
        return nil
    end
    return valid[RandomInt(1, #valid)]
end

-- Закрывает предложение героя: игроку уходит osc_rotation_choice_closed с
-- итоговой способностью, в net table options = {}, picked = chosen.
-- Ничего не делает, если открытого предложения нет.
function OSC_RotationChoice.Close(hero, chosen)
    local state = OSC_HeroState.Get(hero)
    local pending = state.pending_choices
    if not pending then return end
    state.pending_choices = nil

    Publish(hero, pending, chosen or "")
    SendToOwner(hero, "osc_rotation_choice_closed", {
        round = pending.round,
        chosen = chosen or "",
    })
end

function OSC_RotationChoice.Init()
    CustomGameEventManager:RegisterListener("osc_rotation_choice_pick", function(sourceIndex, event)
        OSC_RotationChoice.OnPick(sourceIndex, event)
    end)
    -- «Якорь», купленный после предложения, отменяет выбор: способность
    -- останется текущей
    OSC_GameEvents.Subscribe("hero_anchored", "rotation_choice", function(hero)
        OSC_RotationChoice.Close(hero, OSC_HeroState.Get(hero).ability)
    end)
end
