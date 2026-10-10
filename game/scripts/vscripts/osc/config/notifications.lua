-- Конфигурация уведомлений OSC.
--
-- Каналы доставки (в описании типа: таблица = включён, false/nil = выключен):
--   feed      — строка в ленте уведомлений HUD (текст из addon_*.txt по token)
--   hud       — отдельное событие в Panorama-HUD игрока
--   particle  — частица на юните
--
-- Значения параметров, начинающиеся с "#", тоже переводятся на клиенте,
-- например ability = "#DOTA_Tooltip_Ability_ogre_magi_fireblast".

OSC_NOTIFICATIONS_CONFIG = {
    enabled = true,

    channels = {
        feed = true,
        hud = true,
        particle = true,
    },

    categories = {
        ability = { enabled = true },
        rotation = { enabled = true },
        chaos_round = { enabled = true },
        player = { enabled = true },
    },

    types = {
        -- ===== Способности =====
        ability_changed = {
            category = "ability",
            particle = { name = "particles/generic_hero_status/hero_levelup.vpcf" },
            hud = { event = "osc_ability_changed" },
            feed = { token = "#osc_notify_ability_changed", color = "#D98BFF", scope = "team" },
        },

        -- ===== Ротация =====
        rotation_warning = {
            category = "rotation",
            feed = { token = "#osc_notify_rotation_warning", color = "#FF8C00" },
        },

        rotation_started = {
            category = "rotation",
            feed = { token = "#osc_notify_rotation_started", color = "#FFD700" },
        },

        -- ===== Хаос-раунды =====
        chaos_round_warning = {
            category = "chaos_round",
            feed = { token = "#osc_notify_chaos_round_warning", color = "#FF8C00" },
        },

        chaos_round_started = {
            category = "chaos_round",
            feed = { token = "#osc_notify_chaos_round_started", color = "#FF4D4D" },
        },

        chaos_round_ended = {
            category = "chaos_round",
            feed = { token = "#osc_notify_chaos_round_ended", color = "#B0B0B0" },
        },

        -- ===== События игроков =====
        courier_ability_gained = {
            category = "player",
            feed = { token = "#osc_notify_courier_ability_gained", color = "#FFB347", scope = "team" },
        },
    },
}