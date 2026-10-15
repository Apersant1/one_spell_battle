"use strict";

var OSC = OSC || {};

// Справка по правилам режима: кнопка «?» рядом с Хаос-лавкой открывает
// панель с вкладками. Слева темы, справа страница выбранной; страница
// строится заново при каждом открытии и переключении. Числа текущего матча —
// из net tables osc_state/help (osc/systems/help.lua), shop_<team>, version;
// тексты — ключи osc_hud_help_* с переменными {s:имя}.
OSC.Help = (function () {
  // icon: { item } | { ability } | { image: класс с background-image в CSS }
  var TOPICS = [
    { id: "overview", icon: { image: "HelpImgChaos" }, build: BuildOverview },
    {
      id: "rotation",
      icon: { ability: "rubick_spell_steal" },
      build: BuildRotation,
    },
    { id: "rarity", icon: { image: "HelpImgLegendary" }, build: BuildRarity },
    { id: "anchor", icon: { item: "item_osc_anchor" }, build: BuildAnchor },
    {
      id: "shop",
      icon: { item: "item_osc_ultimate_reroll" },
      build: BuildShop,
    },
    {
      id: "chaos",
      icon: { ability: "zuus_thundergods_wrath" },
      build: BuildChaos,
    },
    { id: "casino", icon: { image: "HelpImgSeven" }, build: BuildCasino },
    {
      id: "sphere",
      icon: { item: "item_osc_chaos_sphere" },
      build: BuildSphere,
    },
    {
      id: "couriers",
      icon: { ability: "courier_burst" },
      build: BuildCouriers,
    },
    { id: "summary", icon: { item: "item_aegis" }, build: BuildSummary },
  ];
  var RARITIES = ["common", "rare", "legendary"];
  var BORDER_CLASS = {
    common: "HelpImgCommon",
    rare: "HelpImgRare",
    legendary: "HelpImgLegendary",
  };
  var CASINO_CLASS = {
    circle: "HelpImgCircle",
    diamond: "HelpImgDiamond",
    star: "HelpImgStar",
    seven: "HelpImgSeven",
  };

  var current = "overview";

  // ================= Данные =================

  function Table(key) {
    return CustomNetTables.GetTableValue("osc_state", key) || {};
  }

  // Lua-массив приходит объектом { "1": ..., "2": ... }
  function ToList(table) {
    if (!table) return [];
    return Object.keys(table)
      .sort(function (a, b) {
        return Number(a) - Number(b);
      })
      .map(function (key) {
        return table[key];
      });
  }

  // Локализация с переменными {s:имя}: $.Localize без панели вырезает их,
  // поэтому значения кладём dialog variables на саму панель справки
  function L(key, vars) {
    var context = $("#HelpPanel");
    Object.keys(vars || {}).forEach(function (name) {
      context.SetDialogVariable(name, String(vars[name]));
    });
    return $.Localize("#" + key, context);
  }

  function ItemName(name) {
    return $.Localize("#DOTA_Tooltip_ability_" + name);
  }

  // ================= Кирпичики страницы =================

  function Add(parent, type, classes, text) {
    var panel = $.CreatePanel(type, parent, "");
    (classes || []).forEach(function (name) {
      panel.AddClass(name);
    });
    if (text !== undefined) panel.text = text;
    return panel;
  }

  function Icon(parent, icon, className) {
    var panel;
    if (icon.item) {
      panel = Add(parent, "DOTAItemImage", [className]);
      panel.itemname = icon.item;
    } else if (icon.ability) {
      panel = Add(parent, "DOTAAbilityImage", [className]);
      panel.abilityname = icon.ability;
    } else {
      panel = Add(parent, "Panel", [className, icon.image]);
    }
    panel.hittest = false;
    return panel;
  }

  function Text(page, key, vars) {
    return Add(page, "Label", ["HelpText"], L(key, vars));
  }

  function Subheading(page, key) {
    return Add(page, "Label", ["HelpSubheading"], L(key));
  }

  // items: [{ icon?: класс значка, value, caption, text?: значение — слово, а не число }]
  function Facts(page, items) {
    var row = Add(page, "Panel", ["HelpFacts"]);
    items.forEach(function (fact) {
      var box = Add(row, "Panel", ["HelpFact"]);
      var head = Add(box, "Panel", ["HelpFactHead"]);
      if (fact.icon) Add(head, "Panel", ["HelpFactIcon", fact.icon]);
      var value = Add(head, "Label", ["HelpFactValue"], String(fact.value));
      value.SetHasClass("Text", !!fact.text);
      Add(box, "Label", ["HelpFactCaption"], L(fact.caption));
    });
  }

  // Слоты героя: значок способности в рамке редкости и пояснение;
  // slots: [{ ability, rarity, title, text }]
  function Slots(page, slots) {
    var row = Add(page, "Panel", ["HelpSlots"]);
    slots.forEach(function (slot) {
      var box = Add(row, "Panel", ["HelpSlot"]);
      var frame = Add(box, "Panel", [
        "HelpSlotFrame",
        BORDER_CLASS[slot.rarity],
      ]);
      var image = Add(frame, "DOTAAbilityImage", ["HelpSlotIcon"]);
      image.abilityname = slot.ability;
      var info = Add(box, "Panel", ["HelpSlotInfo"]);
      Add(info, "Label", ["HelpCardTitle"], slot.title);
      Add(info, "Label", ["HelpCardText"], slot.text);
    });
  }

  // header: ключи заголовков; rows: [{ icon?, cells: [строки] }]
  function Grid(page, header, rows) {
    var table = Add(page, "Panel", ["HelpTable"]);
    var head = Add(table, "Panel", ["HelpRow", "Header"]);
    header.forEach(function (key) {
      Add(head, "Label", ["HelpCell"], L(key));
    });
    rows.forEach(function (row) {
      var line = Add(table, "Panel", ["HelpRow"]);
      row.cells.forEach(function (text, index) {
        var cell = Add(line, "Panel", ["HelpCellBox"]);
        if (index === 0 && row.icon) Icon(cell, row.icon, "HelpCellIcon");
        Add(cell, "Label", ["HelpCell"], text);
      });
    });
  }

  // Строка «значок + число» под описанием, как у способностей героя;
  // stats: [{ icon: класс значка, value, tooltip: готовый текст }]
  function Stats(parent, stats) {
    var row = Add(parent, "Panel", ["HelpStats"]);
    stats.forEach(function (stat) {
      var box = Add(row, "Panel", ["HelpStat"]);
      Add(box, "Panel", ["HelpStatIcon", stat.icon]);
      Add(box, "Label", [], String(stat.value));
      box.SetPanelEvent("onmouseover", function () {
        $.DispatchEvent("DOTAShowTextTooltip", box, stat.tooltip);
      });
      box.SetPanelEvent("onmouseout", function () {
        $.DispatchEvent("DOTAHideTextTooltip", box);
      });
    });
  }

  // cards: [{ icon?, title, text, stats? }]; columns — 2 или 3
  function Cards(page, cards, columns) {
    var grid = Add(page, "Panel", ["HelpCards", "Columns" + (columns || 2)]);
    cards.forEach(function (card) {
      var box = Add(grid, "Panel", ["HelpCard"]);
      var head = Add(box, "Panel", ["HelpCardHead"]);
      if (card.icon) Icon(head, card.icon, "HelpCardIcon");
      Add(head, "Label", ["HelpCardTitle"], card.title);
      Add(box, "Label", ["HelpCardText"], card.text);
      if (card.stats) Stats(box, card.stats);
    });
  }

  // ================= Страницы =================

  function BuildOverview(page, help) {
    var rotation = help.rotation || {};
    var chaos = help.chaos || {};
    var casino = help.casino || {};
    Text(page, "osc_hud_help_overview_text");
    Slots(page, [
      {
        ability: "mirana_arrow",
        rarity: "rare",
        title: L("osc_hud_help_overview_slot_ability"),
        text: L("osc_hud_help_overview_slot_ability_text", {
          interval: rotation.interval,
        }),
      },
      {
        ability: "zuus_thundergods_wrath",
        rarity: "legendary",
        title: L("osc_hud_help_overview_slot_ultimate"),
        text: L("osc_hud_help_overview_slot_ultimate_text"),
      },
    ]);

    Subheading(page, "osc_hud_help_overview_settings");
    Facts(page, [
      {
        icon: "HelpStatCooldown",
        value: rotation.interval,
        caption: "osc_hud_help_fact_rotation",
      },
      {
        icon: "HelpFacetVortex",
        value: chaos.interval,
        caption: "osc_hud_help_fact_chaos",
      },
      {
        icon: "HelpStatDuration",
        value: chaos.duration,
        caption: "osc_hud_help_fact_chaos_duration",
      },
      {
        icon: "HelpImgSeven",
        value: L("osc_hud_help_fact_casino"),
        text: true,
        caption:
          Number(casino.enabled) === 1
            ? "osc_notify_vote_casino_on"
            : "osc_notify_vote_casino_off",
      },
    ]);

    Subheading(page, "osc_hud_help_overview_screen");
    Cards(
      page,
      [
        {
          icon: { image: "HelpStatCooldown" },
          title: L("osc_hud_help_overview_screen_timer"),
          text: L("osc_hud_help_overview_screen_timer_text"),
        },
        {
          icon: { image: "HelpFacetVortex" },
          title: L("osc_hud_help_overview_screen_chaos"),
          text: L("osc_hud_help_overview_screen_chaos_text"),
        },
        {
          icon: { image: "HelpFacetItem" },
          title: L("osc_hud_help_overview_screen_buttons"),
          text: L("osc_hud_help_overview_screen_buttons_text"),
        },
      ],
      3,
    );
    Add(
      page,
      "Label",
      ["HelpFootnote"],
      L("osc_hud_help_overview_version", {
        version: Table("version").version || "?",
      }),
    );
  }

  // Один цикл ротации шагами со стрелками; steps: [{ value?, icon?, title, caption }]
  function Steps(page, steps) {
    var row = Add(page, "Panel", ["HelpSteps"]);
    steps.forEach(function (step, index) {
      if (index > 0) Add(row, "Label", ["HelpStepArrow"], "→");
      var box = Add(row, "Panel", ["HelpStep"]);
      var head = Add(box, "Panel", ["HelpStepHead"]);
      Add(head, "Label", ["HelpStepNumber"], String(index + 1));
      if (step.icon) Add(head, "Panel", ["HelpStepIcon", step.icon]);
      if (step.value !== undefined)
        Add(head, "Label", ["HelpStepValue"], step.value);
      Add(box, "Label", ["HelpStepTitle"], step.title);
      Add(box, "Label", ["HelpStepCaption"], step.caption);
    });
  }

  function BuildRotation(page, help) {
    var rotation = help.rotation || {};
    var interval = Number(rotation.interval) || 0;
    var choices = Number(rotation.choice_count) || 0;
    var warning =
      choices > 0 ? Math.min(Number(rotation.warning) || 0, interval) : 0;
    Text(page, "osc_hud_help_rotation_text", { interval: interval });
    var steps = [
      {
        value: L("osc_hud_help_seconds", { seconds: interval - warning }),
        title: L("osc_hud_help_rotation_step_play"),
        caption: L("osc_hud_help_rotation_step_play_caption"),
      },
    ];
    if (warning > 0) {
      steps.push({
        value: L("osc_hud_help_seconds", { seconds: warning }),
        title: L("osc_hud_help_rotation_step_pick", { count: choices }),
        caption: L("osc_hud_help_rotation_step_pick_caption"),
      });
    }
    steps.push({
      icon: "HelpStatCooldown",
      title: L("osc_hud_help_rotation_step_swap"),
      caption: L("osc_hud_help_rotation_step_swap_caption"),
    });
    Steps(page, steps);

    var cards = [
      {
        icon: { image: "HelpFacetDice" },
        title: L("osc_hud_help_rotation_card_choice"),
        text: L(
          choices > 0
            ? "osc_hud_help_rotation_choice"
            : "osc_hud_help_rotation_no_choice",
          {
            warning: warning,
            count: choices,
          },
        ),
      },
      {
        icon: { image: "HelpFacetAghs" },
        title: L("osc_hud_help_rotation_card_ultimate"),
        text: L("osc_hud_help_rotation_ultimate", {
          max: rotation.max_duplicate_ultimates,
        }),
      },
      {
        icon: { image: "HelpFacetArrows" },
        title: L("osc_hud_help_rotation_card_effects"),
        text: L("osc_hud_help_rotation_effects"),
      },
    ];
    if (Number(rotation.tag_streak) > 0) {
      cards.push({
        icon: { image: "HelpFacetSpin" },
        title: L("osc_hud_help_rotation_card_tags"),
        text: L("osc_hud_help_rotation_tags", { streak: rotation.tag_streak }),
      });
    }
    Cards(page, cards);
  }

  function BuildRarity(page, help) {
    var rarity = help.rarity || {};
    Text(page, "osc_hud_help_rarity_text");
    if (Number(rarity.enabled) !== 1) {
      Text(page, "osc_hud_help_rarity_off");
      return;
    }
    var ability = rarity.ability || {};
    var ultimate = rarity.ultimate || {};
    Grid(
      page,
      [
        "osc_hud_help_rarity_col_rarity",
        "osc_hud_help_rarity_col_frame",
        "osc_hud_help_rarity_col_ability",
        "osc_hud_help_rarity_col_ultimate",
      ],
      RARITIES.map(function (name) {
        return {
          icon: { image: BORDER_CLASS[name] },
          cells: [
            L("osc_hud_help_rarity_" + name),
            L("osc_hud_help_rarity_frame_" + name),
            (ability[name] || 0) + "%",
            (ultimate[name] || 0) + "%",
          ],
        };
      }),
    );
    Text(page, "osc_hud_help_rarity_note");
  }

  function BuildAnchor(page, help) {
    var anchor = help.anchor || {};
    if (Number(anchor.enabled) !== 1) {
      Text(page, "osc_hud_help_anchor_off");
      return;
    }
    Text(page, "osc_hud_help_anchor_text");
    Grid(
      page,
      [
        "osc_hud_help_anchor_col_item",
        "osc_hud_help_anchor_col_rotations",
        "osc_hud_help_col_cost",
      ],
      ToList(anchor.levels).map(function (level, index) {
        return {
          icon: { item: level.name },
          cells: [ItemName(level.name), String(index + 1), String(level.cost)],
        };
      }),
    );
    Text(page, "osc_hud_help_anchor_merge", { count: anchor.merge_count });
  }

  function BuildShop(page) {
    var items = ToList(
      Table("shop_" + Players.GetTeam(Players.GetLocalPlayer())).items,
    );
    if (items.length === 0) {
      Text(page, "osc_hud_help_shop_off");
      return;
    }
    Text(page, "osc_hud_help_shop_text");
    Grid(
      page,
      [
        "osc_hud_help_shop_col_item",
        "osc_hud_help_col_cost",
        "osc_hud_help_shop_col_stock",
      ],
      items.map(function (item) {
        var limited = Number(item.max) >= 0;
        return {
          icon: { item: item.name },
          cells: [
            ItemName(item.name),
            String(item.cost),
            limited
              ? L("osc_hud_help_shop_stock", { max: item.max })
              : L("osc_hud_help_shop_unlimited"),
          ],
        };
      }),
    );
  }

  function BuildChaos(page, help) {
    var chaos = help.chaos || {};
    Text(page, "osc_hud_help_chaos_text", {
      interval: chaos.interval,
      duration: chaos.duration,
      warning: chaos.warning,
    });
    Cards(
      page,
      ToList(chaos.events).map(function (ev) {
        return { title: L(ev.title_key), text: L(ev.desc_key, ev.params) };
      }),
      3,
    );
  }

  function BuildCasino(page, help) {
    var casino = help.casino || {};
    if (Number(casino.enabled) !== 1) {
      Text(page, "osc_hud_help_casino_off");
      return;
    }
    Text(page, "osc_hud_help_casino_text", {
      lifetime: casino.lifetime,
      min: casino.min_stake,
    });
    if (Number(casino.item_bets) === 1) {
      Text(page, "osc_hud_help_casino_items", { pct: casino.item_value_pct });
    }
    var outcomes = ToList(casino.outcomes);
    var win = 0;
    var expected = 0;
    var rows = outcomes.map(function (outcome) {
      win += Number(outcome.chance);
      expected += (Number(outcome.chance) * Number(outcome.multiplier)) / 100;
      return {
        icon: { image: CASINO_CLASS[outcome.symbol] || "HelpImgCircle" },
        cells: [
          L("osc_hud_help_casino_sym_" + outcome.symbol),
          outcome.chance + "%",
          Number(outcome.multiplier) === 1
            ? L("osc_hud_help_casino_refund")
            : "×" + outcome.multiplier,
        ],
      };
    });
    rows.push({
      cells: [
        L("osc_hud_help_casino_lose"),
        Math.max(0, 100 - win) + "%",
        L("osc_hud_help_casino_lost"),
      ],
    });
    Grid(
      page,
      [
        "osc_hud_help_casino_col_combo",
        "osc_hud_help_casino_col_chance",
        "osc_hud_help_casino_col_payout",
      ],
      rows,
    );
    Text(page, "osc_hud_help_casino_return", {
      pct: Math.round(expected * 100),
    });
  }

  function BuildSphere(page, help) {
    var sphere = help.sphere || {};
    if (Number(sphere.enabled) !== 1) {
      Text(page, "osc_hud_help_sphere_off");
      return;
    }
    Text(page, "osc_hud_help_sphere_text");
    Cards(page, [
      {
        icon: { image: "HelpImgLegendary" },
        title: L("osc_sphere_mode_ultimate"),
        text: L("osc_hud_help_sphere_ultimate", {
          choices: sphere.choices,
          level: sphere.min_level,
        }),
      },
      {
        icon: { ability: "chaos_knight_chaos_bolt" },
        title: L("osc_sphere_mode_enemies"),
        text: L("osc_hud_help_sphere_enemies"),
      },
    ]);
    Text(page, "osc_hud_help_sphere_note");
  }

  function BuildCouriers(page, help) {
    var couriers = help.couriers || {};
    Text(page, "osc_hud_help_couriers_text", { count: couriers.count });
    Cards(
      page,
      ToList(couriers.abilities).map(function (ability) {
        var interval = ability.interval_min + "–" + ability.interval_max;
        return {
          title: $.Localize("#" + ability.name_token),
          text: L("osc_hud_help_courier_" + ability.name),
          stats: [
            {
              icon: "HelpStatDuration",
              value: ability.duration,
              tooltip: L("osc_hud_help_stat_duration", {
                value: ability.duration,
              }),
            },
            {
              icon: "HelpStatCooldown",
              value: interval,
              tooltip: L("osc_hud_help_stat_interval", { value: interval }),
            },
          ],
        };
      }),
    );
  }

  function BuildSummary(page, help) {
    var summary = help.summary || {};
    if (Number(summary.enabled) !== 1) {
      Text(page, "osc_hud_help_summary_off");
      return;
    }
    Text(page, "osc_hud_help_summary_text");
    Cards(
      page,
      ToList(summary.titles).map(function (id) {
        return {
          title: L("osc_hud_title_" + id),
          text: L("osc_hud_help_title_" + id),
        };
      }),
    );
    if (summary.ties === "none") Text(page, "osc_hud_help_summary_ties");
  }

  // ================= Панель =================

  function FindTopic(id) {
    for (var i = 0; i < TOPICS.length; i++) {
      if (TOPICS[i].id === id) return TOPICS[i];
    }
    return TOPICS[0];
  }

  function Render() {
    var topic = FindTopic(current);
    $("#HelpTabs")
      .Children()
      .forEach(function (tab) {
        tab.SetHasClass(
          "Selected",
          tab.GetAttributeString("topic", "") === topic.id,
        );
      });

    var page = $("#HelpPage");
    page.RemoveAndDeleteChildren();
    var header = Add(page, "Panel", ["HelpPageHeader"]);
    Icon(header, topic.icon, "HelpPageIcon");
    Add(header, "Label", ["HelpPageTitle"], L("osc_hud_help_tab_" + topic.id));
    topic.build(page, Table("help"));
  }

  function BuildTabs() {
    var tabs = $("#HelpTabs");
    tabs.RemoveAndDeleteChildren();
    TOPICS.forEach(function (topic) {
      var tab = Add(tabs, "Button", ["HelpTab"]);
      tab.SetAttributeString("topic", topic.id);
      Icon(tab, topic.icon, "HelpTabIcon");
      Add(tab, "Label", [], L("osc_hud_help_tab_" + topic.id));
      tab.SetPanelEvent("onactivate", function () {
        current = topic.id;
        Render();
      });
    });
  }

  function SetOpen(open) {
    $("#HelpPanel").SetHasClass("Visible", open);
    // Страница строится при открытии: числа могли смениться после голосования
    if (open) Render();
  }

  function Toggle() {
    SetOpen(!$("#HelpPanel").BHasClass("Visible"));
  }

  function Close() {
    SetOpen(false);
  }

  function Init() {
    BuildTabs();
    SetOpen(false);
  }

  return { Init: Init, Toggle: Toggle, Close: Close };
})();
