Задачи идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2; дорожная карта §9.1). Сначала красные тесты, затем код. В скобках — требование спецификации этого change (`capability` «Requirement», сценарий), решение design.md или строка Must матрицы. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя.

Перед стартом — ответы пользователя на Q1–Q11 design.md. Спецификации написаны под рекомендации; другой ответ сначала правит `specs/` и фикстуры (задача 0.1).

Метки исполнителей:
- `[protocol]` — `codelab_acp_testing` (фикстуры), `codelab_agent_acp`, `codelab_architecture_tests`, матрица целей;
- `[agent]` — `codelab_agent_core`, `codelab_embedded`, `apps/codelab_agent`, документы агентской стороны;
- `[client]` — `apps/codelab_cli`;
- `[desktop]` — `apps/codelab_desktop`.

Проверки каждой задачи — только для затронутого (`AGENTS.md` §21): `fvm dart format`, `fvm dart analyze` пакета, тесты пакета; `conformance:agent`, `conformance:embedded`, `conformance:client` — при правке фикстур и ядра; `test:e2e:cli:dart-agent`, `test:e2e:cli:embedded` — при правке ядра и `apps/codelab_cli`; `web-compile` — при правке `codelab_agent_core`; `guard` — при правке `codelab_architecture_tests` и матрицы. Интеграционные тесты app в `feature/*` только компилируются и анализируются. Для `openspec/` — `openspec validate add-agent-builtin-slash-commands --strict`.

Зависимость: change `switch-default-agent-to-dart`, итерация 2 (в `knownGaps` остались только K-02 и R-08; уточнение D3 того change).

## 0. Документы

- [x] 0.1 `[agent]` Ответы на Q1–Q11 внесены в design.md («Решения пользователя»); при ответе не по рекомендации — правка `specs/agent-slash-commands/spec.md`, `specs/acp-golden-fixtures/spec.md` и затронутых сценариев до красных тестов. Все ответы — по рекомендации (2026-11-10), спецификации не менялись.
- [x] 0.2 `[agent]` `agent-core-architecture`:
  - §13.6 — MVP-список без MCP prompts (E-24, после MVP; решение Q10 change `switch-default-agent-to-dart`), тексты ответов `/mode`, `/model`, `/status`, `/help`, `Nothing to compact.`, абзац «Этап 8.10» — «правило 3 действует с change `add-agent-builtin-slash-commands`»;
  - §13.4 — пункт 6: встроенные команды MVP добавлены этим change;
  - §17.2.6 — «Этап 8.7»: шаг 7 действует, шаги 5–6 — после MVP, незакрытая кавычка — по ответу Q7.

## 1. Красные тесты

- [x] 1.1 `[protocol]` Фикстуры (acp-golden-fixtures «Фикстуры встроенных команд агента»; K-02, R-08): `acp/slash-compact`, `acp/slash-help`, `acp/slash-mode-plan` — перенесённые из итерации 2 change `switch-default-agent-to-dart` (D8). Сверить с требованиями этого change: тексты, порядок кадров `/mode plan` (D6), `/nope` в `slash-mode-plan` (сценарий приёмки R-08). `conformance:agent` красный.
- [x] 1.2 `[protocol]` Обновлённые точные списки `availableCommands` в `acp/available-commands-no-tools`, `acp/prompt-template-command`, `acp/slash-mcp-list` (acp-golden-fixtures «Фикстуры файлов проекта этапа 8»; agent-acp-server «session/new», сценарий «Команды шаблонов после session/new»; D2) — со ссылкой на требование в `spec` фикстуры. Красный.
- [x] 1.3 `[agent]` Тесты ядра (`packages/dart/codelab_agent_core/test/commands/builtin_commands_test.dart` и тест сессии; agent-slash-commands «Встроенные команды MVP», «Неизвестная команда», «Список команд сессии», «Разворачивание команды», «Встроенные команды config и mcp»):
  - объявление и порядок: с конфигом, `compaction` и `mcp` — `compact, mode, model, status, config, mcp, help, review`; без них — `mode, model, status, help`;
  - `/compact` с указанием и без, `Nothing to compact.`, ожидание фонового `afterTurn`, отмена во время резюме, `CompactionFailed` → `AgentError(compaction)` и `TurnEnded(failed)`;
  - `/mode plan` — порядок событий `ModeChanged` → сообщение → `TurnEnded`, запись `mode_change`, без записи промпта; синоним, `autopilot`, неизвестный id, без аргумента;
  - `/model` — смена, неизвестная модель, `--role`, без аргумента;
  - `/status` — четыре строки без конфига; строки `Config` и `Restart required` с конфигом; при `configCommand: false` их нет;
  - `/help` — формат строк, `(template)`;
  - неизвестная команда — текст, обрезка до 64 рун, лог `command.unknown` без имени; `/usr/bin/foo` и ведущий пробел — модели; необъявленные `/config`, `/mcp` — неизвестные;
  - слот хода: второй `prompt` во время `/compact` отклоняется; `session/load` восстанавливает режим и модель, реплей без текстов команд.
  Красные.
- [x] 1.4 `[protocol]` Тест моста (`packages/dart/codelab_agent_acp/test/`; agent-acp-server «session/new»; D6): `/mode plan` даёт `current_mode_update` и `config_option_update` до `agent_message_chunk`, все уведомления — до ответа на `session/prompt` (ACP-3); `/model` — `config_option_update` с полным снимком. Красный.
- [x] 1.5 `[agent]` Тесты хостов (agent-binary «Перезагрузка конфига в serve», сценарий «WebSocket без /config»; «Файлы проекта в бинаре», сценарий «Сценарий не читает CODELAB_HOME»; agent-project-context «Порт файлов проекта», сценарий «Без порта»): `agent_host_ws_commands_test.dart` — `/config check` по WebSocket получает `Unknown command: /config. …` без запроса к модели; списки команд в тестах `apps/codelab_agent/test/` и `packages/dart/codelab_embedded/test/` — со встроенными командами. Красные.
- [x] 1.6 `[agent]` Поиск остальных точных ожиданий списка команд (`availableCommands`, `agentCommands`, `session.commands`, `available_commands_update … пуст`) в тестах пакетов агента, клиента и app; найденные — в задачи 1.5, 1.7, 1.8 с указанием файла.
- [x] 1.7 `[client]` Тест (codelab-cli «Slash-меню и клиентские команды», сценарий «Одноимённые команды клиента и Dart-агента»; U-03, `cli/slash-menu-merges-agent-commands`; D10): вариант PTY-e2e без тега `scripted-only` против `dart` и `embedded` — меню Tab показывает клиентские `/help`, `/mode`, `/model`, `/config`, команды агента `/compact`, `/status`, `/mcp` с пометкой `(agent)`, `/agent:help`, `/agent:mode`, `/agent:model`; `/agent:help` печатает ответ агента. Ожидания — из `test/e2e/support/e2e_agent.dart`; сценарий `--llm-script` для режима теста — в `test/e2e/llm_scripts/` и `apps/codelab_agent/test/llm_scripts_load_test.dart`. Нынешняя scripted-проверка (`/agent:plan`) — отдельный тест с тегом. Красный в `dart` и `embedded`.
- [x] 1.8 `[desktop]` Тест (testing-quality «Интеграционный тест палитры с командами агента»; K-02, R-20; D9): `command_palette_flow_test.dart` делится на тест `scripted-only` (нынешний сценарий) и тест без тега для встроенной `compact` во всех режимах; пропуск `!isScripted` снят; ответ агента — из `integration_test/support/e2e_agent.dart`. В `feature/*` — `fvm flutter analyze` и компиляция; прогон на устройстве — в `release/*`.

## 2. Реализация ядра

- [x] 2.1 `[agent]` `BuiltinCommands` (`codelab_agent_core/lib/src/commands/builtin_commands.dart`): объявление `compact`, `mode`, `model`, `status`, `help` по §13.4 и порядок D2; `match` для всех объявленных команд и результат «неизвестная команда» для слова по регулярному выражению без команды и шаблона (D3, D4); тексты ответов; порты ручного сжатия, смены режима и модели, снимка состояния и списка команд (D1). Doc-комментарии — почему, для чего, как (`AGENTS.md` §15). Тесты 1.3 по разбору и текстам зелёные.
- [x] 2.2 `[agent]` `AgentSession.prompt` (`runtime/`): порядок разбора D3; исполнение новых команд в слоте хода по правилам D12 change `add-config-writer-and-reload`; `/compact` через компактор с `manual` и ожиданием `afterTurn` (D5); `/mode`, `/model` через `setMode` / `setModel` с порядком событий D6; логи D12. Тесты 1.3 зелёные.
- [x] 2.3 `[protocol]` Мост ACP: тест 1.4 зелёный без изменения проекции; если `ModeChanged` от команды не даёт `config_option_update` — исправление в `codelab_agent_acp` по §13.6 п. 4 и §13.7 (таблица проекции).
- [x] 2.4 `[protocol]` `conformance:agent` и `conformance:embedded` зелёные на фикстурах 1.1–1.2; `test-scenario --agent embedded` проигрывает `slash-help` и `slash-mode-plan`.
- [x] 2.5 `[agent]` Тесты хостов 1.5 зелёные; `fvm dart run melos run web-compile` зелёный.

- [x] 2.6 `[agent]` По двойному ревью (2026-11-10, D14): команды `compact`, `mode`, `model` ждут свою работу и отвечают по факту (применено — сообщение и `end_turn`; отмена до применения — `cancelled` без записи и события смены); `close()` ждёт идущую команду до закрытия журнала; общий разбор строки `parseCommandLine` (`commands/command_line.dart`); `enum BuiltinName` и `sealed BuiltinInvocation` (D1); порядок событий `/model` с `ModelOptionsChanged` в тесте ядра. Тесты подтверждены мутациями.
- [x] 2.7 `[protocol]` По двойному ревью: мост признаёт эхом только `changeId` своего клиентского запроса, `config_option_update` чужой смены (например, `/mode` во время `set_config_option`) отправляется до ответа на `session/prompt`; заметка `effort` §2.12.3 при `/model` по `ModelOptionsChanged` (§13.6). Детерминированный тест удержания. Отмена после применения `/mode plan`: кадры смены и сообщение до ответа, ответ `cancelled` (ACP-5, D14; `session_bridge_echo_test.dart`); закрытие сессии при `/mode` в очереди смен — отмена, а не сбой (ядро).

## 3. Клиенты

- [x] 3.1 `[client]` Реализация для 1.7: помощник `e2e_agent.dart` (команды агента по виду агента), сценарий режима для `dart` и `embedded`; изменений `codelab_client_core` не ожидается — если меню расходится со спецификацией, правка `CommandCatalog` по codelab-cli. `test:e2e:cli:dart-agent` и `test:e2e:cli:embedded` зелёные.
- [x] 3.2 `[desktop]` Реализация для 1.8: помощник `integration_test/support/e2e_agent.dart` (ответ на `/compact` по режиму). `fvm flutter analyze` app зелёный; тест на устройстве — в `release/*` (прогон на устройстве — в release/*).

## 4. Матрица и ворота

- [x] 4.1 `[protocol]` `packages/dart/codelab_architecture_tests/test/parity_evidence_test.dart`: записи K-02 и R-08 удалены из `knownGaps`; если список пуст — удалены константа и проверка устаревания (D4 change `switch-default-agent-to-dart`). `guard` зелёный.
- [x] 4.2 `[protocol]` Ночной `parity` (`workflow_dispatch` на ветке или после merge): K-02, R-08 и U-03 — `pass` (app-часть K-02 — `deferred`). Запуск — в описании pull request; итог — в задаче 4.0 change `switch-default-agent-to-dart`. Итог (2026-11-10): ручной `workflow_dispatch` на ветке `feature/add-agent-builtin-slash-commands`, коммит `61edec91` — https://github.com/pese-git/codelab-app/actions/runs/42774368417; все джобы зелёные, `parity` и `ci` — success. Из 157 доказательств `pass` 139, `deferred` 18 (только `app:`), `missing`, `not-run`, `skipped`, `failed` — 0; K-02 `acp/slash-compact`, R-08 `acp/slash-help` и `acp/slash-mode-plan`, U-03 `cli/slash-menu-merges-agent-commands` — `pass`. Pull request #271.
- [x] 4.3 `[protocol]` Матрица `agent-parity-goals.md`: в K-02, R-08, U-03 пометка «закрыто change `add-agent-builtin-slash-commands`» с файлами тестов и фикстур (§1.5); R-07 — встроенные команды в списке закрыты этим change, MCP prompts — E-24. Сделано (2026-11-10): группа `exists` `parity_evidence_test.dart` зелёная, число Must совпадает с §7.
- [ ] 4.4 `[protocol]` Архивирование — только по просьбе пользователя. При слиянии дельт: строка Purpose `agent-slash-commands` («`/x` без шаблона и без встроенной команды уходит модели как есть») приведена к «Неизвестная команда»; Purpose упоминает встроенные команды MVP.
