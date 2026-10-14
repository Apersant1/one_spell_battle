-- Интерфейс прячет клиент (osc_chaos_round.js) по event_id в net table
OSC_ChaosEvents:Register({
    id = "no_hud",
    weight = 8,
    conflicts = { "mouse_swap", "tunnel", "vegas" },
})
