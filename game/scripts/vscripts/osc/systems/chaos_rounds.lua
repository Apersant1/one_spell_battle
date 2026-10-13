require("osc/core/runtime_config")
require("osc/core/heroes")
require("osc/core/game_events")

OSC_ChaosRounds = OSC_ChaosRounds or {}

local THINK_INTERVAL = 0.25
local SPAWN_APPLY_DELAY = 0.5
local STATE = { IDLE = "idle", WARNING = "warning", ACTIVE = "active" }

local function config(key)
    return OSC_Config.Get("CHAOS_ROUNDS." .. key)
end

local function now()
    return GameRules:GetGameTime()
end

local function logError(message)
    OSC_Logger.Error("[ChaosRounds] " .. message)
end

-- Эффекты действуют на все боевые тела: основных героев, клонов Meepo и
-- Tempest Double (у них свои перезарядки и мана), но не на иллюзии
local function forEachHero(callback)
    OSC_Heroes.ForEachCombatHero(callback)
end

local function callHook(ev, hookName, ...)
    local hook = ev[hookName]
    if not hook then
        return
    end

    local ok, err = pcall(hook, ev, ...)
    if not ok then
        logError(ev.id .. ":" .. hookName .. " — " .. tostring(err))
    end
end

local function notifyWarning(ev)
    OSC_Notifications.ChaosRoundWarning(ev.title_key, config("WARNING_TIME"))
end

local function notifyStarted(ev)
    OSC_Notifications.ChaosRoundStarted("#" .. ev.title_key, OSC_ChaosEvents:Duration(ev))
end

local function notifyEnded(ev)
    OSC_Notifications.ChaosRoundEnded("#" .. ev.title_key)
end

function OSC_ChaosRounds:Init()
    self.state = STATE.IDLE
    self.event = nil
    self.pending = nil
    self.lastId = nil
    self.nextStart = 0
    self.startTime = 0
    self.endTime = 0
    self.nextTick = 0
    self.running = false

    OSC_GameEvents.Subscribe("game_started", "chaos_rounds", function()
        OSC_ChaosRounds:OnGameStarted()
    end)
    OSC_GameEvents.Subscribe("hero_spawned", "chaos_rounds", function(hero)
        OSC_ChaosRounds:OnHeroSpawned(hero)
    end)

    self:Publish()
end

function OSC_ChaosRounds:OnGameStarted()
    if self.running then
        return
    end

    self.running = true
    self:ScheduleNext(config("INTERVAL"))
    GameRules:GetGameModeEntity():SetContextThink(
        "osc_chaos_rounds_think",
        function()
            local ok, err = pcall(self.Think, self)
            if not ok then
                logError("Think — " .. tostring(err))
            end
            return THINK_INTERVAL
        end,
        THINK_INTERVAL
    )
end

function OSC_ChaosRounds:ScheduleNext(delay)
    self.state = STATE.IDLE
    self.event = nil
    self.pending = OSC_ChaosEvents:PickRandom(self.lastId, now())
    self.nextStart = now() + delay
    self.startTime = self.nextStart
    self.endTime = 0
    self.nextTick = 0
    self:Publish()
end

function OSC_ChaosRounds:Think()
    if GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
        return nil
    end

    local time = now()
    if self.state == STATE.IDLE then
        if not self.pending then
            self.pending = OSC_ChaosEvents:PickRandom(self.lastId, time)
        end
        if self.pending and time >= self.nextStart - config("WARNING_TIME") then
            self.state = STATE.WARNING
            self:Publish()
            notifyWarning(self.pending)
        end
    elseif self.state == STATE.WARNING then
        if time >= self.nextStart then
            self:StartEvent(self.pending)
        end
    elseif self.state == STATE.ACTIVE then
        local ev = self.event
        if time >= self.endTime then
            self:EndEvent(false)
        elseif ev.OnInterval and time >= self.nextTick then
            self.nextTick = time + OSC_ChaosEvents:TickInterval(ev)
            callHook(ev, "OnInterval", self:Context())
        end
    end

    return THINK_INTERVAL
end

function OSC_ChaosRounds:Context()
    return {
        event_id = self.event and self.event.id or "",
        start_time = self.startTime,
        end_time = self.endTime,
        remaining = math.max(0, self.endTime - now()),
    }
end

function OSC_ChaosRounds:StartEvent(ev)
    if not ev then
        return false, "no event selected"
    end

    self.event = ev
    self.pending = nil
    self.state = STATE.ACTIVE
    self.startTime = now()
    self.endTime = self.startTime + OSC_ChaosEvents:Duration(ev)
    self.nextTick = self.startTime + OSC_ChaosEvents:TickInterval(ev)

    callHook(ev, "OnStart", self:Context())
    forEachHero(function(hero)
        callHook(ev, "ApplyToHero", hero, self:Context())
    end)

    self:Publish()
    notifyStarted(ev)
    OSC_Logger.Log("Chaos round started: " .. ev.id)
    return true
end

function OSC_ChaosRounds:EndEvent(debugStop)
    local ev = self.event
    if not ev then
        return false, "no active chaos round"
    end

    local ctx = self:Context()
    forEachHero(function(hero)
        callHook(ev, "RemoveFromHero", hero, ctx)
    end)
    callHook(ev, "OnEnd", ctx)

    notifyEnded(ev)
    OSC_Logger.Log("Chaos round ended: " .. ev.id)
    self.lastId = ev.id

    local nextDelay
    if debugStop then
        nextDelay = config("INTERVAL")
    else
        nextDelay = math.max(0, self.nextStart + config("INTERVAL") - now())
    end
    self:ScheduleNext(nextDelay)
    return true
end

function OSC_ChaosRounds:OnHeroSpawned(hero)
    if self.state ~= STATE.ACTIVE or not OSC_Heroes.IsCombatHero(hero) then
        return
    end

    local event = self.event
    local eventEndTime = self.endTime
    hero:SetContextThink("osc_chaos_apply_on_spawn", function()
        if not OSC_Heroes.IsCombatHero(hero)
            or self.state ~= STATE.ACTIVE
            or self.event ~= event
            or self.endTime ~= eventEndTime then
            return nil
        end

        callHook(event, "ApplyToHero", hero, self:Context())
        return nil
    end, SPAWN_APPLY_DELAY)
end

function OSC_ChaosRounds:Publish()
    local active = self.state == STATE.ACTIVE
    local ev = active and self.event
        or (self.state == STATE.WARNING and self.pending)
        or nil
    CustomNetTables:SetTableValue("osc_state", "chaos_round", {
        state = self.state,
        event_id = ev and ev.id or "",
        title_key = ev and ev.title_key or "",
        desc_key = ev and ev.desc_key or "",
        desc_params = ev and OSC_ChaosEvents:DescriptionParams(ev) or {},
        start_time = active and self.startTime or self.nextStart,
        end_time = active and self.endTime or 0,
    })
end

function OSC_ChaosRounds:DebugStart(id)
    if not self.running then
        return false, "игра ещё не началась"
    end

    local event
    if id then
        event = OSC_ChaosEvents:Get(id)
    else
        event = OSC_ChaosEvents:PickRandom(self.lastId, now())
    end
    if not event or event.enabled == false or OSC_ChaosEvents:Weight(event) <= 0 then
        return false, "неизвестное или отключённое событие: " .. tostring(id)
    end

    if self.state == STATE.ACTIVE then
        self:EndEvent(true)
    end
    self.nextStart = now()
    self.pending = nil
    self.state = STATE.IDLE
    return self:StartEvent(event)
end

function OSC_ChaosRounds:DebugStop()
    if not self.running then
        return false, "игра ещё не началась"
    end
    if self.state ~= STATE.ACTIVE then
        return false, "нет активного раунда"
    end
    return self:EndEvent(true)
end
