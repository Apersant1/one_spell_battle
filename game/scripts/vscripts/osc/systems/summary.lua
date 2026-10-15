-- Итоги матча (флаг SUMMARY_ENABLED): по событию шины match_stats (его
-- присылает stats при разрушении трона, поэтому нужен и STATS_ENABLED) собирает
-- net table osc_state/summary для экрана итогов:
--   { players = { ["<playerID>"] = { hero, rotations, distinct_kill_abilities,
--       kills, casino_net, chaos_damage } },
--     titles = { [i] = { id, player_id, value } } }
--
-- Титулы (порядок — SUMMARY_TITLES в конфиге):
--   gambler — худший casino_net, только если он отрицательный;
--   lucky — лучший casino_net, только если положительный;
--   chaos_master — больше всего убийств разными способностями;
--   collector — больше всего разных полученных способностей;
--   storm_chaser — больше всего урона во время хаос-раундов.
-- Титул выдаётся, только если |value| >= SUMMARY_TITLE_MIN[id] (0 и нет
-- данных — никогда). При равенстве лучших — SUMMARY_TITLE_TIES: "none" —
-- титул не выдаётся, "lowest_player_id" — игроку с меньшим playerID.

require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/game_events")

OSC_Summary = OSC_Summary or { published = false }

function OSC_Summary.IsEnabled()
    return OSC_Config.Get("SUMMARY_ENABLED") == true
end

local function CountKeys(map)
    local count = 0
    for _ in pairs(map or {}) do
        count = count + 1
    end
    return count
end

local function CountDistinct(list)
    local seen = {}
    for _, name in ipairs(list or {}) do
        seen[name] = true
    end
    return CountKeys(seen)
end

-- Строка игрока для net table и значения для титулов
local function BuildPlayer(playerID, stats)
    stats = stats or {}
    local hero = OSC_Heroes.GetPlayerHero(playerID)
    local abilities = stats.abilities or {}
    return {
        hero = (hero and hero:GetUnitName()) or stats.hero or "",
        rotations = stats.rotations or 0,
        distinct_kill_abilities = CountKeys(stats.kill_abilities),
        kills = stats.kills or 0,
        casino_net = math.floor(stats.casino_net or 0),
        chaos_damage = math.floor(stats.chaos_damage or 0),
    }, CountDistinct(abilities)
end

-- Значение игрока для титула; better(a, b) — a лучше b
local TITLE_RULES = {
    gambler = {
        value = function(row) return row.casino_net end,
        better = function(a, b) return a < b end,
        qualifies = function(value, min) return value < 0 and -value >= min end,
    },
    lucky = {
        value = function(row) return row.casino_net end,
        better = function(a, b) return a > b end,
        qualifies = function(value, min) return value > 0 and value >= min end,
    },
    chaos_master = {
        value = function(row) return row.distinct_kill_abilities end,
        better = function(a, b) return a > b end,
        qualifies = function(value, min) return value > 0 and value >= min end,
    },
    collector = {
        value = function(_, extra) return extra.distinct_abilities end,
        better = function(a, b) return a > b end,
        qualifies = function(value, min) return value > 0 and value >= min end,
    },
    storm_chaser = {
        value = function(row) return row.chaos_damage end,
        better = function(a, b) return a > b end,
        qualifies = function(value, min) return value > 0 and value >= min end,
    },
}

-- Титулы по строкам игроков. rows/extras — по playerID (числу).
function OSC_Summary.Titles(rows, extras)
    local ids = {}
    for playerID in pairs(rows) do
        table.insert(ids, playerID)
    end
    table.sort(ids) -- при lowest_player_id из равных побеждает первый

    local titles = {}
    local minimums = OSC_Config.Get("SUMMARY_TITLE_MIN")
    local ties = OSC_Config.Get("SUMMARY_TITLE_TIES")
    for _, titleId in ipairs(OSC_Config.Get("SUMMARY_TITLES")) do
        local rule = TITLE_RULES[titleId]
        if not rule then
            OSC_Logger.Error("Unknown summary title: " .. tostring(titleId))
        else
            local bestID, bestValue, tied
            for _, playerID in ipairs(ids) do
                local value = rule.value(rows[playerID], extras[playerID] or {})
                if bestValue == nil or rule.better(value, bestValue) then
                    bestID, bestValue, tied = playerID, value, false
                elseif value == bestValue then
                    tied = true
                end
            end
            local min = minimums[titleId] or 1
            local tieAllowed = not tied or ties == "lowest_player_id"
            if bestID ~= nil and tieAllowed and rule.qualifies(bestValue, min) then
                table.insert(titles, { id = titleId, player_id = bestID, value = bestValue })
            end
        end
    end
    return titles
end

-- Собирает и публикует итоги. statsPlayers — из события match_stats.
function OSC_Summary.Publish(statsPlayers)
    if not OSC_Summary.IsEnabled() or OSC_Summary.published then return false end
    OSC_Summary.published = true

    local rows, extras = {}, {}
    local function Add(playerID)
        if rows[playerID] then return end
        local row, distinct = BuildPlayer(playerID, statsPlayers[playerID])
        rows[playerID] = row
        extras[playerID] = { distinct_abilities = distinct }
    end
    for playerID in pairs(statsPlayers or {}) do
        if PlayerResource:IsValidPlayerID(playerID) then
            Add(playerID)
        end
    end
    -- Игроки без единого события тоже есть в итогах (с нулями)
    for playerID = 0, DOTA_MAX_TEAM_PLAYERS - 1 do
        if PlayerResource:IsValidPlayerID(playerID) then
            Add(playerID)
        end
    end

    local players = {}
    for playerID, row in pairs(rows) do
        players[tostring(playerID)] = row
    end
    CustomNetTables:SetTableValue("osc_state", "summary", {
        players = players,
        titles = OSC_Summary.Titles(rows, extras),
    })
    OSC_Logger.Log("Match summary published")
    return true
end

function OSC_Summary.Init()
    -- Надпись «Победа сил …» ложится на окно итогов: оставляем только эффект.
    -- Пробел, а не "": пустая строка может вернуть стандартный текст
    if OSC_Summary.IsEnabled() then
        GameRules:SetCustomVictoryMessage(" ")
    end
    OSC_GameEvents.Subscribe("match_stats", "summary", function(stats)
        OSC_Summary.Publish(stats.players or {})
    end)
end
