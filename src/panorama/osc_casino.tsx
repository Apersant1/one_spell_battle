namespace OSC {
  type CasinoOutcome = NetworkedData<OSCCasinoResult>;
  // name и value запоминаются при чтении инвентаря: проигранные предметы сервер
  // удаляет сразу, а окно ещё перерисовывается, пока крутятся барабаны
  type InventorySlot = { item: ItemEntityIndex | -1; reason: string; name: string; value: number };
  type ReelView = { symbol: string; spinning: boolean; stopped: boolean };

  // Окно автомата (React). Состояние спина — переменные модуля, как и раньше:
  // их меняют события сервера и таймеры анимации, после чего Render()
  // перерисовывает окно. Зона действия по Alt и повторное открытие по
  // выделению автомата — без React.
  export const Casino = (function () {
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
    function Localized(token: string, vars?: Record<string, unknown>) {
      return function (panel: LabelPanel) {
        for (var key in vars || {}) {
          var value = vars![key];
          if (typeof value === "number") {
            panel.SetDialogVariableInt(key, value);
          } else {
            panel.SetDialogVariable(key, String(value));
          }
        }
        return $.Localize("#" + token, panel);
      };
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
    function GetLocalHero() {
      return Players.GetPlayerHeroEntityIndex(Players.GetLocalPlayer());
    }

    function GetItemValue(item: ItemEntityIndex) {
      return Math.floor(Items.GetCost(item) * itemValueFactor);
    }

    // Ключ локализации причины, по которой предмет нельзя поставить (то же, что
    // проверяет сервер), или ""
    function GetItemRejectReason(item: ItemEntityIndex, hero: EntityIndex) {
      if (!Items.IsSellable(item) || GetItemValue(item) <= 0)
        return "osc_casino_err_item_unsellable";
      if (Items.GetPurchaser(item) !== hero) return "osc_casino_err_item_not_yours";
      return "";
    }

    // Шесть слотов основного инвентаря; item -1 — слот пуст
    function GetInventorySlots() {
      var hero = GetLocalHero();
      var result: InventorySlot[] = [];
      for (var slot = 0; slot < 6; slot++) {
        var item: ItemEntityIndex | -1 =
          hero === undefined || hero === -1 ? -1 : Entities.GetItemInSlot(hero, slot);
        if (item === undefined) item = -1;
        result.push({
          item: item,
          reason: item === -1 ? "" : GetItemRejectReason(item, hero),
          name: item === -1 ? "" : Abilities.GetAbilityName(item),
          value: item === -1 ? 0 : GetItemValue(item),
        });
      }
      return result;
    }

    // Предметы основного инвентаря, которые можно поставить
    function GetStakeableItems() {
      if (!itemBets) return [];
      return GetInventorySlots()
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

    // Названия предметов из ответа сервера ("item_a,item_b") через запятую
    // Одинаковые предметы схлопываются: «Javelin ×3, Blades of Attack»
    function LocalizeItemList(names: string) {
      var order: string[] = [];
      var counts: Record<string, number> = {};
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

    // Перечитывает инвентарь; перерисовывает ряд, только если он изменился
    function RefreshItems(force: boolean) {
      var current = GetInventorySlots();
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
      if (responseTimeoutHandle !== null) {
        $.CancelScheduled(responseTimeoutHandle);
        responseTimeoutHandle = null;
      }
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

    // ================= Зона действия по Alt =================
    var rangeParticles: Record<string, ParticleID> = {}; // entindex автомата -> частица

    function GetUseDistance() {
      var data = CustomNetTables.GetTableValue("osc_state", "casino");
      return (data && data.use_distance) || DEFAULT_USE_DISTANCE;
    }

    function FindMachines() {
      var found: EntityIndex[] = [];
      var creatures = Entities.GetAllEntitiesByClassname("npc_dota_creature") || [];
      for (var i = 0; i < creatures.length; i++) {
        if (Entities.GetUnitName(creatures[i]) === MACHINE_UNIT_NAME) {
          found.push(creatures[i]);
        }
      }
      return found;
    }

    function DestroyRange(ent: string) {
      Particles.DestroyParticleEffect(rangeParticles[ent], true);
      Particles.ReleaseParticleIndex(rangeParticles[ent]);
      delete rangeParticles[ent];
    }

    function UpdateRangeDisplay() {
      if (OSC.Util.IsPostGame()) return false;

      var show: Record<string, boolean> = {};
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
          Number(key) as EntityIndex,
        );
        Particles.SetParticleControl(particle, 1, [radius, 0, 0]);
        rangeParticles[key] = particle;
      }
    }

    // ================= Окно =================

    function Tooltip(getText: () => string) {
      return {
        onmouseover: function (panel: Panel) {
          var text = getText();
          if (text) $.DispatchEvent("DOTAShowTextTooltip", panel, text);
        },
        onmouseout: function (panel: Panel) {
          $.DispatchEvent("DOTAHideTextTooltip", panel);
        },
      };
    }

    // Panorama не пускает текст по кривой — заголовок собран из букв: каждая
    // опущена по параболе и повёрнута по касательной к ней
    function Title() {
      var letters = $.Localize("#osc_casino_title").split("");
      var half = Math.max(1, (letters.length - 1) / 2);
      var halfWidth = half * TITLE_LETTER_WIDTH;
      return (
        <Panel id="CasinoTitle" hittest={false}>
          {letters.map(function (letter, i) {
            if (letter === " ") return <Panel key={i} className="CasinoTitleSpace" />;
            var t = (i - half) / half; // -1 … 1 слева направо
            var y = TITLE_ARC * t * t;
            var angle = (Math.atan((2 * TITLE_ARC * t) / halfWidth) * 180) / Math.PI;
            return (
              <Label
                key={i}
                className="OSCTextTitle OSCGold"
                text={letter}
                style={{
                  transform:
                    "translateY(" + y.toFixed(1) + "px) rotateZ(" + angle.toFixed(1) + "deg)",
                }}
              />
            );
          })}
        </Panel>
      );
    }

    // Таблица выплат из исходов, которые прислал сервер: по ячейке на тройку
    // (три символа, под ними множитель и шанс); самая дорогая подсвечена
    function Paytable() {
      var top = Math.max.apply(
        null,
        payouts.map(function (o) {
          return o.multiplier;
        }),
      );
      return (
        <Panel id="CasinoPaytable">
          {payouts.map(function (o) {
            var classes = ["CasinoPayCell"];
            if (o.multiplier === top) classes.push("Top");
            if (o.symbol === hitSymbol) classes.push("Hit");
            return (
              <Panel key={o.symbol} className={classes.join(" ")}>
                <Panel className="CasinoPayIcons">
                  {[0, 1, 2].map(function (i) {
                    return <Panel key={i} className={"CasinoPayIcon Sym_" + o.symbol} />;
                  })}
                </Panel>
                <Panel className="CasinoPayText">
                  <Label className="CasinoPayMult" text={"×" + o.multiplier} />
                  <Label className="CasinoPayChance" text={o.chance + "%"} />
                </Panel>
              </Panel>
            );
          })}
        </Panel>
      );
    }

    // Слот инвентаря: свой продаваемый предмет — кнопка ставки; чужой или
    // непродаваемый — серый с подсказкой почему; пустой — тёмная ячейка
    function Slot(props: { slot: InventorySlot }) {
      var slot = props.slot;
      if (slot.item === -1) return <Button className="CasinoItem Empty" />;
      var item = slot.item;
      var image = <DOTAItemImage itemname={slot.name} hittest={false} />;
      if (slot.reason) {
        return (
          <Button
            className="CasinoItem Locked"
            {...Tooltip(function () {
              return $.Localize("#" + slot.reason);
            })}
          >
            {image}
          </Button>
        );
      }
      return (
        <Button
          className={"CasinoItem" + (selectedItems.indexOf(item) >= 0 ? " Selected" : "")}
          onactivate={function () {
            SelectItem(item);
          }}
        >
          {image}
          <Label className="CasinoItemPrice" text={String(slot.value)} />
        </Button>
      );
    }

    function CasinoWindow() {
      var [, bump] = React.useReducer(function (n: number) {
        return n + 1;
      }, 0);
      Render = bump;

      var stake = parseInt(stakeText, 10);
      var busy = machine < 0 || waiting || animating;
      var spinEnabled =
        stakeMode === "items"
          ? !busy && selectedItems.length > 0 && GetSelectedValue() >= stakeMinimum
          : !busy &&
            !isNaN(stake) &&
            stake >= stakeMinimum &&
            !isNaN(currentGold) &&
            stake <= currentGold;
      var selectedValue = GetSelectedValue();
      // TextEntry не центрирует текст (text-align не действует) — сдвигаем его
      // отступом слева по числу символов.
      // shortcut: ширина цифры подобрана на глаз (~10px при 18px); если шрифт поля
      // сменится, подобрать STAKE_DIGIT_WIDTH заново
      var free = STAKE_TEXT_AREA - stakeText.length * STAKE_DIGIT_WIDTH;

      var windowClasses: string[] = [];
      if (windowSpinning) windowClasses.push("Spinning");
      if (windowWin) windowClasses.push(windowWin);
      if (stakeMode === "items") windowClasses.push("ModeItems");

      return (
        <Panel id="CasinoPanel" className={visible ? "Visible" : ""} hittest={true}>
          <Panel id="CasinoWindow" className={windowClasses.join(" ")} hittest={true}>
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
                  var classes = ["CasinoReel", "Sym_" + reel.symbol];
                  if (reel.spinning) classes.push("Spinning");
                  if (reel.stopped) classes.push("Stopped");
                  return (
                    <Panel key={i} id={"CasinoReel" + (i + 1)} className={classes.join(" ")}>
                      <Panel className="CasinoReelStrip" />
                    </Panel>
                  );
                })}
              </Panel>
            </Panel>
            <Label
              id="CasinoResult"
              className="OSCTextBody"
              text={Localized(result.token, result.vars)}
            />
            <Paytable />
            <Label
              id="CasinoBalance"
              className="OSCTextBody OSCBold OSCGold"
              text={
                isNaN(currentGold) ? "" : Localized("osc_casino_balance", { gold: currentGold })
              }
            />
            {/* Ставка либо золотом, либо предметами: переключатель с иконками,
                ползунок под активной */}
            <Panel id="CasinoModeTabs" className={itemBets ? "" : "Hidden"}>
              <Button
                id="CasinoModeSwitch"
                className={itemsUnavailable ? "ItemsUnavailable" : ""}
                onactivate={ToggleMode}
                {...Tooltip(function () {
                  if (stakeMode === "gold" && itemsUnavailable) {
                    return $.Localize("#osc_casino_items_empty");
                  }
                  return $.Localize(
                    stakeMode === "items" ? "#osc_casino_mode_items" : "#osc_casino_mode_gold",
                  );
                })}
              >
                <Panel id="CasinoModeKnob" hittest={false} />
                <Panel id="CasinoModeGoldIcon" className="CasinoModeIcon" hittest={false} />
                <DOTAItemImage
                  id="CasinoModeItemsIcon"
                  className="CasinoModeIcon"
                  itemname="item_broadsword"
                  hittest={false}
                />
              </Button>
            </Panel>
            {/* Режим «Предметы»: шесть слотов инвентаря и сумма ставки (красная,
                если меньше минимума) */}
            <Panel id="CasinoItemsRow">
              <Panel id="CasinoItems">
                {slots.map(function (slot, i) {
                  return <Slot key={i + ":" + slot.item} slot={slot} />;
                })}
              </Panel>
              <Label
                id="CasinoItemsTotal"
                className={selectedItems.length > 0 && selectedValue < stakeMinimum ? "Low" : ""}
                text={String(selectedValue)}
                {...Tooltip(function () {
                  return Localized("osc_casino_items_hint", { min: stakeMinimum })(
                    $("#CasinoItemsTotal") as LabelPanel,
                  );
                })}
              />
            </Panel>
            <Panel id="CasinoStakeRow">
              {/* −/+ гаснут на краях диапазона */}
              <Button
                id="CasinoStakeMinus"
                className="CasinoStakeStep"
                enabled={!busy && (isNaN(stake) || stake > stakeMinimum)}
                onactivate={function () {
                  StepStake(-1);
                }}
              >
                <Label text={$.Localize("#osc_casino_stake_minus")} />
              </Button>
              <TextEntry
                id="CasinoStake"
                text={stakeText}
                maxchars={8}
                style={{ paddingLeft: STAKE_COIN_WIDTH + Math.max(0, Math.floor(free / 2)) + "px" }}
                ontextentrychange={function (entry) {
                  stakeText = entry.text;
                  Render();
                }}
              />
              <Button
                id="CasinoStakePlus"
                className="CasinoStakeStep"
                enabled={!busy && (isNaN(stake) || isNaN(currentGold) || stake < currentGold)}
                onactivate={function () {
                  StepStake(1);
                }}
              >
                <Label text={$.Localize("#osc_casino_stake_plus")} />
              </Button>
            </Panel>
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
    function Init() {
      ReactPanorama.render(<CasinoWindow />, $("#CasinoRoot"));
      GameEvents.Subscribe("osc_casino_open", OnOpen);
      GameEvents.Subscribe("osc_casino_result", OnResult);
      GameEvents.Subscribe("osc_casino_closed", OnClosed);
      OSC.Util.Loop(SELECTION_POLL, PollSelection);
      OSC.Util.Loop(RANGE_POLL, UpdateRangeDisplay);
      OSC.Util.Loop(0.5, PollItems);
    }

    return { Init: Init };
  })();
}
