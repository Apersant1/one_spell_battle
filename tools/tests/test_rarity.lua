-- Редкость способностей: вес, проверка пулов, фильтр кандидатов, клиент,
-- объявление легендарки

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/systems/abilities")
    require("osc/systems/rotation_choice")
end

-- Теги разные, чтобы правило серии тегов не вмешивалось в выбор
local TAGS = { "damage", "disable", "mobility", "passive", "support" }
local tagIndex = 0

local function entry(name, rarity, weight)
    H.DefineAbility(name)
    tagIndex = tagIndex % #TAGS + 1
    return { name = name, hero = "npc_dota_hero_axe", label = name,
        tags = { TAGS[tagIndex] }, rarity = rarity, weight = weight }
end

local function heroWith(name)
    local hero = H.NewHero({ abilities = { name }, level = 3 })
    H.AddPlayer(0, hero)
    local state = OSC_HeroState.Get(hero)
    state.ability = name
    state.initialized = true
    return hero
end

local function countLogs(pattern)
    local count = 0
    for _, line in ipairs(H.logs) do
        if string.find(line, pattern, 1, true) then count = count + 1 end
    end
    return count
end

return {
    weight_multiplied_by_rarity = function()
        setup()
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_c")), 16, "common: 4 x 4")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_r", "rare")), 8, "rare: 4 x 2")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_l", "legendary")), 4, "legendary: 4 x 1")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_l2", "legendary", 2)), 2, "own weight kept")
        H.eq(OSC_AbilitySelection.GetRarity(entry("test_r2", "rare")), "rare", "rarity read")
        H.eq(OSC_AbilitySelection.GetRarity(entry("test_c2")), "common", "no field = common")
        H.eq(OSC_AbilitySelection.GetRarity(nil), "common", "nil entry = common")
    end,

    flag_off_ignores_rarity = function()
        setup()
        OSC_CONFIG.ABILITY_RARITY_ENABLED = false
        local legendary = entry("test_l", "legendary")
        H.eq(OSC_AbilitySelection.GetWeight(legendary), 4, "no multiplier")
        H.eq(OSC_AbilitySelection.GetRarity(legendary), "common", "everything common")
    end,

    bad_multiplier_logged_once = function()
        setup()
        OSC_CONFIG.ABILITY_RARITY_WEIGHT = { common = 4, rare = 0, legendary = 1.5 }
        local rare = entry("test_r", "rare")
        H.eq(OSC_AbilitySelection.GetWeight(rare), 4, "bad multiplier -> 1")
        H.eq(OSC_AbilitySelection.GetWeight(rare), 4, "still 1")
        H.eq(OSC_AbilitySelection.GetWeight(entry("test_l", "legendary")), 4, "fraction -> 1")
        H.eq(countLogs("ABILITY_RARITY_WEIGHT.rare"), 1, "rare error logged once")
        H.eq(countLogs("ABILITY_RARITY_WEIGHT.legendary"), 1, "legendary error logged once")
    end,

    validate_removes_invalid_rarity = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_ok", "rare"), entry("test_plain", "common"), entry("test_epic", "epic"),
        }
        H.DefineAbility("test_ult", { ultimate = true })
        OSC_ULTIMATE_POOL = { { name = "test_ult", hero = "npc_dota_hero_axe", label = "U", tags = { "damage" } } }

        local removed = OSC_AbilitySelection.ValidatePools()

        H.eq(removed, 1, "only the bad rarity removed")
        H.eq(#OSC_ABILITY_POOL, 2, "rare and explicit common kept")
        H.truthy(H.logged("test_epic (invalid rarity epic)"), "reason logged")
    end,

    rarity_filter_returns_only_that_rarity = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_c1"), entry("test_c2"), entry("test_c3"),
            entry("test_l1", "legendary"), entry("test_l2", "legendary"), entry("test_l3", "legendary"),
        }
        local hero = heroWith("test_c1")
        for _ = 1, 20 do
            local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3, { rarity = "legendary" })
            H.eq(#picked, 3, "three candidates")
            for _, item in ipairs(picked) do
                H.eq(item.rarity, "legendary", "only legendary " .. item.name)
            end
        end
    end,

    rarity_filter_fills_without_duplicates = function()
        setup()
        OSC_ABILITY_POOL = {
            entry("test_c1"), entry("test_c2"), entry("test_c3"), entry("test_c4"),
            entry("test_l1", "legendary"),
        }
        local hero = heroWith("test_c1")
        for _ = 1, 20 do
            local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3, { rarity = "legendary" })
            H.eq(#picked, 3, "filled up to count")
            H.eq(picked[1].name, "test_l1", "legendary first")
            local seen = {}
            for _, item in ipairs(picked) do
                H.eq(seen[item.name], nil, "no duplicates: " .. item.name)
                H.truthy(item.name ~= "test_c1", "current ability not offered")
                seen[item.name] = true
            end
        end
    end,

    rarity_filter_without_matches_still_picks = function()
        setup()
        OSC_CONFIG.ABILITY_RARITY_ENABLED = false -- все записи считаются обычными
        OSC_ABILITY_POOL = {
            entry("test_c1"), entry("test_c2"), entry("test_c3"), entry("test_l1", "legendary"),
        }
        local hero = heroWith("test_c1")
        local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3, { rarity = "legendary" })
        H.eq(#picked, 3, "picked from the whole pool without error")
    end,

    rarity_filter_never_offers_current = function()
        setup()
        OSC_ABILITY_POOL = { entry("test_l1", "legendary"), entry("test_c1"), entry("test_c2") }
        local hero = heroWith("test_l1")
        for _ = 1, 20 do
            local picked = OSC_AbilitySelection.PickCandidates(hero, "ability", 3, { rarity = "legendary" })
            H.eq(#picked, 2, "only the other entries")
            for _, item in ipairs(picked) do
                H.truthy(item.name ~= "test_l1", "current legendary not offered")
            end
        end
    end,
}
