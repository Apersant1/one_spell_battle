require("osc/config/config")
require("osc/config/ability_pools")
require("osc/core/logger")
require("osc/core/runtime_config")
require("osc/core/notifications")
require("osc/core/heroes")
require("osc/core/game_events")
require("osc/core/client_commands")
require("osc/core/hero_state")
require("osc/core/anchor")
require("osc/core/commands")
require("osc/systems/ability_selection")
require("osc/systems/abilities")
require("osc/systems/hero_lifecycle")
require("osc/systems/team_shuffle")
require("osc/systems/vote")
require("osc/systems/rotation_choice")
require("osc/systems/rotation")
require("osc/items/item_ultimate_reroll")
require("osc/items/item_anchor")
require("osc/systems/casino")
require("osc/systems/chaos_shop")
require("osc/systems/chaos_sphere")
require("osc/items/item_chaos_sphere")
require("osc/heroes/ogre_casino")
require("osc/systems/couriers")
require("osc/systems/chaos_events/registry")
require("osc/systems/chaos_events/cooldowns")
require("osc/systems/chaos_events/mana_free")
require("osc/systems/chaos_events/gold_rush")
require("osc/systems/chaos_events/no_hud")
require("osc/systems/chaos_events/mouse_swap")
require("osc/systems/chaos_events/tunnel")
require("osc/systems/chaos_events/vegas")
require("osc/systems/chaos_events/doom")
require("osc/systems/chaos_events/weather_common")
require("osc/systems/chaos_events/weather_storm")
require("osc/systems/chaos_events/weather_torrent")
require("osc/systems/chaos_events/weather_drones")
require("osc/systems/chaos_rounds")
require("osc/systems/stats")
require("osc/systems/summary")
require("osc/core/game_mode")

function Precache(context)
    -- Прекэшим героев-владельцев способностей из whitelist,
    -- иначе у чужих способностей не будет партиклов и звуков
    local done = {}
    for _, pool in ipairs({ OSC_ABILITY_POOL, OSC_ULTIMATE_POOL }) do
        for _, entry in ipairs(pool) do
            if not done[entry.hero] then
                done[entry.hero] = true
                PrecacheUnitByNameSync(entry.hero, context)
            end
        end
    end

    PrecacheResource("model", "models/osc/slot_machine/slot_machine.vmdl", context) -- Казик
    PrecacheUnitByNameSync("npc_osc_casino_test_object", context)
    PrecacheResource("particle", "particles/generic_hero_status/hero_levelup.vpcf", context)
    
    for _, particle in ipairs({ OSC_Config.Get("CASINO_WIN_PARTICLE"), OSC_Config.Get("CASINO_JACKPOT_PARTICLE") }) do
        if particle and particle ~= "" then
            PrecacheResource("particle", particle, context)
        end
    end

    -- Погодные хаос-события: частицы и звуки героев, которых может не быть в матче
    local weather = OSC_Config.Get("CHAOS_ROUNDS.WEATHER")
    PrecacheResource("particle", weather.WARNING_RING, context)
    for _, event in ipairs({ weather.STORM, weather.TORRENT, weather.DRONES }) do
        for _, key in ipairs({ "PARTICLE", "WARN_PARTICLE" }) do
            if event[key] and event[key] ~= "" then
                PrecacheResource("particle", event[key], context)
            end
        end
    end
    for _, soundFile in ipairs(weather.SOUND_FILES) do
        PrecacheResource("soundfile", soundFile, context)
    end
end

function Activate()
    GameRules.OSC = OneSpellChaos()
    GameRules.OSC:Init()
end
