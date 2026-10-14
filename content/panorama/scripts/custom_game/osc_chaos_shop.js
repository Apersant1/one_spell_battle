"use strict";

var OSC = OSC || {};

// Хаос-лавка: кнопка в правом нижнем углу и панель с предметами режима.
// Товары — osc_state/shop_<team> = { items = { [i] = { name, cost, stock, max } } }
// (stock = max = -1 — без лимита). Покупку решает сервер: osc_shop_buy { item },
// ответ osc_shop_result { ok, item, error }; ошибки показывает OSC.HudError.
OSC.ChaosShop = (function () {
  var GOLD_POLL = 0.25; // как часто обновлять кнопки, пока панель открыта

  var rows = []; // { item, button } — для обновления кнопок по золоту
  var open = false;
  var openToken = 0; // меняется при каждом открытии, чтобы не плодить опросы

  // Команду читаем каждый раз: после перемешивания команд она могла смениться
  function NetTableKey() {
    return "shop_" + Players.GetTeam(Players.GetLocalPlayer());
  }

  // Lua-массив приходит объектом { "1": ..., "2": ... }
  function ToList(table) {
    if (!table) return [];
    return Object.keys(table)
      .sort(function (a, b) {
        return Number(a) - Number(b);
      })
      .map(function (key) {
        return table[key];
      });
  }

  // Только подсказка: золото и остаток проверяет сервер
  function UpdateButtons() {
    var gold = Players.GetGold(Players.GetLocalPlayer());
    rows.forEach(function (row) {
      row.button.enabled =
        gold >= Number(row.item.cost) && Number(row.item.stock) !== 0;
    });
  }

  function AddLabel(parent, classes, text) {
    var label = $.CreatePanel("Label", parent, "");
    classes.forEach(function (name) {
      label.AddClass(name);
    });
    label.text = text;
    return label;
  }

  function BuildRow(list, item) {
    var row = $.CreatePanel("Panel", list, "");
    row.AddClass("ChaosShopRow");

    // Стандартная подсказка предмета Dota при наведении
    var image = $.CreatePanel("DOTAItemImage", row, "");
    image.itemname = item.name;
    image.SetPanelEvent("onmouseover", function () {
      $.DispatchEvent("DOTAShowAbilityTooltip", image, item.name);
    });
    image.SetPanelEvent("onmouseout", function () {
      $.DispatchEvent("DOTAHideAbilityTooltip", image);
    });

    var info = $.CreatePanel("Panel", row, "");
    info.AddClass("ChaosShopInfo");
    AddLabel(info, ["OSCTextBody", "OSCBold"], $.Localize("#DOTA_Tooltip_ability_" + item.name));
    AddLabel(info, ["OSCTextSmall", "OSCGold"], String(item.cost));
    if (Number(item.max) >= 0) {
      var stock = AddLabel(info, ["OSCTextSmall", "OSCMuted"], "");
      stock.SetDialogVariableInt("stock", Number(item.stock));
      stock.SetDialogVariableInt("max", Number(item.max));
      stock.text = $.Localize("#osc_shop_stock", stock);
    }

    var button = $.CreatePanel("Button", row, "");
    button.AddClass("OSCButton");
    button.AddClass("OSCButtonPrimary");
    button.AddClass("ChaosShopBuy");
    AddLabel(button, [], $.Localize("#osc_shop_buy_button"));
    button.SetPanelEvent("onactivate", function () {
      GameEvents.SendCustomGameEventToServer("osc_shop_buy", { item: item.name });
    });
    rows.push({ item: item, button: button });
  }

  function Refresh() {
    // Сервер публикует таблицы обеих команд, если лавка включена
    var enabled = !!CustomNetTables.GetTableValue(
      "osc_state",
      "shop_" + DOTATeam_t.DOTA_TEAM_GOODGUYS
    );
    $("#ChaosShopButton").SetHasClass("Hidden", !enabled);
    if (!enabled && open) SetOpen(false);

    var data = CustomNetTables.GetTableValue("osc_state", NetTableKey());
    var list = $("#ChaosShopItems");
    list.RemoveAndDeleteChildren();
    rows = [];
    ToList(data && data.items).forEach(function (item) {
      BuildRow(list, item);
    });
    UpdateButtons();
  }

  function SetOpen(show) {
    open = show;
    $("#ChaosShopPanel").SetHasClass("Visible", show);
    if (!show) return;
    Refresh();
    var token = ++openToken;
    OSC.Util.Loop(GOLD_POLL, function () {
      if (!open || token !== openToken || OSC.Util.IsPostGame()) return false;
      UpdateButtons();
    });
  }

  function Toggle() {
    SetOpen(!open);
  }

  function Close() {
    SetOpen(false);
  }

  function OnResult(event) {
    if (event && Number(event.ok) === 1) OSC.Util.PlaySound(OSC.Sounds.shopBuy);
  }

  function OnNetTableChanged(tableName, key) {
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
