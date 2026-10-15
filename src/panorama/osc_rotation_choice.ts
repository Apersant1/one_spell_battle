namespace OSC {
  // Выбор следующей способности из трёх. Сервер присылает предложение событием
  // osc_rotation_choice_offer и дублирует его в osc_state/choice_<playerID>
  // (для переподключения); клик по карточке отправляет osc_rotation_choice_pick,
  // выбор можно менять до дедлайна.
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
    var confirmHandle: ScheduleID | null = null;
    var visible = false;
    var closing = false;
    var hideHandle: ScheduleID | null = null;

    function NetTableKey(): `choice_${number}` {
      return `choice_${Players.GetLocalPlayer()}`;
    }

    function OptionsSignature(list: OSCAbilityOption[]) {
      return list
        .map(function (option) {
          return option.name;
        })
        .join(",");
    }

    function CancelHide() {
      if (hideHandle !== null) {
        $.CancelScheduled(hideHandle);
        hideHandle = null;
      }
    }

    function SetVisible(show: boolean) {
      visible = show;
      $("#ChoicePanel").SetHasClass("Visible", show);
      if (!show) {
        // Окно скрыто — тултип над исчезнувшей карточкой не нужен
        $.DispatchEvent("DOTAHideAbilityTooltip", $("#ChoicePanel"));
      }
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
      SetVisible(false);
      $("#ChoicePanel").RemoveClass("Closing");
    }

    function ScheduleHide(delay: number) {
      CancelHide();
      hideHandle = $.Schedule(delay, function () {
        hideHandle = null;
        Hide();
      });
    }

    function CurrentPick() {
      return localPick || serverPick;
    }

    function UpdateHighlight(chosen?: string) {
      var picked = chosen || CurrentPick();
      var cards = $("#ChoiceCards").Children();
      for (var i = 0; i < cards.length; i++) {
        var name = cards[i].GetAttributeString("osc_ability", "");
        cards[i].SetHasClass("Picked", name !== "" && name === picked);
        cards[i].SetHasClass("Chosen", !!chosen && name === chosen);
      }
    }

    function Pick(abilityName: string) {
      if (!visible || closing || round < 0) return;
      if (Game.GetGameTime() > deadline) return;
      localPick = abilityName;
      pendingPicks.push(abilityName);
      UpdateHighlight();
      CancelConfirm();
      confirmHandle = $.Schedule(PICK_CONFIRM_TIMEOUT, OnConfirmTimeout);
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
      UpdateHighlight();
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

    function CreateCard(container: Panel, option: OSCAbilityOption) {
      var card = $.CreatePanel("Button", container, "");
      card.AddClass("ChoiceCard");
      card.SetAttributeString("osc_ability", option.name);
      // Рамка редкости (osc_hud.css): обычная — без рамки
      card.SetHasClass("RarityRare", option.rarity === "rare");
      card.SetHasClass("RarityLegendary", option.rarity === "legendary");

      var image = $.CreatePanel("DOTAAbilityImage", card, "");
      image.AddClass("ChoiceIcon");
      image.abilityname = option.name;
      image.hittest = false;

      var displayName = OSC.Util.AbilityName(option.name, option.label);
      var nameLabel = $.CreatePanel("Label", card, "");
      nameLabel.AddClass("ChoiceName");
      nameLabel.AddClass("OSCTextSmall");
      nameLabel.AddClass("OSCBold");
      nameLabel.text = displayName;
      nameLabel.hittest = false;

      card.SetPanelEvent("onactivate", function () {
        Pick(option.name);
      });
      card.SetPanelEvent("onmouseover", function () {
        $.DispatchEvent("DOTAShowAbilityTooltip", card, option.name);
      });
      card.SetPanelEvent("onmouseout", function () {
        $.DispatchEvent("DOTAHideAbilityTooltip", card);
      });
    }

    function BuildCards() {
      var container = $("#ChoiceCards");
      container.RemoveAndDeleteChildren();
      for (var i = 0; i < options.length; i++) {
        CreateCard(container, options[i]);
      }
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
      var isNewOptions = OptionsSignature(list) !== OptionsSignature(options);

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

      if (isNewRound || isNewOptions || !visible) {
        BuildCards();
      }
      if (isNewRound || !visible) {
        CancelHide();
        closing = false;
        $("#ChoicePanel").RemoveClass("Closing");
      }
      UpdateHighlight();
      UpdateTimer();
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
      $("#ChoicePanel").AddClass("Closing");
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
      $("#ChoicePanel").AddClass("Closing");
      UpdateHighlight(serverPick);
      ScheduleHide(CHOSEN_FLASH);
    }

    function OnChoiceState(data: NetworkedData<OSCRotationChoiceState> | null) {
      if (!data) {
        OnOptionsCleared(NaN);
        return;
      }
      ApplyOffer(data, data.picked);
    }

    function UpdateTimer() {
      var left = Math.max(0, deadline - Game.GetGameTime());
      var timer = $("#ChoiceTimer") as LabelPanel;
      timer.SetDialogVariable("time", OSC.Util.FormatTime(left));
      timer.text = $.Localize("#osc_hud_choice_time_left", timer);
      var progress = duration > 0 ? Math.min(1, left / duration) : 0;
      $("#ChoiceProgressFill").style.width = (progress * 100).toFixed(1) + "%";
      $("#ChoicePanel").SetHasClass("Urgent", left <= URGENT_AT);
      return left;
    }

    function Update() {
      if (OSC.Util.IsPostGame()) {
        Hide();
        return false;
      }
      if (!visible || closing) return;
      UpdateTimer();
      // Страховка: смена не пришла — не держим окно вечно
      if (Game.GetGameTime() > deadline + STALE_AFTER) Hide();
    }

    function Init() {
      ($("#ChoiceHeader") as LabelPanel).text = $.Localize("#osc_hud_choice_header");
      GameEvents.Subscribe("osc_rotation_choice_offer", OnOffer);
      GameEvents.Subscribe("osc_rotation_choice_closed", OnClosed);
      // Сразу и текущее значение: предложение могло прийти, пока HUD не был загружен
      OSC.Net.Watch(NetTableKey, OnChoiceState);

      OSC.Util.Loop(UPDATE_INTERVAL, Update);
    }

    return { Init: Init };
  })();
}
