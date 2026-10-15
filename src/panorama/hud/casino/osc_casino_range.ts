namespace OSC.Casino {
  // Казино: круг зоны действия у каждого автомата, пока зажат Alt. Без React,
  // от состояния окна не зависит.
  export const MACHINE_UNIT_NAME = "npc_osc_casino_test_object";
  var RANGE_PARTICLE = "particles/ui_mouseactions/range_display.vpcf";
  var RANGE_POLL = 0.05; // как часто проверяем Alt
  var DEFAULT_USE_DISTANCE = 450;

  var rangeParticles: Record<string, ParticleID> = {}; // entindex автомата -> частица

  function GetUseDistance() {
    var data = CustomNetTables.GetTableValue("osc_state", "casino");
    return (data && data.use_distance) || DEFAULT_USE_DISTANCE;
  }

  function FindMachines() {
    var found: EntityIndex[] = [];
    var creatures = Entities.GetAllEntitiesByClassname("npc_dota_creature") || [];
    for (var i = 0; i < creatures.length; i++) {
      if (Entities.GetUnitName(creatures[i]) === MACHINE_UNIT_NAME) {
        found.push(creatures[i]);
      }
    }
    return found;
  }

  function DestroyRange(ent: string) {
    Particles.DestroyParticleEffect(rangeParticles[ent], true);
    Particles.ReleaseParticleIndex(rangeParticles[ent]);
    delete rangeParticles[ent];
  }

  function UpdateRangeDisplay() {
    if (OSC.Util.IsPostGame()) return false;

    var show: Record<string, boolean> = {};
    if (GameUI.IsAltDown()) {
      var machines = FindMachines();
      for (var i = 0; i < machines.length; i++) show[machines[i]] = true;
    }

    // Убираем круги у пропавших автоматов или когда Alt отпущен
    for (var ent in rangeParticles) {
      if (!show[ent]) DestroyRange(ent);
    }

    // Рисуем круги у новых
    var radius = GetUseDistance();
    for (var key in show) {
      if (rangeParticles[key] !== undefined) continue;
      var particle = Particles.CreateParticle(
        RANGE_PARTICLE,
        ParticleAttachment_t.PATTACH_ABSORIGIN_FOLLOW,
        Number(key) as EntityIndex,
      );
      Particles.SetParticleControl(particle, 1, [radius, 0, 0]);
      rangeParticles[key] = particle;
    }
  }

  export function StartRangeDisplay() {
    OSC.Util.Loop(RANGE_POLL, UpdateRangeDisplay);
  }
}
