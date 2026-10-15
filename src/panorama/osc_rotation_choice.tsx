namespace OSC {
  // Выбор следующей способности из трёх (React). Сервер присылает предложение
  // событием osc_rotation_choice_offer и дублирует его в osc_state/choice_<playerID>
  // (для переподключения); клик по карточке отправляет osc_rotation_choice_pick,
  // выбор можно менять до дедлайна. Состояние — переменные модуля: их меняют
  // события и таймеры, после чего Render() перерисовывает окно.
  export const RotationChoice = (function () {
    var UPDATE_INTERVAL = 0.1;
    var CHOSEN_FLASH = 1.2; // сколько держать подсвеченную выбранную карточку после смены
    var CLOSE_GRACE = 0.2; // ждём osc_rotation_choice_closed после опустевшей net table
    // Страховка от потерянного osc_rotation_choice_closed: оно уходит сразу на
    // ротации (ближайший тик сервера, <= 0,5 с после дедлайна, ещё до отложенной
    // замены способности), поэтому дольше ждать нет смысла
    var STALE_AFTER = 2;
    var URGENT_AT = 3; // секунд до дедлайна, когда отсчёт краснеет
    // Сколько ждать, пока сервер подтвердит клик (picked в net table);
    // потом верим net table — сервер отклоняет выбор молча
    var PICK_CONFIRM_TIMEOUT = 1.0;

    var round = -1;
    var deadline = 0;
    var duration = 0; // для полосы времени: от предложения до дедлайна
    var options: OSCAbilityOption[] = []; // [{ name, label, rarity }] в порядке ключей "1", "2", "3"
    var serverPick = ""; // picked из net table
    var localPick = ""; // последний клик в этом раунде, пока сервер не подтвердил
    var pendingPicks: string[] = []; // все неподтверждённые клики (подтверждения приходят по порядку)
    var chosen = ""; // итог раунда из osc_rotation_choice_closed — подсвечен, пока окно гаснет
    var confirmHandle: ScheduleID | null = null;
    var visible = false;
    var closing = false;
    var hideHandle: ScheduleID | null = null;

    var Render = function () {}; // перерисовка окна; задаёт ChoiceWindow

    function NetTableKey(): `choice_${number}` {
      return `choice_${Players.GetLocalPlayer()}`;
    }

    function CancelHide() {
      if (hideHandle !== null) {
        $.CancelScheduled(hideHandle);
        hideHandle = null;
      }
    }

    function SetVisible(show: boolean) {
      visible = show;
      if (!show) {
        // Окно скрыто — тултип над исчезнувшей карточкой не нужен
        $.DispatchEvent("DOTAHideAbilityTooltip", $("#ChoicePanel"));
      }
      Render();
    }

    function CancelConfirm() {
      if (confirmHandle !== null) {
        $.CancelScheduled(confirmHandle);
        confirmHandle = null;
      }
    }

    function ResetLocalPick() {
      CancelConfirm();
      localPick = "";
      pendingPicks = [];
    }

    function Hide() {
      CancelHide();
      ResetLocalPick();
      closing = false;
      chosen = "";
      SetVisible(false);
    }

    function ScheduleHide(delay: number) {
      CancelHide();
      hideHandle = $.Schedule(delay, function () {
        hideHandle = null;
        Hide();
      });
    }

    function Pick(abilityName: string) {
      if (!visible || closing || round < 0) return;
      if (Game.GetGameTime() > deadline) return;
      localPick = abilityName;
      pendingPicks.push(abilityName);
      CancelConfirm();
      confirmHandle = $.Schedule(PICK_CONFIRM_TIMEOUT, OnConfirmTimeout);
      Render();
      // Шлём каждый клик: прежний выбор мог ещё не дойти до сервера
      GameEvents.SendCustomGameEventToServer("osc_rotation_choice_pick", {
        round: round,
        ability: abilityName,
      });
    }

    // Подтверждения не было: сверяем оптимистичный выбор с net table
    function OnConfirmTimeout() {
      confirmHandle = null;
      if (!localPick || closing) return;
      var data = CustomNetTables.GetTableValue("osc_state", NetTableKey());
      if (data && Number(data.round) === round) {
        serverPick = String(data.picked || "");
      }
      ResetLocalPick();
      Render();
    }

    // Обновление picked из net table для текущего раунда
    function OnServerPick(picked: string | undefined) {
      serverPick = String(picked || "");
      if (!localPick) return;
      if (serverPick === localPick) {
        ResetLocalPick(); // сервер принял последний клик
      } else if (serverPick !== "" && pendingPicks.indexOf(serverPick) < 0) {
        ResetLocalPick(); // сервер отклонил выбор — откатываем к его picked
      }
      // picked совпал с более ранним кликом (подтверждение ещё в пути) или
      // пуст (запись не о выборе) — ждём дальше, решит таймаут
    }

    // Общая точка для события-предложения и net table.
    // picked === undefined — источник ничего не знает о выборе (событие).
    function ApplyOffer(
      data: NetworkedData<CustomGameEventDeclarations["osc_rotation_choice_offer"]>,
      picked: string | undefined,
    ) {
      var newRound = Number(data.round);
      var newDeadline = Number(data.deadline) || 0;
      var list = OSC.Util.AbilityOptions(data.options);
      var now = Game.GetGameTime();

      if (list.length === 0) {
        OnOptionsCleared(newRound);
        return;
      }
      // Старое состояние из net table (дедлайн давно прошёл) не показываем
      if (newDeadline > 0 && now > newDeadline + STALE_AFTER) return;
      // Раунд уже закрывается — запоздалые данные о нём не нужны
      if (closing && newRound === round) return;

      var isNewRound = newRound !== round;
      if (isNewRound) {
        ResetLocalPick();
        serverPick = "";
      }
      // duration от сервера верна и после переподключения; без неё считаем
      // от момента, когда увидели предложение
      var serverDuration = Number(data.duration) || 0;
      if (serverDuration > 0) {
        duration = serverDuration;
      } else if (isNewRound) {
        duration = Math.max(0, newDeadline - now);
      }
      round = newRound;
      deadline = newDeadline;
      options = list;
      if (picked !== undefined) OnServerPick(picked);

      if (isNewRound || !visible) {
        CancelHide();
        closing = false;
        chosen = "";
      }
      SetVisible(true);
    }

    // Сервер закрыл выбор (options = {}). Если следом придёт
    // osc_rotation_choice_closed — он продлит показ с подсветкой.
    function OnOptionsCleared(clearedRound: number) {
      if (!visible || closing) return;
      if (!isNaN(clearedRound) && clearedRound !== round) {
        Hide();
        return;
      }
      closing = true;
      Render();
      ScheduleHide(CLOSE_GRACE);
    }

    function OnOffer(
      event: NetworkedData<CustomGameEventDeclarations["osc_rotation_choice_offer"]>,
    ) {
      if (!event) return;
      ApplyOffer(event, undefined);
    }

    function OnClosed(
      event: NetworkedData<CustomGameEventDeclarations["osc_rotation_choice_closed"]>,
    ) {
      if (!event || Number(event.round) !== round) return;
      if (!visible) return;
      closing = true;
      ResetLocalPick();
      serverPick = String(event.chosen || "");
      chosen = serverPick;
      Render();
      ScheduleHide(CHOSEN_FLASH);
    }

    function OnChoiceState(data: NetworkedData<OSCRotationChoiceState> | null) {
      if (!data) {
        OnOptionsCleared(NaN);
        return;
      }
      ApplyOffer(data, data.picked);
    }

    function Update() {
      if (OSC.Util.IsPostGame()) {
        Hide();
        return false;
      }
      if (!visible || closing) return;
      // Страховка: смена не пришла — не держим окно вечно
      if (Game.GetGameTime() > deadline + STALE_AFTER) {
        Hide();
        return;
      }
      Render(); // отсчёт и полоса времени
    }

    function ChoiceWindow() {
      var [, bump] = React.useReducer(function (n: number) {
        return n + 1;
      }, 0);
      Render = bump;

      var left = Math.max(0, deadline - Game.GetGameTime());
      var progress = duration > 0 ? Math.min(1, left / duration) : 0;
      var picked = chosen || localPick || serverPick;
      var classes = ["OSCSurface", "OSCChaos"];
      if (visible) classes.push("Visible");
      if (closing) classes.push("Closing");
      if (visible && left <= URGENT_AT) classes.push("Urgent");

      // Кликабельны только карточки
      return (
        <Panel id="ChoicePanel" className={classes.join(" ")} hittest={false}>
          <Panel id="ChoiceHeaderRow" hittest={false}>
            <Label
              id="ChoiceHeader"
              className="OSCTextSmall OSCCaps OSCBold OSCChaosText"
              hittest={false}
              text={$.Localize("#osc_hud_choice_header")}
            />
            <Label
              id="ChoiceTimer"
              className="OSCTextSmall OSCBold OSCGold"
              hittest={false}
              text={OSC.Localized("osc_hud_choice_time_left", {
                time: OSC.Util.FormatTime(left),
              })}
            />
          </Panel>
          <Panel id="ChoiceCards" hittest={false}>
            {options.map(function (option) {
              var state: string[] = [];
              if (option.name === picked) state.push("Picked");
              if (chosen && option.name === chosen) state.push("Chosen");
              return (
                <OSC.AbilityCard
                  key={round + ":" + option.name}
                  option={option}
                  className={state.join(" ")}
                  onactivate={function () {
                    Pick(option.name);
                  }}
                />
              );
            })}
          </Panel>
          <Panel id="ChoiceProgress" hittest={false}>
            <Panel
              id="ChoiceProgressFill"
              hittest={false}
              style={{ width: (progress * 100).toFixed(1) + "%" }}
            />
          </Panel>
        </Panel>
      );
    }

    function Init() {
      ReactPanorama.render(<ChoiceWindow />, $("#ChoiceRoot"));
      GameEvents.Subscribe("osc_rotation_choice_offer", OnOffer);
      GameEvents.Subscribe("osc_rotation_choice_closed", OnClosed);
      // Сразу и текущее значение: предложение могло прийти, пока HUD не был загружен
      OSC.Net.Watch(NetTableKey, OnChoiceState);

      OSC.Util.Loop(UPDATE_INTERVAL, Update);
    }

    return { Init: Init };
  })();
}
