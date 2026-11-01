## ADDED Requirements

### Requirement: Встроенный режим в e2e и conformance
Встроенный агент SHALL проверяться на трёх уровнях (design.md change `add-embedded-agent-mode`, D10):
- **Пакет.** Тесты `packages/dart/codelab_embedded/test/` на Dart VM работают на `InProcessAcpLink`, временном `CODELAB_HOME` и `MockClient` провайдера и входят в `melos run test`.
- **CLI.**
  - E2E `apps/codelab_cli/test/e2e/` с `CODELAB_E2E_AGENT=embedded` запускают CLI из kernel тестовой точки входа `test/e2e/support/embedded_cli_main.dart`. Эта точка передаёт `run(…)` открыватель `scriptedEmbeddedAgentOpener` со сценарием `test/e2e/llm_scripts/<сценарий>.json`, путь к которому задаёт переменная теста. Тесты с тегом `scripted-only` исключаются. Скрипт `melos run test:e2e:cli:embedded` входит в `melos run check` (Dart VM, `AGENTS.md` §21).
  - Скрипт `melos run conformance:embedded` — `codelab test-scenario packages/dart/codelab_acp_testing/fixtures/acp --agent embedded` — тоже входит в `check`.
- **App.**
  - Интеграционные тесты `apps/codelab_desktop/integration_test/` с `--dart-define=CODELAB_E2E_AGENT=embedded` подключаются типом `Embedded agent`. Поддержка `integration_test/support/e2e_agent.dart` передаёт `CodeLabBootstrap` scope с открывателем `scriptedEmbeddedAgentOpener`.
  - `fs_flow_test` и `terminal_flow_test` в этом режиме пропускаются с причиной: встроенный агент не шлёт `fs/*` и `terminal/*`.
  - Скрипт `melos run test:e2e:app:embedded` НЕ SHALL входить в `check` и в CI pull request. Его прогон на устройстве выполняется только в ветке `release/<version>` (`AGENTS.md` §21). В feature-ветке эти тесты SHALL проходить `fvm flutter analyze`.

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
