namespace OSC {
  // Пустая строка = без звука. Имена подберите в Asset Browser.
  export const Sounds: Record<string, string> = {
    abilityChanged: "",
    legendaryAbility: "DOTA_Item.Refresher.Activate", // своя легендарная способность
    chaosWarning: "",
    chaosStart: "",
    reelStop: "",
    casinoWin: "General.Coins",
    casinoJackpot: "General.Coins",
    shopBuy: "General.Buy", // покупка в Хаос-лавке

    teamPick: "ui_team_select_pick_team",
    teamShuffle: "ui_team_select_shuffle",
    teamLockStart: "ui_team_select_lock_and_start",
    teamCancel: "ui_team_select_cancel",
  };

  export const Util = {
    FormatTime: function (seconds: number) {
      seconds = Math.max(0, Math.ceil(seconds));
      var m = Math.floor(seconds / 60);
      var s = seconds % 60;
      return m + ":" + (s < 10 ? "0" : "") + s;
    },

    PlaySound: function (name: string) {
      if (name) Game.EmitSound(name);
    },

    IsPostGame: function () {
      return Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_POST_GAME;
    },

    // Вызывает fn сразу и затем каждые interval секунд, пока fn не вернёт false.
    Loop: function (interval: number, fn: () => boolean | void) {
      (function tick() {
        if (fn() === false) return;
        $.Schedule(interval, tick);
      })();
    },

    // Lua-массив приходит объектом { "1": ..., "2": ... } -> массив по порядку ключей
    LuaArray: function <T>(table: { [key: number]: T } | null | undefined): T[] {
      if (!table) return [];
      return Object.keys(table)
        .sort(function (a, b) {
          return Number(a) - Number(b);
        })
        .map(function (key) {
          return table[Number(key)];
        });
    },

    // Варианты способностей с сервера (выбор из трёх, сфера хаоса); пустые имена отбрасываются
    AbilityOptions: function (
      raw: { [key: number]: Partial<OSCAbilityOption> } | null | undefined,
    ): OSCAbilityOption[] {
      return Util.LuaArray(raw)
        .map(function (option) {
          option = option || {};
          return {
            name: String(option.name || ""),
            label: String(option.label || ""),
            rarity: String(option.rarity || "common"),
          };
        })
        .filter(function (option) {
          return option.name !== "";
        });
    },

    // Текст ключа локализации (token с "#"); если ключа нет — fallback.
    // panel — откуда брать dialog variables ({d:...}, {s:...})
    LocalizeOr: function (token: string, fallback: string, panel?: PanelBase) {
      var text = panel ? $.Localize(token, panel) : $.Localize(token);
      return text && text !== token ? text : fallback;
    },

    // Имя способности из локализации Dota; если ключа нет — подпись из пула
    AbilityName: function (name: string, label: string) {
      return Util.LocalizeOr("#DOTA_Tooltip_Ability_" + name, label || name);
    },

    // Строка CSS-классов из частей; ложные части пропускаются:
    // Classes("Card", picked && "Picked") -> "Card" | "Card Picked"
    Classes: function (...parts: (string | false | null | undefined)[]) {
      return parts.filter(Boolean).join(" ");
    },

    // Отменяет отложенный вызов, если он есть; возвращает null для сброса
    // переменной: handle = OSC.Util.Unschedule(handle)
    Unschedule: function (handle: ScheduleID | null): null {
      if (handle !== null) $.CancelScheduled(handle);
      return null;
    },
  };

  type OSCState = CustomNetTableDeclarations["osc_state"];

  export const Net = {
    // fn(значение) сразу (переподключение, поздняя загрузка HUD) и при каждом
    // изменении ключа osc_state. key-функция — для ключей, зависящих от игрока
    // или команды: они читаются заново на каждое изменение.
    Watch: function <K extends keyof OSCState>(
      key: K | (() => K),
      fn: (value: NetworkedData<OSCState[K]> | null) => void,
    ) {
      function current() {
        return typeof key === "function" ? key() : key;
      }
      CustomNetTables.SubscribeNetTableListener("osc_state", function (tableName, changed, value) {
        if (changed === current()) fn(value as NetworkedData<OSCState[K]>);
      });
      fn(CustomNetTables.GetTableValue("osc_state", current()));
    },
  };

  // Подсказки об отказе (казино, «Якорь» и др.): сервер шлёт osc_hud_error с
  // ключом локализации, показываем его штатной красной строкой Dota над панелью
  // способностей (со звуком ошибки)
  export const HudError = (function () {
    function OnHudError(event: NetworkedData<CustomGameEventDeclarations["osc_hud_error"]>) {
      if (!event || !event.message) return;
      GameEvents.SendEventClientSide("dota_hud_error_message", {
        splitscreenplayer: 0,
        reason: 80,
        message: "#" + event.message,
        // формат, который понимает клиент Dota; в panorama-types он описан иначе
      } as unknown as DotaHudErrorMessageEvent);
    }

    function Init() {
      GameEvents.Subscribe("osc_hud_error", OnHudError);
    }

    return { Init: Init };
  })();
}
