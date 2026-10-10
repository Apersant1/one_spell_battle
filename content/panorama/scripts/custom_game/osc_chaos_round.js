"use strict";

var OSC = OSC || {};

OSC.ChaosRound = (function () {
  var UPDATE_INTERVAL = 0.25;
  var lastPhase = "none";

  function OnPhaseChanged(phase) {
    if (phase === "warning") OSC.Util.PlaySound(OSC.Sounds.chaosWarning);
    if (phase === "active") OSC.Util.PlaySound(OSC.Sounds.chaosStart);
  }

  function LocalizeKey(key, fallback) {
    return key ? $.Localize("#" + key) : fallback;
  }

  function Update() {
    var panel = $("#ChaosRoundPanel");
    var vignette = $("#ChaosVignette");

    if (OSC.Util.IsPostGame()) {
      panel.SetHasClass("Shown", false);
      vignette.SetHasClass("Shown", false);
      return false;
    }

    var data = CustomNetTables.GetTableValue("osc_state", "chaos_round");
    var state = data && data.state ? data.state : "idle";
    var isActive = state === "active";
    var isWarning = state === "warning";
    var isShown = isActive || isWarning;
    var now = Game.GetGameTime();
    var timerEnd = isActive ? data.end_time : data && data.start_time;
    var timeLeft = Math.max(0, (timerEnd || 0) - now);
    var phase = isActive ? "active" : isWarning ? "warning" : "none";

    if (phase !== lastPhase) {
      OnPhaseChanged(phase);
      lastPhase = phase;
    }

    panel.SetHasClass("Shown", isShown);
    panel.SetHasClass("Active", isActive);
    panel.SetHasClass("Soon", isWarning);
    vignette.SetHasClass("Shown", isShown);
    vignette.SetHasClass("Soon", isWarning);

    if (isShown) {
      $("#ChaosRoundTitle").text = LocalizeKey(
        data.title_key,
        isActive ? "Хаос-раунд" : "Приближается хаос-раунд"
      );
      $("#ChaosRoundDescription").text = LocalizeKey(
        data.desc_key,
        isActive ? "" : "Правила матча скоро изменятся."
      );
      $("#ChaosRoundTimer").text =
        (isActive ? "До конца: " : "До события: ") +
        OSC.Util.FormatTime(timeLeft);
    }

    return true;
  }

  function Init() {
    OSC.Util.Loop(UPDATE_INTERVAL, Update);
  }

  return { Init: Init };
})();
