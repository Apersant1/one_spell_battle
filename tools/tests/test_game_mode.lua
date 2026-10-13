-- Запуск режима целиком: все модули грузятся, Activate проходит

return {
    activate_validates_pools = function()
        require("addon_game_mode")
        -- В KV есть только первая способность обычного пула и все ультимейты
        H.DefineAbility(OSC_ABILITY_POOL[1].name)
        for _, entry in ipairs(OSC_ULTIMATE_POOL) do
            H.DefineAbility(entry.name, { ultimate = true })
        end
        local ultimateCount = #OSC_ULTIMATE_POOL

        Activate()

        H.eq(#OSC_ABILITY_POOL, 1, "unknown abilities removed from pool")
        H.eq(#OSC_ULTIMATE_POOL, ultimateCount, "known ultimates kept")
        H.truthy(H.logged("One Spell Chaos loaded"), "game mode initialized")
    end,

    pools_declare_linked_sub_abilities = function()
        require("osc/config/ability_pools")
        local linked = {}
        for _, pool in ipairs({ OSC_ABILITY_POOL, OSC_ULTIMATE_POOL }) do
            for _, entry in ipairs(pool) do
                for _, link in ipairs(entry.linked or {}) do
                    linked[entry.name] = link.name
                end
            end
        end
        H.eq(linked.puck_illusory_orb, "puck_ethereal_jaunt", "Puck orb")
        H.eq(linked.bane_nightmare, "bane_nightmare_end", "Bane nightmare")
        H.eq(linked.crystal_maiden_freezing_field, "crystal_maiden_freezing_field_stop", "CM field")
    end,
}
