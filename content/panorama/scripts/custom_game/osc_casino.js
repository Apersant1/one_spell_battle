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
  var SELECTION_POLL = 0.2;
  var JACKPOT_PARTICLE = ""; // путь к .vpcf
  var JACKPOT_PARTICLE_LIFETIME = 3;
  var DEFAULT_STAKE_MINIMUM = 50;
  var DEFAULT_DESCRIPTION =
    "Тройка: ● ×1 (60%), ♦ ×2 (5%), ★ ×5 (2%), 7 ×10 (1%). Без тройки — 32%.";

  var SPIN_SYMBOLS = ["7", "★", "♦", "●", "♠"];
  var SYMBOL_LABELS = { circle: "●", diamond: "♦", star: "★", seven: "7" };

  var TEXT = {
    idle: "Нажмите, чтобы запустить барабаны.",
    spinning: "Барабаны вращаются...",
    timeout: "Нет ответа от автомата. Попробуйте ещё раз.",
    vanished: "Автомат исчез.",
  };

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
  var lastSelectedMachine = -1;
  var selectionSuppressed = false;

  // ================= Вспомогательное =================
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

  function SetBalance(gold) {
    $("#CasinoBalance").text = "Золото: " + gold;
  }

  function UpdateSpinButton() {
    var stake = parseInt($("#CasinoStake").text, 10);
    var gold = parseInt($("#CasinoBalance").text.replace(/[^0-9]/g, ""), 10);
    $("#CasinoSpinButton").enabled =
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
    $("#CasinoResult").text = TEXT.spinning;

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
      outcome = { error: TEXT.timeout };
      TryReveal();
    });
  }

  function TryReveal() {
    if (!animating || revealing || !outcome) return;

    // Ошибку показываем сразу, не дожидаясь анимации
    if (outcome.error) {
      ShowError(outcome.error);
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

  function ShowError(message) {
    for (var i = 0; i < 3; i++) StopReel(i, null, false);
    animating = false;
    revealing = false;
    $("#CasinoWindow").RemoveClass("Spinning");
    $("#CasinoResult").text = message;
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
    $("#CasinoResult").text =
      payout > 0
        ? "Выплата: " + payout + " золота. Чистый итог: " + net
        : "Нет тройки. Ставка потеряна: " + result.stake + " золота.";
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

    SetBalance(event.gold);
    $("#CasinoDescription").text = event.description || DEFAULT_DESCRIPTION;
    $("#CasinoStakeLimit").text =
      "Мин. " + stakeMinimum + " · макс. " + event.gold;

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

    if (event.spinning && !animating) {
      StartSpinVisuals();
    } else if (!animating && !waiting) {
      $("#CasinoResult").text = TEXT.idle;
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

    outcome = event.error ? { error: event.error } : event;
    TryReveal();
  }

  function OnClosed(event) {
    if (
      event.machine_entindex !== undefined &&
      machine !== event.machine_entindex
    )
      return;
    Close();
    $("#CasinoResult").text = TEXT.vanished;
  }

  // ================= Действия игрока =================
  function Spin() {
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
    selectionSuppressed = false;
    if (machine >= 0 && Game.GetSelectedEntities) {
      var selected = Game.GetSelectedEntities();
      if (selected) {
        for (var i = 0; i < selected.length; i++) {
          if (selected[i] === machine) {
            selectionSuppressed = true;
            break;
          }
        }
      }
    }
    machine = -1;
    ResetState();
    $("#CasinoPanel").RemoveClass("Visible");
  }

  // ================= Повторное открытие по выделению =================
  function PollSelection() {
    if (OSC.Util.IsPostGame()) return false;
    if (!Game.GetSelectedEntities) return;

    var selected = Game.GetSelectedEntities();
    var selectedMachine = -1;
    if (selected) {
      for (var i = 0; i < selected.length; i++) {
        if (Entities.GetUnitName(selected[i]) === MACHINE_UNIT_NAME) {
          selectedMachine = selected[i];
          break;
        }
      }
    }

    if (selectedMachine < 0) {
      selectionSuppressed = false;
    } else if (
      selectedMachine !== lastSelectedMachine &&
      !selectionSuppressed
    ) {
      GameEvents.SendCustomGameEventToServer("osc_casino_reopen", {
        machine_entindex: selectedMachine,
      });
    }
    lastSelectedMachine = selectedMachine;
  }

  // ================= Инициализация =================
  function Init() {
    GameEvents.Subscribe("osc_casino_open", OnOpen);
    GameEvents.Subscribe("osc_casino_result", OnResult);
    GameEvents.Subscribe("osc_casino_closed", OnClosed);
    $("#CasinoStake").SetPanelEvent("ontextentrychange", UpdateSpinButton);
    OSC.Util.Loop(SELECTION_POLL, PollSelection);
  }

  return {
    Init: Init,
    Spin: Spin, // вызывается из XML
    Close: Close, // вызывается из XML
  };
})();
