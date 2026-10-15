namespace OSC.TeamSelect {
  // Выбор команд: карточка команды (React) — заголовок, слоты игроков,
  // подсказка. Клик вступает в команду; хост перетаскивает на неё игроков.
  var DEFAULT_COLOR = "#E0C27A";

  var TEAM_THEME: Record<number, { token: string; color: string }> = {};
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_GOODGUYS] = { token: "osc_ts_team_light", color: "#45e0d0" };
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_BADGUYS] = { token: "osc_ts_team_dark", color: "#FF4A5A" };

  function Theme(teamId: DOTATeam_t) {
    var t = TEAM_THEME[teamId];
    if (t) return { name: $.Localize("#" + t.token), color: t.color };
    return { name: $.Localize(Game.GetTeamDetails(teamId).team_name), color: DEFAULT_COLOR };
  }

  function HintToken(locked: boolean, mine: boolean, full: boolean) {
    if (locked) return "osc_ts_hint_locked";
    if (mine) return "osc_ts_hint_mine";
    if (full) return "osc_ts_hint_full";
    return "osc_ts_click_to_join";
  }

  export type TeamView = {
    localTeam: DOTATeam_t | -1;
    localId: PlayerID;
    locked: boolean;
    canDrag: boolean; // хост и команды не зафиксированы
  };

  function Slot(props: { playerId: PlayerID | undefined; color: string; view: TeamView }) {
    var info = props.playerId !== undefined ? Game.GetPlayerInfo(props.playerId) : null;
    var local = !!info && props.playerId === props.view.localId;
    var ref = React.useRef<Panel>(null);
    // Обработчики перетаскивания регистрируются один раз — игрока берём отсюда
    var current = React.useRef<PlayerID | -1>(-1);
    current.current = info ? props.playerId! : -1;

    React.useEffect(function () {
      DragSource(ref.current!, function () {
        return current.current;
      });
    }, []);
    // draggable как атрибут задаётся только при создании панели
    var canDrag = !!info && props.view.canDrag;
    React.useEffect(
      function () {
        ref.current!.SetDraggable(canDrag);
      },
      [canDrag],
    );
    // Свой слот вспыхивает, когда игрок в него попадает
    React.useEffect(
      function () {
        if (local) ref.current!.TriggerClass("Pop");
      },
      [local],
    );

    return (
      <Panel
        ref={ref}
        className={OSC.Util.Classes(
          "Slot",
          info ? "Filled" : "Empty",
          local && "Local",
          !!info && info.player_has_host_privileges && "Host",
        )}
      >
        <Panel className="AvatarPlaceholder">
          <Panel className="SilHead" />
          <Panel className="SilBody" />
        </Panel>
        {/* steamid задаётся при создании — key пересоздаёт аватар под игрока */}
        <DOTAAvatarImage
          key={info ? info.player_steamid : "empty"}
          className="Avatar"
          steamid={info ? info.player_steamid : undefined}
          style={{ borderColor: props.color + "cc" }}
        />
        <Label
          className="SlotName"
          text={info ? info.player_name : $.Localize("#osc_ts_free_slot")}
        />
        <Label className="HostBadge" text={$.Localize("#osc_ts_host_badge")} />
      </Panel>
    );
  }

  export function TeamCard(props: { teamId: DOTATeam_t; view: TeamView; onJoin: () => void }) {
    var view = props.view;
    var theme = Theme(props.teamId);
    var details = Game.GetTeamDetails(props.teamId);
    var players = Game.GetPlayerIDsOnTeam(props.teamId);
    var mine = view.localTeam === props.teamId;
    var full = details.team_num_players >= details.team_max_players;
    var [hover, setHover] = React.useState(false);
    var ref = React.useRef<Panel>(null);

    React.useEffect(function () {
      DropTarget(ref.current!, props.teamId, setHover);
    }, []);

    var slots: JSX.Element[] = [];
    for (var i = 0; i < details.team_max_players; i++) {
      slots.push(<Slot key={i} playerId={players[i]} color={theme.color} view={view} />);
    }

    return (
      <Button
        ref={ref}
        className={OSC.Util.Classes(
          "TeamCard",
          mine && "Mine",
          full && !mine && "Full",
          hover && "DropHover",
        )}
        onactivate={props.onJoin}
      >
        <Panel className="CardBody">
          <Panel className="CardHeader">
            <Label className="TeamName" text={theme.name} style={{ color: theme.color }} />
            <Label
              className="TeamCount"
              text={details.team_num_players + "/" + details.team_max_players}
            />
          </Panel>
          <Panel
            className="Divider"
            style={{
              backgroundColor:
                "gradient(linear, 0% 0%, 100% 0%, from(" + theme.color + "aa), to(#00000000))",
            }}
          />
          <Panel className="SlotList">{slots}</Panel>
          <Label className="JoinHint" text={$.Localize("#" + HintToken(view.locked, mine, full))} />
        </Panel>
      </Button>
    );
  }
}
