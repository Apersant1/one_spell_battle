-- Цвет и качку камеры делает клиент (osc_chaos_round.ts) по event_id в net table
OSC_ChaosEvents:Register({
    id = "vegas",
    weight = 8,
    conflicts = OSC_ChaosEvents.SCREEN_EVENTS,
})
