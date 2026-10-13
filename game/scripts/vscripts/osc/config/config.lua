OSC_CONFIG = {
    VERSION = "1.0.0",
    ROTATION_INTERVAL = 60,
    WARNING_TIME = 10,
    -- Сколько секунд снятая активная способность живёт скрытой, чтобы её
    -- снаряды и эффекты доиграли (Illusory Orb, Static Remnant ~12 с)
    ROTATION_OLD_ABILITY_LIFETIME = 15,
    CHAT_MESSAGES = true,
    DEVELOPMENT_MODE = false,
    MAX_DUPLICATE_ULTIMATES_PER_TEAM = 2,
    CHAOS_ROUNDS = {
        INTERVAL                = 200,
        WARNING_TIME            = 10,
        DURATION                = 30,
        COOLDOWN_REDUCTION_PCT  = 40,
        MANA_COST_REDUCTION_PCT = 100,
        GOLD_RUSH_AMOUNT        = 15,
        GOLD_RUSH_TICK          = 2,
        WEATHER = {
            STORM = {                       -- Гроза: молнии Зевса
                WEIGHT     = 5,
                TICK       = 2.5,           -- раз в N секунд
                TARGETS    = 2,             -- сколько героев бьёт за раз
                DAMAGE_PCT = 8,
                STUN       = 0.2,
                PARTICLE   = "particles/units/heroes/hero_zuus/zuus_lightning_bolt.vpcf",
                SOUND      = "Hero_Zuus.LightningBolt",
            },
            TORRENT = {                     -- Штормовое предупреждение: потоки Кунки
                WEIGHT        = 5,
                TICK          = 2,
                TARGETS       = 2,
                DELAY         = 1.6,        -- сколько секунд видна метка до удара
                RADIUS        = 225,
                DAMAGE_PCT    = 10,
                LIFT_DURATION = 1.0,        -- сколько герой висит в воздухе
                LIFT_HEIGHT   = 350,
                WARN_PARTICLE = "particles/units/heroes/hero_kunkka/kunkka_spell_torrent_bubbles.vpcf",
                WARN_SOUND    = "Ability.pre.Torrent",
                PARTICLE      = "particles/units/heroes/hero_kunkka/kunkka_spell_torrent_splash.vpcf",
                SOUND         = "Ability.Torrent",
            },
            DRONES = {                      -- Атака дронов: ракеты Клокверка
                WEIGHT     = 5,
                TICK       = 1.5,
                TARGETS    = 3,
                DELAY      = 1.2,
                RADIUS     = 200,
                SPREAD     = 350,           -- ракета падает в случайную точку рядом с героем
                DAMAGE_PCT = 6,
                PARTICLE   = "particles/units/heroes/hero_rattletrap/rattletrap_rocket_flare_explosion.vpcf",
                SOUND      = "Hero_Rattletrap.Rocket_Flare.Explode",
            },
            -- Звуки героев, которых может не быть в матче
            SOUND_FILES = {
                "soundevents/game_sounds_heroes/game_sounds_zuus.vsndevts",
                "soundevents/game_sounds_heroes/game_sounds_kunkka.vsndevts",
                "soundevents/game_sounds_heroes/game_sounds_rattletrap.vsndevts",
            },
            WARNING_RING = "particles/ui_mouseactions/range_display.vpcf",
        },
    
    },
    COURIERS = {
        COUNT_PER_TEAM = 2,
        THINK_INTERVAL = 0.5,
        MOVE_ORDER_INTERVAL = 1,
        HERO_DELIVERY_DISTANCE = 250,
        FOUNTAIN_ARRIVAL_DISTANCE = 350,
        HOME_FORWARD_OFFSET = 250,
        HOME_SIDE_OFFSET = 160,
        HOME_ROW_SPACING = 200,      -- третий и следующие курьеры встают рядами дальше
        STASH_FIRST_SLOT = 9,
        STASH_LAST_SLOT = 14,
        INVENTORY_FIRST_SLOT = 0,
        INVENTORY_LAST_SLOT = 5,
        INITIAL_ABILITY_INTERVAL_MIN = 60,
        INITIAL_ABILITY_INTERVAL_MAX = 180,
    },
    CASINO_ACCESS = "all",  -- all/team/owner
    CASINO_USE_DISTANCE = 450,       -- как близко нужно стоять к автомату
    CASINO_HULL_RADIUS = 80,
    CASINO_WIN_PARTICLE = "particles/generic_gameplay/lasthit_coins.vpcf",
    CASINO_WIN_SOUND = "General.Coins",
    CASINO_JACKPOT_PARTICLE = "particles/items2_fx/hand_of_midas.vpcf",
    CASINO_JACKPOT_SOUND = "DOTA_Item.Hand_Of_Midas",
    CASINO_DEFAULT_STAKE = 250,
    CASINO_MIN_SPIN_COST = 50,
    CASINO_MACHINE_LIFETIME = 90,
    CASINO_ITEM_BETS = true,
    CASINO_ITEM_VALUE_FACTOR = 0.5,
    CASINO_OUTCOMES = {
        { chance = 10, symbol = "circle", multiplier = 1 },
        { chance = 15, symbol = "diamond", multiplier = 2 },
        { chance = 4, symbol = "star", multiplier = 5 },
        { chance = 1, symbol = "seven", multiplier = 30 },
    },
}
