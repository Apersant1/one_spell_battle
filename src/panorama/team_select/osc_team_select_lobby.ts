namespace OSC.TeamSelect {
  // Выбор команд: перетаскивание игроков хостом и игроки без команды на
  // орбите. Орбита без React: позиции пузырей меняются каждый кадр, а
  // лопнувший пузырь доигрывает эффект уже после ухода игрока.
  type OrbitItem = { panel: Panel; offset: number | null; x: number; y: number };
  type DragCallbacks = { displayPanel: Panel; offsetX: number; offsetY: number };

  // =====================================================================
  // ПЕРЕТАСКИВАНИЕ: хост тянет игрока (слот или пузырь) на карточку команды,
  // сервер переносит его (osc_team_move, osc/systems/team_shuffle.lua)
  // =====================================================================

  var DRAG_AVATAR = 52; // = .DragAvatar в CSS
  var dragging: PlayerID | -1 = -1;

  // Драг-события Panorama передают (id панели, данные); в panorama-types их
  // сигнатуры другие, поэтому регистрируем по имени-строке
  function OnPanelEvent(name: string, panel: Panel, handler: (...args: never[]) => unknown) {
    $.RegisterEventHandler(name, panel, handler as unknown as () => void);
  }

  // Источник: playerId() — кого тянем сейчас (-1 — нечего тянуть)
  export function DragSource(panel: Panel, playerId: () => PlayerID | -1) {
    OnPanelEvent("DragStart", panel, function (_id: string, callbacks: DragCallbacks) {
      var id = playerId();
      var info = id === -1 ? null : Game.GetPlayerInfo(id);
      if (!info) return false;
      var avatar = $.CreatePanel("DOTAAvatarImage", $.GetContextPanel(), "") as AvatarImage;
      avatar.AddClass("DragAvatar");
      avatar.steamid = info.player_steamid;
      callbacks.displayPanel = avatar;
      callbacks.offsetX = DRAG_AVATAR / 2;
      callbacks.offsetY = DRAG_AVATAR / 2;
      dragging = id;
      return true;
    });
    OnPanelEvent("DragEnd", panel, function (_id: string, dragged: Panel) {
      dragged.DeleteAsync(0);
      dragging = -1;
      return true;
    });
  }

  // Цель: карточка команды. hover(true/false) — подсветка, пока над ней игрок
  export function DropTarget(panel: Panel, team: DOTATeam_t, hover: (on: boolean) => void) {
    OnPanelEvent("DragEnter", panel, function () {
      if (dragging !== -1) hover(true);
      return true;
    });
    OnPanelEvent("DragLeave", panel, function () {
      hover(false);
      return true;
    });
    OnPanelEvent("DragDrop", panel, function () {
      hover(false);
      if (dragging !== -1) {
        GameEvents.SendCustomGameEventToServer("osc_team_move", {
          player_id: dragging,
          team: team,
        });
        Sound("teamPick");
      }
      return true;
    });
  }

  // =====================================================================
  // ИГРОКИ БЕЗ КОМАНДЫ: аватарки-пузыри на орбите
  // Новый игрок появляется с эффектом надувания,
  // выбравший команду — лопается.
  // =====================================================================

  var ORBIT = {
    // size / itemSize / radius должны совпадать с #Orbit, .OrbitItem и #OrbitRing в CSS
    size: 240,
    itemSize: 52,
    radius: 90,
    speed: 0.35, // радиан в секунду
    ease: 0.12, // плавность перестроения при входе/выходе игрока
  };

  var POP = {
    lifetime: 0.5, // через сколько удалять панели эффекта
    droplets: 8,
    spread: 46, // как далеко разлетаются брызги, px
    ringSize: 52,
    dropSize: 8,
  };

  function CreateIn(parent: Panel, classes: string, type?: string): Panel {
    var p = $.CreatePanel(type || "Panel", parent, "");
    classes.split(" ").forEach(function (cls) {
      if (cls) p.AddClass(cls);
    });
    return p;
  }

  // Ставит панель так, чтобы её центр оказался в точке (cx, cy)
  function PlaceAt(p: Panel, cx: number, cy: number, size: number) {
    p.style.position = (cx - size / 2).toFixed(1) + "px " + (cy - size / 2).toFixed(1) + "px 0px";
  }

  export const Lobby = (function () {
    var layer: Panel | null = null;
    var items: Record<number, OrbitItem> = {}; // playerId -> { panel, offset, x, y }
    var order: PlayerID[] = []; // порядок на орбите
    var angle = 0;

    function add(playerId: PlayerID) {
      var info = Game.GetPlayerInfo(playerId);
      if (!info || layer === null) return;

      var p = CreateIn(layer, "OrbitItem Spawn");
      var avatar = CreateIn(p, "OrbitAvatar", "DOTAAvatarImage") as AvatarImage;
      avatar.steamid = info.player_steamid;
      avatar.hittest = false;
      CreateIn(p, "BubbleShine").hittest = false;

      p.SetPanelEvent("onmouseover", function () {
        $.DispatchEvent("DOTAShowTextTooltip", p, info.player_name);
      });
      p.SetPanelEvent("onmouseout", function () {
        $.DispatchEvent("DOTAHideTextTooltip", p);
      });
      DragSource(p, function () {
        return items[playerId] ? playerId : -1;
      });

      items[playerId] = { panel: p, offset: null, x: 0, y: 0 };
      order.push(playerId);
      Sound("lobbyJoin");
    }

    function remove(playerId: PlayerID) {
      var item = items[playerId];
      delete items[playerId];
      order.splice(order.indexOf(playerId), 1);
      pop(item);
    }

    function pop(item: OrbitItem) {
      if (layer === null) return;
      var p = item.panel;
      var half = ORBIT.itemSize / 2;
      var cx = item.x + half;
      var cy = item.y + half;

      $.DispatchEvent("DOTAHideTextTooltip", p);
      p.hittest = false;
      p.RemoveClass("Spawn");
      p.AddClass("Popping");
      p.DeleteAsync(POP.lifetime);

      var ring = CreateIn(layer, "PopRing");
      ring.hittest = false;
      PlaceAt(ring, cx, cy, POP.ringSize);
      ring.DeleteAsync(POP.lifetime);

      for (var k = 0; k < POP.droplets; k++) {
        var a = (Math.PI * 2 * k) / POP.droplets + Math.random() * 0.4;
        var dist = POP.spread * (0.7 + Math.random() * 0.5);
        spawnDrop(layer, cx, cy, Math.cos(a) * dist, Math.sin(a) * dist);
      }

      Sound("lobbyPop");
    }

    function spawnDrop(parent: Panel, cx: number, cy: number, dx: number, dy: number) {
      var d = CreateIn(parent, "PopDrop");
      d.hittest = false;
      PlaceAt(d, cx, cy, POP.dropSize);
      d.DeleteAsync(POP.lifetime);

      // через кадр, чтобы сработал transition из CSS
      $.Schedule(0.01, function () {
        if (!d.IsValid()) return;
        d.style.transform =
          "translate3d(" + dx.toFixed(1) + "px, " + dy.toFixed(1) + "px, 0px) scale3d(0.3, 0.3, 1)";
        d.style.opacity = "0";
      });
    }

    // canDrag — хост и команды не зафиксированы
    function refresh(localId: PlayerID, canDrag: boolean) {
      if (layer === null) layer = $("#OrbitItems");
      var ids = Game.GetUnassignedPlayerIDs();
      var present: Record<number, boolean> = {};

      ids.forEach(function (id) {
        present[id] = true;
        if (!items[id]) add(id);
      });

      order.slice().forEach(function (id) {
        if (!present[id]) remove(id);
      });

      for (var id in items) {
        items[Number(id)].panel.SetHasClass("Local", Number(id) === localId);
        items[Number(id)].panel.SetDraggable(canDrag);
      }
    }

    function tick(dt: number) {
      var n = order.length;
      if (n === 0) return;

      var center = ORBIT.size / 2;
      var half = ORBIT.itemSize / 2;
      angle = (angle + ORBIT.speed * dt) % (Math.PI * 2);

      for (var i = 0; i < n; i++) {
        var item = items[order[i]];
        var target = (Math.PI * 2 * i) / n;

        item.offset =
          item.offset === null ? target : item.offset + (target - item.offset) * ORBIT.ease;

        var a = angle + item.offset;
        item.x = center + Math.cos(a) * ORBIT.radius - half;
        item.y = center + Math.sin(a) * ORBIT.radius - half;
        item.panel.style.position = item.x.toFixed(1) + "px " + item.y.toFixed(1) + "px 0px";
      }
    }

    return { refresh: refresh, tick: tick };
  })();
}
