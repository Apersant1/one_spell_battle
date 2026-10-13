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
-- Q, первая из этих — W) и не снимаются ротацией.
OSC_HERO_EXTRA_ABILITIES = {
    npc_dota_hero_ogre_magi = { "ogre_magi_casino" },
}

-- Запись пула: name, hero (для прекэша), label, tags, weight (по умолчанию 4),
-- linked — подспособности, без которых основная работает не полностью:
-- { name = "...", hidden = true } выдаётся вместе с основной и удаляется с ней.
-- tags — непустой список из OSC_ABILITY_TAGS: что способность даёт игроку.
-- Запись с несколькими тегами участвует в серии каждого из них (см.
-- MAX_SAME_TAG_STREAK в config.lua).
-- Способности, которых нет в KV, с неверным весом или тегами, при старте
-- убирает OSC_AbilitySelection.ValidatePools.
-- Призванные существа (варды и т. п.) после смены способности остаются до смерти.

-- damage — урон; disable — контроль (оглушение, сеть, хекс, молчание,
-- притягивание); mobility — перемещение; passive — пассивная способность;
-- support — лечение, защита и усиление союзников
OSC_ABILITY_TAGS = { "damage", "disable", "mobility", "passive", "support" }

OSC_ABILITY_POOL = {
    { name = "lina_dragon_slave",            hero = "npc_dota_hero_lina",            label = "Dragon Slave", tags = { "damage" } },
    { name = "lina_light_strike_array",      hero = "npc_dota_hero_lina",            label = "Light Strike Array", tags = { "damage", "disable" } },
    { name = "lion_impale",                  hero = "npc_dota_hero_lion",            label = "Earth Spike", tags = { "damage", "disable" } },
    { name = "lion_voodoo",                  hero = "npc_dota_hero_lion",            label = "Hex (Lion)", tags = { "disable" } },
    { name = "sven_storm_bolt",              hero = "npc_dota_hero_sven",            label = "Storm Hammer", tags = { "damage", "disable" } },
    { name = "zuus_arc_lightning",           hero = "npc_dota_hero_zuus",            label = "Arc Lightning", tags = { "damage" } },
    { name = "zuus_lightning_bolt",          hero = "npc_dota_hero_zuus",            label = "Lightning Bolt", tags = { "damage" } },
    { name = "crystal_maiden_crystal_nova",  hero = "npc_dota_hero_crystal_maiden",  label = "Crystal Nova", tags = { "damage" } },
    { name = "crystal_maiden_frostbite",     hero = "npc_dota_hero_crystal_maiden",  label = "Frostbite", tags = { "disable", "damage" } },
    { name = "lich_frost_nova",              hero = "npc_dota_hero_lich",            label = "Frost Blast", tags = { "damage" } },
    { name = "earthshaker_fissure",          hero = "npc_dota_hero_earthshaker",     label = "Fissure", tags = { "disable", "damage" } },
    { name = "sandking_burrowstrike",        hero = "npc_dota_hero_sand_king",       label = "Burrowstrike", tags = { "mobility", "disable", "damage" } },
    { name = "antimage_blink",               hero = "npc_dota_hero_antimage",        label = "Blink (Anti-Mage)", tags = { "mobility" } },
    { name = "queenofpain_blink",            hero = "npc_dota_hero_queenofpain",     label = "Blink (QoP)", tags = { "mobility" } },
    { name = "mirana_arrow",                 hero = "npc_dota_hero_mirana",          label = "Sacred Arrow", tags = { "disable", "damage" } },
    { name = "pudge_meat_hook",              hero = "npc_dota_hero_pudge",           label = "Meat Hook", tags = { "disable", "damage" } },
    { name = "vengefulspirit_magic_missile", hero = "npc_dota_hero_vengefulspirit",  label = "Magic Missile", tags = { "disable", "damage" } },
    { name = "skywrath_mage_arcane_bolt",    hero = "npc_dota_hero_skywrath_mage",   label = "Arcane Bolt", tags = { "damage" } },
    { name = "ogre_magi_fireblast",          hero = "npc_dota_hero_ogre_magi",       label = "Fireblast", tags = { "disable", "damage" } },
    { name = "shadow_shaman_voodoo",         hero = "npc_dota_hero_shadow_shaman",   label = "Hex (Shaman)", tags = { "disable" } },
    { name = "axe_berserkers_call",          hero = "npc_dota_hero_axe",             label = "Berserker's Call", tags = { "disable" } },
    { name = "centaur_hoof_stomp",           hero = "npc_dota_hero_centaur",         label = "Hoof Stomp", tags = { "disable", "damage" } },
    { name = "slardar_slithereen_crush",     hero = "npc_dota_hero_slardar",         label = "Slithereen Crush", tags = { "disable", "damage" } },
    { name = "necrolyte_death_pulse",        hero = "npc_dota_hero_necrolyte",       label = "Death Pulse", tags = { "damage", "support" } },
    { name = "omniknight_purification",      hero = "npc_dota_hero_omniknight",      label = "Purification", tags = { "support", "damage" } },
    { name = "dazzle_shallow_grave",         hero = "npc_dota_hero_dazzle",          label = "Shallow Grave", tags = { "support" } },
    { name = "abaddon_death_coil",           hero = "npc_dota_hero_abaddon",         label = "Mist Coil", tags = { "support", "damage" } },
    { name = "windrunner_shackleshot",       hero = "npc_dota_hero_windrunner",      label = "Shackleshot", tags = { "disable" } },
    { name = "puck_illusory_orb",            hero = "npc_dota_hero_puck",            label = "Illusory Orb", tags = { "mobility", "damage" },
      linked = { { name = "puck_ethereal_jaunt" } } },
    { name = "puck_waning_rift",             hero = "npc_dota_hero_puck",            label = "Waning Rift", tags = { "disable", "damage" } },
    { name = "storm_spirit_static_remnant",  hero = "npc_dota_hero_storm_spirit",    label = "Static Remnant", tags = { "damage" } },
    { name = "storm_spirit_electric_vortex", hero = "npc_dota_hero_storm_spirit",   label = "Electric Vortex", tags = { "disable" } },
    { name = "jakiro_dual_breath",           hero = "npc_dota_hero_jakiro",          label = "Dual Breath", tags = { "damage" } },
    { name = "jakiro_ice_path",              hero = "npc_dota_hero_jakiro",          label = "Ice Path", tags = { "disable" } },
    { name = "witch_doctor_paralyzing_cask", hero = "npc_dota_hero_witch_doctor",   label = "Paralyzing Cask", tags = { "disable", "damage" } },
    { name = "witch_doctor_maledict",        hero = "npc_dota_hero_witch_doctor",   label = "Maledict", tags = { "damage" } },
    { name = "disruptor_thunder_strike",     hero = "npc_dota_hero_disruptor",       label = "Thunder Strike", tags = { "damage" } },
    { name = "disruptor_glimpse",            hero = "npc_dota_hero_disruptor",       label = "Glimpse", tags = { "disable" } },
    { name = "disruptor_kinetic_field",      hero = "npc_dota_hero_disruptor",       label = "Kinetic Field", tags = { "disable" } },
    { name = "bristleback_quill_spray",      hero = "npc_dota_hero_bristleback",     label = "Quill Spray", tags = { "damage" } },
    { name = "bristleback_viscous_nasal_goo", hero = "npc_dota_hero_bristleback",    label = "Viscous Nasal Goo", tags = { "disable" } },
    { name = "venomancer_venomous_gale",     hero = "npc_dota_hero_venomancer",     label = "Venomous Gale", tags = { "damage" } },
    { name = "venomancer_plague_ward",       hero = "npc_dota_hero_venomancer",     label = "Plague Ward", tags = { "damage" } },
    { name = "juggernaut_blade_fury",        hero = "npc_dota_hero_juggernaut",     label = "Blade Fury", tags = { "damage" } },
    { name = "juggernaut_healing_ward",      hero = "npc_dota_hero_juggernaut",     label = "Healing Ward", tags = { "support" } },
    { name = "phantom_assassin_stifling_dagger", hero = "npc_dota_hero_phantom_assassin", label = "Stifling Dagger", tags = { "damage" } },
    { name = "phantom_assassin_phantom_strike", hero = "npc_dota_hero_phantom_assassin", label = "Phantom Strike", tags = { "mobility" } },
    { name = "riki_blink_strike",            hero = "npc_dota_hero_riki",            label = "Blink Strike", tags = { "mobility", "damage" } },
    { name = "bane_brain_sap",               hero = "npc_dota_hero_bane",            label = "Brain Sap", tags = { "damage" } },
    { name = "bane_nightmare",               hero = "npc_dota_hero_bane",            label = "Nightmare", tags = { "disable" },
      linked = { { name = "bane_nightmare_end", hidden = true } } },
    { name = "shadow_demon_disruption",      hero = "npc_dota_hero_shadow_demon",   label = "Disruption", tags = { "disable", "support" } },
    { name = "tinker_laser",                 hero = "npc_dota_hero_tinker",          label = "Laser", tags = { "damage" } },
    { name = "juggernaut_blade_dance",       hero = "npc_dota_hero_juggernaut",     label = "Blade Dance", tags = { "passive", "damage" }, weight = 2 },
    { name = "spirit_breaker_greater_bash",  hero = "npc_dota_hero_spirit_breaker", label = "Greater Bash", tags = { "passive", "disable" }, weight = 2 },
    { name = "axe_counter_helix",            hero = "npc_dota_hero_axe",             label = "Counter Helix", tags = { "passive", "damage" }, weight = 2 },
    { name = "tidehunter_kraken_shell",      hero = "npc_dota_hero_tidehunter",      label = "Kraken Shell", tags = { "passive" }, weight = 2 },
}

OSC_ULTIMATE_POOL = {
    { name = "lina_laguna_blade",             hero = "npc_dota_hero_lina",            label = "Laguna Blade", tags = { "damage" } },
    { name = "lion_finger_of_death",          hero = "npc_dota_hero_lion",            label = "Finger of Death", tags = { "damage" } },
    { name = "sven_gods_strength",            hero = "npc_dota_hero_sven",            label = "God's Strength", tags = { "damage" } },
    { name = "zuus_thundergods_wrath",        hero = "npc_dota_hero_zuus",            label = "Thundergod's Wrath", tags = { "damage" } },
    { name = "crystal_maiden_freezing_field", hero = "npc_dota_hero_crystal_maiden",  label = "Freezing Field", tags = { "damage" },
      linked = { { name = "crystal_maiden_freezing_field_stop", hidden = true } } },
    { name = "lich_chain_frost",              hero = "npc_dota_hero_lich",            label = "Chain Frost", tags = { "damage" } },
    { name = "earthshaker_echo_slam",         hero = "npc_dota_hero_earthshaker",    label = "Echo Slam", tags = { "damage" } },
    { name = "sandking_epicenter",            hero = "npc_dota_hero_sand_king",       label = "Epicenter", tags = { "damage" } },
    { name = "pudge_dismember",               hero = "npc_dota_hero_pudge",           label = "Dismember", tags = { "disable", "damage" } },
    { name = "tidehunter_ravage",             hero = "npc_dota_hero_tidehunter",      label = "Ravage", tags = { "disable", "damage" } },
    { name = "necrolyte_reapers_scythe",      hero = "npc_dota_hero_necrolyte",       label = "Reaper's Scythe", tags = { "damage", "disable" } },
    { name = "axe_culling_blade",             hero = "npc_dota_hero_axe",             label = "Culling Blade", tags = { "damage" } },
    { name = "antimage_mana_void",            hero = "npc_dota_hero_antimage",        label = "Mana Void", tags = { "damage" } },
    { name = "queenofpain_sonic_wave",        hero = "npc_dota_hero_queenofpain",     label = "Sonic Wave", tags = { "damage" } },
    { name = "shadow_shaman_mass_serpent_ward", hero = "npc_dota_hero_shadow_shaman", label = "Mass Serpent Ward", tags = { "damage" } },
    { name = "witch_doctor_death_ward",       hero = "npc_dota_hero_witch_doctor",   label = "Death Ward", tags = { "damage" } },
    { name = "jakiro_macropyre",              hero = "npc_dota_hero_jakiro",          label = "Macropyre", tags = { "damage" } },
    { name = "disruptor_static_storm",         hero = "npc_dota_hero_disruptor",      label = "Static Storm", tags = { "disable", "damage" } },
    { name = "venomancer_poison_nova",         hero = "npc_dota_hero_venomancer",     label = "Poison Nova", tags = { "damage" } },
    { name = "juggernaut_omni_slash",         hero = "npc_dota_hero_juggernaut",     label = "Omnislash", tags = { "damage" } },
    { name = "phantom_assassin_coup_de_grace", hero = "npc_dota_hero_phantom_assassin", label = "Coup de Grace", tags = { "passive", "damage" } },
    { name = "riki_tricks_of_the_trade",      hero = "npc_dota_hero_riki",            label = "Tricks of the Trade", tags = { "damage" } },
    { name = "bane_fiends_grip",              hero = "npc_dota_hero_bane",            label = "Fiend's Grip", tags = { "disable", "damage" } },
    { name = "spirit_breaker_nether_strike",  hero = "npc_dota_hero_spirit_breaker", label = "Nether Strike", tags = { "mobility", "disable" } },
    { name = "shadow_demon_demonic_purge",    hero = "npc_dota_hero_shadow_demon",   label = "Demonic Purge", tags = { "disable", "damage" } },
    { name = "skywrath_mage_mystic_flare",    hero = "npc_dota_hero_skywrath_mage",  label = "Mystic Flare", tags = { "damage" } },
    { name = "centaur_stampede",              hero = "npc_dota_hero_centaur",         label = "Stampede", tags = { "mobility", "support" } },
    { name = "slardar_amplify_damage",        hero = "npc_dota_hero_slardar",         label = "Corrosive Haze", tags = { "support" } },
    { name = "magnataur_reverse_polarity",    hero = "npc_dota_hero_magnataur",       label = "Reverse Polarity", tags = { "disable" } },
    { name = "elder_titan_earth_splitter",    hero = "npc_dota_hero_elder_titan",    label = "Earth Splitter", tags = { "damage" } },
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
