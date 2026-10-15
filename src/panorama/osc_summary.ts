namespace OSC {
  // Итоги матча на DOTA_GAMERULES_STATE_POST_GAME: шуточные титулы и таблица
  // по игрокам из osc_state/summary. Живёт в своём экране конца игры
  // (osc_end_screen.xml, EndScreen) поверх стандартного.
  // Можно закрыть и открыть.
  type SummaryData = NetworkedData<CustomNetTableDeclarations["osc_state"]["summary"]>;

  export const Summary = (function () {
    // Ключи титулов собираются из id с сервера:
    // osc_hud_title_<id> и osc_hud_title_<id>_desc (с {d:value})
    var HUD_KEY = "osc_hud";
    var POLL = 0.5;
    var TEAM_CLASSES: Record<number, string> = {};
    TEAM_CLASSES[DOTATeam_t.DOTA_TEAM_GOODGUYS] = "Radiant";
    TEAM_CLASSES[DOTATeam_t.DOTA_TEAM_BADGUYS] = "Dire";

    var closedByUser = false;
    var renderedSignature = "";

    function LocalizeOr(suffix: string, fallback: string, panel?: Panel) {
      var token = "#" + HUD_KEY + "_" + suffix;
      var text = panel ? $.Localize(token, panel) : $.Localize(token);
      return text && text !== token ? text : fallback;
    }

    // Данные с сервера — пропускаем только имя юнита
    function SafeHeroName(value: string | undefined) {
      var name = String(value || "");
      return /^[a-z0-9_]+$/.test(name) ? name : "";
    }

    function PlayerHero(
      playerId: PlayerID,
      stats: Partial<NetworkedData<OSCSummaryRow>> | undefined,
    ) {
      var hero = stats && stats.hero ? stats.hero : Players.GetPlayerSelectedHero(playerId);
      return SafeHeroName(hero);
    }

    function PlayerName(playerId: PlayerID, hero: string) {
      var name = Players.GetPlayerName(playerId);
      if (name) return name;
      return hero ? $.Localize("#" + hero) : String(playerId);
    }

    // BCreateChildren у панелей из $.CreatePanel нет (JS Exception в матче)
    function CreateHeroImage(parent: Panel, hero: string, style: string, cssClass: string) {
      var image = $.CreatePanel("DOTAHeroImage", parent, "", {
        heroname: hero,
        heroimagestyle: style,
      });
      image.AddClass(cssClass);
      image.hittest = false;
    }

    // 3D-модель героя на пьедестале. Пьедестал создаётся раньше сцены, чтобы
    // ноги рисовались поверх него; лишнее место кадра обрезает рамка (CSS)
    function CreatePodium(parent: Panel, hero: string) {
      var podium = $.CreatePanel("Panel", parent, "");
      podium.AddClass("SummaryPodium");
      podium.hittest = false;
      ["SummaryPedestalSide", "SummaryPedestalTop"].forEach(function (cssClass) {
        var part = $.CreatePanel("Panel", podium, "");
        part.AddClass(cssClass);
        part.hittest = false;
      });
      var scene = $.CreatePanel("DOTAScenePanel", podium, "", {
        unit: hero,
        particleonly: "false",
        allowrotation: "true",
      });
      scene.AddClass("SummaryPodiumScene");
    }

    function CreateLabel(parent: Panel, cssClass: string, text?: string) {
      var label = $.CreatePanel("Label", parent, "");
      label.AddClass(cssClass);
      label.hittest = false;
      if (text !== undefined) label.text = text;
      return label;
    }

    function SignedNumber(raw: number) {
      var value = Number(raw) || 0;
      return value > 0 ? "+" + value : String(value);
    }

    // ================= Титулы =================
    function RenderTitles(data: SummaryData) {
      var container = $("#SummaryTitles");
      container.RemoveAndDeleteChildren();
      var titles = OSC.Util.LuaArray(data.titles).filter(function (title) {
        return title && title.id;
      });
      container.SetHasClass("Hidden", titles.length === 0);

      titles.forEach(function (title) {
        var playerId = Number(title.player_id) as PlayerID;
        var stats = data.players[String(playerId)];
        var hero = PlayerHero(playerId, stats);

        var card = $.CreatePanel("Panel", container, "");
        card.AddClass("SummaryTitleCard");
        card.SetHasClass("Local", playerId === Players.GetLocalPlayer());
        card.hittest = false;

        CreatePodium(card, hero);

        var text = $.CreatePanel("Panel", card, "");
        text.AddClass("SummaryTitleText");
        text.hittest = false;

        CreateLabel(text, "SummaryTitleName", LocalizeOr("title_" + title.id, String(title.id)));
        CreateLabel(text, "SummaryTitlePlayer", PlayerName(playerId, hero));

        var desc = CreateLabel(text, "SummaryTitleDesc");
        desc.SetDialogVariableInt("value", Math.round(Number(title.value) || 0));
        desc.text = LocalizeOr("title_" + title.id + "_desc", "", desc);
      });
    }

    // ================= Таблица =================
    var COLUMNS: { key: string; field: keyof OSCSummaryRow; signed?: boolean }[] = [
      { key: "osc_hud_summary_col_rotations", field: "rotations" },
      { key: "osc_hud_summary_col_kills", field: "kills" },
      { key: "osc_hud_summary_col_casino", field: "casino_net", signed: true },
      { key: "osc_hud_summary_col_chaos_damage", field: "chaos_damage" },
    ];

    function RenderTable(data: SummaryData) {
      var table = $("#SummaryTable");
      table.RemoveAndDeleteChildren();

      var header = $.CreatePanel("Panel", table, "");
      header.AddClass("SummaryRow");
      header.AddClass("SummaryHeaderRow");
      header.hittest = false;
      CreateLabel(header, "SummaryCellPlayer", $.Localize("#osc_hud_summary_col_player"));
      COLUMNS.forEach(function (column) {
        CreateLabel(header, "SummaryCell", $.Localize("#" + column.key));
      });

      var ids = Object.keys(data.players)
        .map(function (id) {
          return Number(id) as PlayerID;
        })
        .sort(function (a, b) {
          return Players.GetTeam(a) - Players.GetTeam(b) || a - b;
        });

      ids.forEach(function (playerId) {
        var stats: Partial<NetworkedData<OSCSummaryRow>> = data.players[String(playerId)] || {};
        var hero = PlayerHero(playerId, stats);

        var row = $.CreatePanel("Panel", table, "");
        row.AddClass("SummaryRow");
        row.SetHasClass("Local", playerId === Players.GetLocalPlayer());
        row.hittest = false;

        var player = $.CreatePanel("Panel", row, "");
        player.AddClass("SummaryCellPlayer");
        player.hittest = false;
        CreateHeroImage(player, hero, "icon", "SummaryRowHero");
        var name = CreateLabel(player, "SummaryPlayerName", PlayerName(playerId, hero));
        var teamClass = TEAM_CLASSES[Players.GetTeam(playerId)];
        if (teamClass) name.AddClass(teamClass);

        COLUMNS.forEach(function (column) {
          var value = Number(stats[column.field]) || 0;
          var cell = CreateLabel(
            row,
            "SummaryCell",
            column.signed ? SignedNumber(value) : String(Math.round(value)),
          );
          if (column.signed) {
            cell.SetHasClass("Positive", value > 0);
            cell.SetHasClass("Negative", value < 0);
          }
        });
      });
    }

    // ================= Видимость =================
    function SetVisible() {
      $("#SummaryPanel").SetHasClass("Visible", !closedByUser);
      $("#SummaryReopen").SetHasClass("Visible", closedByUser);
    }

    function Update() {
      if (!OSC.Util.IsPostGame()) return;
      var data = CustomNetTables.GetTableValue("osc_state", "summary");
      if (!data || !data.players) return; // итог может прийти с задержкой

      var signature = JSON.stringify(data);
      if (signature !== renderedSignature) {
        renderedSignature = signature;
        RenderTitles(data);
        RenderTable(data);
      }
      SetVisible();
      return false; // дальше обновляет подписка на net table
    }

    function OnNetTableChanged(tableName: string, key: string) {
      if (key === "summary") Update();
    }

    function Close() {
      closedByUser = true;
      SetVisible();
    }

    function Open() {
      closedByUser = false;
      SetVisible();
    }

    function Init() {
      CustomNetTables.SubscribeNetTableListener("osc_state", OnNetTableChanged);
      // Ждём POST_GAME: net table может обновиться раньше смены стадии
      OSC.Util.Loop(POLL, Update);
    }

    return {
      Init: Init,
      Close: Close, // вызывается из XML
      Open: Open, // вызывается из XML
    };
  })();
}
