-- 2.1: голосование в лобби

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/core/game_events")
    require("osc/systems/vote")
    OSC_GameEvents.Init()
    OSC_Vote.Init()
    for playerID = 0, 3 do
        H.AddPlayer(playerID, nil)
    end
end

local function enterState(state)
    H.state = state
    H.FireGameEvent("game_rules_state_change", {})
end

local function cast(playerID, question, option)
    H.listeners.osc_vote_cast(playerID + 1, { PlayerID = playerID, question = question, option = option })
end

return {
    opens_on_hero_selection = function()
        setup()
        H.eq(H.netTables.vote, nil, "nothing before hero selection")

        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)

        local vote = H.netTables.vote
        H.eq(vote.open, 1, "open")
        H.eq(vote.questions[1].id, "rotation_interval", "first question")
        H.eq(vote.questions[1].options[2], "60", "options are strings")
        H.eq(vote.questions[2].default, "normal", "default sent")
        H.eq(vote.questions[3].options[2], "off", "casino options")
        H.eq(vote.counts.rotation_interval["30"], 0, "zero counts")
        H.eq(next(vote.result), nil, "no result while open")
        H.eq(H.netTables.vote_2.chaos_frequency, "", "ballot published with empty answers")
        H.eq(OSC_Vote.ValidateQuestions()[1], nil, "config questions are valid")
    end,

    vote_can_be_changed = function()
        setup()
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)

        cast(0, "rotation_interval", "30")
        cast(0, "rotation_interval", "90")
        cast(1, "casino", "off")
        H.RunThink("osc_vote_publish")

        H.eq(H.netTables.vote_0.rotation_interval, "90", "ballot shows the last choice")
        H.eq(H.netTables.vote_0.casino, "", "unanswered question")
        H.eq(H.netTables.vote.counts.rotation_interval["30"], 0, "old vote removed")
        H.eq(H.netTables.vote.counts.rotation_interval["90"], 1, "new vote counted")
        H.eq(H.netTables.vote.counts.casino.off, 1, "other player counted")
    end,

    forged_votes_are_refused_silently = function()
        setup()
        cast(0, "casino", "off") -- голосование ещё не открыто
        H.eq(H.netTables.vote_0, nil, "closed vote ignored")

        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        local vote, ballot = H.netTables.vote, H.netTables.vote_0

        cast(0, "gold_multiplier", "on")                         -- нет такого вопроса
        cast(0, "casino", "maybe")                               -- нет такого варианта
        cast(0, "casino", 1)                                     -- не строка
        cast(0, "rotation_interval", "off")                      -- вариант другого вопроса
        H.listeners.osc_vote_cast(1, { PlayerID = 9, question = "casino", option = "off" })
        H.listeners.osc_vote_cast(1, { question = "casino", option = "off" })

        H.eq(H.netTables.vote, vote, "vote net table untouched")
        H.eq(H.netTables.vote_0, ballot, "ballot untouched")
        H.eq(next(OSC_Vote.votes), nil, "nothing recorded")

        enterState(DOTA_GAMERULES_STATE_PRE_GAME)
        vote = H.netTables.vote
        cast(0, "casino", "off")
        H.eq(H.netTables.vote, vote, "vote after closing ignored")
    end,

    majority_wins_tie_and_silence_give_default = function()
        setup()
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        cast(0, "rotation_interval", "30")
        cast(1, "rotation_interval", "30")
        cast(2, "rotation_interval", "90")
        cast(0, "chaos_frequency", "rare")
        cast(1, "chaos_frequency", "often")

        local result = OSC_Vote.Tally()

        H.eq(result.rotation_interval, "30", "majority")
        H.eq(result.chaos_frequency, "normal", "tie gives the default")
        H.eq(result.casino, "on", "no votes give the default")
    end,

    close_applies_overrides_without_touching_config = function()
        setup()
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        cast(0, "rotation_interval", "30")
        cast(0, "chaos_frequency", "often")
        cast(0, "casino", "off")

        enterState(DOTA_GAMERULES_STATE_PRE_GAME)

        local vote = H.netTables.vote
        H.eq(vote.open, 0, "closed")
        H.eq(vote.result.rotation_interval, "30", "result published")
        H.eq(vote.result.casino, "off", "casino result")
        H.eq(OSC_Config.Get("ROTATION_INTERVAL"), 30, "interval override")
        H.eq(OSC_Config.Get("CHAOS_ROUNDS.INTERVAL"), 120, "chaos frequency override")
        H.eq(OSC_Config.Get("CASINO_ENABLED"), false, "casino override")
        H.eq(OSC_CONFIG.ROTATION_INTERVAL, 60, "OSC_CONFIG untouched")
        H.eq(OSC_CONFIG.CHAOS_ROUNDS.INTERVAL, 200, "nested OSC_CONFIG untouched")
        H.eq(OSC_CONFIG.CASINO_ENABLED, true, "casino flag untouched")
        H.truthy(H.lastEvent("osc_notification"), "result announced")

        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        H.eq(H.netTables.vote.open, 0, "vote does not reopen")
    end,

    systems_read_voted_values_after_close = function()
        setup()
        require("osc/systems/abilities")
        require("osc/systems/rotation")
        require("osc/systems/chaos_events/registry")
        require("osc/systems/chaos_rounds")
        require("osc/systems/casino")
        OSC_Rotation.Init()
        OSC_ChaosRounds:Init()
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        cast(0, "rotation_interval", "90")
        cast(0, "chaos_frequency", "rare")
        cast(0, "casino", "off")

        -- Стадии могут смениться сразу на игру: голосование закрывается раньше game_started
        enterState(DOTA_GAMERULES_STATE_GAME_IN_PROGRESS)

        H.eq(OSC_Rotation.next_time, 90, "rotation timer uses the voted interval")
        H.eq(H.netTables.timer.interval, 90, "HUD timer interval")
        H.eq(OSC_ChaosRounds.nextStart, 300, "first chaos round after the rare interval")

        H.DefineAbility("ogre_magi_casino")
        local ogre = H.NewHero({ name = "npc_dota_hero_ogre_magi", playerID = 0 })
        H.players[0].hero = ogre
        OSC_Abilities.SyncHeroExtras(ogre)
        H.eq(ogre:FindAbilityByName("ogre_magi_casino"), nil, "casino ability not granted")
        H.eq(OSC_Casino.SpawnMachine(ogre), false, "machine refused")
        H.eq(H.lastEvent("osc_hud_error").data.message, "osc_casino_err_disabled", "player told why")
    end,

    disabled_vote_does_nothing = function()
        setup()
        OSC_CONFIG.VOTE_ENABLED = false

        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        cast(0, "rotation_interval", "30")
        enterState(DOTA_GAMERULES_STATE_PRE_GAME)

        H.eq(H.netTables.vote, nil, "no vote net table")
        H.eq(next(OSC_Config.Overrides()), nil, "no overrides")
    end,

    reload_in_the_middle_keeps_votes = function()
        setup()
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        cast(0, "rotation_interval", "30")

        for _, name in ipairs({ "osc/config/config", "osc/core/runtime_config", "osc/systems/vote" }) do
            package.loaded[name] = nil
            require(name)
        end
        cast(1, "rotation_interval", "30")
        enterState(DOTA_GAMERULES_STATE_PRE_GAME)

        H.eq(H.netTables.vote.counts.rotation_interval["30"], 2, "votes kept across reload")
        H.eq(OSC_Config.Get("ROTATION_INTERVAL"), 30, "result applied")
    end,

    open_through_strategy_closed_on_pre_game = function()
        setup()
        local applied = {}
        OSC_GameEvents.Subscribe("config_overrides_applied", "test", function(change)
            table.insert(applied, change)
        end)
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)

        for _, state in ipairs({ DOTA_GAMERULES_STATE_STRATEGY_TIME, DOTA_GAMERULES_STATE_TEAM_SHOWCASE,
            DOTA_GAMERULES_STATE_WAIT_FOR_MAP_TO_LOAD }) do
            enterState(state)
            H.eq(OSC_Vote.open, true, "still open in state " .. state)
        end
        cast(0, "rotation_interval", "90")
        H.eq(OSC_Vote.votes[0].rotation_interval, "90", "vote accepted during strategy time")

        enterState(DOTA_GAMERULES_STATE_PRE_GAME)
        H.eq(OSC_Vote.open, false, "closed on pre-game")
        H.eq(#applied, 1, "overrides announced on the bus")
        H.eq(applied[1].overrides.ROTATION_INTERVAL, 90, "voted interval in the event")
        H.eq(applied[1].overrides.CASINO_ENABLED, true, "defaults are announced too")
    end,

    same_vote_is_ignored = function()
        setup()
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        cast(0, "casino", "off")
        H.RunThink("osc_vote_publish")
        local ballot, vote = H.netTables.vote_0, H.netTables.vote

        cast(0, "casino", "off")

        H.eq(H.netTables.vote_0, ballot, "ballot not republished")
        H.eq(H.thinks.osc_vote_publish, nil, "counts not scheduled")
        H.eq(H.netTables.vote, vote, "vote net table untouched")
    end,

    counts_published_in_batches = function()
        setup()
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        local opened = H.netTables.vote

        cast(0, "casino", "off")
        cast(1, "casino", "off")
        cast(2, "rotation_interval", "30")

        H.eq(H.netTables.vote, opened, "counts wait for the batch")
        H.eq(H.netTables.vote_1.casino, "off", "own ballot published at once")
        H.eq(H.thinks.osc_vote_publish.delay, OSC_CONFIG.VOTE_PUBLISH_INTERVAL, "one timer, interval from config")

        H.eq(H.RunThink("osc_vote_publish"), nil, "timer ends itself")
        H.eq(H.netTables.vote.counts.casino.off, 2, "batch published")

        cast(3, "casino", "on")
        enterState(DOTA_GAMERULES_STATE_PRE_GAME)
        H.eq(H.netTables.vote.counts.casino.on, 1, "final publication on close is immediate")
        H.eq(H.netTables.vote.open, 0, "closed state published")
        local final = H.netTables.vote
        H.RunThink("osc_vote_publish")
        H.eq(H.netTables.vote, final, "pending timer does not republish after close")
    end,

    vote_result_resyncs_casino_of_picked_ogre = function()
        setup()
        require("osc/systems/abilities")
        require("osc/systems/hero_lifecycle")
        require("osc/systems/casino")
        OSC_HeroLifecycle.Init()
        OSC_Casino.Init()
        H.DefineAbility("test_a")
        H.DefineAbility("ogre_magi_casino")
        OSC_ABILITY_POOL = { { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } } }
        local ogre = H.NewHero({ name = "npc_dota_hero_ogre_magi", playerID = 0 })
        H.players[0].hero = ogre
        local machine = H.NewHero({ name = "npc_osc_casino_test_object", playerID = 0 })
        machine.index = 50

        -- Огр пикнут и инициализирован до закрытия голосования
        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        OSC_HeroLifecycle.TryInitializeUnit(ogre, "test")
        H.RunThink("osc_init")
        H.eq(ogre:GetAbilityByIndex(1).name, "ogre_magi_casino", "casino granted at pick")
        OSC_HeroState.Get(ogre).casino_machine = machine
        machine.osc_casino_owner_hero = ogre

        cast(0, "casino", "off")
        enterState(DOTA_GAMERULES_STATE_PRE_GAME)

        local casino = ogre:FindAbilityByName("ogre_magi_casino")
        H.eq(casino:IsHidden(), true, "casino ability retired")
        H.eq(machine:IsNull(), true, "placed machine removed")
        H.RunThinksMatching("osc_retire_ability")
        H.eq(ogre:FindAbilityByName("ogre_magi_casino"), nil, "casino ability gone")
    end,

    vote_can_turn_casino_on = function()
        setup()
        require("osc/systems/abilities")
        require("osc/systems/hero_lifecycle")
        OSC_HeroLifecycle.Init()
        OSC_CONFIG.CASINO_ENABLED = false
        OSC_CONFIG.VOTE_QUESTIONS[3].default = "off"
        H.DefineAbility("test_a")
        H.DefineAbility("ogre_magi_casino")
        H.DefineAbility("test_innate", { innate = true })
        OSC_ABILITY_POOL = { { name = "test_a", hero = "npc_dota_hero_axe", label = "A", tags = { "damage" } } }
        local ogre = H.NewHero({ name = "npc_dota_hero_ogre_magi", playerID = 0 })
        H.players[0].hero = ogre

        enterState(DOTA_GAMERULES_STATE_HERO_SELECTION)
        OSC_HeroLifecycle.TryInitializeUnit(ogre, "test")
        H.RunThink("osc_init")
        H.eq(ogre:FindAbilityByName("ogre_magi_casino"), nil, "no casino while it is off")
        ogre:AddAbility("test_innate") -- слот W занят служебной способностью

        cast(0, "casino", "on")
        enterState(DOTA_GAMERULES_STATE_PRE_GAME)

        H.eq(ogre:GetAbilityByIndex(0).name, "test_a", "main ability stays on Q")
        H.eq(ogre:GetAbilityByIndex(1).name, "ogre_magi_casino", "casino put on W")
        H.eq(ogre:GetAbilityByIndex(1):GetLevel(), 1, "casino learned")
        H.eq(ogre:GetAbilityByIndex(1):IsHidden(), false, "casino visible")
        H.truthy(ogre:FindAbilityByName("test_innate"), "displaced ability kept")
    end,
}
