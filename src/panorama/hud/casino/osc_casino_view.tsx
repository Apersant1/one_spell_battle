namespace OSC.Casino {
  // Казино: части окна. Всё, что им нужно, приходит через props; собирает их
  // CasinoWindow в osc_casino.tsx.
  var TITLE_ARC = -6; // на сколько px концы заголовка ниже середины (дуга вниз)
  var TITLE_LETTER_WIDTH = 13; // примерная ширина буквы — для наклона по касательной
  // Поле ставки (osc_hud.css, #CasinoStake): монета слева, место под цифры справа
  var STAKE_COIN_WIDTH = 26;
  var STAKE_TEXT_AREA = 103;
  var STAKE_DIGIT_WIDTH = 10;

  // Panorama не пускает текст по кривой — заголовок собран из букв: каждая
  // опущена по параболе и повёрнута по касательной к ней
  export function Title() {
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
  export function Paytable(props: {
    payouts: NetworkedData<OSCCasinoOutcome>[];
    hitSymbol: string | null;
  }) {
    var top = Math.max.apply(
      null,
      props.payouts.map(function (o) {
        return o.multiplier;
      }),
    );
    return (
      <Panel id="CasinoPaytable">
        {props.payouts.map(function (o) {
          return (
            <Panel
              key={o.symbol}
              className={OSC.Util.Classes(
                "CasinoPayCell",
                o.multiplier === top && "Top",
                o.symbol === props.hitSymbol && "Hit",
              )}
            >
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

  // Переключатель «золото / предметы»: иконки, ползунок под активной
  export function ModeSwitch(props: {
    mode: string;
    itemBets: boolean;
    itemsUnavailable: boolean;
    onToggle: () => void;
  }) {
    return (
      <Panel id="CasinoModeTabs" className={OSC.Util.Classes(!props.itemBets && "Hidden")}>
        <Button
          id="CasinoModeSwitch"
          className={OSC.Util.Classes(props.itemsUnavailable && "ItemsUnavailable")}
          onactivate={props.onToggle}
          {...OSC.TextTooltip(function () {
            if (props.mode === "gold" && props.itemsUnavailable) {
              return $.Localize("#osc_casino_items_empty");
            }
            return $.Localize(
              props.mode === "items" ? "#osc_casino_mode_items" : "#osc_casino_mode_gold",
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
    );
  }

  // Слот инвентаря: свой продаваемый предмет — кнопка ставки; чужой или
  // непродаваемый — серый с подсказкой почему; пустой — тёмная ячейка
  function Slot(props: {
    slot: InventorySlot;
    selected: boolean;
    onSelect: (item: ItemEntityIndex) => void;
  }) {
    var slot = props.slot;
    if (slot.item === -1) return <Button className="CasinoItem Empty" />;
    var item = slot.item;
    var image = <DOTAItemImage itemname={slot.name} hittest={false} />;
    if (slot.reason) {
      return (
        <Button
          className="CasinoItem Locked"
          {...OSC.TextTooltip(function () {
            return $.Localize("#" + slot.reason);
          })}
        >
          {image}
        </Button>
      );
    }
    return (
      <Button
        className={OSC.Util.Classes("CasinoItem", props.selected && "Selected")}
        onactivate={function () {
          props.onSelect(item);
        }}
      >
        {image}
        <Label className="CasinoItemPrice" text={String(slot.value)} />
      </Button>
    );
  }

  // Режим «Предметы»: шесть слотов инвентаря и сумма ставки (красная,
  // если меньше минимума)
  export function ItemsRow(props: {
    slots: InventorySlot[];
    selected: ItemEntityIndex[];
    value: number;
    minimum: number;
    onSelect: (item: ItemEntityIndex) => void;
  }) {
    return (
      <Panel id="CasinoItemsRow">
        <Panel id="CasinoItems">
          {props.slots.map(function (slot, i) {
            return (
              <Slot
                key={i + ":" + slot.item}
                slot={slot}
                selected={slot.item !== -1 && props.selected.indexOf(slot.item) >= 0}
                onSelect={props.onSelect}
              />
            );
          })}
        </Panel>
        <Label
          id="CasinoItemsTotal"
          className={OSC.Util.Classes(
            props.selected.length > 0 && props.value < props.minimum && "Low",
          )}
          text={String(props.value)}
          {...OSC.TextTooltip(function () {
            return OSC.Localized("osc_casino_items_hint", { min: props.minimum })(
              $("#CasinoItemsTotal") as LabelPanel,
            );
          })}
        />
      </Panel>
    );
  }

  // Поле ставки золотом с кнопками −/+; они гаснут на краях диапазона
  export function StakeRow(props: {
    text: string;
    busy: boolean;
    minimum: number;
    gold: number;
    onStep: (direction: number) => void;
    onChange: (text: string) => void;
  }) {
    var stake = parseInt(props.text, 10);
    // TextEntry не центрирует текст (text-align не действует) — сдвигаем его
    // отступом слева по числу символов.
    // shortcut: ширина цифры подобрана на глаз (~10px при 18px); если шрифт поля
    // сменится, подобрать STAKE_DIGIT_WIDTH заново
    var free = STAKE_TEXT_AREA - props.text.length * STAKE_DIGIT_WIDTH;
    return (
      <Panel id="CasinoStakeRow">
        <Button
          id="CasinoStakeMinus"
          className="CasinoStakeStep"
          enabled={!props.busy && (isNaN(stake) || stake > props.minimum)}
          onactivate={function () {
            props.onStep(-1);
          }}
        >
          <Label text={$.Localize("#osc_casino_stake_minus")} />
        </Button>
        <TextEntry
          id="CasinoStake"
          text={props.text}
          maxchars={8}
          style={{ paddingLeft: STAKE_COIN_WIDTH + Math.max(0, Math.floor(free / 2)) + "px" }}
          ontextentrychange={function (entry) {
            props.onChange(entry.text);
          }}
        />
        <Button
          id="CasinoStakePlus"
          className="CasinoStakeStep"
          enabled={!props.busy && (isNaN(stake) || isNaN(props.gold) || stake < props.gold)}
          onactivate={function () {
            props.onStep(1);
          }}
        >
          <Label text={$.Localize("#osc_casino_stake_plus")} />
        </Button>
      </Panel>
    );
  }
}
