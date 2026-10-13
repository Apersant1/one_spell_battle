-- Единая точка чтения конфига с рантайм-переопределениями.
--
--   OSC_Config.Get("ROTATION_INTERVAL")
--   OSC_Config.Get("CHAOS_ROUNDS.INTERVAL")
--
-- Значение берётся из переопределения для этого пути, иначе из OSC_CONFIG
-- (osc/config/config.lua). Исходный OSC_CONFIG никогда не меняется.
-- Переопределения (например, итоги голосования в лобби) задаются через
-- SetOverride и хранятся в таблице модуля — переживают script_reload, а
-- config.lua при перезагрузке, наоборот, читается заново.
--
-- Правила для модулей:
--   * читать значения в момент использования, а не копировать их в
--     локальные переменные при загрузке файла;
--   * читать листья по полному пути: переопределение действует только на
--     точный путь, и таблица, полученная через Get("CHAOS_ROUNDS"), его не
--     увидит. Таблицы целиком читаются только для статических списков
--     (прекэш, таблица исходов казино).

require("osc/core/logger")

OSC_Config = OSC_Config or { overrides = {} }

local function Split(path)
    local parts = {}
    for part in string.gmatch(path, "[^%.]+") do
        table.insert(parts, part)
    end
    return parts
end

-- Значение исходного конфига по пути или nil
function OSC_Config.GetBase(path)
    local value = OSC_CONFIG
    for _, part in ipairs(Split(path)) do
        if type(value) ~= "table" then
            return nil
        end
        value = value[part]
    end
    return value
end

function OSC_Config.Get(path)
    local overrides = OSC_Config.overrides
    if overrides and overrides[path] ~= nil then
        return overrides[path]
    end
    return OSC_Config.GetBase(path)
end

-- Переопределяет значение на время матча. Путь должен существовать в
-- OSC_CONFIG, тип значения — совпадать с исходным (защита от опечаток).
function OSC_Config.SetOverride(path, value)
    if type(path) ~= "string" or path == "" then
        error("[OSC] Config path must be a non-empty string")
    end
    local base = OSC_Config.GetBase(path)
    if base == nil then
        error("[OSC] Unknown config path: " .. path)
    end
    if type(value) ~= type(base) then
        error("[OSC] Config override " .. path .. " must be a " .. type(base)
            .. ", got " .. type(value))
    end
    OSC_Config.overrides = OSC_Config.overrides or {}
    OSC_Config.overrides[path] = value
    OSC_Logger.Log("Config override " .. path .. " = " .. tostring(value))
end

function OSC_Config.ClearOverride(path)
    if OSC_Config.overrides then
        OSC_Config.overrides[path] = nil
    end
end

function OSC_Config.ClearOverrides()
    OSC_Config.overrides = {}
end

-- Копия текущих переопределений (для отладки и тестов)
function OSC_Config.Overrides()
    local copy = {}
    for path, value in pairs(OSC_Config.overrides or {}) do
        copy[path] = value
    end
    return copy
end
