"use strict";

var OSC = OSC || {};

OSC.Casino = (function () {
  // ================= Настройки =================
  var MACHINE_UNIT_NAME = "npc_osc_casino_test_object";
  var MIN_SPIN_TIME = 1.6; // минимум вращения всех барабанов
  var REEL_STOP_DELAYS = [0, 0.4, 1.1]; // последний держит паузу
  var REEL_TICK = 0.07;
  var REEL_BOUNCE_TIME = 0.3; // совпадает с OSCReelBounce
  var RESPONSE_TIMEOUT = 8;
  var RANGE_PARTICLE = "particles/ui_mouseactions/range_display.vpcf";
  var RANGE_POLL = 0.05; // как часто проверяем Alt
  var DEFAULT_USE_DISTANCE = 450;
  var SELECTION_POLL = 0.2;
  var REOPEN_RETRY = 0.5; // пока автомат в портрете, а окно закрыто, повторяем запрос
  var JACKPOT_PARTICLE = ""; // путь к .vpcf
  var JACKPOT_PARTICLE_LIFETIME = 3;
  var DEFAULT_STAKE_MINIMUM = 50;

  var SPIN_SYMBOLS = ["7", "★", "♦", "●", "♠"];
  var SYMBOL_LABELS = { circle: "●", diamond: "♦", star: "★", seven: "7" };

  // ================= Состояние =================
  var machine = -1;
  var waiting = false; // ждём ответ сервера
  var animating = false; // барабаны крутятся или останавливаются
  var revealing = false; // идёт поочерёдная остановка
  var minSpinDone = false;
  var outcome = null;
  var spinToken = 0; // меняется при каждом спине и закрытии
  var reelSpinning = [false, false, false];
  var responseTimeoutHandle = null;
  var minSpinHandle = null;
  var stakeMinimum = DEFAULT_STAKE_MINIMUM;
  var currentGold = NaN;
  var itemBets = true; // сервер разрешает ставить предметы
  var itemValueFactor = 0.5; // предмет стоит эту долю цены (как при продаже)
  var selectedItems = []; // предметы, выбранные ставкой (можно несколько)
  var itemsSignature = ""; // чтобы не перестраивать ряд предметов без нужды
  var lastSelectedMachine = -1;
  var selectionSuppressed = false;

  // ================= Вспомогательное =================
  // Автомат, который игрок сейчас выбрал кликом, или -1.
  // Чужого юнита (а автомат принадлежит Огру) нельзя «выделить» — он становится
  // юнитом в портрете (query unit). Поэтому смотрим портрет, а не выделение.
  function GetClickedMachine() {
    var unit = Players.GetLocalPlayerPortraitUnit();
    if (unit === undefined || unit === -1) return -1;
    return Entities.GetUnitName(unit) === MACHINE_UNIT_NAME ? unit : -1;
  }

  function Reel(index) {
    return $("#CasinoReel" + (index + 1));
  }

  function CancelTimers() {
    if (responseTimeoutHandle !== null) {
      $.CancelScheduled(responseTimeoutHandle);
      responseTimeoutHandle = null;
    }
    if (minSpinHandle !== null) {
      $.CancelScheduled(minSpinHandle);
      minSpinHandle = null;
    }
  }

  // Текст из resource/addon_<язык>.txt; vars подставляются в {d:...} и {s:...}
  function SetLocalized(panel, token, vars) {
    for (var key in vars || {}) {
      var value = vars[key];
      if (typeof value === "number") {
        panel.SetDialogVariableInt(key, value);
      } else {
        panel.SetDialogVariable(key, String(value));
      }
    }
    panel.text = $.Localize("#" + token, panel);
  }

  function SetResult(token, vars) {
    SetLocalized($("#CasinoResult"), token, vars);
  }

  function SetBalance(gold) {
    currentGold = gold;
    SetLocalized($("#CasinoBalance"), "osc_casino_balance", { gold: gold });
  }

  // Строка правил собирается из таблицы исходов, которую прислал сервер
  function SetRules(outcomes, loseChance) {
    var keys = Object.keys(outcomes || {}).sort(function (a, b) {
      return Number(a) - Number(b);
    });
    var parts = keys.map(function (key) {
      var o = outcomes[key];
      return (
        (SYMBOL_LABELS[o.symbol] || o.symbol) +
        " ×" +
        o.multiplier +
        " (" +
        o.chance +
        "%)"
      );
    });
    SetLocalized($("#CasinoDescription"), "osc_casino_rules", {
      outcomes: parts.join(", "),
      lose_chance: loseChance || 0,
    });
  }

  function UpdateSpinButton() {
    var stakeEntry = $("#CasinoStake");
    var spinButton = $("#CasinoSpinButton");
    // При горячей перезагрузке разметки панели на миг пропадают
    if (!stakeEntry || !spinButton) return;

    // Выбраны предметы — ставка считается по ним, поле золота не нужно
    stakeEntry.enabled = selectedItems.length === 0;
    if (selectedItems.length > 0) {
      spinButton.enabled =
        machine >= 0 &&
        !waiting &&
        !animating &&
        GetSelectedValue() >= stakeMinimum;
      return;
    }

    var stake = parseInt(stakeEntry.text, 10);
    var gold = currentGold;
    spinButton.enabled =
      machine >= 0 &&
      !waiting &&
      !animating &&
      !isNaN(stake) &&
      stake >= stakeMinimum &&
      !isNaN(gold) &&
      stake <= gold;
  }

  // ================= Анимация барабанов =================
  function AnimateReels(token) {
    if (token !== spinToken) return;
    var anySpinning = false;
    for (var i = 0; i < 3; i++) {
      if (!reelSpinning[i]) continue;
      anySpinning = true;
      Reel(i).text =
        SPIN_SYMBOLS[Math.floor(Math.random() * SPIN_SYMBOLS.length)];
    }
    if (anySpinning) {
      $.Schedule(REEL_TICK, function () {
        AnimateReels(token);
      });
    }
  }

  function StopReel(index, symbol, bounce) {
    reelSpinning[index] = false;
    var reel = Reel(index);
    if (symbol) reel.text = symbol;
    reel.RemoveClass("Spinning");
    reel.SetHasClass("Stopped", bounce);
  }

  function ScheduleReelStop(token, index, symbol, delay) {
    $.Schedule(delay, function () {
      if (token !== spinToken) return;
      StopReel(index, symbol, true);
      OSC.Util.PlaySound(OSC.Sounds.reelStop);
    });
  }

  function PlayJackpotParticles() {
    if (!JACKPOT_PARTICLE) return;
    var fx = $("#CasinoFx");
    fx.BCreateChildren(
      '<DOTAParticleScenePanel class="CasinoFxScene" hittest="false" particleonly="true" ' +
        'startActive="true" cameraOrigin="0 0 400" lookAt="0 0 0" fov="50" ' +
        'particleName="' +
        JACKPOT_PARTICLE +
        '" />',
    );
    var scene = fx.GetChild(fx.GetChildCount() - 1);
    $.Schedule(JACKPOT_PARTICLE_LIFETIME, function () {
      if (scene && scene.IsValid()) scene.DeleteAsync(0);
    });
  }

  // ================= Ставка предметом =================
  function GetLocalHero() {
    return Players.GetPlayerHeroEntityIndex(Players.GetLocalPlayer());
  }

  function GetItemValue(item) {
    return Math.floor(Items.GetCost(item) * itemValueFactor);
  }

  // Почему предмет нельзя поставить (то же, что проверяет сервер), или ""
  function GetItemRejectReason(item, hero) {
    if (!Items.IsSellable(item) || GetItemValue(item) <= 0)
      return "не продаётся";
    if (Items.GetPurchaser(item) !== hero) return "куплен не вами";
    return "";
  }

  // Предметы основного инвентаря, которые можно поставить
  function GetStakeableItems(debugLog) {
    var hero = GetLocalHero();
    var result = [];
    if (!itemBets || hero === undefined || hero === -1) return result;
    for (var slot = 0; slot < 6; slot++) {
      var item = Entities.GetItemInSlot(hero, slot);
      if (item === undefined || item === -1) continue;
      var reason = GetItemRejectReason(item, hero);
      if (reason) {
        if (debugLog) {
          $.Msg(
            "[OSC] casino item skipped: ",
            Abilities.GetAbilityName(item),
            " (",
            reason,
            ", value ",
            GetItemValue(item),
            ")",
          );
        }
        continue;
      }
      result.push(item);
    }
    return result;
  }

  function GetSelectedValue() {
    var total = 0;
    for (var i = 0; i < selectedItems.length; i++) {
      total += GetItemValue(selectedItems[i]);
    }
    return total;
  }

  // Подпись справа от поля ставки: лимит золота или сумма выбранных предметов
  function UpdateStakeLabel() {
    var label = $("#CasinoStakeLimit");
    if (!label) return;
    if (selectedItems.length > 0) {
      var value = GetSelectedValue();
      SetLocalized(
        label,
        value >= stakeMinimum
          ? "osc_casino_stake_items"
          : "osc_casino_stake_items_low",
        { count: selectedItems.length, value: value, min: stakeMinimum },
      );
    } else {
      SetLocalized(label, "osc_casino_stake_limit", {
        min: stakeMinimum,
        max: currentGold,
      });
    }
  }

  // Клик по предмету добавляет его в ставку или убирает из неё
  function SelectItem(item) {
    if (waiting || animating) return;
    var index = selectedItems.indexOf(item);
    if (index >= 0) {
      selectedItems.splice(index, 1);
    } else {
      selectedItems.push(item);
    }
    var buttons = $("#CasinoItems").Children();
    for (var i = 0; i < buttons.length; i++) {
      buttons[i].SetHasClass(
        "Selected",
        selectedItems.indexOf(buttons[i].GetAttributeInt("osc_item", -1)) >= 0,
      );
    }
    UpdateStakeLabel();
    UpdateSpinButton();
  }

  function ClearItemSelection() {
    selectedItems = [];
    UpdateStakeLabel();
  }

  // Названия предметов из ответа сервера ("item_a,item_b") через запятую
  function LocalizeItemList(names) {
    return String(names)
      .split(",")
      .map(function (name) {
        return $.Localize("#DOTA_Tooltip_Ability_" + name);
      })
      .join(", ");
  }

  // Перестраивает ряд предметов, только если инвентарь изменился
  function RefreshItems(force) {
    var container = $("#CasinoItems");
    var row = $("#CasinoItemsRow");
    if (!container || !row) return;

    var items = GetStakeableItems(force);
    var signature = items.join(",");
    if (!force && signature === itemsSignature) return;
    itemsSignature = signature;

    // Убираем из выбора предметы, которых больше нет в инвентаре
    selectedItems = selectedItems.filter(function (item) {
      return items.indexOf(item) >= 0;
    });
    UpdateStakeLabel();

    container.RemoveAndDeleteChildren();
    // Ряд виден всегда, когда ставки предметами включены; если ставить
    // нечего — показываем подсказку, а не прячем блок
    row.SetHasClass("Hidden", !itemBets);
    var empty = $("#CasinoItemsEmpty");
    if (empty) empty.SetHasClass("Hidden", items.length > 0);
    items.forEach(function (item) {
      var button = $.CreatePanel("Button", container, "");
      button.AddClass("CasinoItem");
      button.SetHasClass("Selected", selectedItems.indexOf(item) >= 0);
      button.SetAttributeInt("osc_item", item);

      var image = $.CreatePanel("DOTAItemImage", button, "");
      image.itemname = Abilities.GetAbilityName(item);
      image.hittest = false;

      var price = $.CreatePanel("Label", button, "");
      price.AddClass("CasinoItemPrice");
      price.text = String(GetItemValue(item));

      button.SetPanelEvent("onactivate", function () {
        SelectItem(item);
      });
    });
  }

  // Пока окно открыто и спина нет, держим баланс и список предметов свежими:
  // золото меняется и без казино (убийства, покупки)
  function PollItems() {
    if (OSC.Util.IsPostGame()) return false;
    if (machine < 0 || waiting || animating) return;
    var gold = Players.GetGold(Players.GetLocalPlayer());
    if (gold !== currentGold) {
      SetBalance(gold);
      UpdateStakeLabel();
      UpdateSpinButton();
    }
    RefreshItems(false);
  }

  // ================= Жизненный цикл спина =================
  function StartSpinVisuals() {
    spinToken++;
    var token = spinToken;

    waiting = true;
    animating = true;
    revealing = false;
    minSpinDone = false;
    outcome = null;

    var win = $("#CasinoWindow");
    win.RemoveClass("Win");
    win.RemoveClass("Jackpot");
    win.AddClass("Spinning");
    SetResult("osc_casino_spinning");

    for (var i = 0; i < 3; i++) {
      reelSpinning[i] = true;
      Reel(i).RemoveClass("Stopped");
      Reel(i).AddClass("Spinning");
    }

    UpdateSpinButton();
    AnimateReels(token);

    CancelTimers();
    minSpinHandle = $.Schedule(MIN_SPIN_TIME, function () {
      minSpinHandle = null;
      if (token !== spinToken) return;
      minSpinDone = true;
      TryReveal();
    });
    responseTimeoutHandle = $.Schedule(RESPONSE_TIMEOUT, function () {
      responseTimeoutHandle = null;
      if (token !== spinToken || !waiting) return;
      waiting = false;
      outcome = { error: "osc_casino_err_timeout" };
      TryReveal();
    });
  }

  function TryReveal() {
    if (!animating || revealing || !outcome) return;

    // Ошибку показываем сразу, не дожидаясь анимации
    if (outcome.error) {
      ShowError(outcome.error, outcome);
      return;
    }
    if (!minSpinDone) return;

    revealing = true;
    var token = spinToken;
    var result = outcome;
    var symbols = [
      SYMBOL_LABELS[result.reel1] || "●",
      SYMBOL_LABELS[result.reel2] || "♦",
      SYMBOL_LABELS[result.reel3] || "★",
    ];

    for (var i = 0; i < 3; i++) {
      ScheduleReelStop(token, i, symbols[i], REEL_STOP_DELAYS[i]);
    }
    $.Schedule(REEL_STOP_DELAYS[2] + REEL_BOUNCE_TIME, function () {
      if (token !== spinToken) return;
      FinishSpin(result);
    });
  }

  // token — ключ ошибки с сервера или клиента; data — подстановки (min_stake)
  function ShowError(token, data) {
    for (var i = 0; i < 3; i++) StopReel(i, null, false);
    animating = false;
    revealing = false;
    $("#CasinoWindow").RemoveClass("Spinning");
    RefreshItems(true);
    SetResult(token, {
      min_stake: (data && data.min_stake) || stakeMinimum,
    });
    UpdateSpinButton();
  }

  function FinishSpin(result) {
    animating = false;
    revealing = false;

    var win = $("#CasinoWindow");
    win.RemoveClass("Spinning");

    var payout = result.payout;
    var isJackpot =
      result.reel1 === "seven" &&
      result.reel2 === "seven" &&
      result.reel3 === "seven";

    if (payout > 0) {
      win.AddClass(isJackpot ? "Jackpot" : "Win");
      OSC.Util.PlaySound(
        isJackpot ? OSC.Sounds.casinoJackpot : OSC.Sounds.casinoWin,
      );
      if (isJackpot) PlayJackpotParticles();
    }

    var net = result.net > 0 ? "+" + result.net : String(result.net);
    var itemNames = result.items ? LocalizeItemList(result.items) : "";
    if (result.items && result.multiplier === 1) {
      SetResult("osc_casino_result_item_return", { item: itemNames });
    } else if (payout > 0) {
      SetResult("osc_casino_result_win", { payout: payout, net: net });
    } else if (result.items) {
      SetResult("osc_casino_result_item_lose", { item: itemNames });
    } else {
      SetResult("osc_casino_result_lose", { stake: result.stake });
    }

    // Поставленные предметы ушли в автомат — снимаем выбор
    ClearItemSelection();
    RefreshItems(true);
    UpdateSpinButton();
  }

  function ResetState() {
    spinToken++; // отменяет все отложенные остановки
    CancelTimers();
    waiting = false;
    animating = false;
    revealing = false;
    minSpinDone = false;
    outcome = null;
    for (var i = 0; i < 3; i++) StopReel(i, null, false);
    $("#CasinoWindow").RemoveClass("Spinning");
  }

  // ================= События сервера =================
  function OnOpen(event) {
    machine = event.machine_entindex;
    stakeMinimum = event.min_stake || DEFAULT_STAKE_MINIMUM;
    selectionSuppressed = false;
    itemBets = event.item_bets !== false && event.item_bets !== 0;
    itemValueFactor = event.item_value_factor || 0.5;

    SetBalance(event.gold);
    SetRules(event.outcomes, event.lose_chance);
    SetLocalized($("#CasinoStakeLimit"), "osc_casino_stake_limit", {
      min: stakeMinimum,
      max: event.gold,
    });

    var currentStake = parseInt($("#CasinoStake").text, 10);
    if (
      isNaN(currentStake) ||
      currentStake < stakeMinimum ||
      currentStake > event.gold
    ) {
      $("#CasinoStake").text = String(
        Math.min(event.default_stake, event.gold),
      );
    }

    if (!animating && !waiting) {
      ClearItemSelection();
      RefreshItems(true);
    }

    if (event.spinning && !animating) {
      StartSpinVisuals();
    } else if (!animating && !waiting) {
      SetResult("osc_casino_idle");
    }

    UpdateSpinButton();
    $("#CasinoPanel").AddClass("Visible");
  }

  function OnResult(event) {
    if (responseTimeoutHandle !== null) {
      $.CancelScheduled(responseTimeoutHandle);
      responseTimeoutHandle = null;
    }
    waiting = false;

    if (event.gold !== undefined) SetBalance(event.gold);

    // Поздний ответ (после таймаута или закрытия) — только баланс
    if (!animating || revealing) {
      UpdateSpinButton();
      return;
    }

    outcome = event.error
      ? { error: event.error, min_stake: event.min_stake }
      : event;
    TryReveal();
  }

  function OnClosed(event) {
    if (
      event.machine_entindex !== undefined &&
      machine !== event.machine_entindex
    )
      return;
    Close();
    SetResult("osc_casino_vanished");
  }

  // ================= Действия игрока =================
  function Spin() {
    if (selectedItems.length > 0) {
      if (machine < 0 || waiting || animating) return;
      if (GetSelectedValue() < stakeMinimum) return;
      StartSpinVisuals();
      GameEvents.SendCustomGameEventToServer("osc_casino_spin", {
        machine_entindex: machine,
        item_entindices: selectedItems.join(","),
      });
      return;
    }

    var stake = parseInt($("#CasinoStake").text, 10);
    if (
      machine < 0 ||
      waiting ||
      animating ||
      isNaN(stake) ||
      stake < stakeMinimum
    )
      return;

    StartSpinVisuals();
    GameEvents.SendCustomGameEventToServer("osc_casino_spin", {
      machine_entindex: machine,
      stake: stake,
    });
  }

  function Close() {
    // Если окно закрыли, пока автомат в портрете, не открываем его снова сразу же
    selectionSuppressed = machine >= 0 && GetClickedMachine() === machine;
    machine = -1;
    ResetState();
    $("#CasinoPanel").RemoveClass("Visible");
  }

  // ================= Повторное открытие по выделению =================
  var nextReopenTime = 0;

  function PollSelection() {
    if (OSC.Util.IsPostGame()) return false;

    var selectedMachine = GetClickedMachine();
    var now = Game.GetGameTime();

    if (selectedMachine < 0) {
      selectionSuppressed = false;
    } else if (!selectionSuppressed && machine !== selectedMachine) {
      // Первый запрос — с подсказкой об отказе. Повторные (пока герой идёт
      // к автомату) — тихие: окно откроется, как только он подойдёт.
      var isNewClick = selectedMachine !== lastSelectedMachine;
      if (isNewClick || now >= nextReopenTime) {
        GameEvents.SendCustomGameEventToServer("osc_casino_reopen", {
          machine_entindex: selectedMachine,
          quiet: isNewClick ? 0 : 1,
        });
        nextReopenTime = now + REOPEN_RETRY;
      }
    }
    lastSelectedMachine = selectedMachine;
  }

  // ================= Зона действия по Alt =================
  var rangeParticles = {}; // entindex автомата -> частица

  function GetUseDistance() {
    var data = CustomNetTables.GetTableValue("osc_state", "casino");
    return (data && data.use_distance) || DEFAULT_USE_DISTANCE;
  }

  function FindMachines() {
    var result = [];
    var creatures =
      Entities.GetAllEntitiesByClassname("npc_dota_creature") || [];
    for (var i = 0; i < creatures.length; i++) {
      if (Entities.GetUnitName(creatures[i]) === MACHINE_UNIT_NAME) {
        result.push(creatures[i]);
      }
    }
    return result;
  }

  function DestroyRange(ent) {
    Particles.DestroyParticleEffect(rangeParticles[ent], true);
    Particles.ReleaseParticleIndex(rangeParticles[ent]);
    delete rangeParticles[ent];
  }

  function UpdateRangeDisplay() {
    if (OSC.Util.IsPostGame()) return false;

    var show = {};
    if (GameUI.IsAltDown()) {
      var machines = FindMachines();
      for (var i = 0; i < machines.length; i++) show[machines[i]] = true;
    }

    // Убираем круги у пропавших автоматов или когда Alt отпущен
    for (var ent in rangeParticles) {
      if (!show[ent]) DestroyRange(ent);
    }

    // Рисуем круги у новых
    var radius = GetUseDistance();
    for (var key in show) {
      if (rangeParticles[key] !== undefined) continue;
      var particle = Particles.CreateParticle(
        RANGE_PARTICLE,
        ParticleAttachment_t.PATTACH_ABSORIGIN_FOLLOW,
        Number(key),
      );
      Particles.SetParticleControl(particle, 1, [radius, 0, 0]);
      rangeParticles[key] = particle;
    }
  }

  // ================= Инициализация =================
  function Init() {
    GameEvents.Subscribe("osc_casino_open", OnOpen);
    GameEvents.Subscribe("osc_casino_result", OnResult);
    GameEvents.Subscribe("osc_casino_closed", OnClosed);
    $("#CasinoStake").SetPanelEvent("ontextentrychange", UpdateSpinButton);
    OSC.Util.Loop(SELECTION_POLL, PollSelection);
    OSC.Util.Loop(RANGE_POLL, UpdateRangeDisplay);
    OSC.Util.Loop(0.5, PollItems);
  }

  return {
    Init: Init,
    Spin: Spin, // вызывается из XML
    Close: Close, // вызывается из XML
  };
})();
