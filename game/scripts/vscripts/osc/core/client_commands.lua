-- Общая проверка команд, которые присылает клиент (CustomGameEventManager).
-- Всё, что пришло от клиента, можно подделать, поэтому каждый обработчик
-- начинает с OSC_ClientCommands.Check: игрок существует, при необходимости
-- у него есть герой, аргументы допустимы.
--
--   local ok, cmd, reason = OSC_ClientCommands.Check(sourceIndex, event, {
--       hero = true,                                   -- нужен основной герой
--       args = {                                       -- проверяются по порядку
--           { name = "machine_entindex", check = OSC_ClientCommands.Integer({ min = 0 }) },
--       },
--   })
--
-- cmd = { player_id, player, hero, args = { имя = значение } } заполняется
-- по мере проверки, поэтому при отказе из-за героя или аргумента в нём уже
-- есть игрок, которому можно ответить. reason: "invalid_player", "no_hero"
-- или "invalid_<имя аргумента>".

require("osc/core/heroes")

OSC_ClientCommands = OSC_ClientCommands or {}

-- ID отправителя движок кладёт в event.PlayerID. sourceIndex — индекс
-- сущности игрока (обычно PlayerID + 1), его нельзя считать ID игрока:
-- он нужен только как запасной путь, если PlayerID нет.
function OSC_ClientCommands.GetSender(sourceIndex, event)
    local playerID = event and tonumber(event.PlayerID)
    if playerID == nil then
        local source = sourceIndex and EntIndexToHScript(sourceIndex)
        if source and not source:IsNull() and source.GetPlayerID then
            playerID = source:GetPlayerID()
        end
    end

    if playerID == nil or not PlayerResource:IsValidPlayerID(playerID) then
        return nil
    end
    local player = PlayerResource:GetPlayer(playerID)
    if not player then
        return nil
    end
    return playerID, player
end

-- ================= Проверки аргументов =================
-- Проверка — функция value -> ok, нормализованное значение

-- Целое число; opts: min, max, one_of (список допустимых значений)
function OSC_ClientCommands.Integer(opts)
    opts = opts or {}
    return function(value)
        local number = tonumber(value)
        -- NaN не равен сам себе; бесконечности и огромные числа не нужны
        if number == nil or number ~= number or math.abs(number) >= 2 ^ 31
            or number ~= math.floor(number) then
            return false
        end
        if (opts.min and number < opts.min) or (opts.max and number > opts.max) then
            return false
        end
        if opts.one_of then
            local found = false
            for _, allowed in ipairs(opts.one_of) do
                if allowed == number then
                    found = true
                    break
                end
            end
            if not found then
                return false
            end
        end
        return true, number
    end
end

-- ID существующего игрока
function OSC_ClientCommands.PlayerID()
    local integer = OSC_ClientCommands.Integer({ min = 0 })
    return function(value)
        local ok, number = integer(value)
        if not ok or not PlayerResource:IsValidPlayerID(number) then
            return false
        end
        return true, number
    end
end

-- Строка из списка допустимых
function OSC_ClientCommands.OneOf(list)
    return function(value)
        for _, allowed in ipairs(list) do
            if value == allowed then
                return true, value
            end
        end
        return false
    end
end

-- ================= Проверка команды =================

function OSC_ClientCommands.Check(sourceIndex, event, spec)
    spec = spec or {}
    local cmd = { args = {} }

    local playerID, player = OSC_ClientCommands.GetSender(sourceIndex, event)
    if playerID == nil then
        return false, cmd, "invalid_player"
    end
    cmd.player_id = playerID
    cmd.player = player

    if spec.hero then
        cmd.hero = OSC_Heroes.GetPlayerHero(playerID)
        if not cmd.hero then
            return false, cmd, "no_hero"
        end
    end

    for _, arg in ipairs(spec.args or {}) do
        local ok, value = arg.check(event and event[arg.name])
        if not ok then
            return false, cmd, "invalid_" .. arg.name
        end
        cmd.args[arg.name] = value
    end

    return true, cmd
end
