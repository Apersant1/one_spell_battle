"use strict";

var OSC = OSC || {};

// Справка по правилам режима: кнопка «?» рядом с Хаос-лавкой открывает и
// закрывает панель, тексты разделов — в osc_hud.xml (ключи osc_hud_help_*).
// Только клиент: сервер о справке не знает.
OSC.Help = (function () {
  function SetOpen(open) {
    $("#HelpPanel").SetHasClass("Visible", open);
  }

  function Toggle() {
    SetOpen(!$("#HelpPanel").BHasClass("Visible"));
  }

  function Close() {
    SetOpen(false);
  }

  function Init() {
    SetOpen(false);
  }

  return { Init: Init, Toggle: Toggle, Close: Close };
})();
