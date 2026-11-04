## Context

Change вводит экран настроек codelab-app и первую страницу на нём — «Connection». Источники:
- `dart-agent-and-clients` §12.4.9 (навигация настроек, страница «Connection», «Add connection profile») и §12.4.11 (SETUP-2, SETUP-17, SETUP-19…SETUP-22);
- §12.3 A13 и DSK-24;
- §12.6.7 (U-26);
- `09-14-stage-9-switch-default.md` (задача 9.3);
- холст `docs/design/claude-design/` (`Connection`, `AddProfile`, `General`, `Components`).

При расхождении документы и `openspec/specs/` сильнее холста (README холста). Общие правила — `docs/architecture/state-management.md`, `layers-and-dependencies.md`, `observability.md` (их сверка — в D4, D6, D17).

Что уже есть в коде (на `develop`):
- **Подключение app.** `features/workbench/application/connection_cubit.dart` держит черновик формы (`ConnectionFormState`: тип, команда, аргументы, env, адрес, токен) и собирает из него профиль с фиксированными id `codelab_desktop.stdio` / `codelab_desktop.websocket` / `embedded`. Черновик живёт только в памяти, начальные значения — `codelabAgentStdioProfile` (`codelab serve --stdio`). В `shared_preferences` форма не пишется; там хранятся только `codelab.recent_projects`, `codelab.workspace.snapshot` (без профиля) и `codelab.dock.*`. Токен WebSocket лежит в `InMemorySecretSource` под ссылкой `codelab_desktop.websocket.token`.
- **Диалог.** `ConnectionSetupDialog` + `TransportSetupPanel` открываются из сайдбара (`workbench_shell.dart:131`, `onSettings`), с экрана подключения и из баннера соединения («Configure connection»). Переключатель «Run agent from project directory» — в `SettingsCubit`.
- **Kit.** Уже есть:
  - `ConnectionProfile` (`stdio`/`webSocket`/`embedded`), `ConfigTransportResolver`, `SecretSource`, `parseShellWords`, `parseEnvLines`;
  - порт `ProfileStore` (`load`/`save`/`remove`); его doc-комментарий говорит «App этот порт не использует»;
  - `ClientWorkspace.reconnect(profile:)` — загружает открытые сессии, поздние попытки отбрасывает по номеру попытки.
  
  `ClientWorkspace.restart` (§12.6.7) не реализован.
- **CLI.** `JsonFileProfileStore('$CODELAB_HOME/profiles.json')`, id профиля по `^[A-Za-z0-9][A-Za-z0-9_.-]*$`. WebSocket-профили CLI получают `tokenRef: env:CODELAB_AGENT_TOKEN`. Их читает `EnvSecretSource` (`apps/codelab_cli/lib/src/profiles/profile_arg.dart`), который уже понимает любую ссылку `env:<VAR>`, а прочие ссылки возвращает как `null`.
- **`codelab_ui`.** Есть `CodeLabExpanderCard`, `CodeLabBadge`, `CodeLabStatusIndicator`, `CodeLabButton`; виджетов навигации и строк настроек нет.

Ограничения:
- корневой `AGENTS.md`:
  - §3.4 — ACP не меняется;
  - §6 — presentation без IO;
  - §8 — явные состояния;
  - §9 и §12 — поздние результаты проверки и подключения;
  - §10 — секреты;
  - §13 — без слоёв «на вырост»;
  - §21 — интеграционные тесты на устройстве только в `release/*`;
- `codelab_client_core/AGENTS.md` — web-безопасность, allowlist, секреты только ссылками.

## Goals / Non-Goals

**Goals:**
- одна навигация настроек с фиксированным порядком и скрытыми пустыми страницами (SETUP-17);
- переходы workbench ↔ настройки только через `NavigationCubit` (DSK-24);
- у app и CLI один файл профилей `profiles.json`, одно правило id и одно правило ссылки на токен;
- добавление, проверка, переименование и удаление профиля с инвариантами SETUP-19 (часть про `env`), SETUP-20…SETUP-22;
- значение токена в профиль, состояние и логи не попадает: профиль хранит только ссылку `env:<NAME>`;
- `ConnectionSetupDialog` удалён без потери сценариев: подключение stdio, WebSocket и встроенного агента, папка проекта, переподключение;
- без явного выбора и app, и CLI запускают встроенный агент; `default` — второе имя встроенного агента, запись `default` в `profiles.json` игнорируется с предупреждением. Это закрывает задачу 9.3 в части профиля по умолчанию (D5, D21);
- ни одного нового поля или метода ACP.

**Non-Goals:** — раздел «Не входит» в `proposal.md`. В частности, хранение токенов в хранилище секретов агента («Use stored secret», «Store a new token», порт `ProfileSecrets`, порядок «секрет → профиль» с откатом, удаление собственного `codelab/profiles/<id>/token`) переходит в change `add-provider-setup-ui` (Q2).

## Decisions

### D1. Change A вводит `NavigationCubit` только для workbench и настроек

`AppDestination` в этом change — закрытая иерархия из двух веток:
- `WorkbenchDestination` — хаб;
- `SettingsDestination(SettingsPage page, {String? returnTo})` — `returnTo` содержит id сессии.

`BootDestination`, `OnboardingDestination`, `ProjectPickerDestination`, оверлеи и сочетания A13 (Cmd/Ctrl+O, «Go to» палитры, …) добавит `add-app-navigation-shell`; в `delivery-roadmap.md` §10.3 он сужается до этой части.

Почему: у каждого экрана A13 свой change и свой потребитель, и пустые ветки сейчас были бы абстракцией «на вырост» (§13). Настройкам нужен только переход туда и обратно. Иерархия `sealed` расширяется без правки существующих веток.

*Альтернативы:*
- (а) реализовать `add-app-navigation-shell` целиком — объём удваивается, а сочетания палитры зависят от `CommandPaletteCubit`, которого здесь нет;
- (б) открывать настройки модальным диалогом без `NavigationCubit` — нарушает DSK-24 и требует переделки во втором change.

### D2. Состояние навигации и возврат

`NavigationCubit` (`apps/codelab_desktop/lib/app/navigation/navigation_cubit.dart`) предоставляет:
- `openSettings({SettingsPage? page, required SettingsOpenSource source})` — `source`: `shortcut | sidebar | banner`, уходит в событие `settings.opened` (D17). Открывает `page`, иначе последнюю страницу, иначе «Connection», а если «Connection» не видна — первую видимую страницу по порядку D3. При пустом наборе видимых страниц ничего не делает и пишет в журнал событие уровня `debug`;
- `selectSettingsPage(page)`;
- `back({String? toSession})` — id сессии; `toSession` передаёт только InfoBar ожидающего одобрения.

**Последняя страница.** Хранится в `shared_preferences` `codelab.settings.last_page`. Значение — kebab-case slug страницы, тот же, что в ключе теста: `connection`, `mcp-servers`, `agents-and-modes`. Имя значения enum не используется, чтобы переименование в коде не ломало сохранённые данные (`state-management.md` §50).

Читает и пишет её узкий порт `SettingsPageStore` с реализацией на `shared_preferences` рядом с Cubit-ом в `lib/app/navigation/`. Потребитель один, поэтому в `lib/core/` порт не идёт (`layers-and-dependencies.md` §14). Ошибка чтения или записи — предупреждение в журнале (`settings.last_page_load_failed` / `settings.last_page_save_failed`, D17), а не отказ. Значение, не совпадающее ни с одной **видимой** страницей (скрытая в этой сборке, неизвестная), обрабатывается так же, как отсутствие значения.

**Гонка с чтением.** `openSettings` без `page` ждёт чтения `last_page`. Каждый вызов `openSettings` и `selectSettingsPage` увеличивает номер попытки. После `await` чтения результат применяется, только если номер не изменился. Явная страница, выбранная во время чтения, перекрывает прочитанную (AGENTS.md §12, поздний результат).

**`returnTo` и возврат.** `returnTo` — активная сессия на момент ухода. Повторный `openSettings` при уже открытых настройках `returnTo` не меняет. `back()` активирует сессию `returnTo`, если она ещё открыта (есть `SessionHandle`). Если её закрыли или она сменилась после переподключения, остаётся текущая активная сессия: другую сессию `back()` не подбирает (вариант (а) ревью итерации 1).

Навигация — состояние приложения, на которое реагирует UI (`state-management.md` §45). Cubit не зависит от `BuildContext`, экран рисует `CodeLabAppWidget` по его состоянию. Экран настроек рисуется вместо workbench, но workbench остаётся смонтированным (`IndexedStack`/`Offstage`): текст композера, прокрутка ленты и раскрытые блоки не теряются. Cubit-ы workbench живут в root scope и при уходе не закрываются.

**Фокус под настройками (H1 ревью итерации 1, безопасность).** Смонтированное рабочее место НЕ получает клавиатуру, пока открыты настройки:
- поддерево workbench обёрнуто в `ExcludeFocus(excluding: true)`, либо в `Visibility(visible: false, maintainState: true)`, которое сохраняет состояние и снимает фокус;
- `SettingsShell` — собственный `FocusScope` с `FocusTraversalGroup`: Tab и Shift+Tab ходят только внутри настроек;
- сочетания `CodeLabWorkbenchShortcuts` (Enter/Cmd+Enter — отправка, Esc — отмена хода, клавиши карточки одобрения) под настройками не срабатывают;
- Esc в настройках обрабатывает `SettingsShell`, и это всегда `back()`.

Инвариант (spec app-settings «Рабочее место недоступно с клавиатуры из настроек»): из экрана настроек клавиатурой нельзя отправить промпт, ответить на запрос разрешения и отменить ход. При возврате фокус восстанавливается в узле, где он был до ухода, если тот ещё жив; иначе фокус уходит в область рабочего места, то есть в её первый фокусируемый узел. `FocusNode` запоминает виджет `_CodeLabHome` по переходу состояния, а не `NavigationCubit`: Cubit не знает `BuildContext` и фокус. Почему это безопасность: Enter или Space, нажатый на невидимой карточке одобрения, ответил бы агенту без контекста tool call (AGENTS.md §10).

**Ожидающее одобрение (решение пользователя 2026-11-04).** Пока открыты настройки и у активной или любой открытой сессии есть ожидающий `session/request_permission`, над страницей настроек показывается InfoBar `warning` с текстом `Agent is waiting for your approval` и кнопкой `Back to session` (ключ `settings-pending-approval`).
- Состояние берётся из `WorkspaceState`/`SessionView` kit — те же ожидающие одобрения, что рисует workbench. Своего источника у InfoBar нет.
- Кнопка вызывает `back(toSession: id)`. При нескольких сессиях с запросом выбирается активная, иначе первая в порядке сайдбара. Кнопка перекрывает `returnTo` и активирует сессию с запросом.
- Само одобрение даётся только на рабочем месте: там виден контекст tool call (spec agent-workbench-ui «Approval card inside the tool call row»). В настройках вариантов ответа нет.
- Автовозврата на рабочее место нет: пользователь может быть посреди формы.
- InfoBar исчезает, когда запросов больше нет: ответ пришёл из другого клиента, ход отменён или соединение потеряно. Пока соединение не `Connected`, InfoBar не показывается, и для сессии со статусом `detached` тоже: на запрос мёртвого соединения ответить нельзя (повторное ревью безопасности итерации 1).

Esc и «Back» на экране настроек возвращают на workbench. Открытый поверх страницы `ContentDialog` закрывает только сам диалог. На workbench Esc сохраняет смысл A9 — отмену хода. Cmd/Ctrl+, — новое сочетание `CodeLabWorkbenchShortcuts` (Cmd на macOS, Ctrl на других ОС) и экрана настроек; на экране настроек оно ничего не делает.

*Альтернативы:*
- маршрутизация `Navigator`/`go_router` — новая библиотека для задачи, которую решает state management (AGENTS.md §4, A13);
- автоматический возврат на рабочее место при новом запросе разрешения — отбирает экран посреди ввода, и пользователь может нажать Enter уже на карточке одобрения;
- кнопки одобрения прямо в InfoBar — ответ без контекста tool call.

### D3. Оболочка: реестр страниц и точки расширения

`SettingsPage` — enum всех одиннадцати страниц §12.4.9 в фиксированном порядке, с группой (`agent`/`app`), заголовком и ключом теста:

```
Agent: connection, providers, mcpServers, agentsAndModes, permissionsAndTools, redaction, skillsAndExtensions, codeAndWeb
App:   general, appearance, keyboard
```

Видимые страницы задаёт composition root: `SettingsPages(available: {SettingsPage.connection})` в `lib/app/`. При пустом наборе экран настроек не открывается (D2): пустого экрана не бывает. Если «Connection» не видна, первой открывается первая видимая страница по порядку enum. Навигация показывает пересечение порядка enum и множества `available`; группа без видимых страниц не показывает заголовка. Тело страницы — `Widget Function(BuildContext)` из таблицы `settingsPageBuilders` в `features/settings/presentation/`. Страница без построителя попасть в `available` не может — это проверяет тест.

Точки расширения для `add-provider-setup-ui` — добавить значение в `available`, построитель страницы и ключевые слова поиска. Оболочка, `NavigationCubit` и порядок при этом не меняются. Ключи `settings-providers` и `settings-mcp` (§12.4.9) остаются за телами тех страниц. Пункты навигации получают `settings-nav-<page>`, где `<page>` — kebab-case значения (`settings-nav-connection`, `settings-nav-mcp-servers`).

**Поиск «Find a setting».** Фильтр по заголовку страницы и по статическому списку ключевых слов строк страницы (`SettingsSearchIndex`; у «Connection»: `profile`, `stdio`, `websocket`, `token`, `connect on start`, `restart`). Регистр не учитывается, совпадение — по подстроке. Нечёткого поиска и поиска по значениям нет. Выбор результата вызывает `selectSettingsPage`, пустой результат показывает строку «No settings match "<query>"».

**Узкая раскладка.** При окне уже 760 px навигация сверху (`PaneDisplayMode.top`), шире — панелью слева (`PaneDisplayMode.expanded`; значения `open` в `fluent_ui` 4.16 нет). Заголовки групп «Agent» и «App» — `PaneItemWidgetAdapter` с подписью группы: `PaneItemHeader` не даёт нужной вёрстки в обоих режимах. Порог 760 взят из макета (`@media (max-width:760px)` артбордов `Connection` и `General`) и относится только к экрану настроек. Классы раскладки workbench (641/900/1280, требование «Layout class follows the window width») он не меняет.

*Альтернатива:* показывать все пункты с заглушкой «Coming soon», как на холсте, — нарушает SETUP-17 и правило среза roadmap §10.

### D4. `ConnectionSettingsCubit` и состояние страницы

`features/settings/application/connection_settings_cubit.dart` — явный автомат (`state-management.md` §13, §22, §23):
- `ConnectionSettingsLoading`;
- `ConnectionSettingsReady`:
  - `rows` — встроенный агент первым, далее профили `ProfileStore` в порядке файла;
  - `defaultProfileId`;
  - `currentProfileId` — профиль текущего окна из `WorkspaceState.profile`;
  - `connection` — `CodeLabConnectionStatus`;
  - `connectOnStart`;
  - `lastProbes` — `id → ProfileProbeOutcome` за жизнь страницы;
  - `banner` — `saved`/`removed`/`failed(message)`;
- `ConnectionSettingsUnreadable(reason)` — `profiles.json` не разбирается или имеет неизвестную версию.

Три вида данных разведены, как требует `state-management.md` §63:
- **сохранённые настройки** — профили в `profiles.json`, профиль по умолчанию и «Connect on start» в `shared_preferences`;
- **черновик формы** — `ProfileDraft` диалога, у которого свой Cubit-состояние `AddProfileState` (D12), потому что форма сложная (§64);
- **действующее подключение** — `WorkspaceState.profile`.

В `shared_preferences` пишутся только сохранённые настройки, а не состояние Cubit целиком (§49, §50). Открыт ли диалог — эфемерное состояние presentation (`showDialog`), а не флаг в Cubit (§46, §48).

В `ConnectionSettingsUnreadable` страница показывает строку встроенного агента (она не из файла) и InfoBar `error` с текстом «Cannot read ~/.codelab/profiles.json: <причина>. Fix or remove the file; CodeLab will not overwrite it.». «Add profile», «Rename» и «Remove» недоступны: битый файл пользователя не перезаписывается — целостность данных (AGENTS.md §2, п. 3). CLI в той же ситуации выходит с кодом `64`.

Профиль текущего окна app не перечитывает из файла: это `WorkspaceState.profile`. Удаление или переименование этого профиля в CLI не рвёт соединение. Строка отмечается «Current» по совпадению id. Если профиля в файле больше нет, текущий показывается отдельной строкой «Current connection (not saved)».

Файл перечитывается при открытии страницы и после каждой собственной записи. Слежения за файлом нет: правка CLI видна при следующем открытии страницы (см. риски).

Связь с workbench идёт через application API, а не через внутренности feature (`layers-and-dependencies.md` §27). `ConnectionSettingsCubit` получает узкий интерфейс `ConnectionCommands` (`connect(profile)`, `reconnect()`, `current`), который реализует `ConnectionCubit` feature `workbench`. Так одна и та же логика номера попытки и диагностики подключения не дублируется.

### D5. Профиль по умолчанию и профиль текущего окна

У строки две разные роли.

**Радиокнопка** с меткой «Default» выбирает профиль по умолчанию. Это тот профиль, к которому app подключается при старте («Connect on start», D8) и который предлагают экран подключения и кнопка «Connect» в app bar, пока окно ни к чему не подключалось. Хранится в `shared_preferences` `codelab.connection.default_profile` (id).

**«Connect»** переключает текущее окно на этот профиль (`ConnectionCommands.connect(profile)`) и профиль по умолчанию не меняет.

Без ключа (новая установка) профиль по умолчанию — встроенный агент (решение Q1). Правило совпадает с CLI: `codelab` без `--agent` тоже всегда запускает встроенный агент.

`default` — не профиль из файла, а второе имя встроенного агента: `-a default` и `-a embedded` означают одно и то же, а id `default` зарезервирован (D21, D11). Запись с id `default`, уже лежащая в `profiles.json` от прежней версии, игнорируется. Страница «Connection» не показывает её строкой. Вместо этого над списком выводится InfoBar `warning` (ключ `connection-profiles-ignored-default`) с текстом `Profile "default" in profiles.json is ignored: default is the built-in agent. Remove it with codelab profiles remove default.` и кнопкой «Remove». Кнопка вызывает `ProfileStore.remove('default')` после подтверждения. Команду, аргументы, URL и `env` записи InfoBar не показывает. Файл автоматически не перезаписывается.

Почему так:
- встроенный агент не требует отдельного бинаря — это цель задачи 9.3;
- выбор по умолчанию в app задаётся явно радиокнопкой и хранится в `codelab.connection.default_profile`;
- неявный выбор по имени файла давал бы двум клиентам разные «умолчания» при одном `profiles.json`.

Ключ с id, которого больше нет, тоже даёт встроенный агент, а сам ключ удаляется. «Remove» профиля по умолчанию тоже удаляет ключ.

Так закрывается часть задачи 9.3 (`09-14-stage-9-switch-default.md`) для app: «Встроенный агент» — профиль по умолчанию. Вторая часть 9.3 — встроенный stdio-профиль «codelab-agent (stdio)» вместо `codelabAgentStdioProfile` — здесь не делается: свой stdio-агент сохраняется через «Add profile», где по умолчанию стоят `codelab-agent serve --stdio`. Нужен ли отдельный встроенный stdio-профиль, решает 9.3.

Выбор по умолчанию в `profiles.json` не пишется: флаг в файле изменил бы формат `version: 1` и смысл `default` у CLI. Окно в 1.0 одно (§12.3 A13, шаг 0), поэтому в диалоге вместо «Use for new windows» стоит флажок «Use by default» с подсказкой «Used when CodeLab starts and by Connect on start.» (решение Q3).

*Альтернативы:*
- (а) считать профилем по умолчанию id `default` в `profiles.json` — id неизменяем (SETUP-21), и выбрать по умолчанию другой профиль было бы нельзя;
- (б) поле `default: true` в файле — меняет общий с CLI формат.

### D6. `ConnectionCubit` переходит с формы на профиль

`ConnectionFormState` теряет поля формы и тип подключения и получает `profile` (`ConnectionProfile`) — профиль текущего окна, а до первого подключения профиль по умолчанию. Методы:
- `selectTransport`, `updateStdio*`, `updateWebSocket*` удаляются;
- `connect([ConnectionProfile? profile])` подключает `profile` или текущий профиль;
- `reconnect()` — тот же профиль.

Логика номера попытки, проверка папки проекта (для `StdioProfile` и `EmbeddedProfile`) и тексты диагностики сохраняются; тип для текстов берётся из ветки профиля. `ConnectionCubit` реализует `ConnectionCommands` (D4).

«Run agent from project directory» становится полем stdio-профиля (`runInProjectDirectory`); переключатель `SettingsCubit.toggleRunAgentFromProjectDirectory` удаляется. Сценарий «stdio process spawn directory can be decoupled from the project» переходит в поле диалога.

Кнопки «Configure connection» экрана подключения и баннера соединения вызывают `NavigationCubit.openSettings(SettingsPage.connection)` с той же подписью. Баннер и экран — presentation, переход принадлежит presentation/app (`layers-and-dependencies.md`, таблица владельцев side effects).

Характеризационные тесты `shell_cubit_characterization/connection_test.dart` и `connection_cubit_test.dart` меняются явно: вызовы формы заменяются выбором профиля, а проверяемые исходы (статус, диагностика, номер попытки) остаются прежними. Это правило `codelab_client_core/AGENTS.md` §5: новое поведение меняет их только с обоснованием здесь.

*Альтернатива:* оставить форму как «ad-hoc профиль» рядом со списком — два способа сделать одно, и несохраняемый профиль снова расходился бы с CLI.

### D7. Данные пользователя и миграция

Переносить из `shared_preferences` нечего: форма подключения app не сохранялась никогда, а снимок `codelab.workspace.snapshot` профиля не содержит (`codelab_client_core/AGENTS.md` §4). После обновления пользователь видит встроенного агента и профили из `profiles.json`, если работал с CLI. Собственный stdio-агент, которого раньше приходилось вписывать в форму при каждом запуске, теперь сохраняется один раз через «Add profile».

`profiles.json`:
- формат не меняется (`version: 1`, те же поля);
- app пишет его тем же `JsonFileProfileStore`, что CLI (временный файл и переименование, `save` читает файл перед записью);
- путь — `$CODELAB_HOME/profiles.json` (`CODELAB_HOME` непуст, иначе `~/.codelab`); вычисляется в `lib/app/` из того же окружения, что открыватель встроенного агента, шов теста — `createCodeLabRootScope(environment:)`;
- битый или незнакомый файл не перезаписывается (D4);
- встроенный профиль в файл не пишется (`ArgumentError` хранилища, spec acp-client-kit).

`InMemorySecretSource` и ссылка `codelab_desktop.websocket.token` удаляются. Значение токена из прежней формы не сохранялось, переносить его некуда.

### D8. «Connect on start»

Ключ `shared_preferences` `codelab.connection.connect_on_start`, по умолчанию `false` — прежнее поведение: app открывается без подключения.

При `true` app после первого кадра и после `restoreProject()` один раз подключается к профилю по умолчанию. Это обычный `ConnectionCubit.connect`: сбой даёт `ConnectionFailed` и баннер, повторов нет. Запуск не блокируется: подключение идёт после `runApp` и первого кадра, поэтому пустого окна D-15 нет.

Когда появится сторож запуска (`add-app-boot-watchdog`), это действие станет частью шага `routes` с его таймаутом и «Start without auto-connect»; переключатель и ключ при этом не меняются.

### D9. «Restart agent» — существующее переподключение

`ClientWorkspace.restart` (§12.6.7: `session/cancel`, завершение процесса с ожиданием, `RestartOutcome`) не реализован. Цель U-26 — Could этапа 9+, а изобретать новое поведение kit без требования нельзя. Поэтому строка «Restart agent» блока «Behavior» вызывает `ConnectionCubit.reconnect()` — то же, что кнопка «Restart agent» диалога переноса секретов (spec agent-workbench-ui «Перенос секретов встроенного агента»):
- встроенный агент — резолвер сначала освобождает прежнего агента (`dispose`), затем открывает нового с перечитанным конфигом (D6 change `add-embedded-agent-mode`);
- stdio — прежний транспорт закрывается, процесс стартует заново;
- WebSocket — процесс на чужой машине, поэтому кнопка называется «Reconnect».

Текст строки честный и не обещает `session/cancel`: «Reconnects with the same profile and reloads open sessions. A running turn is interrupted; queued prompts stay.»; для WebSocket — «Reconnects to the remote agent…». Обрыв хода и сохранность очереди — уже существующее поведение `reconnect` (spec acp-client-kit «Сессии после переподключения»). Кнопка недоступна без текущего профиля и во время `connecting`/`reconnecting`.

В CommandBar страницы остаётся только «Add profile», дублирующая кнопка «Restart agent» с холста убрана: у одного действия одно место, рядом с объяснением последствий. Когда появится `restart()`, кнопка переключится на него без изменения UI (`12-6` §12.6.7, `agent-parity-goals.md` U-26).

### D10. InfoBar «только чтение» и справка D-10

Пока текущий профиль — `WebSocketProfile` в состоянии `Connected`, страница показывает InfoBar `warning` с текстом артборда: «Read-only: this agent runs on <scheme://host:port>. Change providers and MCP on that host: codelab provider add, codelab mcp add, codelab config set.». Путь, query и userinfo URL не показываются. Профили клиента при этом редактируемы (§12.4.9: SETUP-2 касается конфига агента).

Expander «Join a session started in the CLI» (D-10, Could) — статичная справка, по умолчанию свёрнута: «On the host run codelab-agent serve --ws <port>; the CLI connects with codelab -a <profile>. Choose the same WebSocket profile here; its sessions appear in the sidebar.». Фраз холста о блокировке, значке замка и «Fork» нет: lease (`_meta.codelab.lease`, S-09) не реализован, и такой текст описывал бы несуществующее поведение. Справка верна уже сейчас: `session/list` и `session/load` по WebSocket работают.

### D11. `ProfileDraft` — правила черновика в kit

`codelab_client_core/lib/src/connection/profile_draft.dart` — неизменяемый черновик с двумя операциями:
- `validate(existingIds) → List<ProfileDraftIssue>`;
- `toProfile(existingIds)` — строит `ConnectionProfile` только из валидного черновика, иначе возвращает проблемы.

Это одна логика для app и будущего `codelab profiles add` (§12.4.9). Правила безопасности (секретоподобный `env`, зарезервированный id) проверяются в `toProfile`, а не только в UI-валидации формы (`state-management.md` §65): другого пути из черновика в профиль нет.

**Тип.** `ProfileKind.stdio | webSocket`. Список предлагаемых типов вычисляет `profileKindsFor(resolvers)` по `TransportResolver.supports` на образцовом профиле каждого типа (SETUP-22): на хосте без stdio-резолвера stdio нет.

**Имя и id.** `label` обязателен. `suggestProfileId(label)` даёт нижний регистр, каждый символ вне `[a-z0-9]` заменяется на `-`, повторы и крайние `-` убираются. Правило id — `isValidProfileId`: `^[a-z0-9][a-z0-9._-]{0,63}$`, подмножество правила CLI (`^[A-Za-z0-9][A-Za-z0-9_.-]*$`). Нижний регистр выбран заранее для change B: тогда имя секрета `codelab/profiles/<id>/token` пройдёт `SecretNames`. `:` исключено правилом. Ошибки:
- `idEmpty`;
- `idInvalid`;
- `idReserved` — `embedded` или `default` (общее множество kit `reservedProfileIds`; D21);
- `idTaken` — сравнение без учёта регистра.

Id неизменяем после сохранения; «Rename» меняет только `label`. CLI переходит на то же правило через общую функцию (D15). Существующие профили с заглавными буквами читаются и работают как прежде, но `profiles add` новых таких не создаёт.

**stdio.**
- «Command» обязательна.
- «Arguments» разбирает `parseShellWords`; незакрытая кавычка — проблема `argsInvalid`. По умолчанию в новом черновике — `codelab-agent` и `serve --stdio` (в артборде `Connection` указано `--stdio` — это ошибка макета, D20).
- «Run in the project folder» по умолчанию включено.
- «Environment» — строки `KEY=value` (`parseEnvLines`). Ключ, похожий на секрет, отклоняется (`envSecretLike`, SETUP-19): после `toUpperCase()` он равен `KEY`, `TOKEN`, `SECRET` или оканчивается на `_KEY`, `_TOKEN`, `_SECRET`. Подсказка: «<KEY> looks like a secret. Set it in the system environment or reference it from the agent config as ${secret:…}.».

**WebSocket.**
- «URL» — схема `ws` или `wss` и непустой хост, иначе `urlInvalid`.
- `ws://` к нелокальному хосту (не `localhost`, `127.0.0.0/8`, `::1`) даёт предупреждение `plaintextToRemote`. Оно не блокирует сохранение, но требует подтверждения «Save anyway», как SETUP-10.
- «Token» — `ProfileTokenChoice`, в этом change три формы (D13):
  - `NoToken`;
  - `EnvToken(name)` — имя переменной по правилу `^[A-Za-z_][A-Za-z0-9_]*$`, в профиль идёт `tokenRef: env:<name>`;
  - `KeepTokenRef(ref)` — только у существующих профилей с другой ссылкой; в диалоге добавления не предлагается.

Отдельного типа для значения секрета в kit в этом change нет: значения токена app не принимает и не хранит, только имя переменной. `SecretText` появится в change B вместе с «Store a new token».

*Альтернатива:* правила в Cubit app — CLI повторил бы их, и правила id разошлись бы (уже было: CLI разрешает заглавные буквы).

### D12. `ProfileProbe` — проверка только `initialize`

`ProfileProbe.probe(profile, {required Duration timeout})` (`lib/src/connection/profile_probe.dart`, 10 s по умолчанию):
1. Открывает транспорт тем же набором `TransportResolver`, что `ClientWorkspace`; токен даёт тот же `ProfileSecretSource` (D15).
2. Создаёт временный `AcpClientApplication` без fs- и terminal-адаптеров и выполняет `connect` — ровно один `initialize`. Возможности клиента в нём честно `false`; `AcpClientApplication` и `ClientWorkspace` окна не затрагиваются.
3. Закрывает транспорт и освобождает приложение по ответу, ошибке, таймауту и отмене (SETUP-20). `session/new` не отправляется никогда.

Исход — `ProfileProbeOutcome`:
- `Reachable(latency, agentName?, agentVersion?)`;
- `Unauthorized`;
- `Unreachable(message)`;
- `TimedOut`;
- `NotAcp` — ответ не разобран или протокол несовместим;
- `CommandNotFound`;
- `Unsupported` — нет резолвера.

Тексты UI — §12.4.9, шаг 5; `message` проходит `describeFailure` (без секретов). Если у `EnvToken` переменная не задана в окружении app, перед проверкой показывается заметка «CODELAB_AGENT_TOKEN is not set in CodeLab's environment; the agent may reject the connection.» с настоящим именем переменной. Проверка всё равно выполняется.

Классифицировать ошибки IO-транспортов kit не может: `ProcessException` и `WebSocketException` — типы `dart:io`. Поэтому composition root передаёт классификатор `ProbeFailureClassifier` из `codelab_client_io` (`classifyProbeFailure`). Он смотрит на `AcpTransportException.code` и `cause`:
- отсутствующая команда (`ProcessException` с errno `ENOENT`) → `CommandNotFound`;
- ответ рукопожатия WebSocket 401/403 → `Unauthorized`, только если транспорт сохраняет статус.

Задача 3.3 сначала проверяет это тестом. Если статус теряется, `Unauthorized` по тексту не угадывается, а показывается `Unreachable` с сообщением; типизированный статус в `codelab_acp_transports` — отдельная задача `[protocol]` (см. риски).

**Состояние диалога.** `AddProfileCubit` (`features/settings/application/`) ведёт закрытую иерархию `AddProfileState`:
- `Editing(draft, issues)`;
- `Probing(draft, probeId)`;
- `ConfirmingPlaintext(draft)`;
- `Saving(draft)`;
- `Saved(profileId, tested, useByDefault)`;
- `SaveFailed(draft, message)`.

Невозможные сочетания вроде «идёт проверка, и идёт сохранение» исключены (`state-management.md` §13).

**Отмена и поздние результаты.** У каждой проверки свой номер. Новая проверка, закрытие диалога и `close()` Cubit-а отменяют прежнюю: транспорт закрывается, исход отбрасывается с событием `connection_profile.probe_discarded` (AGENTS.md §9, §12).

**Встроенный агент.** «Test connection» ему не предлагается (решение Q4): проверка открыла бы второй экземпляр ядра в процессе app с побочными эффектами (журнал, предложение переноса секретов), а ошибки его конфига и так видны при «Connect».

### D13. Токен профиля в change A — только переменная окружения

В change A у WebSocket-профиля два варианта токена (решение Q2):
- **«No token»** — `tokenRef` отсутствует;
- **«From environment variable»** — поле имени переменной, в профиль пишется `tokenRef: env:<NAME>`. По умолчанию подставляется `CODELAB_AGENT_TOKEN`, как у CLI. Значение переменной app не читает при сохранении и нигде не показывает: его получает только транспорт при открытии (`ProfileSecretSource`, D15).

Как UI показывает ограничение (без обещаний сверх A):
- в «Add connection profile» под полем токена — подсказка «CodeLab reads the token from this environment variable when it connects. Token values are not saved in profiles.json.»;
- вторая строка подсказки — «Apps opened from Finder do not see variables set in your shell profile.» (macOS; `apps/codelab_desktop/AGENTS.md`) — это честно описывает, почему токен может не дойти;
- если переменная не задана в окружении app, строка профиля и проверка показывают «<NAME> is not set in CodeLab's environment.»;
- профиль со ссылкой не вида `env:` (вручную правленый файл или будущий change B) показывается строкой «Token: <ref> (not supported in this version)». Подключение тогда идёт без токена с предупреждением в диагностике `Token reference <ref> is not supported in this version; connecting without a token.`. Имя ссылки — не секрет, значение не читается.

О будущем хранилище секретов UI ничего не говорит: обещание функции, которой в сборке нет, хуже её отсутствия. Задана ли переменная, проверяет `AddProfileCubit` через узкий порт окружения (`Map<String, String>` из composition root). Значение он при этом не читает, виджеты окружения не видят.

**В change B `add-provider-setup-ui` переходят:**
- варианты «Use stored secret» и «Store a new token»;
- порт `ProfileSecrets` поверх хранилища агента (`ClientSecretAccess` через `codelab_setup/io.dart`, чтение через `SecretResolver`);
- `SecretText`;
- порядок записи «секрет → профиль» с откатом (SETUP-19, часть про `SecretStore`);
- удаление собственного секрета `codelab/profiles/<id>/token` при «Remove»;
- форма ссылки «имя секрета» в `ProfileTokenRef`;
- зависимость app от `codelab_setup` и правило сторожа для `codelab_setup/io.dart`.

Они записаны в `12-4` §12.4.9 и `delivery-roadmap.md` §10.3.

*Альтернативы:*
- (а) в A сразу и хранилище агента — нужна работа на стороне агента (`ClientSecretAccess` в `codelab_agent_io`); пользователь решил отнести её к B вместе с остальной работой над `codelab_setup` в app;
- (б) хранить токен в `InMemorySecretSource`, как прежняя форма, — токен терялся бы при каждом перезапуске, а профиль в CLI работал бы иначе;
- (в) `flutter_secure_storage` — запрещено (`apps/codelab_desktop/AGENTS.md`, D15/D16 change `add-agent-secret-store`).

### D14. Запись, «Rename» и «Remove»

Запись — `ProfileStore.save(draft.toProfile(...))`. Ошибка записи даёт `SaveFailed` с текстом без `toString()` исключения (D17); черновик сохраняется.

«Use by default» после успешной записи пишет `codelab.connection.default_profile`; текущее подключение диалог не меняет. Без успешной проверки в этом запуске строка получает метку «Not tested». Метка — UI-состояние страницы (`lastProbes`), в `profiles.json` она не пишется: менять общий формат ради метки несоразмерно.

**«Rename»** — встроенный редактор `label` (`TextBox`) и `save` с тем же id.

**«Remove»** недоступна у встроенного профиля и у профиля текущего подключения, с подсказкой «Disconnect first». Disconnect появится отдельным change; до него нужно подключиться к другому профилю. Подтверждение — «Remove profile <label>?». Удаляется только запись в `profiles.json`: секретов профиль в этом change не создаёт, и переменные окружения app не трогает. Эти проверки (SETUP-21) — application policy `ConnectionSettingsCubit`, они повторяются перед вызовом `ProfileStore.remove`, а не только в виде недоступной кнопки.

### D15. Ссылка на токен — одно правило для app и CLI

`ProfileTokenRef.parse(ref)` (kit) в этом change различает:
- `env:<NAME>` для **любой** переменной с допустимым именем → `EnvTokenRef(name)`;
- любую другую строку → `UnsupportedTokenRef(ref)`.

Форму «имя секрета» добавит change B.

`ProfileSecretSource(environment)` реализует `SecretSource` по этому правилу: пустая или отсутствующая переменная и `UnsupportedTokenRef` дают `null`, и подключение идёт без токена.

- **App** передаёт `ProfileSecretSource(Platform.environment)` в `ConfigTransportResolver` вместо `InMemorySecretSource`.
- **CLI** заменяет свой `EnvSecretSource` на `ProfileSecretSource` из kit. Поведение не меняется: `EnvSecretSource` уже читал любую ссылку `env:<VAR>`, а прочие ссылки давал как `null` (решение Q5). `profiles add` проверяет id общей функцией `isValidProfileId` (D11).

Старые профили CLI читаются как раньше: формат `profiles.json` тот же, `tokenRef: env:CODELAB_AGENT_TOKEN` разрешается тем же правилом, id с заглавными буквами загружаются и выбираются `-a <id>`. Новое ограничение действует только на id новых `profiles add`.

*Альтернатива:* оставить два источника (`EnvSecretSource` в CLI и свой в app) — правило ссылки разошлось бы при первом же расширении в B.

### D16. Виджеты `codelab_ui`

Виджеты без бизнес-логики и без знания `ConnectionProfile`: модели — простые значения и колбэки.
- **`CodeLabSettingsNavigation`** (organism, `organisms/`) — `NavigationView` с полем «Find a setting», заголовками групп, пунктами `CodeLabSettingsNavItem(key, title, icon, group)`, выбранным пунктом, режимом `left`/`top` по ширине (D3) и кнопкой «Back». Содержимое страницы — `child`.
- **`CodeLabSettingsRow`** (molecule) — «Card row» артборда: заголовок, описание, `trailing` (ToggleSwitch, кнопка, ComboBox), необязательный ключ теста.
- **`CodeLabSettingsSection`** (molecule) — подзаголовок секции («Profiles», «Behavior») и столбец строк с промежутками макета.

Строка профиля собирается в presentation app из готовых виджетов: `CodeLabExpanderCard` (шапка 48 px, раскрытие решает владелец), `RadioButton`, `CodeLabBadge` («Default», «Current», «Not tested»), `CodeLabStatusIndicator` (результат проверки) и `CodeLabButton`. Отдельный виджет для неё не нужен.

Превью — в `codelab_molecule_previews.dart` и `codelab_organism_previews.dart`, по образцу существующих.

### D17. Наблюдаемость

События пишет структурный логгер приложения (`StructuredLogLogger('codelab_desktop.settings')`) с категорией `application` и компонентом `settings`, по образцу `secret_migration.*`. Поля — структурные, текст для человека — дополнительно (`observability.md` §7, §35).

| Событие | Уровень | Поля |
|---|---|---|
| `settings.opened` | info | `page`, `source: shortcut \| sidebar \| banner` |
| `settings.page_selected` | debug | `page` |
| `settings.closed` | debug | `page` |
| `settings.open_skipped` | debug | — (видимых страниц нет) |
| `settings.last_page_load_failed` | warning | `error_type` |
| `settings.last_page_save_failed` | warning | `error_type` |
| `settings.pending_approval_shown` | info | `sessions` (число сессий с запросом) |
| `settings.back_to_approval` | info | — |
| `connection_profile.saved` | info | `profile_id`, `type`, `token: none \| env`, `tested` |
| `connection_profile.renamed` | info | `profile_id` |
| `connection_profile.removed` | info | `profile_id` |
| `connection_profile.save_failed` | warning | `profile_id`, `error_type` |
| `connection_profile.probe_started` | info | `operation_id`, `profile_id?`, `type` |
| `connection_profile.probe_finished` | info | `operation_id`, `outcome`, `duration_ms` |
| `connection_profile.probe_discarded` | debug | `operation_id` |
| `connection_profile.default_changed` | info | `profile_id` |
| `connection_profile.unreadable` | warning | `error_type` |
| `connection_profile.default_ignored` | warning | — (только факт; поля записи не пишутся) |
| `connection_profile.default_removed` | info | — |
| `connection_profile.token_ref_unsupported` | warning | `profile_id` |
| `connection.connect_on_start` | info | `profile_id`, `type` |

Уровень `error` не используется: всё это ожидаемые ситуации, которые пользователь видит и исправляет сам (§9).

События InfoBar одобрения нужны, чтобы по журналу было видно: пользователь узнал о запросе, находясь в настройках. В них нет id сессии, id запроса и полей tool call: id запроса уже пишет журнал разрешений kit (§16), а здесь он только раздвоил бы корреляцию. `settings.pending_approval_shown` пишется один раз при появлении InfoBar, а не на каждой перерисовке.

Номер проверки называется `operation_id` (§4). Для подключения в событиях уже есть `attempt` у `ConnectionCubit`.

В события не попадают (§43–§46):
- аргументы и значения `env` stdio — только `type` и, при необходимости, имя исполняемого файла;
- значение переменной токена — только признак `token: env`, имя переменной тоже не пишется;
- путь, query и userinfo URL — только `scheme://host:port`;
- путь к `profiles.json` (на экране он показывается, в лог не идёт);
- тексты исключений — только имя типа, как в требовании «Перенос секретов»: `error.toString()` может нести секрет.

### D18. Пакеты, зависимости и сторож

| Пакет | Что меняется | Слой |
|---|---|---|
| `codelab_client_core` | `ProfileDraft`, `ProfileProbe`, `ProfileTokenRef`, `ProfileSecretSource`, `isValidProfileId`, `reservedProfileIds`/`isReservedProfileId`, `usableStoredProfiles`, `suggestProfileId`, `profileKindsFor` | core, web-безопасно |
| `codelab_client_io` | `classifyProbeFailure` | io |
| `codelab_ui` | три виджета D16 | ui_kit |
| `apps/codelab_desktop` | навигация, feature `settings`, `ConnectionCubit`, composition root | app |
| `apps/codelab_cli` | `ProfileSecretSource` вместо `EnvSecretSource`, `isValidProfileId` и `reservedProfileIds`, без `--agent` и с `-a default` — встроенный агент, предупреждение о старой записи `default` (D21) | app |

Новых зависимостей и рёбер графа нет: app уже зависит от `codelab_client_core`, `codelab_client_io` и `codelab_ui`. Allowlist ядра, kit, `codelab_client_io` и app не меняется. Новых правил в `codelab_architecture_tests/test/support/rules.dart` нет. Правило «stage 7» для `features/settings/presentation` (запрет `codelab_setup/io.dart` и `dart:io`, SETUP-9) и ребро `codelab_desktop → codelab_setup` переходят в change B вместе с первым импортом `codelab_setup` в app. Граф в `README.md` не меняется.

### D19. Тесты по веткам

В `feature/*` выполняются:
- `fvm dart test` — kit, `codelab_client_io` (настоящие процессы и WebSocket на loopback), `codelab_cli`;
- `fvm flutter test` — `codelab_ui`, `codelab_desktop`;
- `melos run guard`;
- `melos run web-compile` — при правке kit.

Новые интеграционные сценарии app (`settings_navigation_flow_test.dart`, `connection_profiles_flow_test.dart`) и правка существующих, которые настраивали подключение диалогом, в `feature/*` только компилируются (`fvm flutter analyze`). На устройстве их запускает `release/<version>` (AGENTS.md §21). Хелпер интеграционных тестов `support/` получает функцию «временный `CODELAB_HOME` с `profiles.json` + выбор профиля» вместо заполнения формы.

### D20. Расхождения холста и решения

| Где | Холст | Решение | Почему |
|---|---|---|---|
| Навигация (`Connection`, `General`) | все 11 пунктов | только видимые страницы (D3) | SETUP-17, roadmap §10 |
| Строка профиля | Test, Rename, Remove; радиокнопка «The active one is used for new windows» | Test, Connect, Rename, Remove; радиокнопка — профиль по умолчанию, «Connect» — текущее окно (D5) | §12.4.9, шаг 8 |
| Токен на `Connection` и в `AddProfile` | «Token secret» `codelab/ws-devbox`, `keychain-macos · set`; «Use stored secret» / «Store a new token» | в A — «No token» и «From environment variable»; хранилище секретов — change B (D13) | решение пользователя Q2; keychain после 1.0 |
| Аргументы stdio | `--stdio` | `serve --stdio` | `codelab-agent serve --stdio` (§9.9) |
| CommandBar | «Restart agent» и «Add profile» | только «Add profile»; «Restart agent» — в блоке «Behavior» (D9) | одно действие — одно место |
| «Restart agent» | «Cancels running turns, re-runs initialize…» | честный текст о переподключении; для WebSocket — «Reconnect» (D9) | `restart()` §12.6.7 не реализован |
| «Join a session started in the CLI» | замок, read-only, «Fork» | статичная справка без lease (D10) | S-09 и lease не реализованы |
| «Use for new windows» | флажок | «Use by default» с подсказкой (Q3) | окно одно |
| Встроенный агент | «InProcessAcpLink», «providers and MCP edited here (D-04)» | «Runs inside CodeLab; no separate process.» | страниц Providers/MCP в этом change нет; внутренние имена типов в UI не нужны |
| Заголовок встроенного | «Default · Connected» | «Default» и «Current» — разные метки | D5 |
| Поиск | «Find a setting» | по заголовкам и ключевым словам страниц (D3) | нечёткий поиск по значениям не нужен |
| Узкая раскладка | `max-width:760px` | навигация сверху при < 760 px | только экран настроек |
| `AddProfile` (телефон) | «Use for new sessions» | вне охвата (§12.8) | мобильной сборки нет |

### D21. CLI: без `--agent` и с `-a default` — встроенный агент

Решения пользователя 2026-11-04 (Q1 и уточнение того же дня) меняют правило CLI из D13, п. 1 change `add-embedded-agent-mode`. Прежнее правило: «профиль `default` из `profiles.json`, если есть, иначе встроенный». Новое:
- `codelab` без `--agent` **всегда** запускает встроенный агент (`EmbeddedProfile(hostProfile: 'embedded-cli')`);
- `default` — алиас `embedded`: `-a default` и `-a embedded` означают одно и то же, и `profiles.json` при этом не читается;
- правило одно для REPL, `--ui tui`, `-p` и `test-scenario` (как D13, п. 7).

**Резерв id.** Множество `reservedProfileIds = {embedded, default}` и функция `isReservedProfileId` живут в kit (`codelab_client_core/lib/src/connection/profile_draft.dart`). Ими пользуются `ProfileDraft` (app, D11) и `codelab profiles add` (CLI). Резерв отделён от синтаксиса id (`isValidProfileId`): нужно разное сообщение об ошибке.
- `codelab profiles add default …` и `codelab profiles add x default` дают код `64` и `default is the built-in agent; use --agent embedded` — в стиле прежнего `embedded is built in; use --agent embedded`, который не меняется.
- `JsonFileProfileStore.save` отклоняет профиль с зарезервированным id `ArgumentError`, как сейчас `EmbeddedProfile`; файл при этом не меняется.

**Старая запись `default` в `profiles.json`.**
- `load` хранилища возвращает её как есть: хранилище не прячет данные.
- Игнорирует её потребитель через функцию kit `usableStoredProfiles(profiles) → (usable, ignoredDefault)`.
- CLI пишет одно предупреждение в stderr при `codelab profiles list`, `codelab profiles show default` и `-a default`: `profile "default" in profiles.json is ignored: default is the built-in agent; remove it with codelab profiles remove default`. Без `--agent` файл не читается (п. 1 ниже), поэтому предупреждения нет.
- `profiles list` не показывает запись в списке, `profiles show default` печатает встроенный профиль.
- `codelab profiles remove default` удаляет запись, как любую другую (`ProfileStore.remove` резерва не проверяет). Это единственный путь, кроме ручной правки, и он должен работать.
- Команда, аргументы, URL и `env` записи в предупреждения не попадают (`observability.md` §44–§46).
- App показывает то же предупреждение InfoBar-ом на странице «Connection» (D5).

Технические решения оркестратора 2026-11-04:
1. **Без `--agent` CLI не читает `profiles.json`.** Битый или незнакомый файл не мешает запуску встроенного агента. Код `64` за битый файл — только когда файл действительно нужен: `-a <id>` (кроме `embedded` и `default`) и подкоманды `codelab profiles …`.

   В коде: `resolveAgentProfile` (`apps/codelab_cli/lib/src/profiles/profile_arg.dart`) для `value == null`, `embedded` и `default` возвращает встроенный профиль до обращения к хранилищу. `final id = value ?? defaultProfileId;` и константа `defaultProfileId` удаляются. Справка `--agent` в `cli_args.dart` перестаёт упоминать `profile "default" if it exists`.
2. **Подсказку о смене правила CLI не печатает.** Dart CLI ещё не выпущен (этап 9), и на старое правило никто не опирается. Строки о неявном выборе встроенного агента по-прежнему нет (D13, п. 8 change `add-embedded-agent-mode`); выбранный профиль виден с `--verbose` и `/profile`. Предупреждение о старой записи `default` — не подсказка о смене правила: оно сообщает о данных пользователя, которые больше не используются.

Флаг `codelab provider add --default` не меняется: он про модель по умолчанию, а не про профиль подключения.

Тесты, которые опираются на `default` как профиль из файла, переписываются явно (задача 2.13):
- `apps/codelab_cli/test/profiles/profile_arg_test.dart`, `test/profiles/profiles_command_test.dart`;
- `test/run_embedded_test.dart`;
- e2e `test/e2e/connect_profiles_test.dart`, `test/e2e/embedded_agent_test.dart`, `test/e2e/headless_print_basic_test.dart`;
- `test/e2e/codelab_home_tilde_test.dart` — там `profiles add default stdio:agent`, теперь это `64`; тест переходит на другой id;
- `test/scenario/test_scenario_command_test.dart`;
- хелпер e2e `test/e2e/support/e2e_agent.dart` (`profiles add default <агент>`) переходит на явный id и `-a <id>`.

**BREAKING (CLI):**
- без `--agent` и с `-a default` профиль `default` из файла больше не используется;
- `profiles add default` и `profiles add x default` отклоняются.

Формат `profiles.json` не меняется; запись `default` остаётся в файле до `profiles remove default`.

*Альтернативы:*
- (а) оставить `default` обычным профилем, выбираемым только `-a default` (первая версия D21) — пользователь решил иначе: одно имя «по умолчанию» на оба клиента без файла;
- (б) автоматически переименовать или удалить старую запись — запись в пользовательском файле без его действия нарушает целостность данных (AGENTS.md §2, п. 3).

## Risks / Trade-offs

- **[Гонка записи `profiles.json` app и CLI]** Оба пишут через `profiles.json.tmp` и переименование, и одновременная запись может потерять профиль из второй. → `save` перечитывает файл непосредственно перед записью; окно гонки — миллисекунды ручных действий. Блокировка файла — отдельный change, если гонку увидят на практике.
- **[Устаревший список]** Слежения за файлом нет (D4). → Файл перечитывается при открытии страницы. Профиль, удалённый в CLI, при «Connect» из устаревшего списка подключится данными из памяти, без повреждения файла.
- **[Поздний исход проверки]** Диалог закрыт или проверка повторена. → Номер проверки; отмена закрывает транспорт, исход отбрасывается с событием (D12). Тест проверяет, что процесс stdio завершён после закрытия диалога.
- **[Позднее подключение из «Connect on start»]** Пользователь нажал «Connect» другого профиля, пока шло автоподключение. → Существующий номер попытки `ConnectionCubit`/`ClientWorkspace` (spec acp-client-kit «Повторный Connect во время подключения»).
- **[Unauthorized не определяется]** Транспорт WebSocket может не сохранять статус рукопожатия. → По тексту не угадываем, показываем `Unreachable` с сообщением. Задача 3.3 проверяет это и при необходимости заводит задачу `[protocol]` на типизированный статус в `codelab_acp_transports`.
- **[Токен недоступен app из Finder]** Переменная окружения задана в оболочке, а приложение запущено из Finder. → Подсказка в диалоге и строка «<NAME> is not set in CodeLab's environment.» (D13). Полное решение — хранилище секретов в change B.
- **[Секрет в логах и ошибках]** → События только с id и типами (D17), `describeFailure` для сообщений. Тест подставляет маркер `sk-test-leak-…` в значение переменной токена, в `env` stdio, в URL и в текст исключения.
- **[Утечка токена по `ws://`]** → Предупреждение и подтверждение при сохранении (D11).
- **[Containment]** Профиль stdio запускает произвольную команду пользователя — так же, как сегодняшняя форма и `codelab -a stdio:…`. Агентских действий без одобрения не появляется. `fs/*` и `terminal/*` ограничены папкой сессии, как раньше (AGENTS.md §10).
- **[Forward compatibility ACP]** Проверка — обычный `initialize`: незнакомые поля ответа игнорируются, несовместимая версия даёт `NotAcp` с текстом версии.
- **[Web-безопасность]** Всё новое в kit — чистый Dart без `dart:io`; классификатор IO живёт в `codelab_client_io`. `melos run web-compile` входит в задачи kit.
- **[Allowlist ядра PKG-2]** Не меняется: этот change не трогает агентские пакеты.
- **[Потеря привычного входа]** Пользователи, вписывавшие команду в форму, должны один раз создать профиль. → Экран подключения и баннер ведут прямо на страницу «Connection», встроенный агент доступен без настройки.

## Migration Plan

1. Итерация 0 — документы, без кода.
2. Итерация 1 — навигация, оболочка, виджеты. Страница «Connection» появляется только в итерации 2, поэтому в итерации 1 рабочий набор `available` пуст (SETUP-17: пустого экрана нет). Cmd/Ctrl+, и кнопка «Settings» пока открывают прежний `ConnectionSetupDialog`, а навигацию проверяют тесты на тестовом наборе страниц.
3. Итерация 2 — kit (`ProfileTokenRef`, `ProfileSecretSource`), страница «Connection», переход `ConnectionCubit` на профили, удаление диалога, CLI на общем источнике токена. «Settings» и Cmd/Ctrl+, открывают страницу.
4. Итерация 3 — «Add connection profile», «Test connection», «Rename», «Remove».
5. Итерация 4 — документы и DoD.

Откат — revert PR итерации. `profiles.json` между итерациями не меняет формат, а новые ключи `shared_preferences` прежняя версия игнорирует.

## Open Questions

Все вопросы решены 2026-11-04.

- **Q1. Профиль по умолчанию на новой установке.** Решил пользователь 2026-11-04 (уточнено тем же днём):
  - без явного выбора app и CLI всегда запускают встроенный агент;
  - `default` — алиас встроенного агента (`-a default` = `-a embedded`), id `default` зарезервирован, старая запись `default` в `profiles.json` игнорируется с предупреждением (уточнение пользователя того же дня);
  - правила app и CLI совпадают (D5, D21);
  - это закрывает задачу 9.3 в части профиля по умолчанию, `09-14-stage-9-switch-default.md` дополнен ссылкой.
- **Q2. Хранилище секретов агента в этом change.** Решил пользователь: не включать. Токен в A — только «No token» и `env:<NAME>` (D13). «Use stored secret», «Store a new token», порт `ProfileSecrets`, порядок «секрет → профиль» с откатом, удаление `codelab/profiles/<id>/token` при «Remove», `SecretText`, зависимость app от `codelab_setup` и правило сторожа переходят в change `add-provider-setup-ui`.
- **Q3. Подпись «Use for new windows».** Решил оркестратор: «Use by default» с подсказкой «Used when CodeLab starts and by Connect on start.» и меткой «Default» у радиокнопки (D5).
- **Q4. «Test connection» у встроенного агента.** Решил оркестратор: кнопки нет (D12).
- **Q5. Правка CLI.** Решил пользователь: включить общее правило id `isValidProfileId` и общую ссылку на токен `ProfileTokenRef`/`ProfileSecretSource`. В A ссылка — только `env:<NAME>` для любой переменной (D15); старые профили CLI читаются как раньше.
