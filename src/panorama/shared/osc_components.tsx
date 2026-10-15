namespace OSC {
  // Общие React-хелперы и компоненты. Файл подключается после библиотек React и
  // до модулей, которые их используют.

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

  // Подсказка Dota с текстом при наведении: {...OSC.TextTooltip(() => текст)}.
  // Текст читается в момент наведения; пустой — без подсказки
  export function TextTooltip(getText: () => string) {
    return {
      onmouseover: function (panel: Panel) {
        var text = getText();
        if (text) $.DispatchEvent("DOTAShowTextTooltip", panel, text);
      },
      onmouseout: function (panel: Panel) {
        $.DispatchEvent("DOTAHideTextTooltip", panel);
      },
    };
  }

  // Подсказка способности или предмета Dota при наведении: {...OSC.AbilityTooltip(имя)}
  export function AbilityTooltip(name: string) {
    return {
      onmouseover: function (panel: Panel) {
        $.DispatchEvent("DOTAShowAbilityTooltip", panel, name);
      },
      onmouseout: function (panel: Panel) {
        $.DispatchEvent("DOTAHideAbilityTooltip", panel);
      },
    };
  }

  // Значение read(), перечитываемое раз в interval секунд, пока active.
  // done(значение) === true останавливает опрос насовсем (стадия игры не вернётся)
  export function usePolled<T>(
    read: () => T,
    interval: number,
    active?: boolean,
    done?: (value: T) => boolean,
  ) {
    var [value, setValue] = React.useState(read);
    React.useEffect(
      function () {
        if (active === false) return;
        var stopped = false;
        OSC.Util.Loop(interval, function () {
          if (stopped) return false;
          var next = read();
          setValue(next);
          if (done && done(next)) return false;
        });
        return function () {
          stopped = true;
        };
      },
      [active],
    );
    return value;
  }

  // Для окон, чьё состояние — переменные модуля (казино, выбор из трёх):
  // функция перерисовки компонента
  export function useRerender() {
    var [, bump] = React.useReducer(function (n: number) {
      return n + 1;
    }, 0);
    return bump as () => void;
  }

  // Карточка способности (выбор из трёх, сфера хаоса): иконка, имя, рамка
  // редкости (osc_hud.css: обычная — без рамки), подсказка способности Dota
  export function AbilityCard(props: {
    option: OSCAbilityOption;
    className?: string;
    onactivate: () => void;
  }) {
    var option = props.option;
    return (
      <Button
        className={OSC.Util.Classes(
          "ChoiceCard",
          option.rarity === "rare" && "RarityRare",
          option.rarity === "legendary" && "RarityLegendary",
          props.className,
        )}
        onactivate={props.onactivate}
        {...OSC.AbilityTooltip(option.name)}
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
