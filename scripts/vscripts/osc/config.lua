OSC_CONFIG = {
    ROTATION_INTERVAL = 60,  -- секунд между сменами
    WARNING_TIME      = 10,  -- предупреждение за N секунд
    CHAT_MESSAGES     = false,
}

-- Служебные способности, которые нельзя удалять
OSC_KEEP_ABILITIES = {
    ability_capture               = true,
    ability_lamp_use              = true,
    ability_pluck_famango         = true,
    twin_gate_portal_warp         = true,
    abyssal_underlord_portal_warp = true,
}

-- name: имя способности, hero: герой для прекэша, label: название в чате
OSC_ABILITY_POOL = {
    { name = "lina_dragon_slave",            hero = "npc_dota_hero_lina",            label = "Dragon Slave" },
    { name = "lina_light_strike_array",      hero = "npc_dota_hero_lina",            label = "Light Strike Array" },
    { name = "lion_impale",                  hero = "npc_dota_hero_lion",            label = "Earth Spike" },
    { name = "lion_voodoo",                  hero = "npc_dota_hero_lion",            label = "Hex (Lion)" },
    { name = "lion_finger_of_death",         hero = "npc_dota_hero_lion",            label = "Finger of Death" },
    { name = "sven_storm_bolt",              hero = "npc_dota_hero_sven",            label = "Storm Hammer" },
    { name = "zuus_arc_lightning",           hero = "npc_dota_hero_zuus",            label = "Arc Lightning" },
    { name = "zuus_lightning_bolt",          hero = "npc_dota_hero_zuus",            label = "Lightning Bolt" },
    { name = "crystal_maiden_crystal_nova",  hero = "npc_dota_hero_crystal_maiden",  label = "Crystal Nova" },
    { name = "crystal_maiden_frostbite",     hero = "npc_dota_hero_crystal_maiden",  label = "Frostbite" },
    { name = "lich_frost_nova",              hero = "npc_dota_hero_lich",            label = "Frost Blast" },
    { name = "earthshaker_fissure",          hero = "npc_dota_hero_earthshaker",     label = "Fissure" },
    { name = "sandking_burrowstrike",        hero = "npc_dota_hero_sand_king",       label = "Burrowstrike" },
    { name = "antimage_blink",               hero = "npc_dota_hero_antimage",        label = "Blink (Anti-Mage)" },
    { name = "queenofpain_blink",            hero = "npc_dota_hero_queenofpain",     label = "Blink (QoP)" },
    { name = "mirana_arrow",                 hero = "npc_dota_hero_mirana",          label = "Sacred Arrow" },
    { name = "pudge_meat_hook",              hero = "npc_dota_hero_pudge",           label = "Meat Hook" },
    { name = "vengefulspirit_magic_missile", hero = "npc_dota_hero_vengefulspirit",  label = "Magic Missile" },
    { name = "skywrath_mage_arcane_bolt",    hero = "npc_dota_hero_skywrath_mage",   label = "Arcane Bolt" },
    { name = "ogre_magi_fireblast",          hero = "npc_dota_hero_ogre_magi",       label = "Fireblast" },
    { name = "shadow_shaman_voodoo",         hero = "npc_dota_hero_shadow_shaman",   label = "Hex (Shaman)" },
    { name = "axe_berserkers_call",          hero = "npc_dota_hero_axe",             label = "Berserker's Call" },
    { name = "centaur_hoof_stomp",           hero = "npc_dota_hero_centaur",         label = "Hoof Stomp" },
    { name = "slardar_slithereen_crush",     hero = "npc_dota_hero_slardar",         label = "Slithereen Crush" },
    { name = "tidehunter_ravage",            hero = "npc_dota_hero_tidehunter",      label = "Ravage" },
    { name = "necrolyte_death_pulse",        hero = "npc_dota_hero_necrolyte",       label = "Death Pulse" },
    { name = "omniknight_purification",      hero = "npc_dota_hero_omniknight",      label = "Purification" },
    { name = "dazzle_shallow_grave",         hero = "npc_dota_hero_dazzle",          label = "Shallow Grave" },
    { name = "abaddon_death_coil",           hero = "npc_dota_hero_abaddon",         label = "Mist Coil" },
    { name = "windrunner_shackleshot",       hero = "npc_dota_hero_windrunner",      label = "Shackleshot" },
}