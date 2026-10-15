"use strict";

var OSC = OSC || {};

// Значок «Якоря» у таймера ротации: osc_state/anchor_<playerID> = { active, rotations }.
// Пока якорь стоит, ротации этого игрока пропускаются (rotations — сколько осталось).
OSC.Anchor = (function () {
  var rotations = 0;

  function NetTableKey() {
    return "anchor_" + Players.GetLocalPlayer();
  }

  function Apply(data) {
    var active = !!data && Number(data.active) === 1;
    rotations = (data && Number(data.rotations)) || 1;
    var badge = $("#AnchorBadge");
    badge.SetHasClass("Active", active);
    $("#TimerPanel").SetHasClass("Anchored", active);
    if (!active) HideTooltip();
  }

  function ShowTooltip() {
    var badge = $("#AnchorBadge");
    $.DispatchEvent(
      "DOTAShowTitleTextTooltip",
      badge,
      $.Localize("#osc_hud_anchor_title"),
      $.Localize("#osc_hud_anchor_tooltip").replace("{n}", rotations)
    );
  }

  function HideTooltip() {
    $.DispatchEvent("DOTAHideTitleTextTooltip", $("#AnchorBadge"));
  }

  function OnNetTableChanged(tableName, key, data) {
    if (key === NetTableKey()) Apply(data);
  }

  function Init() {
    var badge = $("#AnchorBadge");
    badge.SetPanelEvent("onmouseover", ShowTooltip);
    badge.SetPanelEvent("onmouseout", HideTooltip);
    CustomNetTables.SubscribeNetTableListener("osc_state", OnNetTableChanged);
    // Переподключение: якорь мог быть поставлен до загрузки HUD
    Apply(CustomNetTables.GetTableValue("osc_state", NetTableKey()));
  }

  return { Init: Init };
})();
