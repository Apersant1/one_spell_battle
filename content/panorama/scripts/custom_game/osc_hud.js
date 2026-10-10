"use strict";

var popupHideHandle = null;
var activeCasinoMachine = -1;
var casinoWaiting = false;
var casinoAnimating = false;
var casinoOutcome = null;
var casinoSpinTimeout = null;
var casinoAnimationTimeout = null;
var casinoSymbols = ["7", "★", "♦", "●", "♠"];
var casinoStakeMinimum = 50;
var lastSelectedCasinoMachine = -1;
var casinoSelectionSuppressed = false;

// Служебные констранты для обновления HUD
var CHAOS_PANEL_SHOW_BEFORE = 30; // секунд до начала хаос-раунда

function FormatTime(seconds) {
  seconds = Math.max(0, Math.ceil(seconds));
  var m = Math.floor(seconds / 60);
  var s = seconds % 60;
  return m + ":" + (s < 10 ? "0" : "") + s;
}

function UpdateTimer() {
  var panel = $("#TimerPanel");
  var label = $("#TimerLabel");

  if (Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_POST_GAME) {
    panel.AddClass("Hidden");
    return; // игра окончена, цикл больше не нужен
  }

  var data = CustomNetTables.GetTableValue("osc_state", "timer");

  if (!data || data.next_rotation < 0) {
    label.text = "Смена способностей начнётся после горна";
    panel.SetHasClass("Urgent", false);
  } else {
    var left = data.next_rotation - Game.GetGameTime();
    label.text = "Новая способность через " + FormatTime(left);
    panel.SetHasClass("Urgent", left <= 10);
  }

  $.Schedule(0.1, UpdateTimer);
}

function UpdateChaosRound() {
  var panel = $("#ChaosRoundPanel");
  if (Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_POST_GAME) {
    panel.visible = false;
    return;
  }

  var data = CustomNetTables.GetTableValue("osc_state", "chaos_round");
  var now = Game.GetGameTime();
  var isActive = data && data.active === 1;
  var timeUntilRound =
    data && data.next_round_at >= 0 ? data.next_round_at - now : -1;
  var isSoon =
    !isActive &&
    timeUntilRound >= 0 &&
    timeUntilRound <= CHAOS_PANEL_SHOW_BEFORE;

  panel.SetHasClass("Shown", isActive || isSoon);
  panel.SetHasClass("Active", isActive);

  if (isActive) {
    $("#ChaosRoundTitle").text = data.title || "Хаос-раунд";
    $("#ChaosRoundDescription").text = data.description || "";
    $("#ChaosRoundTimer").text = "До конца: " + FormatTime(data.ends_at - now);
  } else if (isSoon) {
    $("#ChaosRoundTitle").text = "Приближается хаос-раунд";
    $("#ChaosRoundDescription").text = "Правила матча скоро изменятся.";
    $("#ChaosRoundTimer").text = "До события: " + FormatTime(timeUntilRound);
  }

  $.Schedule(0.25, UpdateChaosRound);
}

function OnAbilityChanged(event) {
  $("#PopupIcon").abilityname = event.ability;
  $("#PopupTitle").text = "Новая способность";
  $("#PopupName").text = event.label;

  var popup = $("#Popup");
  popup.AddClass("Visible");

  if (popupHideHandle !== null) {
    $.CancelScheduled(popupHideHandle);
  }
  popupHideHandle = $.Schedule(2.5, function () {
    popupHideHandle = null;
    popup.RemoveClass("Visible");
  });
}

function OnCasinoOpen(event) {
  activeCasinoMachine = event.machine_entindex;
  casinoStakeMinimum = event.min_stake || 50;
  casinoSelectionSuppressed = false;
  if (!casinoWaiting) {
    casinoOutcome = null;
  }
  $("#CasinoBalance").text = "Золото: " + event.gold;
  $("#CasinoDescription").text =
    "Тройка: ● ×1 (60%), ♦ ×2 (5%), ★ ×5 (2%), 7 ×10 (1%). Без тройки — 32%.";
  $("#CasinoStakeLimit").text =
    "Мин. " + casinoStakeMinimum + " · макс. " + event.gold;
  var currentStake = parseInt($("#CasinoStake").text, 10);
  if (
    isNaN(currentStake) ||
    currentStake < casinoStakeMinimum ||
    currentStake > event.gold
  ) {
    $("#CasinoStake").text = String(Math.min(event.default_stake, event.gold));
  }
  UpdateCasinoSpinButton();
  if (!casinoWaiting) {
    $("#CasinoResult").text = "Нажмите, чтобы запустить барабаны.";
  }

  if (event.spinning && !casinoAnimating) {
    casinoWaiting = true;
    casinoAnimating = true;
    casinoOutcome = null;
    $("#CasinoSpinButton").enabled = false;
    $("#CasinoWindow").AddClass("Spinning");
    $("#CasinoResult").text = "Барабаны вращаются...";
    AnimateCasinoReels();
    casinoAnimationTimeout = $.Schedule(2.4, function () {
      casinoAnimationTimeout = null;
      casinoAnimating = false;
      if (casinoOutcome) FinishCasinoAnimation();
      else $("#CasinoWindow").RemoveClass("Spinning");
    });
    casinoSpinTimeout = $.Schedule(8, function () {
      casinoSpinTimeout = null;
      if (!casinoWaiting) return;
      casinoWaiting = false;
      casinoOutcome = { error: "Нет ответа от автомата. Попробуйте ещё раз." };
      FinishCasinoAnimation();
    });
  }
  $("#CasinoPanel").AddClass("Visible");
}

function UpdateCasinoSpinButton() {
  var stake = parseInt($("#CasinoStake").text, 10);
  var gold = parseInt($("#CasinoBalance").text.replace(/[^0-9]/g, ""), 10);
  $("#CasinoSpinButton").enabled =
    activeCasinoMachine >= 0 &&
    !casinoWaiting &&
    !casinoAnimating &&
    !isNaN(stake) &&
    stake >= casinoStakeMinimum &&
    !isNaN(gold) &&
    stake <= gold;
}

function OnCasinoSpin() {
  var stake = parseInt($("#CasinoStake").text, 10);
  if (
    activeCasinoMachine < 0 ||
    casinoWaiting ||
    casinoAnimating ||
    isNaN(stake) ||
    stake < casinoStakeMinimum
  )
    return;
  casinoWaiting = true;
  casinoAnimating = true;
  casinoOutcome = null;
  $("#CasinoSpinButton").enabled = false;
  $("#CasinoWindow").RemoveClass("Win");
  $("#CasinoWindow").RemoveClass("Jackpot");
  $("#CasinoWindow").AddClass("Spinning");
  $("#CasinoResult").text = "Барабаны вращаются...";
  UpdateCasinoSpinButton();
  AnimateCasinoReels();
  if (casinoAnimationTimeout !== null) {
    $.CancelScheduled(casinoAnimationTimeout);
  }
  casinoAnimationTimeout = $.Schedule(2.4, function () {
    casinoAnimationTimeout = null;
    casinoAnimating = false;
    if (casinoOutcome) {
      FinishCasinoAnimation();
    } else {
      $("#CasinoWindow").RemoveClass("Spinning");
    }
  });
  GameEvents.SendCustomGameEventToServer("osc_casino_spin", {
    machine_entindex: activeCasinoMachine,
    stake: stake,
  });

  if (casinoSpinTimeout !== null) {
    $.CancelScheduled(casinoSpinTimeout);
  }
  casinoSpinTimeout = $.Schedule(8, function () {
    casinoSpinTimeout = null;
    if (!casinoWaiting) return;
    casinoWaiting = false;
    casinoOutcome = { error: "Нет ответа от автомата. Попробуйте ещё раз." };
    FinishCasinoAnimation();
  });
}

function OnCasinoResult(event) {
  if (casinoSpinTimeout !== null) {
    $.CancelScheduled(casinoSpinTimeout);
    casinoSpinTimeout = null;
  }

  casinoWaiting = false;
  if (event.gold !== undefined) {
    $("#CasinoBalance").text = "Золото: " + event.gold;
  }
  UpdateCasinoSpinButton();

  if (event.error) {
    casinoOutcome = { error: event.error };
    if (!casinoAnimating) FinishCasinoAnimation();
    return;
  }

  casinoOutcome = event;
  if (!casinoAnimating) {
    FinishCasinoAnimation();
  }
}

function AnimateCasinoReels() {
  if (!casinoAnimating) return;
  for (var i = 1; i <= 3; i++) {
    $("#CasinoReel" + i).text =
      casinoSymbols[Math.floor(Math.random() * casinoSymbols.length)];
  }
  $.Schedule(0.09, AnimateCasinoReels);
}

function FinishCasinoAnimation() {
  casinoAnimating = false;
  if (casinoAnimationTimeout !== null) {
    $.CancelScheduled(casinoAnimationTimeout);
    casinoAnimationTimeout = null;
  }

  $("#CasinoWindow").RemoveClass("Spinning");
  if (!casinoOutcome) return;

  if (casinoOutcome.error) {
    $("#CasinoResult").text = casinoOutcome.error;
    UpdateCasinoSpinButton();
    return;
  }

  var symbolLabels = {
    circle: "●",
    diamond: "♦",
    star: "★",
    seven: "7",
  };
  var symbols = [
    symbolLabels[casinoOutcome.reel1] || "●",
    symbolLabels[casinoOutcome.reel2] || "♦",
    symbolLabels[casinoOutcome.reel3] || "★",
  ];
  for (var i = 1; i <= 3; i++) {
    $("#CasinoReel" + i).text = symbols[i - 1];
  }

  var payout = casinoOutcome.payout;
  if (payout > 0) {
    $("#CasinoWindow").AddClass(payout >= 2500 ? "Jackpot" : "Win");
    Game.EmitSound("General.Coins");
  }

  var net =
    casinoOutcome.net > 0 ? "+" + casinoOutcome.net : String(casinoOutcome.net);
  $("#CasinoResult").text =
    payout > 0
      ? "Выплата: " + payout + " золота. Чистый итог: " + net
      : "Нет тройки. Ставка потеряна: " + casinoOutcome.stake + " золота.";
  UpdateCasinoSpinButton();
}

function CloseCasino() {
  casinoSelectionSuppressed = false;
  if (activeCasinoMachine >= 0 && Game.GetSelectedEntities) {
    var selected = Game.GetSelectedEntities();
    if (selected) {
      for (var i = 0; i < selected.length; i++) {
        if (selected[i] === activeCasinoMachine) {
          casinoSelectionSuppressed = true;
          break;
        }
      }
    }
  }
  activeCasinoMachine = -1;
  casinoWaiting = false;
  casinoAnimating = false;
  casinoOutcome = null;
  if (casinoSpinTimeout !== null) {
    $.CancelScheduled(casinoSpinTimeout);
    casinoSpinTimeout = null;
  }
  if (casinoAnimationTimeout !== null) {
    $.CancelScheduled(casinoAnimationTimeout);
    casinoAnimationTimeout = null;
  }
  $("#CasinoWindow").RemoveClass("Spinning");
  $("#CasinoPanel").RemoveClass("Visible");
}

function OnCasinoClosed(event) {
  if (
    event.machine_entindex !== undefined &&
    activeCasinoMachine !== event.machine_entindex
  )
    return;
  activeCasinoMachine = -1;
  casinoWaiting = false;
  casinoAnimating = false;
  casinoOutcome = null;
  if (casinoSpinTimeout !== null) {
    $.CancelScheduled(casinoSpinTimeout);
    casinoSpinTimeout = null;
  }
  if (casinoAnimationTimeout !== null) {
    $.CancelScheduled(casinoAnimationTimeout);
    casinoAnimationTimeout = null;
  }
  CloseCasino();
  $("#CasinoResult").text = "Автомат исчез.";
}

function OnCasinoStakeChanged() {
  UpdateCasinoSpinButton();
}

function CheckSelectedCasinoMachine() {
  if (Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_POST_GAME) return;

  if (Game.GetSelectedEntities) {
    var selected = Game.GetSelectedEntities();
    var selectedMachine = -1;
    if (selected) {
      for (var i = 0; i < selected.length; i++) {
        if (
          Entities.GetUnitName(selected[i]) === "npc_osc_casino_test_object"
        ) {
          selectedMachine = selected[i];
          break;
        }
      }
    }

    if (selectedMachine < 0) {
      casinoSelectionSuppressed = false;
    } else if (
      selectedMachine !== lastSelectedCasinoMachine &&
      !casinoSelectionSuppressed
    ) {
      GameEvents.SendCustomGameEventToServer("osc_casino_reopen", {
        machine_entindex: selectedMachine,
      });
    }
    lastSelectedCasinoMachine = selectedMachine;
  }

  $.Schedule(0.2, CheckSelectedCasinoMachine);
}

(function () {
  GameEvents.Subscribe("osc_ability_changed", OnAbilityChanged);
  GameEvents.Subscribe("osc_casino_open", OnCasinoOpen);
  GameEvents.Subscribe("osc_casino_result", OnCasinoResult);
  GameEvents.Subscribe("osc_casino_closed", OnCasinoClosed);
  $("#CasinoStake").SetPanelEvent("ontextentrychange", OnCasinoStakeChanged);
  CheckSelectedCasinoMachine();
  UpdateTimer();
  UpdateChaosRound();
})();
