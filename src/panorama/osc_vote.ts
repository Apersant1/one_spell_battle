namespace OSC {
  // Голосование на экране выбора героев. Состояние — osc_state/vote (вопросы,
  // счётчики, итог), свой голос — osc_state/vote_<playerID>. Клик отправляет
  // osc_vote_cast; сервер отказывает молча, поэтому подсветка оптимистичная
  // и сверяется с vote_<playerID> (как выбор из трёх).
  type VoteQuestion = { id: string; options: string[]; def: string };

  export const Vote = (function () {
    // Ключи вопросов и вариантов собираются из id с сервера:
    // osc_hud_vote_q_<question>, osc_hud_vote_opt_<question>_<option>
    var HUD_KEY = "osc_hud";
    var CONFIRM_TIMEOUT = 1.0; // ждём подтверждения голоса в vote_<playerID>
    var STATE_POLL = 0.25;

    var vote: NetworkedData<OSCVoteState> | null = null; // osc_state/vote
    var serverVotes: Record<string, string> = {}; // osc_state/vote_<playerID>
    var localVotes: Record<string, { option: string; pending: string[] }> = {}; // question -> { option, pending: [] } до подтверждения
    var confirmHandles: Record<string, ScheduleID> = {};
    var builtSignature = "";
    var collapsed = false; // игрок свернул окно, чтобы не мешало экрану выбора

    function GameState() {
      return Game.GetState();
    }

    function MyVotesKey(): `vote_${number}` {
      return `vote_${Players.GetLocalPlayer()}`;
    }

    function LocalizeOr(suffix: string, fallback: string) {
      var token = "#" + HUD_KEY + "_" + suffix;
      var text = $.Localize(token);
      return text && text !== token ? text : fallback;
    }

    // Lua-таблица { "1": x, "2": y } -> массив по возрастанию ключей
    function SortedValues<T>(raw: { [key: number]: T } | null | undefined): T[] {
      if (!raw) return [];
      return Object.keys(raw)
        .sort(function (a, b) {
          return Number(a) - Number(b);
        })
        .map(function (key) {
          return raw[Number(key)];
        });
    }

    function Questions() {
      return SortedValues(vote && vote.questions)
        .filter(function (q) {
          return q && q.id;
        })
        .map(function (q) {
          return {
            id: String(q.id),
            options: SortedValues(q.options).map(String),
            def: q["default"] !== undefined ? String(q["default"]) : "",
          };
        });
    }

    function IsOpen() {
      return !!vote && Number(vote.open) === 1;
    }

    function CurrentVote(question: string) {
      var local = localVotes[question];
      if (local) return local.option;
      return serverVotes && serverVotes[question] ? String(serverVotes[question]) : "";
    }

    // ================= Подтверждение голоса =================
    function CancelConfirm(question: string) {
      if (confirmHandles[question] !== undefined) {
        $.CancelScheduled(confirmHandles[question]);
        delete confirmHandles[question];
      }
    }

    function DropLocal(question: string) {
      CancelConfirm(question);
      delete localVotes[question];
    }

    // Подтверждения не было: верим vote_<playerID>
    function OnConfirmTimeout(question: string) {
      delete confirmHandles[question];
      serverVotes = CustomNetTables.GetTableValue("osc_state", MyVotesKey()) || {};
      delete localVotes[question];
      Refresh();
    }

    function OnMyVotes(data: Record<string, string> | null) {
      serverVotes = data || {};
      for (var question in localVotes) {
        var local = localVotes[question];
        var server = serverVotes[question] ? String(serverVotes[question]) : "";
        if (server === local.option) {
          DropLocal(question); // принят
        } else if (server !== "" && local.pending.indexOf(server) < 0) {
          DropLocal(question); // отклонён — откат к голосу сервера
        }
        // совпал с более ранним кликом или пуст — ждём, решит таймаут
      }
      Refresh();
    }

    function Cast(question: string, option: string) {
      if (!IsVisible()) return;
      var local = localVotes[question] || { option: "", pending: [] };
      local.option = option;
      local.pending.push(option);
      localVotes[question] = local;
      CancelConfirm(question);
      confirmHandles[question] = $.Schedule(CONFIRM_TIMEOUT, function () {
        OnConfirmTimeout(question);
      });
      Refresh();
      GameEvents.SendCustomGameEventToServer("osc_vote_cast", {
        question: question,
        option: option,
      });
    }

    // ================= Разметка =================
    function CreateOption(row: Panel, question: VoteQuestion, option: string, isDefault: boolean) {
      var button = $.CreatePanel("Button", row, "");
      button.AddClass("VoteOption");
      button.SetAttributeString("osc_question", question.id);
      button.SetAttributeString("osc_option", option);

      var name = $.CreatePanel("Label", button, "");
      name.AddClass("VoteOptionName");
      name.text = LocalizeOr("vote_opt_" + question.id + "_" + option, option);
      name.hittest = false;

      if (isDefault) {
        var mark = $.CreatePanel("Panel", button, "");
        mark.AddClass("VoteDefaultMark");
        mark.hittest = false;
      }

      var count = $.CreatePanel("Label", button, "");
      count.AddClass("VoteOptionCount");
      count.text = "0";
      count.hittest = false;

      button.SetPanelEvent("onactivate", function () {
        Cast(question.id, option);
      });
    }

    function Build(questions: VoteQuestion[]) {
      var container = $("#VoteQuestions");
      container.RemoveAndDeleteChildren();
      questions.forEach(function (question) {
        var block = $.CreatePanel("Panel", container, "");
        block.AddClass("VoteQuestion");
        block.hittest = false;

        var title = $.CreatePanel("Label", block, "");
        title.AddClass("VoteQuestionTitle");
        title.AddClass("OSCTextSmall");
        title.AddClass("OSCBold");
        title.text = LocalizeOr("vote_q_" + question.id, question.id);
        title.hittest = false;

        var row = $.CreatePanel("Panel", block, "");
        row.AddClass("VoteOptions");
        row.hittest = false;
        question.options.forEach(function (option) {
          CreateOption(row, question, option, option === question.def);
        });
      });
    }

    function Signature(questions: VoteQuestion[]) {
      return questions
        .map(function (q) {
          return q.id + ":" + q.options.join("|") + ":" + q.def;
        })
        .join(";");
    }

    // Обновляет счётчики и подсветку, не пересоздавая кнопки
    function Refresh() {
      var questions = Questions();
      var signature = Signature(questions);
      if (signature !== builtSignature) {
        builtSignature = signature;
        Build(questions);
      }

      var counts: Record<string, Record<string, number>> = (vote && vote.counts) || {};
      var blocks = $("#VoteQuestions").Children();
      for (var b = 0; b < blocks.length; b++) {
        var row = blocks[b].GetChild(1);
        if (!row) continue;
        var buttons = row.Children();
        for (var i = 0; i < buttons.length; i++) {
          var button = buttons[i];
          var question = button.GetAttributeString("osc_question", "");
          var option = button.GetAttributeString("osc_option", "");
          var questionCounts = counts[question] || {};
          var count = Number(questionCounts[option]) || 0;
          (button.GetChild(button.GetChildCount() - 1) as LabelPanel).text = String(count);
          button.SetHasClass("Picked", CurrentVote(question) === option);
        }
      }
    }

    // ================= Видимость =================
    // Сервер держит голосование открытым от выбора героев до PRE_GAME (включая
    // стадию стратегии). Итог после закрытия уходит в ленту уведомлений HUD:
    // на PRE_GAME экран выбора героев вместе с этим окном уже скрыт.
    function IsVisible() {
      return IsOpen() && GameState() < DOTA_GameState.DOTA_GAMERULES_STATE_PRE_GAME;
    }

    function Update() {
      var visible = IsVisible();
      var panel = $("#VotePanel");
      panel.SetHasClass("Visible", visible);
      panel.SetHasClass("Collapsed", collapsed);
      ($("#VoteCollapse") as LabelPanel).text = collapsed ? "+" : "-";
      // Экран выбора героев закрыт — голосование больше не нужно
      if (GameState() >= DOTA_GameState.DOTA_GAMERULES_STATE_PRE_GAME) return false;
    }

    function ToggleCollapsed() {
      collapsed = !collapsed;
      Update();
    }

    function OnNetTableChanged(tableName: string, key: string, data: any) {
      if (key === "vote") {
        vote = data;
        Refresh();
        Update();
      } else if (key === MyVotesKey()) {
        OnMyVotes(data);
      }
    }

    function Init() {
      CustomNetTables.SubscribeNetTableListener("osc_state", OnNetTableChanged);
      // Переподключение / поздняя загрузка: читаем текущее состояние
      vote = CustomNetTables.GetTableValue("osc_state", "vote");
      serverVotes = CustomNetTables.GetTableValue("osc_state", MyVotesKey()) || {};
      ($("#VoteTitle") as LabelPanel).text = $.Localize("#osc_hud_vote_title");
      ($("#VoteHint") as LabelPanel).text = $.Localize("#osc_hud_vote_hint");
      Refresh();
      OSC.Util.Loop(STATE_POLL, Update);
    }

    return {
      Init: Init,
      ToggleCollapsed: ToggleCollapsed, // вызывается из XML
    };
  })();
}

OSC.Vote.Init();
