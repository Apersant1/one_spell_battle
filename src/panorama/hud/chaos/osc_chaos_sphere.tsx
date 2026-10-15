namespace OSC {
  // Сфера хаоса (React): сервер шлёт osc_sphere_offer { options, ultimate_allowed,
  // min_level }, когда игрок применил сферу. Окно: два режима; после
  // «Легендарный ультимейт» — карточки вариантов (классы выбора из трёх и
  // рамки редкости). Выбор уходит osc_sphere_pick { mode, ability }; решает
  // сервер, отказы показывает OSC.HudError.
  type SphereOffer = { options: OSCAbilityOption[]; levelOk: boolean; minLevel: number };

  export const ChaosSphere = (function () {
    function Send(mode: string, ability?: string) {
      GameEvents.SendCustomGameEventToServer("osc_sphere_pick", {
        mode: mode,
        ability: ability || "",
      });
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

      return (
        <Panel
          id="ChaosSpherePanel"
          className={OSC.Util.Classes(
            "OSCSurface OSCChaos",
            visible && "Visible",
            cards && "Cards",
          )}
          hittest={true}
        >
          <Label
            id="ChaosSphereTitle"
            className="OSCTextTitle OSCGold"
            text={$.Localize("#osc_sphere_title")}
          />
          <Panel id="ChaosSphereModes">
            <Button
              id="ChaosSphereUltimateButton"
              className="OSCButton OSCButtonPrimary"
              enabled={ultimateAllowed}
              onactivate={function () {
                if (ultimateAllowed) setCards(true);
              }}
            >
              <Label text={$.Localize("#osc_sphere_mode_ultimate")} />
            </Button>
            <Button
              id="ChaosSphereEnemiesButton"
              className="OSCButton OSCButtonPrimary"
              onactivate={function () {
                Send("enemies");
                Hide();
              }}
            >
              <Label text={$.Localize("#osc_sphere_mode_enemies")} />
            </Button>
          </Panel>
          <Label
            id="ChaosSphereLevelHint"
            className={OSC.Util.Classes("OSCTextSmall OSCMuted", offer.levelOk && "Hidden")}
            text={OSC.Localized("osc_sphere_level_hint", { level: offer.minLevel })}
          />
          <Label
            id="ChaosSphereChoose"
            className="OSCTextSmall OSCCaps OSCBold OSCChaosText"
            text={$.Localize("#osc_sphere_choose")}
          />
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
            id="ChaosSphereCancel"
            className="OSCButton"
            onactivate={function () {
              Send("cancel");
              Hide();
            }}
          >
            <Label text={$.Localize("#osc_sphere_cancel")} />
          </Button>
        </Panel>
      );
    }

    function Init() {
      ReactPanorama.render(<SphereWindow />, $("#ChaosSphereRoot"));
    }

    return { Init: Init };
  })();
}
