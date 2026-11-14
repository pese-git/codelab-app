Порядок: 0 → 1 → 2 → 3 → 4; 2.1–2.3 (фикстура, режим scripted-агента) можно начинать параллельно с 1.1–1.2; 2.4 — после 1.3; 3 — после 2.3; 4 — последней.

TDD (вложенные `AGENTS.md`): красный тест каждой пары коммитится отдельно до кода — только по явной просьбе пользователя. Тесты-закрепления (поведение уже верное) помечены «зелёный сразу».

## 0. Документы

- [x] 0.1 `[agent]` Документы ядра до кода (выполнено архитектором 2026-11-13; «сначала документ», `codelab_agent_core/AGENTS.md`; design.md, D1–D5):
  - `docs/architecture/proposals/agent-core/07-permissions.md`: §7.2 (комментарий к `criticalLabel`), §7.4 (псевдокод ветки PERM-11), §7.6.1 (первый пункт — метка), §7.7 п. 2, §7.8 п. 1, §7.9 PERM-11;
  - `docs/architecture/proposals/agent-core/13-acp-adapter.md` §13.12 — строка `_meta.codelab.critical`;
  - `docs/architecture/permissions.md` — абзац PERM-11.

## 1. Ядро (`codelab_agent_core`)

- [ ] 1.1 `[agent]` Красные тесты метки PERM-11 (agent-permissions «Пометка критичности вопроса о конфигурации агента», сценарии «write в проектный конфиг в bypass», «edit пути хоста», «Одна метка для write и exec», «Тип агента с режимом bypass», «autopilot без изменений»):
  - `test/permissions/permission_request_fields_test.dart`: `write .codelab/config.yaml` в `bypass` → `criticalLabel == 'write to agent configuration'`, `reason == 'agent configuration: .codelab/config.yaml'`, `allowAlwaysOffered == false`; `write .codelab/config.local.yaml` и `exec echo x > .codelab/config.local.yaml` — одинаковая метка, разные `reason`;
  - `test/permissions/agent_config_paths_test.dart`: `edit ~/.codelab/config.yaml` с `agentConfigPaths` в `accept-edits` → метка; `autopilot` — отказ без запроса (закрепление);
  - `test/agents/agent_select_serial_test.dart`: в тесте типа с `mode: bypass` — `gate.requests[1].criticalLabel == 'write to agent configuration'`.
- [ ] 1.2 `[agent]` Красный тест лога `permission.asked` (тот же requirement, сценарии «Поле лога», «Обычная правка не критична»): `test/permissions/` (рядом с тестами логов политики; при отсутствии — новый `permission_asked_log_test.dart` с `RecordingLogger`/фейковым логгером ядра): `write .codelab/agents/x.md` в `bypass` → `critical: true`; `edit README.md` в `standard` → `critical: false`; вызов `_ask` с `reason` без метки недоступен извне, поэтому инвариант `critical == criticalLabel != null` проверяется сравнением поля лога с `gate.requests.single.criticalLabel` на обоих вызовах.
- [ ] 1.3 `[agent]` Реализация 1.1–1.2 (design.md, D1, D3, D4):
  - `lib/src/permissions/agent_config_rules.dart`: константа метки `write to agent configuration` (без экспорта из барреля) с doc-комментарием «почему/для чего/как» (одна строка для `exec` и `write`/`edit`, клиенты сравнивают метку побайтово);
  - `lib/src/permissions/critical_patterns.dart`: `_agentConfig` заменить ссылкой на константу;
  - `lib/src/permissions/policy.dart`: ветка `_agentConfigTarget` передаёт `criticalLabel:`; комментарий ветки — ссылка на PERM-11 и design.md change `mark-agent-config-edits-critical`, D1; в `_ask` поле лога `'critical': criticalLabel != null`.
  - Doc-комментарий `PermissionRequest.criticalLabel` (`lib/src/permissions/gate.dart`) — упомянуть PERM-11 (§7.6.1).

## 2. Протокольный слой и фикстуры (`codelab_acp_testing`, `codelab_agent_acp`)

- [ ] 2.1 `[protocol]` Тест-закрепление gate (зелёный сразу; agent-acp-server «Запросы агента к клиенту»): `packages/dart/codelab_agent_acp/test/acp_permission_gate_test.dart` — запрос с `reason: 'agent configuration: .codelab/config.yaml'`, `criticalLabel: 'write to agent configuration'`, `allowAlways: false` и одним diff → `toolCall._meta` `{"codelab": {"critical": true, "label": "write to agent configuration"}}`, первый блок `content` — текст `reason`, затем `diff`; варианты `allow_once`, `reject_once`, `reject_always`. Существующий тест обычного запроса дополнить проверкой: `_meta` отсутствует.
- [ ] 2.2 `[protocol]` Красная фикстура `packages/dart/codelab_acp_testing/fixtures/acp/permission-agent-config-edit-critical.json` (acp-golden-fixtures «Фикстура критической правки конфигурации агента»; design.md, D8) по образцу `permission-critical-pattern-in-bypass.json` и `tool-write-permission-diff.json`; id — новым набором в `test/fixtures_load_test.dart` по образцу `_toolKindFixtures` и `_skillFixtures` (комментарий — ссылка на этот change). Агентский прогон (`melos run conformance:agent`) красный до 1.3: кадр без `_meta`.
- [ ] 2.3 `[protocol]` Режим scripted-агента `with_agent_config_write` в `CodelabCompatibleStdioAgentMode` (`lib/src/codelab_compatible_stdio_agent.dart`; design.md, D8): `tool_call` вида `edit` с путём `.codelab/config.yaml`, `session/request_permission` с той же пометкой и вариантами без `allow_always`; ответ модели после решения — маркер выбранного варианта, как у `with_critical_permission`. Тест режима — `test/cli_modes_agent_test.dart`, рядом с тестом `with_critical_permission`.
- [ ] 2.4 `[protocol]` После 1.3: агентский прогон 2.2 зелёный; `melos run protocol-conformance`, `melos run conformance:agent` и `melos run conformance:embedded`.

## 3. Клиенты (`codelab_client_acp`, `apps/codelab_cli`)

- [ ] 3.1 `[client]` Клиентский прогон фикстуры (зелёный сразу — клиент уже читает пометку; acp-golden-fixtures, сценарий «Клиентский прогон»): запись `acp/permission-agent-config-edit-critical` в `packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart` — `approval.critical == true`, `call_1` — `failed`, ход завершён.
- [ ] 3.2 `[client]` Красный сквозной тест headless (cli-headless «allow-all не одобряет правку конфигурации Dart-агента», сценарий «Правка проектного конфига в allow-all»): `apps/codelab_cli/test/e2e/headless_exit_codes_test.dart` — `-p … --approve allow-all` в режиме `with_agent_config_write`; ожидания: код `0`, строка stderr `permission "<launch.agentConfigTitle>": reject_once (critical)`, файла `<dir>/.codelab/config.yaml` нет. Поддержка в `test/e2e/support/e2e_agent.dart`: поле `agentConfigTitle` у `E2eCliLaunch` для всех видов агента, режим `bypass` для `dart` и `embedded`, сценарий модели `test/e2e/llm_scripts/with_agent_config_write.json` (вызов `write` с путём `.codelab/config.yaml`, затем текст после отказа). Красный против `CODELAB_E2E_AGENT=dart` и `embedded` до 1.3 (stderr `allow_once (policy)`, файл создан); против scripted — зелёный после 2.3 (закрепление клиента).
- [ ] 3.3 `[client]` Тест-закрепление политики (зелёный сразу): `apps/codelab_cli/test/headless/approval_policy_test.dart` — `PendingApprovalView` вида `edit` с `critical: true` и вариантами без `allow_always` при `allow-all` → `reject_once`, причина `critical`; при `read-only` и `reject` → `reject_once`, причина `policy`.
- [ ] 3.4 `[client]` Тест-закрепление REPL (зелёный сразу; design.md, D7): `apps/codelab_cli/test/repl/approval_prompt_test.dart` — для такого одобрения блок начинается с `Permission: <title> (<risk>, critical)`, подсказка без `[a] allow always`.

## 4. Проверки (§21 `AGENTS.md`)

- [ ] 4.1 `[agent]` `fvm dart format --set-exit-if-changed` изменённых файлов; `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_agent_core`.
- [ ] 4.2 `[protocol]` `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_agent_acp` и `packages/dart/codelab_acp_testing`; `melos run protocol-conformance`, `melos run conformance:agent`, `melos run conformance:embedded` (корпус против встроенного агента через `codelab test-scenario`).
- [ ] 4.3 `[client]` `fvm dart analyze` и `fvm dart test` в `packages/dart/codelab_client_acp` и `apps/codelab_cli`; `melos run conformance:client`, `melos run test:e2e:cli`, `melos run test:e2e:cli:dart-agent`, `melos run test:e2e:cli:embedded`.
- [ ] 4.4 `[agent]` `openspec validate mark-agent-config-edits-critical --strict`. `guard` и `web-compile` не нужны: импорты и `pubspec.yaml` не меняются (design.md, D9). Полный `melos run check` — только по просьбе пользователя.
