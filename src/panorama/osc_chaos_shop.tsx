namespace OSC {
  // Хаос-лавка (React): кнопка в правом нижнем углу и панель с предметами режима.
  // Товары — osc_state/shop_<team> = { items = { [i] = { name, cost, stock, max } } }
  // (stock = max = -1 — без лимита). Покупку решает сервер: osc_shop_buy { item },
  // ответ osc_shop_result { ok, item, error }; ошибки показывает OSC.HudError.
  export const ChaosShop = (function () {
    var GOLD_POLL = 0.25; // как часто обновлять подсветку плиток, пока панель открыта

    // Команду читаем на каждом рендере: после перемешивания команд она могла смениться
    function NetTableKey(): `shop_${number}` {
      return `shop_${Players.GetTeam(Players.GetLocalPlayer())}`;
    }

    function LocalGold() {
      return Players.GetGold(Players.GetLocalPlayer());
    }

    // Плитка как в стандартном магазине: иконка, остаток в углу, цена под
    // ней; название и описание — в подсказке предмета Dota. Покупка — любым кликом.
    // Подсветка только для вида: золото и остаток проверяет сервер, клик по
    // недоступному товару вернёт его ошибку
    function Tile(props: { item: NetworkedData<OSCShopItem>; gold: number }) {
      var item = props.item;

      function Buy() {
        GameEvents.SendCustomGameEventToServer("osc_shop_buy", { item: item.name });
      }

      return (
        <Button
          className={OSC.Util.Classes(
            "ChaosShopTile",
            props.gold < Number(item.cost) && "Unaffordable",
            Number(item.stock) === 0 && "SoldOut",
          )}
          onactivate={Buy}
          oncontextmenu={Buy}
          {...OSC.AbilityTooltip(item.name)}
        >
          <Panel className="ChaosShopIcon">
            <DOTAItemImage itemname={item.name} hittest={false} />
            {Number(item.max) >= 0 && (
              <Label className="ChaosShopStock" text={String(item.stock)} />
            )}
          </Panel>
          <Label className="ChaosShopCost" text={String(item.cost)} />
        </Button>
      );
    }

    function Shop() {
      var [open, setOpen] = React.useState(false);
      // Сервер публикует таблицы обеих команд, если лавка включена
      var enabled = !!ReactPanorama.useNetTableKey(
        "osc_state",
        `shop_${DOTATeam_t.DOTA_TEAM_GOODGUYS}`,
      );
      var data = ReactPanorama.useNetTableKey("osc_state", NetTableKey());
      var shown = open && enabled;
      var gold = OSC.usePolled(LocalGold, GOLD_POLL, shown);

      React.useEffect(
        function () {
          if (!enabled) setOpen(false);
        },
        [enabled],
      );
      ReactPanorama.useGameEvent(
        "osc_shop_result",
        function (event) {
          if (event && Number(event.ok) === 1) OSC.Util.PlaySound(OSC.Sounds.shopBuy);
        },
        [],
      );

      return (
        <>
          <Button
            id="ChaosShopButton"
            className={OSC.Util.Classes("OSCButton OSCButtonPrimary", !enabled && "Hidden")}
            onactivate={function () {
              setOpen(!open);
            }}
          >
            <Label text={$.Localize("#osc_shop_button")} />
          </Button>
          <Panel
            id="ChaosShopPanel"
            className={OSC.Util.Classes(shown && "Visible")}
            hittest={true}
          >
            <Button
              id="ChaosShopClose"
              className="OSCButton"
              onactivate={function () {
                setOpen(false);
              }}
            >
              <Label text={$.Localize("#osc_shop_close")} />
            </Button>
            <Label
              id="ChaosShopTitle"
              className="OSCTextTitle OSCChaosText"
              text={$.Localize("#osc_shop_title")}
            />
            <Panel id="ChaosShopItems">
              {OSC.Util.LuaArray(data && data.items).map(function (item) {
                return <Tile key={item.name} item={item} gold={gold} />;
              })}
            </Panel>
          </Panel>
        </>
      );
    }

    function Init() {
      ReactPanorama.render(<Shop />, $("#ChaosShopRoot"));
    }

    return { Init: Init };
  })();
}
