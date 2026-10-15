namespace OSC.Casino {
  // Окно автомата (React). Состояние спина — переменные модуля, как и раньше:
  // их меняют события сервера и таймеры анимации, после чего Render()
  // перерисовывает окно. Части окна — osc_casino_view.tsx, инвентарь —
  // osc_casino_items.ts, зона действия по Alt — osc_casino_range.ts.
  // Повторное открытие по выделению автомата — без React, здесь же.
  type CasinoOutcome = NetworkedData<OSCCasinoResult>;
  type ReelView = { symbol: string; spinning: boolean; stopped: boolean };

  // ================= Настройки =================
  var MIN_SPIN_TIME = 1.6; // минимум вращения всех барабанов
  var REEL_STOP_DELAYS = [0, 0.4, 1.1]; // последний держит паузу; сумма с REEL_BOUNCE_TIME = WIN_EFFECTS_DELAY в casino.lua
  var REEL_BOUNCE_TIME = 0.3; // совпадает с OSCReelBounce
  var RESPONSE_TIMEOUT = 8;
  var SELECTION_POLL = 0.2;
  var REOPEN_RETRY = 0.5; // пока автомат в портрете, а окно закрыто, повторяем запрос
  var JACKPOT_PARTICLE = ""; // путь к .vpcf
  var JACKPOT_PARTICLE_LIFETIME = 3;
  var DEFAULT_STAKE_MINIMUM = 50;
  var STAKE_STEP = 50; // шаг кнопок −/+ у поля ставки

  // Ключи символов с сервера; картинка — класс Sym_<ключ> (барабаны и таблица выплат)
  var SYMBOL_KEYS = ["circle", "diamond", "star", "seven"];

  // ================= Состояние =================
  var machine: EntityIndex | -1 = -1;
  var waiting = false; // ждём ответ сервера
  var animating = false; // барабаны крутятся или останавливаются
  var revealing = false; // идёт поочерёдная остановка
  var minSpinDone = false;
  var outcome: CasinoOutcome | null = null;
  var spinToken = 0; // меняется при каждом спине и закрытии
  var responseTimeoutHandle: ScheduleID | null = null;
  var minSpinHandle: ScheduleID | null = null;
  var stakeMinimum = DEFAULT_STAKE_MINIMUM;
  var currentGold = NaN;
  var itemBets = true; // сервер разрешает ставить предметы
  var itemValueFactor = 0.5; // предмет стоит эту долю цены (как при продаже)
  var stakeMode = "gold"; // "gold" | "items": ставка либо золотом, либо предметами
  var selectedItems: ItemEntityIndex[] = []; // предметы, выбранные ставкой (можно несколько)
  var itemsSignature = ""; // чтобы не перерисовывать ряд предметов без нужды
  var lastSelectedMachine: EntityIndex | -1 = -1;
  var selectionSuppressed = false;

  // То, что раньше писалось прямо в панели, — теперь рисует CasinoWindow
  var visible = false;
  var reels: ReelView[] = [
    { symbol: "seven", spinning: false, stopped: false },
    { symbol: "star", spinning: false, stopped: false },
    { symbol: "diamond", spinning: false, stopped: false },
  ];
  var windowSpinning = false;
  var windowWin = ""; // "" | "Win" | "Jackpot"
  var hitSymbol: string | null = null; // подсвеченная ячейка таблицы выплат
  var payouts: NetworkedData<OSCCasinoOutcome>[] = [];
  var result: { token: string; vars?: Record<string, unknown> } = { token: "osc_casino_idle" };
  var stakeText = "250";
  var slots: InventorySlot[] = [];
  var itemsUnavailable = false; // ставить нечего — вкладка «Предметы» серая

  var Render = function () {}; // перерисовка окна; задаёт CasinoWindow

  // ================= Вспомогательное =================
  // Автомат, который игрок сейчас выбрал кликом, или -1.
  // Чужого юнита (а автомат принадлежит Огру) нельзя «выделить» — он становится
  // юнитом в портрете (query unit). Поэтому смотрим портрет, а не выделение.
  function GetClickedMachine(): EntityIndex | -1 {
    var unit = Players.GetLocalPlayerPortraitUnit();
    if (unit === undefined || unit === -1) return -1;
    return Entities.GetUnitName(unit) === MACHINE_UNIT_NAME ? unit : -1;
  }

  function CancelTimers() {
    responseTimeoutHandle = OSC.Util.Unschedule(responseTimeoutHandle);
    minSpinHandle = OSC.Util.Unschedule(minSpinHandle);
  }

  function SetResult(token: string, vars?: Record<string, unknown>) {
    result = { token: token, vars: vars };
    Render();
  }

  function SetBalance(gold: number) {
    currentGold = gold;
    Render();
  }

  // −/+ у поля ставки: шаг STAKE_STEP в пределах от минимума до запаса золота
  function StepStake(direction: number) {
    if (machine < 0 || waiting || animating) return;
    var stake = parseInt(stakeText, 10);
    stake = isNaN(stake) ? stakeMinimum : stake + direction * STAKE_STEP;
    if (!isNaN(currentGold)) stake = Math.min(stake, currentGold);
    stakeText = String(Math.max(stakeMinimum, stake));
    Render();
  }

  // ================= Анимация барабанов =================
  // Пока у барабана класс Spinning, CSS прокручивает ленту символов (OSCReelSpin)
  function StopReel(index: number, symbol: string | null, bounce: boolean) {
    reels[index] = {
      symbol: symbol || reels[index].symbol,
      spinning: false,
      stopped: bounce,
    };
    Render();
  }

  function ScheduleReelStop(token: number, index: number, symbol: string, delay: number) {
    $.Schedule(delay, function () {
      if (token !== spinToken) return;
      StopReel(index, symbol, true);
      OSC.Util.PlaySound(OSC.Sounds.reelStop);
    });
  }

  function PlayJackpotParticles() {
    if (!JACKPOT_PARTICLE) return;
    var fx = $("#CasinoFx");
    // BCreateChildren нет в panorama-types
    (fx as Panel & { BCreateChildren(xml: string): void }).BCreateChildren(
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
  // Предметы основного инвентаря, которые можно поставить
  function GetStakeableItems() {
    if (!itemBets) return [];
    return GetInventorySlots(itemValueFactor)
      .filter(function (s) {
        return s.item !== -1 && !s.reason;
      })
      .map(function (s) {
        return s.item as ItemEntityIndex;
      });
  }

  // По запомненным слотам, а не по живым предметам (см. InventorySlot)
  function GetSelectedValue() {
    var total = 0;
    slots.forEach(function (slot) {
      if (slot.item !== -1 && selectedItems.indexOf(slot.item) >= 0) total += slot.value;
    });
    return total;
  }

  // Режим ставки. В «Предметы» нельзя, если ставить нечего
  function SetMode(mode: string) {
    if (waiting || animating) return;
    if (mode === "items" && GetStakeableItems().length === 0) return;
    stakeMode = mode;
    if (mode === "gold") selectedItems = [];
    RefreshItems(true);
    Render();
  }

  function ToggleMode() {
    SetMode(stakeMode === "gold" ? "items" : "gold");
  }

  // Клик по предмету добавляет его в ставку или убирает из неё
  function SelectItem(item: ItemEntityIndex) {
    if (waiting || animating) return;
    var index = selectedItems.indexOf(item);
    if (index >= 0) {
      selectedItems.splice(index, 1);
    } else {
      selectedItems.push(item);
    }
    Render();
  }

  function ClearItemSelection() {
    selectedItems = [];
    Render();
  }

  // Перечитывает инвентарь; перерисовывает ряд, только если он изменился
  function RefreshItems(force: boolean) {
    var current = GetInventorySlots(itemValueFactor);
    var signature = current
      .map(function (s) {
        return s.item + ":" + s.reason;
      })
      .join(",");
    if (!force && signature === itemsSignature) return;
    itemsSignature = signature;
    slots = current;

    // Убираем из выбора предметы, которых больше нет в инвентаре
    var stakeable = GetStakeableItems();
    selectedItems = selectedItems.filter(function (item) {
      return stakeable.indexOf(item) >= 0;
    });
    itemsUnavailable = stakeable.length === 0;
    if (stakeMode === "items" && stakeable.length === 0) {
      SetMode("gold");
      return;
    }
    Render();
  }

  // Пока окно открыто и спина нет, держим баланс и список предметов свежими:
  // золото меняется и без казино (убийства, покупки)
  function PollItems() {
    if (OSC.Util.IsPostGame()) return false;
    if (machine < 0 || waiting || animating) return;
    var gold = Players.GetGold(Players.GetLocalPlayer());
    if (gold !== currentGold) SetBalance(gold);
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

    windowWin = "";
    hitSymbol = null;
    windowSpinning = true;
    reels = reels.map(function (reel) {
      return { symbol: reel.symbol, spinning: true, stopped: false };
    });
    SetResult("osc_casino_spinning");

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

  function SymbolOr(symbol: string | undefined, fallback: string) {
    return symbol && SYMBOL_KEYS.indexOf(symbol) >= 0 ? symbol : fallback;
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
    var spun = outcome;
    var symbols = [
      SymbolOr(spun.reel1, "circle"),
      SymbolOr(spun.reel2, "diamond"),
      SymbolOr(spun.reel3, "star"),
    ];

    for (var i = 0; i < 3; i++) {
      ScheduleReelStop(token, i, symbols[i], REEL_STOP_DELAYS[i]);
    }
    $.Schedule(REEL_STOP_DELAYS[2] + REEL_BOUNCE_TIME, function () {
      if (token !== spinToken) return;
      FinishSpin(spun);
    });
  }

  // token — ключ ошибки с сервера или клиента; data — подстановки (min_stake)
  function ShowError(token: string, data: CasinoOutcome | null) {
    for (var i = 0; i < 3; i++) StopReel(i, null, false);
    animating = false;
    revealing = false;
    windowSpinning = false;
    RefreshItems(true);
    SetResult(token, {
      min_stake: (data && data.min_stake) || stakeMinimum,
    });
  }

  function FinishSpin(spun: CasinoOutcome) {
    animating = false;
    revealing = false;
    if (spun.gold !== undefined) currentGold = spun.gold;
    windowSpinning = false;

    var payout = spun.payout || 0;
    var isJackpot = spun.reel1 === "seven" && spun.reel2 === "seven" && spun.reel3 === "seven";

    if (payout > 0) {
      windowWin = isJackpot ? "Jackpot" : "Win";
      hitSymbol = spun.reel1 || null;
      OSC.Util.PlaySound(isJackpot ? OSC.Sounds.casinoJackpot : OSC.Sounds.casinoWin);
      if (isJackpot) PlayJackpotParticles();
    }

    var net = spun.net! > 0 ? "+" + spun.net : String(spun.net);
    var itemNames = spun.items ? LocalizeItemList(spun.items) : "";
    if (spun.items && spun.multiplier === 1) {
      SetResult("osc_casino_result_item_return", { item: itemNames });
    } else if (payout > 0) {
      SetResult("osc_casino_result_win", { payout: payout, net: net });
    } else if (spun.items) {
      SetResult("osc_casino_result_item_lose", { item: itemNames });
    } else {
      SetResult("osc_casino_result_lose", { stake: spun.stake });
    }

    // Поставленные предметы ушли в автомат — снимаем выбор
    ClearItemSelection();
    RefreshItems(true);
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
    windowSpinning = false;
  }

  // ================= События сервера =================
  function OnOpen(event: NetworkedData<CustomGameEventDeclarations["osc_casino_open"]>) {
    machine = event.machine_entindex;
    stakeMinimum = event.min_stake || DEFAULT_STAKE_MINIMUM;
    selectionSuppressed = false;
    itemBets = (event.item_bets as unknown) !== false && event.item_bets !== 0;
    itemValueFactor = event.item_value_factor || 0.5;

    currentGold = event.gold;
    payouts = OSC.Util.LuaArray(event.outcomes);

    var currentStake = parseInt(stakeText, 10);
    if (isNaN(currentStake) || currentStake < stakeMinimum || currentStake > event.gold) {
      stakeText = String(Math.min(event.default_stake, event.gold));
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

    visible = true;
    Render();
  }

  function OnResult(event: NetworkedData<CustomGameEventDeclarations["osc_casino_result"]>) {
    responseTimeoutHandle = OSC.Util.Unschedule(responseTimeoutHandle);
    waiting = false;

    // Баланс после выигрыша покажем, когда барабаны остановятся (FinishSpin),
    // иначе он раньше времени выдаёт исход
    var revealLater = animating && !revealing && !event.error;
    if (event.gold !== undefined && !revealLater) currentGold = event.gold;

    // Поздний ответ (после таймаута или закрытия) — только баланс
    if (!animating || revealing) {
      Render();
      return;
    }

    outcome = event.error ? { error: event.error, min_stake: event.min_stake } : event;
    TryReveal();
    Render();
  }

  function OnClosed(event: NetworkedData<CustomGameEventDeclarations["osc_casino_closed"]>) {
    if (event.machine_entindex !== undefined && machine !== event.machine_entindex) return;
    Close();
    SetResult("osc_casino_vanished");
  }

  // ================= Действия игрока =================
  function Spin() {
    if (stakeMode === "items") {
      if (machine < 0 || waiting || animating) return;
      if (selectedItems.length === 0 || GetSelectedValue() < stakeMinimum) return;
      StartSpinVisuals();
      GameEvents.SendCustomGameEventToServer("osc_casino_spin", {
        machine_entindex: machine as EntityIndex,
        item_entindices: selectedItems.join(","),
      });
      return;
    }

    var stake = parseInt(stakeText, 10);
    if (machine < 0 || waiting || animating || isNaN(stake) || stake < stakeMinimum) return;

    StartSpinVisuals();
    GameEvents.SendCustomGameEventToServer("osc_casino_spin", {
      machine_entindex: machine as EntityIndex,
      stake: stake,
    });
  }

  function Close() {
    // Если окно закрыли, пока автомат в портрете, не открываем его снова сразу же
    selectionSuppressed = machine >= 0 && GetClickedMachine() === machine;
    machine = -1;
    ResetState();
    visible = false;
    Render();
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
          machine_entindex: selectedMachine as EntityIndex,
          quiet: isNewClick ? 0 : 1,
        });
        nextReopenTime = now + REOPEN_RETRY;
      }
    }
    lastSelectedMachine = selectedMachine;
  }

  // ================= Окно =================
  function CasinoWindow() {
    Render = OSC.useRerender();

    var stake = parseInt(stakeText, 10);
    var busy = machine < 0 || waiting || animating;
    var selectedValue = GetSelectedValue();
    var spinEnabled =
      stakeMode === "items"
        ? !busy && selectedItems.length > 0 && selectedValue >= stakeMinimum
        : !busy &&
          !isNaN(stake) &&
          stake >= stakeMinimum &&
          !isNaN(currentGold) &&
          stake <= currentGold;

    return (
      <Panel id="CasinoPanel" className={OSC.Util.Classes(visible && "Visible")} hittest={true}>
        <Panel
          id="CasinoWindow"
          className={OSC.Util.Classes(
            windowSpinning && "Spinning",
            windowWin,
            stakeMode === "items" && "ModeItems",
          )}
          hittest={true}
        >
          <Button id="CasinoCloseButton" className="OSCButton" onactivate={Close}>
            <Label text={$.Localize("#osc_casino_btn_close")} />
          </Button>
          {/* Лента-заголовок; при джекпоте поверх проявляется огненная */}
          <Panel id="CasinoTitlePlaque" hittest={false}>
            <Panel id="CasinoTitleJackpot" hittest={false} />
            <Title />
          </Panel>
          <Panel id="CasinoReels">
            {/* Окошко барабанов: обрезает ленты по краю рамки */}
            <Panel id="CasinoReelsWindow">
              {reels.map(function (reel, i) {
                return (
                  <Panel
                    key={i}
                    id={"CasinoReel" + (i + 1)}
                    className={OSC.Util.Classes(
                      "CasinoReel",
                      "Sym_" + reel.symbol,
                      reel.spinning && "Spinning",
                      reel.stopped && "Stopped",
                    )}
                  >
                    <Panel className="CasinoReelStrip" />
                  </Panel>
                );
              })}
            </Panel>
          </Panel>
          <Label
            id="CasinoResult"
            className="OSCTextBody"
            text={OSC.Localized(result.token, result.vars)}
          />
          <Paytable payouts={payouts} hitSymbol={hitSymbol} />
          <Label
            id="CasinoBalance"
            className="OSCTextBody OSCBold OSCGold"
            text={
              isNaN(currentGold) ? "" : OSC.Localized("osc_casino_balance", { gold: currentGold })
            }
          />
          <ModeSwitch
            mode={stakeMode}
            itemBets={itemBets}
            itemsUnavailable={itemsUnavailable}
            onToggle={ToggleMode}
          />
          <ItemsRow
            slots={slots}
            selected={selectedItems}
            value={selectedValue}
            minimum={stakeMinimum}
            onSelect={SelectItem}
          />
          <StakeRow
            text={stakeText}
            busy={busy}
            minimum={stakeMinimum}
            gold={currentGold}
            onStep={StepStake}
            onChange={function (text) {
              stakeText = text;
              Render();
            }}
          />
          <Panel id="CasinoButtons">
            <Button
              id="CasinoSpinButton"
              className="OSCButton OSCButtonPrimary"
              enabled={spinEnabled}
              onactivate={Spin}
            >
              <Label text={$.Localize("#osc_casino_btn_spin")} />
            </Button>
          </Panel>
        </Panel>
        {/* Слой для частиц поверх окна */}
        <Panel id="CasinoFx" hittest={false} />
      </Panel>
    );
  }

  // ================= Инициализация =================
  export function Init() {
    ReactPanorama.render(<CasinoWindow />, $("#CasinoRoot"));
    GameEvents.Subscribe("osc_casino_open", OnOpen);
    GameEvents.Subscribe("osc_casino_result", OnResult);
    GameEvents.Subscribe("osc_casino_closed", OnClosed);
    OSC.Util.Loop(SELECTION_POLL, PollSelection);
    StartRangeDisplay();
    OSC.Util.Loop(0.5, PollItems);
  }
}
