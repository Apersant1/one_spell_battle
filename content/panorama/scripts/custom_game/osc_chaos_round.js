"use strict";

var OSC = OSC || {};

OSC.ChaosRound = (function () {
  var UPDATE_INTERVAL = 0.25;
  var lastPhase = "none";
  var hudHidden = false;
  // Хаос-раунд no_hud: стандартный интерфейс Доты, наш HUD остаётся
  var NO_HUD_ELEMENTS = [
    "DOTA_DEFAULT_UI_ACTION_PANEL",
    "DOTA_DEFAULT_UI_INVENTORY_PANEL",
    "DOTA_DEFAULT_UI_INVENTORY_SHOP",
    "DOTA_DEFAULT_UI_INVENTORY_QUICKBUY",
    "DOTA_DEFAULT_UI_INVENTORY_COURIER",
    "DOTA_DEFAULT_UI_INVENTORY_GOLD",
    "DOTA_DEFAULT_UI_ACTION_MINIMAP",
    "DOTA_DEFAULT_UI_TOP_HEROES",
    "DOTA_DEFAULT_UI_TOP_TIMEOFDAY",
    "DOTA_DEFAULT_UI_TOP_BAR_BACKGROUND",
  ];

  function SetHudHidden(hidden) {
    if (hidden === hudHidden) return;
    hudHidden = hidden;
    NO_HUD_ELEMENTS.forEach(function (name) {
      var element = DotaDefaultUIElement_t[name];
      if (element !== undefined) GameUI.SetDefaultUIEnabled(element, !hidden);
    });
  }

  // Хаос-раунд mouse_swap: левая кнопка ходит и атакует, правая выделяет.
  // shortcut: только ходьба, атака и выделение — подбор предметов, рамка
  // и миникарта не инвертируются; дописать, если игроки будут жаловаться.
  var mouseSwapped = false;

  function EntityUnderCursor() {
    var entities = GameUI.FindScreenEntities(GameUI.GetCursorPosition());
    for (var i = 0; i < entities.length; i++) {
      if (entities[i].accurateCollision) return entities[i].entityIndex;
    }
    return entities.length > 0 ? entities[0].entityIndex : -1;
  }

  function IssueRightClick() {
    var target = EntityUnderCursor();
    var order = {
      OrderIssuer: PlayerOrderIssuer_t.DOTA_ORDER_ISSUER_SELECTED_UNITS,
      QueueBehavior: OrderQueueBehavior_t.DOTA_ORDER_QUEUE_NEVER,
      ShowEffects: true,
    };
    if (target !== -1 && Entities.IsEnemy(target) && Entities.IsAlive(target)) {
      order.OrderType = dotaunitorder_t.DOTA_UNIT_ORDER_ATTACK_TARGET;
      order.TargetIndex = target;
    } else {
      var position = GameUI.GetScreenWorldPosition(GameUI.GetCursorPosition());
      if (!position) return;
      order.OrderType = dotaunitorder_t.DOTA_UNIT_ORDER_MOVE_TO_POSITION;
      order.Position = position;
    }
    Game.PrepareUnitOrders(order);
  }

  function OnMouse(eventName, button) {
    if (!mouseSwapped || (button !== 0 && button !== 1) || eventName === "wheeled") {
      return false;
    }
    // Прицеливание способностью и прочие режимы клика — как обычно
    if (GameUI.GetClickBehaviors() !== CLICK_BEHAVIORS.DOTA_CLICK_BEHAVIOR_NONE) {
      return false;
    }
    if (eventName === "pressed") {
      if (button === 0) {
        IssueRightClick();
      } else {
        var target = EntityUnderCursor();
        if (target !== -1) GameUI.SelectUnit(target, false);
      }
    }
    return true;
  }

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
      SetHudHidden(false);
      mouseSwapped = false;
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

    SetHudHidden(isActive && data.event_id === "no_hud");
    mouseSwapped = isActive && data.event_id === "mouse_swap";

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
    GameUI.SetMouseCallback(OnMouse);
    OSC.Util.Loop(UPDATE_INTERVAL, Update);
  }

  return { Init: Init };
})();
