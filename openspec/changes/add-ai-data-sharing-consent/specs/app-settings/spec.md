## MODIFIED Requirements

### Requirement: Страница «General»: состав и порядок
Страница «General» группы «App» SHALL показывать блоки в таком порядке (артборд «26 Settings — General»; design.md change `add-app-general-page`, D17; design.md change `add-app-legal-page`, D9):
1. InfoBar `settings-general-shared-info` и блок «Agent defaults» (`settings-general-agent-defaults`) — требования «Умолчания агента на странице «General»: …»;
2. блок «Interface» со строкой «Language» (`settings-general-language`, spec app-settings «Язык интерфейса app»); строка и её поведение этим требованием не меняются;
3. блок «Startup and files» со строкой «Reopen the last project and its tabs» (`settings-general-reopen-last-project`);
4. блок «Privacy» (`settings-general-privacy`) со строкой «No telemetry» (`settings-general-no-telemetry`): описание `The app, the CLI and the agent send no usage analytics or crash reports. Prompts and files go only to the provider and tools you set up.` и ссылка «Privacy policy» (`settings-general-privacy-policy`), которая открывает страницу «Legal» на вкладке «Privacy policy»;
   затем строка «Data sharing» (`settings-general-data-sharing`) — требование «Строка «Data sharing» страницы «General»» (design.md change `add-ai-data-sharing-consent`, D10);
5. раздел «About» (`settings-general-about`).

Строка без поведения в текущей сборке НЕ SHALL показываться (SETUP-17). Строки «When I press Enter during a turn», «Sidebar opens on» и «Send crash reports» НЕ SHALL показываться (design.md change `add-app-general-page`, D8, D17; E-21). У строки «No telemetry» нет переключателя: телеметрии нет, и выключать нечего. Блок, в котором не осталось видимых строк, SHALL быть скрыт вместе с заголовком.

Поиск «Find a setting» SHALL находить «General» по английским ключевым словам `language`, `budget`, `steps`, `compaction`, `subagent`, `log level`, `startup`, `reopen`, `ignored`, `about`, `version`, `license`, `diagnostics`, `telemetry`, `data sharing`, `permission`, `provider`, `consent` при любом языке интерфейса, а при русском интерфейсе — ещё по русским `язык`, `бюджет`, `шаги`, `сжатие`, `субагент`, `уровень журнала`, `запуск`, `открывать`, `игнорируемые`, `о программе`, `версия`, `лицензия`, `диагностика`, `телеметрия`, `передача данных`, `разрешение`, `провайдер`, `согласие`. Слова обоих языков SHALL храниться в каталогах ARB `en` и `ru` (`settingsSearchKeywordsGeneral`, список через запятую; spec app-settings «Навигация настроек», change `add-desktop-localization`).

Все тексты страницы SHALL браться из каталогов ARB `en` и `ru` (spec app-settings «Локализация интерфейса app»). Ключи конфигурации, значения, источники `default`, `user`, `project`, `local`, `config`, `env`, пути и версии SHALL показываться как есть.

#### Scenario: Порядок блоков
- **WHEN** встроенный агент подключён, проект выбран, и пользователь открывает «General»
- **THEN** сверху вниз идут `settings-general-shared-info`, `settings-general-agent-defaults`, `settings-general-language`, `settings-general-reopen-last-project`, `settings-general-no-telemetry`, `settings-general-data-sharing`, `settings-general-about`; строк Enter во время хода, «Sidebar opens on» и «Send crash reports» нет

#### Scenario: «No telemetry» ведёт на политику
- **WHEN** пользователь нажимает `settings-general-privacy-policy`
- **THEN** экран настроек показывает страницу «Legal» с выбранной вкладкой `settings-legal-tab-privacy-policy`, пункт навигации `settings-nav-legal` выбран, сеть не используется

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `compaction` в «Find a setting»
- **THEN** в навигации остаётся «General», а выбор результата открывает её

#### Scenario: Русское ключевое слово «General» зависит от языка интерфейса
- **WHEN** пользователь вводит `сжатие` в «Find a setting» сначала на русском интерфейсе, затем на английском
- **THEN** на русском в навигации остаётся «General», на английском ни одной страницы не найдено и показано `No settings match "сжатие"`

#### Scenario: Поиск строки разрешений
- **WHEN** пользователь вводит `data sharing` в «Find a setting» на английском интерфейсе, затем `передача данных` на русском
- **THEN** оба раза в навигации остаётся `settings-nav-general`

### Requirement: Страница «Legal»: видимость и вкладки
Страница «Legal» (`settings-legal`, последний пункт группы «App») SHALL показывать правовые документы сборки на четырёх вкладках в таком порядке (`dart-agent-and-clients` §12.7.7а; артборды 32–35):
1. «Privacy policy» (`settings-legal-tab-privacy-policy`) — `PRIVACY.md`;
2. «Terms of use» (`settings-legal-tab-terms-of-use`) — `TERMS.md`;
3. «License» (`settings-legal-tab-license`) — требование «Страница «Legal»: вкладка «License»»;
4. «Third-party notices» (`settings-legal-tab-third-party-notices`) — требование «Страница «Legal»: вкладка «Third-party notices»».

Вкладки SHALL быть одной группой с подписью `Legal documents` для программ чтения с экрана; выбранная вкладка SHALL объявляться выбранной. В окне шириной 800 px и на русском языке подписи вкладок НЕ SHALL обрезаться: не помещающиеся вкладки прокручиваются по горизонтали.

Страница SHALL быть видна в каждой сборке app: её содержимое задают ресурсы сборки, а не конфигурация (SETUP-17; design.md, D1). Выбор пунктом навигации, поиском или последней сохранённой страницей SHALL открывать вкладку «Privacy policy». Переход со страницы «General» SHALL открывать вкладку, названную ссылкой. Выбранная вкладка и запрос поиска НЕ SHALL сохраняться между открытиями страницы; `codelab.settings.last_page` хранит только страницу (`legal`).

Под вкладками SHALL стоять подпись источника `settings-legal-source`: `Bundled with CodeLab <version> as <asset> · readable offline`, где `<asset>` — путь ресурса показанного документа (`assets/legal/PRIVACY.md`, `assets/legal/TERMS.ru.md`, `assets/legal/LICENSE`, `assets/legal/THIRD_PARTY_NOTICES.md`).

Страница НЕ SHALL обращаться к сети для показа документов. Кнопок и флажков принятия условий, записи о принятии условий или политики в `shared_preferences` и `~/.codelab` НЕ SHALL быть (D-29, §12.7.7а). Разрешения на передачу данных показываются и отзываются на странице «General» (spec app-data-sharing), а не на странице «Legal». Кнопок «Copy link», «Open on the web», «Copy all», «Open LICENSE» и оглавления «On this page» артбордов НЕ SHALL быть в этой сборке (design.md, D12).

Поиск «Find a setting» SHALL находить «Legal» по английским ключевым словам `legal`, `privacy`, `terms`, `license`, `notices`, `third-party`, `telemetry`, `packages` при любом языке интерфейса, а при русском — ещё по `правовая`, `конфиденциальность`, `условия`, `лицензия`, `уведомления`, `телеметрия`, `пакеты` (`settingsSearchKeywordsLegal`).

#### Scenario: Пункт навигации открывает политику
- **WHEN** пользователь выбирает `settings-nav-legal`
- **THEN** выбрана вкладка `settings-legal-tab-privacy-policy`, показан текст `assets/legal/PRIVACY.md`, подпись `settings-legal-source` содержит `assets/legal/PRIVACY.md`

#### Scenario: Последняя страница без вкладки
- **WHEN** пользователь ушёл со страницы «Legal» с вкладки «License» и снова открыл настройки
- **THEN** открыта страница «Legal» на вкладке «Privacy policy»

#### Scenario: Принимать нечего
- **WHEN** пользователь открывает каждую из четырёх вкладок
- **THEN** на странице нет флажка, кнопки или переключателя согласия и разрешения, а `shared_preferences` не изменились

#### Scenario: Узкое окно на русском
- **WHEN** app работает на русском в окне шириной 800 px, и пользователь открывает «Legal»
- **THEN** подписи четырёх вкладок видны целиком без многоточия, переполнения раскладки нет

#### Scenario: Поиск страницы по ключевому слову
- **WHEN** пользователь вводит `privacy` в «Find a setting»
- **THEN** в навигации остаётся `settings-nav-legal`

## ADDED Requirements

### Requirement: Строка «Data sharing» страницы «General»
Строка «Data sharing» (`settings-general-data-sharing`) блока «Privacy» SHALL показывать описание `settingsGeneralDataSharingDescription` и список действующих разрешений из `DataSharingCubit` (spec app-data-sharing; design.md change `add-ai-data-sharing-consent`, D10, D12) в порядке выдачи. Каждый элемент (`settings-general-data-sharing-item`) SHALL показывать первой строкой `{label} · {target}` — id провайдера и хост или метку профиля и цель (команда stdio — с `~` вместо домашнего каталога), второй — `Model provider · allowed {date}` или `External agent · allowed {date}` с датой `YYYY-MM-DD` как есть, и кнопку `Withdraw` (`settings-general-data-sharing-withdraw`). Без разрешений SHALL показываться `You have not allowed any service yet.` (`settings-general-data-sharing-empty`).

Кнопки выдачи разрешения строка НЕ SHALL иметь. `Withdraw` SHALL отзывать разрешение по требованию spec app-data-sharing «Отзыв разрешения» без подтверждения: отзыв безопасен и обратим вопросом при следующем запросе. Сбой чтения хранилища SHALL показывать InfoBar `settings-general-data-sharing-unreadable`, сбой записи отзыва — InfoBar `settings-general-data-sharing-not-saved` с кнопкой `Try again` (`settings-general-data-sharing-retry`). Строка SHALL обновляться, когда разрешение выдано диалогом, пока настройки открыты.

Строка SHALL быть видна в каждой сборке app: её содержимое задаёт app, а не конфигурация агента. Тексты SHALL браться из ARB `en` и `ru`; id провайдеров, хосты, команды, метки профилей и даты SHALL показываться как есть.

#### Scenario: Список и отзыв
- **WHEN** разрешены провайдер `anthropic` (`api.anthropic.com`, 2026-11-25) и WebSocket-агент `Remote` (`agent.example.com:8443`), и пользователь нажимает `Withdraw` у `anthropic`
- **THEN** до нажатия видны два элемента `anthropic · api.anthropic.com` с `Model provider · allowed 2026-11-25` и `Remote · agent.example.com:8443` с `External agent · allowed …`; после — один элемент `Remote`, в `codelab.app.data_sharing` нет записи `anthropic`

#### Scenario: Пусто
- **WHEN** разрешений нет
- **THEN** строка показывает `settings-general-data-sharing-empty` и не показывает кнопок `Allow`

#### Scenario: Русский интерфейс
- **WHEN** язык app — `ru`, разрешён провайдер `gw` (`llm.internal`)
- **THEN** заголовок строки — `Передача данных`, вторая строка элемента — `Провайдер модели · разрешено …`, `gw · llm.internal` показан без перевода
