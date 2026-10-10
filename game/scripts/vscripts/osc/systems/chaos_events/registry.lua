-- Chaos event descriptor contract:
-- id (required), weight (default 10; 0 disables), duration (default
-- CHAOS_ROUNDS.DURATION), title_key/desc_key (default osc_chaos_<id>_title/
-- osc_chaos_<id>_desc), conflicts (default {}), modifier (optional automatic
-- ApplyToHero/RemoveFromHero), tick_interval (default 1), and optional hooks
-- OnStart(ev, ctx), ApplyToHero(ev, hero, ctx), RemoveFromHero(ev, hero, ctx),
-- OnInterval(ev, ctx), OnEnd(ev, ctx). ctx has event_id, start_time,
-- end_time, and remaining. ApplyToHero must be idempotent because it is also
-- called after hero respawns.

OSC_ChaosEvents = OSC_ChaosEvents or { list = {}, byId = {} }

local function logError(message)
    OSC_Logger.Error("[ChaosEvents] " .. message)
end

function OSC_ChaosEvents:Register(def)
    if type(def) ~= "table" or type(def.id) ~= "string" or def.id == "" then
        logError("Cannot register descriptor without an id")
        return false, "descriptor must have a non-empty string id"
    end

    if self.byId[def.id] then
        logError("Duplicate event id: " .. def.id)
        return false, "duplicate event id: " .. def.id
    end

    if def.weight ~= nil and (type(def.weight) ~= "number" or def.weight < 0) then
        logError("Invalid weight for event " .. def.id)
        return false, "event weight must be a non-negative number"
    end
    if def.duration ~= nil and (type(def.duration) ~= "number" or def.duration <= 0) then
        logError("Invalid duration for event " .. def.id)
        return false, "event duration must be a positive number"
    end
    if def.tick_interval ~= nil
        and (type(def.tick_interval) ~= "number" or def.tick_interval <= 0) then
        logError("Invalid tick interval for event " .. def.id)
        return false, "event tick_interval must be a positive number"
    end
    if def.conflicts ~= nil and type(def.conflicts) ~= "table" then
        logError("Invalid conflicts for event " .. def.id)
        return false, "event conflicts must be a table"
    end

    def.weight = def.weight == nil and 10 or def.weight
    def.duration = def.duration or OSC_CONFIG.CHAOS_ROUNDS.DURATION
    def.title_key = def.title_key or ("osc_chaos_" .. def.id .. "_title")
    def.desc_key = def.desc_key or ("osc_chaos_" .. def.id .. "_desc")
    def.conflicts = def.conflicts or {}
    def.tick_interval = def.tick_interval or 1
    def.min_game_time = def.min_game_time or 0

    if def.modifier then
        def.ApplyToHero = def.ApplyToHero or function(ev, hero, ctx)
            if ctx.remaining <= 0 or hero:HasModifier(ev.modifier) then
                return
            end
            hero:AddNewModifier(hero, nil, ev.modifier, {
                duration = ctx.remaining,
            })
        end
        def.RemoveFromHero = def.RemoveFromHero or function(ev, hero)
            hero:RemoveModifierByName(ev.modifier)
        end
    end

    self.byId[def.id] = def
    table.insert(self.list, def)
    return true
end

function OSC_ChaosEvents:Get(id)
    return self.byId[id]
end

local function conflictsWithLastEvent(def, lastId)
    if not lastId then
        return false
    end
    if def.id == lastId then
        return true
    end
    for _, conflictId in ipairs(def.conflicts) do
        if conflictId == lastId then
            return true
        end
    end
    return false
end

local function collectCandidates(self, lastId, gameTime, avoidRepeat)
    local candidates = {}
    local totalWeight = 0
    for _, def in ipairs(self.list) do
        if def.enabled ~= false
            and def.weight > 0
            and gameTime >= def.min_game_time
            and not (avoidRepeat and conflictsWithLastEvent(def, lastId)) then
            table.insert(candidates, def)
            totalWeight = totalWeight + def.weight
        end
    end
    return candidates, totalWeight
end

function OSC_ChaosEvents:PickRandom(lastId, gameTime)
    gameTime = gameTime or GameRules:GetGameTime()
    local candidates, totalWeight =
        collectCandidates(self, lastId, gameTime, true)
    if #candidates == 0 then
        candidates, totalWeight = collectCandidates(self, lastId, gameTime, false)
    end
    if totalWeight <= 0 then
        return nil
    end

    local roll = RandomFloat(0, totalWeight)
    for _, def in ipairs(candidates) do
        roll = roll - def.weight
        if roll <= 0 then
            return def
        end
    end
    return candidates[#candidates]
end
