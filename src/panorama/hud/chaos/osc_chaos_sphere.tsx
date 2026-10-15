namespace OSC {
  // Сфера хаоса (React): сервер шлёт osc_sphere_offer { options, ultimate_allowed,
  // min_level }, когда игрок применил сферу. Окно в рамке справки
  // (sphere_bg_shadow): две плитки режимов; после «Легендарный ультимейт» —
  // карточки вариантов (классы выбора из трёх и рамки редкости) и «Назад».
  // Выбор уходит osc_sphere_pick { mode, ability }; решает сервер, отказы
  // показывает OSC.HudError. Крестик — cancel: сфера не тратится.
  type SphereOffer = { options: OSCAbilityOption[]; levelOk: boolean; minLevel: number };

  export const ChaosSphere = (function () {
    function Send(mode: string, ability?: string) {
      GameEvents.SendCustomGameEventToServer("osc_sphere_pick", {
        mode: mode,
        ability: ability || "",
      });
    }

    // Плитка режима: иконка в рамке редкости, название, описание. locked —
    // почему режим пока недоступен (вместо описания); пусто — доступен
    function ModeTile(props: {
      frame: string;
      icon: JSX.Element;
      title: string;
      text: string | ((label: LabelPanel) => string);
      locked?: string | ((label: LabelPanel) => string);
      enabled: boolean;
      onactivate: () => void;
    }) {
      return (
        <Button
          className={OSC.Util.Classes("SphereMode", !!props.locked && "Locked")}
          enabled={props.enabled}
          onactivate={props.onactivate}
        >
          <Panel className={"SphereModeFrame " + props.frame} hittest={false}>
            {props.icon}
          </Panel>
          <Label className="SphereModeTitle" text={props.title} hittest={false} />
          <Label
            className={OSC.Util.Classes("SphereModeText", !!props.locked && "Lock")}
            text={props.locked || props.text}
            hittest={false}
          />
        </Button>
      );
    }

    function SphereWindow() {
      // Последнее предложение остаётся и после закрытия — окно гаснет с ним
      var [offer, setOffer] = React.useState<SphereOffer>({
        options: [],
        levelOk: false,
        minLevel: 0,
      });
      var [visible, setVisible] = React.useState(false);
      var [cards, setCards] = React.useState(false);
      var ultimateAllowed = offer.levelOk && offer.options.length > 0;

      ReactPanorama.useGameEvent(
        "osc_sphere_offer",
        function (event) {
          if (!event) return;
          setOffer({
            options: OSC.Util.AbilityOptions(event.options),
            levelOk: Number(event.ultimate_allowed) === 1,
            minLevel: Number(event.min_level) || 0,
          });
          setCards(false);
          setVisible(true);
        },
        [],
      );

      function Hide() {
        setVisible(false);
        setCards(false);
        $.DispatchEvent("DOTAHideAbilityTooltip", $("#ChaosSpherePanel"));
      }

      function Cancel() {
        Send("cancel");
        Hide();
      }

      return (
        <Panel
          id="ChaosSpherePanel"
          className={OSC.Util.Classes(visible && "Visible", cards && "Cards")}
          hittest={true}
        >
          {/* Как у Хаос-лавки: крестик в углу рамки, сфера не тратится */}
          <Button id="ChaosSphereClose" onactivate={Cancel}>
            <Label text={$.Localize("#osc_sphere_cancel")} />
          </Button>
          <Panel id="ChaosSphereHeader" hittest={false}>
            <DOTAItemImage id="ChaosSphereIcon" itemname="item_osc_chaos_sphere" hittest={false} />
            <Label
              id="ChaosSphereTitle"
              className="OSCTextTitle OSCGold"
              text={$.Localize(cards ? "#osc_sphere_choose" : "#osc_sphere_title")}
            />
          </Panel>
          {!cards && (
            <Panel id="ChaosSphereModes">
              <ModeTile
                frame="Legendary"
                icon={<Panel className="SphereModeIcon HelpFacetAghs" hittest={false} />}
                title={$.Localize("#osc_sphere_mode_ultimate")}
                text={OSC.Localized("osc_hud_help_sphere_ultimate", {
                  choices: String(offer.options.length),
                  level: String(offer.minLevel),
                })}
                locked={
                  offer.levelOk
                    ? ""
                    : OSC.Localized("osc_sphere_level_hint", { level: offer.minLevel })
                }
                enabled={ultimateAllowed}
                onactivate={function () {
                  setCards(true);
                }}
              />
              <ModeTile
                frame="Rare"
                icon={
                  <DOTAAbilityImage
                    className="SphereModeIcon"
                    abilityname="chaos_knight_chaos_bolt"
                    hittest={false}
                  />
                }
                title={$.Localize("#osc_sphere_mode_enemies")}
                text={$.Localize("#osc_hud_help_sphere_enemies")}
                enabled={true}
                onactivate={function () {
                  Send("enemies");
                  Hide();
                }}
              />
            </Panel>
          )}
          {cards && (
            <>
              <Panel id="ChaosSphereCards">
                {offer.options.map(function (option) {
                  return (
                    <OSC.AbilityCard
                      key={option.name}
                      option={option}
                      onactivate={function () {
                        Send("ultimate", option.name);
                        Hide();
                      }}
                    />
                  );
                })}
              </Panel>
              <Button
                id="ChaosSphereBack"
                className="OSCButton"
                onactivate={function () {
                  setCards(false);
                }}
              >
                <Label text={$.Localize("#osc_sphere_back")} />
              </Button>
            </>
          )}
        </Panel>
      );
    }

    function Init() {
      ReactPanorama.render(<SphereWindow />, $("#ChaosSphereRoot"));
    }

    return { Init: Init };
  })();
}
