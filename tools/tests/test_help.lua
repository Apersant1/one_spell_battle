-- Справка: числа матча в osc_state/help, обновление после голосования

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/systems/chaos_events/registry")
    require("osc/systems/chaos_events/cooldowns")
    require("osc/systems/chaos_events/gold_rush")
    require("osc/systems/help")
    OSC_ABILITY_POOL = {
        { name = "test_a", hero = "npc_dota_hero_axe", label = "a", tags = { "damage" } },
        { name = "test_b", hero = "npc_dota_hero_axe", label = "b", tags = { "damage" }, rarity = "rare" },
        { name = "test_c", hero = "npc_dota_hero_axe", label = "c", tags = { "damage" }, rarity = "legendary" },
    }
end

return {
    publishes_match_numbers = function()
        setup()
        OSC_Help.Init()
        local help = H.netTables.help

        H.eq(help.rotation.interval, 60, "rotation interval")
        H.eq(help.anchor.merge_count, 2, "anchor merge count")
        H.eq(help.anchor.levels[3].name, "item_osc_anchor_3", "anchor levels in order")
        H.eq(help.casino.outcomes[4].multiplier, 30, "casino jackpot multiplier")
        H.eq(help.casino.item_value_pct, 50, "item bets at half price")
        H.eq(#help.chaos.events, 2, "registered events listed")
        H.eq(help.chaos.events[2].params.amount ~= nil, true, "description params resolved")
    end,

    rarity_shares_follow_weights = function()
        setup()
        local shares = OSC_Help.Build().rarity.ability

        -- веса 4 : 2 : 1 из ABILITY_RARITY_WEIGHT
        H.eq(shares.common, 57.1, "common share")
        H.eq(shares.rare, 28.6, "rare share")
        H.eq(shares.legendary, 14.3, "legendary share")
    end,

    vote_result_is_republished = function()
        setup()
        OSC_Help.Init()
        OSC_Config.SetOverride("ROTATION_INTERVAL", 90)

        OSC_GameEvents.Emit("config_overrides_applied", { overrides = { ROTATION_INTERVAL = 90 } })

        H.eq(H.netTables.help.rotation.interval, 90, "voted interval shown")
    end,
}
