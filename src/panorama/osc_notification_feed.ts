namespace OSC {
  export const NotificationFeed = (function () {
    var MAX_ITEMS = 5;
    var LIFETIME = 6; // секунд на экране
    var FADE_OUT = 0.3; // совпадает с transition-duration у .OSCNotification

    var items: LabelPanel[] = [];

    // Значения с "#" в начале — ключи локализации
    function LocalizeValue(value: string | number, panel: Panel) {
      var text = String(value);
      return text.charAt(0) === "#" ? $.Localize(text, panel) : text;
    }
    // Ник игрока; если пустой (боты, локальный тест) — имя героя
    function ResolvePlayerName(playerID: PlayerID) {
      var name = Players.GetPlayerName(playerID);
      if (name) return name;
      var hero = Players.GetPlayerSelectedHero(playerID);
      return hero ? $.Localize("#" + hero) : "";
    }

    function RemoveItem(item: LabelPanel) {
      var index = items.indexOf(item);
      if (index >= 0) items.splice(index, 1);
      if (!item.IsValid()) return;
      item.RemoveClass("Shown");
      item.DeleteAsync(FADE_OUT);
    }

    function OnNotification(event: NetworkedData<CustomGameEventDeclarations["osc_notification"]>) {
      var feed = $("#NotificationFeed");
      var item = $.CreatePanel("Label", feed, "");
      item.AddClass("OSCNotification");
      item.AddClass("OSCTextBody");

      var params: Record<string, string | number> = event.params || {};
      for (var key in params) {
        item.SetDialogVariable(key, LocalizeValue(params[key], item));
      }
      if (params.player_id !== undefined) {
        item.SetDialogVariable(
          "player_name",
          ResolvePlayerName(Number(params.player_id) as PlayerID),
        );
      }
      item.text = $.Localize(event.token, item);
      if (event.color) item.style.color = event.color;

      items.push(item);
      while (items.length > MAX_ITEMS) RemoveItem(items[0]);

      $.Schedule(0.03, function () {
        if (item.IsValid()) item.AddClass("Shown");
      });
      $.Schedule(LIFETIME, function () {
        RemoveItem(item);
      });
    }

    function Init() {
      GameEvents.Subscribe("osc_notification", OnNotification);
    }

    return { Init: Init };
  })();
}
