-- Пассивное золото (osc/systems/passive_gold.lua): начисление по таймеру
-- после горна, только игрокам с героем, остановка на POST_GAME

local function setup()
    require("osc/config/config")
    require("osc/core/logger")
    require("osc/systems/passive_gold")
    H.AddPlayer(0, H.NewHero({}), { gold = 0 })
    H.AddPlayer(1, nil, { gold = 0 }) -- ещё без героя
    OSC_PassiveGold.Init()
end

return {
    engine_passive_gold_is_off = function()
        setup()
        H.eq(H.goldPerTick, 0, "engine passive gold disabled")
    end,

    starts_at_horn_and_pays_heroes = function()
        setup()
        H.eq(H.thinks["osc_passive_gold"], nil, "no gold before the horn")
        OSC_GameEvents.Emit("game_started")
        H.eq(H.RunThink("osc_passive_gold"), OSC_Config.Get("PASSIVE_GOLD_TICK_TIME"), "keeps ticking")
        H.eq(H.players[0].gold, OSC_Config.Get("PASSIVE_GOLD_PER_TICK"), "hero owner paid")
        H.eq(H.players[1].gold, 0, "player without a hero not paid")
    end,

    stops_after_the_game = function()
        setup()
        OSC_GameEvents.Emit("game_started")
        H.state = DOTA_GAMERULES_STATE_POST_GAME
        H.eq(H.RunThink("osc_passive_gold"), nil, "timer stops")
        H.eq(H.players[0].gold, 0, "nothing paid after the game")
    end,
}
