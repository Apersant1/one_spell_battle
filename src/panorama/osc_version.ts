namespace OSC {
  export const Version = (function () {
    function OnNetTableChanged(tableName: string, key: string, value: any) {
      if (tableName === "osc_state" && key === "version" && value) {
        ($("#VersionLabel") as LabelPanel).text = "v" + value.version;
      }
    }

    function Init() {
      CustomNetTables.SubscribeNetTableListener("osc_state", OnNetTableChanged);
      OnNetTableChanged(
        "osc_state",
        "version",
        CustomNetTables.GetTableValue("osc_state", "version"),
      );
    }

    return { Init: Init };
  })();
}
