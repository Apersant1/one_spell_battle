OSC_ChaosRounds = OSC_ChaosRounds or {}

local THINK_INTERVAL = 0.25
local SPAWN_APPLY_DELAY = 0.5
local STATE = { IDLE = "idle", WARNING = "warning", ACTIVE = "active" }

local function config()
    return OSC_CONFIG.CHAOS_ROUNDS
end

local function now()
    return GameRules:GetGameTime()
end

local function logError(message)
    OSC_Logger.Error("[ChaosRounds] " .. message)
end

local function isValidEntity(entity)
    return entity and not entity:IsNull()
end

local function isRealHero(hero)
    return isValidEntity(hero)
        and hero.IsRealHero
        and hero:IsRealHero()
        and not (hero.IsIllusion and hero:IsIllusion())
        and not (hero.IsTempestDouble and hero:IsTempestDouble())
        and not (hero.IsClone and hero:IsClone())
end

local function forEachHero(callback)
    for _, hero in pairs(HeroList:GetAllHeroes() or {}) do
        if isRealHero(hero) then
            callback(hero)
        end
    end
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
    OSC_Notifications.ChaosRoundWarning(ev.title_key, config().WARNING_TIME)
end

local function notifyStarted(ev)
    OSC_Notifications.ChaosRoundStarted("#" .. ev.title_key, ev.duration)
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

    ListenToGameEvent(
        "game_rules_state_change",
        Dynamic_Wrap(OSC_ChaosRounds, "OnGameStateChange"),
        self
    )
    ListenToGameEvent(
        "npc_spawned",
        Dynamic_Wrap(OSC_ChaosRounds, "OnNPCSpawned"),
        self
    )

    self:Publish()
end

function OSC_ChaosRounds:OnGameStateChange()
    if self.running
        or GameRules:State_Get() ~= DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
        return
    end

    self.running = true
    self:ScheduleNext(config().INTERVAL)
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
        if self.pending and time >= self.nextStart - config().WARNING_TIME then
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
            self.nextTick = time + ev.tick_interval
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
    self.endTime = self.startTime + ev.duration
    self.nextTick = self.startTime + ev.tick_interval

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
        nextDelay = config().INTERVAL
    else
        nextDelay = math.max(0, self.nextStart + config().INTERVAL - now())
    end
    self:ScheduleNext(nextDelay)
    return true
end

function OSC_ChaosRounds:OnNPCSpawned(keys)
    if self.state ~= STATE.ACTIVE then
        return
    end

    local hero = EntIndexToHScript(keys.entindex)
    if not isRealHero(hero) then
        return
    end

    local event = self.event
    local eventEndTime = self.endTime
    hero:SetContextThink("osc_chaos_apply_on_spawn", function()
        if not isRealHero(hero)
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
        start_time = active and self.startTime or self.nextStart,
        end_time = active and self.endTime or 0,
    })
end
