Задачи с кодом идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2, `packages/dart/codelab_client_acp/AGENTS.md`). Красный тест — отдельный коммит до кода; коммит — только по просьбе пользователя. В скобках — требование и сценарий дельты этого change или решение design.md.

Метки исполнителей:
- `[client]` — `packages/dart/codelab_client_acp`; правило сторожа для `apps/codelab_cli` (зона `client-engineer`);
- `[desktop]` — правило сторожа для `packages/flutter/codelab_ui`, тест одобрения app (зона `desktop-engineer`);
- `[protocol]` — тесты `codelab_architecture_tests` для `tool/ci` и `.github/workflows/ci.yml` (как в `switch-default-agent-to-dart`; у CI нет отдельной зоны);
- `[agent]` — задач нет: код агента не меняется;
- `[docs]` — `docs/architecture/**` и `openspec/**`, исполнитель `codelab-architect` (D1). README пакетов — `docs-writer`, это указано в самой задаче.

Решения пользователя Q1–Q8 получены 2026-11-24 и внесены (design.md, «Решения пользователя»).

## 0. Условия старта

- [x] 0.1 `[docs]` Получены решения Q1–Q8 (2026-11-24); дельта и задачи приведены к ним.
- [ ] 0.2 `[docs]` `extend-secret-name-redaction` и `redesign-protocol-pane` слиты в `develop`; ветка обновлена от `develop` (D15). Реализация 2.x и 4.x возможна и раньше, архивация — только после них.

## 1. Сверка сценариев с тестами (`[docs]`)

- [x] 1.1 `[docs]` Каждый сценарий с именем теста в дельтах существует в коде под этим именем (`structured_logging_test.dart`, `payload_policy_diagnostics_test.dart`, `application_use_cases_test.dart`, `unknown_tool_kind_test.dart`, `codelab_client_acp_test.dart`, `approval_prompt_test.dart`, `approval_policy_test.dart` CLI, `ci_scope_test.dart`, `evidence_test.dart`). Переименованный тест — правка ссылки в дельте, не теста. Итог сверки: все названные тесты есть, включая `import_guard_test.dart`, `subagent_approval_block_test.dart`, `diagnostics_test.dart`, `secret_redaction_test.dart`; ссылки «тест задачи N» заменены именами — «diagnostics do not change the session snapshot» (`structured_logging_test.dart`), «Полный прогон CI совпадает с check» и «Джобов на macOS нет» (`ci_scope_test.dart`), «the IO barrel of the setup bridge is forbidden in the barrel and bin/ of the terminal client, allowed only in run.dart» (`import_guard_test.dart`, сценарий «IO-барель моста настроек вне run.dart CLI»). На удалённые тесты `decidePermission` (4.1) дельты не ссылаются. Сценарий «Плагин в ките» называет тест 3.6 — «reports the OS drag-and-drop plugin imported by the UI kit» (`import_guard_test.dart`). По ревью добавлены ссылки: «classifies approval risk levels for tool calls» (`codelab_client_acp_test.dart`, сценарий «Деструктивная команда») и «answers cancelled when handling a permission request fails internally» (`application_use_cases_test.dart`, сценарий «Внутренняя ошибка обработки запроса разрешения», задача 5.4).

## 2. structured-logging: диагностика без копии в сессиях (D3, решение Q2 = C)

- [x] 2.1 `[client]` Тест (structured-logging «Ограниченная (bounded) история diagnostic-событий», сценарий «Диагностика не меняет снимок сессии»): в `structured_logging_test.dart` создать сессию, подписаться на `sessionChanges`, эмитить диагностику транспорта; ожидать запись в `client.diagnostics`, неизменный снимок сессии (`identical` до и после) и ни одного события `sessionChanges`. Сейчас красный: `_recordDiagnostic` копирует запись во все сессии и публикует их. Тест — «diagnostics do not change the session snapshot».
- [x] 2.2 `[client]` Реализация:
  - удалить из `_recordDiagnostic` (`acp_client_application.dart`) цикл `for (final session in _sessions.values…) _storeSession(session.copyWith(diagnostics: …))`;
  - удалить поле `diagnostics` из `AcpSession` (`domain_models.dart`), перегенерировать `domain_models.freezed.dart` (`fvm dart run build_runner build` в пакете). Файл отслеживается git в обход `.gitignore` — новая версия коммитится вместе с кодом;
  - `test/fixtures/client_fixture_conformance_test.dart:480`: `expect(session.diagnostics, isEmpty)` заменить проверкой ошибок в `user.app.diagnostics` (как в строках 477 и 500) или удалить, если она уже есть рядом;
  - doc-комментарии `_recordDiagnostic` и `AcpSession` по `AGENTS.md` §15: единственный буфер — `AcpClientApplication.diagnostics` (OBS-004, D3).
  - Тесты 2.1 и «bounds in-memory diagnostics…» зелёные.
- [x] 2.3 `[client]` `fvm dart analyze` зависимых пакетов (изменён публичный тип `AcpSession`): `codelab_client_core`, `codelab_client_io`, `codelab_agent_acp` (контрактный тест `test/contract/client_application_contract_test.dart`), `codelab_embedded`, `apps/codelab_cli`, `apps/codelab_desktop`; тесты `codelab_client_core` и контрактный тест `codelab_agent_acp`.

## 3. Сторож и CI (D6, D7)

- [x] 3.1 `[protocol]` Тест (testing-quality «Проверки workspace», сценарий «Полный прогон CI совпадает с check»): в `ci_scope_test.dart` прочитать шаги `check` из секции `melos:` корневого `pubspec.yaml` (разбор строк без пакета `yaml`, как `WorkspacePackage.fromPubspec`) и сравнить множество со скриптами `fullJobs`, разбитыми по пробелу; проверить, что среди них нет `test:e2e:app:` и `test:e2e:cli:python-agent`. Ожидаемо зелёный сразу (13 шагов совпадают); если красный — сообщить архитектору, а не править тест.
- [x] 3.2 `[protocol]` Реализация: не нужна, если 3.1 зелёный. Иначе — привести `fullJobs` к `check` по решению архитектора.
- [x] 3.3 `[protocol]` Тест (testing-quality «Непрерывная интеграция», сценарий «Джобов на macOS нет»): в `ci_scope_test.dart` прочитать `.github/workflows/ci.yml`; каждая непустая строка `runs-on:` (без комментариев) — `ubuntu-latest`, строк `runs-on` хотя бы столько, сколько джобов `scope`, `checks`, `site`, `parity`, `ci`. Комментарии workflow упоминают `macOS` и `test:e2e:app:*` — по подстроке во всём файле не проверять. Скрипты джобов приходят из `fullJobs` и проверяются 3.1. Ожидаемо зелёный сразу; это страж нормы, которая раньше не проверялась.
- [x] 3.4 `[client]` Тест (workspace-architecture «Автоматический сторож границ пакетов», сценарий «IO-барель моста настроек вне run.dart CLI»): негативный тест в `import_guard_test.dart` на временном дереве — `lib/codelab_cli.dart` и `bin/codelab.dart` импортируют `package:codelab_setup/io.dart`, `lib/src/run.dart` — тоже; ожидаются нарушения ровно для бареля и `bin/`. Красный: правило охватывает только `lib/src`.
- [x] 3.5 `[client]` Реализация: в `rules.dart` правило `codelab_setup/io.dart` перенести на `apps/codelab_cli/lib` с `exclude: ['src/run.dart']`, `sealExclude: false`; в правило `apps/codelab_cli/bin` добавить `package:codelab_setup/io.dart`. Комментарии правил — по-русски, ссылка на D6. `melos run guard` зелёный на настоящем дереве.
- [x] 3.6 `[desktop]` Тест (workspace-architecture «Плагин перетаскивания из ОС только в адаптере платформы», сценарий «Плагин в ките»): негативный тест в `import_guard_test.dart` — файл `lib/src/x.dart` временного дерева кита импортирует `package:desktop_drop/desktop_drop.dart`; ожидается одно нарушение. Красный: правила нет.
- [x] 3.7 `[desktop]` Реализация: правило `PackageRule('packages/flutter/codelab_ui/lib', forbidden: ['package:desktop_drop/'])` в `rules.dart` с комментарием (`AGENTS.md` §11, D6). `melos run guard` зелёный.

## 4. approval-safety: мёртвые режимы разрешений клиента (D9)

- [x] 4.1 `[client]` Тесты (approval-safety REMOVED «Режимы разрешений»; «Риск вызова неизвестного вида и смены режима»; acp-client-kit «Неизвестный уровень риска вызова»):
  - удалить тесты `decidePermission` и `requiresExplicitApproval` из `codelab_client_acp_test.dart` («decidePermission requires explicit approval in every mode», «decides permission mode behavior from risk levels») и `state_machines_test.dart` (~1208);
  - убедиться, что ранг и классификацию `unknown` по-прежнему покрывают группа «unknown approval risk» и `unknown_tool_kind_test.dart`. Если проверка из удаляемого теста больше нигде не покрыта (например, «риск не `readOnly`»), перенести её утверждение в `classifyToolCall*`-тест, без `PermissionMode`.
- [x] 4.2 `[client]` Реализация: удалить `PermissionMode`, `PermissionModeDecision`, `ApprovalPolicy.decidePermission`, `ApprovalPolicy.requiresExplicitApproval` из `lib/src/domain/approval_policy.dart`; поправить doc-комментарий `ApprovalRiskLevel` (`domain_models.dart`, ~128), который ссылается на `decidePermission`. `fvm dart analyze` в `codelab_client_acp`, `codelab_client_core`, `codelab_client_io`, `apps/codelab_cli`, `apps/codelab_desktop` — без ошибок (изменён публичный API, `AGENTS.md` §21 п. 2).
- [x] 4.3 `[docs]` README `packages/dart/codelab_client_acp/README.md` (строки про `PermissionMode` и `decidePermission`) — исполнитель `docs-writer`, шаг 2а: риск считает `ApprovalPolicy.classifyToolCall`, решение об одобрении — у агента и пользователя, автоматическая политика — `--approve` CLI.

## 5. Сценарии без явного теста

- [x] 5.1 `[client]` Сверка (structured-logging «Логирование по слоям согласно ownership»): тест «tags protocol send failures with component=protocol» соответствует сценарию «Сбой отправки запроса помечен компонентом protocol». Если тест проверяет другое событие — уточнить сценарий через `[docs]`, тест не менять. Итог: тест проверяет ровно сценарий — сбой отправки `session/new`, запись `error` с `event` `Failed to send ACP request session/new.` и `component` `protocol`; сценарий не менялся.
- [x] 5.2 `[client]` Сверка (approval-safety «Редактирование секретов», «Отображаются переменные окружения»): найти тест маскирования launch environment в диагностике (`connection_cubit_test.dart` desktop или тест kit). Если теста нет — добавить характеризационный тест в `codelab_client_core` (зелёный сразу) и сообщить имя для дельты. Итог: добавлен характеризационный тест `packages/dart/codelab_client_core/test/diagnostics/diagnostics_test.dart`, «launch environment in diagnostics masks secret-like values» (`formatRedactedJson` скрывает `API_KEY`, `GITHUB_TOKEN`, `DB_PASSWORD` в `env`, `PATH` виден). Сценарий «Отображаются переменные окружения» сужен под тест: он называет форматирование диагностики ядра клиента и конкретные переменные, без обещаний про экран диагностики desktop и приватные ключи.
- [x] 5.3 `[desktop]` Сверка (approval-safety «Review-first изменения», «Запрошена правка файла»): найти виджет-тест, где карточка или строка ждущего одобрения показывает diff вызова. Если нет — добавить характеризационный виджет-тест в `apps/codelab_desktop/test/features/workbench/presentation/` (зелёный сразу) и сообщить имя для дельты (D12). Итог сверки: diff в карточке одобрения app не показывается — в `PendingApprovalView` и `ToolCallView` нет поля для diff, `ToolCallDiff` разбирается только в инспекторе (`inspector_projection.dart`); характеризационный тест не добавлялся. Подтверждены тесты `subagent_approval_block_test.dart`: «the file path is visible without opening the raw input», «shows path, command and the panel; Allow answers this request». По решению пользователя (2026-11-24) сценарий «Запрошена правка файла» смягчён до факта со ссылками на эти тесты, показ diff не обещается; diff в одобрении — отдельный change (design.md, D12; proposal, «Не входит»).

- [x] 5.4 `[client]` Тест (approval-safety «Поток разрешений ACP», сценарий «Внутренняя ошибка обработки запроса разрешения»): в `application_use_cases_test.dart` запрос `session/request_permission` с неразбираемыми параметрами получает ответ `cancelled`, пишется диагностика уровня error с источником `application.permission`, хода нет. Тест «answers cancelled when handling a permission request fails internally»; зелёный сразу — характеризация существующей ветки `catch` в `_handlePermissionRequest` (D10, D14).

## 6. Документы и процесс

- [x] 6.1 `[docs]` `docs/architecture/observability.md`:
  - §3 — ссылка на structured-logging «Логирование по слоям согласно ownership»;
  - §28, §29 и «Где в коде» — единственный буфер `AcpClientApplication.diagnostics`, без абзаца о неограниченном списке `AcpSession.diagnostics`, ссылка на «Ограниченная (bounded) история»;
  - §32, §33 — ссылка на «Logger-абстракция»;
  - §35 — ссылка на «Маршрутизация категорий журнала по sink»;
  - §48а — нормы о причине сбоя и пропуске `sessionUpdate` ссылками на требования вместо пересказа;
  - абзац `streaming.md` о буферах без предела — убрать копии диагностики в `AcpSession.diagnostics` из перечня.
- [x] 6.2 `[docs]` `docs/architecture/permissions.md`: разделы о режимах (§7, §15 и др.), где упоминаются клиентские `PermissionMode`, — режимы принадлежат агенту (`agent-permissions`), клиент — `ApprovalRiskLevel` для показа и `--approve` CLI; §34 — ссылки на «Поток разрешений ACP» и acp-protocol-client «Отмена prompt turn», ответ без активного хода — кандидат D14; §46 — ссылка на сценарий «Внутренняя ошибка обработки запроса разрешения» (D10); §2 «Исключение» — ссылка на «Review-first изменения». `docs/architecture/acp-boundary.md` §30 «В коде»: вместо «режим одобрения — `ApprovalPolicy`, `PermissionMode`» — риск считает `ApprovalPolicy.classifyToolCall`, режимы разрешений у агента (`agent-permissions`), автоматическая политика — `--approve` CLI (ревью).
- [x] 6.3 `[docs]` `docs/architecture/layers-and-dependencies.md` и `technology-stack.md`:
  - перенести смысл удалённых требований `workspace-architecture` по таблице design.md, D5: `codelab_ui/atomics` в §8, если его нет; ссылка §9.1 на закрытие root scope;
  - §42 — ссылка на «Автоматический сторож границ пакетов» вместо перечня правил, строки о `codelab_setup/io.dart` в CLI и о `codelab_ui` без плагина — по 3.5 и 3.7;
  - строка о расширении allowlist через OpenSpec change — в §43.
- [x] 6.4 `[docs]` `docs/architecture/testing.md`:
  - §74 — состав джобов и правила охвата ссылкой на testing-quality «Непрерывная интеграция» и «Проверки workspace» вместо пересказа;
  - убрать абзац «спецификация `testing-quality` описывает `web-compile`… устарело»;
  - уточнить, что сужение действует для любого pull request, кроме `master` и `release/*` (D7);
  - §88 и §92 — ссылка на `AGENTS.md` §17–§21 вместо удалённого «Соблюдение Definition of Done».
- [x] 6.5 `[docs]` README `packages/dart/codelab_architecture_tests/README.md` — исполнитель `docs-writer`: новые проверки `ci_scope_test.dart` (3.1, 3.3) и правила 3.5, 3.7 в таблице «Что проверяют тесты».
- [x] 6.6 `[docs]` Одобрено пользователем 2026-11-24 (Q7). `AGENTS.md` §21: одна фраза — состав `check` и охват CI заданы требованиями testing-quality «Проверки workspace» и «Непрерывная интеграция»; §21 задаёт, что запускать перед pull request. Остальной текст §21 не меняется.
- [x] 6.7 `[docs]` Одобрено пользователем 2026-11-24 (Q7). `.github/pull_request_template.md`, пункт «Проверка»: вместо «`fvm dart run melos run check` зелёный локально» — «проверки затронутого по `AGENTS.md` §21 перечислены в описании; полный `check` не запускался (кроме `release/*` или по просьбе)». Затронутые интеграционные тесты — как сейчас.

- [x] 6.8 `[docs]` Дельта agent-workbench-ui «Выбор значения селектора отправляется агенту»: ссылка на удалённые клиентские режимы `approval-safety` заменена ссылкой на `agent-permissions` (D9). Активные changes это требование не модифицируют.

## 7. Внешние зависимости

- [ ] 7.1 `[docs]` Перед архивацией: сверить дельту «Редактирование секретов» с главной спекой после архивации `extend-secret-name-redaction` и с дельтой `redesign-protocol-pane` (D11, D15). Расхождение в тексте правил переносится в эту дельту.
- [ ] 7.2 `[docs]` Если PR #467 влит: в testing-quality «Непрерывная интеграция» строка «`web-compile` — …» дополняется мостами `codelab_embedded` и `codelab_setup` по поведению `ci_scope.dart` после merge; сценарий — по его тесту (D7).
- [ ] 7.3 `[docs]` Решение Q5: дельта активного change `switch-default-agent-to-dart` не правится. Перед его архивацией (`--skip-specs`, его задача 4.8) сверить: главная спека `testing-quality` «Проверка доказательств матрицы целей» остаётся без `knownGaps` — сверка 4.8 не переносит его старый текст в главную спеку. Напоминание передать исполнителю архивации того change.

## 8. Проверка и архивация

- [x] 8.1 `[client]` Проверки затронутого (`AGENTS.md` §21): `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm dart analyze` в `codelab_client_acp` и зависимых (`codelab_client_core`, `codelab_client_io`, `codelab_agent_acp`, `codelab_embedded`, `apps/codelab_cli`, `apps/codelab_desktop`); `fvm dart test` в `codelab_client_acp`, `codelab_client_core` и контрактный тест `codelab_agent_acp`; `melos run guard`; `melos run conformance:client`; `melos run test:e2e:cli:dart-agent` и `melos run test:e2e:cli:embedded` (изменён клиентский слой CLI). Полный `check` — только по просьбе.
  - Итог 2026-11-24: format, analyze 8 пакетов, тесты `codelab_client_acp` (518 после правок ревью) и `codelab_client_core` (1029), контрактный тест `codelab_agent_acp`, `guard` (366), `conformance:client`, `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded`, `site verify` — зелёные; полный `check` не запускался.
- [ ] 8.2 `[docs]` `openspec validate align-cross-cutting-specs --strict` зелёный. При архивации (только по просьбе пользователя, после `extend-secret-name-redaction` и `redesign-protocol-pane`) поправить `## Purpose`: `workspace-architecture` — без SOLID, CherryPick, `fpdart`; `testing-quality` — без Definition of Done; `approval-safety` — без «режимов разрешений MVP» (D15 п. 5).
