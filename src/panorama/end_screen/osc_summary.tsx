namespace OSC {
  // Итоги матча на DOTA_GAMERULES_STATE_POST_GAME (React): шуточные титулы и
  // таблица по игрокам из osc_state/summary. Живёт в своём экране конца игры
  // (osc_end_screen.xml, EndScreen) поверх стандартного.
  // Можно закрыть и открыть.
  type SummaryData = NetworkedData<CustomNetTableDeclarations["osc_state"]["summary"]>;
  type SummaryStats = Partial<NetworkedData<OSCSummaryRow>>;

  export const Summary = (function () {
    // Ключи титулов собираются из id с сервера:
    // osc_hud_title_<id> и osc_hud_title_<id>_desc (с {d:value})
    var POLL = 0.5;
    var TEAM_CLASSES: Record<number, string> = {};
    TEAM_CLASSES[DOTATeam_t.DOTA_TEAM_GOODGUYS] = "Radiant";
    TEAM_CLASSES[DOTATeam_t.DOTA_TEAM_BADGUYS] = "Dire";

    var COLUMNS: { key: string; field: keyof OSCSummaryRow; signed?: boolean }[] = [
      { key: "osc_hud_summary_col_rotations", field: "rotations" },
      { key: "osc_hud_summary_col_kills", field: "kills" },
      { key: "osc_hud_summary_col_casino", field: "casino_net", signed: true },
      { key: "osc_hud_summary_col_chaos_damage", field: "chaos_damage" },
    ];

    // Данные с сервера — пропускаем только имя юнита
    function SafeHeroName(value: string | undefined) {
      var name = String(value || "");
      return /^[a-z0-9_]+$/.test(name) ? name : "";
    }

    function PlayerHero(playerId: PlayerID, stats: SummaryStats | undefined) {
      var hero = stats && stats.hero ? stats.hero : Players.GetPlayerSelectedHero(playerId);
      return SafeHeroName(hero);
    }

    function PlayerName(playerId: PlayerID, hero: string) {
      var name = Players.GetPlayerName(playerId);
      if (name) return name;
      return hero ? $.Localize("#" + hero) : String(playerId);
    }

    function SignedNumber(raw: number) {
      var value = Number(raw) || 0;
      return value > 0 ? "+" + value : String(value);
    }

    // ================= Титулы =================
    // 3D-модель героя на пьедестале. Пьедестал идёт раньше сцены, чтобы ноги
    // рисовались поверх него; лишнее место кадра обрезает рамка (CSS).
    // Свойства сцены задаются только при создании — key пересоздаёт её с героем
    function Podium(props: { hero: string }) {
      return (
        <Panel className="SummaryPodium" hittest={false}>
          <Panel className="SummaryPedestalSide" hittest={false} />
          <Panel className="SummaryPedestalTop" hittest={false} />
          <DOTAScenePanel
            key={props.hero}
            className="SummaryPodiumScene"
            unit={props.hero}
            particleonly={false}
            allowrotation={true}
          />
        </Panel>
      );
    }

    function Titles(props: { data: SummaryData }) {
      var data = props.data;
      var titles = OSC.Util.LuaArray(data.titles).filter(function (title) {
        return title && title.id;
      });
      return (
        <Panel
          id="SummaryTitles"
          className={OSC.Util.Classes(titles.length === 0 && "Hidden")}
          hittest={false}
        >
          {titles.map(function (title) {
            var playerId = Number(title.player_id) as PlayerID;
            var hero = PlayerHero(playerId, data.players[String(playerId)]);
            return (
              <Panel
                key={title.id}
                className={OSC.Util.Classes(
                  "SummaryTitleCard",
                  playerId === Players.GetLocalPlayer() && "Local",
                )}
                hittest={false}
              >
                <Podium hero={hero} />
                <Panel className="SummaryTitleText" hittest={false}>
                  <Label
                    className="SummaryTitleName"
                    hittest={false}
                    text={OSC.Util.LocalizeOr("#osc_hud_title_" + title.id, String(title.id))}
                  />
                  <Label
                    className="SummaryTitlePlayer"
                    hittest={false}
                    text={PlayerName(playerId, hero)}
                  />
                  <Label
                    className="SummaryTitleDesc"
                    hittest={false}
                    text={function (desc) {
                      desc.SetDialogVariableInt("value", Math.round(Number(title.value) || 0));
                      return OSC.Util.LocalizeOr("#osc_hud_title_" + title.id + "_desc", "", desc);
                    }}
                  />
                </Panel>
              </Panel>
            );
          })}
        </Panel>
      );
    }

    // ================= Таблица =================
    function Table(props: { data: SummaryData }) {
      var players = props.data.players;
      var ids = Object.keys(players)
        .map(function (id) {
          return Number(id) as PlayerID;
        })
        .sort(function (a, b) {
          return Players.GetTeam(a) - Players.GetTeam(b) || a - b;
        });
      return (
        <Panel id="SummaryTable" hittest={false}>
          <Panel className="SummaryRow SummaryHeaderRow" hittest={false}>
            <Label
              className="SummaryCellPlayer"
              hittest={false}
              text={$.Localize("#osc_hud_summary_col_player")}
            />
            {COLUMNS.map(function (column) {
              return (
                <Label
                  key={column.key}
                  className="SummaryCell"
                  hittest={false}
                  text={$.Localize("#" + column.key)}
                />
              );
            })}
          </Panel>
          {ids.map(function (playerId) {
            var stats: SummaryStats = players[String(playerId)] || {};
            var hero = PlayerHero(playerId, stats);
            var teamClass = TEAM_CLASSES[Players.GetTeam(playerId)];
            return (
              <Panel
                key={playerId}
                className={OSC.Util.Classes(
                  "SummaryRow",
                  playerId === Players.GetLocalPlayer() && "Local",
                )}
                hittest={false}
              >
                <Panel className="SummaryCellPlayer" hittest={false}>
                  <DOTAHeroImage
                    key={hero}
                    className="SummaryRowHero"
                    heroname={hero}
                    heroimagestyle="icon"
                    hittest={false}
                  />
                  <Label
                    className={OSC.Util.Classes("SummaryPlayerName", teamClass)}
                    hittest={false}
                    text={PlayerName(playerId, hero)}
                  />
                </Panel>
                {COLUMNS.map(function (column) {
                  var value = Number(stats[column.field]) || 0;
                  return (
                    <Label
                      key={column.key}
                      className={OSC.Util.Classes(
                        "SummaryCell",
                        column.signed && value > 0 && "Positive",
                        column.signed && value < 0 && "Negative",
                      )}
                      hittest={false}
                      text={column.signed ? SignedNumber(value) : String(Math.round(value))}
                    />
                  );
                })}
              </Panel>
            );
          })}
        </Panel>
      );
    }

    // ================= Окно =================
    function SummaryWindow() {
      var data = ReactPanorama.useNetTableKey("osc_state", "summary");
      // Ждём POST_GAME: net table может обновиться раньше смены стадии
      var postGame = OSC.usePolled(OSC.Util.IsPostGame, POLL, true, function (post) {
        return post;
      });
      var [closed, setClosed] = React.useState(false);
      // Итог может прийти с задержкой — до него окна нет
      var ready = postGame && !!data && !!data.players;

      return (
        <>
          <Panel
            id="SummaryPanel"
            className={OSC.Util.Classes("OSCSurface OSCChaos", ready && !closed && "Visible")}
            hittest={true}
          >
            <Panel id="SummaryHeader" hittest={false}>
              <Label
                id="SummaryTitle"
                className="OSCTextTitle OSCGold"
                text={$.Localize("#osc_hud_summary_title")}
              />
              <Button
                id="SummaryClose"
                onactivate={function () {
                  setClosed(true);
                }}
              >
                <Label text={$.Localize("#osc_hud_summary_close")} />
              </Button>
            </Panel>
            {ready && <Titles data={data!} />}
            {ready && <Table data={data!} />}
          </Panel>
          <Button
            id="SummaryReopen"
            className={OSC.Util.Classes("OSCSurface OSCChaos", ready && closed && "Visible")}
            onactivate={function () {
              setClosed(false);
            }}
          >
            <Label className="OSCTextBody OSCBold" text={$.Localize("#osc_hud_summary_show")} />
          </Button>
        </>
      );
    }

    function Init() {
      // Корень разметки (.OSCRoot) — сама контекстная панель: id у корня запрещён
      ReactPanorama.render(<SummaryWindow />, $.GetContextPanel());
    }

    return { Init: Init };
  })();
}

OSC.Summary.Init();
