namespace OSC {
  // Итоги матча на DOTA_GAMERULES_STATE_POST_GAME (React): шуточные титулы на
  // пьедесталах и таблица по командам из osc_state/summary. Живёт в своём экране
  // конца игры (osc_end_screen.xml, EndScreen) поверх стандартного.
  // Можно закрыть и открыть.
  type SummaryData = NetworkedData<CustomNetTableDeclarations["osc_state"]["summary"]>;
  type SummaryStats = Partial<NetworkedData<OSCSummaryRow>>;
  // Карточка на пьедестале: титул или, если титулов нет, победитель
  type PodiumCard = {
    key: string;
    playerId: PlayerID;
    name: string;
    desc?: (l: LabelPanel) => string;
  };

  export const Summary = (function () {
    // Ключи титулов собираются из id с сервера:
    // osc_hud_title_<id> и osc_hud_title_<id>_desc (с {d:value})
    var POLL = 0.5;
    var TEAMS: Record<number, { className: string; token: string }> = {};
    TEAMS[DOTATeam_t.DOTA_TEAM_GOODGUYS] = {
      className: "Radiant",
      token: "osc_hud_summary_team_radiant",
    };
    TEAMS[DOTATeam_t.DOTA_TEAM_BADGUYS] = { className: "Dire", token: "osc_hud_summary_team_dire" };

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

    function PlayerIds(data: SummaryData) {
      return Object.keys(data.players)
        .map(function (id) {
          return Number(id) as PlayerID;
        })
        .sort(function (a, b) {
          return Players.GetTeam(a) - Players.GetTeam(b) || a - b;
        });
    }

    // ================= Пьедесталы =================
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

    // Титулы с сервера; если их нет — герои победившей команды
    function PodiumCards(data: SummaryData): PodiumCard[] {
      var titles = OSC.Util.LuaArray(data.titles).filter(function (title) {
        return title && title.id;
      });
      if (titles.length > 0) {
        return titles.map(function (title) {
          return {
            key: title.id,
            playerId: Number(title.player_id) as PlayerID,
            name: OSC.Util.LocalizeOr("#osc_hud_title_" + title.id, String(title.id)),
            desc: function (label: LabelPanel) {
              label.SetDialogVariableInt("value", Math.round(Number(title.value) || 0));
              return OSC.Util.LocalizeOr("#osc_hud_title_" + title.id + "_desc", "", label);
            },
          };
        });
      }
      var winner = Game.GetGameWinner();
      return PlayerIds(data)
        .filter(function (playerId) {
          return Players.GetTeam(playerId) === winner;
        })
        .map(function (playerId) {
          return {
            key: String(playerId),
            playerId: playerId,
            name: $.Localize("#osc_hud_summary_winner"),
          };
        });
    }

    function Podiums(props: { data: SummaryData }) {
      var cards = PodiumCards(props.data);
      if (cards.length === 0) return null;
      return (
        <Panel id="SummaryPodiums" hittest={false}>
          {cards.map(function (card) {
            var hero = PlayerHero(card.playerId, props.data.players[String(card.playerId)]);
            return (
              <Panel
                key={card.key}
                className={OSC.Util.Classes(
                  "SummaryTitleCard",
                  (TEAMS[Players.GetTeam(card.playerId)] || { className: "" }).className,
                  card.playerId === Players.GetLocalPlayer() && "Local",
                )}
                hittest={false}
              >
                <Podium hero={hero} />
                <Label className="SummaryTitleName" hittest={false} text={card.name} />
                <Label
                  className="SummaryTitlePlayer"
                  hittest={false}
                  text={PlayerName(card.playerId, hero)}
                />
                {card.desc && (
                  <Label className="SummaryTitleDesc" hittest={false} text={card.desc} />
                )}
              </Panel>
            );
          })}
        </Panel>
      );
    }

    // ================= Таблица =================
    // Лучшее значение колонки (больше нуля) — его ячейки подсвечены
    function BestValues(data: SummaryData) {
      var best: Record<string, number> = {};
      COLUMNS.forEach(function (column) {
        var top = 0;
        for (var id in data.players) {
          top = Math.max(top, Number(data.players[id][column.field]) || 0);
        }
        best[column.field] = top;
      });
      return best;
    }

    function PlayerRow(props: {
      playerId: PlayerID;
      stats: SummaryStats;
      best: Record<string, number>;
    }) {
      var hero = PlayerHero(props.playerId, props.stats);
      return (
        <Panel
          className={OSC.Util.Classes(
            "SummaryRow",
            props.playerId === Players.GetLocalPlayer() && "Local",
          )}
          hittest={false}
        >
          <Panel className="SummaryCellPlayer" hittest={false}>
            <DOTAHeroImage
              key={hero}
              className="SummaryRowHero"
              heroname={hero}
              heroimagestyle="landscape"
              hittest={false}
            />
            <Label
              className="SummaryPlayerName"
              hittest={false}
              text={PlayerName(props.playerId, hero)}
            />
          </Panel>
          {COLUMNS.map(function (column) {
            var value = Number(props.stats[column.field]) || 0;
            return (
              <Label
                key={column.key}
                className={OSC.Util.Classes(
                  "SummaryCell",
                  column.signed && value > 0 && "Positive",
                  column.signed && value < 0 && "Negative",
                  value > 0 && value === props.best[column.field] && "Best",
                )}
                hittest={false}
                text={column.signed ? SignedNumber(value) : String(Math.round(value))}
              />
            );
          })}
        </Panel>
      );
    }

    function Table(props: { data: SummaryData }) {
      var players = props.data.players;
      var best = BestValues(props.data);
      var ids = PlayerIds(props.data);
      var teams = ids
        .map(function (playerId) {
          return Players.GetTeam(playerId);
        })
        .filter(function (team, index, all) {
          return all.indexOf(team) === index;
        });
      var winner = Game.GetGameWinner();
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
          {teams.map(function (team) {
            var info = TEAMS[team];
            return (
              <Panel
                key={team}
                className={OSC.Util.Classes("SummaryTeam", info && info.className)}
                hittest={false}
              >
                {info && (
                  <Panel className="SummaryTeamHeader" hittest={false}>
                    <Label
                      className="SummaryTeamName"
                      hittest={false}
                      text={$.Localize("#" + info.token)}
                    />
                    {team === winner && (
                      <Label
                        className="SummaryTeamWinner"
                        hittest={false}
                        text={$.Localize("#osc_hud_summary_winner")}
                      />
                    )}
                  </Panel>
                )}
                {ids
                  .filter(function (playerId) {
                    return Players.GetTeam(playerId) === team;
                  })
                  .map(function (playerId) {
                    return (
                      <PlayerRow
                        key={playerId}
                        playerId={playerId}
                        stats={players[String(playerId)] || {}}
                        best={best}
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
    // Эффект победы стандартного HUD рисуется поверх нашего слоя. z-index
    // действует только среди соседей, поэтому поднимаем всю цепочку предков:
    // на уровне общего с эффектом предка наша ветка окажется выше.
    // Цепочка — в консоль, если эффект всё же окажется сверху
    function RaiseAboveHud() {
      var chain: string[] = [];
      for (var panel: Panel | null = $.GetContextPanel(); panel; panel = panel.GetParent()) {
        panel.style.zIndex = 100;
        chain.push(panel.id || panel.paneltype);
      }
      $.Msg("[OSC] summary raised: " + chain.join(" < "));
    }

    function SummaryWindow() {
      var data = ReactPanorama.useNetTableKey("osc_state", "summary");
      // Ждём POST_GAME: net table может обновиться раньше смены стадии
      var postGame = OSC.usePolled(OSC.Util.IsPostGame, POLL, true, function (post) {
        return post;
      });
      var [closed, setClosed] = React.useState(false);
      // Итог может прийти с задержкой — до него окна нет
      var ready = postGame && !!data && !!data.players;
      React.useEffect(
        function () {
          if (ready) RaiseAboveHud();
        },
        [ready],
      );

      return (
        <>
          <Panel
            id="SummaryPanel"
            className={OSC.Util.Classes(ready && !closed && "Visible")}
            hittest={true}
          >
            {/* Как в справке: крестик в углу рамки, заголовок по центру */}
            <Button
              id="SummaryClose"
              onactivate={function () {
                setClosed(true);
              }}
            >
              <Label text={$.Localize("#osc_hud_summary_close")} />
            </Button>
            <Label
              id="SummaryTitle"
              className="OSCTextTitle OSCGold"
              text={$.Localize("#osc_hud_summary_title")}
            />
            <Panel id="SummaryBody" hittest={false}>
              {ready && <Podiums data={data!} />}
              {ready && <Table data={data!} />}
            </Panel>
          </Panel>
          <Button
            id="SummaryReopen"
            className={OSC.Util.Classes(ready && closed && "Visible")}
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
