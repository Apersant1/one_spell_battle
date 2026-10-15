namespace OSC {
  // Справка по правилам режима (React): кнопка «?» рядом с Хаос-лавкой открывает
  // панель с вкладками. Слева темы, справа страница выбранной. Числа текущего
  // матча — из net tables osc_state/help (osc/systems/help.lua), shop_<team>,
  // version; тексты — ключи osc_hud_help_* с переменными {s:имя}.
  type OSCState = CustomNetTableDeclarations["osc_state"];
  type HelpTable = Partial<NetworkedData<OSCHelpData>>;
  type HelpSection<K extends keyof OSCHelpData> = Partial<NetworkedData<OSCHelpData[K]>>;
  // { item } | { ability } | { image: класс с background-image в CSS }
  type HelpIcon = { item?: string; ability?: string; image?: string };
  type HelpStat = { icon: string; value: string | number | undefined; tooltip: string };
  type HelpCard = { icon?: HelpIcon; title: string; text: string; stats?: HelpStat[] };
  type HelpRow = { icon?: HelpIcon; cells: string[] };
  type HelpStep = { value?: string; icon?: string; title: string; caption: string };

  export const Help = (function () {
    var TOPICS: { id: string; icon: HelpIcon; page: (help: HelpTable) => JSX.Element }[] = [
      { id: "overview", icon: { image: "HelpImgChaos" }, page: OverviewPage },
      { id: "rotation", icon: { ability: "rubick_spell_steal" }, page: RotationPage },
      { id: "rarity", icon: { image: "HelpImgLegendary" }, page: RarityPage },
      { id: "anchor", icon: { item: "item_osc_anchor" }, page: AnchorPage },
      { id: "shop", icon: { item: "item_osc_ultimate_reroll" }, page: ShopPage },
      { id: "chaos", icon: { ability: "zuus_thundergods_wrath" }, page: ChaosPage },
      { id: "casino", icon: { image: "HelpImgSeven" }, page: CasinoPage },
      { id: "sphere", icon: { item: "item_osc_chaos_sphere" }, page: SpherePage },
      { id: "couriers", icon: { ability: "courier_burst" }, page: CouriersPage },
      { id: "summary", icon: { item: "item_aegis" }, page: SummaryPage },
    ];
    var RARITIES = ["common", "rare", "legendary"];
    var BORDER_CLASS: Record<string, string> = {
      common: "HelpImgCommon",
      rare: "HelpImgRare",
      legendary: "HelpImgLegendary",
    };
    var CASINO_CLASS: Record<string, string> = {
      circle: "HelpImgCircle",
      diamond: "HelpImgDiamond",
      star: "HelpImgStar",
      seven: "HelpImgSeven",
    };

    // ================= Данные =================

    function Table<K extends keyof OSCState>(key: K) {
      return (CustomNetTables.GetTableValue("osc_state", key) || {}) as Partial<
        NetworkedData<OSCState[K]>
      >;
    }

    // Локализация с переменными {s:имя}: $.Localize без панели вырезает их,
    // поэтому значения кладём dialog variables на контейнер справки из разметки
    function L(key: string, vars?: Record<string, unknown>) {
      var context = $("#HelpRoot");
      Object.keys(vars || {}).forEach(function (name) {
        context.SetDialogVariable(name, String(vars![name]));
      });
      return $.Localize("#" + key, context);
    }

    function ItemName(name: string) {
      return $.Localize("#DOTA_Tooltip_ability_" + name);
    }

    // ================= Кирпичики страницы =================

    function Icon(props: { icon: HelpIcon; className: string }) {
      var icon = props.icon;
      if (icon.item) {
        return <DOTAItemImage className={props.className} itemname={icon.item} hittest={false} />;
      }
      if (icon.ability) {
        return (
          <DOTAAbilityImage
            className={props.className}
            abilityname={icon.ability}
            hittest={false}
          />
        );
      }
      return <Panel className={props.className + " " + icon.image} hittest={false} />;
    }

    function Text(props: { k: string; vars?: Record<string, unknown> }) {
      return <Label className="HelpText" text={L(props.k, props.vars)} />;
    }

    function Subheading(props: { k: string }) {
      return <Label className="HelpSubheading" text={L(props.k)} />;
    }

    // value — число; text — значение словом, а не числом
    function Facts(props: {
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
    function Slots(props: {
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
    function Grid(props: { header: string[]; rows: HelpRow[] }) {
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
    function Stats(props: { stats: HelpStat[] }) {
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
    function Cards(props: { cards: HelpCard[]; columns?: number }) {
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
    function Steps(props: { steps: HelpStep[] }) {
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

    // ================= Страницы =================

    function OverviewPage(help: HelpTable) {
      var rotation: HelpSection<"rotation"> = help.rotation || {};
      var chaos: HelpSection<"chaos"> = help.chaos || {};
      var casino: HelpSection<"casino"> = help.casino || {};
      return (
        <>
          <Text k="osc_hud_help_overview_text" />
          <Slots
            slots={[
              {
                ability: "mirana_arrow",
                rarity: "rare",
                title: L("osc_hud_help_overview_slot_ability"),
                text: L("osc_hud_help_overview_slot_ability_text", {
                  interval: rotation.interval,
                }),
              },
              {
                ability: "zuus_thundergods_wrath",
                rarity: "legendary",
                title: L("osc_hud_help_overview_slot_ultimate"),
                text: L("osc_hud_help_overview_slot_ultimate_text"),
              },
            ]}
          />
          <Subheading k="osc_hud_help_overview_settings" />
          <Facts
            items={[
              {
                icon: "HelpStatCooldown",
                value: rotation.interval,
                caption: "osc_hud_help_fact_rotation",
              },
              {
                icon: "HelpFacetVortex",
                value: chaos.interval,
                caption: "osc_hud_help_fact_chaos",
              },
              {
                icon: "HelpStatDuration",
                value: chaos.duration,
                caption: "osc_hud_help_fact_chaos_duration",
              },
              {
                icon: "HelpImgSeven",
                value: L("osc_hud_help_fact_casino"),
                text: true,
                caption:
                  Number(casino.enabled) === 1
                    ? "osc_notify_vote_casino_on"
                    : "osc_notify_vote_casino_off",
              },
            ]}
          />
          <Subheading k="osc_hud_help_overview_screen" />
          <Cards
            columns={3}
            cards={[
              {
                icon: { image: "HelpStatCooldown" },
                title: L("osc_hud_help_overview_screen_timer"),
                text: L("osc_hud_help_overview_screen_timer_text"),
              },
              {
                icon: { image: "HelpFacetVortex" },
                title: L("osc_hud_help_overview_screen_chaos"),
                text: L("osc_hud_help_overview_screen_chaos_text"),
              },
              {
                icon: { image: "HelpFacetItem" },
                title: L("osc_hud_help_overview_screen_buttons"),
                text: L("osc_hud_help_overview_screen_buttons_text"),
              },
            ]}
          />
          <Label
            className="HelpFootnote"
            text={L("osc_hud_help_overview_version", {
              version: Table("version").version || "?",
            })}
          />
        </>
      );
    }

    function RotationPage(help: HelpTable) {
      var rotation: HelpSection<"rotation"> = help.rotation || {};
      var interval = Number(rotation.interval) || 0;
      var choices = Number(rotation.choice_count) || 0;
      var warning = choices > 0 ? Math.min(Number(rotation.warning) || 0, interval) : 0;
      var steps: HelpStep[] = [
        {
          value: L("osc_hud_help_seconds", { seconds: interval - warning }),
          title: L("osc_hud_help_rotation_step_play"),
          caption: L("osc_hud_help_rotation_step_play_caption"),
        },
      ];
      if (warning > 0) {
        steps.push({
          value: L("osc_hud_help_seconds", { seconds: warning }),
          title: L("osc_hud_help_rotation_step_pick", { count: choices }),
          caption: L("osc_hud_help_rotation_step_pick_caption"),
        });
      }
      steps.push({
        icon: "HelpStatCooldown",
        title: L("osc_hud_help_rotation_step_swap"),
        caption: L("osc_hud_help_rotation_step_swap_caption"),
      });

      var cards: HelpCard[] = [
        {
          icon: { image: "HelpFacetDice" },
          title: L("osc_hud_help_rotation_card_choice"),
          text: L(
            choices > 0 ? "osc_hud_help_rotation_choice" : "osc_hud_help_rotation_no_choice",
            {
              warning: warning,
              count: choices,
            },
          ),
        },
        {
          icon: { image: "HelpFacetAghs" },
          title: L("osc_hud_help_rotation_card_ultimate"),
          text: L("osc_hud_help_rotation_ultimate", { max: rotation.max_duplicate_ultimates }),
        },
        {
          icon: { image: "HelpFacetArrows" },
          title: L("osc_hud_help_rotation_card_effects"),
          text: L("osc_hud_help_rotation_effects"),
        },
      ];
      if (Number(rotation.tag_streak) > 0) {
        cards.push({
          icon: { image: "HelpFacetSpin" },
          title: L("osc_hud_help_rotation_card_tags"),
          text: L("osc_hud_help_rotation_tags", { streak: rotation.tag_streak }),
        });
      }
      return (
        <>
          <Text k="osc_hud_help_rotation_text" vars={{ interval: interval }} />
          <Steps steps={steps} />
          <Cards cards={cards} />
        </>
      );
    }

    function RarityPage(help: HelpTable) {
      var rarity: HelpSection<"rarity"> = help.rarity || {};
      if (Number(rarity.enabled) !== 1) {
        return (
          <>
            <Text k="osc_hud_help_rarity_text" />
            <Text k="osc_hud_help_rarity_off" />
          </>
        );
      }
      var ability = rarity.ability || {};
      var ultimate = rarity.ultimate || {};
      return (
        <>
          <Text k="osc_hud_help_rarity_text" />
          <Grid
            header={[
              "osc_hud_help_rarity_col_rarity",
              "osc_hud_help_rarity_col_frame",
              "osc_hud_help_rarity_col_ability",
              "osc_hud_help_rarity_col_ultimate",
            ]}
            rows={RARITIES.map(function (name) {
              return {
                icon: { image: BORDER_CLASS[name] },
                cells: [
                  L("osc_hud_help_rarity_" + name),
                  L("osc_hud_help_rarity_frame_" + name),
                  (ability[name] || 0) + "%",
                  (ultimate[name] || 0) + "%",
                ],
              };
            })}
          />
          <Text k="osc_hud_help_rarity_note" />
        </>
      );
    }

    function AnchorPage(help: HelpTable) {
      var anchor: HelpSection<"anchor"> = help.anchor || {};
      if (Number(anchor.enabled) !== 1) return <Text k="osc_hud_help_anchor_off" />;
      return (
        <>
          <Text k="osc_hud_help_anchor_text" />
          <Grid
            header={[
              "osc_hud_help_anchor_col_item",
              "osc_hud_help_anchor_col_rotations",
              "osc_hud_help_col_cost",
            ]}
            rows={OSC.Util.LuaArray(anchor.levels).map(function (level, index) {
              return {
                icon: { item: level.name },
                cells: [ItemName(level.name), String(index + 1), String(level.cost)],
              };
            })}
          />
          <Text k="osc_hud_help_anchor_merge" vars={{ count: anchor.merge_count }} />
        </>
      );
    }

    function ShopPage() {
      var items = OSC.Util.LuaArray(
        Table(`shop_${Players.GetTeam(Players.GetLocalPlayer())}`).items,
      );
      if (items.length === 0) return <Text k="osc_hud_help_shop_off" />;
      return (
        <>
          <Text k="osc_hud_help_shop_text" />
          <Grid
            header={[
              "osc_hud_help_shop_col_item",
              "osc_hud_help_col_cost",
              "osc_hud_help_shop_col_stock",
            ]}
            rows={items.map(function (item) {
              return {
                icon: { item: item.name },
                cells: [
                  ItemName(item.name),
                  String(item.cost),
                  Number(item.max) >= 0
                    ? L("osc_hud_help_shop_stock", { max: item.max })
                    : L("osc_hud_help_shop_unlimited"),
                ],
              };
            })}
          />
        </>
      );
    }

    function ChaosPage(help: HelpTable) {
      var chaos: HelpSection<"chaos"> = help.chaos || {};
      return (
        <>
          <Text
            k="osc_hud_help_chaos_text"
            vars={{ interval: chaos.interval, duration: chaos.duration, warning: chaos.warning }}
          />
          <Cards
            columns={3}
            cards={OSC.Util.LuaArray(chaos.events).map(function (ev) {
              return { title: L(ev.title_key), text: L(ev.desc_key, ev.params) };
            })}
          />
        </>
      );
    }

    function CasinoPage(help: HelpTable) {
      var casino: HelpSection<"casino"> = help.casino || {};
      if (Number(casino.enabled) !== 1) return <Text k="osc_hud_help_casino_off" />;
      var win = 0;
      var expected = 0;
      var rows: HelpRow[] = OSC.Util.LuaArray(casino.outcomes).map(function (outcome) {
        win += Number(outcome.chance);
        expected += (Number(outcome.chance) * Number(outcome.multiplier)) / 100;
        return {
          icon: { image: CASINO_CLASS[outcome.symbol] || "HelpImgCircle" },
          cells: [
            L("osc_hud_help_casino_sym_" + outcome.symbol),
            outcome.chance + "%",
            Number(outcome.multiplier) === 1
              ? L("osc_hud_help_casino_refund")
              : "×" + outcome.multiplier,
          ],
        };
      });
      rows.push({
        cells: [
          L("osc_hud_help_casino_lose"),
          Math.max(0, 100 - win) + "%",
          L("osc_hud_help_casino_lost"),
        ],
      });
      return (
        <>
          <Text
            k="osc_hud_help_casino_text"
            vars={{ lifetime: casino.lifetime, min: casino.min_stake }}
          />
          {Number(casino.item_bets) === 1 && (
            <Text k="osc_hud_help_casino_items" vars={{ pct: casino.item_value_pct }} />
          )}
          <Grid
            header={[
              "osc_hud_help_casino_col_combo",
              "osc_hud_help_casino_col_chance",
              "osc_hud_help_casino_col_payout",
            ]}
            rows={rows}
          />
          <Text k="osc_hud_help_casino_return" vars={{ pct: Math.round(expected * 100) }} />
        </>
      );
    }

    function SpherePage(help: HelpTable) {
      var sphere: HelpSection<"sphere"> = help.sphere || {};
      if (Number(sphere.enabled) !== 1) return <Text k="osc_hud_help_sphere_off" />;
      return (
        <>
          <Text k="osc_hud_help_sphere_text" />
          <Cards
            cards={[
              {
                icon: { image: "HelpImgLegendary" },
                title: L("osc_sphere_mode_ultimate"),
                text: L("osc_hud_help_sphere_ultimate", {
                  choices: sphere.choices,
                  level: sphere.min_level,
                }),
              },
              {
                icon: { ability: "chaos_knight_chaos_bolt" },
                title: L("osc_sphere_mode_enemies"),
                text: L("osc_hud_help_sphere_enemies"),
              },
            ]}
          />
          <Text k="osc_hud_help_sphere_note" />
        </>
      );
    }

    function CouriersPage(help: HelpTable) {
      var couriers: HelpSection<"couriers"> = help.couriers || {};
      return (
        <>
          <Text k="osc_hud_help_couriers_text" vars={{ count: couriers.count }} />
          <Cards
            cards={OSC.Util.LuaArray(couriers.abilities).map(function (ability) {
              var interval = ability.interval_min + "–" + ability.interval_max;
              return {
                title: $.Localize("#" + ability.name_token),
                text: L("osc_hud_help_courier_" + ability.name),
                stats: [
                  {
                    icon: "HelpStatDuration",
                    value: ability.duration,
                    tooltip: L("osc_hud_help_stat_duration", { value: ability.duration }),
                  },
                  {
                    icon: "HelpStatCooldown",
                    value: interval,
                    tooltip: L("osc_hud_help_stat_interval", { value: interval }),
                  },
                ],
              };
            })}
          />
        </>
      );
    }

    function SummaryPage(help: HelpTable) {
      var summary: HelpSection<"summary"> = help.summary || {};
      if (Number(summary.enabled) !== 1) return <Text k="osc_hud_help_summary_off" />;
      return (
        <>
          <Text k="osc_hud_help_summary_text" />
          <Cards
            cards={OSC.Util.LuaArray(summary.titles).map(function (id) {
              return { title: L("osc_hud_title_" + id), text: L("osc_hud_help_title_" + id) };
            })}
          />
          {summary.ties === "none" && <Text k="osc_hud_help_summary_ties" />}
        </>
      );
    }

    // ================= Панель =================

    function HelpWindow() {
      var [open, setOpen] = React.useState(false);
      var [current, setCurrent] = React.useState(TOPICS[0].id);
      // Подписка, чтобы открытая справка обновилась после итогов голосования
      var help = ReactPanorama.useNetTableKey("osc_state", "help") || {};
      var topic =
        TOPICS.filter(function (t) {
          return t.id === current;
        })[0] || TOPICS[0];

      return (
        <>
          <Button
            id="HelpButton"
            className="OSCButton"
            onactivate={function () {
              setOpen(!open);
            }}
          >
            <Label text={$.Localize("#osc_hud_help_button")} />
          </Button>
          <Panel id="HelpPanel" className={OSC.Util.Classes(open && "Visible")} hittest={true}>
            <Button
              id="HelpClose"
              className="OSCButton"
              onactivate={function () {
                setOpen(false);
              }}
            >
              <Label text={$.Localize("#osc_hud_help_close")} />
            </Button>
            <Label
              id="HelpTitle"
              className="OSCTextTitle OSCChaosText"
              text={$.Localize("#osc_hud_help_title")}
            />
            <Panel id="HelpBody">
              <Panel id="HelpTabs">
                {TOPICS.map(function (t) {
                  return (
                    <Button
                      key={t.id}
                      className={OSC.Util.Classes("HelpTab", t.id === topic.id && "Selected")}
                      onactivate={function () {
                        setCurrent(t.id);
                      }}
                    >
                      <Icon icon={t.icon} className="HelpTabIcon" />
                      <Label text={L("osc_hud_help_tab_" + t.id)} />
                    </Button>
                  );
                })}
              </Panel>
              {/* Страница строится только в открытой справке: числа и тексты свежие */}
              {open && (
                <Panel id="HelpPage" key={topic.id}>
                  <Panel className="HelpPageHeader">
                    <Icon icon={topic.icon} className="HelpPageIcon" />
                    <Label className="HelpPageTitle" text={L("osc_hud_help_tab_" + topic.id)} />
                  </Panel>
                  {topic.page(help)}
                </Panel>
              )}
            </Panel>
          </Panel>
        </>
      );
    }

    function Init() {
      ReactPanorama.render(<HelpWindow />, $("#HelpRoot"));
    }

    return { Init: Init };
  })();
}
