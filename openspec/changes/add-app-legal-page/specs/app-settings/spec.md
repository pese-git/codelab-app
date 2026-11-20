## MODIFIED Requirements

### Requirement: Навигация настроек
Экран настроек SHALL показывать одну навигацию (Fluent `NavigationView`) с полем поиска «Find a setting» и группами «Agent» и «App» в фиксированном порядке `dart-agent-and-clients` §12.4.9:
- Agent: Connection, Providers, MCP servers, Agents & modes, Permissions & tools, Redaction, Skills & extensions, Code & web;
- App: General, Appearance, Keyboard, Legal.

Страница без содержимого в текущей сборке SHALL быть скрыта, а не пуста (SETUP-17); группа без видимых страниц НЕ SHALL показывать заголовок. Набор видимых страниц SHALL задавать composition root. Пункт навигации SHALL иметь ключ теста `settings-nav-<page>` (kebab-case: `settings-nav-connection`, `settings-nav-mcp-servers`, `settings-nav-legal`).

Заголовки групп и страниц SHALL показываться на языке интерфейса (требование «Локализация интерфейса app»); ключ теста и значение `codelab.settings.last_page` от языка НЕ SHALL зависеть.

Поиск SHALL отбирать страницы по совпадению подстроки без учёта регистра с заголовком страницы на языке интерфейса, с её английским заголовком, с её ключевыми словами на языке интерфейса или с её английскими ключевыми словами. Ключевые слова SHALL браться из каталогов ARB `en` и `ru` (сообщение на страницу, слова через запятую); ключевые слова другого языка, кроме английского, страницу НЕ SHALL находить. При пустом результате SHALL показываться строка `No settings match "<query>"` на языке интерфейса.

При ширине окна меньше 760 px навигация SHALL располагаться сверху, при 760 px и шире — панелью слева.

#### Scenario: Только существующие страницы
- **WHEN** сборка содержит только страницу «Connection»
- **THEN** навигация показывает группу «Agent» с единственным пунктом `settings-nav-connection`, заголовка «App» и пунктов других страниц нет

#### Scenario: Порядок не зависит от регистрации
- **WHEN** тестовая сборка регистрирует страницы `keyboard`, `connection`, `general` в этом порядке
- **THEN** навигация показывает Connection в группе «Agent», затем General и Keyboard в группе «App»

#### Scenario: Legal — последний пункт группы «App»
- **WHEN** тестовая сборка регистрирует страницы `legal`, `general`, `keyboard`, `appearance` в этом порядке
- **THEN** группа «App» показывает General, Appearance, Keyboard и `settings-nav-legal` последним

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `token` в «Find a setting»
- **THEN** в навигации остаётся «Connection», а выбор результата открывает эту страницу

#### Scenario: Поиск по английскому заголовку при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `providers` в поле поиска настроек
- **THEN** в навигации остаётся страница «Providers» с переведённым заголовком

#### Scenario: Поиск по переведённому заголовку
- **WHEN** app работает на русском, и пользователь вводит часть переведённого заголовка страницы «General» из `app_ru.arb`
- **THEN** в навигации остаётся страница `settings-nav-general`

#### Scenario: Русское ключевое слово при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `токен` в поле поиска настроек
- **THEN** в навигации остаётся страница `settings-nav-connection`

#### Scenario: Английское ключевое слово при русском интерфейсе
- **WHEN** app работает на русском, и пользователь вводит `token` в поле поиска настроек
- **THEN** в навигации остаётся страница `settings-nav-connection`

#### Scenario: Русское ключевое слово при английском интерфейсе
- **WHEN** app работает на английском, и пользователь вводит `токен` в поле поиска настроек
- **THEN** ни одной страницы не найдено, показана строка `No settings match "токен"`

#### Scenario: Узкое окно
- **WHEN** ширина окна 700 px
- **THEN** пункты навигации настроек расположены сверху, а не панелью слева

### Requirement: Страница «General»: состав и порядок
Страница «General» группы «App» SHALL показывать блоки в таком порядке (артборд «26 Settings — General»; design.md change `add-app-general-page`, D17; design.md change `add-app-legal-page`, D9):
1. InfoBar `settings-general-shared-info` и блок «Agent defaults» (`settings-general-agent-defaults`) — требования «Умолчания агента на странице «General»: …»;
2. блок «Interface» со строкой «Language» (`settings-general-language`, spec app-settings «Язык интерфейса app»); строка и её поведение этим требованием не меняются;
3. блок «Startup and files» со строками «Reopen the last project and its tabs» (`settings-general-reopen-last-project`) и «Show ignored files» (`settings-general-show-ignored`);
4. блок «Privacy» (`settings-general-privacy`) со строкой «No telemetry» (`settings-general-no-telemetry`): описание `The app, the CLI and the agent send no usage analytics or crash reports. Prompts and files go only to the provider and tools you set up.` и ссылка «Privacy policy» (`settings-general-privacy-policy`), которая открывает страницу «Legal» на вкладке «Privacy policy»;
5. раздел «About» (`settings-general-about`).

Строка без поведения в текущей сборке НЕ SHALL показываться (SETUP-17). Строки «When I press Enter during a turn», «Sidebar opens on» и «Send crash reports» НЕ SHALL показываться (design.md change `add-app-general-page`, D8, D17; E-21). У строки «No telemetry» нет переключателя: телеметрии нет, и выключать нечего. Блок, в котором не осталось видимых строк, SHALL быть скрыт вместе с заголовком.

Поиск «Find a setting» SHALL находить «General» по английским ключевым словам `language`, `budget`, `steps`, `compaction`, `subagent`, `log level`, `startup`, `reopen`, `ignored`, `about`, `version`, `license`, `diagnostics`, `telemetry` при любом языке интерфейса, а при русском интерфейсе — ещё по русским `язык`, `бюджет`, `шаги`, `сжатие`, `субагент`, `уровень журнала`, `запуск`, `открывать`, `игнорируемые`, `о программе`, `версия`, `лицензия`, `диагностика`, `телеметрия`. Слова обоих языков SHALL храниться в каталогах ARB `en` и `ru` (`settingsSearchKeywordsGeneral`, список через запятую; spec app-settings «Навигация настроек», change `add-desktop-localization`).

Все тексты страницы SHALL браться из каталогов ARB `en` и `ru` (spec app-settings «Локализация интерфейса app»). Ключи конфигурации, значения, источники `default`, `user`, `project`, `local`, `config`, `env`, пути и версии SHALL показываться как есть.

#### Scenario: Порядок блоков
- **WHEN** встроенный агент подключён, проект выбран, и пользователь открывает «General»
- **THEN** сверху вниз идут `settings-general-shared-info`, `settings-general-agent-defaults`, `settings-general-language`, `settings-general-reopen-last-project`, `settings-general-no-telemetry`, `settings-general-about`; строк Enter во время хода, «Sidebar opens on» и «Send crash reports» нет

#### Scenario: «No telemetry» ведёт на политику
- **WHEN** пользователь нажимает `settings-general-privacy-policy`
- **THEN** экран настроек показывает страницу «Legal» с выбранной вкладкой `settings-legal-tab-privacy-policy`, пункт навигации `settings-nav-legal` выбран, сеть не используется

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `compaction` в «Find a setting»
- **THEN** в навигации остаётся «General», а выбор результата открывает её

#### Scenario: Русское ключевое слово «General» зависит от языка интерфейса
- **WHEN** пользователь вводит `сжатие` в «Find a setting» сначала на русском интерфейсе, затем на английском
- **THEN** на русском в навигации остаётся «General», на английском ни одной страницы не найдено и показано `No settings match "сжатие"`

### Requirement: Раздел «About» страницы «General»
Раздел «About» (`settings-general-about`) SHALL быть Fluent `Expander`, по умолчанию свёрнутым. В заголовке SHALL быть `CodeLab <version>` и строка `<os> <arch> · embedded agent <agentVersion>`, где:
- `<version>` — версия сборки app из константы, которую тест сверяет с полем `version` в `apps/codelab_desktop/pubspec.yaml`;
- `<os>` и `<arch>` — операционная система и архитектура процесса (`macOS arm64`, `Linux x64`, `Windows x64`);
- `<agentVersion>` — `embeddedAgentVersion` моста `codelab_embedded` (spec embedded-agent «Версия встроенного агента для клиентов»).

В развёрнутом разделе SHALL быть:
- строка «License» — ссылка `MIT` (`settings-general-about-license`) и строка авторского права из `LICENSE`; ссылка открывает страницу «Legal» на вкладке «License»;
- строка «Config folder» — `$CODELAB_HOME`, разрешённый composition root, с `~` вместо домашнего каталога;
- кнопки «Copy diagnostics» (`settings-general-about-copy-diagnostics`), «Privacy policy» (`settings-general-about-privacy`), «Terms of use» (`settings-general-about-terms`), «Third-party notices» (`settings-general-about-third-party`), «Release notes» (`settings-general-about-release-notes`), «Open log folder» (`settings-general-about-open-logs`);
- InfoBar уровня `info` `settings-general-about-updates`: `Updates come from the installer or your package manager — the app does not update itself.` (D-16, U-29).

Строки «Channel» и «Signed by» НЕ SHALL показываться: в сборке нет источника этих значений (design.md change `add-app-general-page`, D11).

«Privacy policy», «Terms of use» и «Third-party notices» SHALL открывать страницу «Legal» на одноимённой вкладке без сети (design.md change `add-app-legal-page`, D9). Диалога `settings-general-third-party-dialog` НЕ SHALL быть: записи реестра и лицензии пакетов показывает только вкладка «Third-party notices» страницы «Legal», по тем же правилам (требование «Страница «Legal»: вкладка «Third-party notices»»).

«Release notes» SHALL открывать `CHANGELOG.md` репозитория CodeLab в браузере через порт `ExternalLinkOpener`. Адрес SHALL быть константой app, а не вводом пользователя.

«Open log folder» SHALL открывать каталог журналов app (`<application support>/logs`, тот же, что получает `CodeLabLoggingModule`) через порт `LocalFolderOpener` без создания каталога.

Сбой открытия ссылки или каталога SHALL показывать InfoBar `settings-general-about-open-failed`: `Couldn't open the release notes.` или `Couldn't open the log folder.`. Текст исключения и путь в InfoBar НЕ SHALL попадать.

Сбой «Copy diagnostics» (сбор данных окна, построение текста или запись в буфер обмена) SHALL показывать InfoBar уровня `warning` `settings-general-about-copy-failed`: `Couldn't copy the diagnostics.`. Подтверждение `Diagnostics copied.` при этом НЕ SHALL показываться, а текст диагностики НЕ SHALL класться в буфер обмена.

Если данные раздела не читаются (ресурсы `assets/legal/` сборки), вместо развёрнутого раздела под заголовком «About» SHALL показываться InfoBar уровня `warning` `settings-general-about-load-failed`: `Couldn't load the About section.`. Остальные блоки страницы при этом SHALL работать.

Текст исключения и путь НЕ SHALL попадать ни в один InfoBar раздела.

#### Scenario: Версии в заголовке
- **WHEN** app версии `0.1.0` запущен на macOS arm64, и пользователь открывает «General»
- **THEN** заголовок «About» содержит `CodeLab 0.1.0` и `macOS arm64 · embedded agent 0.1.0`, строк «Channel» и «Signed by» нет

#### Scenario: Ссылки «About» открывают вкладки Legal
- **WHEN** пользователь по очереди возвращается на «General» и нажимает `settings-general-about-privacy`, `settings-general-about-terms`, `settings-general-about-license` и `settings-general-about-third-party`
- **THEN** каждый раз открыта страница «Legal» с выбранной вкладкой `settings-legal-tab-privacy-policy`, `settings-legal-tab-terms-of-use`, `settings-legal-tab-license` и `settings-legal-tab-third-party-notices` соответственно, `ExternalLinkOpener.open` не вызывался

#### Scenario: Диалога сторонних уведомлений нет
- **WHEN** пользователь нажимает `settings-general-about-third-party`
- **THEN** диалога `settings-general-third-party-dialog` нет, вкладка «Third-party notices» страницы «Legal» показывает запись `JetBrains Mono (шрифт в пакете gpt_markdown)` и список лицензий пакетов

#### Scenario: Release notes через порт
- **WHEN** пользователь нажимает «Release notes»
- **THEN** `ExternalLinkOpener.open` вызван один раз с адресом `CHANGELOG.md` репозитория CodeLab

#### Scenario: Каталог журналов не открылся
- **WHEN** `LocalFolderOpener` возвращает `failed` для каталога журналов
- **THEN** показан InfoBar `settings-general-about-open-failed` с `Couldn't open the log folder.` без пути

#### Scenario: Диагностика не скопировалась
- **WHEN** запись в буфер обмена при «Copy diagnostics» завершается ошибкой
- **THEN** показан InfoBar `settings-general-about-copy-failed` с `Couldn't copy the diagnostics.` без текста исключения, `Diagnostics copied.` не показан, журнал содержит `settings.about_action` с `action: copy_diagnostics` и `outcome: failed`

#### Scenario: Данные раздела не прочитались
- **WHEN** ресурс `assets/legal/LICENSE` не читается, и пользователь открывает «General»
- **THEN** под заголовком «About» показан InfoBar `settings-general-about-load-failed` с `Couldn't load the About section.` без пути и текста исключения, кнопок раздела нет, блоки «Agent defaults», «Interface», «Startup and files» и «Privacy» работают; журнал содержит `settings.about_load_failed` с именем типа исключения

### Requirement: События журнала страницы «General»
Страница SHALL писать события логгера `codelab_desktop.settings`:
- `agent_defaults.loaded` (`rows`, `access`), `agent_defaults.unreadable`, `agent_defaults.load_discarded` (`reason: reload | access_changed | closed`);
- `agent_defaults.saved` (`key`, `restart_required`, `overridden`) и `agent_defaults.save_failed` (`key`, `outcome: conflict | rejected | inline_secret | stale | error`, при `error` — имя типа исключения);
- `settings.reopen_last_project_changed` (`enabled`) и `settings.reopen_last_project_save_failed` (имя типа исключения);
- `settings.about_action` (`action: copy_diagnostics | release_notes | open_logs`, `outcome: opened | copied | failed | rejected_scheme | missing`);
- `settings.legal_link` (`from: privacy_block | about`, `tab: privacy_policy | terms_of_use | license | third_party_notices`) — переход на страницу «Legal»;
- `settings.about_load_failed` (`error_type` — имя типа исключения) — данные раздела «About» не прочитались.

Старт app с выключенной настройкой SHALL писать `app.reopen_last_project_skipped`. Сбой чтения настройки SHALL писать `app.reopen_last_project_unreadable` с именем типа исключения.

События НЕ SHALL содержать значений ключей конфигурации, путей, URL и текстов исключений (CFG-10; AGENTS.md §16).

#### Scenario: Запись без значения в журнале
- **WHEN** пользователь записывает `budget.max_steps: 80`
- **THEN** журнал содержит `agent_defaults.saved` с `key: budget.max_steps` и не содержит `80` ни в одном поле события

#### Scenario: Переход на Legal в журнале
- **WHEN** пользователь нажимает `settings-general-about-terms`
- **THEN** журнал содержит `settings.legal_link` с `from: about` и `tab: terms_of_use`

## ADDED Requirements

### Requirement: Страница «Legal»: видимость и вкладки
Страница «Legal» (`settings-legal`, последний пункт группы «App») SHALL показывать правовые документы сборки на четырёх вкладках в таком порядке (`dart-agent-and-clients` §12.7.7а; артборды 32–35):
1. «Privacy policy» (`settings-legal-tab-privacy-policy`) — `PRIVACY.md`;
2. «Terms of use» (`settings-legal-tab-terms-of-use`) — `TERMS.md`;
3. «License» (`settings-legal-tab-license`) — требование «Страница «Legal»: вкладка «License»»;
4. «Third-party notices» (`settings-legal-tab-third-party-notices`) — требование «Страница «Legal»: вкладка «Third-party notices»».

Вкладки SHALL быть одной группой с подписью `Legal documents` для программ чтения с экрана; выбранная вкладка SHALL объявляться выбранной. В окне шириной 800 px и на русском языке подписи вкладок НЕ SHALL обрезаться: не помещающиеся вкладки прокручиваются по горизонтали.

Страница SHALL быть видна в каждой сборке app: её содержимое задают ресурсы сборки, а не конфигурация (SETUP-17; design.md, D1). Выбор пунктом навигации, поиском или последней сохранённой страницей SHALL открывать вкладку «Privacy policy». Переход со страницы «General» SHALL открывать вкладку, названную ссылкой. Выбранная вкладка и запрос поиска НЕ SHALL сохраняться между открытиями страницы; `codelab.settings.last_page` хранит только страницу (`legal`).

Под вкладками SHALL стоять подпись источника `settings-legal-source`: `Bundled with CodeLab <version> as <asset> · readable offline`, где `<asset>` — путь ресурса показанного документа (`assets/legal/PRIVACY.md`, `assets/legal/TERMS.ru.md`, `assets/legal/LICENSE`, `assets/legal/THIRD_PARTY_NOTICES.md`).

Страница НЕ SHALL обращаться к сети для показа документов. Кнопок и флажков принятия условий, записи о согласии в `shared_preferences` и `~/.codelab` НЕ SHALL быть (D-29, §12.7.7а). Кнопок «Copy link», «Open on the web», «Copy all», «Open LICENSE» и оглавления «On this page» артбордов НЕ SHALL быть в этой сборке (design.md, D12).

Поиск «Find a setting» SHALL находить «Legal» по английским ключевым словам `legal`, `privacy`, `terms`, `license`, `notices`, `third-party`, `telemetry`, `packages` при любом языке интерфейса, а при русском — ещё по `правовая`, `конфиденциальность`, `условия`, `лицензия`, `уведомления`, `телеметрия`, `пакеты` (`settingsSearchKeywordsLegal`).

#### Scenario: Пункт навигации открывает политику
- **WHEN** пользователь выбирает `settings-nav-legal`
- **THEN** выбрана вкладка `settings-legal-tab-privacy-policy`, показан текст `assets/legal/PRIVACY.md`, подпись `settings-legal-source` содержит `assets/legal/PRIVACY.md`

#### Scenario: Последняя страница без вкладки
- **WHEN** пользователь ушёл со страницы «Legal» с вкладки «License» и снова открыл настройки
- **THEN** открыта страница «Legal» на вкладке «Privacy policy»

#### Scenario: Принимать нечего
- **WHEN** пользователь открывает каждую из четырёх вкладок
- **THEN** на странице нет флажка, кнопки или переключателя согласия, а `shared_preferences` не изменились

#### Scenario: Узкое окно на русском
- **WHEN** app работает на русском в окне шириной 800 px, и пользователь открывает «Legal»
- **THEN** подписи четырёх вкладок видны целиком без многоточия, переполнения раскладки нет

#### Scenario: Поиск страницы по ключевому слову
- **WHEN** пользователь вводит `privacy` в «Find a setting»
- **THEN** в навигации остаётся `settings-nav-legal`

### Requirement: Страница «Legal»: документы на языке интерфейса
Вкладки «Privacy policy» и «Terms of use» SHALL показывать редакцию документа на языке интерфейса app (spec app-settings «Язык интерфейса app»): при русском — `assets/legal/PRIVACY.ru.md` и `assets/legal/TERMS.ru.md`, при любом другом — `assets/legal/PRIVACY.md` и `assets/legal/TERMS.md` (design.md, D2). Смена языка при открытой странице SHALL показывать редакцию нового языка без перезапуска; выбранная вкладка и запрос поиска при этом SHALL сохраняться.

Документ SHALL показываться как есть, без сокращений и правок, как markdown (`CodeLabMarkdown` кита) с выделением текста.

Если ресурс документа не читается, на месте документа SHALL показываться InfoBar уровня `warning` `settings-legal-load-failed`: `Couldn't load this document.`. Остальные вкладки SHALL работать. Путь и текст исключения в InfoBar НЕ SHALL попадать.

#### Scenario: Русская редакция
- **WHEN** app работает на русском, и пользователь открывает вкладку «Terms of use»
- **THEN** показан текст `assets/legal/TERMS.ru.md`, подпись `settings-legal-source` содержит `assets/legal/TERMS.ru.md`

#### Scenario: Английская редакция для другого языка
- **WHEN** app работает на английском, и пользователь открывает вкладку «Privacy policy»
- **THEN** показан текст `assets/legal/PRIVACY.md`

#### Scenario: Смена языка при открытой странице
- **WHEN** открыта вкладка «Privacy policy» на английском, и пользователь переключает язык интерфейса на русский
- **THEN** показан текст `assets/legal/PRIVACY.ru.md`, выбрана та же вкладка

#### Scenario: Документ не прочитался
- **WHEN** ресурс `assets/legal/TERMS.md` не читается, и пользователь открывает вкладку «Terms of use» на английском
- **THEN** показан InfoBar `settings-legal-load-failed` с `Couldn't load this document.` без пути; вкладка «Privacy policy» показывает свой документ; журнал содержит `legal.document_load_failed` с `tab: terms_of_use` и именем типа исключения

### Requirement: Страница «Legal»: ссылки внутри документов
Ссылки в показанном документе SHALL обрабатываться политикой app, а не виджетом (`CodeLabMarkdownScope`; design.md, D8):
- относительная ссылка на `PRIVACY.md`, `PRIVACY.ru.md`, `TERMS.md`, `TERMS.ru.md`, `LICENSE` или `THIRD_PARTY_NOTICES.md` (с `./` или без, с якорем или без) SHALL переключать вкладку страницы на этот документ без сети;
- ссылка `https:` SHALL открываться в браузере через порт `ExternalLinkOpener`;
- остальные ссылки SHALL быть неактивными.

Изображения в документах НЕ SHALL загружаться.

Если порт не открыл ссылку `https:` (`failed` или `rejectedScheme`), SHALL показываться InfoBar `settings-legal-link-failed`: `Couldn't open the link.`. Адрес и текст исключения в InfoBar НЕ SHALL попадать.

#### Scenario: Ссылка условий на лицензию
- **WHEN** на вкладке «Terms of use» пользователь нажимает ссылку на `LICENSE`
- **THEN** выбрана вкладка `settings-legal-tab-license`, `ExternalLinkOpener.open` не вызывался

#### Scenario: Ссылка на неизвестный файл неактивна
- **WHEN** документ содержит ссылку `SECURITY.md`
- **THEN** ссылка показана неактивной, нажатие ничего не открывает

### Requirement: Страница «Legal»: вкладка «License»
Вкладка «License» SHALL показывать:
1. краткое содержание MIT (`settings-legal-license-summary`) из трёх строк: «Allowed» — `Use, copy, modify, merge, publish, distribute, sublicense and sell copies`, «Condition» — `Keep the copyright and license notice in copies or substantial portions`, «No warranty» — `Provided “as is”; the authors are not liable for damages`, и под ними — `This summary is not the license. The full text below is what applies.`;
2. абзац «Third-party components»: `Open-source packages bundled with CodeLab keep their own licenses. They are listed in Third-party notices.` со ссылкой `settings-legal-license-notices-link`, которая выбирает вкладку «Third-party notices»;
3. полный текст `assets/legal/LICENSE` (`settings-legal-license-text`) как есть, моноширинно, с выделением.

Краткое содержание SHALL быть сообщениями ARB `en` и `ru`; полный текст `LICENSE` НЕ SHALL переводиться.

#### Scenario: Полный текст лицензии
- **WHEN** пользователь открывает вкладку «License» на русском
- **THEN** краткое содержание показано на русском, `settings-legal-license-text` побайтно совпадает с текстом `assets/legal/LICENSE` и содержит `MIT License`

#### Scenario: Переход к сторонним уведомлениям
- **WHEN** пользователь нажимает `settings-legal-license-notices-link`
- **THEN** выбрана вкладка `settings-legal-tab-third-party-notices`

### Requirement: Страница «Legal»: вкладка «Third-party notices»
Вкладка «Third-party notices» SHALL показывать два раздела (правила D13 change `add-app-general-page` сохраняются; design.md, D10):
1. «Notices register» (`settings-legal-notices-records`) — подпись `Entries of the CodeLab third-party notices register, as kept in the repository.` и записи раздела `## Записи` файла `assets/legal/THIRD_PARTY_NOTICES.md` как есть, без перевода, на любом языке интерфейса. Заголовок первого уровня файла, вводная и раздел `## Формат записи` НЕ SHALL показываться; если раздела `## Записи` нет, SHALL показываться весь файл без заголовка первого уровня;
2. «Package licenses» — InfoBar уровня `info` `settings-legal-packages-info`: `Every package the build collected, including development tools of the workspace. A longer list is safe; a missing license would not be.`, поле поиска (требование «Страница «Legal»: поиск по пакетам») и список пакетов.

Пакет SHALL быть уникальным именем из поля `packages` записей реестра лицензий Flutter (`LicenseRegistry`); запись с несколькими именами SHALL относиться к каждому. Пакеты SHALL идти по имени. Пакет SHALL показываться свёрнутым `Expander` (`settings-legal-package-<name>`) с именем в заголовке и числом лицензий (`1 license`, `2 licenses`); развёрнутый — текстами лицензий как есть, с выделением.

Пока реестр собирается, вместо списка SHALL показываться индикатор `settings-legal-packages-loading`. Сбой реестра НЕ SHALL прятать записи реестра уведомлений: список SHALL показывать то, что успело собраться.

#### Scenario: Записи реестра офлайн
- **WHEN** сети нет, и пользователь открывает вкладку «Third-party notices» на английском
- **THEN** `settings-legal-notices-records` содержит запись `JetBrains Mono (шрифт в пакете gpt_markdown)` и подпись `Entries of the CodeLab third-party notices register, as kept in the repository.`; раздела `Формат записи` и строки шаблона `<Название источника>` нет

#### Scenario: Пакет из записи с двумя именами
- **WHEN** реестр лицензий возвращает одну запись с пакетами `alpha` и `beta` и одну запись с пакетом `alpha`
- **THEN** список содержит `settings-legal-package-alpha` с `2 licenses` и `settings-legal-package-beta` с `1 license`, счётчик — `2 packages`

#### Scenario: Сбой реестра лицензий
- **WHEN** поток реестра лицензий отдаёт запись пакета `alpha` и завершается ошибкой
- **THEN** записи реестра уведомлений показаны, список содержит `settings-legal-package-alpha`, журнал содержит `legal.licenses_collected` с `packages: 1` и `failed: true`

### Requirement: Страница «Legal»: поиск по пакетам
Над списком пакетов вкладки «Third-party notices» SHALL стоять поле `settings-legal-packages-search` с подсказкой `Search packages` и доступным именем `Search packages by name` (§12.7.7а; артборды 35, 35a–35c; design.md, D5–D7). Поиск SHALL только сужать показ, а не менять состав списка:
- пакет показывается, если запрос без пробелов по краям входит в его имя как подстрока без учёта регистра; пустой запрос или запрос из одних пробелов показывает все пакеты;
- записи реестра уведомлений («Notices register») SHALL оставаться видимыми при любом запросе;
- счётчик `settings-legal-packages-count` SHALL показывать `<N> packages` при пустом запросе и `<M> of <N> packages` при непустом (`0 of <N> packages`, если совпадений нет), где `N` — число пакетов, `M` — число показанных;
- в имени показанного пакета SHALL подсвечиваться каждое вхождение запроса без учёта регистра; текст имени и его подпись для программ чтения с экрана SHALL оставаться прежними; раскрытие пакета SHALL работать так же, как без запроса;
- при непустом запросе в поле SHALL быть кнопка очистки `settings-legal-packages-clear` с доступным именем `Clear search`; она очищает запрос и возвращает полный список;
- если совпадений нет, вместо списка SHALL показываться блок `settings-legal-packages-empty`: заголовок `No packages match`, текст `No package name contains “<query>”. The notices register above is not affected by search.` и кнопка `Clear search` (`settings-legal-packages-empty-clear`) с тем же действием, что у крестика. Запрос в тексте SHALL показываться с экранированием управляющих и bidi-символов (`escapeForDisplay`).

Запрос SHALL жить только в состоянии страницы: НЕ SHALL сохраняться между открытиями страницы, НЕ SHALL попадать в журнал, `shared_preferences`, `~/.codelab` и запросы за пределы процесса. Подписи поля, счётчика, кнопок и пустого блока SHALL быть сообщениями ARB `en` и `ru` с ICU `plural`; имена пакетов НЕ SHALL переводиться.

#### Scenario: Совпадение без учёта регистра
- **WHEN** пакеты — `flutter`, `flutter_bloc`, `fpdart`, `val_latex_flutter`, и пользователь вводит `FLUTTER`
- **THEN** показаны `flutter`, `flutter_bloc`, `val_latex_flutter` в этом порядке, счётчик — `3 of 4 packages`, в каждом имени подсвечено `flutter`, записи реестра видны

#### Scenario: Все вхождения подсвечены
- **WHEN** есть пакет `aa_aa`, и пользователь вводит `aa`
- **THEN** в имени `aa_aa` подсвечены оба вхождения `aa`, видимый текст имени — `aa_aa`

#### Scenario: Пустой запрос
- **WHEN** пользователь вводит три пробела
- **THEN** показаны все пакеты, счётчик — `4 packages`, кнопки `settings-legal-packages-clear` нет

#### Scenario: Ничего не найдено
- **WHEN** пользователь вводит `reqwest`
- **THEN** списка нет, показан `settings-legal-packages-empty` с `No packages match` и `No package name contains “reqwest”. The notices register above is not affected by search.`, счётчик — `0 of 4 packages`, записи реестра видны

#### Scenario: Очистка из пустого блока
- **WHEN** совпадений нет, и пользователь нажимает `settings-legal-packages-empty-clear`
- **THEN** поле пусто, показаны все пакеты, счётчик — `4 packages`

#### Scenario: Запрос не сохраняется и не пишется в журнал
- **WHEN** пользователь вводит `marker-query-7f3a`, уходит со страницы «Legal» и возвращается на неё
- **THEN** поле поиска пусто, ни одна запись журнала не содержит `marker-query-7f3a`, `shared_preferences` не содержат `marker-query-7f3a`

#### Scenario: Русский интерфейс
- **WHEN** app работает на русском, пакетов 21, и пользователь вводит `flutter`, совпадают 5
- **THEN** счётчик — `5 из 21 пакета`, имена пакетов не переведены

### Requirement: События журнала страницы «Legal»
Страница «Legal» SHALL писать события логгера `codelab_desktop.settings`:
- `legal.tab_selected` (`tab: privacy_policy | terms_of_use | license | third_party_notices`, `source: open | tab | link`), уровень `debug`;
- `legal.document_load_failed` (`tab`, `error_type` — имя типа исключения), уровень `warning`;
- `legal.licenses_collected` (`packages` — число пакетов, `failed` — был ли сбой реестра), уровень `info`;
- `legal.link_opened` (`target: tab | external`, `outcome: opened | failed | rejected_scheme`).

События НЕ SHALL содержать запрос поиска, число совпадений, путей, URL, текстов документов и текстов исключений (AGENTS.md §16; design.md, D11).

#### Scenario: Поиск не оставляет следов в журнале
- **WHEN** пользователь вводит и очищает запрос на вкладке «Third-party notices»
- **THEN** за это время журнал не получил ни одного события
