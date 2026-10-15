namespace OSC.TeamSelect {
  // Экран выбора команд (React, свой контекст GameSetup). Части: карточки —
  // osc_team_select_cards.tsx, орбита и перетаскивание — osc_team_select_lobby.ts,
  // родной чат — osc_team_select_chat.ts.
  // Состояние берём у движка (Game.*) и перерисовываем по его событиям.
  var CFG = {
    tick: 0.03,
    timerPoll: 0.05,
    urgentSeconds: 5, // с этого момента кольцо таймера краснеет
    lockCountdown: 4, // секунд до старта после «Начать игру»
    starCount: 90,
    narrowAspect: 1.6, // уже этого (16:10, 4:3) — компактная раскладка
  };

  // Карточки ставятся слева и справа; экран рассчитан на две команды
  var TEAM_CONTAINERS = ["TeamLeft", "TeamRight"];

  var Render = function () {}; // перерисовка экрана; задаёт App
  var chatReady = false;
  var narrowNow = false;

  // ================= Утилиты =================

  export function Sound(name: string) {
    if (OSC.Sounds[name]) OSC.Util.PlaySound(OSC.Sounds[name]);
  }

  // Скрипт может загрузиться чуть раньше стадии выбора команд — тогда ждём;
  // закончилась — возвращаем Dota её чат и контейнер
  export function SetupStarted() {
    return Game.GetState() >= DOTA_GameState.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP;
  }

  export function SetupOver() {
    return Game.GetState() > DOTA_GameState.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP;
  }

  function IsHost() {
    var info = Game.GetLocalPlayerInfo();
    return !!(info && info.player_has_host_privileges);
  }

  function LocalTeam(): DOTATeam_t | -1 {
    var info = Game.GetLocalPlayerInfo();
    return info ? info.player_team_id : -1;
  }

  function IsNarrow() {
    var h = Game.GetScreenHeight();
    return !!h && Game.GetScreenWidth() / h < CFG.narrowAspect;
  }

  // ================= Действия игрока =================

  var Actions = {
    join: function (teamId: DOTATeam_t) {
      if (Game.GetTeamSelectionLocked()) return;
      if (LocalTeam() === teamId) return;

      var details = Game.GetTeamDetails(teamId);
      if (details.team_num_players >= details.team_max_players) return;

      Game.PlayerJoinTeam(teamId);
      Sound("teamPick");
    },

    // Обратно на орбиту, как в стандартном выборе команд Valve
    leave: function () {
      if (Game.GetTeamSelectionLocked()) return;
      Game.PlayerJoinTeam(DOTATeam_t.DOTA_TEAM_NOTEAM);
      Sound("teamCancel");
    },

    // Одна кнопка вместо «Перемешать» и «Автораспределения»: сервер
    // раскладывает всех, включая игроков без команды, поровну и случайно
    // (osc/systems/team_shuffle.lua)
    shuffle: function () {
      GameEvents.SendCustomGameEventToServer("osc_team_shuffle", {});
      Sound("teamShuffle");
    },

    toggleStart: function () {
      if (Game.GetTeamSelectionLocked()) {
        Game.SetTeamSelectionLocked(false);
        Game.SetRemainingSetupTime(-1);
        Sound("teamCancel");
      } else {
        if (Game.GetUnassignedPlayerIDs().length > 0) return;
        Game.SetTeamSelectionLocked(true);
        Game.SetAutoLaunchEnabled(false);
        Game.SetRemainingSetupTime(CFG.lockCountdown);
        Sound("teamLockStart");
      }
      Render();
    },
  };

  // ================= Фон и заголовок =================

  // Звёзды случайные — строим один раз
  function Stars() {
    var stars = React.useMemo(function () {
      var list: JSX.Element[] = [];
      for (var i = 0; i < CFG.starCount; i++) {
        var size = 1 + Math.floor(Math.random() * 3) + "px";
        list.push(
          <Panel
            key={i}
            className="Star"
            hittest={false}
            style={{
              width: size,
              height: size,
              position:
                (Math.random() * 100).toFixed(2) +
                "% " +
                (Math.random() * 100).toFixed(2) +
                "% 0px",
              animationDuration: (2 + Math.random() * 4).toFixed(2) + "s",
              animationDelay: (Math.random() * 4).toFixed(2) + "s",
            }}
          />,
        );
      }
      return list;
    }, []);
    return (
      <Panel id="Stars" hittest={false}>
        {stars}
      </Panel>
    );
  }

  function Backdrop() {
    return (
      <Panel id="Backdrop" hittest={false}>
        <Panel className="Nebula NebulaCenter" hittest={false} />
        <Panel className="Nebula NebulaLeft" hittest={false} />
        <Panel className="Nebula NebulaRight" hittest={false} />
        <Stars />
        <Panel className="Vignette" hittest={false} />
      </Panel>
    );
  }

  function Header() {
    var map = (Game.GetMapInfo().map_display_name || "").toUpperCase();
    return (
      <Panel id="Header" hittest={false}>
        <Panel id="TitleHalo" hittest={false} />
        <Panel id="TitlePlaque" hittest={false} />
        <Panel id="TitleContent" hittest={false}>
          <Label id="Title" text={$.Localize("#addon_game_name")} />
          <Label id="MapName" text={OSC.Localized("osc_ts_map", { map: map })} />
        </Panel>
      </Panel>
    );
  }

  // ================= Таймер =================

  function ReadTimer() {
    var transition = Game.GetStateTransitionTime();
    return {
      transition: transition,
      left: transition < 0 ? -1 : Math.max(0, transition - Game.GetGameTime()),
    };
  }

  function Timer() {
    var timer = OSC.usePolled(ReadTimer, CFG.timerPoll);
    // Полное время — с момента, когда таймер запущен или перезапущен
    var total = React.useRef({ transition: -1, left: 0 });
    if (timer.transition !== total.current.transition) {
      total.current = { transition: timer.transition, left: timer.left };
    }

    var idle = timer.transition < 0;
    var long = timer.left >= 60;
    var deg = idle ? 360 : total.current.left > 0 ? (360 * timer.left) / total.current.left : 0;
    return (
      <Panel
        id="TimerWrap"
        className={OSC.Util.Classes(
          idle && "Idle",
          !idle && timer.left <= CFG.urgentSeconds && "Urgent",
        )}
        hittest={false}
      >
        <Panel id="RingBox" hittest={false}>
          <Panel id="TimerFrame" hittest={false} />
          <Panel id="TimerTrack" hittest={false} />
          <Panel
            id="TimerRing"
            hittest={false}
            style={{ clip: "radial(50% 50%, 0deg, " + deg.toFixed(1) + "deg)" }}
          />
          <Label
            id="TimerText"
            className={OSC.Util.Classes(!idle && long && "Long")}
            text={
              idle ? "∞" : long ? OSC.Util.FormatTime(timer.left) : String(Math.ceil(timer.left))
            }
          />
        </Panel>
        <Label
          id="TimerCaption"
          text={$.Localize(idle ? "#osc_ts_timer_waiting" : "#osc_ts_timer_caption")}
        />
      </Panel>
    );
  }

  // ================= Кнопки =================

  function Footer(props: { view: TeamView; host: boolean; unassigned: number; inTeam: boolean }) {
    var locked = props.view.locked;
    return (
      <Panel id="Footer">
        <Label id="LockedBanner" text={$.Localize("#osc_ts_locked_banner")} />
        <Panel id="FooterDivider" hittest={false} />
        <Panel id="HostControls">
          {props.inTeam && !locked && (
            <Button id="LeaveButton" className="LBButton Ghost" onactivate={Actions.leave}>
              <Label text={$.Localize("#osc_ts_btn_leave")} />
            </Button>
          )}
          {props.host && (
            <>
              <Button
                id="ShuffleButton"
                className="LBButton Ghost"
                enabled={!locked}
                onactivate={Actions.shuffle}
              >
                <Label text={$.Localize("#osc_ts_btn_shuffle")} />
              </Button>
              <Button
                id="StartButton"
                className={OSC.Util.Classes("LBButton Primary", locked && "Cancel")}
                enabled={locked || props.unassigned === 0}
                onactivate={Actions.toggleStart}
              >
                <Label text={$.Localize(locked ? "#osc_ts_btn_cancel" : "#osc_ts_btn_start")} />
              </Button>
            </>
          )}
        </Panel>
        {props.host && !locked && <Label id="HostHint" text={$.Localize("#osc_ts_host_hint")} />}
      </Panel>
    );
  }

  // ================= Экран =================

  function App() {
    Render = OSC.useRerender();
    var narrow = OSC.usePolled(IsNarrow, 0.5);
    narrowNow = narrow;

    var host = IsHost();
    var locked = Game.GetTeamSelectionLocked();
    var view: TeamView = {
      localTeam: LocalTeam(),
      localId: Players.GetLocalPlayer(),
      locked: locked,
      canDrag: host && !locked,
    };
    var unassigned = Game.GetUnassignedPlayerIDs().length;
    var teams = Game.GetAllTeamIDs();

    // Пузыри орбиты — не React: синхронизируем после каждой отрисовки
    React.useEffect(function () {
      Lobby.refresh(view.localId, view.canDrag);
    });

    return (
      <Panel
        id="LBRoot"
        className={OSC.Util.Classes(narrow && "Narrow", locked && "Locked")}
        hittest={true}
      >
        <Backdrop />

        {/* Центральная колонка: заголовок, команды, кнопки. Все дети выровнены
            по центру, поэтому раскладка симметрична на любом соотношении сторон */}
        <Panel id="Main" hittest={false}>
          <Header />
          <Panel id="TeamsRow">
            {TEAM_CONTAINERS.map(function (id, index) {
              var teamId = teams[index];
              return (
                <React.Fragment key={id}>
                  {index > 0 && <Panel id="TeamGap" />}
                  <Panel id={id} className="TeamSlot">
                    {teamId !== undefined && (
                      <TeamCard
                        teamId={teamId}
                        view={view}
                        onJoin={function () {
                          Actions.join(teamId);
                        }}
                      />
                    )}
                  </Panel>
                </React.Fragment>
              );
            })}
          </Panel>
          <Footer
            view={view}
            host={host}
            unassigned={unassigned}
            inTeam={teams.indexOf(view.localTeam as DOTATeam_t) >= 0}
          />
        </Panel>

        <Timer />

        {/* Игроки без команды: орбита в правом нижнем углу, пузыри — Lobby */}
        <Panel id="Lobby" className={OSC.Util.Classes(unassigned === 0 && "Empty")} hittest={false}>
          <Panel id="Orbit" hittest={false}>
            <Panel id="OrbitRing" hittest={false} />
            <Panel id="OrbitCenter" hittest={false}>
              <Label id="LobbyCount" text={String(unassigned)} />
            </Panel>
            <Panel id="OrbitItems" />
          </Panel>
          <Label id="LobbyTitle" text={$.Localize("#osc_ts_lobby_title")} />
        </Panel>

        {/* Последний слой: сюда переносится родной чат Dota (Chat) */}
        <Panel id="ChatLayer" hittest={false}>
          <Panel
            id="ChatFrame"
            className={OSC.Util.Classes(!chatReady && "Hidden")}
            hittest={false}
          >
            <Panel id="ChatAccent" hittest={false} />
          </Panel>
        </Panel>
      </Panel>
    );
  }

  // ================= Цикл =================

  var lastFrame = Date.now();

  function Tick() {
    if (SetupOver()) {
      Container.restore();
      Chat.restore();
      return false; // останавливает OSC.Util.Loop
    }

    var now = Date.now();
    var dt = Math.min(0.1, (now - lastFrame) / 1000);
    lastFrame = now;

    Lobby.tick(dt);
    Chat.sync(narrowNow);
    return true;
  }

  export function Init() {
    Container.fix();
    // Корень разметки (.TeamSelectContext) — сама контекстная панель: id у корня запрещён
    ReactPanorama.render(<App />, $.GetContextPanel());

    OSC.Util.Loop(CFG.tick, Tick);
    Chat.attach(
      function () {
        return narrowNow;
      },
      function () {
        chatReady = true;
        Render();
      },
    );

    $.RegisterForUnhandledEvent("DOTAGame_TeamPlayerListChanged", function () {
      Render();
    });
    $.RegisterForUnhandledEvent("DOTAGame_PlayerDetailsChanged", function () {
      Render();
    });
  }
}

// Свой контекст GameSetup — инициализируемся здесь
OSC.TeamSelect.Init();
