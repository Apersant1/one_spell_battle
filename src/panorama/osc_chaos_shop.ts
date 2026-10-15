namespace OSC {
  // Хаос-лавка: кнопка в правом нижнем углу и панель с предметами режима.
  // Товары — osc_state/shop_<team> = { items = { [i] = { name, cost, stock, max } } }
  // (stock = max = -1 — без лимита). Покупку решает сервер: osc_shop_buy { item },
  // ответ osc_shop_result { ok, item, error }; ошибки показывает OSC.HudError.
  export const ChaosShop = (function () {
    var GOLD_POLL = 0.25; // как часто обновлять подсветку плиток, пока панель открыта

    var rows: { item: NetworkedData<OSCShopItem>; tile: Panel }[] = []; // { item, tile } — для подсветки плиток по золоту
    var open = false;
    var openToken = 0; // меняется при каждом открытии, чтобы не плодить опросы

    // Команду читаем каждый раз: после перемешивания команд она могла смениться
    function NetTableKey(): `shop_${number}` {
      return `shop_${Players.GetTeam(Players.GetLocalPlayer())}`;
    }

    // Lua-массив приходит объектом { "1": ..., "2": ... }
    function ToList<T>(table: { [key: number]: T } | null | undefined): T[] {
      if (!table) return [];
      return Object.keys(table)
        .sort(function (a, b) {
          return Number(a) - Number(b);
        })
        .map(function (key) {
          return table[Number(key)];
        });
    }

    // Только подсветка: золото и остаток проверяет сервер, клик по
    // недоступному товару вернёт его ошибку
    function UpdateTiles() {
      var gold = Players.GetGold(Players.GetLocalPlayer());
      rows.forEach(function (row) {
        row.tile.SetHasClass("Unaffordable", gold < Number(row.item.cost));
        row.tile.SetHasClass("SoldOut", Number(row.item.stock) === 0);
      });
    }

    // Плитка как в стандартном магазине: иконка, остаток в углу, цена под
    // ней; название и описание — в подсказке предмета Dota. Покупка — любым кликом
    function BuildTile(list: Panel, item: NetworkedData<OSCShopItem>) {
      var tile = $.CreatePanel("Button", list, "");
      tile.AddClass("ChaosShopTile");

      var icon = $.CreatePanel("Panel", tile, "");
      icon.AddClass("ChaosShopIcon");
      var image = $.CreatePanel("DOTAItemImage", icon, "");
      image.itemname = item.name;
      image.hittest = false;
      if (Number(item.max) >= 0) {
        var stock = $.CreatePanel("Label", icon, "");
        stock.AddClass("ChaosShopStock");
        stock.text = String(item.stock);
      }

      var cost = $.CreatePanel("Label", tile, "");
      cost.AddClass("ChaosShopCost");
      cost.text = String(item.cost);

      tile.SetPanelEvent("onmouseover", function () {
        $.DispatchEvent("DOTAShowAbilityTooltip", tile, item.name);
      });
      tile.SetPanelEvent("onmouseout", function () {
        $.DispatchEvent("DOTAHideAbilityTooltip", tile);
      });
      function Buy() {
        GameEvents.SendCustomGameEventToServer("osc_shop_buy", { item: item.name });
      }
      tile.SetPanelEvent("onactivate", Buy);
      tile.SetPanelEvent("oncontextmenu", Buy);
      rows.push({ item: item, tile: tile });
    }

    function Refresh() {
      // Сервер публикует таблицы обеих команд, если лавка включена
      var enabled = !!CustomNetTables.GetTableValue(
        "osc_state",
        `shop_${DOTATeam_t.DOTA_TEAM_GOODGUYS}`
      );
      $("#ChaosShopButton").SetHasClass("Hidden", !enabled);
      if (!enabled && open) SetOpen(false);

      var data = CustomNetTables.GetTableValue("osc_state", NetTableKey());
      var list = $("#ChaosShopItems");
      list.RemoveAndDeleteChildren();
      rows = [];
      ToList(data && data.items).forEach(function (item) {
        BuildTile(list, item);
      });
      UpdateTiles();
    }

    function SetOpen(show: boolean) {
      open = show;
      $("#ChaosShopPanel").SetHasClass("Visible", show);
      if (!show) return;
      Refresh();
      var token = ++openToken;
      OSC.Util.Loop(GOLD_POLL, function () {
        if (!open || token !== openToken || OSC.Util.IsPostGame()) return false;
        UpdateTiles();
      });
    }

    function Toggle() {
      SetOpen(!open);
    }

    function Close() {
      SetOpen(false);
    }

    function OnResult(event: NetworkedData<CustomGameEventDeclarations["osc_shop_result"]>) {
      if (event && Number(event.ok) === 1) OSC.Util.PlaySound(OSC.Sounds.shopBuy);
    }

    function OnNetTableChanged(tableName: string, key: string) {
      if (key.indexOf("shop_") === 0) Refresh();
    }

    function Init() {
      CustomNetTables.SubscribeNetTableListener("osc_state", OnNetTableChanged);
      GameEvents.Subscribe("osc_shop_result", OnResult);
      // Переподключение: таблицы могли прийти до загрузки HUD
      Refresh();
    }

    return {
      Init: Init,
      Toggle: Toggle, // вызывается из XML
      Close: Close, // вызывается из XML
    };
  })();
}
