namespace OSC {
  export const Version = (function () {
    function Init() {
      OSC.Net.Watch("version", function (value) {
        if (value) ($("#VersionLabel") as LabelPanel).text = "v" + value.version;
      });
    }

    return { Init: Init };
  })();
}
