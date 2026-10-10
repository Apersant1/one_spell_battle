"use strict";

var OSC = OSC || {};

OSC.ChaosRound = (function () {
  var SHOW_BEFORE = 30; // секунд до начала хаос-раунда
  var UPDATE_INTERVAL = 0.25;

  var lastPhase = "none";

  function OnPhaseChanged(phase) {
    if (phase === "soon") OSC.Util.PlaySound(OSC.Sounds.chaosWarning);
    if (phase === "active") OSC.Util.PlaySound(OSC.Sounds.chaosStart);
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
    var now = Game.GetGameTime();
    var isActive = Boolean(data && data.active === 1);
    var timeUntilRound =
      data && data.next_round_at >= 0 ? data.next_round_at - now : -1;
    var isSoon =
      !isActive && timeUntilRound >= 0 && timeUntilRound <= SHOW_BEFORE;

    var phase = isActive ? "active" : isSoon ? "soon" : "none";
    if (phase !== lastPhase) {
      OnPhaseChanged(phase);
      lastPhase = phase;
    }

    panel.SetHasClass("Shown", isActive || isSoon);
    panel.SetHasClass("Active", isActive);
    panel.SetHasClass("Soon", isSoon);
    vignette.SetHasClass("Shown", isActive || isSoon);
    vignette.SetHasClass("Soon", isSoon);

    if (isActive) {
      $("#ChaosRoundTitle").text = data.title || "Хаос-раунд";
      $("#ChaosRoundDescription").text = data.description || "";
      $("#ChaosRoundTimer").text =
        "До конца: " + OSC.Util.FormatTime(data.ends_at - now);
    } else if (isSoon) {
      $("#ChaosRoundTitle").text = "Приближается хаос-раунд";
      $("#ChaosRoundDescription").text = "Правила матча скоро изменятся.";
      $("#ChaosRoundTimer").text =
        "До события: " + OSC.Util.FormatTime(timeUntilRound);
    }
  }

  function Init() {
    OSC.Util.Loop(UPDATE_INTERVAL, Update);
  }

  return { Init: Init };
})();
