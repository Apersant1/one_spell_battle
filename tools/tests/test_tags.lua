-- 1.3: теги в пулах, серия одинаковых тегов, выбор нескольких кандидатов

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
end

local function entry(name, tags)
    H.DefineAbility(name)
    return { name = name, hero = "npc_dota_hero_axe", label = name, tags = tags }
end

local function heroWith(name)
    local hero = H.NewHero({ abilities = { name }, level = 3 })
    H.AddPlayer(0, hero)
    OSC_HeroState.Get(hero).ability = name
    return hero
end

-- История тегов основного слота, старые первыми
local function history(hero, ...)
    OSC_HeroState.Get(hero).recent_tags.ability = { ... }
end

local function names(entries)
    local result = {}
    for _, item in ipairs(entries) do result[item.name] = true end
    return result
end

return {
    validate_checks_tags = function()
        setup()
        H.DefineAbility("test_ult", { ultimate = true })
        OSC_ABILITY_POOL = {
            entry("test_ok", { "damage", "disable" }),
            entry("test_none", nil),
            entry("test_empty", {}),
            entry("test_unknown", { "healing" }),
            entry("test_twice", { "damage", "damage" }),
        }
        OSC_ULTIMATE_POOL = { entry("test_ult", { "damage" }) }

        local removed = OSC_AbilitySelection.ValidatePools()

        H.eq(removed, 4, "entries with bad tags removed")
        H.eq(#OSC_ABILITY_POOL, 1, "valid entry kept")
        H.truthy(H.logged("test_none (invalid tags: no tags)"), "missing tags logged")
        H.truthy(H.logged("test_unknown (invalid tags: unknown tag healing)"), "unknown tag logged")
        H.truthy(H.logged("test_twice (invalid tags: duplicate tag damage)"), "duplicate logged")
    end,

    every_pool_entry_has_valid_tags = function()
        setup()
        for _, pool in ipairs({ OSC_ABILITY_POOL, OSC_ULTIMATE_POOL }) do
            for _, item in ipairs(pool) do
                H.DefineAbility(item.name)
                for _, link in ipairs(item.linked or {}) do H.DefineAbility(link.name) end
            end
        end
        local before = #OSC_ABILITY_POOL + #OSC_ULTIMATE_POOL

        local removed = OSC_AbilitySelection.ValidatePools()

        H.eq(removed, 0, "nothing removed from the real pools")
        H.eq(#OSC_ABILITY_POOL + #OSC_ULTIMATE_POOL, before, "pool sizes")
    end,

    third_same_tag_in_a_row_is_skipped = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_d1", { "damage" }), entry("test_d2", { "damage" }),
            entry("test_d3", { "damage" }), entry("test_s", { "support" }),
        }
        local hero = heroWith("test_d1")

        for _ = 1, 10 do
            OSC_HeroState.Get(hero).ability = "test_d1"
            history(hero, { "damage" }, { "damage" })
            H.eq(OSC_AbilitySelection.Pick(hero, "ability").name, "test_s", "only non-damage left")
        end
    end,

    streak_is_counted_per_tag = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_dd", { "disable", "damage" }),
            entry("test_dis", { "disable" }),
            entry("test_cur", { "mobility" }),
        }
        local hero = heroWith("test_cur")
        -- damage — два раза подряд, disable — только один (у последней его нет)
        history(hero, { "damage", "disable" }, { "damage" })

        for _ = 1, 10 do
            H.eq(OSC_AbilitySelection.Pick(hero, "ability").name, "test_dis",
                "an entry with any exhausted tag is skipped")
        end
    end,

    rule_relaxed_when_nothing_else = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_d1", { "damage" }), entry("test_d2", { "damage" }),
        }
        local hero = heroWith("test_d1")
        history(hero, { "damage" }, { "damage" })

        H.eq(OSC_AbilitySelection.Pick(hero, "ability").name, "test_d2", "damage given anyway")
        H.truthy(H.logged("relaxed to rule 'base'"), "relaxation logged")
    end,

    rule_disabled_by_flag = function()
        setup()
        OSC_CONFIG.ABILITY_TAG_STREAK_ENABLED = false
        OSC_ABILITY_POOL = { entry("test_d1", { "damage" }), entry("test_d2", { "damage" }),
            entry("test_s", { "support" }) }
        local hero = heroWith("test_d1")
        history(hero, { "damage" }, { "damage" })

        local seen = {}
        for _ = 1, 30 do seen[OSC_AbilitySelection.Pick(hero, "ability").name] = true end

        H.truthy(seen.test_d2, "damage allowed again")
    end,

    rotation_records_given_tags = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_d1", { "damage" }), entry("test_d2", { "damage" }),
            entry("test_m", { "mobility" }),
        }
        local hero = heroWith("test_d1")
        history(hero, { "damage" })

        OSC_Abilities.Give(hero, "ability", OSC_ABILITY_POOL[2], false)
        local recent = OSC_HeroState.Get(hero).recent_tags.ability
        H.eq(#recent, 2, "history kept to MAX_SAME_TAG_STREAK")
        H.eq(recent[2][1], "damage", "latest tags recorded")

        OSC_Abilities.GiveRandom(hero, false)
        H.eq(OSC_HeroState.Get(hero).ability, "test_m", "third damage in a row avoided")
        H.eq(#OSC_HeroState.Get(hero).recent_tags.ability, 2, "history trimmed")
        H.eq(#OSC_HeroState.Get(hero).recent_tags.ultimate, 0, "ultimate history separate")
    end,

    candidates_are_distinct_strict_first = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_cur", { "damage" }), entry("test_d2", { "damage" }),
            entry("test_d3", { "damage" }), entry("test_s", { "support" }),
            entry("test_m", { "mobility" }),
        }
        local hero = heroWith("test_cur")
        history(hero, { "damage" }, { "damage" })

        local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3)
        local set = names(picked)

        H.eq(#picked, 3, "three candidates")
        H.truthy(set.test_s and set.test_m, "strict candidates first")
        H.eq(set.test_cur, nil, "current ability never offered")
        H.truthy(set.test_d2 or set.test_d3, "missing one filled from the relaxed rule")

        local all = OSC_AbilitySelection.PickCandidates(hero, "ability", 10)
        H.eq(#all, 4, "no duplicates, current excluded")

        local rest = OSC_AbilitySelection.PickCandidates(hero, "ability", 3,
            { exclude = { "test_s", "test_m" } })
        H.eq(names(rest).test_s, nil, "excluded names skipped")
        H.eq(#rest, 2, "only the remaining entries")
    end,

    ultimate_candidates_respect_team_limit = function()
        setup()
        OSC_CONFIG.MAX_DUPLICATE_ULTIMATES_PER_TEAM = 1
        H.DefineAbility("test_u1", { ultimate = true })
        H.DefineAbility("test_u2", { ultimate = true })
        OSC_ULTIMATE_POOL = {
            { name = "test_u1", hero = "npc_dota_hero_axe", label = "U1", tags = { "damage" } },
            { name = "test_u2", hero = "npc_dota_hero_axe", label = "U2", tags = { "damage" } },
        }
        local hero = H.NewHero({ level = 6 })
        H.AddPlayer(0, hero)
        local ally = H.NewHero({ level = 6 })
        H.AddPlayer(1, ally)
        OSC_HeroState.Get(ally).ultimate = "test_u1"

        local picked = OSC_AbilitySelection.PickCandidates(hero, "ultimate", 3)

        H.eq(#picked, 1, "only one allowed")
        H.eq(picked[1].name, "test_u2", "ally's ultimate excluded")
    end,
}
