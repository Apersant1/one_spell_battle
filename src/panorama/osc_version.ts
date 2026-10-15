"use strict";

var OSC = OSC || {};

OSC.Version = (function () {
  function OnNetTableChanged(tableName, key, value) {
    if (tableName === "osc_state" && key === "version" && value) {
      $("#VersionLabel").text = "v" + value.version;
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
