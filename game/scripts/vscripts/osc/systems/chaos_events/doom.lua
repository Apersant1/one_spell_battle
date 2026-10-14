-- Рывки камеры, ретро-фильтр и VHS делает клиент
-- (osc_chaos_round.js) по event_id в net table
OSC_ChaosEvents:Register({
    id = "doom",
    weight = 8,
    conflicts = OSC_ChaosEvents.SCREEN_EVENTS,
})
