-- 2.2: статистика матча из шины событий и событий движка

local function setup()
    require("osc/config/config")
    require("osc/config/ability_pools")
    require("osc/core/logger")
    require("osc/core/notifications")
    require("osc/core/game_events")
    require("osc/systems/stats")
    OSC_GameEvents.Init()
    OSC_Stats.Init()
end

-- Основные герои игроков 0 (Свет) и 1 (Тьма), сущности 10 и 11
local function duel()
    local radiant = H.NewHero({ playerID = 0, team = DOTA_TEAM_GOODGUYS, name = "npc_dota_hero_lina" })
    local dire = H.NewHero({ playerID = 1, team = DOTA_TEAM_BADGUYS, name = "npc_dota_hero_axe" })
    H.AddPlayer(0, radiant)
    H.AddPlayer(1, dire)
    H.entities[10], H.entities[11] = radiant, dire
    return radiant, dire
end

local function ability(name, item)
    return {
        IsNull = function() return false end,
        GetAbilityName = function() return name end,
        IsItem = function() return item == true end,
    }
end

local function kill(killed, attacker, inflictor)
    H.FireGameEvent("entity_killed", {
        entindex_killed = killed, entindex_attacker = attacker, entindex_inflictor = inflictor,
    })
end

local function hurt(victim, attacker, damage)
    H.FireGameEvent("entity_hurt", { entindex_killed = victim, entindex_attacker = attacker, damage = damage })
end

return {
    rotations_and_abilities_from_ability_changed = function()
        setup()
        local hero = duel()
        local function changed(slot, name, previous)
            OSC_GameEvents.Emit("ability_changed",
                { hero = hero, player_id = 0, slot = slot, ability = name, previous = previous })
        end

        changed("ability", "test_a", nil)       -- первая выдача
        changed("ability", "test_b", "test_a")  -- ротация
        changed("ultimate", "test_u", nil)      -- ультимейт
        changed("ability", "test_c", "test_b")  -- ротация

        local record = OSC_Stats.Player(0)
        H.eq(record.rotations, 2, "only main ability replacements count as rotations")
        H.eq(table.concat(record.abilities, ","), "test_a,test_b,test_u,test_c", "all received abilities")
        H.eq(record.hero, "npc_dota_hero_lina", "hero name")
    end,

    hero_kills_by_ability = function()
        setup()
        duel()
        H.entities[20] = ability("lina_laguna_blade")
        H.entities[21] = ability("item_dagon", true)
        local ward = H.NewHero({ playerID = 0, team = DOTA_TEAM_GOODGUYS, name = "npc_dota_plague_ward" })
        ward.IsHero = function() return false end
        H.entities[12] = ward
        local creep = H.NewHero({ playerID = 1, team = DOTA_TEAM_BADGUYS })
        creep.IsHero = function() return false end
        H.entities[13] = creep
        H.entities[14] = H.NewHero({ playerID = 1, team = DOTA_TEAM_BADGUYS, copy = "illusion" })

        kill(11, 10, 20) -- способностью
        kill(11, 10, 21) -- предметом
        kill(11, 12, 20) -- призванным существом игрока
        kill(13, 10, 20) -- крип
        kill(14, 10, 20) -- иллюзия
        kill(10, 10, 20) -- сам себя

        local record = OSC_Stats.Player(0)
        H.eq(record.kills, 3, "hero kills by the player and his units")
        H.eq(record.kill_abilities.lina_laguna_blade, 2, "kills by the ability")
        H.eq(record.kill_abilities.item_dagon, nil, "items are not abilities")
        H.eq(OSC_Stats.players[1], nil, "victim gets no record")
    end,

    casino_net_sums_spins = function()
        setup()
        duel()
        OSC_GameEvents.Emit("casino_spin_resolved", { player_id = 0, stake = 100, payout = 0, net = -100 })
        OSC_GameEvents.Emit("casino_spin_resolved", { player_id = 0, stake = 100, payout = 500, net = 400 })

        H.eq(OSC_Stats.Player(0).casino_net, 300, "wins minus stakes")
    end,

    chaos_damage_only_during_rounds = function()
        setup()
        duel()
        H.entities[15] = H.NewHero({ playerID = 1, team = DOTA_TEAM_BADGUYS, copy = "illusion" })

        hurt(11, 10, 50)
        OSC_GameEvents.Emit("chaos_started", { event_id = "test" })
        hurt(11, 10, 120)
        hurt(15, 10, 70)  -- иллюзия
        hurt(10, 10, 30)  -- по себе
        hurt(11, 10, 0)
        OSC_GameEvents.Emit("chaos_ended", { event_id = "test", stopped = false })
        hurt(11, 10, 40)

        H.eq(OSC_Stats.Player(0).chaos_damage, 120, "enemy hero damage during the round only")
    end,

    post_game_publishes_once = function()
        setup()
        duel()
        OSC_Stats.Player(0).kills = 2
        local seen = {}
        OSC_GameEvents.Subscribe("match_stats", "test", function(stats) table.insert(seen, stats) end)

        H.state = DOTA_GAMERULES_STATE_POST_GAME
        H.FireGameEvent("game_rules_state_change", {})
        OSC_Stats.OnStateChanged({ state = DOTA_GAMERULES_STATE_POST_GAME })

        H.eq(#seen, 1, "published once")
        H.eq(seen[1].players[0].kills, 2, "snapshot data")
        H.eq(seen[1].players[0].hero, "npc_dota_hero_lina", "hero of the player")
        seen[1].players[0].kills = 99
        H.eq(OSC_Stats.Player(0).kills, 2, "snapshot is a copy")
    end,

    disabled_flag_collects_nothing = function()
        setup()
        OSC_CONFIG.STATS_ENABLED = false
        duel()
        H.entities[20] = ability("lina_laguna_blade")

        kill(11, 10, 20)
        OSC_GameEvents.Emit("casino_spin_resolved", { player_id = 0, net = 100 })

        H.eq(next(OSC_Stats.players), nil, "no records")
    end,

    stats_survive_reload = function()
        setup()
        duel()
        H.entities[20] = ability("lina_laguna_blade")
        kill(11, 10, 20)

        package.loaded["osc/systems/stats"] = nil
        require("osc/systems/stats")
        OSC_Stats.Init()
        kill(11, 10, 20)

        H.eq(OSC_Stats.Player(0).kills, 2, "data kept, listener not duplicated")
    end,
}
