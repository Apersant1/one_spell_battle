"use strict";

var OSC = OSC || {};

OSC.AbilityPopup = (function () {
  var FLIP_DURATION = 0.15; // совпадает с transition-duration у #PopupCard
  var FLASH_HOLD = 0.05;
  var SHOW_DURATION = 2.5;

  var hideHandle = null;
  var flipHandle = null;
  var flashHandle = null;

  function Flash() {
    var flash = $("#PopupFlash");
    flash.AddClass("Flash");
    if (flashHandle !== null) $.CancelScheduled(flashHandle);
    flashHandle = $.Schedule(FLASH_HOLD, function () {
      flashHandle = null;
      flash.RemoveClass("Flash");
    });
  }

  function OnAbilityChanged(event) {
    var popup = $("#Popup");
    var card = $("#PopupCard");

    popup.AddClass("Visible");
    card.AddClass("FlipHidden"); // старая иконка уходит ребром

    if (flipHandle !== null) $.CancelScheduled(flipHandle);
    flipHandle = $.Schedule(FLIP_DURATION, function () {
      flipHandle = null;
      $("#PopupIcon").abilityname = event.ability;
      $("#PopupTitle").text = "Новая способность";
      $("#PopupName").text = event.label;
      card.RemoveClass("FlipHidden"); // новая разворачивается
      Flash();
      OSC.Util.PlaySound(OSC.Sounds.abilityChanged);
    });

    if (hideHandle !== null) $.CancelScheduled(hideHandle);
    hideHandle = $.Schedule(SHOW_DURATION, function () {
      hideHandle = null;
      popup.RemoveClass("Visible");
    });
  }

  function Init() {
    GameEvents.Subscribe("osc_ability_changed", OnAbilityChanged);
  }

  return { Init: Init };
})();
