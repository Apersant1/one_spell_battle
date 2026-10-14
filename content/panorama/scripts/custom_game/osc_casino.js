"use strict";

var OSC = OSC || {};

OSC.Casino = (function () {
  // ================= Настройки =================
  var MACHINE_UNIT_NAME = "npc_osc_casino_test_object";
  var MIN_SPIN_TIME = 1.6; // минимум вращения всех барабанов
  var REEL_STOP_DELAYS = [0, 0.4, 1.1]; // последний держит паузу; сумма с REEL_BOUNCE_TIME = WIN_EFFECTS_DELAY в casino.lua
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
  var STAKE_STEP = 50; // шаг кнопок −/+ у поля ставки
  var TITLE_ARC = -6; // на сколько px концы заголовка ниже середины (дуга вниз)
  var TITLE_LETTER_WIDTH = 13; // примерная ширина буквы — для наклона по касательной
  // Поле ставки (osc_hud.css, #CasinoStake): монета слева, место под цифры справа
  var STAKE_COIN_WIDTH = 26;
  var STAKE_TEXT_AREA = 103;
  var STAKE_DIGIT_WIDTH = 10;

  // Ключи символов с сервера; картинка — класс Sym_<ключ> (барабаны и таблица выплат)
  var SYMBOL_KEYS = ["circle", "diamond", "star", "seven"];

  // ================= Состояние =================
  var machine = -1;
  var waiting = false; // ждём ответ сервера
  var animating = false; // барабаны крутятся или останавливаются
  var revealing = false; // идёт поочерёдная остановка
  var minSpinDone = false;
  var outcome = null;
  var spinToken = 0; // меняется при каждом спине и закрытии
  var payCells = {}; // символ → ячейка таблицы выплат
  var responseTimeoutHandle = null;
  var minSpinHandle = null;
  var stakeMinimum = DEFAULT_STAKE_MINIMUM;
  var currentGold = NaN;
  var itemBets = true; // сервер разрешает ставить предметы
  var itemValueFactor = 0.5; // предмет стоит эту долю цены (как при продаже)
  var stakeMode = "gold"; // "gold" | "items": ставка либо золотом, либо предметами
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

  function ShowSymbol(reel, symbol) {
    SYMBOL_KEYS.forEach(function (key) {
      reel.SetHasClass("Sym_" + key, key === symbol);
    });
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

  function AddPayLabel(parent, className, text) {
    var label = $.CreatePanel("Label", parent, "");
    label.AddClass(className);
    label.text = text;
  }

  // Таблица выплат собирается из исходов, которые прислал сервер: по ячейке на
  // тройку (три символа, под ними множитель и шанс); самая дорогая подсвечена
  function SetRules(outcomes) {
    var table = $("#CasinoPaytable");
    table.RemoveAndDeleteChildren();
    payCells = {};
    var list = Object.keys(outcomes || {})
      .sort(function (a, b) {
        return Number(a) - Number(b);
      })
      .map(function (key) {
        return outcomes[key];
      });
    var top = Math.max.apply(
      null,
      list.map(function (o) {
        return o.multiplier;
      }),
    );
    list.forEach(function (o) {
      var cell = $.CreatePanel("Panel", table, "");
      cell.AddClass("CasinoPayCell");
      cell.SetHasClass("Top", o.multiplier === top);
      var icons = $.CreatePanel("Panel", cell, "");
      icons.AddClass("CasinoPayIcons");
      for (var i = 0; i < 3; i++) {
        var icon = $.CreatePanel("Panel", icons, "");
        icon.AddClass("CasinoPayIcon");
        icon.AddClass("Sym_" + o.symbol);
      }
      var text = $.CreatePanel("Panel", cell, "");
      text.AddClass("CasinoPayText");
      AddPayLabel(text, "CasinoPayMult", "×" + o.multiplier);
      AddPayLabel(text, "CasinoPayChance", o.chance + "%");
      payCells[o.symbol] = cell;
    });
  }

  function MarkPayCell(symbol) {
    for (var key in payCells) payCells[key].SetHasClass("Hit", key === symbol);
  }

  function UpdateSpinButton() {
    var stakeEntry = $("#CasinoStake");
    var spinButton = $("#CasinoSpinButton");
    // При горячей перезагрузке разметки панели на миг пропадают
    if (!stakeEntry || !spinButton) return;

    if (stakeMode === "items") {
      spinButton.enabled =
        machine >= 0 &&
        !waiting &&
        !animating &&
        selectedItems.length > 0 &&
        GetSelectedValue() >= stakeMinimum;
      return;
    }

    CenterStakeText();
    var stake = parseInt(stakeEntry.text, 10);
    var gold = currentGold;
    var busy = machine < 0 || waiting || animating;
    spinButton.enabled =
      !busy &&
      !isNaN(stake) &&
      stake >= stakeMinimum &&
      !isNaN(gold) &&
      stake <= gold;
    // −/+ гаснут на краях диапазона
    var minus = $("#CasinoStakeMinus");
    var plus = $("#CasinoStakePlus");
    if (minus) minus.enabled = !busy && (isNaN(stake) || stake > stakeMinimum);
    if (plus)
      plus.enabled = !busy && (isNaN(stake) || isNaN(gold) || stake < gold);
  }

  // TextEntry не центрирует текст (text-align не действует) — сдвигаем его
  // отступом слева по числу символов.
  // shortcut: ширина цифры подобрана на глаз (~10px при 18px); если шрифт поля
  // сменится, подобрать STAKE_DIGIT_WIDTH заново
  function CenterStakeText() {
    var entry = $("#CasinoStake");
    if (!entry) return;
    var free = STAKE_TEXT_AREA - entry.text.length * STAKE_DIGIT_WIDTH;
    entry.style.paddingLeft =
      STAKE_COIN_WIDTH + Math.max(0, Math.floor(free / 2)) + "px";
  }

  // Panorama не пускает текст по кривой — заголовок собран из букв: каждая
  // опущена по параболе и повёрнута по касательной к ней
  function BuildTitle() {
    var title = $("#CasinoTitle");
    if (!title) return;
    title.RemoveAndDeleteChildren();
    var letters = $.Localize("#osc_casino_title").split("");
    var half = Math.max(1, (letters.length - 1) / 2);
    var halfWidth = half * TITLE_LETTER_WIDTH;
    letters.forEach(function (letter, i) {
      if (letter === " ") {
        $.CreatePanel("Panel", title, "").AddClass("CasinoTitleSpace");
        return;
      }
      var t = (i - half) / half; // -1 … 1 слева направо
      var y = TITLE_ARC * t * t;
      var angle = (Math.atan((2 * TITLE_ARC * t) / halfWidth) * 180) / Math.PI;
      var label = $.CreatePanel("Label", title, "");
      label.AddClass("OSCTextTitle");
      label.AddClass("OSCGold");
      label.text = letter;
      label.style.transform =
        "translateY(" +
        y.toFixed(1) +
        "px) rotateZ(" +
        angle.toFixed(1) +
        "deg)";
    });
  }

  // −/+ у поля ставки: шаг STAKE_STEP в пределах от минимума до запаса золота
  function StepStake(direction) {
    if (machine < 0 || waiting || animating) return;
    var entry = $("#CasinoStake");
    var stake = parseInt(entry.text, 10);
    stake = isNaN(stake) ? stakeMinimum : stake + direction * STAKE_STEP;
    if (!isNaN(currentGold)) stake = Math.min(stake, currentGold);
    entry.text = String(Math.max(stakeMinimum, stake));
    UpdateSpinButton();
  }

  // ================= Анимация барабанов =================
  // Пока у барабана класс Spinning, CSS прокручивает ленту символов (OSCReelSpin)
  function StopReel(index, symbol, bounce) {
    var reel = Reel(index);
    if (symbol) ShowSymbol(reel, symbol);
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

  // Ключ локализации причины, по которой предмет нельзя поставить (то же, что
  // проверяет сервер), или ""
  function GetItemRejectReason(item, hero) {
    if (!Items.IsSellable(item) || GetItemValue(item) <= 0)
      return "osc_casino_err_item_unsellable";
    if (Items.GetPurchaser(item) !== hero)
      return "osc_casino_err_item_not_yours";
    return "";
  }

  // Шесть слотов основного инвентаря: { item, reason }; item -1 — слот пуст
  function GetInventorySlots() {
    var hero = GetLocalHero();
    var slots = [];
    for (var slot = 0; slot < 6; slot++) {
      var item =
        hero === undefined || hero === -1
          ? -1
          : Entities.GetItemInSlot(hero, slot);
      if (item === undefined) item = -1;
      slots.push({
        item: item,
        reason: item === -1 ? "" : GetItemRejectReason(item, hero),
      });
    }
    return slots;
  }

  // Предметы основного инвентаря, которые можно поставить
  function GetStakeableItems() {
    if (!itemBets) return [];
    return GetInventorySlots()
      .filter(function (s) {
        return s.item !== -1 && !s.reason;
      })
      .map(function (s) {
        return s.item;
      });
  }

  function GetSelectedValue() {
    var total = 0;
    for (var i = 0; i < selectedItems.length; i++) {
      total += GetItemValue(selectedItems[i]);
    }
    return total;
  }

  // Сумма выбранных предметов (красная, если меньше минимума)
  function UpdateStakeLabel() {
    var total = $("#CasinoItemsTotal");
    if (total) {
      var value = GetSelectedValue();
      total.text = String(value);
      total.SetHasClass(
        "Low",
        selectedItems.length > 0 && value < stakeMinimum,
      );
    }
  }

  function ShowTooltipOnHover(panel, getText) {
    // при горячей перезагрузке JS может прийти раньше разметки — не роняем Init
    if (!panel) return;
    panel.SetPanelEvent("onmouseover", function () {
      var text = getText();
      if (text) $.DispatchEvent("DOTAShowTextTooltip", panel, text);
    });
    panel.SetPanelEvent("onmouseout", function () {
      $.DispatchEvent("DOTAHideTextTooltip", panel);
    });
  }

  // Режим ставки. В «Предметы» нельзя, если ставить нечего
  function SetMode(mode) {
    if (waiting || animating) return;
    if (mode === "items" && GetStakeableItems().length === 0) return;
    stakeMode = mode;
    if (mode === "gold") selectedItems = [];
    $("#CasinoWindow").SetHasClass("ModeItems", mode === "items");
    RefreshItems(true);
    UpdateSpinButton();
  }

  function ToggleMode() {
    SetMode(stakeMode === "gold" ? "items" : "gold");
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
  // Одинаковые предметы схлопываются: «Javelin ×3, Blades of Attack»
  function LocalizeItemList(names) {
    var order = [];
    var counts = {};
    String(names)
      .split(",")
      .forEach(function (name) {
        if (!counts[name]) order.push(name);
        counts[name] = (counts[name] || 0) + 1;
      });
    return order
      .map(function (name) {
        var title = $.Localize("#DOTA_Tooltip_Ability_" + name);
        return counts[name] > 1 ? title + " ×" + counts[name] : title;
      })
      .join(", ");
  }

  // Слот инвентаря: свой продаваемый предмет — кнопка ставки; чужой или
  // непродаваемый — серый с подсказкой почему; пустой — тёмная ячейка
  function BuildSlot(container, slot) {
    var cell = $.CreatePanel("Button", container, "");
    cell.AddClass("CasinoItem");
    if (slot.item === -1) {
      cell.AddClass("Empty");
      return;
    }
    var image = $.CreatePanel("DOTAItemImage", cell, "");
    image.itemname = Abilities.GetAbilityName(slot.item);
    image.hittest = false;
    if (slot.reason) {
      cell.AddClass("Locked");
      ShowTooltipOnHover(cell, function () {
        return $.Localize("#" + slot.reason);
      });
      return;
    }
    var price = $.CreatePanel("Label", cell, "");
    price.AddClass("CasinoItemPrice");
    price.text = String(GetItemValue(slot.item));
    cell.SetHasClass("Selected", selectedItems.indexOf(slot.item) >= 0);
    cell.SetAttributeInt("osc_item", slot.item);
    cell.SetPanelEvent("onactivate", function () {
      SelectItem(slot.item);
    });
  }

  // Перестраивает слоты, только если инвентарь изменился
  function RefreshItems(force) {
    var container = $("#CasinoItems");
    if (!container) return;

    var slots = GetInventorySlots();
    var signature = slots
      .map(function (s) {
        return s.item + ":" + s.reason;
      })
      .join(",");
    if (!force && signature === itemsSignature) return;
    itemsSignature = signature;

    // Убираем из выбора предметы, которых больше нет в инвентаре
    var stakeable = GetStakeableItems();
    selectedItems = selectedItems.filter(function (item) {
      return stakeable.indexOf(item) >= 0;
    });

    // Без ставок предметами вкладок нет; ставить нечего — вкладка серая
    $("#CasinoModeTabs").SetHasClass("Hidden", !itemBets);
    $("#CasinoModeSwitch").SetHasClass(
      "ItemsUnavailable",
      stakeable.length === 0,
    );
    if (stakeMode === "items" && stakeable.length === 0) {
      SetMode("gold");
      return;
    }
    UpdateStakeLabel();

    container.RemoveAndDeleteChildren();
    slots.forEach(function (slot) {
      BuildSlot(container, slot);
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
    MarkPayCell(null);
    win.AddClass("Spinning");
    SetResult("osc_casino_spinning");

    for (var i = 0; i < 3; i++) {
      Reel(i).RemoveClass("Stopped");
      Reel(i).AddClass("Spinning");
    }

    UpdateSpinButton();

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
      SYMBOL_KEYS.indexOf(result.reel1) >= 0 ? result.reel1 : "circle",
      SYMBOL_KEYS.indexOf(result.reel2) >= 0 ? result.reel2 : "diamond",
      SYMBOL_KEYS.indexOf(result.reel3) >= 0 ? result.reel3 : "star",
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
    if (result.gold !== undefined) SetBalance(result.gold);

    var win = $("#CasinoWindow");
    win.RemoveClass("Spinning");

    var payout = result.payout;
    var isJackpot =
      result.reel1 === "seven" &&
      result.reel2 === "seven" &&
      result.reel3 === "seven";

    if (payout > 0) {
      win.AddClass(isJackpot ? "Jackpot" : "Win");
      MarkPayCell(result.reel1);
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
    SetRules(event.outcomes);

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

    // Баланс после выигрыша покажем, когда барабаны остановятся (FinishSpin),
    // иначе он раньше времени выдаёт исход
    var revealLater = animating && !revealing && !event.error;
    if (event.gold !== undefined && !revealLater) SetBalance(event.gold);

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
    if (stakeMode === "items") {
      if (machine < 0 || waiting || animating) return;
      if (selectedItems.length === 0 || GetSelectedValue() < stakeMinimum)
        return;
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
    BuildTitle();
    GameEvents.Subscribe("osc_casino_open", OnOpen);
    GameEvents.Subscribe("osc_casino_result", OnResult);
    GameEvents.Subscribe("osc_casino_closed", OnClosed);
    $("#CasinoStake").SetPanelEvent("ontextentrychange", UpdateSpinButton);
    ShowTooltipOnHover($("#CasinoModeSwitch"), function () {
      if (
        stakeMode === "gold" &&
        $("#CasinoModeSwitch").BHasClass("ItemsUnavailable")
      )
        return $.Localize("#osc_casino_items_empty");
      return $.Localize(
        stakeMode === "items"
          ? "#osc_casino_mode_items"
          : "#osc_casino_mode_gold",
      );
    });
    ShowTooltipOnHover($("#CasinoItemsTotal"), function () {
      var hint = $("#CasinoItemsTotal");
      hint.SetDialogVariableInt("min", stakeMinimum);
      return $.Localize("#osc_casino_items_hint", hint);
    });
    OSC.Util.Loop(SELECTION_POLL, PollSelection);
    OSC.Util.Loop(RANGE_POLL, UpdateRangeDisplay);
    OSC.Util.Loop(0.5, PollItems);
  }

  return {
    Init: Init,
    Spin: Spin, // вызывается из XML
    ToggleMode: ToggleMode, // вызывается из XML
    StepStake: StepStake, // вызывается из XML
    Close: Close, // вызывается из XML
  };
})();
