-- 2.3: итоги матча и титулы

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/core/game_events")
    require("osc/systems/stats")
    require("osc/systems/summary")
    OSC_GameEvents.Init()
    OSC_Stats.Init()
    OSC_Summary.Init()
end

local function player(playerID, name)
    local hero = H.NewHero({ playerID = playerID, name = name or "npc_dota_hero_axe" })
    H.AddPlayer(playerID, hero)
    return hero
end

local function stats(fields)
    local record = { hero = "", rotations = 0, abilities = {}, kills = 0,
        kill_abilities = {}, casino_net = 0, chaos_damage = 0 }
    for key, value in pairs(fields) do record[key] = value end
    return record
end

local function titlesById()
    local result = {}
    for _, title in ipairs(H.netTables.summary.titles) do
        result[title.id] = title
    end
    return result
end

return {
    post_game_builds_summary_from_stats = function()
        setup()
        player(0, "npc_dota_hero_lina")
        player(1)
        OSC_GameEvents.Emit("ability_changed",
            { player_id = 0, slot = "ability", ability = "test_a" })
        OSC_GameEvents.Emit("ability_changed",
            { player_id = 0, slot = "ability", ability = "test_b", previous = "test_a" })
        OSC_GameEvents.Emit("casino_spin_resolved", { player_id = 0, net = -150 })
        OSC_Stats.Player(0).kill_abilities = { test_a = 2, test_b = 1 }
        OSC_Stats.Player(0).kills = 3
        OSC_Stats.Player(0).chaos_damage = 123.6

        H.state = DOTA_GAMERULES_STATE_POST_GAME
        H.FireGameEvent("game_rules_state_change", {})

        local row = H.netTables.summary.players["0"]
        H.eq(row.hero, "npc_dota_hero_lina", "hero")
        H.eq(row.rotations, 1, "rotations")
        H.eq(row.abilities, nil, "ability list is not sent to the HUD")
        H.eq(row.distinct_kill_abilities, 2, "distinct kill abilities")
        H.eq(row.kills, 3, "kills")
        H.eq(row.casino_net, -150, "casino net")
        H.eq(row.chaos_damage, 123, "chaos damage rounded down")
        H.eq(H.netTables.summary.players["1"].kills, 0, "player without events listed with zeros")
    end,

    titles_pick_best_and_skip_zero = function()
        setup()
        for playerID = 0, 3 do player(playerID) end

        OSC_Summary.Publish({
            [0] = stats({ casino_net = -300, abilities = { "a", "b", "a" }, chaos_damage = 10 }),
            [1] = stats({ casino_net = 500, kill_abilities = { a = 1, b = 1 }, chaos_damage = 900 }),
            [2] = stats({ casino_net = -50, abilities = { "a", "b", "c" }, kill_abilities = { a = 5 } }),
        })

        local titles = titlesById()
        H.eq(titles.gambler.player_id, 0, "worst casino result")
        H.eq(titles.gambler.value, -300, "gambler value")
        H.eq(titles.lucky.player_id, 1, "best casino result")
        H.eq(titles.chaos_master.player_id, 1, "most distinct kill abilities")
        H.eq(titles.chaos_master.value, 2, "chaos master value")
        H.eq(titles.collector.player_id, 2, "most distinct received abilities")
        H.eq(titles.collector.value, 3, "collector value")
        H.eq(titles.storm_chaser.player_id, 1, "most chaos damage")
        H.eq(H.netTables.summary.titles[1].id, "gambler", "order from config")
    end,

    no_titles_without_data = function()
        setup()
        player(0)
        player(1)

        OSC_Summary.Publish({ [0] = stats({ casino_net = 200 }) })

        local titles = titlesById()
        H.eq(titles.gambler, nil, "no negative casino result — no gambler")
        H.eq(titles.lucky.player_id, 0, "lucky given")
        H.eq(titles.chaos_master, nil, "no kills — no chaos master")
        H.eq(titles.collector, nil, "no abilities — no collector")
        H.eq(titles.storm_chaser, nil, "no chaos damage — no storm chaser")
    end,

    ties_give_no_title_by_default = function()
        setup()
        for playerID = 0, 4 do player(playerID) end
        H.eq(OSC_CONFIG.SUMMARY_TITLE_TIES, "none", "default rule")

        OSC_Summary.Publish({
            [4] = stats({ chaos_damage = 500, casino_net = -100 }),
            [2] = stats({ chaos_damage = 500, casino_net = -100 }),
            [3] = stats({ chaos_damage = 100, casino_net = 300 }),
        })

        local titles = titlesById()
        H.eq(titles.storm_chaser, nil, "tie for the most chaos damage: no title")
        H.eq(titles.gambler, nil, "tie for the worst casino result: no title")
        H.eq(titles.lucky.player_id, 3, "unique best still gets a title")
    end,

    ties_go_to_the_smaller_player_id_when_configured = function()
        setup()
        OSC_CONFIG.SUMMARY_TITLE_TIES = "lowest_player_id"
        for playerID = 0, 4 do player(playerID) end

        OSC_Summary.Publish({
            [4] = stats({ chaos_damage = 500, casino_net = -100 }),
            [2] = stats({ chaos_damage = 500, casino_net = -100 }),
        })

        local titles = titlesById()
        H.eq(titles.storm_chaser.player_id, 2, "tie: smaller player id")
        H.eq(titles.gambler.player_id, 2, "tie for the worst result: smaller player id")
    end,

    thresholds_from_config = function()
        setup()
        player(0)
        OSC_CONFIG.SUMMARY_TITLE_MIN = { storm_chaser = 1000, gambler = 1, lucky = 1,
            chaos_master = 1, collector = 1 }

        OSC_Summary.Publish({ [0] = stats({ chaos_damage = 999, abilities = { "a", "b", "c", "d" } }) })

        H.eq(titlesById().storm_chaser, nil, "below the threshold")
        H.eq(titlesById().collector.value, 4, "collector counts the full list from stats")
    end,

    disabled_flag_publishes_nothing = function()
        setup()
        OSC_CONFIG.SUMMARY_ENABLED = false
        player(0)

        H.state = DOTA_GAMERULES_STATE_POST_GAME
        H.FireGameEvent("game_rules_state_change", {})

        H.eq(H.netTables.summary, nil, "no summary")
    end,
}
