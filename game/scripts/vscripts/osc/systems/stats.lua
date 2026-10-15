-- Статистика матча по игрокам (флаг STATS_ENABLED). Слушает только шину
-- событий (OSC_GameEvents) и события движка, другие системы не вызывает.
--
-- По каждому игроку:
--   rotations — сколько раз основная способность сменилась на другую
--     (ротация, «-reroll»; первая выдача и ультимейты не считаются);
--   abilities — полученные способности режима по порядку (основные и
--     ультимейты, включая первую выдачу);
--   kills / kill_abilities — убийства вражеских основных героев: всего и по
--     способностям (entindex_inflictor — способность, не предмет). Крипы,
--     иллюзии, клоны, добивание своих и смерть с перерождением (Aegis,
--     Reincarnation) не считаются: иначе фарм перевесил бы «убийства
--     способностями»;
--   casino_net — сумма выигрышей минус ставки (casino_spin_resolved);
--   chaos_damage — урон по вражеским героям (не иллюзиям) во время
--     активного хаос-раунда. Источник — событие движка entity_hurt; пока
--     раунд не идёт, обработчик сразу выходит, поэтому это дёшево и не
--     вмешивается в урон (в отличие от фильтра урона).
--
-- При разрушении трона (или на POST_GAME, что раньше) статистика
-- публикуется в шину событием match_stats { players = { [playerID] = запись } }
-- — его забирает экран итогов. Ждать только POST_GAME нельзя: в матче на
-- POST_GAME серверные события и think уже не приходили.

require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/game_events")

OSC_Stats = OSC_Stats or {
    players = {},
    chaos_active = false,
    listening = false,
    published = false,
}

function OSC_Stats.IsEnabled()
    return OSC_Config.Get("STATS_ENABLED") == true
end

-- Запись игрока; создаётся при первом обращении
function OSC_Stats.Player(playerID)
    local record = OSC_Stats.players[playerID]
    if not record then
        record = {
            hero = "",
            rotations = 0,
            abilities = {},
            kills = 0,
            kill_abilities = {},
            casino_net = 0,
            chaos_damage = 0,
        }
        OSC_Stats.players[playerID] = record
    end
    return record
end

local function IsPlayer(playerID)
    return playerID ~= nil and playerID >= 0 and PlayerResource:IsValidPlayerID(playerID)
end

-- ================= События режима =================

function OSC_Stats.OnAbilityChanged(change)
    if not OSC_Stats.IsEnabled() or not IsPlayer(change.player_id) then return end
    local record = OSC_Stats.Player(change.player_id)
    table.insert(record.abilities, change.ability)
    if change.slot == "ability" and change.previous ~= nil and change.previous ~= change.ability then
        record.rotations = record.rotations + 1
    end
    if IsValidEntity(change.hero) then
        record.hero = change.hero:GetUnitName()
    end
end

function OSC_Stats.OnCasinoSpin(spin)
    if not OSC_Stats.IsEnabled() or not IsPlayer(spin.player_id) then return end
    local record = OSC_Stats.Player(spin.player_id)
    record.casino_net = record.casino_net + (spin.net or 0)
end

-- ================= События движка =================

local function Entity(index)
    return index and EntIndexToHScript(index) or nil
end

local function OwnerID(unit)
    if not IsValidEntity(unit) or not unit.GetPlayerOwnerID then
        return nil
    end
    local playerID = unit:GetPlayerOwnerID()
    return IsPlayer(playerID) and playerID or nil
end

function OSC_Stats.OnEntityKilled(event)
    if not OSC_Stats.IsEnabled() then return end
    local killed = Entity(event.entindex_killed)
    if IsValidEntity(killed) and killed.GetClassname
        and killed:GetClassname() == "npc_dota_fort" then
        OSC_Stats.Publish()
        return
    end
    if not OSC_Heroes.IsMainHero(killed) then return end
    if killed.IsReincarnating and killed:IsReincarnating() then return end

    local attackerID = OwnerID(Entity(event.entindex_attacker))
    if not attackerID or PlayerResource:GetTeam(attackerID) == killed:GetTeamNumber() then
        return
    end

    local record = OSC_Stats.Player(attackerID)
    record.kills = record.kills + 1

    local inflictor = Entity(event.entindex_inflictor)
    if IsValidEntity(inflictor) and inflictor.GetAbilityName
        and not (inflictor.IsItem and inflictor:IsItem()) then
        local name = inflictor:GetAbilityName()
        record.kill_abilities[name] = (record.kill_abilities[name] or 0) + 1
    end
end

function OSC_Stats.OnEntityHurt(event)
    if not OSC_Stats.chaos_active or not OSC_Stats.IsEnabled() then return end
    local damage = tonumber(event.damage)
    if not damage or damage <= 0 then return end

    local victim = Entity(event.entindex_killed)
    if not OSC_Heroes.IsCombatHero(victim) then return end
    local attackerID = OwnerID(Entity(event.entindex_attacker))
    if not attackerID or PlayerResource:GetTeam(attackerID) == victim:GetTeamNumber() then
        return
    end

    local record = OSC_Stats.Player(attackerID)
    record.chaos_damage = record.chaos_damage + damage
end

-- ================= Итог =================

-- Копия статистики для публикации: имя героя берётся у текущего героя игрока
function OSC_Stats.Snapshot()
    local players = {}
    for playerID, record in pairs(OSC_Stats.players) do
        local hero = OSC_Heroes.GetPlayerHero(playerID)
        local copy = {
            hero = hero and hero:GetUnitName() or record.hero,
            rotations = record.rotations,
            abilities = {},
            kills = record.kills,
            kill_abilities = {},
            casino_net = record.casino_net,
            chaos_damage = record.chaos_damage,
        }
        for index, name in ipairs(record.abilities) do
            copy.abilities[index] = name
        end
        for name, count in pairs(record.kill_abilities) do
            copy.kill_abilities[name] = count
        end
        players[playerID] = copy
    end
    return players
end

function OSC_Stats.Publish()
    if OSC_Stats.published or not OSC_Stats.IsEnabled() then return end
    OSC_Stats.published = true
    OSC_Logger.Log("Match stats published")
    OSC_GameEvents.Emit("match_stats", { players = OSC_Stats.Snapshot() })
end

function OSC_Stats.OnStateChanged(change)
    if change.state == DOTA_GAMERULES_STATE_POST_GAME then OSC_Stats.Publish() end
end

function OSC_Stats.Init()
    OSC_GameEvents.Subscribe("ability_changed", "stats", function(change)
        OSC_Stats.OnAbilityChanged(change)
    end)
    OSC_GameEvents.Subscribe("casino_spin_resolved", "stats", function(spin)
        OSC_Stats.OnCasinoSpin(spin)
    end)
    OSC_GameEvents.Subscribe("chaos_started", "stats", function()
        OSC_Stats.chaos_active = true
    end)
    OSC_GameEvents.Subscribe("chaos_ended", "stats", function()
        OSC_Stats.chaos_active = false
    end)
    OSC_GameEvents.Subscribe("game_state_changed", "stats", function(change)
        OSC_Stats.OnStateChanged(change)
    end)

    if OSC_Stats.listening then return end
    OSC_Stats.listening = true
    ListenToGameEvent("entity_killed", function(event)
        OSC_Stats.OnEntityKilled(event)
    end, nil)
    ListenToGameEvent("entity_hurt", function(event)
        OSC_Stats.OnEntityHurt(event)
    end, nil)
end
