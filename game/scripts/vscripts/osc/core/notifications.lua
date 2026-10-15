require("osc/config/notifications")

OSC_Notifications = OSC_Notifications or {}

local FEED_EVENT = "osc_notification"

-- Служебные поля params, которые не уходят клиенту как подстановки
local SERVICE_KEYS = { player = true, unit = true, team = true, hud = true }

-- ================= Вспомогательное =================

local function GetConfig()
    return OSC_NOTIFICATIONS_CONFIG or {}
end

local function IsChannelEnabled(channel)
    local channels = GetConfig().channels
    return not channels or channels[channel] ~= false
end

local function IsTypeEnabled(def)
    local config = GetConfig()
    if config.enabled == false or def.enabled == false then return false end

    local category = config.categories and config.categories[def.category]
    return not (category and category.enabled == false)
end

-- Оставляет только строки и числа: сущности и таблицы по сети не передать
local function BuildClientParams(params)
    local result = {}
    for key, value in pairs(params) do
        local valueType = type(value)
        if not SERVICE_KEYS[key] and (valueType == "string" or valueType == "number") then
            result[key] = tostring(value)
        end
    end
    return result
end

-- ================= Каналы доставки =================

local Channels = {}

function Channels.feed(settings, params)
    local data = {
        token = settings.token,
        color = settings.color,
        params = BuildClientParams(params),
    }

    if settings.scope == "team" then
        if params.team == nil then
            OSC_Logger.Error("Feed notification '" .. tostring(settings.token) .. "' needs params.team")
            return
        end

        for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
            if PlayerResource:IsValidPlayerID(playerID)
                and PlayerResource:GetTeam(playerID) == params.team then
                local player = PlayerResource:GetPlayer(playerID)
                if player then
                    CustomGameEventManager:Send_ServerToPlayer(player, FEED_EVENT, data)
                end
            end
        end
    else
        CustomGameEventManager:Send_ServerToAllClients(FEED_EVENT, data)
    end
end

function Channels.hud(settings, params)
    local playerID = params.player_id
    if playerID == nil or not PlayerResource:IsValidPlayerID(playerID) then
        OSC_Logger.Error("Cannot send HUD notification '" .. tostring(settings.event) .. "': invalid player ID")
        return
    end

    local player = PlayerResource:GetPlayer(playerID)
    if not player then
        OSC_Logger.Error("Cannot send HUD notification '" .. tostring(settings.event) .. "': player is unavailable")
        return
    end

    local data = params.hud or {}
    data.player_id = playerID
    CustomGameEventManager:Send_ServerToPlayer(player, settings.event, data)
end

function Channels.particle(settings, params)
    if not params.unit then return end
    local particle = ParticleManager:CreateParticle(
        settings.name,
        settings.attach or PATTACH_ABSORIGIN_FOLLOW,
        params.unit
    )
    ParticleManager:ReleaseParticleIndex(particle)
end

local CHANNEL_ORDER = { "particle", "hud", "feed" }

-- ================= Публичный API =================

-- params: подстановки для текста плюс служебные поля:
--   player_id — ID игрока (для hud)
--   unit   — юнит (для particle)
--   team   — команда (для адресной feed-доставки)
--   hud    — таблица данных для hud-события
function OSC_Notifications.Notify(typeName, params)
    params = params or {}

    local types = GetConfig().types or {}
    local def = types[typeName]
    if not def then
        OSC_Logger.Error("Unknown notification type '" .. tostring(typeName) .. "'")
        return false
    end

    if not IsTypeEnabled(def) then return false end

    for _, channel in ipairs(CHANNEL_ORDER) do
        local settings = def[channel]
        if settings and IsChannelEnabled(channel) then
            Channels[channel](settings, params)
        end
    end
    return true
end

function OSC_Notifications.PlayerEvent(player, eventName, data)
    if not player then
        OSC_Logger.Error("Cannot send event '" .. eventName .. "': player is unavailable")
        return false
    end
    CustomGameEventManager:Send_ServerToPlayer(player, eventName, data)
    return true
end

-- Красная подсказка внизу экрана, как у стандартных ошибок Dota; token —
-- ключ локализации. Сервер не может вызвать её напрямую: шлём своё событие,
-- клиент (OSC.HudError, shared/osc_core.ts) показывает стандартную ошибку.
-- Игрока нет (отключился) — подсказку просто не показываем
function OSC_Notifications.HudError(player, token)
    if player then
        CustomGameEventManager:Send_ServerToPlayer(player, "osc_hud_error", { message = token })
    end
end

-- ================= Обёртки для существующего кода =================

-- rarity — редкость записи (OSC_AbilitySelection.GetRarity) для рамки
-- всплывающего окна; по умолчанию "common"
function OSC_Notifications.AbilityChanged(hero, entry, rarity)
    local playerID = hero:GetPlayerOwnerID()
    OSC_Notifications.Notify("ability_changed", {
        unit = hero,
        team = hero:GetTeamNumber(),
        player_id = playerID,
        ability = "#DOTA_Tooltip_Ability_" .. entry.name,
        hud = { ability = entry.name, label = entry.label, rarity = rarity or "common" },
    })
end

-- Герой получил легендарную способность: объявление всем игрокам
function OSC_Notifications.LegendaryAbility(hero, entry)
    OSC_Notifications.Notify("legendary_ability", {
        unit = hero,
        player_id = hero:GetPlayerOwnerID(),
        ability = "#DOTA_Tooltip_Ability_" .. entry.name,
    })
end

function OSC_Notifications.RotationWarning(seconds)
    OSC_Notifications.Notify("rotation_warning", { seconds = seconds })
end

function OSC_Notifications.RotationStarted()
    OSC_Notifications.Notify("rotation_started")
end

function OSC_Notifications.ChaosRoundWarning(eventTitle, seconds)
    OSC_Notifications.Notify("chaos_round_warning", {
        name = "#" .. eventTitle,
        seconds = seconds,
    })
end

function OSC_Notifications.ChaosRoundStarted(eventName, duration)
    OSC_Notifications.Notify("chaos_round_started", { name = eventName, duration = duration })
end

function OSC_Notifications.ChaosRoundEnded(eventName)
    OSC_Notifications.Notify("chaos_round_ended", { name = eventName })
end

-- Итог голосования в лобби. Числа подставляются как есть, остальные
-- значения — ключами osc_notify_vote_<вопрос>_<вариант>
function OSC_Notifications.VoteResult(result)
    local params = {}
    for questionId, value in pairs(result or {}) do
        if tonumber(value) then
            params[questionId] = value
        else
            params[questionId] = "#osc_notify_vote_" .. questionId .. "_" .. value
        end
    end
    OSC_Notifications.Notify("vote_result", params)
end

function OSC_Notifications.CourierAbilityGained(team, ability, duration)
    OSC_Notifications.Notify("courier_ability_gained", {
        team = team,
        ability = "#" .. (ability.name_token or ("DOTA_Tooltip_" .. ability.modifier)),
        duration = duration,
    })
end
