namespace OSC {
  export const ChaosRound = (function () {
    var UPDATE_INTERVAL = 0.25;
    var lastPhase = "none";
    // Какие элементы стандартного интерфейса Доты прячет раунд; наш HUD остаётся
    var HIDDEN_UI: Record<string, (keyof typeof DotaDefaultUIElement_t)[]> = {
      no_hud: [
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
      ],
      tunnel: ["DOTA_DEFAULT_UI_ACTION_MINIMAP"], // иначе вся карта видна на миникарте
    };
    var NOTHING_HIDDEN: (keyof typeof DotaDefaultUIElement_t)[] = [];
    var hiddenUI = NOTHING_HIDDEN;

    function SetHiddenUI(names: (keyof typeof DotaDefaultUIElement_t)[]) {
      if (names === hiddenUI) return;
      function setEnabled(list: (keyof typeof DotaDefaultUIElement_t)[], enabled: boolean) {
        list.forEach(function (name) {
          var element = DotaDefaultUIElement_t[name];
          if (element !== undefined) GameUI.SetDefaultUIEnabled(element, enabled);
        });
      }
      setEnabled(hiddenUI, true);
      setEnabled(names, false);
      hiddenUI = names;
    }

    // Туннель: камера держится на своём герое, маска в CSS оставляет круг в центре
    var cameraLocked = false;

    function SetCameraLocked(locked: boolean) {
      if (locked === cameraLocked) return;
      cameraLocked = locked;
      var hero = Players.GetPlayerHeroEntityIndex(Players.GetLocalPlayer());
      GameUI.SetCameraTarget(locked ? hero : (-1 as EntityIndex));
    }

    // Лас-Вегас: камера покачивается и «дышит»; после раунда — стандартные значения
    var DEFAULT_CAMERA_YAW = 0;
    var DEFAULT_CAMERA_DISTANCE = 1134;
    var cameraSwaying = false;

    function SetCameraSwaying(swaying: boolean) {
      if (swaying === cameraSwaying) return;
      cameraSwaying = swaying;
      if (!swaying) return;
      var start = Game.Time();
      OSC.Util.Loop(0.03, function () {
        if (!cameraSwaying) {
          GameUI.SetCameraYaw(DEFAULT_CAMERA_YAW);
          GameUI.SetCameraDistance(DEFAULT_CAMERA_DISTANCE);
          return false;
        }
        var t = Game.Time() - start;
        GameUI.SetCameraYaw(DEFAULT_CAMERA_YAW + 7 * Math.sin(t * 1.1));
        GameUI.SetCameraDistance(DEFAULT_CAMERA_DISTANCE + 140 * Math.sin(t * 1.5));
        return true;
      });
    }

    // Хаос-раунд mouse_swap: левая кнопка ходит и атакует, правая выделяет.
    // shortcut: только ходьба, атака и выделение — подбор предметов, рамка
    // и миникарта не инвертируются; дописать, если игроки будут жаловаться.
    var mouseSwapped = false;

    function EntityUnderCursor(): EntityIndex | -1 {
      var entities = GameUI.FindScreenEntities(GameUI.GetCursorPosition());
      for (var i = 0; i < entities.length; i++) {
        if (entities[i].accurateCollision) return entities[i].entityIndex;
      }
      return entities.length > 0 ? entities[0].entityIndex : -1;
    }

    function IssueRightClick() {
      var target = EntityUnderCursor();
      var order: PrepareUnitOrdersArgument = {
        OrderIssuer: PlayerOrderIssuer_t.DOTA_ORDER_ISSUER_SELECTED_UNITS,
        QueueBehavior: OrderQueueBehavior_t.DOTA_ORDER_QUEUE_NEVER,
        ShowEffects: true,
        OrderType: dotaunitorder_t.DOTA_UNIT_ORDER_NONE,
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

    function OnMouse(eventName: MouseEvent, button: MouseButton | MouseScrollDirection) {
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

    // Doom: камера прыгает за героем 20 раз в секунду без сглаживания — как при
    // 20 FPS; изредка сбой трекинга сдвигает её вбок, шум VHS мигает
    var DOOM_CAMERA_STEP = 0.05;
    var VHS_GLITCH_CHANCE = 0.06;
    var VHS_GLITCH_OFFSET = 45;
    var cameraStepping = false;

    function SetCameraStepping(stepping: boolean) {
      if (stepping === cameraStepping) return;
      cameraStepping = stepping;
      if (!stepping) return;
      OSC.Util.Loop(DOOM_CAMERA_STEP, function () {
        if (!cameraStepping) return false;
        var noiseA = Math.random() < 0.5;
        $("#DoomNoiseA").SetHasClass("On", noiseA);
        $("#DoomNoiseB").SetHasClass("On", !noiseA);
        var hero = Players.GetPlayerHeroEntityIndex(Players.GetLocalPlayer());
        if (hero === -1) return true;
        var position = Entities.GetAbsOrigin(hero);
        if (Math.random() < VHS_GLITCH_CHANCE) {
          position[0] += (Math.random() < 0.5 ? -1 : 1) * VHS_GLITCH_OFFSET;
        }
        GameUI.SetCameraTargetPosition(position, -1);
        return true;
      });
    }

    function FormatVhsCounter(seconds: number) {
      var total = Math.max(0, Math.floor(seconds));
      return [Math.floor(total / 3600), Math.floor(total / 60) % 60, total % 60]
        .map(function (part) {
          return (part < 10 ? "0" : "") + part;
        })
        .join(":");
    }

    // Клиентские хаос-раунды: eventId — активный раунд или "" (нет раунда)
    function ApplyScreenEffects(eventId: string) {
      SetHiddenUI(HIDDEN_UI[eventId] || NOTHING_HIDDEN);
      mouseSwapped = eventId === "mouse_swap";
      SetCameraLocked(eventId === "tunnel");
      SetCameraSwaying(eventId === "vegas");
      $("#TunnelMask").SetHasClass("Shown", eventId === "tunnel");
      $("#VegasOverlay").SetHasClass("Shown", eventId === "vegas");
      SetCameraStepping(eventId === "doom");
      $("#DoomOverlay").SetHasClass("Shown", eventId === "doom");
      $.GetContextPanel().SetHasClass("Doom", eventId === "doom");
      if (eventId === "doom") {
        ($("#VhsCounter") as LabelPanel).text = FormatVhsCounter(Game.GetDOTATime(false, false));
      }
    }

    function OnPhaseChanged(phase: string) {
      if (phase === "warning") OSC.Util.PlaySound(OSC.Sounds.chaosWarning);
      if (phase === "active") OSC.Util.PlaySound(OSC.Sounds.chaosStart);
    }

    // key — ключ события с сервера; fallbackKey — свой ключ, если события нет
    function LocalizeKey(key: string, fallbackKey: string, panel?: Panel) {
      var token = "#" + (key || fallbackKey);
      return panel ? $.Localize(token, panel) : $.Localize(token);
    }

    function Update() {
      var panel = $("#ChaosRoundPanel");
      var vignette = $("#ChaosVignette");

      if (OSC.Util.IsPostGame()) {
        ApplyScreenEffects("");
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
      var timerEnd = isActive ? data!.end_time : data && data.start_time;
      var timeLeft = Math.max(0, (timerEnd || 0) - now);
      var phase = isActive ? "active" : isWarning ? "warning" : "none";

      ApplyScreenEffects(isActive ? data!.event_id : "");

      if (phase !== lastPhase) {
        OnPhaseChanged(phase);
        lastPhase = phase;
      }

      panel.SetHasClass("Shown", isShown);
      panel.SetHasClass("Active", isActive);
      panel.SetHasClass("Soon", isWarning);
      vignette.SetHasClass("Shown", isShown);
      vignette.SetHasClass("Soon", isWarning);

      if (data && isShown) {
        var description = $("#ChaosRoundDescription") as LabelPanel;
        var descriptionParams: Record<string, string | number> = data.desc_params || {};
        for (var parameter in descriptionParams) {
          description.SetDialogVariable(
            parameter,
            String(descriptionParams[parameter])
          );
        }
        ($("#ChaosRoundTitle") as LabelPanel).text = LocalizeKey(
          data.title_key,
          isActive ? "osc_hud_chaos_active_fallback" : "osc_hud_chaos_soon_fallback"
        );
        description.text =
          data.desc_key || !isActive
            ? LocalizeKey(data.desc_key, "osc_hud_chaos_soon_desc", description)
            : "";
        var timer = $("#ChaosRoundTimer") as LabelPanel;
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
}
