namespace OSC {
  // Голосование на экране выбора героев (React). Состояние — osc_state/vote
  // (вопросы, счётчики, итог), свой голос — osc_state/vote_<playerID>. Клик
  // отправляет osc_vote_cast; сервер отказывает молча, поэтому подсветка
  // оптимистичная и сверяется с vote_<playerID> (как выбор из трёх).
  type VoteQuestion = { id: string; options: string[]; def: string };
  // question -> последний клик и все неподтверждённые клики по порядку
  type LocalVotes = Record<string, { option: string; pending: string[] }>;

  export const Vote = (function () {
    // Ключи вопросов и вариантов собираются из id с сервера:
    // osc_hud_vote_q_<question>, osc_hud_vote_opt_<question>_<option>
    var CONFIRM_TIMEOUT = 1.0; // ждём подтверждения голоса в vote_<playerID>
    var STATE_POLL = 0.25;

    function MyVotesKey(): `vote_${number}` {
      return `vote_${Players.GetLocalPlayer()}`;
    }

    function Questions(vote: NetworkedData<OSCVoteState> | null): VoteQuestion[] {
      return OSC.Util.LuaArray(vote && vote.questions)
        .filter(function (q) {
          return q && q.id;
        })
        .map(function (q) {
          return {
            id: String(q.id),
            options: OSC.Util.LuaArray(q.options).map(String),
            def: q["default"] !== undefined ? String(q["default"]) : "",
          };
        });
    }

    function Without(votes: LocalVotes, question: string) {
      var next = Object.assign({}, votes);
      delete next[question];
      return next;
    }

    // Сервер держит голосование открытым от выбора героев до PRE_GAME (включая
    // стадию стратегии). Итог после закрытия уходит в ленту уведомлений HUD:
    // на PRE_GAME экран выбора героев вместе с этим окном уже скрыт.
    function IsBeforePreGame() {
      return Game.GetState() < DOTA_GameState.DOTA_GAMERULES_STATE_PRE_GAME;
    }

    function VoteWindow() {
      var vote = ReactPanorama.useNetTableKey("osc_state", "vote");
      var myVotes = ReactPanorama.useNetTableKey("osc_state", MyVotesKey());
      var serverVotes: Record<string, string> = myVotes || {};
      var [local, setLocal] = React.useState<LocalVotes>({});
      var [collapsed, setCollapsed] = React.useState(false);
      var timers = React.useRef<Record<string, ScheduleID>>({});
      // Опрос стадии игры, пока не наступит PRE_GAME
      var beforePreGame = OSC.usePolled(IsBeforePreGame, STATE_POLL, true, function (before) {
        return !before;
      });
      var visible = !!vote && Number(vote.open) === 1 && beforePreGame;

      function ServerVote(question: string) {
        return serverVotes[question] ? String(serverVotes[question]) : "";
      }

      function DropLocal(question: string) {
        if (timers.current[question] !== undefined) {
          $.CancelScheduled(timers.current[question]);
          delete timers.current[question];
        }
        setLocal(function (prev) {
          return Without(prev, question);
        });
      }

      // Пришёл vote_<playerID>: принятые клики снимаем, отклонённые откатываем к
      // голосу сервера; совпал с более ранним кликом или пуст — ждём, решит таймаут
      React.useEffect(
        function () {
          Object.keys(local).forEach(function (question) {
            var server = ServerVote(question);
            var mine = local[question];
            if (server === mine.option || (server !== "" && mine.pending.indexOf(server) < 0)) {
              DropLocal(question);
            }
          });
        },
        [myVotes],
      );

      function Cast(question: string, option: string) {
        if (!visible) return;
        setLocal(function (prev) {
          var next = Object.assign({}, prev);
          var pending = prev[question] ? prev[question].pending : [];
          next[question] = { option: option, pending: pending.concat(option) };
          return next;
        });
        if (timers.current[question] !== undefined) $.CancelScheduled(timers.current[question]);
        // Подтверждения не было: верим vote_<playerID>
        timers.current[question] = $.Schedule(CONFIRM_TIMEOUT, function () {
          delete timers.current[question];
          DropLocal(question);
        });
        GameEvents.SendCustomGameEventToServer("osc_vote_cast", {
          question: question,
          option: option,
        });
      }

      var counts: Record<string, Record<string, number>> = (vote && vote.counts) || {};

      return (
        <Panel
          id="VotePanel"
          className={OSC.Util.Classes(visible && "Visible", collapsed && "Collapsed")}
          hittest={true}
        >
          {/* Клик по заголовку сворачивает окно, если оно что-то закрывает */}
          <Button
            id="VoteHeader"
            onactivate={function () {
              setCollapsed(!collapsed);
            }}
          >
            <Label
              id="VoteTitle"
              className="OSCTextBody OSCCaps OSCBold OSCChaosText"
              hittest={false}
              text={$.Localize("#osc_hud_vote_title")}
            />
            <Label
              id="VoteCollapse"
              className="OSCTextBody OSCBold OSCChaosText"
              hittest={false}
              text={collapsed ? "+" : "-"}
            />
          </Button>
          <Panel id="VoteQuestions" hittest={false}>
            {Questions(vote).map(function (question) {
              var picked = local[question.id] ? local[question.id].option : ServerVote(question.id);
              var questionCounts = counts[question.id] || {};
              return (
                <Panel key={question.id} className="VoteQuestion" hittest={false}>
                  <Label
                    className="VoteQuestionTitle OSCTextSmall OSCBold"
                    hittest={false}
                    text={OSC.Util.LocalizeOr("#osc_hud_vote_q_" + question.id, question.id)}
                  />
                  <Panel className="VoteOptions" hittest={false}>
                    {question.options.map(function (option) {
                      return (
                        <Button
                          key={option}
                          className={OSC.Util.Classes("VoteOption", picked === option && "Picked")}
                          onactivate={function () {
                            Cast(question.id, option);
                          }}
                        >
                          <Label
                            className="VoteOptionName"
                            hittest={false}
                            text={OSC.Util.LocalizeOr(
                              "#osc_hud_vote_opt_" + question.id + "_" + option,
                              option,
                            )}
                          />
                          {option === question.def && (
                            <Panel className="VoteDefaultMark" hittest={false} />
                          )}
                          <Label
                            className="VoteOptionCount"
                            hittest={false}
                            text={String(Number(questionCounts[option]) || 0)}
                          />
                        </Button>
                      );
                    })}
                  </Panel>
                </Panel>
              );
            })}
          </Panel>
          <Label
            id="VoteHint"
            className="OSCMuted"
            hittest={false}
            text={$.Localize("#osc_hud_vote_hint")}
          />
        </Panel>
      );
    }

    function Init() {
      // Корень разметки (.VoteRoot) — сама контекстная панель: id у корня запрещён
      ReactPanorama.render(<VoteWindow />, $.GetContextPanel());
    }

    return { Init: Init };
  })();
}

OSC.Vote.Init();
