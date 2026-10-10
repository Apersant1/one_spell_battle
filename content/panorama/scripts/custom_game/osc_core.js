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
