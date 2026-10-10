"use strict";

var OSC = OSC || {};

OSC.Timer = (function () {
  var URGENT_AT = 10; // секунд до смены способности
  var UPDATE_INTERVAL = 0.1;

  var rotationInterval = 0;
  var lastNextRotation = null;

  function SetRingProgress(progress) {
    progress = Math.max(0, Math.min(1, progress));
    $("#TimerRingFill").style.clip =
      "radial( 50% 50%, 0deg, " + (progress * 360).toFixed(1) + "deg )";
  }

  function Update() {
    var panel = $("#TimerPanel");
    if (OSC.Util.IsPostGame()) {
      panel.AddClass("Hidden");
      return false;
    }

    var label = $("#TimerLabel");
    var data = CustomNetTables.GetTableValue("osc_state", "timer");

    if (!data || data.next_rotation < 0) {
      label.text = "Смена способностей начнётся после горна";
      SetRingProgress(1);
      panel.SetHasClass("Urgent", false);
      return;
    }

    var left = Math.max(0, data.next_rotation - Game.GetGameTime());
    if (data.next_rotation !== lastNextRotation) {
      lastNextRotation = data.next_rotation;
      rotationInterval = data.interval || left;
    }

    SetRingProgress(rotationInterval > 0 ? left / rotationInterval : 0);
    label.text = "Новая способность через " + OSC.Util.FormatTime(left);
    panel.SetHasClass("Urgent", left <= URGENT_AT);
  }

  function Init() {
    OSC.Util.Loop(UPDATE_INTERVAL, Update);
  }

  return { Init: Init };
})();
