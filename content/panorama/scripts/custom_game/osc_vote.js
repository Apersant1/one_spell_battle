"use strict";

var OSC = OSC || {};

// Голосование на экране выбора героев. Состояние — osc_state/vote (вопросы,
// счётчики, итог), свой голос — osc_state/vote_<playerID>. Клик отправляет
// osc_vote_cast; сервер отказывает молча, поэтому подсветка оптимистичная
// и сверяется с vote_<playerID> (как выбор из трёх).
OSC.Vote = (function () {
  // Ключи вопросов и вариантов собираются из id с сервера:
  // osc_hud_vote_q_<question>, osc_hud_vote_opt_<question>_<option>
  var HUD_KEY = "osc_hud";
  var CONFIRM_TIMEOUT = 1.0; // ждём подтверждения голоса в vote_<playerID>
  var RESULT_SHOW_TIME = 6; // сколько показывать итог после закрытия
  var STATE_POLL = 0.25;

  var vote = null; // osc_state/vote
  var serverVotes = {}; // osc_state/vote_<playerID>
  var localVotes = {}; // question -> { option, pending: [] } до подтверждения
  var confirmHandles = {};
  var builtSignature = "";
  var wasOpen = false;
  var resultHandle = null;
  var resultDone = false;

  function GameState() {
    return Game.GetState();
  }

  function MyVotesKey() {
    return "vote_" + Players.GetLocalPlayer();
  }

  function LocalizeOr(suffix, fallback) {
    var token = "#" + HUD_KEY + "_" + suffix;
    var text = $.Localize(token);
    return text && text !== token ? text : fallback;
  }

  // Lua-таблица { "1": x, "2": y } -> массив по возрастанию ключей
  function SortedValues(raw) {
    if (!raw) return [];
    return Object.keys(raw)
      .sort(function (a, b) {
        return Number(a) - Number(b);
      })
      .map(function (key) {
        return raw[key];
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

  function HasResult() {
    return !!vote && !!vote.result && Object.keys(vote.result).length > 0;
  }

  function CurrentVote(question) {
    var local = localVotes[question];
    if (local) return local.option;
    return serverVotes && serverVotes[question] ? String(serverVotes[question]) : "";
  }

  // ================= Подтверждение голоса =================
  function CancelConfirm(question) {
    if (confirmHandles[question] !== undefined) {
      $.CancelScheduled(confirmHandles[question]);
      delete confirmHandles[question];
    }
  }

  function DropLocal(question) {
    CancelConfirm(question);
    delete localVotes[question];
  }

  function DropAllLocal() {
    for (var question in localVotes) DropLocal(question);
  }

  // Подтверждения не было: верим vote_<playerID>
  function OnConfirmTimeout(question) {
    delete confirmHandles[question];
    serverVotes = CustomNetTables.GetTableValue("osc_state", MyVotesKey()) || {};
    delete localVotes[question];
    Refresh();
  }

  function OnMyVotes(data) {
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

  function Cast(question, option) {
    if (!IsOpen() || GameState() !== DOTA_GameState.DOTA_GAMERULES_STATE_HERO_SELECTION) return;
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
  function CreateOption(row, question, option, isDefault) {
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

  function Build(questions) {
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

  function Signature(questions) {
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

    var counts = (vote && vote.counts) || {};
    var result = (vote && vote.result) || {};
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
        button.GetChild(button.GetChildCount() - 1).text = String(count);
        button.SetHasClass("Picked", CurrentVote(question) === option);
        button.SetHasClass("Winner", result[question] !== undefined && String(result[question]) === option);
      }
    }
  }

  // ================= Видимость =================
  function SetMode(visible, closed) {
    var panel = $("#VotePanel");
    panel.SetHasClass("Visible", visible);
    panel.SetHasClass("Closed", closed);
    $("#VoteTitle").text = $.Localize(closed ? "#osc_hud_vote_result_title" : "#osc_hud_vote_title");
    $("#VoteHint").text = closed ? "" : $.Localize("#osc_hud_vote_hint");
    $("#VoteHint").SetHasClass("Hidden", closed);
  }

  function ShowResult() {
    if (resultHandle !== null || resultDone) return;
    DropAllLocal();
    Refresh();
    SetMode(true, true);
    resultHandle = $.Schedule(RESULT_SHOW_TIME, function () {
      resultHandle = null;
      resultDone = true;
      SetMode(false, true);
    });
  }

  function Update() {
    var state = GameState();
    if (state >= DOTA_GameState.DOTA_GAMERULES_STATE_PRE_GAME) {
      if (resultHandle !== null) {
        $.CancelScheduled(resultHandle);
        resultHandle = null;
      }
      SetMode(false, false);
      return false; // экран выбора героев закрыт — голосование больше не нужно
    }

    var inPick = state === DOTA_GameState.DOTA_GAMERULES_STATE_HERO_SELECTION;
    if (IsOpen() && inPick) {
      wasOpen = true;
      resultDone = false;
      SetMode(true, false);
    } else if (wasOpen && !IsOpen() && HasResult()) {
      ShowResult();
    } else if (wasOpen && IsOpen()) {
      // Выбор героев кончился, а сервер ещё не закрыл голосование —
      // окно не прячем, чтобы итог не мигал
    } else if (resultHandle === null) {
      // Голосование не открыто (или выбор героев уже кончился, а сервер ещё
      // не прислал итог) — держим окно скрытым
      SetMode(false, false);
    }
  }

  function OnNetTableChanged(tableName, key, data) {
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
    Refresh();
    OSC.Util.Loop(STATE_POLL, Update);
  }

  return { Init: Init };
})();

OSC.Vote.Init();
