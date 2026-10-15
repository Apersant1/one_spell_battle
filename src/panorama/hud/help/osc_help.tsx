namespace OSC.Help {
  // Справка по правилам режима (React): кнопка «?» рядом с Хаос-лавкой открывает
  // панель с вкладками. Слева темы, справа страница выбранной. Числа текущего
  // матча — из net tables osc_state/help (osc/systems/help.lua), shop_<team>,
  // version; тексты — ключи osc_hud_help_* с переменными {s:имя}.
  // Кирпичики — osc_help_blocks.tsx, страницы тем — osc_help_pages.tsx.

  function HelpWindow() {
    var [open, setOpen] = React.useState(false);
    var [current, setCurrent] = React.useState(TOPICS[0].id);
    // Подписка, чтобы открытая справка обновилась после итогов голосования
    var help = ReactPanorama.useNetTableKey("osc_state", "help") || {};
    var topic =
      TOPICS.filter(function (t) {
        return t.id === current;
      })[0] || TOPICS[0];

    return (
      <>
        <Button
          id="HelpButton"
          className="OSCButton"
          onactivate={function () {
            setOpen(!open);
          }}
        >
          <Label text={$.Localize("#osc_hud_help_button")} />
        </Button>
        <Panel id="HelpPanel" className={OSC.Util.Classes(open && "Visible")} hittest={true}>
          <Button
            id="HelpClose"
            className="OSCButton"
            onactivate={function () {
              setOpen(false);
            }}
          >
            <Label text={$.Localize("#osc_hud_help_close")} />
          </Button>
          <Label
            id="HelpTitle"
            className="OSCTextTitle OSCChaosText"
            text={$.Localize("#osc_hud_help_title")}
          />
          <Panel id="HelpBody">
            <Panel id="HelpTabs">
              {TOPICS.map(function (t) {
                return (
                  <Button
                    key={t.id}
                    className={OSC.Util.Classes("HelpTab", t.id === topic.id && "Selected")}
                    onactivate={function () {
                      setCurrent(t.id);
                    }}
                  >
                    <Icon icon={t.icon} className="HelpTabIcon" />
                    <Label text={L("osc_hud_help_tab_" + t.id)} />
                  </Button>
                );
              })}
            </Panel>
            {/* Страница строится только в открытой справке: числа и тексты свежие */}
            {open && (
              <Panel id="HelpPage" key={topic.id}>
                <Panel className="HelpPageHeader">
                  <Icon icon={topic.icon} className="HelpPageIcon" />
                  <Label className="HelpPageTitle" text={L("osc_hud_help_tab_" + topic.id)} />
                </Panel>
                {topic.page(help)}
              </Panel>
            )}
          </Panel>
        </Panel>
      </>
    );
  }

  export function Init() {
    ReactPanorama.render(<HelpWindow />, $("#HelpRoot"));
  }
}
