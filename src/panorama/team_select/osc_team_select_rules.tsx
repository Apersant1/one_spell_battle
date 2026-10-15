namespace OSC.TeamSelect {
  // Выбор команд: правила матча слева вверху — главные настройки из
  // osc_state/help (osc/systems/help.lua), тех же, что в справке HUD.
  // Голосование в начале матча может их изменить — об этом подпись внизу.
  type Help = Partial<NetworkedData<OSCHelpData>>;

  function OnOff(enabled: number | undefined) {
    return $.Localize(Number(enabled) === 1 ? "#osc_ts_rule_on" : "#osc_ts_rule_off");
  }

  // Строки: название — вкладка справки, значение — текст или функция для Label
  function Rows(help: Help): { tab: string; value: string | ((l: LabelPanel) => string) }[] {
    var rotation: Partial<NetworkedData<OSCHelpData["rotation"]>> = help.rotation || {};
    var chaos: Partial<NetworkedData<OSCHelpData["chaos"]>> = help.chaos || {};
    return [
      {
        tab: "rotation",
        value: OSC.Localized("osc_ts_rule_every", { seconds: Number(rotation.interval) || 0 }),
      },
      {
        tab: "chaos",
        value: OSC.Localized("osc_ts_rule_chaos", {
          interval: Number(chaos.interval) || 0,
          duration: Number(chaos.duration) || 0,
        }),
      },
      { tab: "rarity", value: OnOff(help.rarity && help.rarity.enabled) },
      { tab: "anchor", value: OnOff(help.anchor && help.anchor.enabled) },
      { tab: "casino", value: OnOff(help.casino && help.casino.enabled) },
      { tab: "sphere", value: OnOff(help.sphere && help.sphere.enabled) },
    ];
  }

  export function Rules() {
    var help = ReactPanorama.useNetTableKey("osc_state", "help");
    if (!help) return null;
    return (
      <Panel id="Rules" hittest={false}>
        <Label id="RulesTitle" text={$.Localize("#osc_ts_rules_title")} />
        {Rows(help).map(function (row) {
          return (
            <Panel key={row.tab} className="RuleRow">
              <Label className="RuleName" text={$.Localize("#osc_hud_help_tab_" + row.tab)} />
              <Label className="RuleValue" text={row.value} />
            </Panel>
          );
        })}
        <Label id="RulesNote" text={$.Localize("#osc_ts_rules_note")} />
      </Panel>
    );
  }
}
