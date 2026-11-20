## MODIFIED Requirements

### Requirement: Страница «General»: состав и порядок
Страница «General» группы «App» SHALL показывать блоки в таком порядке (артборд «26 Settings — General»; design.md change `add-app-general-page`, D17; design.md change `add-app-legal-page`, D9; design.md change `add-file-preview-and-tree`, D14):
1. InfoBar `settings-general-shared-info` и блок «Agent defaults» (`settings-general-agent-defaults`) — требования «Умолчания агента на странице «General»: …»;
2. блок «Interface» со строкой «Language» (`settings-general-language`, spec app-settings «Язык интерфейса app»); строка и её поведение этим требованием не меняются;
3. блок «Startup and files» со строками «Reopen the last project and its tabs» (`settings-general-reopen-last-project`) и «Show ignored files» (`settings-general-show-ignored`; требование «Показ игнорируемых файлов на странице «General»»);
4. блок «Privacy» (`settings-general-privacy`) со строкой «No telemetry» (`settings-general-no-telemetry`): описание `The app, the CLI and the agent send no usage analytics or crash reports. Prompts and files go only to the provider and tools you set up.` и ссылка «Privacy policy» (`settings-general-privacy-policy`), которая открывает страницу «Legal» на вкладке «Privacy policy»;
5. раздел «About» (`settings-general-about`).

Строка без поведения в текущей сборке НЕ SHALL показываться (SETUP-17). Строки «When I press Enter during a turn», «Sidebar opens on» и «Send crash reports» НЕ SHALL показываться (design.md change `add-app-general-page`, D8, D17; E-21). У строки «No telemetry» нет переключателя: телеметрии нет, и выключать нечего. Блок, в котором не осталось видимых строк, SHALL быть скрыт вместе с заголовком.

Поиск «Find a setting» SHALL находить «General» по английским ключевым словам `language`, `budget`, `steps`, `compaction`, `subagent`, `log level`, `startup`, `reopen`, `ignored`, `about`, `version`, `license`, `diagnostics`, `telemetry` при любом языке интерфейса, а при русском интерфейсе — ещё по русским `язык`, `бюджет`, `шаги`, `сжатие`, `субагент`, `уровень журнала`, `запуск`, `открывать`, `игнорируемые`, `о программе`, `версия`, `лицензия`, `диагностика`, `телеметрия`. Слова обоих языков SHALL храниться в каталогах ARB `en` и `ru` (`settingsSearchKeywordsGeneral`, список через запятую; spec app-settings «Навигация настроек», change `add-desktop-localization`).

Все тексты страницы SHALL браться из каталогов ARB `en` и `ru` (spec app-settings «Локализация интерфейса app»). Ключи конфигурации, значения, источники `default`, `user`, `project`, `local`, `config`, `env`, пути и версии SHALL показываться как есть.

#### Scenario: Порядок блоков
- **WHEN** встроенный агент подключён, проект выбран, и пользователь открывает «General»
- **THEN** сверху вниз идут `settings-general-shared-info`, `settings-general-agent-defaults`, `settings-general-language`, `settings-general-reopen-last-project`, `settings-general-show-ignored`, `settings-general-no-telemetry`, `settings-general-about`; строк Enter во время хода, «Sidebar opens on» и «Send crash reports» нет

#### Scenario: «No telemetry» ведёт на политику
- **WHEN** пользователь нажимает `settings-general-privacy-policy`
- **THEN** экран настроек показывает страницу «Legal» с выбранной вкладкой `settings-legal-tab-privacy-policy`, пункт навигации `settings-nav-legal` выбран, сеть не используется

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `compaction` в «Find a setting»
- **THEN** в навигации остаётся «General», а выбор результата открывает её

#### Scenario: Русское ключевое слово «General» зависит от языка интерфейса
- **WHEN** пользователь вводит `сжатие` в «Find a setting» сначала на русском интерфейсе, затем на английском
- **THEN** на русском в навигации остаётся «General», на английском ни одной страницы не найдено и показано `No settings match "сжатие"`

## ADDED Requirements

### Requirement: Показ игнорируемых файлов на странице «General»
Строка «Show ignored files» (`settings-general-show-ignored`) SHALL быть переключателем той же настройки `codelab.file_browser.show_ignored`, что переключатель `file-tree-show-ignored` панели Files (spec workspace-file-browser «Игнорируемые записи по `.gitignore`»). Значение SHALL иметь одного владельца в app: строка «General» и переключатель панели SHALL менять одно значение, второй копии НЕ SHALL быть. Смена на «General» SHALL применяться к открытой панели Files без перезапуска. Подпись строки — `Files matched by .gitignore appear dimmed in the Files pane.`

Строка SHALL показываться, только когда в сборке есть фильтр `.gitignore` панели Files (итерация 3 этого change). До этого строка НЕ SHALL показываться (SETUP-17).

#### Scenario: Одна настройка на две точки
- **WHEN** панель Files открыта, в корне `.gitignore` со строкой `build/`, и пользователь включает «Show ignored files» на «General»
- **THEN** `codelab.file_browser.show_ignored` равен `true`, переключатель `file-tree-show-ignored` панели включён, а папка `build` в дереве показана приглушённой
