-- Шина событий матча. Это единственная точка, через которую системы узнают
-- друг о друге: одна система публикует (Emit), другие подписываются
-- (Subscribe), напрямую никто никого не вызывает. Отдельной шины нет —
-- события движка и события режима идут через один модуль.
--
-- Только этот модуль слушает npc_spawned, dota_on_hero_finish_spawn и
-- game_rules_state_change; системы подписываются здесь, а не у движка.
--
-- События движка и жизненного цикла:
--   hero_spawned(unit, source) — герой (основной или копия) появился или
--     возродился. source — имя события движка. Первое появление приходит
--     дважды (npc_spawned и dota_on_hero_finish_spawn) — это второй шанс,
--     если на npc_spawned юнит ещё не распознан (владелец не выставлен) или
--     обработчик упал. Поэтому обработчики обязаны быть идемпотентными.
--     Кто нужен — фильтруют через OSC_Heroes.
--   hero_initialized(hero) — основной герой получил способности режима
--     (присылает hero_lifecycle).
--   game_state_changed { state, previous } — сменилась стадия игры
--     (DOTA_GAMERULES_STATE_*); приходит до game_started.
--   game_started() — игра перешла в GAME_IN_PROGRESS; приходит один раз.
--   hero_anchored(hero) — основному герою поставлен «Якорь» (присылает
--     OSC_Anchor).
--
-- События режима (один аргумент — таблица, её можно расширять полями):
--   ability_changed { hero, player_id, slot, ability, previous } —
--     основному герою фактически выдана способность режима (после отсрочки
--     фазы каста). slot — "ability" | "ultimate"; previous — имя прежней
--     или nil при первой выдаче. Присылает OSC_Abilities.
--   chaos_started { event_id, start_time, end_time } и
--   chaos_ended { event_id, start_time, end_time, stopped } — хаос-раунд
--     начался / закончился (stopped = true — досрочно, -chaos_stop или
--     смена события). Присылает chaos_rounds.
--   casino_spin_resolved { player_id, hero, stake, payout, net, multiplier,
--     item_stake } — спин казино рассчитан и выплачен; net = payout - stake.
--     Спин, отменённый с возвратом ставки, не публикуется. Присылает casino.
--   config_overrides_applied { overrides = { [путь] = значение } } — итоги
--     голосования записаны в OSC_Config; кто уже применил прежние значения,
--     пересинхронизируется. Присылает vote.
--   match_stats { players = { [playerID] = { hero, rotations, abilities,
--     kills, kill_abilities, casino_net, chaos_damage } } } — итоговая
--     статистика матча на POST_GAME. Присылает stats.
--
-- Подписка именованная: повторный Subscribe с тем же id заменяет обработчик,
-- поэтому повторная инициализация и script_reload не дублируют подписки.
-- Ошибка одного обработчика пишется в лог и не мешает остальным.

require("osc/core/logger")
require("osc/core/heroes")

OSC_GameEvents = OSC_GameEvents or {
    handlers = {},
    game_started = false,
    listening = false,
}

local KNOWN_EVENTS = {
    hero_spawned = true,
    hero_initialized = true,
    game_state_changed = true,
    game_started = true,
    hero_anchored = true,
    ability_changed = true,
    chaos_started = true,
    chaos_ended = true,
    casino_spin_resolved = true,
    match_stats = true,
    config_overrides_applied = true,
}

function OSC_GameEvents.Subscribe(eventName, id, handler)
    if not KNOWN_EVENTS[eventName] then
        error("[OSC] Unknown game event: " .. tostring(eventName))
    end
    if type(id) ~= "string" or id == "" or type(handler) ~= "function" then
        error("[OSC] Subscribe needs a string id and a handler function")
    end

    local list = OSC_GameEvents.handlers[eventName] or {}
    OSC_GameEvents.handlers[eventName] = list
    for _, subscription in ipairs(list) do
        if subscription.id == id then
            subscription.handler = handler
            return
        end
    end
    table.insert(list, { id = id, handler = handler })
end

function OSC_GameEvents.Emit(eventName, ...)
    if not KNOWN_EVENTS[eventName] then
        error("[OSC] Unknown game event: " .. tostring(eventName))
    end
    for _, subscription in ipairs(OSC_GameEvents.handlers[eventName] or {}) do
        local ok, err = pcall(subscription.handler, ...)
        if not ok then
            OSC_Logger.Error("[GameEvents] " .. eventName .. " handler '"
                .. subscription.id .. "' failed: " .. tostring(err))
        end
    end
end

function OSC_GameEvents.IsGameStarted()
    return OSC_GameEvents.game_started == true
end

-- ================= События движка =================

function OSC_GameEvents.OnNPCSpawned(event)
    local unit = EntIndexToHScript(event.entindex)
    if not OSC_Heroes.IsHeroUnit(unit) then return end
    OSC_GameEvents.Emit("hero_spawned", unit, "npc_spawned")
end

-- Второй шанс для первого появления (см. hero_spawned выше)
function OSC_GameEvents.OnHeroFinishSpawn(event)
    local unit = EntIndexToHScript(event.heroindex)
    if not OSC_Heroes.IsHeroUnit(unit) then return end
    OSC_GameEvents.Emit("hero_spawned", unit, "dota_on_hero_finish_spawn")
end

function OSC_GameEvents.OnStateChange()
    local state = GameRules:State_Get()
    local previous = OSC_GameEvents.last_state
    if state ~= previous then
        OSC_GameEvents.last_state = state
        OSC_GameEvents.Emit("game_state_changed", { state = state, previous = previous })
    end

    if OSC_GameEvents.game_started or state ~= DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        return
    end
    OSC_GameEvents.game_started = true
    OSC_GameEvents.Emit("game_started")
end

-- Обработчики вызываются через таблицу модуля: после script_reload
-- работает новый код без повторной подписки у движка
function OSC_GameEvents.Init()
    if OSC_GameEvents.listening then return end
    OSC_GameEvents.listening = true
    ListenToGameEvent("npc_spawned", function(event)
        OSC_GameEvents.OnNPCSpawned(event)
    end, nil)
    ListenToGameEvent("dota_on_hero_finish_spawn", function(event)
        OSC_GameEvents.OnHeroFinishSpawn(event)
    end, nil)
    ListenToGameEvent("game_rules_state_change", function()
        OSC_GameEvents.OnStateChange()
    end, nil)
end
