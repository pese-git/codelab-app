## MODIFIED Requirements

### Requirement: Проверки workspace
CodeLab SHALL предоставлять Melos-скрипты проверок. Конфигурация Melos SHALL храниться в одном месте — секции `melos:` корневого `pubspec.yaml`.

Полная проверка `check` SHALL состоять из шагов `check-format`, `analyze`, `guard`, `prompts:check`, `l10n:check`, `test`, `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded`, `protocol-conformance`, `conformance:client`, `conformance:agent`, `conformance:embedded` и `web-compile`. Полный прогон CI SHALL выполнять те же скрипты, что и `check` (требование «Непрерывная интеграция»).

`web-compile` SHALL компилировать в JavaScript и WebAssembly три точки web-smoke: ядра агента, моста встроенного агента и моста настроек (workspace-architecture «Границы пакетов monorepo»).

Вне `check` SHALL оставаться:
- прогоны на устройстве или симуляторе `test:e2e:app:*`;
- прогон против Python-агента `test:e2e:cli:python-agent`;
- сборки `build:agent` и `build:cli`.

Когда какие скрипты запускать перед pull request — `AGENTS.md` §21.

#### Scenario: Запускается полная проверка
- **WHEN** в развёрнутом workspace выполняется `fvm dart run melos run check`
- **THEN** выполняются все 13 шагов в указанном порядке, и каждый проходит либо сообщает конкретные, действенные ошибки

#### Scenario: Полный прогон CI совпадает с check
- **WHEN** тест сторожа сравнивает шаги `check` из `pubspec.yaml` со скриптами джобов полного прогона `fullJobs` (`tool/ci/ci_scope.dart`)
- **THEN** множества скриптов совпадают, а ни одного скрипта `test:e2e:app:*` и `test:e2e:cli:python-agent` в них нет (`ci_scope_test.dart`, «Полный прогон CI совпадает с check»)

#### Scenario: Один источник конфигурации Melos
- **WHEN** выполняется `fvm dart run melos list` или любой скрипт из прежнего `melos.yaml`
- **THEN** команда работает, а файла `melos.yaml` в корне нет

#### Scenario: Сборка бинаря агента
- **WHEN** выполняется `fvm dart run melos run build:agent`
- **THEN** появляется исполняемый файл `build/bin/codelab-agent`, который отвечает на `initialize` по stdio; скрипт не входит в `check` (design.md change `add-codelab-agent-binary`, D9)

#### Scenario: Сборка терминального клиента
- **WHEN** выполняется `fvm dart run melos run build:cli`
- **THEN** появляется исполняемый файл `build/bin/codelab`, который печатает версию по `--version`; скрипт не входит в `check`

#### Scenario: Отдельный прогон e2e CLI
- **WHEN** выполняется `fvm dart run melos run test:e2e:cli`
- **THEN** запускаются только тесты `apps/codelab_cli/test/e2e/` на Dart VM

#### Scenario: e2e CLI против Dart-агента
- **WHEN** выполняется `fvm dart run melos run test:e2e:cli:dart-agent`
- **THEN** тесты `apps/codelab_cli/test/e2e/` без тега `scripted-only` идут с `CODELAB_E2E_AGENT=dart` против `codelab-agent serve --stdio --llm-script`, скомпилированного в kernel на этот прогон

#### Scenario: e2e CLI против Python-агента
- **WHEN** выполняется `fvm dart run melos run test:e2e:cli:python-agent`
- **THEN** идут только тесты с тегом `python-agent` с `CODELAB_E2E_AGENT=python`; без установленного Python-агента они пропущены с причиной, а прогон зелёный

### Requirement: Интеграционные тесты stdio
CodeLab SHALL тестировать stdio-интеграцию с `codelab-agent` либо совместимым тестовым двойником, использующим ту же семантику запуска/профиля. E2E-тесты `apps/codelab_desktop/integration_test/` SHALL параметризоваться агентом через `--dart-define=CODELAB_E2E_AGENT=scripted|dart` (по умолчанию `scripted`) и помощник `integration_test/support/e2e_agent.dart`; в режиме `dart` агент — бинарь `CODELAB_E2E_AGENT_BIN` со сценарием `integration_test/llm_scripts/<режим>.json`. Тесты поведения именно scripted-агента SHALL иметь тег `scripted-only` и исключаться в режиме `dart`. Код `apps/codelab_desktop/lib` для этого НЕ SHALL меняться.

Скрипты прогона на устройстве `melos run test:e2e:app:*` НЕ SHALL входить в `check` и в CI (требования «Проверки workspace», «Непрерывная интеграция»); сами тесты SHALL проходить `fvm dart analyze` в составе `analyze`. В каких ветках запускать прогон на устройстве — `AGENTS.md` §21.

#### Scenario: Референсный агент инициализируется
- **WHEN** тест stdio-интеграции запускает настроенную команду
- **THEN** CodeLab завершает `initialize` ACP

#### Scenario: Prompt turn стримит
- **WHEN** интеграционный тест отправляет `session/prompt`
- **THEN** CodeLab получает потоковые `session/update` и финальный ответ на prompt

#### Scenario: Тест в режиме Dart-агента
- **WHEN** `permission_flow_test.dart` запускается с `CODELAB_E2E_AGENT=dart`
- **THEN** карточка одобрения показывает команду `echo hello` из аргументов вызова `exec` — она же заголовок вызова

#### Scenario: Тест только для scripted-агента
- **WHEN** e2e-прогон идёт с `--exclude-tags scripted-only`
- **THEN** тест `agent dying mid-turn` не запускается

#### Scenario: Интеграционные тесты app анализируются в каждом прогоне
- **WHEN** выполняется `fvm dart run melos run analyze`
- **THEN** файлы `apps/codelab_desktop/integration_test/` проходят статический анализ без запуска на устройстве

### Requirement: Непрерывная интеграция
CodeLab SHALL запускать CI (`.github/workflows/ci.yml`) на push в `master` и `develop`, на каждый pull request, ночью по расписанию (`schedule`) и вручную (`workflow_dispatch`). Все джобы SHALL выполняться на `ubuntu-latest`: джобов на macOS и прогонов `test:e2e:app:*` в CI нет. Python-агента в CI нет.

Охват прогона SHALL считать `ciScope` (`tool/ci/ci_scope.dart`, вызов — `tool/ci/affected.dart` в джобе `scope`):
- **Полный прогон** — джобы `fullJobs` со всеми шагами `check` (требование «Проверки workspace») и джоб `site`. Он выполняется, если `ci.yml` передал причину полного прогона (любое событие, кроме `pull_request`; pull request в `master`; pull request из `release/*`) или изменён файл вне пакетов workspace, вне документации и вне `site/`.
- **Только документация** (`docs/`, `openspec/`, `.claude/`, `*.md` в корне; `AGENTS.md`, `README.md`, `CHANGELOG.md` в любом каталоге) — без Dart-джобов. Исключение — матрица целей `docs/architecture/proposals/agent-parity-goals.md`: её правка добавляет `guard` (требование «Ночная проверка доказательств в CI»).
- **Затронутое** — остальные pull request:
  - `format` — по всему репозиторию;
  - `analyze` и `test` — для изменённых пакетов и всех, кто от них зависит транзитивно по `dependencies` и `dev_dependencies`;
  - `guard` — всегда, с `prompts:check`, если изменено ядро агента;
  - `conformance` — корпуса затронутых ACP-слоёв, а `conformance:embedded` — если затронуты `codelab_cli` или `codelab_embedded`;
  - `l10n` — при изменении файлов локализации `codelab_desktop` или `codelab_ui`;
  - `web-compile` — при изменении ядра агента или пакета, от которого оно зависит;
  - `e2e-cli-dart` — если затронуты `codelab_cli` или `codelab_agent`;
  - `e2e-cli-embedded` — если затронуты `codelab_cli` или `codelab_embedded`.
- Признак джоба `site` SHALL считаться независимо от Dart-матрицы (project-site «Проверка сайта в CI»).

Итоговый джоб `ci` SHALL быть единственным обязательным статусом: он красный, если `scope` не `success` или если `checks`, `site` или `parity` не `success` и не `skipped`. Пропущенные джобы матрицы merge не блокируют. Процессные правила проверки перед pull request и чек-лист pull request — `AGENTS.md` §21 и `.github/pull_request_template.md`.

#### Scenario: Pull request с нарушением
- **WHEN** открыт pull request, в котором нарушен формат, анализ, тест, сторож или web-компиляция затронутого
- **THEN** соответствующий джоб матрицы красный, и итоговый джоб `ci` красный

#### Scenario: Изменение пакета сужает проверки
- **WHEN** pull request в `develop` меняет только `packages/flutter/codelab_ui/lib/`
- **THEN** `ciScope` возвращает джобы `format`, `analyze`, `test` и `guard`, а `analyze` и `test` идут для `codelab_desktop` и `codelab_ui` (`ci_scope_test.dart`, «a package change scopes analyze and test to it and its dependents»)

#### Scenario: Только документация
- **WHEN** pull request меняет только `docs/architecture/testing.md`, `openspec/changes/x/tasks.md`, `.claude/commands/check.md`, `apps/codelab_cli/AGENTS.md` и `README.md`
- **THEN** `ciScope` не возвращает ни одного Dart-джоба (`ci_scope_test.dart`, «documentation only needs no code jobs»)

#### Scenario: Файл вне пакетов даёт полный прогон
- **WHEN** pull request меняет `pubspec.lock`, `analysis_options.yaml`, `.github/workflows/ci.yml` или `tool/ci/ci_scope.dart`
- **THEN** `ciScope` возвращает все джобы `fullJobs` без сужения по пакетам и называет файл в причине (`ci_scope_test.dart`, «a file outside the packages runs everything unscoped»)

#### Scenario: Причина полного прогона
- **WHEN** `ciScope` получает причину полного прогона `push to develop`, а изменён только `docs/x.md`
- **THEN** прогон полный, причина — `push to develop`, джобов столько же, сколько в `fullJobs` (`ci_scope_test.dart`, «an explicit full reason runs everything»)

#### Scenario: e2e CLI по затронутому
- **WHEN** pull request в `develop` меняет `packages/dart/codelab_client_acp/lib/` или `packages/dart/codelab_agent_core/lib/`, от которых транзитивно зависят `codelab_cli` или `codelab_agent`
- **THEN** матрица содержит `e2e-cli-dart`, а pull request, затрагивающий только `packages/flutter/codelab_ui/lib/`, его не содержит (`ci_scope_test.dart`, «the CLI e2e runs when the CLI or the agent binary is affected»)

#### Scenario: Джобов на macOS нет
- **WHEN** тест сторожа читает `.github/workflows/ci.yml`
- **THEN** у каждого джоба `runs-on` — `ubuntu-latest` (`ci_scope_test.dart`, «Джобов на macOS нет»), а скрипты джобов `checks` — только скрипты `fullJobs` без `test:e2e:app:*` (сценарий «Полный прогон CI совпадает с check»)

#### Scenario: Сайт в CI
- **WHEN** CI запускается на pull request, который меняет `site/**` или опубликованную документацию
- **THEN** джоб `site` на `ubuntu-latest` собирает и проверяет сайт, и его падение делает итоговый джоб `ci` и pull request красными

### Requirement: Встроенный режим в e2e и conformance
Встроенный агент SHALL проверяться на трёх уровнях (design.md change `add-embedded-agent-mode`, D10):
- **Пакет.** Тесты `packages/dart/codelab_embedded/test/` на Dart VM работают на `InProcessAcpLink`, временном `CODELAB_HOME` и `MockClient` провайдера и входят в `melos run test`.
- **CLI.**
  - E2E `apps/codelab_cli/test/e2e/` с `CODELAB_E2E_AGENT=embedded` запускают CLI из kernel тестовой точки входа `test/e2e/support/embedded_cli_main.dart`. Эта точка передаёт `runCodelab(…, embeddedOpener:)` открыватель `scriptedEmbeddedAgentOpener` со сценарием `test/e2e/llm_scripts/<сценарий>.json`, путь к которому задаёт переменная теста. Тесты с тегом `scripted-only` исключаются. Скрипт `melos run test:e2e:cli:embedded` входит в `melos run check`.
  - Скрипт `melos run conformance:embedded` — `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded` — тоже входит в `check`.
- **App.**
  - Интеграционные тесты `apps/codelab_desktop/integration_test/` с `--dart-define=CODELAB_E2E_AGENT=embedded` подключаются типом `Embedded agent`. Поддержка `integration_test/support/e2e_agent.dart` передаёт `CodeLabBootstrap` scope с открывателем `scriptedEmbeddedAgentOpener`.
  - `fs_flow_test` и `terminal_flow_test` в этом режиме пропускаются с причиной: встроенный агент не шлёт `fs/*` и `terminal/*`.
  - Скрипт `melos run test:e2e:app:embedded` НЕ SHALL входить в `check` и в CI. Эти тесты SHALL проходить `fvm dart analyze` в составе `analyze`. В каких ветках их запускать на устройстве — `AGENTS.md` §21.

Рабочий код клиентов (`lib/`) НЕ SHALL импортировать `package:codelab_embedded/testing.dart`. Исключение — драйвер фикстур CLI `lib/src/scenario/`.

#### Scenario: E2E CLI против встроенного агента
- **WHEN** `cli/repl-permission-allow-once` идёт с `CODELAB_E2E_AGENT=embedded`
- **THEN** блок одобрения показывает команду из сценария, `y` разрешает вызов, ход заканчивается выполненным вызовом, а дочерний процесс агента не запускается

#### Scenario: check содержит встроенный режим
- **WHEN** выполняется `fvm dart run melos run check`
- **THEN** в шагах есть `test:e2e:cli:embedded` и `conformance:embedded`, и нет `test:e2e:app:embedded`

#### Scenario: Тестовый сценарий не попадает в app
- **WHEN** файл в `apps/codelab_desktop/lib/` импортирует `package:codelab_embedded/testing.dart`
- **THEN** `fvm dart run melos run guard` падает и называет файл и строку

### Requirement: Проверка доказательств матрицы целей
Тест `packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart` SHALL разбирать матрицу целей `docs/architecture/proposals/agent-parity-goals.md` и проверять доказательства каждой строки Must (задача 9.1; design.md change `switch-default-agent-to-dart`, D2–D5).

**Разбор.**
- Тест SHALL брать строки с приоритетом `Must` из таблиц §3 (заголовок с колонкой «Приоритет») и все строки таблицы §4.1.
- Строка таблицы, у которой число ячеек отличается от заголовка, SHALL быть ошибкой разбора с номером строки файла, какой бы ни был её приоритет. Ячейки делятся по `|`, не экранированному `\`.
- Число найденных строк Must SHALL совпадать с итогом Must сводки §7; расхождение — ошибка разбора.
- Доказательства строки SHALL извлекаться из фрагментов в обратных кавычках колонки «Критерий приёмки»:
  - `acp/<id>`;
  - `cli/<id>`;
  - `core/<id>`;
  - `app:<файл>`;
  - путь файла теста (`packages/…_test.dart`, `apps/…_test.dart`);
  - шаблоны `acp/*` и `app:*`.
  Строка Must без единого доказательства SHALL получать статус `missing`. Строка закрыта, только если закрыто каждое её доказательство.

**Существование** проверяется в каждом запуске, без отчётов.
- Правила:
  - `acp/<id>` — есть `packages/dart/codelab_acp_testing/fixtures/acp/<id>.json`, и среди ролей фикстуры есть `agent`: строка матрицы — цель агента, а фикстуру без роли `agent` агентский корпус пропускает;
  - `cli/<id>` — в `apps/codelab_cli/test/e2e/` есть вызов `test(` или `group(`, не вложенный в тело другого `group(`, первый строковый литерал которого начинается с `cli/<id>`, а за id идёт конец литерала, `:` или пробел (id — начало полного имени теста в отчёте; design.md, D3, уточнение 2026-11-10);
  - `core/<id>` — то же в тестах `codelab_agent_core`, `codelab_agent_io`, `codelab_agent_acp`, `codelab_agent_mcp`, `codelab_embedded` и `apps/codelab_agent`;
  - `app:<файл>` — есть `apps/codelab_desktop/integration_test/<файл>`;
  - путь файла теста — файл есть.
- Упоминание id в комментарии НЕ SHALL считаться тестом.
- Исключений нет: каждое нарушение SHALL ронять тест строкой `<строка> <доказательство> missing`, строка без доказательств — `<строка> (no evidence) missing`, фикстура без роли `agent` — `<строка> acp/<id> has roles [<роли>] without "agent"`. Временного списка известных пробелов нет: храповик `knownGaps` удалён, когда закрылись его последние записи K-02 и R-08 (change `add-agent-builtin-slash-commands`, задача 4.1).

**Статус** проверяется только при заданной переменной `CODELAB_PARITY_RESULTS` — каталоге отчётов (требование «Машинные отчёты прогонов»).
- Без переменной группа статуса SHALL пропускаться с причиной `CODELAB_PARITY_RESULTS is not set: status is checked by the nightly parity job`.
- Если переменная задана, а каталога или файла `meta.json` нет, тест SHALL падать.
- Статус доказательства SHALL быть одним из пяти:
  - `pass` — в обязательном источнике (design.md, D5) есть хотя бы один пройденный тест id, ни одного пропущенного и ни одного упавшего в любом источнике;
  - `failed` — тест id упал в любом источнике или упал набор, в котором он лежит;
  - `skipped` — тест id пропущен в обязательном источнике либо в дополнительном с причиной вне перечня `allowedSkips`; для доказательства-пути файла теста — пропущен тест файла с причиной вне перечня `allowedSkips` (пропуск по перечню строку не открывает, решение Q8);
  - `not-run` — в обязательном источнике нет ни одного теста id, в том числе исключённого тегом `scripted-only`;
  - `missing` — доказательство не существует.
- Тест принадлежит id, если его полное имя в отчёте начинается с id, а за id идёт конец, `:` или пробел.
- Без переменной `CODELAB_PARITY_APP_RESULTS` доказательства `app:` SHALL получать статус `deferred`: он печатается, но тест не роняет. С переменной они проверяются по отчётам app.
- Тест SHALL падать, если хотя бы одно доказательство строки Must не `pass` и не `deferred`. Сообщение — строки `<строка> <доказательство> <статус> [<источник>] [<причина>]`, отсортированные по id строки, а первой строкой — содержимое `meta.json`.

Логика разбора и свёртки SHALL проверяться модульными тестами на временном дереве: своя матрица, фикстуры и отчёты. Настоящая матрица для них не нужна.

#### Scenario: Нет файла фикстуры
- **WHEN** строка Must временной матрицы ссылается на `acp/slash-help`, а файла фикстуры нет
- **THEN** проверка существования падает со строкой `R-08 acp/slash-help missing` (`evidence_test.dart`, «Нет файла фикстуры: R-08 acp/slash-help missing»)

#### Scenario: Фикстура без роли agent
- **WHEN** строка Must ссылается на `acp/x`, а у фикстуры `acp/x.json` только роль `client`
- **THEN** проверка существования падает строкой с `acp/x`, ролями фикстуры и `without "agent"` (`evidence_test.dart`, «фикстура без роли agent — не доказательство строки»)

#### Scenario: Id только в комментарии
- **WHEN** id `core/x` встречается в тестах только в комментарии `// core/x`
- **THEN** доказательство `core/x` — `missing`

#### Scenario: Id во вложенном тесте
- **WHEN** `test('core/x: …')` вложен в `group('другое имя', …)`, а других вызовов с `core/x` нет
- **THEN** доказательство `core/x` — `missing`: полное имя в отчёте начинается с `другое имя`

#### Scenario: Id во внешней группе
- **WHEN** `group('core/x', …)` стоит на верхнем уровне `main`, а внутри него тесты с другими именами
- **THEN** доказательство `core/x` существует

#### Scenario: Сломанная строка таблицы
- **WHEN** строка таблицы §3 содержит неэкранированный `|` внутри обратных кавычек, и число ячеек больше, чем в заголовке
- **THEN** тест падает с ошибкой разбора и номером строки файла

#### Scenario: Число строк Must не совпадает со сводкой
- **WHEN** во временной матрице 3 строки Must, а итог сводки §7 — 4
- **THEN** тест падает с ошибкой разбора

#### Scenario: Без отчётов
- **WHEN** `fvm dart run melos run guard` выполняется без `CODELAB_PARITY_RESULTS`
- **THEN** группа статуса пропущена с причиной, а прогон зелёный, если существование в порядке

#### Scenario: Каталог отчётов без meta.json
- **WHEN** `CODELAB_PARITY_RESULTS` указывает на пустой каталог
- **THEN** тест падает с сообщением об отсутствии `meta.json`

#### Scenario: Тест scripted-only в режиме dart
- **WHEN** единственный тест `cli/x` имеет тег `scripted-only` и потому отсутствует в `cli-dart.json`
- **THEN** доказательство `cli/x` — `not-run`, тест падает

#### Scenario: Падение в дополнительном источнике
- **WHEN** фикстура `acp/x` проходит в отчёте `conformance:agent`, но в `scenario-embedded.xml` у неё `failure`
- **THEN** доказательство `acp/x` — `failed` с источником `scenario-embedded.xml`

#### Scenario: Пропуск по спецификации в дополнительном источнике
- **WHEN** фикстура `acp/mcp-stdio-tool-call` проходит в `conformance:agent`, а в `scenario-embedded.xml` пропущена с причиной `setup.mcp cannot be passed to the agent process`
- **THEN** доказательство — `pass`

#### Scenario: Отчёты app не переданы
- **WHEN** задана только `CODELAB_PARITY_RESULTS`, а строка Must ссылается на `app:fs_flow_test.dart`
- **THEN** доказательство печатается как `deferred`, и тест из-за него не падает

## REMOVED Requirements

### Requirement: Соблюдение Definition of Done
**Reason**: Процессное правило без автоматической проверки: «задача помечена выполненной — тесты проходят и DoD соблюдён» проверяет ревью, а не тест (design.md change `align-cross-cutting-specs`, D1, D8).
**Migration**: Порядок работы над задачей, TDD и проверка перед pull request — `AGENTS.md` §17–§21, вложенные `AGENTS.md` пакетов (TDD), `docs/architecture/testing.md` §88, §92, §93. Проверяемая часть критериев приёмки — требования этой спеки («Проверки workspace», «Непрерывная интеграция») и сторож.

### Requirement: Характеризационные тесты фасада приложения
**Reason**: Требование защищало перенос логики `CodeLabShellCubit` в `codelab_client_core`; change `extract-acp-client-kit` завершён и заархивирован (`openspec/changes/archive/2026-10-26-extract-acp-client-kit/`), а условия «тексты тестов не меняются на время переноса» больше не к чему применять (design.md, D8).
**Migration**: Поведение фасада покрывают обычные тесты Cubit-ов `apps/codelab_desktop/test/features/workbench/application/` и требования `acp-client-kit` и `agent-workbench-ui`; характеризационные тесты остаются регрессионными тестами пакета без отдельного требования.
