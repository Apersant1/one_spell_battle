namespace OSC {
  // Общие React-компоненты HUD. Файл подключается после библиотек React и до
  // модулей, которые их используют.

  // Текст Label из resource/addon_<язык>.txt: значение для text={...}.
  // vars подставляются в {d:...} (числа) и {s:...} (строки) как dialog variables
  // самой метки — $.Localize без панели их вырезает
  export function Localized(token: string, vars?: Record<string, unknown>) {
    return function (panel: LabelPanel) {
      for (var key in vars || {}) {
        var value = vars![key];
        if (typeof value === "number") {
          panel.SetDialogVariableInt(key, value);
        } else {
          panel.SetDialogVariable(key, String(value));
        }
      }
      return $.Localize("#" + token, panel);
    };
  }

  // Карточка способности (выбор из трёх, сфера хаоса): иконка, имя, рамка
  // редкости (osc_hud.css: обычная — без рамки), подсказка способности Dota
  export function AbilityCard(props: {
    option: OSCAbilityOption;
    className?: string;
    onactivate: () => void;
  }) {
    var option = props.option;
    var classes = ["ChoiceCard"];
    if (option.rarity === "rare") classes.push("RarityRare");
    if (option.rarity === "legendary") classes.push("RarityLegendary");
    if (props.className) classes.push(props.className);
    return (
      <Button
        className={classes.join(" ")}
        onactivate={props.onactivate}
        onmouseover={function (card) {
          $.DispatchEvent("DOTAShowAbilityTooltip", card, option.name);
        }}
        onmouseout={function (card) {
          $.DispatchEvent("DOTAHideAbilityTooltip", card);
        }}
      >
        <DOTAAbilityImage className="ChoiceIcon" abilityname={option.name} hittest={false} />
        <Label
          className="ChoiceName OSCTextSmall OSCBold"
          text={OSC.Util.AbilityName(option.name, option.label)}
          hittest={false}
        />
      </Button>
    );
  }
}
