-- Справка (osc_help.ts): числа текущего матча для её разделов. Тексты — в
-- локализации, здесь только значения из конфига, пулов и хаос-событий.
--
-- Net table osc_state/help публикуется в Init и заново после итогов
-- голосования (config_overrides_applied), чтобы справка показывала
-- выбранные значения. Флаги передаются числами 1/0.

require("osc/core/runtime_config")
require("osc/core/game_events")
require("osc/core/anchor")
require("osc/systems/ability_selection")
require("osc/systems/chaos_events/registry")

OSC_Help = OSC_Help or {}

local function Flag(key)
    return OSC_Config.Get(key) == true and 1 or 0
end

-- Доля каждой редкости в пуле слота с учётом весов, в процентах (до десятых)
local function RarityShares(slot)
    local totals, sum = {}, 0
    for _, entry in ipairs(OSC_AbilitySelection.GetPool(slot)) do
        local rarity = OSC_AbilitySelection.GetRarity(entry)
        local weight = OSC_AbilitySelection.GetWeight(entry)
        totals[rarity] = (totals[rarity] or 0) + weight
        sum = sum + weight
    end
    local shares = {}
    for _, rarity in ipairs(OSC_ABILITY_RARITIES) do
        shares[rarity] = sum > 0 and math.floor((totals[rarity] or 0) * 1000 / sum + 0.5) / 10 or 0
    end
    return shares
end

-- События с ненулевым весом: те, что могут выпасть в этом матче
local function ChaosEvents()
    local events = {}
    for _, def in ipairs(OSC_ChaosEvents.list) do
        if OSC_ChaosEvents:Weight(def) > 0 then
            table.insert(events, {
                title_key = def.title_key,
                desc_key = def.desc_key,
                params = OSC_ChaosEvents:DescriptionParams(def),
            })
        end
    end
    return events
end

local function CourierAbilities()
    local abilities = {}
    for _, ability in ipairs(OSC_COURIER_ABILITY_POOL or {}) do
        table.insert(abilities, {
            name = ability.name,
            name_token = ability.name_token,
            duration = ability.duration,
            interval_min = ability.interval_min,
            interval_max = ability.interval_max,
        })
    end
    return abilities
end

-- Уровни якоря по порядку: уровень N пропускает N ротаций
local function AnchorLevels()
    local levels = {}
    for _, name in ipairs(OSC_Anchor.LEVELS) do
        table.insert(levels, { name = name, cost = GetItemCost(name) })
    end
    return levels
end

local function CasinoOutcomes()
    local outcomes = {}
    for _, outcome in ipairs(OSC_Config.Get("CASINO_OUTCOMES") or {}) do
        table.insert(outcomes, {
            symbol = outcome.symbol,
            chance = outcome.chance,
            multiplier = outcome.multiplier,
        })
    end
    return outcomes
end

function OSC_Help.Build()
    return {
        rotation = {
            interval = OSC_Config.Get("ROTATION_INTERVAL"),
            warning = OSC_Config.Get("WARNING_TIME"),
            choice_count = OSC_Config.Get("ROTATION_CHOICE_ENABLED") == true
                and OSC_Config.Get("ROTATION_CHOICE_COUNT") or 0,
            tag_streak = OSC_Config.Get("ABILITY_TAG_STREAK_ENABLED") == true
                and OSC_Config.Get("MAX_SAME_TAG_STREAK") or 0,
            max_duplicate_ultimates = OSC_Config.Get("MAX_DUPLICATE_ULTIMATES_PER_TEAM"),
        },
        rarity = {
            enabled = Flag("ABILITY_RARITY_ENABLED"),
            ability = RarityShares("ability"),
            ultimate = RarityShares("ultimate"),
        },
        anchor = {
            enabled = Flag("ANCHOR_ENABLED"),
            merge_count = OSC_Config.Get("ANCHOR_MERGE_COUNT"),
            levels = AnchorLevels(),
        },
        chaos = {
            interval = OSC_Config.Get("CHAOS_ROUNDS.INTERVAL"),
            warning = OSC_Config.Get("CHAOS_ROUNDS.WARNING_TIME"),
            duration = OSC_Config.Get("CHAOS_ROUNDS.DURATION"),
            events = ChaosEvents(),
        },
        casino = {
            enabled = Flag("CASINO_ENABLED"),
            min_stake = OSC_Config.Get("CASINO_MIN_SPIN_COST"),
            lifetime = OSC_Config.Get("CASINO_MACHINE_LIFETIME"),
            item_bets = Flag("CASINO_ITEM_BETS"),
            item_value_pct = math.floor((OSC_Config.Get("CASINO_ITEM_VALUE_FACTOR") or 0) * 100 + 0.5),
            outcomes = CasinoOutcomes(),
        },
        sphere = {
            enabled = Flag("CHAOS_SPHERE_ENABLED"),
            min_level = OSC_Config.Get("CHAOS_SPHERE_MIN_LEVEL"),
            choices = OSC_Config.Get("CHAOS_SPHERE_ULTIMATE_CHOICES"),
        },
        couriers = {
            count = OSC_Config.Get("COURIERS.COUNT_PER_TEAM"),
            abilities = CourierAbilities(),
        },
        summary = {
            enabled = Flag("SUMMARY_ENABLED"),
            titles = OSC_Config.Get("SUMMARY_TITLES") or {},
            ties = OSC_Config.Get("SUMMARY_TITLE_TIES"),
        },
    }
end

function OSC_Help.Publish()
    CustomNetTables:SetTableValue("osc_state", "help", OSC_Help.Build())
end

function OSC_Help.Init()
    OSC_Help.Publish()
    OSC_GameEvents.Subscribe("config_overrides_applied", "help", function()
        OSC_Help.Publish()
    end)
end
