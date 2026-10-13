-- Голосование в лобби (флаг VOTE_ENABLED, вопросы — VOTE_QUESTIONS).
-- Открыто с входа в DOTA_GAMERULES_STATE_HERO_SELECTION и всё время
-- стратегии (STRATEGY_TIME, TEAM_SHOWCASE, WAIT_FOR_MAP_TO_LOAD);
-- закрывается на первой стадии >= PRE_GAME (в том числе если стадии
-- перескочили) — до game_started. Итог пишется в рантайм-переопределения
-- OSC_Config (исходный конфиг не меняется) и публикуется в шину событием
-- config_overrides_applied { overrides }: системы, которые уже применили
-- значения (например, выданное казино), пересинхронизируются по нему.
-- Ротация и хаос-раунды стартуют на game_started и читают итог сразу.
--
-- Протокол с HUD:
--   net table osc_state/vote = { open = 1|0,
--     questions = { [i] = { id, options = { [j] = "<value>" }, default } },
--     counts = { <id> = { ["<value>"] = n } }, result = { <id> = "<value>" } }
--     result пуст, пока голосование открыто. Счётчики публикуются не чаще
--     раза в VOTE_PUBLISH_INTERVAL секунд, итог при закрытии — сразу.
--   net table osc_state/vote_<playerID> = { <id> = "<value>" | "" }
--   клиент -> сервер osc_vote_cast { question, option } — голос можно
--     менять; отказ и повтор того же голоса молчаливые, net table не меняется.

require("osc/core/runtime_config")
require("osc/core/client_commands")
require("osc/core/game_events")

OSC_Vote = OSC_Vote or {
    open = false,
    closed = false,
    votes = {}, -- playerID -> { question id -> value }
    result = nil,
}

local function Questions()
    return OSC_Config.Get("VOTE_QUESTIONS") or {}
end

function OSC_Vote.IsEnabled()
    return OSC_Config.Get("VOTE_ENABLED") == true
end

local function FindQuestion(id)
    for _, question in ipairs(Questions()) do
        if question.id == id then
            return question
        end
    end
end

local function OptionValues(question)
    local values = {}
    for index, option in ipairs(question.options) do
        values[index] = option.value
    end
    return values
end

local function FindOption(question, value)
    for _, option in ipairs(question.options) do
        if option.value == value then
            return option
        end
    end
end

-- Голоса существующих игроков по вариантам
function OSC_Vote.Counts()
    local counts = {}
    for _, question in ipairs(Questions()) do
        local perOption = {}
        for _, option in ipairs(question.options) do
            perOption[option.value] = 0
        end
        counts[question.id] = perOption
    end
    for playerID, ballot in pairs(OSC_Vote.votes) do
        if PlayerResource:IsValidPlayerID(playerID) then
            for questionId, value in pairs(ballot) do
                local perOption = counts[questionId]
                if perOption and perOption[value] ~= nil then
                    perOption[value] = perOption[value] + 1
                end
            end
        end
    end
    return counts
end

-- Итог по каждому вопросу: единственный лидер, иначе (ничья, нет голосов)
-- значение по умолчанию из конфига
function OSC_Vote.Tally()
    local counts = OSC_Vote.Counts()
    local result = {}
    for _, question in ipairs(Questions()) do
        local best, bestCount, tie = nil, 0, false
        for _, option in ipairs(question.options) do
            local count = counts[question.id][option.value]
            if count > bestCount then
                best, bestCount, tie = option.value, count, false
            elseif count == bestCount and count > 0 then
                tie = true
            end
        end
        result[question.id] = (best and not tie) and best or question.default
    end
    return result
end

local function PublishVote()
    local questions = {}
    for index, question in ipairs(Questions()) do
        questions[index] = {
            id = question.id,
            options = OptionValues(question),
            default = question.default,
        }
    end
    CustomNetTables:SetTableValue("osc_state", "vote", {
        open = OSC_Vote.open and 1 or 0,
        questions = questions,
        counts = OSC_Vote.Counts(),
        result = OSC_Vote.result or {},
    })
end

local function PublishBallot(playerID)
    local ballot = OSC_Vote.votes[playerID] or {}
    local data = {}
    for _, question in ipairs(Questions()) do
        data[question.id] = ballot[question.id] or ""
    end
    CustomNetTables:SetTableValue("osc_state", "vote_" .. playerID, data)
end

-- Счётчики меняются с каждым голосом: публикуем их пачкой не чаще раза в
-- VOTE_PUBLISH_INTERVAL. Think разовый — после публикации завершается сам.
function OSC_Vote.FlushPublish()
    OSC_Vote.publish_scheduled = false
    if OSC_Vote.dirty then
        OSC_Vote.dirty = false
        PublishVote()
    end
    return nil
end

local function MarkDirty()
    OSC_Vote.dirty = true
    local interval = OSC_Config.Get("VOTE_PUBLISH_INTERVAL") or 0
    if interval <= 0 then
        OSC_Vote.FlushPublish()
        return
    end
    if OSC_Vote.publish_scheduled then return end
    OSC_Vote.publish_scheduled = true
    GameRules:GetGameModeEntity():SetContextThink("osc_vote_publish", function()
        return OSC_Vote.FlushPublish()
    end, interval)
end

function OSC_Vote.Open()
    if not OSC_Vote.IsEnabled() or OSC_Vote.open or OSC_Vote.closed then
        return false
    end
    OSC_Vote.open = true
    OSC_Vote.votes = {}
    OSC_Vote.result = nil
    PublishVote()
    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            PublishBallot(playerID)
        end
    end
    OSC_Logger.Log("Lobby vote opened")
    return true
end

-- Закрывает голосование и применяет итог через OSC_Config.SetOverride
function OSC_Vote.Close()
    if not OSC_Vote.open then
        return false
    end
    OSC_Vote.open = false
    OSC_Vote.closed = true
    OSC_Vote.result = OSC_Vote.Tally()

    for _, question in ipairs(Questions()) do
        local value = OSC_Vote.result[question.id]
        local option = FindOption(question, value)
        for path, overrideValue in pairs(option and option.overrides or {}) do
            local ok, err = pcall(OSC_Config.SetOverride, path, overrideValue)
            if not ok then
                OSC_Logger.Error("Vote result " .. question.id .. "=" .. tostring(value)
                    .. " not applied: " .. tostring(err))
            end
        end
        OSC_Logger.Log("Lobby vote: " .. question.id .. " = " .. tostring(value))
    end

    -- Финальная публикация обязательна и сразу, отложенная больше не нужна
    OSC_Vote.dirty = false
    PublishVote()

    local overrides = {}
    for _, question in ipairs(Questions()) do
        local option = FindOption(question, OSC_Vote.result[question.id])
        for path, overrideValue in pairs(option and option.overrides or {}) do
            overrides[path] = overrideValue
        end
    end
    OSC_GameEvents.Emit("config_overrides_applied", { overrides = overrides })

    local ok, err = pcall(OSC_Notifications.VoteResult, OSC_Vote.result)
    if not ok then
        OSC_Logger.Error("Vote result notification failed: " .. tostring(err))
    end
    return true
end

-- Голос игрока. Принимается только существующий вопрос и вариант, пока
-- голосование открыто. Героя на этой стадии может не быть.
function OSC_Vote.OnCast(sourceIndex, event)
    local questionIds = {}
    for index, question in ipairs(Questions()) do
        questionIds[index] = question.id
    end

    local ok, cmd, reason = OSC_ClientCommands.Check(sourceIndex, event, {
        args = { { name = "question", check = OSC_ClientCommands.OneOf(questionIds) } },
    })
    if not ok then
        OSC_ClientCommands.LogRefusal("Vote", cmd.player_id or (event and event.PlayerID), reason)
        return
    end
    if not OSC_Vote.open then
        OSC_ClientCommands.LogRefusal("Vote", cmd.player_id, "vote is closed")
        return
    end

    local question = FindQuestion(cmd.args.question)
    local option = event.option
    if type(option) ~= "string" or not FindOption(question, option) then
        OSC_ClientCommands.LogRefusal("Vote", cmd.player_id, "unknown option " .. tostring(option))
        return
    end

    local ballot = OSC_Vote.votes[cmd.player_id] or {}
    OSC_Vote.votes[cmd.player_id] = ballot
    if ballot[question.id] == option then
        return -- тот же голос: ничего не изменилось
    end
    ballot[question.id] = option
    PublishBallot(cmd.player_id)
    MarkDirty()
end

function OSC_Vote.OnStateChanged(change)
    local state = change.state
    if state >= DOTA_GAMERULES_STATE_PRE_GAME then
        if OSC_Vote.open then
            OSC_Vote.Close()
        end
    elseif state >= DOTA_GAMERULES_STATE_HERO_SELECTION then
        OSC_Vote.Open()
    end
end

-- Проверка VOTE_QUESTIONS: список ошибок (пустой — всё в порядке)
function OSC_Vote.ValidateQuestions()
    local errors, ids = {}, {}
    for index, question in ipairs(Questions()) do
        local where = "VOTE_QUESTIONS[" .. index .. "]"
        if type(question.id) ~= "string" or ids[question.id] then
            table.insert(errors, where .. ": missing or duplicate id")
        end
        ids[question.id or ""] = true
        local values = {}
        for _, option in ipairs(question.options or {}) do
            if type(option.value) ~= "string" or values[option.value] then
                table.insert(errors, where .. ": option value must be a unique string")
            end
            values[option.value or ""] = true
            for path, value in pairs(option.overrides or {}) do
                local base = OSC_Config.GetBase(path)
                if base == nil or type(base) ~= type(value) then
                    table.insert(errors, where .. ": bad override " .. tostring(path))
                end
            end
        end
        if not values[question.default] then
            table.insert(errors, where .. ": default " .. tostring(question.default) .. " is not an option")
        end
    end
    return errors
end

function OSC_Vote.Init()
    for _, message in ipairs(OSC_Vote.ValidateQuestions()) do
        OSC_Logger.Error("Vote config: " .. message)
    end
    CustomGameEventManager:RegisterListener("osc_vote_cast", function(sourceIndex, event)
        OSC_Vote.OnCast(sourceIndex, event)
    end)
    OSC_GameEvents.Subscribe("game_state_changed", "vote", function(change)
        OSC_Vote.OnStateChanged(change)
    end)
end
