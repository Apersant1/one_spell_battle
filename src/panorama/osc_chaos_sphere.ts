namespace OSC {
  // Сфера хаоса: сервер шлёт osc_sphere_offer { options, ultimate_allowed,
  // min_level }, когда игрок применил сферу. Окно: два режима; после
  // «Легендарный ультимейт» — карточки вариантов (классы выбора из трёх и
  // рамки редкости). Выбор уходит osc_sphere_pick { mode, ability }; решает
  // сервер, отказы показывает OSC.HudError.
  export const ChaosSphere = (function () {
    var ultimateAllowed = false;

    function Send(mode: string, ability?: string) {
      GameEvents.SendCustomGameEventToServer("osc_sphere_pick", {
        mode: mode,
        ability: ability || "",
      });
    }

    function Hide() {
      var panel = $("#ChaosSpherePanel");
      panel.RemoveClass("Visible");
      panel.RemoveClass("Cards");
      $.DispatchEvent("DOTAHideAbilityTooltip", panel);
    }

    function CreateCard(container: Panel, option: OSCAbilityOption) {
      var card = $.CreatePanel("Button", container, "");
      card.AddClass("ChoiceCard");
      card.SetHasClass("RarityRare", option.rarity === "rare");
      card.SetHasClass("RarityLegendary", option.rarity === "legendary");

      var image = $.CreatePanel("DOTAAbilityImage", card, "");
      image.AddClass("ChoiceIcon");
      image.abilityname = option.name;
      image.hittest = false;

      var nameLabel = $.CreatePanel("Label", card, "");
      nameLabel.AddClass("ChoiceName");
      nameLabel.AddClass("OSCTextSmall");
      nameLabel.AddClass("OSCBold");
      nameLabel.text = OSC.Util.AbilityName(option.name, option.label);
      nameLabel.hittest = false;

      card.SetPanelEvent("onactivate", function () {
        Send("ultimate", option.name);
        Hide();
      });
      card.SetPanelEvent("onmouseover", function () {
        $.DispatchEvent("DOTAShowAbilityTooltip", card, option.name);
      });
      card.SetPanelEvent("onmouseout", function () {
        $.DispatchEvent("DOTAHideAbilityTooltip", card);
      });
    }

    function OnOffer(event: NetworkedData<CustomGameEventDeclarations["osc_sphere_offer"]>) {
      if (!event) return;
      var options = OSC.Util.AbilityOptions(event.options);
      var levelOk = Number(event.ultimate_allowed) === 1;
      ultimateAllowed = levelOk && options.length > 0;

      var cards = $("#ChaosSphereCards");
      cards.RemoveAndDeleteChildren();
      options.forEach(function (option) {
        CreateCard(cards, option);
      });

      $("#ChaosSphereUltimateButton").enabled = ultimateAllowed;
      var hint = $("#ChaosSphereLevelHint") as LabelPanel;
      hint.SetDialogVariableInt("level", Number(event.min_level) || 0);
      hint.text = $.Localize("#osc_sphere_level_hint", hint);
      hint.SetHasClass("Hidden", levelOk);

      var panel = $("#ChaosSpherePanel");
      panel.RemoveClass("Cards");
      panel.AddClass("Visible");
    }

    function ChooseUltimate() {
      if (!ultimateAllowed) return;
      $("#ChaosSpherePanel").AddClass("Cards");
    }

    function ChooseEnemies() {
      Send("enemies");
      Hide();
    }

    function Cancel() {
      Send("cancel");
      Hide();
    }

    function Init() {
      GameEvents.Subscribe("osc_sphere_offer", OnOffer);
    }

    return {
      Init: Init,
      ChooseUltimate: ChooseUltimate,
      ChooseEnemies: ChooseEnemies,
      Cancel: Cancel,
    };
  })();
}
