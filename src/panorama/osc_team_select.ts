"use strict";

var OSC = OSC || {};

OSC.TeamSelect = (function () {
  // =====================================================================
  // НАСТРОЙКИ
  // =====================================================================

  var CFG = {
    debug: false,
    tick: 0.03,
    urgentSeconds: 5, // с этого момента кольцо таймера краснеет
    lockCountdown: 4, // секунд до старта после «Начать игру»
    starCount: 90,
    defaultColor: "#E0C27A",
    narrowAspect: 1.6, // уже этого (16:10, 4:3) — компактная раскладка

    // Орбита игроков без команды. size / itemSize / radius
    // должны совпадать с #Orbit, .OrbitItem и #OrbitRing в CSS
    orbit: {
      size: 240,
      itemSize: 52,
      radius: 90,
      speed: 0.35, // радиан в секунду
      ease: 0.12, // плавность перестроения при входе/выходе игрока
    },

    pop: {
      lifetime: 0.5, // через сколько удалять панели эффекта
      droplets: 8,
      spread: 46, // как далеко разлетаются брызги, px
      ringSize: 52,
      dropSize: 8,
    },

    chat: {
      linesHeight: 300, // высота области сообщений, px
      searchInterval: 0.25,
      searchAttempts: 20, // ~5 секунд
      // = width и margin у #ChatFrame (обычный / Narrow)
      frame: { width: 380, left: 40, bottom: 36 },
      frameNarrow: { width: 300, left: 16, bottom: 20 },
      padding: { top: 12, side: 10, bottom: 8 }, // отступ чата внутри рамки
    },
  };

  var TEAM_THEME = {};
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_GOODGUYS] = {
    token: "osc_ts_team_light",
    color: "#45e0d0",
  };
  TEAM_THEME[DOTATeam_t.DOTA_TEAM_BADGUYS] = {
    token: "osc_ts_team_dark",
    color: "#FF4A5A",
  };

  // Карточки ставятся слева и справа; экран рассчитан на две команды
  var TEAM_CONTAINERS = ["#TeamLeft", "#TeamRight"];

  // =====================================================================
  // УТИЛИТЫ
  // =====================================================================

  var U = {
    // Локализация: токены лежат в resource/addon_<язык>.txt
    L: function (token) {
      return $.Localize("#" + token);
    },

    panel: function (parent, classes, type) {
      var p = $.CreatePanel(type || "Panel", parent, "");
      classes.split(" ").forEach(function (cls) {
        if (cls) p.AddClass(cls);
      });
      return p;
    },

    label: function (parent, classes, text) {
      var l = U.panel(parent, classes, "Label");
      l.text = text;
      return l;
    },

    avatar: function (parent, classes, steamId) {
      var a = U.panel(parent, classes, "DOTAAvatarImage");
      if (steamId) a.steamid = steamId;
      return a;
    },

    // Ставит панель так, чтобы её центр оказался в точке (cx, cy)
    placeAt: function (p, cx, cy, size) {
      p.style.position =
        (cx - size / 2).toFixed(1) +
        "px " +
        (cy - size / 2).toFixed(1) +
        "px 0px";
    },

    hGradient: function (color) {
      return (
        "gradient(linear, 0% 0%, 100% 0%, from(" + color + "), to(#00000000))"
      );
    },

    sound: function (name) {
      if (OSC.Sounds && OSC.Sounds[name]) OSC.Util.PlaySound(OSC.Sounds[name]);
    },

    isHost: function () {
      var info = Game.GetLocalPlayerInfo();
      return !!(info && info.player_has_host_privileges);
    },

    localTeam: function () {
      var info = Game.GetLocalPlayerInfo();
      return info ? info.player_team_id : -1;
    },

    isSetupPhase: function () {
      return (
        Game.GetState() ===
        DOTA_GameState.DOTA_GAMERULES_STATE_CUSTOM_GAME_SETUP
      );
    },

    topPanel: function () {
      var p = $.GetContextPanel();
      while (p.GetParent() !== null) p = p.GetParent();
      return p;
    },
  };

  // =====================================================================
  // АДАПТИВНОСТЬ
  // =====================================================================

  var Layout = (function () {
    var narrow = null;

    function update() {
      if (typeof Game.GetScreenWidth !== "function") return;
      var h = Game.GetScreenHeight();
      if (!h) return;

      var isNarrow = Game.GetScreenWidth() / h < CFG.narrowAspect;
      if (isNarrow === narrow) return;

      narrow = isNarrow;
      $("#LBRoot").SetHasClass("Narrow", narrow);
    }

    return {
      update: update,
      isNarrow: function () {
        return narrow === true;
      },
    };
  })();

  // =====================================================================
  // ФОН
  // =====================================================================

  function BuildStars() {
    var layer = $("#Stars");
    for (var i = 0; i < CFG.starCount; i++) {
      var star = U.panel(layer, "Star");
      var size = 1 + Math.floor(Math.random() * 3);
      star.style.width = size + "px";
      star.style.height = size + "px";
      star.style.position =
        (Math.random() * 100).toFixed(2) +
        "% " +
        (Math.random() * 100).toFixed(2) +
        "% 0px";
      star.style.animationDuration = (2 + Math.random() * 4).toFixed(2) + "s";
      star.style.animationDelay = (Math.random() * 4).toFixed(2) + "s";
    }
  }

  function SetMapName() {
    var map = Game.GetMapInfo();
    var label = $("#MapName");
    label.SetDialogVariable("map", (map.map_display_name || "").toUpperCase());
    label.text = $.Localize("#osc_ts_map", label);
  }

  // =====================================================================
  // ДЕЙСТВИЯ ИГРОКА
  // =====================================================================

  var Actions = {
    join: function (teamId) {
      if (Game.GetTeamSelectionLocked()) return;
      if (U.localTeam() === teamId) return;

      var details = Game.GetTeamDetails(teamId);
      if (details.team_num_players >= details.team_max_players) return;

      Game.PlayerJoinTeam(teamId);
      U.sound("teamPick");
    },

    shuffle: function () {
      GameEvents.SendCustomGameEventToServer("osc_team_shuffle", {});
      U.sound("teamShuffle");
    },

    autoAssign: function () {
      Game.AutoAssignPlayersToTeams();
      U.sound("teamAutoAssign");
    },

    toggleStart: function () {
      if (Game.GetTeamSelectionLocked()) {
        Game.SetTeamSelectionLocked(false);
        Game.SetRemainingSetupTime(-1);
        U.sound("teamCancel");
      } else {
        if (Game.GetUnassignedPlayerIDs().length > 0) return;
        Game.SetTeamSelectionLocked(true);
        Game.SetAutoLaunchEnabled(false);
        Game.SetRemainingSetupTime(CFG.lockCountdown);
        U.sound("teamLockStart");
      }
      Refresh();
    },
  };

  // =====================================================================
  // КАРТОЧКИ КОМАНД
  // Слоты создаются один раз и дальше только обновляются,
  // без пересоздания панелей на каждое событие.
  // =====================================================================

  var Cards = (function () {
    var cards = {};
    var lastLocalTeam = -2;

    function theme(teamId) {
      var t = TEAM_THEME[teamId];
      if (t) return { name: U.L(t.token), color: t.color };
      return {
        name: $.Localize(Game.GetTeamDetails(teamId).team_name),
        color: CFG.defaultColor,
      };
    }

    function buildSlot(parent, color) {
      var root = U.panel(parent, "Slot Empty");

      var placeholder = U.panel(root, "AvatarPlaceholder");
      U.panel(placeholder, "SilHead");
      U.panel(placeholder, "SilBody");

      var avatar = U.avatar(root, "Avatar");
      avatar.style.borderColor = color + "cc";

      var name = U.label(root, "SlotName", U.L("osc_ts_free_slot"));
      U.label(root, "HostBadge", U.L("osc_ts_host_badge"));

      return { root: root, avatar: avatar, name: name, playerId: -1 };
    }

    function updateSlot(slot, playerId, localId) {
      var info = playerId !== undefined ? Game.GetPlayerInfo(playerId) : null;
      var filled = !!info;

      slot.root.SetHasClass("Empty", !filled);
      slot.root.SetHasClass("Filled", filled);
      slot.root.SetHasClass("Local", filled && playerId === localId);
      slot.root.SetHasClass(
        "Host",
        filled && !!info.player_has_host_privileges,
      );

      if (!filled) {
        slot.playerId = -1;
        slot.name.text = U.L("osc_ts_free_slot");
        return;
      }

      if (slot.playerId !== playerId) {
        slot.playerId = playerId;
        slot.avatar.steamid = info.player_steamid;
      }
      slot.name.text = info.player_name;
    }

    function buildCard(container, teamId) {
      var t = theme(teamId);
      var details = Game.GetTeamDetails(teamId);
      container.RemoveAndDeleteChildren();

      var card = U.panel(container, "TeamCard", "Button");
      card.SetPanelEvent("onactivate", function () {
        Actions.join(teamId);
      });

      var body = U.panel(card, "CardBody");
      var head = U.panel(body, "CardHeader");
      U.label(head, "TeamName", t.name).style.color = t.color;
      var count = U.label(head, "TeamCount", "");

      U.panel(body, "Divider").style.backgroundColor = U.hGradient(
        t.color + "aa",
      );

      var list = U.panel(body, "SlotList");
      var slots = [];
      for (var i = 0; i < details.team_max_players; i++) {
        slots.push(buildSlot(list, t.color));
      }

      var hint = U.label(body, "JoinHint", "");

      cards[teamId] = { card: card, count: count, hint: hint, slots: slots };
    }

    function build() {
      var teams = Game.GetAllTeamIDs();
      cards = {};
      for (var i = 0; i < TEAM_CONTAINERS.length && i < teams.length; i++) {
        buildCard($(TEAM_CONTAINERS[i]), teams[i]);
      }
    }

    function hintToken(locked, mine, full) {
      if (locked) return "osc_ts_hint_locked";
      if (mine) return "osc_ts_hint_mine";
      if (full) return "osc_ts_hint_full";
      return "osc_ts_click_to_join";
    }

    function refresh(s) {
      var justJoined = s.localTeam !== lastLocalTeam;
      lastLocalTeam = s.localTeam;

      for (var key in cards) {
        var teamId = Number(key);
        var c = cards[key];
        var details = Game.GetTeamDetails(teamId);
        var players = Game.GetPlayerIDsOnTeam(teamId);
        var mine = s.localTeam === teamId;
        var full = details.team_num_players >= details.team_max_players;

        c.card.SetHasClass("Mine", mine);
        c.card.SetHasClass("Full", full && !mine);
        c.count.text =
          details.team_num_players + "/" + details.team_max_players;
        c.hint.text = U.L(hintToken(s.locked, mine, full));

        for (var i = 0; i < c.slots.length; i++) {
          updateSlot(c.slots[i], players[i], s.localId);
          if (justJoined && mine && players[i] === s.localId) {
            c.slots[i].root.TriggerClass("Pop");
          }
        }
      }
    }

    return { build: build, refresh: refresh };
  })();

  // =====================================================================
  // ИГРОКИ БЕЗ КОМАНДЫ: аватарки-пузыри на орбите
  // Новый игрок появляется с эффектом надувания,
  // выбравший команду — лопается.
  // =====================================================================

  var Lobby = (function () {
    var root, layer, countLabel;
    var items = {}; // playerId -> { panel, offset, x, y }
    var order = []; // порядок на орбите
    var angle = 0;

    function init() {
      root = $("#Lobby");
      layer = $("#OrbitItems");
      countLabel = $("#LobbyCount");
    }

    function add(playerId) {
      var info = Game.GetPlayerInfo(playerId);
      if (!info) return;

      var p = U.panel(layer, "OrbitItem Spawn");
      U.avatar(p, "OrbitAvatar", info.player_steamid).hittest = false;
      U.panel(p, "BubbleShine").hittest = false;

      p.SetPanelEvent("onmouseover", function () {
        $.DispatchEvent("DOTAShowTextTooltip", p, info.player_name);
      });
      p.SetPanelEvent("onmouseout", function () {
        $.DispatchEvent("DOTAHideTextTooltip", p);
      });

      items[playerId] = { panel: p, offset: null, x: 0, y: 0 };
      order.push(playerId);
      U.sound("lobbyJoin");
    }

    function remove(playerId) {
      var item = items[playerId];
      delete items[playerId];
      order.splice(order.indexOf(playerId), 1);
      pop(item);
    }

    function pop(item) {
      var p = item.panel;
      var half = CFG.orbit.itemSize / 2;
      var cx = item.x + half;
      var cy = item.y + half;

      $.DispatchEvent("DOTAHideTextTooltip", p);
      p.hittest = false;
      p.RemoveClass("Spawn");
      p.AddClass("Popping");
      p.DeleteAsync(CFG.pop.lifetime);

      var ring = U.panel(layer, "PopRing");
      ring.hittest = false;
      U.placeAt(ring, cx, cy, CFG.pop.ringSize);
      ring.DeleteAsync(CFG.pop.lifetime);

      for (var k = 0; k < CFG.pop.droplets; k++) {
        var a = (Math.PI * 2 * k) / CFG.pop.droplets + Math.random() * 0.4;
        var dist = CFG.pop.spread * (0.7 + Math.random() * 0.5);
        spawnDrop(cx, cy, Math.cos(a) * dist, Math.sin(a) * dist);
      }

      U.sound("lobbyPop");
    }

    function spawnDrop(cx, cy, dx, dy) {
      var d = U.panel(layer, "PopDrop");
      d.hittest = false;
      U.placeAt(d, cx, cy, CFG.pop.dropSize);
      d.DeleteAsync(CFG.pop.lifetime);

      // через кадр, чтобы сработал transition из CSS
      $.Schedule(0.01, function () {
        if (!d.IsValid()) return;
        d.style.transform =
          "translate3d(" +
          dx.toFixed(1) +
          "px, " +
          dy.toFixed(1) +
          "px, 0px) scale3d(0.3, 0.3, 1)";
        d.style.opacity = "0";
      });
    }

    function refresh(localId) {
      var ids = Game.GetUnassignedPlayerIDs();
      var present = {};

      ids.forEach(function (id) {
        present[id] = true;
        if (!items[id]) add(id);
      });

      order.slice().forEach(function (id) {
        if (!present[id]) remove(id);
      });

      for (var id in items) {
        items[id].panel.SetHasClass("Local", Number(id) === localId);
      }

      countLabel.text = String(ids.length);
      root.SetHasClass("Empty", ids.length === 0);
    }

    function tick(dt) {
      var n = order.length;
      if (n === 0) return;

      var o = CFG.orbit;
      var center = o.size / 2;
      var half = o.itemSize / 2;
      angle = (angle + o.speed * dt) % (Math.PI * 2);

      for (var i = 0; i < n; i++) {
        var item = items[order[i]];
        var target = (Math.PI * 2 * i) / n;

        item.offset =
          item.offset === null
            ? target
            : item.offset + (target - item.offset) * o.ease;

        var a = angle + item.offset;
        item.x = center + Math.cos(a) * o.radius - half;
        item.y = center + Math.sin(a) * o.radius - half;
        item.panel.style.position =
          item.x.toFixed(1) + "px " + item.y.toFixed(1) + "px 0px";
      }
    }

    return { init: init, refresh: refresh, tick: tick };
  })();

  // =====================================================================
  // КНОПКИ ХОСТА
  // =====================================================================

  var Controls = {
    bind: function () {
      $("#ShuffleButton").SetPanelEvent("onactivate", Actions.shuffle);
      $("#AutoButton").SetPanelEvent("onactivate", Actions.autoAssign);
      $("#StartButton").SetPanelEvent("onactivate", Actions.toggleStart);
    },

    refresh: function (locked) {
      var unassigned = Game.GetUnassignedPlayerIDs().length;

      $("#HostControls").SetHasClass("Hidden", !U.isHost());
      $("#LBRoot").SetHasClass("Locked", locked);
      $("#StartLabel").text = U.L(
        locked ? "osc_ts_btn_cancel" : "osc_ts_btn_start",
      );
      $("#StartButton").SetHasClass("Cancel", locked);
      $("#StartButton").enabled = locked || unassigned === 0;
      $("#ShuffleButton").enabled = !locked;
      $("#AutoButton").enabled = !locked;
    },
  };

  // =====================================================================
  // ТАЙМЕР
  // =====================================================================

  var Timer = (function () {
    var lastTransition = -1;
    var total = 0;

    function update() {
      var transition = Game.GetStateTransitionTime();
      var wrap = $("#TimerWrap");
      var ring = $("#TimerRing");
      var text = $("#TimerText");

      if (transition < 0) {
        lastTransition = -1;
        ring.style.clip = "radial(50% 50%, 0deg, 360deg)";
        text.text = "∞";
        text.SetHasClass("Long", false);
        $("#TimerCaption").text = U.L("osc_ts_timer_waiting");
        wrap.SetHasClass("Urgent", false);
        wrap.SetHasClass("Idle", true);
        return;
      }
      $("#TimerCaption").text = U.L("osc_ts_timer_caption");
      var left = Math.max(0, transition - Game.GetGameTime());
      if (transition !== lastTransition) {
        // таймер запущен или перезапущен
        lastTransition = transition;
        total = left;
      }

      var deg = total > 0 ? (360 * left) / total : 0;
      ring.style.clip = "radial(50% 50%, 0deg, " + deg.toFixed(1) + "deg)";

      var long = left >= 60;
      text.text = long ? OSC.Util.FormatTime(left) : String(Math.ceil(left));
      text.SetHasClass("Long", long);

      wrap.SetHasClass("Urgent", left <= CFG.urgentSeconds);
      wrap.SetHasClass("Idle", false);
    }

    return { update: update };
  })();

  // =====================================================================
  // РОДНОЙ ЧАТ DOTA: лежит поверх своей подложки #ChatFrame,
  // подложка каждый кадр подстраивается под его реальную высоту
  // =====================================================================

  var Chat = (function () {
    var chat = null;
    var originalParent = null;
    var touched = []; // [panel, styleProp] — чтобы всё вернуть при выходе
    var lastNarrow = null;

    // внутренние подложки чата, которые дают «двухцветный» фон
    var INNER_BG = /ChatMain|ChatLines|Background/i;

    function setStyle(p, prop, value) {
      touched.push([p, prop]);
      p.style[prop] = value;
    }

    function find() {
      var queue = [U.topPanel()];
      while (queue.length > 0) {
        var p = queue.shift();
        if (p.paneltype === "DOTAChat" && p.id === "Chat") return p;
        for (var i = 0; i < p.GetChildCount(); i++) queue.push(p.GetChild(i));
      }
      return null;
    }

    function clearInnerBackgrounds(p) {
      for (var i = 0; i < p.GetChildCount(); i++) {
        var c = p.GetChild(i);
        if (INNER_BG.test(c.id)) {
          setStyle(c, "backgroundColor", "#00000000");
          setStyle(c, "boxShadow", "none");
        }
        clearInnerBackgrounds(c);
      }
    }

    function dump(p, depth) {
      var scale = p.actualuiscale_y || 1;
      $.Msg(
        new Array(depth + 1).join("  ") +
          p.paneltype +
          " #" +
          p.id +
          "  h=" +
          Math.round(p.actuallayoutheight / scale),
      );
      for (var i = 0; i < p.GetChildCount(); i++)
        dump(p.GetChild(i), depth + 1);
    }

    // позиция и ширина чата внутри рамки
    function place(narrow) {
      var f = narrow ? CFG.chat.frameNarrow : CFG.chat.frame;
      var pad = CFG.chat.padding;
      chat.style.width = f.width - pad.side * 2 + "px";
      chat.style.margin =
        "0px 0px " +
        (f.bottom + pad.bottom) +
        "px " +
        (f.left + pad.side) +
        "px";
    }

    // каждый кадр: подложка повторяет высоту чата
    function sync(narrow) {
      if (chat === null || !chat.IsValid()) return;

      if (narrow !== lastNarrow) {
        lastNarrow = narrow;
        place(narrow);
      }

      var scale = chat.actualuiscale_y || 1;
      var h = chat.actuallayoutheight / scale;
      if (h > 0) {
        var pad = CFG.chat.padding;
        $("#ChatFrame").style.height =
          Math.round(h + pad.top + pad.bottom) + "px";
      }
    }

    function attach() {
      var attempts = 0;

      OSC.Util.Loop(CFG.chat.searchInterval, function () {
        if (!U.isSetupPhase()) return false;

        var found = find();
        if (found === null) {
          attempts++;
          if (attempts >= CFG.chat.searchAttempts) {
            $.Msg("[OSC] native chat not found");
            return false;
          }
          return true;
        }

        chat = found;
        originalParent = found.GetParent();
        if (CFG.debug) {
          $.Schedule(1, function () {
            if (chat !== null && chat.IsValid()) dump(chat, 0);
          });
        }

        // в конец #ChatLayer — поверх подложки
        chat.SetParent($("#ChatLayer"));
        // в обычном клиенте Дота сама сдвигает чат — обнуляем её позиционирование
        setStyle(chat, "position", "0px 0px 0px");
        setStyle(chat, "transform", "none");
        setStyle(chat, "align", "left bottom"); // !!!!!!
        setStyle(chat, "backgroundColor", "#00000000");
        setStyle(chat, "boxShadow", "none");
        setStyle(chat, "borderRadius", "0px");
        touched.push([chat, "width"], [chat, "margin"]);
        clearInnerBackgrounds(chat);

        // скрытая справка занимает 196px над сообщениями — убираем её и кнопку «?»
        var help = chat.FindChildTraverse("ChatHelpPanel");
        if (help) setStyle(help, "visibility", "collapse");
        var helpBtn = chat.FindChildTraverse("ChatTabHelpButton");
        if (helpBtn) setStyle(helpBtn, "visibility", "collapse");

        // отдаём освободившееся место сообщениям
        var area = chat.FindChildTraverse("ChatLinesArea");
        if (area) setStyle(area, "height", CFG.chat.linesHeight + "px");
        ["ChatChannelArea", "ChatLinesContainer"].forEach(function (id) {
          var p = chat.FindChildTraverse(id);
          if (p) setStyle(p, "height", "100%");
        });

        lastNarrow = null;
        sync(Layout.isNarrow());
        $("#ChatFrame").RemoveClass("Hidden");
        return false;
      });
    }

    function restore() {
      // сначала возвращаем чат Доте — это важнее стилей
      if (
        chat !== null &&
        chat.IsValid() &&
        originalParent !== null &&
        originalParent.IsValid()
      ) {
        chat.SetParent(originalParent);
      }

      touched.forEach(function (t) {
        if (!t[0].IsValid()) return;
        try {
          t[0].style[t[1]] = null;
        } catch (e) {
          $.Msg("[OSC] can't reset style ", t[1], ": ", e);
        }
      });
      touched = [];

      chat = null;
      originalParent = null;
    }

    return { attach: attach, restore: restore, sync: sync };
  })();

  // =====================================================================
  // КОНТЕЙНЕР DOTA: убираем его отступ слева, чтобы центр совпадал с экраном
  // =====================================================================

  var Container = (function () {
    var container = null;

    function fix() {
      var p = $.GetContextPanel();
      while (p !== null && p.id !== "CustomUIContainer") p = p.GetParent();
      if (p === null) return;

      container = p;
      container.style.margin = "0px";
      container.style.padding = "0px";
      container.style.position = "0px 0px 0px";
      container.style.width = "100%";
      container.style.height = "100%";
    }

    function restore() {
      if (container !== null && container.IsValid()) {
        container.style.margin = null;
        container.style.padding = null;
        container.style.position = null;
        container.style.width = null;
        container.style.height = null;
      }
      container = null;
    }

    return { fix: fix, restore: restore };
  })();

  // =====================================================================
  // ОБНОВЛЕНИЕ И ЦИКЛ
  // =====================================================================

  function Refresh() {
    var s = {
      localTeam: U.localTeam(),
      localId: Players.GetLocalPlayer(),
      locked: Game.GetTeamSelectionLocked(),
    };

    Cards.refresh(s);
    Lobby.refresh(s.localId);
    Controls.refresh(s.locked);
  }

  var lastFrame = Date.now();

  function Tick() {
    if (!U.isSetupPhase()) {
      Container.restore();
      Chat.restore();
      return false; // останавливает OSC.Util.Loop
    }

    var now = Date.now();
    var dt = Math.min(0.1, (now - lastFrame) / 1000);
    lastFrame = now;

    Layout.update();
    Timer.update();
    Lobby.tick(dt);
    Chat.sync(Layout.isNarrow());
    return true;
  }

  function Init() {
    Container.fix();
    BuildStars();
    SetMapName();

    Controls.bind();
    Cards.build();
    Lobby.init();

    Refresh();
    Layout.update();
    OSC.Util.Loop(CFG.tick, Tick);
    Chat.attach();

    $.RegisterForUnhandledEvent("DOTAGame_TeamPlayerListChanged", Refresh);
    $.RegisterForUnhandledEvent("DOTAGame_PlayerDetailsChanged", Refresh);
  }

  return { Init: Init };
})();

// Свой контекст GameSetup — инициализируемся здесь
OSC.TeamSelect.Init();
