-- Серверная часть казино: проверка конфига исходов, отказ мёртвым, dev-команда,
-- розыгрыш исхода (OSC_Casino.Roll), спин на золото и на предметы до расчёта

local function setup()
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/casino")
end

local function outcome(chance, symbol, multiplier)
    return { chance = chance, symbol = symbol, multiplier = multiplier }
end

-- Живой герой игрока 0 у своего автомата (entindex 100)
local function atMachine(gold)
    setup()
    local hero = H.NewHero({})
    H.AddPlayer(0, hero, { gold = gold or 1000 })
    local machine = H.NewHero({ name = "npc_osc_casino_test_object" })
    machine.index = 100
    machine.osc_casino_owner_player_id = 0
    OSC_HeroState.Get(hero).casino_machine = machine
    H.entities[100] = machine
    return hero, machine
end

-- Продаваемый предмет героя в слоте инвентаря, цена покупки cost
local function stakeItem(hero, slot, cost)
    local item = H.NewItem("item_test_" .. slot)
    item.IsItem = function() return true end
    item.IsSellable = function() return true end
    item.GetCost = function() return cost end
    item.GetPurchaser = function() return hero end
    hero.items[slot] = item
    return item
end

-- Исход спина без случайности
local function fixRoll(reels, multiplier)
    OSC_Casino.Roll = function() return reels, multiplier end
end

local function settle()
    H.eq(H.RunThinksMatching("osc_casino_settle_"), 1, "settlement scheduled")
    return H.lastEvent("osc_casino_result").data
end

return {
    validate_outcomes_current_config_ev = function()
        setup()
        local ok, ev = OSC_Casino.ValidateOutcomes(OSC_CONFIG.CASINO_OUTCOMES)
        H.eq(ok, true, "current config is valid")
        H.truthy(math.abs(ev - 0.9) < 1e-9, "expected payout 0.9, got " .. tostring(ev))
    end,

    validate_outcomes_rejects_over_100 = function()
        setup()
        local ok, err = OSC_Casino.ValidateOutcomes({
            outcome(60, "circle", 1), outcome(50, "star", 2),
        })
        H.eq(ok, false, "sum over 100 rejected")
        H.truthy(string.find(err, "100", 1, true), "error mentions 100: " .. tostring(err))
    end,

    validate_outcomes_rejects_unknown_symbol = function()
        setup()
        local ok = OSC_Casino.ValidateOutcomes({ outcome(10, "cherry", 2) })
        H.eq(ok, false, "unknown symbol rejected")
    end,

    validate_outcomes_rejects_duplicate_symbol = function()
        setup()
        local ok = OSC_Casino.ValidateOutcomes({ outcome(10, "star", 2), outcome(5, "star", 5) })
        H.eq(ok, false, "duplicate symbol rejected")
    end,

    validate_outcomes_rejects_fractional_chance = function()
        setup()
        local ok = OSC_Casino.ValidateOutcomes({ outcome(0.5, "seven", 30) })
        H.eq(ok, false, "fractional chance rejected")
    end,

    init_logs_expected_payout = function()
        setup()
        OSC_Casino.Init()
        H.truthy(H.logged("expected payout 0.90"), "EV logged")
    end,

    init_logs_invalid_outcomes = function()
        setup()
        OSC_CONFIG.CASINO_OUTCOMES = { outcome(150, "seven", 2) }
        OSC_Casino.Init()
        H.truthy(H.logged("ERROR: Casino outcomes"), "config error logged")
    end,

    spin_refused_when_dead = function()
        setup()
        local hero = H.NewHero({ alive = false })
        H.AddPlayer(0, hero, { gold = 1000 })
        local machine = H.NewHero({ name = "npc_osc_casino_test_object" })
        machine.osc_casino_owner_player_id = 0
        OSC_HeroState.Get(hero).casino_machine = machine
        H.entities[100] = machine

        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, stake = 100 })

        local result = H.lastEvent("osc_casino_result")
        H.truthy(result, "result sent")
        H.eq(result.data.error, "osc_casino_err_dead", "error key")
        H.eq(H.players[0].gold, 1000, "gold untouched")
    end,

    dev_command_forces_symbol = function()
        setup()
        require("osc/core/commands")
        OSC_CONFIG.DEVELOPMENT_MODE = true
        H.AddPlayer(0, H.NewHero({}))
        OSC_Commands.Init()
        local function chat(data) H.FireGameEvent("player_chat", data) end

        chat({ text = "-casino seven", playerid = 0 })
        H.eq(OSC_Casino.debug_forced_symbol, "seven", "forced symbol")

        chat({ text = "-casino off", playerid = 0 })
        H.eq(OSC_Casino.debug_forced_symbol, nil, "forcing disabled")
    end,

    gold_spin_win_pays_after_settlement = function()
        local hero = atMachine(1000)
        fixRoll({ "star", "star", "star" }, 5)
        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, stake = 100 })
        H.eq(H.players[0].gold, 900, "stake charged at once")

        local result = settle()
        H.eq(result.payout, 500, "stake times multiplier")
        H.eq(result.net, 400, "net win")
        H.eq(H.players[0].gold, 1400, "winnings paid")
        H.eq(hero:GetGold(), result.gold, "client gets the new balance")
    end,

    gold_spin_rejects_stake_above_gold = function()
        atMachine(80)
        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, stake = 100 })
        H.eq(H.lastEvent("osc_casino_result").data.error, "osc_casino_err_stake", "error key")
        H.eq(H.players[0].gold, 80, "gold untouched")
    end,

    item_stake_lost_on_a_loss = function()
        local hero = atMachine(1000)
        local item = stakeItem(hero, 0, 400) -- ставка 200 при CASINO_ITEM_VALUE_FACTOR 0.5
        fixRoll({ "seven", "star", "circle" }, 0)
        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, item_entindices = tostring(item.index) })
        H.eq(hero.items[0], nil, "item taken into the machine")

        local result = settle()
        H.eq(result.stake, 200, "item stake value")
        H.eq(result.items, item.name, "lost item reported")
        H.eq(hero.items[0], nil, "item stays lost")
        H.eq(H.players[0].gold, 1000, "gold untouched")
    end,

    item_stake_returned_on_refund_multiplier = function()
        local hero = atMachine(1000)
        local item = stakeItem(hero, 0, 400)
        fixRoll({ "circle", "circle", "circle" }, 1)
        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, item_entindices = tostring(item.index) })
        settle()
        H.eq(hero.items[0], item, "item back in the inventory")
        H.eq(H.players[0].gold, 1000, "no gold paid for x1")
    end,

    cheap_item_stake_refused = function()
        local hero = atMachine(1000)
        local item = stakeItem(hero, 0, 60) -- 30 золота меньше минимальной ставки 50
        OSC_Casino.OnSpin(1, { PlayerID = 0, machine_entindex = 100, item_entindices = tostring(item.index) })
        H.eq(H.lastEvent("osc_casino_result").data.error, "osc_casino_err_item_cheap", "error key")
        H.eq(hero.items[0], item, "item stays in the inventory")
    end,

    roll_follows_chances = function()
        setup()
        local outcomes = { outcome(10, "seven", 10), outcome(20, "star", 3) }
        local reels, multiplier = OSC_Casino.Roll(outcomes, 10, nil)
        H.eq(table.concat(reels, ","), "seven,seven,seven", "roll 10 is within the first 10%")
        H.eq(multiplier, 10, "first outcome multiplier")
        reels, multiplier = OSC_Casino.Roll(outcomes, 11, nil)
        H.eq(table.concat(reels, ","), "star,star,star", "roll 11 falls into the next 20%")
        H.eq(multiplier, 3, "second outcome multiplier")
    end,

    roll_loss_never_shows_three_of_a_kind = function()
        setup()
        local outcomes = { outcome(10, "seven", 10) }
        for _ = 1, 50 do
            local reels, multiplier = OSC_Casino.Roll(outcomes, 100, nil)
            H.eq(multiplier, 0, "loss pays nothing")
            H.truthy(not (reels[1] == reels[2] and reels[2] == reels[3]), "reels differ on a loss")
        end
    end,

    roll_forced_symbol_ignores_roll = function()
        setup()
        local outcomes = { outcome(10, "seven", 10), outcome(20, "star", 3) }
        local reels, multiplier = OSC_Casino.Roll(outcomes, 100, "star")
        H.eq(reels[1], "star", "forced symbol")
        H.eq(multiplier, 3, "forced symbol pays its multiplier")
    end,
}
