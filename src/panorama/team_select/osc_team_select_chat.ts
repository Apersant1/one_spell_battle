namespace OSC.TeamSelect {
  // Выбор команд: родной чат Dota и контейнер кастомного UI. Без React — это
  // чужие панели Dota: чат переносится в наш #ChatLayer, а при выходе из
  // стадии выбора всё возвращается как было.
  type StyleProp = keyof VCSSStyleDeclaration;

  var CHAT = {
    debug: false,
    linesHeight: 300, // высота области сообщений, px
    searchInterval: 0.25,
    searchAttempts: 20, // ~5 секунд
    // = width и margin у #ChatFrame (обычный / Narrow)
    frame: { width: 380, left: 40, bottom: 36 },
    frameNarrow: { width: 300, left: 16, bottom: 20 },
    padding: { top: 12, side: 10, bottom: 8 }, // отступ чата внутри рамки
  };

  function TopPanel() {
    var p = $.GetContextPanel();
    while (p.GetParent() !== null) p = p.GetParent()!;
    return p;
  }

  // =====================================================================
  // РОДНОЙ ЧАТ DOTA: лежит поверх своей подложки #ChatFrame,
  // подложка каждый кадр подстраивается под его реальную высоту
  // =====================================================================

  export const Chat = (function () {
    var chat: Panel | null = null;
    var originalParent: Panel | null = null;
    var touched: [Panel, StyleProp][] = []; // [panel, styleProp] — чтобы всё вернуть при выходе
    var lastNarrow: boolean | null = null;

    // внутренние подложки чата, которые дают «двухцветный» фон
    var INNER_BG = /ChatMain|ChatLines|Background/i;

    function setStyle(p: Panel, prop: StyleProp, value: string) {
      touched.push([p, prop]);
      (p.style as Record<StyleProp, string | null>)[prop] = value;
    }

    function find() {
      var queue = [TopPanel()];
      while (queue.length > 0) {
        var p = queue.shift()!;
        if (p.paneltype === "DOTAChat" && p.id === "Chat") return p;
        for (var i = 0; i < p.GetChildCount(); i++) queue.push(p.GetChild(i)!);
      }
      return null;
    }

    function clearInnerBackgrounds(p: Panel) {
      for (var i = 0; i < p.GetChildCount(); i++) {
        var c = p.GetChild(i)!;
        if (INNER_BG.test(c.id)) {
          setStyle(c, "backgroundColor", "#00000000");
          setStyle(c, "boxShadow", "none");
        }
        clearInnerBackgrounds(c);
      }
    }

    function dump(p: Panel, depth: number) {
      var scale = p.actualuiscale_y || 1;
      $.Msg(
        new Array(depth + 1).join("  ") +
          p.paneltype +
          " #" +
          p.id +
          "  h=" +
          Math.round(p.actuallayoutheight / scale),
      );
      for (var i = 0; i < p.GetChildCount(); i++) dump(p.GetChild(i)!, depth + 1);
    }

    // позиция и ширина чата внутри рамки
    function place(chat: Panel, narrow: boolean) {
      var f = narrow ? CHAT.frameNarrow : CHAT.frame;
      var pad = CHAT.padding;
      chat.style.width = f.width - pad.side * 2 + "px";
      chat.style.margin = "0px 0px " + (f.bottom + pad.bottom) + "px " + (f.left + pad.side) + "px";
    }

    var narrowNow: () => boolean = function () {
      return false;
    };
    var onReady = function () {};
    var searching = false;

    // каждый кадр: подложка повторяет высоту чата. Если чат ушёл из
    // #ChatLayer (Dota вернула его к себе или его удалили) — ищем и
    // переносим заново; куда он делся, пишем в консоль
    function sync(narrow: boolean) {
      if (chat === null) return;

      var parent = chat.IsValid() ? chat.GetParent() : null;
      if (parent === null || parent.id !== "ChatLayer") {
        $.Msg(
          "[OSC] team select chat left #ChatLayer: ",
          chat.IsValid() ? (parent ? parent.paneltype + " #" + parent.id : "no parent") : "deleted",
        );
        chat = null;
        search();
        return;
      }

      if (narrow !== lastNarrow) {
        lastNarrow = narrow;
        place(chat, narrow);
      }

      var scale = chat.actualuiscale_y || 1;
      var h = chat.actuallayoutheight / scale;
      if (h > 0) {
        var pad = CHAT.padding;
        $("#ChatFrame").style.height = Math.round(h + pad.top + pad.bottom) + "px";
      }
    }

    function take(found: Panel) {
      chat = found;
      // При повторном переносе родитель уже может быть нашим — помним родной
      if (originalParent === null) originalParent = found.GetParent();
      if (CHAT.debug) {
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
      if (area) setStyle(area, "height", CHAT.linesHeight + "px");
      ["ChatChannelArea", "ChatLinesContainer"].forEach(function (id) {
        var p = chat!.FindChildTraverse(id);
        if (p) setStyle(p, "height", "100%");
      });

      lastNarrow = null;
      sync(narrowNow());
    }

    // Ищем чат, пока идёт выбор команд; до его начала — ждём
    function search() {
      if (searching) return;
      searching = true;
      var attempts = 0;

      OSC.Util.Loop(CHAT.searchInterval, function () {
        if (SetupOver()) {
          searching = false;
          return false;
        }
        if (!SetupStarted()) return true;

        var found = find();
        if (found === null) {
          attempts++;
          if (attempts >= CHAT.searchAttempts) {
            $.Msg("[OSC] native chat not found");
            searching = false;
            return false;
          }
          return true;
        }

        take(found);
        searching = false;
        onReady();
        return false;
      });
    }

    // narrow — текущая раскладка; ready — чат перенесён, подложку можно показать
    function attach(narrow: () => boolean, ready: () => void) {
      narrowNow = narrow;
      onReady = ready;
      search();
    }

    function restore() {
      // сначала возвращаем чат Доте — это важнее стилей
      if (chat !== null && chat.IsValid() && originalParent !== null && originalParent.IsValid()) {
        chat.SetParent(originalParent);
      }

      touched.forEach(function (t) {
        if (!t[0].IsValid()) return;
        try {
          (t[0].style as Record<StyleProp, string | null>)[t[1]] = null;
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

  export const Container = (function () {
    var container: Panel | null = null;

    function fix() {
      var p: Panel | null = $.GetContextPanel();
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
}
