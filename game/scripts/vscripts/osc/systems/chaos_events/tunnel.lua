-- Камеру и маску делает клиент (osc_chaos_round.ts) по event_id в net table
OSC_ChaosEvents:Register({
    id = "tunnel",
    weight = 8,
    conflicts = OSC_ChaosEvents.SCREEN_EVENTS,
})
