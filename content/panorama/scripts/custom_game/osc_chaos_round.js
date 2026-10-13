"use strict";

var OSC = OSC || {};

OSC.ChaosRound = (function () {
  var UPDATE_INTERVAL = 0.25;
  var lastPhase = "none";

  function OnPhaseChanged(phase) {
    if (phase === "warning") OSC.Util.PlaySound(OSC.Sounds.chaosWarning);
    if (phase === "active") OSC.Util.PlaySound(OSC.Sounds.chaosStart);
  }

  // key — ключ события с сервера; fallbackKey — свой ключ, если события нет
  function LocalizeKey(key, fallbackKey, panel) {
    var token = "#" + (key || fallbackKey);
    return panel ? $.Localize(token, panel) : $.Localize(token);
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
      var description = $("#ChaosRoundDescription");
      var descriptionParams = data.desc_params || {};
      for (var parameter in descriptionParams) {
        description.SetDialogVariable(
          parameter,
          String(descriptionParams[parameter])
        );
      }
      $("#ChaosRoundTitle").text = LocalizeKey(
        data.title_key,
        isActive ? "osc_hud_chaos_active_fallback" : "osc_hud_chaos_soon_fallback"
      );
      description.text =
        data.desc_key || !isActive
          ? LocalizeKey(data.desc_key, "osc_hud_chaos_soon_desc", description)
          : "";
      var timer = $("#ChaosRoundTimer");
      timer.SetDialogVariable("time", OSC.Util.FormatTime(timeLeft));
      timer.text = $.Localize(
        isActive ? "#osc_hud_chaos_time_left" : "#osc_hud_chaos_time_until",
        timer
      );
    }

    return true;
  }

  function Init() {
    OSC.Util.Loop(UPDATE_INTERVAL, Update);
  }

  return { Init: Init };
})();
