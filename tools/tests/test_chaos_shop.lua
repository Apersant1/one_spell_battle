-- Хаос-лавка: покупка у магазина и в тайник, сток команды, отказы без
-- списания золота, выключенные товары

local REROLL, ANCHOR = "item_osc_ultimate_reroll", "item_osc_anchor"

-- opts: gold, alive, at_shop (по умолчанию герой жив и у магазина)
local function setup(opts)
    opts = opts or {}
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/chaos_shop")
    H.itemCosts = { [REROLL] = 3500, [ANCHOR] = 400 }
    local hero = H.NewHero({ alive = opts.alive })
    hero.at_shop = opts.at_shop ~= false
    H.AddPlayer(0, hero, { gold = opts.gold or 5000 })
    return hero
end

local function buy(item)
    OSC_ChaosShop.OnBuy(1, { PlayerID = 0, item = item })
end

local function shopItem(team, name)
    for _, item in ipairs(H.netTables["shop_" .. team].items) do
        if item.name == name then return item end
    end
end

local function fill(hero, first, last)
    for slot = first, last do
        hero.items[slot] = H.NewItem("item_branches")
    end
end

local function assertRefused(reason)
    local result = H.lastEvent("osc_shop_result")
    H.truthy(result, "result sent")
    H.eq(result.data.ok, 0, "refused")
    H.eq(result.data.error, reason, "error key")
    H.eq(H.lastEvent("osc_hud_error").data.message, reason, "HUD error")
end

return {
    init_publishes_both_teams = function()
        setup()
        OSC_ChaosShop.Init()
        for _, team in ipairs({ DOTA_TEAM_GOODGUYS, DOTA_TEAM_BADGUYS }) do
            local reroll = shopItem(team, REROLL)
            H.eq(reroll.cost, 3500, "reroll cost from KV")
            H.eq(reroll.stock, 5, "reroll stock")
            H.eq(reroll.max, 5, "reroll max")
            local anchor = shopItem(team, ANCHOR)
            H.eq(anchor.cost, 400, "anchor cost from KV")
            H.eq(anchor.stock, -1, "anchor unlimited stock")
            H.eq(anchor.max, -1, "anchor unlimited max")
        end
        H.truthy(H.listeners.osc_shop_buy, "listener registered")
    end,

    buy_at_shop_puts_item_in_inventory = function()
        local hero = setup()
        OSC_ChaosShop.Init()
        buy(REROLL)
        H.eq(H.players[0].gold, 1500, "gold charged by ItemCost")
        H.eq(hero.items[0] and hero.items[0].name, REROLL, "item in inventory")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 4, "team stock decreased")
        H.eq(shopItem(DOTA_TEAM_BADGUYS, REROLL).stock, 5, "other team untouched")
        local result = H.lastEvent("osc_shop_result")
        H.eq(result.data.ok, 1, "success result")
        H.eq(result.data.item, REROLL, "result item")
    end,

    unknown_item_refused_silently = function()
        local hero = setup()
        OSC_ChaosShop.Init()
        buy("item_rapier")
        H.eq(H.players[0].gold, 5000, "gold untouched")
        H.eq(hero.items[0], nil, "no item")
        H.eq(H.lastEvent("osc_shop_result"), nil, "no reply to a forged request")
        H.truthy(H.logged("Chaos shop purchase of player 0 refused: invalid_item"), "refusal logged")
    end,

    not_enough_gold_refused = function()
        local hero = setup({ gold = 1000 })
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_no_gold")
        H.eq(H.players[0].gold, 1000, "gold untouched")
        H.eq(hero.items[0], nil, "no item")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 5, "stock untouched")
    end,

    stock_runs_out = function()
        setup({ gold = 100000 })
        OSC_ChaosShop.Init()
        for _ = 1, 5 do buy(REROLL) end
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 0, "stock empty")
        buy(REROLL)
        assertRefused("osc_shop_err_no_stock")
        H.eq(H.players[0].gold, 100000 - 5 * 3500, "sixth not charged")
    end,

    away_from_shop_goes_to_stash = function()
        local hero = setup({ at_shop = false })
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        H.eq(hero.items[0], nil, "not in inventory")
        H.eq(hero.items[DOTA_STASH_SLOT_1] and hero.items[DOTA_STASH_SLOT_1].name, ANCHOR, "in stash")
        H.eq(H.players[0].gold, 4600, "charged")
    end,

    dead_hero_goes_to_stash = function()
        local hero = setup({ alive = false })
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        H.eq(hero.items[0], nil, "not in inventory")
        H.eq(hero.items[DOTA_STASH_SLOT_1] and hero.items[DOTA_STASH_SLOT_1].name, ANCHOR, "in stash")
    end,

    full_inventory_at_shop_goes_to_stash = function()
        local hero = setup()
        fill(hero, 0, 8)
        local backpackItem = hero.items[8]
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        H.eq(hero.items[DOTA_STASH_SLOT_1] and hero.items[DOTA_STASH_SLOT_1].name, ANCHOR, "in stash")
        H.eq(hero.items[8], backpackItem, "own backpack item back in place")
        H.eq(H.players[0].gold, 4600, "charged")
    end,

    stash_full_refused_without_charge = function()
        local hero = setup({ at_shop = false })
        fill(hero, DOTA_STASH_SLOT_1, DOTA_STASH_SLOT_6)
        OSC_ChaosShop.Init()
        buy(ANCHOR)
        assertRefused("osc_shop_err_no_space")
        H.eq(H.players[0].gold, 5000, "gold untouched")
        H.eq(hero.items[0], nil, "no item")
    end,

    anchor_disabled = function()
        setup()
        OSC_CONFIG.ANCHOR_ENABLED = false
        OSC_ChaosShop.Init()
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, ANCHOR), nil, "anchor not in net table")
        H.truthy(shopItem(DOTA_TEAM_GOODGUYS, REROLL), "reroll still sold")
        buy(ANCHOR)
        assertRefused("osc_shop_err_disabled")
        H.eq(H.players[0].gold, 5000, "gold untouched")
    end,

    shop_disabled_ignores_event = function()
        setup()
        OSC_CONFIG.CHAOS_SHOP_ENABLED = false
        OSC_ChaosShop.Init()
        H.eq(H.listeners.osc_shop_buy, nil, "no listener")
        H.eq(H.netTables["shop_" .. DOTA_TEAM_GOODGUYS], nil, "nothing published")
    end,

    zero_cost_refused = function()
        local hero = setup()
        H.itemCosts[REROLL] = 0
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_disabled")
        H.eq(hero.items[0], nil, "not given for free")
    end,

    partial_charge_refunded = function()
        local hero = setup()
        PlayerResource.SpendGold = function(_, id) H.players[id].gold = H.players[id].gold - 100 end
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_no_gold")
        H.eq(H.players[0].gold, 5000, "partial charge returned")
        H.eq(hero.items[0], nil, "no item")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 5, "stock untouched")
    end,

    failed_give_refunds_gold = function()
        setup()
        CreateItem = function() return nil end
        OSC_ChaosShop.Init()
        buy(REROLL)
        assertRefused("osc_shop_err_no_space")
        H.eq(H.players[0].gold, 5000, "gold returned")
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, REROLL).stock, 5, "stock untouched")
    end,

    stacked_anchor_counts_as_bought = function()
        local hero = setup()
        OSC_ChaosShop.Init()
        local held = H.NewItem(ANCHOR)
        hero.items[2] = held
        -- Как Dota со стакающимся предметом: заряд вливается в лежащий
        hero.AddItem = function(_, item)
            held.charges = held.charges + item.charges
            item._removed = true
        end

        buy(ANCHOR)

        H.eq(held.charges, 2, "charge added to the stack")
        H.eq(H.players[0].gold, 4600, "charged, not refunded")
        H.eq(H.lastEvent("osc_shop_result").data.ok, 1, "success result")
    end,

    every_anchor_level_is_sold = function()
        setup()
        OSC_ChaosShop.Init()
        for _, name in ipairs({ "item_osc_anchor_2", "item_osc_anchor_3" }) do
            H.truthy(shopItem(DOTA_TEAM_GOODGUYS, name), name .. " in the shop")
        end
        OSC_CONFIG.ANCHOR_ENABLED = false
        OSC_ChaosShop.Publish(DOTA_TEAM_GOODGUYS)
        H.eq(shopItem(DOTA_TEAM_GOODGUYS, "item_osc_anchor_3"), nil, "flag hides every level")
    end,
}
