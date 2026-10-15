namespace OSC.Help {
  // Справка: данные и кирпичики страниц (иконка, текст, факты, таблица, карточки,
  // шаги). Страницы — osc_help_pages.tsx, окно — osc_help.tsx.
  export type OSCState = CustomNetTableDeclarations["osc_state"];
  export type HelpTable = Partial<NetworkedData<OSCHelpData>>;
  export type HelpSection<K extends keyof OSCHelpData> = Partial<NetworkedData<OSCHelpData[K]>>;
  // { item } | { ability } | { image: класс с background-image в CSS }
  export type HelpIcon = { item?: string; ability?: string; image?: string };
  export type HelpStat = { icon: string; value: string | number | undefined; tooltip: string };
  export type HelpCard = { icon?: HelpIcon; title: string; text: string; stats?: HelpStat[] };
  export type HelpRow = { icon?: HelpIcon; cells: string[] };
  export type HelpStep = { value?: string; icon?: string; title: string; caption: string };

  export const BORDER_CLASS: Record<string, string> = {
    common: "HelpImgCommon",
    rare: "HelpImgRare",
    legendary: "HelpImgLegendary",
  };

  // ================= Данные =================

  export function Table<K extends keyof OSCState>(key: K) {
    return (CustomNetTables.GetTableValue("osc_state", key) || {}) as Partial<
      NetworkedData<OSCState[K]>
    >;
  }

  // Локализация с переменными {s:имя}: $.Localize без панели вырезает их,
  // поэтому значения кладём dialog variables на контейнер справки из разметки
  export function L(key: string, vars?: Record<string, unknown>) {
    var context = $("#HelpRoot");
    Object.keys(vars || {}).forEach(function (name) {
      context.SetDialogVariable(name, String(vars![name]));
    });
    return $.Localize("#" + key, context);
  }

  export function ItemName(name: string) {
    return $.Localize("#DOTA_Tooltip_ability_" + name);
  }

  // ================= Кирпичики страницы =================

  export function Icon(props: { icon: HelpIcon; className: string }) {
    var icon = props.icon;
    if (icon.item) {
      return <DOTAItemImage className={props.className} itemname={icon.item} hittest={false} />;
    }
    if (icon.ability) {
      return (
        <DOTAAbilityImage className={props.className} abilityname={icon.ability} hittest={false} />
      );
    }
    return <Panel className={props.className + " " + icon.image} hittest={false} />;
  }

  export function Text(props: { k: string; vars?: Record<string, unknown> }) {
    return <Label className="HelpText" text={L(props.k, props.vars)} />;
  }

  export function Subheading(props: { k: string }) {
    return <Label className="HelpSubheading" text={L(props.k)} />;
  }

  // value — число; text — значение словом, а не числом
  export function Facts(props: {
    items: { icon?: string; value: unknown; caption: string; text?: boolean }[];
  }) {
    return (
      <Panel className="HelpFacts">
        {props.items.map(function (fact) {
          return (
            <Panel key={fact.caption} className="HelpFact">
              <Panel className="HelpFactHead">
                {fact.icon && <Panel className={"HelpFactIcon " + fact.icon} />}
                <Label
                  className={OSC.Util.Classes("HelpFactValue", fact.text && "Text")}
                  text={String(fact.value)}
                />
              </Panel>
              <Label className="HelpFactCaption" text={L(fact.caption)} />
            </Panel>
          );
        })}
      </Panel>
    );
  }

  // Слоты героя: значок способности в рамке редкости и пояснение
  export function Slots(props: {
    slots: { ability: string; rarity: string; title: string; text: string }[];
  }) {
    return (
      <Panel className="HelpSlots">
        {props.slots.map(function (slot) {
          return (
            <Panel key={slot.ability} className="HelpSlot">
              <Panel className={"HelpSlotFrame " + BORDER_CLASS[slot.rarity]}>
                <DOTAAbilityImage className="HelpSlotIcon" abilityname={slot.ability} />
              </Panel>
              <Panel className="HelpSlotInfo">
                <Label className="HelpCardTitle" text={slot.title} />
                <Label className="HelpCardText" text={slot.text} />
              </Panel>
            </Panel>
          );
        })}
      </Panel>
    );
  }

  // header — ключи заголовков; значок строки — в первой ячейке
  export function Grid(props: { header: string[]; rows: HelpRow[] }) {
    return (
      <Panel className="HelpTable">
        <Panel className="HelpRow Header">
          {props.header.map(function (key) {
            return <Label key={key} className="HelpCell" text={L(key)} />;
          })}
        </Panel>
        {props.rows.map(function (row, rowIndex) {
          return (
            <Panel key={rowIndex} className="HelpRow">
              {row.cells.map(function (text, index) {
                return (
                  <Panel key={index} className="HelpCellBox">
                    {index === 0 && row.icon && <Icon icon={row.icon} className="HelpCellIcon" />}
                    <Label className="HelpCell" text={text} />
                  </Panel>
                );
              })}
            </Panel>
          );
        })}
      </Panel>
    );
  }

  // Строка «значок + число» под описанием, как у способностей героя
  export function Stats(props: { stats: HelpStat[] }) {
    return (
      <Panel className="HelpStats">
        {props.stats.map(function (stat) {
          return (
            <Panel
              key={stat.icon}
              className="HelpStat"
              {...OSC.TextTooltip(function () {
                return stat.tooltip;
              })}
            >
              <Panel className={"HelpStatIcon " + stat.icon} />
              <Label text={String(stat.value)} />
            </Panel>
          );
        })}
      </Panel>
    );
  }

  // columns — 2 или 3
  export function Cards(props: { cards: HelpCard[]; columns?: number }) {
    return (
      <Panel className={"HelpCards Columns" + (props.columns || 2)}>
        {props.cards.map(function (card, index) {
          return (
            <Panel key={index} className="HelpCard">
              <Panel className="HelpCardHead">
                {card.icon && <Icon icon={card.icon} className="HelpCardIcon" />}
                <Label className="HelpCardTitle" text={card.title} />
              </Panel>
              <Label className="HelpCardText" text={card.text} />
              {card.stats && <Stats stats={card.stats} />}
            </Panel>
          );
        })}
      </Panel>
    );
  }

  // Один цикл ротации шагами со стрелками
  export function Steps(props: { steps: HelpStep[] }) {
    var children: JSX.Element[] = [];
    props.steps.forEach(function (step, index) {
      if (index > 0) {
        children.push(<Label key={"arrow" + index} className="HelpStepArrow" text="→" />);
      }
      children.push(
        <Panel key={index} className="HelpStep">
          <Panel className="HelpStepHead">
            <Label className="HelpStepNumber" text={String(index + 1)} />
            {step.icon && <Panel className={"HelpStepIcon " + step.icon} />}
            {step.value !== undefined && <Label className="HelpStepValue" text={step.value} />}
          </Panel>
          <Label className="HelpStepTitle" text={step.title} />
          <Label className="HelpStepCaption" text={step.caption} />
        </Panel>,
      );
    });
    return <Panel className="HelpSteps">{children}</Panel>;
  }
}
