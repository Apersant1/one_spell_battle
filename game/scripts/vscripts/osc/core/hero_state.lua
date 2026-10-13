-- Состояние героя в режиме: всё, что режим помнит о герое (основном или
-- копии), описано здесь и создаётся только здесь. Системы читают и меняют
-- поля через OSC_HeroState.Get(hero); новое поле добавляется в FIELDS.
--
-- Состояние лежит на самой сущности (hero.osc_state): удаляется вместе с ней
-- и переживает script_reload.

OSC_HeroState = OSC_HeroState or {}

-- default — значение или функция, создающая значение (для таблиц)
local FIELDS = {
    -- Способности режима (имена записей пулов). У копии — то, что скопировано
    -- у владельца.
    { name = "ability", doc = "текущая основная способность (слот Q)" },
    { name = "ultimate", doc = "текущий ультимейт" },

    -- Замены, отложенные до конца фазы каста старой способности:
    -- слот -> { entry, notify, deadline }
    { name = "deferred", default = function() return {} end, doc = "отложенные замены по слотам" },

    -- Инициализация основного героя (hero_lifecycle)
    { name = "initialized", default = false, doc = "способности режима выданы" },
    { name = "init_state", doc = "nil | initializing | retry_pending | failed" },
    { name = "init_attempts", default = 0, doc = "сколько раз пробовали инициализировать" },

    -- Копия (иллюзия, Tempest Double, клон Meepo)
    { name = "copy_done", default = false, doc = "способности владельца уже скопированы" },

    -- События движка (game_events)
    { name = "spawn_seen", default = false, doc = "npc_spawned уже приходил" },

    -- Задел на этап 1
    { name = "anchored", default = false, doc = "«Якорь»: пропустить следующую ротацию (1.5)" },
    { name = "pending_choices", doc = "кандидаты выбора из трёх, выданные игроку (1.4)" },
}

-- Заполняет недостающие поля значениями по умолчанию. schema — таблица
-- FIELDS, по которой состояние уже дополнено: после script_reload она новая,
-- и у героев, созданных старым кодом, появляются добавленные поля.
local function FillDefaults(state)
    for _, field in ipairs(FIELDS) do
        if state[field.name] == nil then
            local default = field.default
            if type(default) == "function" then
                default = default()
            end
            state[field.name] = default
        end
    end
    state.schema = FIELDS
    return state
end

-- Состояние героя; создаётся при первом обращении
function OSC_HeroState.Get(hero)
    local state = hero.osc_state
    if not state then
        state = FillDefaults({})
        hero.osc_state = state
    elseif state.schema ~= FIELDS then
        FillDefaults(state)
    end
    return state
end

-- Состояние без создания: nil, если герой режиму ещё не встречался
function OSC_HeroState.Peek(hero)
    return hero and hero.osc_state or nil
end

-- Описание полей по порядку (имя, значение по умолчанию, смысл)
function OSC_HeroState.Fields()
    return FIELDS
end

-- ================= Отладка =================

local function Format(value, depth)
    if type(value) ~= "table" then
        return tostring(value)
    end
    if depth > 2 then
        return "{...}"
    end
    local keys = {}
    for key in pairs(value) do
        table.insert(keys, key)
    end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        local text = Format(value[key], depth + 1)
        if type(key) == "number" then
            table.insert(parts, text)
        else
            table.insert(parts, tostring(key) .. "=" .. text)
        end
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

-- Сколько способностей на герое: всего, скрытых и снятых ротацией, но ещё
-- не удалённых (рост этих чисел со временем — утечка)
function OSC_HeroState.CountAbilities(hero)
    local total, hidden, retired = 0, 0, 0
    for index = 0, hero:GetAbilityCount() - 1 do
        local ability = hero:GetAbilityByIndex(index)
        if ability then
            total = total + 1
            if ability:IsHidden() then hidden = hidden + 1 end
            if ability.osc_retired then retired = retired + 1 end
        end
    end
    return total, hidden, retired
end

-- Строки для лога: все поля состояния по порядку, способности и модификаторы
function OSC_HeroState.Describe(hero)
    local lines = { "Hero state: " .. hero:GetUnitName() }
    local state = OSC_HeroState.Peek(hero) or {}
    for _, field in ipairs(FIELDS) do
        table.insert(lines, "  " .. field.name .. " = " .. Format(state[field.name], 0))
    end

    local total, hidden, retired = OSC_HeroState.CountAbilities(hero)
    table.insert(lines, "  abilities: " .. total .. " (hidden " .. hidden
        .. ", retired " .. retired .. ")")
    local modifiers = hero.GetModifierCount and hero:GetModifierCount() or "n/a"
    table.insert(lines, "  modifiers: " .. tostring(modifiers))
    return lines
end
