"use strict";

var OSC = OSC || {};

OSC.TeamSelect = (function () {
  var TIMER_TICK = 0.03;
  var URGENT_SECONDS = 5; // с этого момента кольцо краснеет и пульсирует
  var LOCK_COUNTDOWN = 4; // секунд до старта после "Начать игру"
  var DEFAULT_COLOR = "#E0C27A";

  var CHAT_SEARCH_INTERVAL = 0.25;
  var CHAT_SEARCH_ATTEMPTS = 20; // ~5 секунд
  var CHAT_MARGIN = "0px 0px 24px 24px";

  var TEAM_THEME = {};
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_GOODGUYS] = {
    name: "Силы Света",
    color: "#5BE38A",
  };
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_BADGUYS] = {
    name: "Силы Тьмы",
    color: "#FF5A4E",
  };
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_CUSTOM_1] = {
    name: "Буря",
    color: "#4FB3FF",
  };
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_CUSTOM_2] = {
    name: "Пламя",
    color: "#FFB347",
  };
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_CUSTOM_3] = {
    name: "Пустота",
    color: "#B57CFF",
  };
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_CUSTOM_4] = {
    name: "Мороз",
    color: "#7FE7F2",
  };

  var cards = {};
  var lastLocalTeam = -2;
  var lastTransition = -1;
  var timerTotal = 0;

  var nativeChat = null;
  var nativeChatParent = null;
  var uiContainer = null;
  // ---------- утилиты ----------

  function GetTheme(teamId) {
    return (
      TEAM_THEME[teamId] || {
        name: $.Localize(Game.GetTeamDetails(teamId).team_name),
        color: DEFAULT_COLOR,
      }
    );
  }

  function IsHost() {
    var info = Game.GetLocalPlayerInfo();
    return !!(info && info.player_has_host_privileges);
  }

  function GetLocalTeam() {
    var info = Game.GetLocalPlayerInfo();
    return info ? info.player_team_id : -1;
  }

  function IsSetupPhase() {
    return (
      Game.GetState() === DOTA_GameState.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
    );
  }

  function MakeLabel(parent, cls, text) {
    var label = $.CreatePanel("Label", parent, "");
    label.AddClass(cls);
    label.text = text;
    return label;
  }

  function VerticalGradient(color) {
    return (
      "gradient(linear, 0% 0%, 0% 100%, from(" + color + "), to(#00000000))"
    );
  }

  function HorizontalGradient(color) {
    return (
      "gradient(linear, 0% 0%, 100% 0%, from(" + color + "), to(#00000000))"
    );
  }

  function GetTopPanel() {
    var panel = $.GetContextPanel();
    while (panel.GetParent() !== null) panel = panel.GetParent();
    return panel;
  }

  // ---------- карточки (строятся один раз) ----------

  function BuildCard(row, teamId) {
    var theme = GetTheme(teamId);

    var card = $.CreatePanel("Button", row, "");
    card.AddClass("TeamCard");
    card.SetPanelEvent("onactivate", function () {
      OnTeamClicked(teamId);
    });

    var glow = $.CreatePanel("Panel", card, "");
    glow.AddClass("CardGlow");
    glow.style.backgroundColor = VerticalGradient(theme.color + "38");

    var body = $.CreatePanel("Panel", card, "");
    body.AddClass("CardBody");

    var head = $.CreatePanel("Panel", body, "");
    head.AddClass("CardHeader");

    var bar = $.CreatePanel("Panel", head, "");
    bar.AddClass("ColorBar");
    bar.style.backgroundColor = theme.color;

    MakeLabel(head, "TeamName", theme.name).style.color = theme.color;
    var count = MakeLabel(head, "TeamCount", "");

    var divider = $.CreatePanel("Panel", body, "");
    divider.AddClass("Divider");
    divider.style.backgroundColor = HorizontalGradient(theme.color + "aa");

    var list = $.CreatePanel("Panel", body, "");
    list.AddClass("SlotList");

    var hint = MakeLabel(body, "JoinHint", "");

    cards[teamId] = {
      card: card,
      list: list,
      count: count,
      hint: hint,
      theme: theme,
    };
  }

  function BuildCards() {
    var row = $("#TeamsRow");
    var teams = Game.GetAllTeamIDs();

    row.RemoveAndDeleteChildren();
    cards = {};
    $("#LBRoot").SetHasClass("ManyTeams", teams.length > 2);

    teams.forEach(function (teamId, i) {
      if (i > 0 && teams.length === 2) MakeLabel(row, "VS", "VS");
      BuildCard(row, teamId);
    });
  }

  // ---------- слоты и неопределившиеся ----------

  function BuildSlot(parent, playerId, theme, localPlayerId, animate) {
    var slot = $.CreatePanel("Panel", parent, "");
    slot.AddClass("Slot");

    if (playerId === undefined) {
      slot.AddClass("Empty");
      $.CreatePanel("Panel", slot, "").AddClass("AvatarPlaceholder");
      MakeLabel(slot, "SlotName", "Свободный слот");
      return;
    }

    var info = Game.GetPlayerInfo(playerId);
    var isLocal = playerId === localPlayerId;

    slot.AddClass("Filled");
    slot.SetHasClass("Local", isLocal);
    slot.SetHasClass("Pop", isLocal && animate);
    if (isLocal)
      slot.style.backgroundColor = HorizontalGradient(theme.color + "33");

    var avatar = $.CreatePanel("DOTAAvatarImage", slot, "");
    avatar.AddClass("Avatar");
    avatar.steamid = info.player_steamid;
    avatar.style.borderColor = theme.color + "cc";

    MakeLabel(slot, "SlotName", info.player_name);
    if (info.player_has_host_privileges) MakeLabel(slot, "HostBadge", "ХОСТ");
  }

  function RefreshCard(teamId, localTeam, localPlayerId, locked, justJoined) {
    var c = cards[teamId];
    var details = Game.GetTeamDetails(teamId);
    var players = Game.GetPlayerIDsOnTeam(teamId);
    var mine = localTeam === teamId;
    var full = details.team_num_players >= details.team_max_players;

    c.card.SetHasClass("Mine", mine);
    c.card.SetHasClass("Full", full && !mine);
    c.card.style.borderColor = mine ? c.theme.color : c.theme.color + "40";
    c.card.style.boxShadow = mine
      ? c.theme.color + "55 0px 0px 48px 4px"
      : "#000000aa 0px 12px 40px 0px";

    c.count.text = details.team_num_players + " / " + details.team_max_players;

    if (locked) c.hint.text = "КОМАНДЫ ЗАФИКСИРОВАНЫ";
    else if (mine) c.hint.text = "ВЫ В ЭТОЙ КОМАНДЕ";
    else if (full) c.hint.text = "МЕСТ НЕТ";
    else c.hint.text = "НАЖМИТЕ, ЧТОБЫ ВСТУПИТЬ";

    c.list.RemoveAndDeleteChildren();
    for (var s = 0; s < details.team_max_players; s++) {
      BuildSlot(c.list, players[s], c.theme, localPlayerId, justJoined && mine);
    }
  }

  function RefreshUnassigned(localPlayerId) {
    var ids = Game.GetUnassignedPlayerIDs();
    var list = $("#UnassignedList");

    $("#Unassigned").SetHasClass("Hidden", ids.length === 0);
    $("#UnassignedTitle").text = "НЕ ВЫБРАЛИ КОМАНДУ · " + ids.length;

    list.RemoveAndDeleteChildren();
    ids.forEach(function (playerId) {
      var info = Game.GetPlayerInfo(playerId);

      var chip = $.CreatePanel("Panel", list, "");
      chip.AddClass("Chip");
      chip.SetHasClass("Local", playerId === localPlayerId);

      var avatar = $.CreatePanel("DOTAAvatarImage", chip, "");
      avatar.AddClass("ChipAvatar");
      avatar.steamid = info.player_steamid;

      MakeLabel(chip, "ChipName", info.player_name);
    });
  }

  function RefreshButtons(locked) {
    $("#HostControls").SetHasClass("Hidden", !IsHost());
    $("#LBRoot").SetHasClass("Locked", locked);
    $("#StartLabel").text = locked ? "ОТМЕНА" : "НАЧАТЬ ИГРУ";
    $("#StartButton").SetHasClass("Cancel", locked);
    $("#StartButton").enabled =
      locked || Game.GetUnassignedPlayerIDs().length === 0;
    $("#ShuffleButton").enabled = !locked;
    $("#AutoButton").enabled = !locked;
  }

  function Refresh() {
    var localTeam = GetLocalTeam();
    var localPlayerId = Players.GetLocalPlayer();
    var locked = Game.GetTeamSelectionLocked();
    var justJoined = localTeam !== lastLocalTeam;

    lastLocalTeam = localTeam;

    for (var key in cards) {
      RefreshCard(Number(key), localTeam, localPlayerId, locked, justJoined);
    }
    RefreshUnassigned(localPlayerId);
    RefreshButtons(locked);
  }

  // ---------- действия ----------

  function OnTeamClicked(teamId) {
    if (Game.GetTeamSelectionLocked() || GetLocalTeam() === teamId) return;

    var details = Game.GetTeamDetails(teamId);
    if (details.team_num_players >= details.team_max_players) return;

    Game.PlayerJoinTeam(teamId);
    OSC.Util.PlaySound(OSC.Sounds.teamPick);
  }

  function OnShuffle() {
    GameEvents.SendCustomGameEventToServer("osc_team_shuffle", {});
    OSC.Util.PlaySound(OSC.Sounds.teamShuffle);
  }

  function OnAutoAssign() {
    Game.AutoAssignPlayersToTeams();
    OSC.Util.PlaySound(OSC.Sounds.teamAutoAssign);
  }

  function OnStartPressed() {
    if (Game.GetTeamSelectionLocked()) {
      Game.SetTeamSelectionLocked(false);
      Game.SetRemainingSetupTime(-1);
      OSC.Util.PlaySound(OSC.Sounds.teamCancel);
    } else {
      if (Game.GetUnassignedPlayerIDs().length > 0) return;
      Game.SetTeamSelectionLocked(true);
      Game.SetAutoLaunchEnabled(false);
      Game.SetRemainingSetupTime(LOCK_COUNTDOWN);
      OSC.Util.PlaySound(OSC.Sounds.teamLockStart);
    }
    Refresh();
  }

  // ---------- родной чат Dota ----------

  // Чат экрана настройки: DOTAChat с id "Chat" (HudChat — внутриигровой, его не трогаем)
  function FindNativeChat() {
    var queue = [GetTopPanel()];
    while (queue.length > 0) {
      var panel = queue.shift();
      if (panel.paneltype === "DOTAChat" && panel.id === "Chat") return panel;
      for (var i = 0; i < panel.GetChildCount(); i++)
        queue.push(panel.GetChild(i));
    }
    return null;
  }

  // Переносим чат в наш верхний слой, чтобы он был поверх экрана
  function BringChatToFront() {
    var attempts = 0;

    OSC.Util.Loop(CHAT_SEARCH_INTERVAL, function () {
      if (!IsSetupPhase()) return false;

      var chat = FindNativeChat();
      if (chat !== null) {
        nativeChat = chat;
        nativeChatParent = chat.GetParent();

        chat.SetParent($("#ChatLayer"));
        chat.style.align = "left bottom";
        chat.style.margin = CHAT_MARGIN;
        return false;
      }

      attempts++;
      if (attempts >= CHAT_SEARCH_ATTEMPTS) {
        $.Msg("[OSC] native chat not found");
        return false;
      }
      return true;
    });
  }

  // Возвращаем чат на место перед выбором героев
  function RestoreChat() {
    if (
      nativeChat !== null &&
      nativeChat.IsValid() &&
      nativeChatParent !== null &&
      nativeChatParent.IsValid()
    ) {
      nativeChat.style.align = null;
      nativeChat.style.margin = null;
      nativeChat.SetParent(nativeChatParent);
    }
    nativeChat = null;
    nativeChatParent = null;
  }

  // ---------- отступ контейнера Dota слева ----------

  // CustomUIContainer сдвинут на 35px под левую кнопку Dota — растягиваем на весь экран
  function FixLeftOffset() {
    var panel = $.GetContextPanel();
    while (panel !== null && panel.id !== "CustomUIContainer")
      panel = panel.GetParent();
    if (panel === null) return;

    uiContainer = panel;
    uiContainer.style.margin = "0px";
    uiContainer.style.padding = "0px";
    uiContainer.style.position = "0px 0px 0px";
    uiContainer.style.width = "100%";
  }

  function RestoreLeftOffset() {
    if (uiContainer !== null && uiContainer.IsValid()) {
      uiContainer.style.margin = null;
      uiContainer.style.padding = null;
      uiContainer.style.position = null;
      uiContainer.style.width = null;
    }
    uiContainer = null;
  }

  // ---------- таймер ----------

  function UpdateTimer() {
    if (!IsSetupPhase()) {
      RestoreLeftOffset();
      RestoreChat();
      return false; // останавливает OSC.Util.Loop
    }

    var transition = Game.GetStateTransitionTime();
    var wrap = $("#TimerWrap");
    var ring = $("#TimerRing");
    var text = $("#TimerText");

    if (transition >= 0) {
      var left = Math.max(0, transition - Game.GetGameTime());

      if (transition !== lastTransition) {
        // таймер запущен или перезапущен
        lastTransition = transition;
        timerTotal = left;
      }

      var deg = timerTotal > 0 ? (360 * left) / timerTotal : 0;
      ring.style.clip = "radial(50% 50%, 0deg, " + deg.toFixed(1) + "deg)";

      var long = left >= 60;
      text.text = long ? OSC.Util.FormatTime(left) : String(Math.ceil(left));
      text.SetHasClass("Long", long);

      wrap.SetHasClass("Urgent", left <= URGENT_SECONDS);
      wrap.SetHasClass("Idle", false);
    } else {
      lastTransition = -1;
      ring.style.clip = "radial(50% 50%, 0deg, 360deg)";
      text.text = "—";
      text.SetHasClass("Long", false);
      wrap.SetHasClass("Urgent", false);
      wrap.SetHasClass("Idle", true);
    }

    return true;
  }

  // ---------- инициализация ----------

  function BindButtons() {
    $("#ShuffleButton").SetPanelEvent("onactivate", OnShuffle);
    $("#AutoButton").SetPanelEvent("onactivate", OnAutoAssign);
    $("#StartButton").SetPanelEvent("onactivate", OnStartPressed);
  }

  function Init() {
    var map = Game.GetMapInfo();
    $("#MapName").text = "КАРТА: " + (map.map_display_name || "").toUpperCase();

    BindButtons();
    BuildCards();
    Refresh();
    OSC.Util.Loop(TIMER_TICK, UpdateTimer);
    BringChatToFront();
    FixLeftOffset();

    $.RegisterForUnhandledEvent("DOTAGame_TeamPlayerListChanged", Refresh);
    $.RegisterForUnhandledEvent("DOTAGame_PlayerDetailsChanged", Refresh);
  }

  return { Init: Init };
})();

// Свой контекст GameSetup — инициализируемся здесь
OSC.TeamSelect.Init();
