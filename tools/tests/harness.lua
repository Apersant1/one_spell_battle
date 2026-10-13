-- Моки Dota VScript API для офлайн-тестов. Загружается в свежий рантайм
-- LuaJIT перед каждым тестом; состояние моков лежит в глобальной таблице H.

H = {
    logs = {},
    events = {},
    netTables = {},
    listeners = {},
    gameEvents = {},
    thinks = {},
    kv = {},
    failAdd = {},
    heroes = {},
    players = {},
    entities = {},
    assignments = {},
    time = 0,
    state = 8,
}

math.randomseed(1)

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[#parts + 1] = tostring(select(i, ...))
    end
    table.insert(H.logs, table.concat(parts, " "))
end

-- ================= Константы =================

DOTA_TEAM_GOODGUYS = 2
DOTA_TEAM_BADGUYS = 3
DOTA_MAX_TEAM_PLAYERS = 24
DOTA_MAX_PLAYERS = 64
ABILITY_TYPE_BASIC = 0
ABILITY_TYPE_ULTIMATE = 1
DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP = 2
DOTA_GAMERULES_STATE_HERO_SELECTION = 4
DOTA_GAMERULES_STATE_STRATEGY_TIME = 5
DOTA_GAMERULES_STATE_PRE_GAME = 7
DOTA_GAMERULES_STATE_GAME_IN_PROGRESS = 8
DOTA_GAMERULES_STATE_POST_GAME = 9
DOTA_ModifyGold_Unspecified = 0
PATTACH_ABSORIGIN_FOLLOW = 1
PATTACH_WORLDORIGIN = 2
LUA_MODIFIER_MOTION_NONE = 0
FCVAR_CHEAT = 0

-- ================= Базовые функции движка =================

local VectorMeta = {}
VectorMeta.__index = VectorMeta
VectorMeta.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VectorMeta.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VectorMeta.__mul = function(a, b)
    if type(a) == "number" then a, b = b, a end
    return Vector(a.x * b, a.y * b, a.z * b)
end
VectorMeta.__eq = function(a, b) return a.x == b.x and a.y == b.y and a.z == b.z end
VectorMeta.__tostring = function(v) return string.format("(%g, %g, %g)", v.x, v.y, v.z) end
function VectorMeta:Length2D() return math.sqrt(self.x * self.x + self.y * self.y) end

function Vector(x, y, z)
    return setmetatable({ x = x or 0, y = y or 0, z = z or 0 }, VectorMeta)
end

function class(def)
    return setmetatable(def or {}, {
        __call = function(cls)
            return setmetatable({}, { __index = cls })
        end,
    })
end

function RandomInt(a, b) return math.random(a, b) end
function RandomFloat(a, b) return a + (b - a) * math.random() end
function RandomVector(length) return Vector(length, 0, 0) end
function IsServer() return true end
function LinkLuaModifier() end
function GetGroundPosition(v) return v end
function EmitSoundOn() end
function EmitSoundOnLocationWithCaster() end
function FindClearSpaceForUnit() end
function UTIL_Remove(entity) entity._null = true end
function ListenToGameEvent(name, fn, ctx)
    H.gameEvents[name] = H.gameEvents[name] or {}
    table.insert(H.gameEvents[name], { fn = fn, ctx = ctx })
end

-- Вызывает всех подписчиков события движка
function H.FireGameEvent(name, data)
    for _, listener in ipairs(H.gameEvents[name] or {}) do
        if listener.ctx ~= nil then
            listener.fn(listener.ctx, data)
        else
            listener.fn(data)
        end
    end
end
function Dynamic_Wrap(cls, name) return function(...) return cls[name](...) end end
function EntIndexToHScript(index) return H.entities[index] end
function GetAbilityKeyValuesByName(name) return H.kv[name] end

local uniqueCounter = 0
function DoUniqueString(prefix)
    uniqueCounter = uniqueCounter + 1
    return prefix .. "_" .. uniqueCounter
end

Convars = { RegisterCommand = function() end }
ParticleManager = {
    CreateParticle = function() return 1 end,
    SetParticleControl = function() end,
    SetParticleControlEnt = function() end,
    ReleaseParticleIndex = function() end,
    DestroyParticle = function() end,
}

local thinker = {}
function thinker:SetContextThink(name, fn, delay) H.thinks[name] = { fn = fn, delay = delay } end
function thinker:SetThink(name, owner, thinkName, delay)
    H.thinks[thinkName] = { fn = function() return owner[name](owner) end, delay = delay }
end

GameRules = {
    GetGameTime = function() return H.time end,
    State_Get = function() return H.state end,
    GetGameModeEntity = function() return thinker end,
    GetCustomGameTeamMaxPlayers = function() return 5 end,
    PlayerHasCustomGameHostPrivileges = function(_, player) return player.host == true end,
    SetCustomGameTeamMaxPlayers = function() end,
    SetCustomGameSetupAutoLaunchDelay = function() end,
    SetCustomGameSetupTimeout = function() end,
    LockCustomGameSetupTeamAssignment = function() end,
}

PlayerResource = {
    IsValidPlayerID = function(_, id) return id ~= nil and H.players[id] ~= nil end,
    GetSelectedHeroEntity = function(_, id) return H.players[id] and H.players[id].hero end,
    GetPlayer = function(_, id) return H.players[id] and H.players[id].player end,
    GetTeam = function(_, id) return H.players[id] and H.players[id].team end,
    GetGold = function(_, id) return H.players[id].gold end,
    GetReliableGold = function() return 0 end,
    SpendGold = function(_, id, amount) H.players[id].gold = H.players[id].gold - amount end,
    ModifyGold = function(_, id, amount) H.players[id].gold = H.players[id].gold + amount end,
    SetCustomTeamAssignment = function(_, id, team) H.assignments[id] = team end,
    GetCustomTeamAssignment = function(_, id) return H.players[id] and H.players[id].team end,
    GetPlayerCountForTeam = function() return 0 end,
}

HeroList = { GetAllHeroes = function() return H.heroes end }

H.byClass = {}
Entities = {
    FindAllByClassname = function(_, className) return H.byClass[className] or {} end,
}
function ExecuteOrderFromTable(order) H.lastOrder = order end
function CreateUnitByName() return nil end

function H.NewItem(name)
    return {
        name = name,
        IsNull = function() return false end,
        GetAbilityName = function(self) return self.name end,
    }
end

CustomNetTables = {
    SetTableValue = function(_, _, key, value) H.netTables[key] = value end,
}

CustomGameEventManager = {
    Send_ServerToPlayer = function(_, player, name, data)
        table.insert(H.events, { player = player, name = name, data = data })
    end,
    Send_ServerToAllClients = function(_, name, data)
        table.insert(H.events, { name = name, data = data })
    end,
    RegisterListener = function(_, name, fn) H.listeners[name] = fn end,
}

-- ================= Способности и герои =================

local SLOT_COUNT = 16

-- opts: ultimate, maxLevel, innate, passive, cooldown (число или список по уровням)
function H.DefineAbility(name, opts)
    opts = opts or {}
    H.kv[name] = {
        Innate = opts.innate and "1" or nil,
        _ultimate = opts.ultimate == true,
        _maxLevel = opts.maxLevel or (opts.ultimate and 3 or 4),
        _passive = opts.passive == true,
        _cooldown = opts.cooldown or 0,
    }
end

local Ability = {}
Ability.__index = Ability

function Ability:GetAbilityName() return self.name end
function Ability:IsNull() return self._removed == true end
function Ability:GetLevel() return self.level end
function Ability:SetLevel(level) self.level = level end
function Ability:GetMaxLevel() return H.kv[self.name]._maxLevel end
function Ability:GetAbilityType()
    return H.kv[self.name]._ultimate and ABILITY_TYPE_ULTIMATE or ABILITY_TYPE_BASIC
end
function Ability:SetHidden(hidden) self.hidden = hidden end
function Ability:IsHidden() return self.hidden end
function Ability:EndCooldown() self.cooldown = 0 end
function Ability:StartCooldown(seconds) self.cooldown = seconds end
function Ability:GetCooldownTimeRemaining() return self.cooldown or 0 end
-- iLevel — индекс уровня с нуля, как в движке
function Ability:GetCooldown(levelIndex)
    local cooldown = H.kv[self.name]._cooldown
    if type(cooldown) == "table" then
        return cooldown[math.min(levelIndex + 1, #cooldown)]
    end
    return cooldown
end
function Ability:GetEffectiveCooldown(levelIndex) return self:GetCooldown(levelIndex) end
function Ability:IsChanneling() return self.channeling == true end
function Ability:GetToggleState() return self.toggled == true end
function Ability:ToggleAbility() self.toggled = not self.toggled end
function Ability:IsPassive() return H.kv[self.name]._passive end
function Ability:IsInAbilityPhase() return self.in_phase == true end

-- В игре SetAbilityIndex не переставляет способность на панели: слот
-- определяют AddAbility (первый свободный) и SwapAbilities. Мок повторяет это.
function Ability:SetAbilityIndex(index)
    self.requestedIndex = index
end

local Hero = {}
Hero.__index = Hero

function Hero:IsNull() return self._null == true end
function Hero:IsHero() return true end
-- Как в Dota: IsRealHero ложно только у иллюзий, клоны Meepo и Tempest
-- Double — «настоящие» герои
function Hero:IsRealHero() return self.copy ~= "illusion" end
function Hero:IsIllusion() return self.copy == "illusion" end
function Hero:IsTempestDouble() return self.copy == "tempest" end
function Hero:IsClone() return self.copy == "clone" end
function Hero:IsAlive() return self.alive ~= false end
function Hero:IsInvulnerable() return false end
function Hero:IsMagicImmune() return false end
function Hero:GetUnitName() return self.name end
function Hero:GetLevel() return self.level end
function Hero:GetPlayerOwnerID() return self.playerID end
function Hero:GetTeamNumber() return self.team end
function Hero:GetAbsOrigin() return self.origin end
function Hero:GetForwardVector() return Vector(1, 0, 0) end
function Hero:GetGold() return H.players[self.playerID].gold end
function Hero:GetRightVector() return Vector(0, 1, 0) end
function Hero:GetBaseMoveSpeed() return 300 end
function Hero:SetControllableByPlayer() end
function Hero:entindex() return self.index or 0 end
function Hero:GetItemInSlot(slot) return self.items[slot] end

function Hero:TakeItem(item)
    for slot, current in pairs(self.items) do
        if current == item then
            self.items[slot] = nil
            return item
        end
    end
end

-- Как в Dota: сначала основной инвентарь и рюкзак (0-8)
function Hero:AddItem(item)
    for slot = 0, 8 do
        if not self.items[slot] then
            self.items[slot] = item
            return item
        end
    end
end
function Hero:RemoveItem(item)
    self:TakeItem(item)
    item._removed = true
    self.removedItems = (self.removedItems or 0) + 1
end
function Hero:HasModifier(name) return self.modifiers[name] ~= nil end
local function ModifierNames(hero)
    local names = {}
    for name in pairs(hero.modifiers) do table.insert(names, name) end
    table.sort(names)
    return names
end
function Hero:GetModifierCount() return #ModifierNames(self) end
function Hero:GetModifierNameByIndex(index) return ModifierNames(self)[index + 1] end
function Hero:AddNewModifier(_, _, name, params) self.modifiers[name] = params or {}; return {} end
function Hero:RemoveModifierByName(name) self.modifiers[name] = nil end
function Hero:SetContextThink(name, fn, delay) H.thinks[name] = { fn = fn, delay = delay } end
function Hero:GetAbilityCount() return SLOT_COUNT end
function Hero:GetAbilityByIndex(index) return self.slots[index] end

function Hero:IndexOf(ability)
    for index = 0, SLOT_COUNT - 1 do
        if self.slots[index] == ability then return index end
    end
end

function Hero:FindAbilityByName(name)
    for index = 0, SLOT_COUNT - 1 do
        local ability = self.slots[index]
        if ability and ability.name == name then return ability end
    end
end

function Hero:AddAbility(name)
    if H.failAdd[name] or not H.kv[name] then return nil end
    for index = 0, SLOT_COUNT - 1 do
        if not self.slots[index] then
            local ability = setmetatable({ name = name, level = 0, hidden = false, owner = self }, Ability)
            self.slots[index] = ability
            return ability
        end
    end
end

function Hero:RemoveAbilityByHandle(ability)
    local index = self:IndexOf(ability)
    if index ~= nil then
        self.slots[index] = nil
        ability._removed = true
    end
end

function Hero:SwapAbilities(name1, name2, enable1, enable2)
    local first, second = self:FindAbilityByName(name1), self:FindAbilityByName(name2)
    assert(first and second, "SwapAbilities: both abilities must exist")
    local firstIndex, secondIndex = self:IndexOf(first), self:IndexOf(second)
    self.slots[firstIndex], self.slots[secondIndex] = second, first
    first.hidden = not enable1
    second.hidden = not enable2
end

function Hero:RemoveAbility(name)
    local ability = self:FindAbilityByName(name)
    if ability then self:RemoveAbilityByHandle(ability) end
end

function Hero:InterruptChannel()
    for index = 0, SLOT_COUNT - 1 do
        local ability = self.slots[index]
        if ability then ability.channeling = false end
    end
    self.interrupted = true
end

-- opts: name, playerID, team, level, copy ("illusion"/"clone"/"tempest"),
-- alive, abilities (список имён по слотам начиная с 0), origin
function H.NewHero(opts)
    local hero = setmetatable({
        name = opts.name or "npc_dota_hero_axe",
        playerID = opts.playerID or 0,
        team = opts.team or DOTA_TEAM_GOODGUYS,
        level = opts.level or 1,
        copy = opts.copy,
        alive = opts.alive,
        origin = opts.origin or Vector(0, 0, 0),
        slots = {},
        modifiers = {},
        items = {},
    }, Hero)
    for index, name in ipairs(opts.abilities or {}) do
        if not H.kv[name] then H.DefineAbility(name) end
        hero.slots[index - 1] = setmetatable({ name = name, level = 1, hidden = false, owner = hero }, Ability)
    end
    table.insert(H.heroes, hero)
    return hero
end

function H.AddPlayer(id, hero, opts)
    opts = opts or {}
    H.players[id] = {
        hero = hero,
        team = hero and hero:GetTeamNumber() or opts.team or DOTA_TEAM_GOODGUYS,
        player = { id = id, host = opts.host },
        gold = opts.gold or 1000,
    }
end

-- Запускает все отложенные действия, в имени которых есть prefix
function H.RunThinksMatching(prefix)
    local names = {}
    for name in pairs(H.thinks) do
        if string.find(name, prefix, 1, true) then
            table.insert(names, name)
        end
    end
    for _, name in ipairs(names) do
        H.RunThink(name)
    end
    return #names
end

-- Как в движке: если think вернул число, он запланирован снова
function H.RunThink(name)
    local think = H.thinks[name]
    assert(think, "no think registered: " .. tostring(name))
    H.thinks[name] = nil
    local delay = think.fn()
    if type(delay) == "number" and H.thinks[name] == nil then
        H.thinks[name] = { fn = think.fn, delay = delay }
    end
    return delay
end

-- ================= Проверки =================

function H.eq(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual), 2)
    end
end

function H.truthy(value, message)
    if not value then error(message or "expected truthy value", 2) end
end

function H.logged(pattern)
    for _, line in ipairs(H.logs) do
        if string.find(line, pattern, 1, true) then return true end
    end
    return false
end

function H.lastEvent(name)
    for i = #H.events, 1, -1 do
        if H.events[i].name == name then return H.events[i] end
    end
end
