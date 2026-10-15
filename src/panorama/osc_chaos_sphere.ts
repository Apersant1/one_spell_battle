namespace OSC {
  // Сфера хаоса: сервер шлёт osc_sphere_offer { options, ultimate_allowed,
  // min_level }, когда игрок применил сферу. Окно: два режима; после
  // «Легендарный ультимейт» — карточки вариантов (классы выбора из трёх и
  // рамки редкости). Выбор уходит osc_sphere_pick { mode, ability }; решает
  // сервер, отказы показывает OSC.HudError.
  export const ChaosSphere = (function () {
    var ultimateAllowed = false;

    // Lua-таблица { "1": {...}, "2": {...} } -> массив по возрастанию ключей
    function ToOptionList(raw: { [key: number]: Partial<OSCAbilityOption> } | null | undefined): OSCAbilityOption[] {
      if (!raw) return [];
      return Object.keys(raw)
        .sort(function (a, b) {
          return Number(a) - Number(b);
        })
        .map(function (key) {
          var option = raw[Number(key)] || {};
          return {
            name: String(option.name || ""),
            label: String(option.label || ""),
            rarity: String(option.rarity || "common"),
          };
        })
        .filter(function (option) {
          return option.name !== "";
        });
    }

    // Имя способности из локализации Dota; если ключа нет — подпись из пула
    function AbilityDisplayName(option: OSCAbilityOption) {
      var token = "#DOTA_Tooltip_Ability_" + option.name;
      var localized = $.Localize(token);
      if (localized && localized !== token) return localized;
      return option.label || option.name;
    }

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
      nameLabel.text = AbilityDisplayName(option);
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
      var options = ToOptionList(event.options);
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
