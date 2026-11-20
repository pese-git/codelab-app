## ADDED Requirements

### Requirement: Страница «General»: состав и порядок
Страница «General» группы «App» SHALL показывать блоки в таком порядке (артборд «26 Settings — General»; design.md change `add-app-general-page`, D17):
1. InfoBar `settings-general-shared-info` и блок «Agent defaults» (`settings-general-agent-defaults`) — требования «Умолчания агента на странице «General»: …»;
2. блок «Interface» со строкой «Language» (`settings-general-language`, spec app-settings «Язык интерфейса app»); строка и её поведение этим требованием не меняются;
3. блок «Startup and files» со строкой «Reopen the last project and its tabs» (`settings-general-reopen-last-project`);
4. раздел «About» (`settings-general-about`).

Строка без поведения в текущей сборке НЕ SHALL показываться (SETUP-17). Строки «When I press Enter during a turn», «Sidebar opens on», «Send crash reports» и ссылка «Privacy policy» НЕ SHALL показываться (design.md, D8, D17). Блок, в котором не осталось видимых строк, SHALL быть скрыт вместе с заголовком.

Поиск «Find a setting» SHALL находить «General» по английским ключевым словам `language`, `budget`, `steps`, `compaction`, `subagent`, `log level`, `startup`, `reopen`, `ignored`, `about`, `version`, `license`, `diagnostics` при любом языке интерфейса, а при русском интерфейсе — ещё по русским `язык`, `бюджет`, `шаги`, `сжатие`, `субагент`, `уровень журнала`, `запуск`, `открывать`, `игнорируемые`, `о программе`, `версия`, `лицензия`, `диагностика`. Слова обоих языков SHALL храниться в каталогах ARB `en` и `ru` (`settingsSearchKeywordsGeneral`, список через запятую; spec app-settings «Навигация настроек», change `add-desktop-localization`).

Все тексты страницы SHALL браться из каталогов ARB `en` и `ru` (spec app-settings «Локализация интерфейса app»). Ключи конфигурации, значения, источники `default`, `user`, `project`, `local`, `config`, `env`, пути и версии SHALL показываться как есть.

#### Scenario: Порядок блоков
- **WHEN** встроенный агент подключён, проект выбран, и пользователь открывает «General»
- **THEN** сверху вниз идут `settings-general-shared-info`, `settings-general-agent-defaults`, `settings-general-language`, `settings-general-reopen-last-project`, `settings-general-about`; строк Enter во время хода, «Sidebar opens on», «Send crash reports» и «Privacy policy» нет

#### Scenario: Поиск по ключевому слову
- **WHEN** пользователь вводит `compaction` в «Find a setting»
- **THEN** в навигации остаётся «General», а выбор результата открывает её

#### Scenario: Русское ключевое слово «General» зависит от языка интерфейса
- **WHEN** пользователь вводит `сжатие` в «Find a setting» сначала на русском интерфейсе, затем на английском
- **THEN** на русском в навигации остаётся «General», на английском ни одной страницы не найдено и показано `No settings match "сжатие"`

### Requirement: Умолчания агента на странице «General»: доступ и строки
Блок «Agent defaults» SHALL вычислять доступ так же, как «Providers», «MCP servers» и «Agents & modes»: `resolveSettingsAccess` для профиля текущего подключения, без подключения — для профиля по умолчанию; папка — папка сессии в фокусе, иначе выбранный проект, иначе без папки (требование «Доступ к настройкам агента на страницах Providers и MCP servers»). Смена подключения или папки SHALL перечитывать доступ и снимок. Снимок и запись SHALL идти через `AgentConfigStore` сессии страницы, строки — через `settingFieldsOf` моста `codelab_setup` (spec client-agent-setup «Состав моста codelab_setup для настройки агента»).

Блок SHALL показывать строки ключей реестра со `scope: shared` из разделов реестра Budget, Agent, Subagents и Logging, кроме ключей, у которых есть своя страница: `budget.max_steps`, `budget.max_tokens`, `budget.max_cost`, `budget.max_duration`, `compaction.enabled`, ключи `subagents.*` и `logging.level`. Ключи `agent.default_model`, `providers.*` («Providers»), `permissions.mode`, `agent.effort` («Agents & modes»), `mcp.servers` («MCP servers»), `permissions.deny`, `permissions.tools` (будущая «Permissions & tools») и `trusted_projects` (граница доверия) НЕ SHALL показываться на «General» (design.md, D2). Ключ реестра `scope: shared`, который не отнесён ни к «General», ни к странице-владельцу, SHALL ронять тест классификации, а не появляться на странице сам.

Строки SHALL группироваться по разделу реестра в порядке Budget, Agent, Subagents, Logging; внутри раздела — в порядке реестра. Над каждой непустой группой SHALL быть подзаголовок раздела на языке интерфейса (`Budget`, `Agent`, `Subagents`, `Logging`) с ключом `settings-general-agent-group-<section>` (`budget`, `agent`, `subagents`, `logging`). Строка SHALL показывать подпись ключа на языке интерфейса, ключ (`budget.max_steps`), итоговое значение (`SettingFieldView.displayValue`; для незаданного ключа без умолчания — `Not set`), источник `default`, `user`, `project`, `local`, `config` или `env` и тег `shared`. Ключ с `restartRequired` SHALL нести пометку `(applies after restart)`. Ключ строки — `settings-general-agent-row-<key>`. Описание строки НЕ SHALL обрезаться: при нехватке ширины оно переносится. Ключ SHALL переноситься только после `.` или `_` и SHALL быть доступен скринридеру целиком одной меткой.

Над блоком SHALL быть InfoBar уровня `info` `settings-general-shared-info`: `Shared with the codelab CLI. Rows marked shared come from the agent's settings registry and are saved to <home>/config.yaml; codelab /settings shows them too.`, где `<home>` — `$CODELAB_HOME` с `~` вместо домашнего каталога.

Для `RemoteReadOnly` и `NotManaged` блок НЕ SHALL читать локальный конфиг, НЕ SHALL показывать строк и InfoBar `settings-general-shared-info` и SHALL показывать InfoBar уровня `warning` `settings-general-agent-read-only`: `Read-only: this agent runs on <scheme://host:port>. Change its settings on that host: codelab config set.` или `Agent settings are managed by <agentName>.` (SETUP-2). Остальные блоки страницы при этом SHALL работать.

Если `config.yaml` не разбирается или нарушает схему, блок SHALL показывать проблемы загрузчика с путём ключа (`settings-general-agent-unreadable`) и НЕ SHALL предлагать запись. Пока снимок загружается, блок SHALL показывать индикатор загрузки, а остальные блоки страницы — работать.

#### Scenario: Строки из своего подмножества
- **WHEN** встроенный агент подключён, `$CODELAB_HOME/config.yaml` задаёт `budget.max_steps: 80` и `permissions.mode: ask`
- **THEN** блок показывает строку `settings-general-agent-row-budget.max_steps` со значением `80` и источником `user`, строку `settings-general-agent-row-compaction.enabled` со значением `true` и источником `default`; строк `permissions.mode`, `agent.effort`, `agent.default_model`, `trusted_projects` нет

#### Scenario: Новый ключ реестра без решения
- **WHEN** в реестр добавлен ключ `scope: shared`, который не отнесён ни к «General», ни к странице-владельцу
- **THEN** тест классификации ключей страницы падает и называет ключ

#### Scenario: Одинаковые подписи в разных группах
- **WHEN** встроенный агент подключён, и пользователь открывает «General»
- **THEN** строка `settings-general-agent-row-budget.max_steps` стоит под подзаголовком `settings-general-agent-group-budget` (`Budget`), а строка `settings-general-agent-row-subagents.max_steps` — под `settings-general-agent-group-subagents` (`Subagents`); на русском подзаголовки — «Бюджет» и «Субагенты»

#### Scenario: Узкое окно не обрезает описания и ключи
- **WHEN** app работает на русском, ширина области страницы соответствует окну 760 px, и пользователь открывает «General»
- **THEN** описание строки `settings-general-reopen-last-project` показано целиком, включая «Применится при следующем запуске», описания строк ключей не обрезаны многоточием, ключ `subagents.heartbeat_interval` разорван только после `.` или `_`, переполнения нет

#### Scenario: Пометка перезапуска
- **WHEN** блок показывает `logging.level`
- **THEN** строка несёт `(applies after restart)`

#### Scenario: WebSocket-агент
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp`, а в локальном `$CODELAB_HOME/config.yaml` есть `budget.max_steps: 80`
- **THEN** блок показывает `settings-general-agent-read-only` с `wss://devbox:7420` без `/acp`, строк и `settings-general-shared-info` нет, локальный файл не читался, а строка «Language» и раздел «About» доступны

#### Scenario: Битый конфиг
- **WHEN** `$CODELAB_HOME/config.yaml` не разбирается как YAML
- **THEN** блок показывает `settings-general-agent-unreadable` и не показывает редакторов; файл не изменён

### Requirement: Умолчания агента на странице «General»: запись
Редактор строки SHALL соответствовать типу дескриптора: `bool` — переключатель, `enumeration` — выпадающий список `enumValues`, `int`, `float` и `duration` — поле ввода. Поле ввода SHALL применять значение по Enter и при потере фокуса. Введённую строку SHALL разбирать `SettingsRegistry.parseCliValue`. При ошибке разбора запись НЕ SHALL выполняться, а под полем SHALL показываться подсказка формата на языке интерфейса, построенная по типу и границам дескриптора: `Enter a whole number of 1 or greater.`, `Enter a whole number from 1 to 3.`, `Enter a number.`, `Enter a duration like 500ms, 30s, 2m or 1h.`. Введённое значение в подсказку НЕ SHALL попадать. Пустое поле у ключа, заданного в слое `user`, SHALL записывать `UnsetValue`; у ключа, не заданного в `user`, пустое поле SHALL возвращать показанное значение без записи.

Запись SHALL выполняться одним `AgentConfigStore.apply` с одной правкой в слой `user`. Слои `project`, `projectLocal` и файл `--config` блок НЕ SHALL записывать (SETUP-3; design.md, D4). Под заголовком блока SHALL быть подпись `Changes are saved for all projects.`.

Строка НЕ SHALL редактироваться, и вместо редактора SHALL показываться значение с причиной, если правило моста `settingEditRefusalOf` отказывает (spec client-agent-setup «Правила правки строк настроек агента»):
- ключ хранит имя секрета — `Change it with codelab secret set.`;
- значение замаскировано — `This value contains a secret; change it in the config file.`;
- источник `config` или `env` — `Set by <source>; it cannot be changed here.`.

Если источник строки — `project` или `local`, строка SHALL оставаться редактируемой и показывать подпись `This project overrides it (<source>).`.

После `ConfigSaved` блок SHALL перечитывать снимок и строить баннер `settings-general-agent-banner` по действующему значению нового снимка (как D16 change `add-settings-agents-modes`):
- значение совпало с записанным — `Saved.`;
- значение совпало, и ключ входит в `restartRequiredKeys` — `Saved. Applies after Restart agent.`, если агент профиля подключён, иначе `Saved. Applies when the agent starts.`;
- значение перекрыто другим слоем — баннер уровня `warning` `Saved to all projects; <source> overrides it: the agent uses <effective>.` с тем же хвостом о перезапуске;
- перечитать не удалось — `Saved to <home>/config.yaml.`.

`ConfigConflict` SHALL давать баннер `The config file changed on disk; the page was reloaded. Try again.` и перечитывание снимка без автоповтора (SETUP-6). `ConfigRejected` SHALL давать баннер уровня `error` с путём ключа и текстом проблемы писателя как есть. `ConfigInlineSecret` SHALL давать баннер `Change it with codelab secret set.`. Пока идёт запись, повторные правки блока SHALL игнорироваться. Новая правка строки — в том числе неверный ввод и пустое поле без записи — SHALL снимать баннер прошлой записи.

Результат загрузки или записи, начатой до смены подключения, папки или до закрытия страницы, НЕ SHALL менять состояние блока. Правка, начатая до новой загрузки, НЕ SHALL записываться.

Блок НЕ SHALL отправлять агенту запросов ACP.

#### Scenario: Смена лимита шагов
- **WHEN** встроенный агент подключён, `budget.max_steps` нигде не задан, и пользователь вводит `80` в поле строки `settings-general-agent-row-budget.max_steps` и нажимает Enter
- **THEN** `$CODELAB_HOME/config.yaml` содержит `budget.max_steps: 80`, источник строки — `user`, баннер `settings-general-agent-banner` — `Saved.`; агенту не отправлено ни одного запроса

#### Scenario: Неверное число
- **WHEN** пользователь вводит `0` в поле `budget.max_steps`
- **THEN** под полем показано `Enter a whole number of 1 or greater.` без `0`, файл конфига не изменён

#### Scenario: Ключ с перезапуском
- **WHEN** встроенный агент подключён, и пользователь выбирает `debug` в строке `logging.level`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `logging.level: debug`, баннер — `Saved. Applies after Restart agent.`

#### Scenario: Перекрытие проектным файлом
- **WHEN** выбран проект `/work/demo`, его `.codelab/config.local.yaml` задаёт `compaction.enabled: false`, и пользователь включает `compaction.enabled`
- **THEN** `$CODELAB_HOME/config.yaml` содержит `compaction.enabled: true`, `/work/demo/.codelab/config.local.yaml` не изменён, баннер уровня `warning` содержит `Saved to all projects; local overrides it: the agent uses false`

#### Scenario: Значение из окружения
- **WHEN** `budget.max_steps` задан переменной окружения агента
- **THEN** строка показывает значение и `Set by env; it cannot be changed here.` без редактора

#### Scenario: Сброс поля
- **WHEN** `$CODELAB_HOME/config.yaml` задаёт `budget.max_tokens: 100000`, и пользователь очищает поле и нажимает Enter
- **THEN** ключ `budget.max_tokens` удалён из `$CODELAB_HOME/config.yaml`, строка показывает `Not set` и источник `default`

#### Scenario: Конфликт записи
- **WHEN** файл конфига изменён на диске после загрузки снимка, и пользователь меняет `compaction.enabled`
- **THEN** файл не перезаписан, баннер содержит `The config file changed on disk`, снимок перечитан, повторной записи нет

#### Scenario: Неверный ввод после успешной записи
- **WHEN** запись `budget.max_steps: 80` дала баннер `Saved.`, и затем пользователь вводит `0` в поле `budget.max_steps`
- **THEN** баннера `settings-general-agent-banner` нет, под полем показано `Enter a whole number of 1 or greater.`, файл конфига не изменён

#### Scenario: Смена подключения во время записи
- **WHEN** запись `budget.max_steps` идёт, и подключение переходит на профиль `wss://devbox:7420/acp`
- **THEN** блок показывает `settings-general-agent-read-only`, баннера о записи нет

### Requirement: Открытие последнего проекта при запуске
Строка «Reopen the last project and its tabs» (`settings-general-reopen-last-project`) SHALL быть переключателем настройки app `codelab.workspace.reopen_last_project` в `shared_preferences` (`bool`, по умолчанию включено; во включённом состоянии ключ удаляется). Подпись строки SHALL быть `On: open the last project and its open sessions. Off: start with recent projects in the sidebar. Applies at the next start.` «Its tabs» в этой сборке — открытые сессии снимка рабочего пространства (spec acp-client-kit «Восстановление после перезапуска»).

При старте app SHALL читать настройку до восстановления проекта прошлого запуска:
- включено — поведение не меняется (spec acp-client-kit «Восстановление после перезапуска»);
- выключено — app НЕ SHALL выбирать проект из снимка, НЕ SHALL восстанавливать его сессии и НЕ SHALL запускать агента при старте. Сайдбар SHALL показывать недавние проекты и «Open folder…» (spec agent-workbench-ui «"Open Project" offers native browse and recent projects»). Рабочее пространство SHALL стартовать через `ClientWorkspace.startWithoutRestore()`, так что снимок этого запуска пишется как обычно;
- значение не читается (сбой хранилища, нестроковое или небулево значение) — как при включённом, с предупреждением в журнале без текста ошибки; значение не перезаписывается.

Переключение SHALL сразу записывать значение и НЕ SHALL менять открытый проект, сессии и подключение. Сбой записи SHALL оставлять переключатель в выбранном положении и показывать `Couldn't save this setting. The previous value applies at the next start.` с кнопкой `Retry` (`settings-general-reopen-last-project-retry`).

#### Scenario: По умолчанию проект прошлого запуска открывается
- **WHEN** ключа `codelab.workspace.reopen_last_project` нет, а снимок прошлого запуска содержит проект `/work/app` с активной сессией `sess_42`
- **THEN** app выбирает `/work/app` и при первом подключении загружает `sess_42`, как раньше

#### Scenario: Выключено — старт без проекта
- **WHEN** пользователь выключил «Reopen the last project and its tabs», закрыл app и запустил снова, а снимок содержит проект `/work/app`
- **THEN** проект не выбран, агент не запущен, `session/load` и `session/new` не отправлены, сайдбар показывает недавние проекты с `/work/app` и «Open folder…»

#### Scenario: Выключено — снимок нового запуска пишется
- **WHEN** настройка выключена, app стартовал без проекта, пользователь выбрал проект `/work/other`, затем включил настройку и перезапустил app
- **THEN** при старте выбран `/work/other`, а не проект прошлого снимка

#### Scenario: Переключение не трогает текущую работу
- **WHEN** открыт проект `/work/app` с идущей сессией, и пользователь выключает настройку
- **THEN** проект, сессии и подключение не меняются, агенту не отправлено ни одного запроса

### Requirement: Раздел «About» страницы «General»
Раздел «About» (`settings-general-about`) SHALL быть Fluent `Expander`, по умолчанию свёрнутым. В заголовке SHALL быть `CodeLab <version>` и строка `<os> <arch> · embedded agent <agentVersion>`, где:
- `<version>` — версия сборки app из константы, которую тест сверяет с полем `version` в `apps/codelab_desktop/pubspec.yaml`;
- `<os>` и `<arch>` — операционная система и архитектура процесса (`macOS arm64`, `Linux x64`, `Windows x64`);
- `<agentVersion>` — `embeddedAgentVersion` моста `codelab_embedded` (spec embedded-agent «Версия встроенного агента для клиентов»).

В развёрнутом разделе SHALL быть:
- строка «License» — `MIT` и строка авторского права из `LICENSE`;
- строка «Config folder» — `$CODELAB_HOME`, разрешённый composition root, с `~` вместо домашнего каталога;
- кнопки «Copy diagnostics» (`settings-general-about-copy-diagnostics`), «Third-party notices» (`settings-general-about-third-party`), «Release notes» (`settings-general-about-release-notes`), «Open log folder» (`settings-general-about-open-logs`);
- InfoBar уровня `info` `settings-general-about-updates`: `Updates come from the installer or your package manager — the app does not update itself.` (D-16, U-29).

Строки «Channel» и «Signed by» НЕ SHALL показываться: в сборке нет источника этих значений (design.md, D11).

«Third-party notices» SHALL открывать диалог `settings-general-third-party-dialog` с записями раздела `## Записи` файла `THIRD_PARTY_NOTICES.md` из ресурсов сборки и списком лицензий пакетов из реестра лицензий Flutter. Заголовок первого уровня файла, вводная и раздел `## Формат записи` НЕ SHALL показываться. Записи SHALL показываться как есть, без перевода, на любом языке интерфейса. Перед ними SHALL быть подпись `Entries of the CodeLab third-party notices register, as kept in the repository.` на языке интерфейса. Если раздела `## Записи` нет, SHALL показываться весь файл без заголовка первого уровня. Диалог SHALL работать без сети (spec licensing-and-attribution «Лицензия и сторонние уведомления в сборке app»).

«Release notes» SHALL открывать `CHANGELOG.md` репозитория CodeLab в браузере через порт `ExternalLinkOpener`. Адрес SHALL быть константой app, а не вводом пользователя.

«Open log folder» SHALL открывать каталог журналов app (`<application support>/logs`, тот же, что получает `CodeLabLoggingModule`) через порт `LocalFolderOpener` без создания каталога.

Сбой открытия ссылки или каталога SHALL показывать InfoBar `settings-general-about-open-failed`: `Couldn't open the release notes.` или `Couldn't open the log folder.`. Текст исключения и путь в InfoBar НЕ SHALL попадать.

Сбой «Copy diagnostics» (сбор данных окна, построение текста или запись в буфер обмена) SHALL показывать InfoBar уровня `warning` `settings-general-about-copy-failed`: `Couldn't copy the diagnostics.`. Подтверждение `Diagnostics copied.` при этом НЕ SHALL показываться, а текст диагностики НЕ SHALL класться в буфер обмена.

Если данные раздела не читаются (ресурсы `assets/legal/` сборки), вместо развёрнутого раздела под заголовком «About» SHALL показываться InfoBar уровня `warning` `settings-general-about-load-failed`: `Couldn't load the About section.`. Остальные блоки страницы при этом SHALL работать.

Текст исключения и путь НЕ SHALL попадать ни в один InfoBar раздела.

#### Scenario: Версии в заголовке
- **WHEN** app версии `0.1.0` запущен на macOS arm64, и пользователь открывает «General»
- **THEN** заголовок «About» содержит `CodeLab 0.1.0` и `macOS arm64 · embedded agent 0.1.0`, строк «Channel» и «Signed by» нет

#### Scenario: Сторонние уведомления офлайн
- **WHEN** сети нет, и пользователь нажимает «Third-party notices»
- **THEN** диалог `settings-general-third-party-dialog` показывает запись `JetBrains Mono (шрифт в пакете gpt_markdown)` из `THIRD_PARTY_NOTICES.md` и список лицензий пакетов

#### Scenario: Только записи реестра
- **WHEN** app работает на английском, и пользователь нажимает «Third-party notices»
- **THEN** диалог содержит запись `JetBrains Mono (шрифт в пакете gpt_markdown)` и подпись `Entries of the CodeLab third-party notices register, as kept in the repository.`; заголовка `Third-party notices` из файла, раздела `Формат записи` и строки шаблона `<Название источника>` в диалоге нет, заголовок диалога `Third-party notices` показан один раз

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
- **THEN** под заголовком «About» показан InfoBar `settings-general-about-load-failed` с `Couldn't load the About section.` без пути и текста исключения, кнопок раздела нет, блоки «Agent defaults», «Interface» и «Startup and files» работают; журнал содержит `settings.about_load_failed` с именем типа исключения

### Requirement: Диагностика для отчёта без секретов и путей
«Copy diagnostics» SHALL класть в буфер обмена текст на английском из фиксированных строк, независимо от языка интерфейса (spec app-settings «Локализация интерфейса app»: диагностика не переводится):
- `CodeLab <version>`;
- `OS: <os> <arch>`;
- `Embedded agent: <agentVersion>`;
- `UI language: <locale> (preference: system|en|ru)`;
- `Connection: <embedded|stdio|websocket> · <state>`, где `<state>` — состояние подключения окна (`connecting`, `connected`, `reconnecting`, `failed`, `disconnected`);
- `Agent settings: editable|remote-read-only|not-managed`;
- `Config folder: default|custom` — задан ли `CODELAB_HOME`.

Текст НЕ SHALL содержать пути (в том числе папки проекта, `$CODELAB_HOME` и каталога журналов), URL, адреса и порты, id и имена профилей, команды и аргументы stdio-профиля, имена и значения переменных окружения, имена и значения секретов, id сессий, значения конфигурации и тексты исключений. После копирования страница SHALL показывать подтверждение `Diagnostics copied.`.

#### Scenario: Ничего лишнего в буфере
- **WHEN** окно подключено к профилю `wss://devbox:7420/acp?t=sk-test-leak-0123456789` с id `devbox`, выбран проект `/Users/alice/work/app`, `CODELAB_HOME` равен `/Users/alice/.codelab-test`, и пользователь нажимает «Copy diagnostics»
- **THEN** буфер обмена содержит `Connection: websocket · connected` и `Config folder: custom` и не содержит `sk-test-leak-0123456789`, `devbox`, `7420`, `/acp`, `alice` и `/Users`

#### Scenario: Текст не зависит от языка
- **WHEN** app работает на русском, и пользователь нажимает «Copy diagnostics»
- **THEN** буфер обмена содержит `UI language: ru (preference: ru)` и английские подписи строк

### Requirement: События журнала страницы «General»
Страница SHALL писать события логгера `codelab_desktop.settings`:
- `agent_defaults.loaded` (`rows`, `access`), `agent_defaults.unreadable`, `agent_defaults.load_discarded` (`reason: reload | access_changed | closed`);
- `agent_defaults.saved` (`key`, `restart_required`, `overridden`) и `agent_defaults.save_failed` (`key`, `outcome: conflict | rejected | inline_secret | stale | error`, при `error` — имя типа исключения);
- `settings.reopen_last_project_changed` (`enabled`) и `settings.reopen_last_project_save_failed` (имя типа исключения);
- `settings.about_action` (`action: copy_diagnostics | third_party | release_notes | open_logs`, `outcome: opened | copied | failed | rejected_scheme | missing`).
- `settings.about_load_failed` (`error_type` — имя типа исключения) — данные раздела «About» не прочитались.

Старт app с выключенной настройкой SHALL писать `app.reopen_last_project_skipped`. Сбой чтения настройки SHALL писать `app.reopen_last_project_unreadable` с именем типа исключения.

События НЕ SHALL содержать значений ключей конфигурации, путей, URL и текстов исключений (CFG-10; AGENTS.md §16).

#### Scenario: Запись без значения в журнале
- **WHEN** пользователь записывает `budget.max_steps: 80`
- **THEN** журнал содержит `agent_defaults.saved` с `key: budget.max_steps` и не содержит `80` ни в одном поле события
