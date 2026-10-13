"use strict";

var OSC = OSC || {};

// Пустая строка = без звука. Имена подберите в Asset Browser.
OSC.Sounds = {
  abilityChanged: "",
  chaosWarning: "",
  chaosStart: "",
  reelStop: "",
  casinoWin: "General.Coins",
  casinoJackpot: "General.Coins",

  teamPick: "ui_team_select_pick_team",
  teamShuffle: "ui_team_select_shuffle",
  teamAutoAssign: "ui_team_select_auto_assign",
  teamLockStart: "ui_team_select_lock_and_start",
  teamCancel: "ui_team_select_cancel",
};

OSC.Util = {
  FormatTime: function (seconds) {
    seconds = Math.max(0, Math.ceil(seconds));
    var m = Math.floor(seconds / 60);
    var s = seconds % 60;
    return m + ":" + (s < 10 ? "0" : "") + s;
  },

  PlaySound: function (name) {
    if (name) Game.EmitSound(name);
  },

  IsPostGame: function () {
    return Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_POST_GAME;
  },

  // Вызывает fn сразу и затем каждые interval секунд, пока fn не вернёт false.
  Loop: function (interval, fn) {
    (function tick() {
      if (fn() === false) return;
      $.Schedule(interval, tick);
    })();
  },
};

// Подсказки об отказе (казино, «Якорь» и др.): сервер шлёт osc_hud_error с
// ключом локализации, показываем его штатной красной строкой Dota над панелью
// способностей (со звуком ошибки)
OSC.HudError = (function () {
  function OnHudError(event) {
    if (!event || !event.message) return;
    GameEvents.SendEventClientSide("dota_hud_error_message", {
      splitscreenplayer: 0,
      reason: 80,
      message: "#" + event.message,
    });
  }

  function Init() {
    GameEvents.Subscribe("osc_hud_error", OnHudError);
  }

  return { Init: Init };
})();
