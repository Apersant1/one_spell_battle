OSC_CONFIG = {
    VERSION = "1.3.0",
    ROTATION_INTERVAL = 60,
    WARNING_TIME = 10,
    -- Сколько секунд снятая активная способность живёт скрытой, чтобы её
    -- снаряды и эффекты доиграли (Illusory Orb, Static Remnant ~12 с)
    ROTATION_OLD_ABILITY_LIFETIME = 15,
    -- Если старая способность в фазе каста (замах до применения), замена
    -- откладывается шагами ROTATION_DEFER_STEP, но не дольше
    -- ROTATION_MAX_DEFER секунд, потом выполняется принудительно
    ROTATION_CAST_PHASE_DEFER = true,
    ROTATION_DEFER_STEP = 0.25,
    ROTATION_MAX_DEFER = 3,
    -- Перезарядка способности, пришедшей на смену прежней (ротация, -reroll,
    -- смена ультимейта): "ready" — готова сразу; "partial" — на перезарядке
    -- NEW_ABILITY_COOLDOWN_FRACTION от полной на текущем уровне. Первая
    -- способность героя и первый ультимейт всегда готовы.
    NEW_ABILITY_COOLDOWN_MODE = "ready",
    NEW_ABILITY_COOLDOWN_FRACTION = 0.5,
    -- Не выдавать герою больше MAX_SAME_TAG_STREAK способностей подряд с
    -- одним тегом (отдельно для основной способности и ультимейта). Если
    -- подходящих способностей не остаётся, правило не применяется.
    ABILITY_TAG_STREAK_ENABLED = true,
    MAX_SAME_TAG_STREAK = 2,
    -- Выбор из трёх: на предупреждении о ротации игрок получает
    -- ROTATION_CHOICE_COUNT кандидатов; не выбрал — случайный из них
    ROTATION_CHOICE_ENABLED = true,
    ROTATION_CHOICE_COUNT = 3,
    -- Редкость способностей (поле rarity в ability_pools.lua): итоговый вес
    -- записи = weight × ABILITY_RARITY_WEIGHT[редкость]. Выключено — все обычные.
    ABILITY_RARITY_ENABLED = true,
    ABILITY_RARITY_WEIGHT = { common = 4, rare = 2, legendary = 1 },
    -- Отказы на команды клиента (выбор из трёх, голосование) пишутся в лог
    -- не чаще раза в столько секунд на игрока и канал
    CLIENT_REFUSAL_LOG_INTERVAL = 5,
    -- Предмет «Якорь» (item_osc_anchor): пропустить ближайшую ротацию
    ANCHOR_ENABLED = true,
    -- Хаос-лавка (osc/systems/chaos_shop.lua): предметы режима продаются в
    -- своей панели HUD, а не в стандартном магазине. Цена — ItemCost в
    -- npc_items_custom.txt; team_stock — сколько штук команда может купить
    -- за матч, без него — без лимита. «Якорь» выключается и ANCHOR_ENABLED.
    CHAOS_SHOP_ENABLED = true,
    CHAOS_SHOP_ITEMS = {
        { name = "item_osc_ultimate_reroll", team_stock = 5 }, -- 5 на команду за матч
        { name = "item_osc_anchor" },                          -- без лимита
    },
    -- Сфера хаоса (osc/systems/chaos_sphere.lua): падает с Рошана, владелец
    -- выбирает легендарный ультимейт (из CHAOS_SPHERE_ULTIMATE_CHOICES) или
    -- новую случайную способность всем врагам
    CHAOS_SPHERE_ENABLED = true,
    CHAOS_SPHERE_ULTIMATE_CHOICES = 3,
    CHAOS_SPHERE_MIN_LEVEL = 6,       -- для варианта «ультимейт»
    CHAOS_SPHERE_DROP_OFFSET = 150,   -- на сколько от Рошана падает сфера
    -- Статистика матча по игрокам (osc/systems/stats.lua)
    STATS_ENABLED = true,
    -- Итоги матча на POST_GAME (нужна и статистика). Титулы выдаются по
    -- порядку SUMMARY_TITLES, если |значение| не меньше SUMMARY_TITLE_MIN
    -- (casino_net — в золоте, storm_chaser — в уроне). При равенстве
    -- лучших: SUMMARY_TITLE_TIES = "none" — титул не выдаётся,
    -- "lowest_player_id" — игроку с меньшим playerID.
    SUMMARY_ENABLED = true,
    SUMMARY_TITLE_TIES = "none",
    SUMMARY_TITLES = { "gambler", "lucky", "chaos_master", "collector", "storm_chaser" },
    SUMMARY_TITLE_MIN = {
        gambler = 100, -- не за одну мелкую ставку
        lucky = 1,
        chaos_master = 1,
        collector = 4, -- стартовая + ещё три разных (ротации и ультимейты с предмета)
        storm_chaser = 1,
    },
    -- Голосование в лобби (выбор героев и стратегия). Вопросы и варианты по
    -- порядку; у варианта value (строка для клиента) и overrides — какие
    -- значения конфига он задаёт через OSC_Config.SetOverride. Побеждает
    -- большинство; при ничьей или без голосов — default. Счётчики голосов
    -- в net table публикуются не чаще раза в VOTE_PUBLISH_INTERVAL секунд.
    VOTE_ENABLED = true,
    VOTE_PUBLISH_INTERVAL = 0.25,
    VOTE_QUESTIONS = {
        {
            id = "rotation_interval",
            default = "60",
            options = {
                { value = "30", overrides = { ROTATION_INTERVAL = 30 } },
                { value = "60", overrides = { ROTATION_INTERVAL = 60 } },
                { value = "90", overrides = { ROTATION_INTERVAL = 90 } },
            },
        },
        {
            -- Частота хаос-раундов задаётся интервалом между их стартами
            id = "chaos_frequency",
            default = "normal",
            options = {
                { value = "rare", overrides = { ["CHAOS_ROUNDS.INTERVAL"] = 300 } },
                { value = "normal", overrides = { ["CHAOS_ROUNDS.INTERVAL"] = 200 } },
                { value = "often", overrides = { ["CHAOS_ROUNDS.INTERVAL"] = 120 } },
            },
        },
        {
            id = "casino",
            default = "on",
            options = {
                { value = "on", overrides = { CASINO_ENABLED = true } },
                { value = "off", overrides = { CASINO_ENABLED = false } },
            },
        },
    },
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
    -- Казино Огра: false — способность казино не выдаётся, автомат не
    -- ставится (может выключить голосование в лобби)
    CASINO_ENABLED = true,
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
