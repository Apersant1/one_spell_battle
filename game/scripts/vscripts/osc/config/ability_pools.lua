OSC_KEEP_ABILITIES = {
    ability_capture               = true,
    ability_lamp_use               = true,
    ability_pluck_famango          = true,
    twin_gate_portal_warp          = true,
    abyssal_underlord_portal_warp = true,
    ogre_magi_unrefined_fireblast = true,
}

-- Собственные способности героев в этом режиме. Выдаются при инициализации
-- сразу после основной способности (порядок выдачи задаёт слоты: основная —
-- Q, первая из этих — W) и не снимаются ротацией. Запись — имя способности
-- или { name = "...", enabled_by = "<путь флага в OSC_CONFIG>" }: способность
-- выдаётся, только если флаг (с учётом переопределений) включён.
OSC_HERO_EXTRA_ABILITIES = {
    npc_dota_hero_ogre_magi = { { name = "ogre_magi_casino", enabled_by = "CASINO_ENABLED" } },
}

-- Запись пула: name, hero (для прекэша), label, tags, weight (по умолчанию 4),
-- linked — подспособности, без которых основная работает не полностью:
-- { name = "...", hidden = true } выдаётся вместе с основной и удаляется с ней.
-- tags — непустой список из OSC_ABILITY_TAGS: что способность даёт игроку.
-- Запись с несколькими тегами участвует в серии каждого из них (см.
-- MAX_SAME_TAG_STREAK в config.lua).
-- rarity — "rare" или "legendary" (из OSC_ABILITY_RARITIES); без поля —
-- обычная. Редкость меняет только шанс выпадения (множитель веса
-- ABILITY_RARITY_WEIGHT в config.lua) и оформление в HUD, но не силу.
-- Способности, которых нет в KV, с неверным весом, тегами или редкостью, при старте
-- убирает OSC_AbilitySelection.ValidatePools.
-- Призванные существа (варды и т. п.) после смены способности остаются до смерти.

-- damage — урон; disable — контроль (оглушение, сеть, хекс, молчание,
-- притягивание); mobility — перемещение; passive — пассивная способность;
-- support — лечение, защита и усиление союзников
OSC_ABILITY_TAGS = { "damage", "disable", "mobility", "passive", "support" }

-- Редкости записей пула: common — обычная (поле rarity можно не писать)
OSC_ABILITY_RARITIES = { "common", "rare", "legendary" }

OSC_ABILITY_POOL = {
    { name = "lina_dragon_slave",            hero = "npc_dota_hero_lina",            label = "Dragon Slave", tags = { "damage" } },
    { name = "lina_light_strike_array",      hero = "npc_dota_hero_lina",            label = "Light Strike Array", tags = { "damage", "disable" }, rarity = "rare" },
    { name = "lion_impale",                  hero = "npc_dota_hero_lion",            label = "Earth Spike", tags = { "damage", "disable" }, rarity = "rare" },
    { name = "lion_voodoo",                  hero = "npc_dota_hero_lion",            label = "Hex (Lion)", tags = { "disable" }, rarity = "legendary" },
    { name = "sven_storm_bolt",              hero = "npc_dota_hero_sven",            label = "Storm Hammer", tags = { "damage", "disable" }, rarity = "rare" },
    { name = "zuus_arc_lightning",           hero = "npc_dota_hero_zuus",            label = "Arc Lightning", tags = { "damage" } },
    { name = "zuus_lightning_bolt",          hero = "npc_dota_hero_zuus",            label = "Lightning Bolt", tags = { "damage" } },
    { name = "crystal_maiden_crystal_nova",  hero = "npc_dota_hero_crystal_maiden",  label = "Crystal Nova", tags = { "damage" } },
    { name = "crystal_maiden_frostbite",     hero = "npc_dota_hero_crystal_maiden",  label = "Frostbite", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "lich_frost_nova",              hero = "npc_dota_hero_lich",            label = "Frost Blast", tags = { "damage" } },
    { name = "earthshaker_fissure",          hero = "npc_dota_hero_earthshaker",     label = "Fissure", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "sandking_burrowstrike",        hero = "npc_dota_hero_sand_king",       label = "Burrowstrike", tags = { "mobility", "disable", "damage" }, rarity = "legendary" },
    { name = "antimage_blink",               hero = "npc_dota_hero_antimage",        label = "Blink (Anti-Mage)", tags = { "mobility" }, rarity = "legendary" },
    { name = "queenofpain_blink",            hero = "npc_dota_hero_queenofpain",     label = "Blink (QoP)", tags = { "mobility" }, rarity = "rare" },
    { name = "mirana_arrow",                 hero = "npc_dota_hero_mirana",          label = "Sacred Arrow", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "pudge_meat_hook",              hero = "npc_dota_hero_pudge",           label = "Meat Hook", tags = { "disable", "damage" }, rarity = "legendary" },
    { name = "vengefulspirit_magic_missile", hero = "npc_dota_hero_vengefulspirit",  label = "Magic Missile", tags = { "disable", "damage" } },
    { name = "skywrath_mage_arcane_bolt",    hero = "npc_dota_hero_skywrath_mage",   label = "Arcane Bolt", tags = { "damage" } },
    { name = "ogre_magi_fireblast",          hero = "npc_dota_hero_ogre_magi",       label = "Fireblast", tags = { "disable", "damage" } },
    { name = "shadow_shaman_voodoo",         hero = "npc_dota_hero_shadow_shaman",   label = "Hex (Shaman)", tags = { "disable" }, rarity = "rare" },
    { name = "axe_berserkers_call",          hero = "npc_dota_hero_axe",             label = "Berserker's Call", tags = { "disable" }, rarity = "rare" },
    { name = "centaur_hoof_stomp",           hero = "npc_dota_hero_centaur",         label = "Hoof Stomp", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "slardar_slithereen_crush",     hero = "npc_dota_hero_slardar",         label = "Slithereen Crush", tags = { "disable", "damage" } },
    { name = "necrolyte_death_pulse",        hero = "npc_dota_hero_necrolyte",       label = "Death Pulse", tags = { "damage", "support" } },
    { name = "omniknight_purification",      hero = "npc_dota_hero_omniknight",      label = "Purification", tags = { "support", "damage" } },
    { name = "dazzle_shallow_grave",         hero = "npc_dota_hero_dazzle",          label = "Shallow Grave", tags = { "support" }, rarity = "legendary" },
    { name = "abaddon_death_coil",           hero = "npc_dota_hero_abaddon",         label = "Mist Coil", tags = { "support", "damage" } },
    { name = "windrunner_shackleshot",       hero = "npc_dota_hero_windrunner",      label = "Shackleshot", tags = { "disable" }, rarity = "rare" },
    { name = "puck_illusory_orb",            hero = "npc_dota_hero_puck",            label = "Illusory Orb", tags = { "mobility", "damage" }, rarity = "legendary",
      linked = { { name = "puck_ethereal_jaunt" } } },
    { name = "puck_waning_rift",             hero = "npc_dota_hero_puck",            label = "Waning Rift", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "storm_spirit_static_remnant",  hero = "npc_dota_hero_storm_spirit",    label = "Static Remnant", tags = { "damage" } },
    { name = "storm_spirit_electric_vortex", hero = "npc_dota_hero_storm_spirit",   label = "Electric Vortex", tags = { "disable" } },
    { name = "jakiro_dual_breath",           hero = "npc_dota_hero_jakiro",          label = "Dual Breath", tags = { "damage" } },
    { name = "jakiro_ice_path",              hero = "npc_dota_hero_jakiro",          label = "Ice Path", tags = { "disable" }, rarity = "rare" },
    { name = "witch_doctor_paralyzing_cask", hero = "npc_dota_hero_witch_doctor",   label = "Paralyzing Cask", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "witch_doctor_maledict",        hero = "npc_dota_hero_witch_doctor",   label = "Maledict", tags = { "damage" } },
    { name = "disruptor_thunder_strike",     hero = "npc_dota_hero_disruptor",       label = "Thunder Strike", tags = { "damage" } },
    { name = "disruptor_glimpse",            hero = "npc_dota_hero_disruptor",       label = "Glimpse", tags = { "disable" } },
    { name = "disruptor_kinetic_field",      hero = "npc_dota_hero_disruptor",       label = "Kinetic Field", tags = { "disable" }, rarity = "legendary" },
    { name = "bristleback_quill_spray",      hero = "npc_dota_hero_bristleback",     label = "Quill Spray", tags = { "damage" } },
    { name = "bristleback_viscous_nasal_goo", hero = "npc_dota_hero_bristleback",    label = "Viscous Nasal Goo", tags = { "disable" } },
    { name = "venomancer_venomous_gale",     hero = "npc_dota_hero_venomancer",     label = "Venomous Gale", tags = { "damage" } },
    { name = "venomancer_plague_ward",       hero = "npc_dota_hero_venomancer",     label = "Plague Ward", tags = { "damage" } },
    { name = "juggernaut_blade_fury",        hero = "npc_dota_hero_juggernaut",     label = "Blade Fury", tags = { "damage" } },
    { name = "juggernaut_healing_ward",      hero = "npc_dota_hero_juggernaut",     label = "Healing Ward", tags = { "support" } },
    { name = "phantom_assassin_stifling_dagger", hero = "npc_dota_hero_phantom_assassin", label = "Stifling Dagger", tags = { "damage" } },
    { name = "phantom_assassin_phantom_strike", hero = "npc_dota_hero_phantom_assassin", label = "Phantom Strike", tags = { "mobility" }, rarity = "rare" },
    { name = "riki_blink_strike",            hero = "npc_dota_hero_riki",            label = "Blink Strike", tags = { "mobility", "damage" } },
    { name = "bane_brain_sap",               hero = "npc_dota_hero_bane",            label = "Brain Sap", tags = { "damage" } },
    { name = "bane_nightmare",               hero = "npc_dota_hero_bane",            label = "Nightmare", tags = { "disable" }, rarity = "rare",
      linked = { { name = "bane_nightmare_end", hidden = true } } },
    { name = "shadow_demon_disruption",      hero = "npc_dota_hero_shadow_demon",   label = "Disruption", tags = { "disable", "support" }, rarity = "rare" },
    { name = "tinker_laser",                 hero = "npc_dota_hero_tinker",          label = "Laser", tags = { "damage" } },
    { name = "juggernaut_blade_dance",       hero = "npc_dota_hero_juggernaut",     label = "Blade Dance", tags = { "passive", "damage" }, weight = 2 },
    { name = "spirit_breaker_greater_bash",  hero = "npc_dota_hero_spirit_breaker", label = "Greater Bash", tags = { "passive", "disable" }, rarity = "rare", weight = 2 },
    { name = "axe_counter_helix",            hero = "npc_dota_hero_axe",             label = "Counter Helix", tags = { "passive", "damage" }, weight = 2 },
    { name = "tidehunter_kraken_shell",      hero = "npc_dota_hero_tidehunter",      label = "Kraken Shell", tags = { "passive" }, weight = 2 },
    -- Расширение пула (1.3)
    { name = "tidehunter_gush",              hero = "npc_dota_hero_tidehunter",      label = "Gush", tags = { "damage" } },
    { name = "ogre_magi_ignite",             hero = "npc_dota_hero_ogre_magi",       label = "Ignite", tags = { "damage" } },
    { name = "magnataur_shockwave",          hero = "npc_dota_hero_magnataur",       label = "Shockwave", tags = { "damage" } },
    { name = "magnataur_skewer",             hero = "npc_dota_hero_magnataur",       label = "Skewer", tags = { "mobility", "disable" }, rarity = "rare" },
    { name = "mirana_leap",                  hero = "npc_dota_hero_mirana",          label = "Leap", tags = { "mobility" } },
    { name = "centaur_double_edge",          hero = "npc_dota_hero_centaur",         label = "Double Edge", tags = { "damage" } },
    { name = "shadow_shaman_ether_shock",    hero = "npc_dota_hero_shadow_shaman",   label = "Ether Shock", tags = { "damage" } },
    { name = "queenofpain_shadow_strike",    hero = "npc_dota_hero_queenofpain",     label = "Shadow Strike", tags = { "damage" } },
    { name = "earthshaker_enchant_totem",    hero = "npc_dota_hero_earthshaker",     label = "Enchant Totem", tags = { "damage" } },
    { name = "tusk_ice_shards",              hero = "npc_dota_hero_tusk",            label = "Ice Shards", tags = { "disable", "damage" } },
    { name = "nyx_assassin_impale",          hero = "npc_dota_hero_nyx_assassin",    label = "Impale (Nyx)", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "dragon_knight_dragon_tail",    hero = "npc_dota_hero_dragon_knight",   label = "Dragon Tail", tags = { "disable" } },
    { name = "dragon_knight_breathe_fire",   hero = "npc_dota_hero_dragon_knight",   label = "Breathe Fire", tags = { "damage" } },
    { name = "chaos_knight_chaos_bolt",      hero = "npc_dota_hero_chaos_knight",    label = "Chaos Bolt", tags = { "disable", "damage" } },
    { name = "skeleton_king_hellfire_blast", hero = "npc_dota_hero_skeleton_king",   label = "Wraithfire Blast", tags = { "disable", "damage" } },
    { name = "night_stalker_void",           hero = "npc_dota_hero_night_stalker",   label = "Void", tags = { "damage", "disable" } },
    { name = "tiny_avalanche",               hero = "npc_dota_hero_tiny",            label = "Avalanche", tags = { "damage", "disable" } },
    { name = "leshrac_split_earth",          hero = "npc_dota_hero_leshrac",         label = "Split Earth", tags = { "damage", "disable" } },
    { name = "kunkka_torrent",               hero = "npc_dota_hero_kunkka",          label = "Torrent", tags = { "damage", "disable" } },
    { name = "dark_seer_vacuum",             hero = "npc_dota_hero_dark_seer",       label = "Vacuum", tags = { "disable" }, rarity = "rare" },
    { name = "batrider_sticky_napalm",       hero = "npc_dota_hero_batrider",        label = "Sticky Napalm", tags = { "damage" } },
    { name = "faceless_void_time_walk",      hero = "npc_dota_hero_faceless_void",   label = "Time Walk", tags = { "mobility" }, rarity = "rare" },
    { name = "slark_pounce",                 hero = "npc_dota_hero_slark",           label = "Pounce", tags = { "mobility", "disable" } },
    { name = "ember_spirit_searing_chains",  hero = "npc_dota_hero_ember_spirit",    label = "Searing Chains", tags = { "disable", "damage" } },
    { name = "bounty_hunter_shuriken_toss",  hero = "npc_dota_hero_bounty_hunter",   label = "Shuriken Toss", tags = { "damage", "disable" } },
    { name = "sniper_shrapnel",              hero = "npc_dota_hero_sniper",          label = "Shrapnel", tags = { "damage" } },
    { name = "oracle_fortunes_end",          hero = "npc_dota_hero_oracle",          label = "Fortune's End", tags = { "disable", "damage" } },
    { name = "oracle_purifying_flames",      hero = "npc_dota_hero_oracle",          label = "Purifying Flames", tags = { "support", "damage" } },
    { name = "warlock_shadow_word",          hero = "npc_dota_hero_warlock",         label = "Shadow Word", tags = { "damage", "support" } },
    { name = "bloodseeker_blood_bath",       hero = "npc_dota_hero_bloodseeker",     label = "Blood Rite", tags = { "damage", "disable" } },
    { name = "snapfire_scatterblast",        hero = "npc_dota_hero_snapfire",        label = "Scatterblast", tags = { "damage" } },
    { name = "snapfire_firesnap_cookie",     hero = "npc_dota_hero_snapfire",        label = "Firesnap Cookie", tags = { "mobility", "support" }, rarity = "rare" },
    { name = "mars_spear",                   hero = "npc_dota_hero_mars",            label = "Spear of Mars", tags = { "damage", "disable" }, rarity = "rare" },
    { name = "monkey_king_boundless_strike", hero = "npc_dota_hero_monkey_king",     label = "Boundless Strike", tags = { "damage", "disable" } },
    { name = "legion_commander_overwhelming_odds", hero = "npc_dota_hero_legion_commander", label = "Overwhelming Odds", tags = { "damage" } },
    { name = "death_prophet_silence",        hero = "npc_dota_hero_death_prophet",   label = "Silence (DP)", tags = { "disable" } },
    { name = "obsidian_destroyer_astral_imprisonment", hero = "npc_dota_hero_obsidian_destroyer", label = "Astral Imprisonment", tags = { "disable", "support" }, rarity = "rare" },
    { name = "naga_siren_ensnare",           hero = "npc_dota_hero_naga_siren",      label = "Ensnare", tags = { "disable" } },
    { name = "muerta_dead_shot",             hero = "npc_dota_hero_muerta",          label = "Dead Shot", tags = { "damage", "disable" } },
}

OSC_ULTIMATE_POOL = {
    { name = "lina_laguna_blade",             hero = "npc_dota_hero_lina",            label = "Laguna Blade", tags = { "damage" } },
    { name = "lion_finger_of_death",          hero = "npc_dota_hero_lion",            label = "Finger of Death", tags = { "damage" }, rarity = "rare" },
    { name = "sven_gods_strength",            hero = "npc_dota_hero_sven",            label = "God's Strength", tags = { "damage" }, rarity = "rare" },
    { name = "zuus_thundergods_wrath",        hero = "npc_dota_hero_zuus",            label = "Thundergod's Wrath", tags = { "damage" }, rarity = "legendary" },
    { name = "crystal_maiden_freezing_field", hero = "npc_dota_hero_crystal_maiden",  label = "Freezing Field", tags = { "damage" }, rarity = "rare",
      linked = { { name = "crystal_maiden_freezing_field_stop", hidden = true } } },
    { name = "lich_chain_frost",              hero = "npc_dota_hero_lich",            label = "Chain Frost", tags = { "damage" }, rarity = "rare" },
    { name = "earthshaker_echo_slam",         hero = "npc_dota_hero_earthshaker",    label = "Echo Slam", tags = { "damage" }, rarity = "legendary" },
    { name = "sandking_epicenter",            hero = "npc_dota_hero_sand_king",       label = "Epicenter", tags = { "damage" }, rarity = "rare" },
    { name = "pudge_dismember",               hero = "npc_dota_hero_pudge",           label = "Dismember", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "tidehunter_ravage",             hero = "npc_dota_hero_tidehunter",      label = "Ravage", tags = { "disable", "damage" }, rarity = "legendary" },
    { name = "necrolyte_reapers_scythe",      hero = "npc_dota_hero_necrolyte",       label = "Reaper's Scythe", tags = { "damage", "disable" }, rarity = "legendary" },
    { name = "axe_culling_blade",             hero = "npc_dota_hero_axe",             label = "Culling Blade", tags = { "damage" }, rarity = "rare" },
    { name = "antimage_mana_void",            hero = "npc_dota_hero_antimage",        label = "Mana Void", tags = { "damage" } },
    { name = "queenofpain_sonic_wave",        hero = "npc_dota_hero_queenofpain",     label = "Sonic Wave", tags = { "damage" } },
    { name = "shadow_shaman_mass_serpent_ward", hero = "npc_dota_hero_shadow_shaman", label = "Mass Serpent Ward", tags = { "damage" } },
    { name = "witch_doctor_death_ward",       hero = "npc_dota_hero_witch_doctor",   label = "Death Ward", tags = { "damage" }, rarity = "rare" },
    { name = "jakiro_macropyre",              hero = "npc_dota_hero_jakiro",          label = "Macropyre", tags = { "damage" } },
    { name = "disruptor_static_storm",         hero = "npc_dota_hero_disruptor",      label = "Static Storm", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "venomancer_poison_nova",         hero = "npc_dota_hero_venomancer",     label = "Poison Nova", tags = { "damage" } },
    { name = "juggernaut_omni_slash",         hero = "npc_dota_hero_juggernaut",     label = "Omnislash", tags = { "damage" }, rarity = "legendary" },
    { name = "phantom_assassin_coup_de_grace", hero = "npc_dota_hero_phantom_assassin", label = "Coup de Grace", tags = { "passive", "damage" }, rarity = "rare" },
    { name = "riki_tricks_of_the_trade",      hero = "npc_dota_hero_riki",            label = "Tricks of the Trade", tags = { "damage" } },
    { name = "bane_fiends_grip",              hero = "npc_dota_hero_bane",            label = "Fiend's Grip", tags = { "disable", "damage" }, rarity = "legendary" },
    { name = "spirit_breaker_nether_strike",  hero = "npc_dota_hero_spirit_breaker", label = "Nether Strike", tags = { "mobility", "disable" } },
    { name = "shadow_demon_demonic_purge",    hero = "npc_dota_hero_shadow_demon",   label = "Demonic Purge", tags = { "disable", "damage" } },
    { name = "skywrath_mage_mystic_flare",    hero = "npc_dota_hero_skywrath_mage",  label = "Mystic Flare", tags = { "damage" } },
    { name = "centaur_stampede",              hero = "npc_dota_hero_centaur",         label = "Stampede", tags = { "mobility", "support" } },
    { name = "slardar_amplify_damage",        hero = "npc_dota_hero_slardar",         label = "Corrosive Haze", tags = { "support" } },
    { name = "magnataur_reverse_polarity",    hero = "npc_dota_hero_magnataur",       label = "Reverse Polarity", tags = { "disable" }, rarity = "legendary" },
    { name = "elder_titan_earth_splitter",    hero = "npc_dota_hero_elder_titan",    label = "Earth Splitter", tags = { "damage" } },
    -- Расширение пула (1.3)
    { name = "abaddon_borrowed_time",         hero = "npc_dota_hero_abaddon",         label = "Borrowed Time", tags = { "support" }, rarity = "rare" },
    { name = "enigma_black_hole",             hero = "npc_dota_hero_enigma",          label = "Black Hole", tags = { "disable", "damage" }, rarity = "legendary" },
    { name = "faceless_void_chronosphere",    hero = "npc_dota_hero_faceless_void",   label = "Chronosphere", tags = { "disable" }, rarity = "legendary" },
    { name = "doom_bringer_doom",             hero = "npc_dota_hero_doom_bringer",    label = "Doom", tags = { "disable", "damage" }, rarity = "legendary" },
    { name = "winter_wyvern_winters_curse",   hero = "npc_dota_hero_winter_wyvern",   label = "Winter's Curse", tags = { "disable" }, rarity = "legendary" },
    { name = "sniper_assassinate",            hero = "npc_dota_hero_sniper",          label = "Assassinate", tags = { "damage" } },
    { name = "kunkka_ghostship",              hero = "npc_dota_hero_kunkka",          label = "Ghostship", tags = { "damage", "disable" }, rarity = "rare" },
    { name = "legion_commander_duel",         hero = "npc_dota_hero_legion_commander", label = "Duel", tags = { "disable" }, rarity = "rare" },
    { name = "bloodseeker_rupture",           hero = "npc_dota_hero_bloodseeker",     label = "Rupture", tags = { "damage" } },
    { name = "beastmaster_primal_roar",       hero = "npc_dota_hero_beastmaster",     label = "Primal Roar", tags = { "disable", "damage" }, rarity = "rare" },
    { name = "batrider_flaming_lasso",        hero = "npc_dota_hero_batrider",        label = "Flaming Lasso", tags = { "disable" }, rarity = "rare" },
    { name = "obsidian_destroyer_sanity_eclipse", hero = "npc_dota_hero_obsidian_destroyer", label = "Sanity's Eclipse", tags = { "damage" } },
    { name = "silencer_global_silence",       hero = "npc_dota_hero_silencer",        label = "Global Silence", tags = { "disable" }, rarity = "rare" },
    { name = "nyx_assassin_vendetta",         hero = "npc_dota_hero_nyx_assassin",    label = "Vendetta", tags = { "mobility", "damage" } },
    { name = "treant_overgrowth",             hero = "npc_dota_hero_treant",          label = "Overgrowth", tags = { "disable" }, rarity = "rare" },
    { name = "mars_arena_of_blood",           hero = "npc_dota_hero_mars",            label = "Arena of Blood", tags = { "disable" }, rarity = "rare" },
    { name = "snapfire_mortimer_kisses",      hero = "npc_dota_hero_snapfire",        label = "Mortimer Kisses", tags = { "damage" } },
    { name = "void_spirit_astral_step",       hero = "npc_dota_hero_void_spirit",     label = "Astral Step", tags = { "mobility", "damage" } },
    { name = "death_prophet_exorcism",        hero = "npc_dota_hero_death_prophet",   label = "Exorcism", tags = { "damage" } },
    { name = "medusa_stone_gaze",             hero = "npc_dota_hero_medusa",          label = "Stone Gaze", tags = { "disable" }, rarity = "rare" },
}

OSC_COURIER_ABILITY_POOL = {
    {
        name = "drunk",
        name_token = "DOTA_Tooltip_modifier_osc_courier_drunk",
        modifier = "modifier_osc_courier_drunk",
        duration = 15,
        slow_pct = 30,
        interval_min = 60,
        interval_max = 180,
    },
    {
        name = "lost",
        name_token = "DOTA_Tooltip_modifier_osc_courier_lost",
        modifier = "modifier_osc_courier_lost",
        duration = 30,
        interval_min = 60,
        interval_max = 180,
    },
}
