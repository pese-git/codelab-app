## Why

CLI `codelab` печатает команду stdio-профиля вместе со всеми аргументами. Если пользователь вписал секрет в аргументы (`--agent 'stdio:my-agent --api-key sk-…'` или такой же профиль в `profiles.json`), значение уходит в stdout и stderr: в строку ошибки запуска, в `/profile`, в `codelab profiles list|show` и в ошибку разбора `--agent`. Кроме того, `StdioAcpTransport` отдаёт наружу `ProcessException` с аргументами (`Command: <exe> <args>`), и они попадают в журнал `--verbose` (CLI и app) и в строку `FAIL` `codelab test-scenario`. Это нарушает приоритет 1 и правила секретов корневого `AGENTS.md` (§2, §10, §16).

Маскирование по шаблонам не помогает. `SecretRedactor` (`codelab_client_acp`, `lib/src/domain/secret_redaction.dart`) ловит `key=value`, `Bearer …`, `Token X` и PEM, но не `--api-key sk-…` и не позиционный секрет. Какой из аргументов секретный, по строке не определить: значение может идти позиционным аргументом. Надёжное правило одно: значения аргументов stdio-профиля CLI не печатает нигде.

codelab-app уже следует этому правилу: сводка stdio-профиля — только команда, без аргументов, `env` и токена (`profileSummary`, spec app-settings «Список профилей на странице «Connection»»). Заголовок при `label` из значения `--agent` — `id` (`profileTitle`). CLI выравнивается с app.

## What Changes

- Описание stdio-профиля во всех выводах CLI — команда как есть и число аргументов, без значений аргументов:
  - `codelab: cannot start the agent "<command>" with <N> arguments: <причина>` (REPL, `--ui tui`, `-p`) и `codelab: cannot connect to "<command>" with <N> arguments: <причина>` (`/profile <id>` в REPL и TUI);
  - `/profile` без аргументов — `Profile <id>: stdio "<command>" with <N> arguments`; `label` в скобках не печатается, если он пуст или взят из значения `--agent` (`stdio:…`, `ws://…`, `wss://…`) — то же правило, что `profileTitle` app;
  - `codelab profiles list` — `stdio: <command> (<N> arguments)`;
  - `codelab profiles show` — `args: <N> (values hidden)` вместо JSON-массива значений;
  - ошибка разбора `stdio:…` — `Invalid agent command: <причина>.` без повтора значения `--agent`;
  - неизвестный id в `-a` и `/profile` — `Unknown agent profile. Run "codelab profiles list".`, неверное значение `profiles add` — `Invalid agent: use "stdio:<command> [args]", ws:// or wss://.`: значение `--agent` без префикса `stdio:` может быть командной строкой с секретом;
  - причина сбоя запуска процесса — без аргументов: `StdioAcpTransport.start()` отдаёт и в `cause`, и в throw копию `ProcessException` без `arguments` (тип, `message` и `errorCode` сохраняются); драйвер фикстур печатает для `ProcessException` только текст ОС.
- Новое требование spec `codelab-cli` «Аргументы stdio-профиля в выводе CLI» со сценариями маркера `sk-test-leak-0123456789` (`--api-key <маркер>` и позиционный маркер), включая `--verbose` и `--ui tui`.
- Новые требования `agent-transports` «Ошибка запуска stdio transport без аргументов» и `cli-scenario-driver` «Ошибка запуска агента в test-scenario без аргументов».
- Требование «Профили подключения CLI» уточняется: сценарий «Профиль stdio с кавычками» проверяет `profiles.json`, а не вывод `profiles show`; сценарий «Агент не запускается» — сообщение с командой и без аргументов.
- `apps/codelab_cli/AGENTS.md` §2: правило про аргументы рядом со строкой про токен.

## Не входит

- Адрес WebSocket-профиля: origin вместо полного URL задаёт требование «Адрес WebSocket-профиля в выводе CLI» change `add-provider-setup-ui` (PR #248). Ветки WS в `describeProfile`, `profiles list|show` и текст `Invalid agent URL "<value>"` здесь не меняются; общее правило скобок `label` в `/profile` действует и для WS (D3).
- Переменные `env` профиля: `profiles show` уже печатает только имена.
- Маскирование по шаблонам и правка `SecretRedactor`; правка журнала kit (`_recordDiagnostic`) и драйвера `codelab_acp_testing` — причина исправлена в транспорте (D8).
- Формат `profiles.json`: значения аргументов и `label` хранятся как раньше; файл — единственное место, где их видно.
- Сообщения kit (`UnsupportedConnectionProfileException` с `label`): CLI держит резолверы для всех типов профилей, и для stdio эта ветка в CLI недостижима (FU2 design.md).
- `codelab: Unknown agent profile "<id>".` у `profiles show|remove <id>`: аргумент там — id, а не значение `--agent` (D6).
- Потеря аргументов в `/profile stdio:… args` (FU3 design.md).
- Правка дельты активного change `add-provider-setup-ui` (риск порядка архивации, FU1 design.md).
- codelab-app: код и дельта `app-settings` не нужны — app уже показывает только команду, а журнал app исправляется транспортом (D8).
- ACP не меняется.

## Capabilities

### Modified Capabilities
- `codelab-cli`: новое требование «Аргументы stdio-профиля в выводе CLI»; уточнены сценарии требования «Профили подключения CLI».
- `agent-transports`: новое требование «Ошибка запуска stdio transport без аргументов».
- `cli-scenario-driver`: новое требование «Ошибка запуска агента в test-scenario без аргументов».

## Impact

- `apps/codelab_cli/lib/src/`: `session_setup.dart` (`describeProfile`), `repl/commands/profile.dart`, `profiles/profiles_command.dart` (`_summary`, `_show`), `profiles/profile_arg.dart` (тексты ошибки разбора и неизвестного профиля, правило `label` из `--agent`), `profiles/profiles_command.dart` (текст `Invalid agent` у `profiles add`).
- `apps/codelab_cli/lib/src/scenario/test_scenario_command.dart` (`_play`).
- `packages/dart/codelab_acp_transports/lib/src/io/stdio_acp_transport.dart` (`start`) и тест транспорта.
- `packages/dart/codelab_client_io/test/`: регрессионный тест `classifyProbeFailure`.
- Тесты `apps/codelab_cli/test/`: `profiles/*`, `repl/commands/profile_test.dart`, `session_setup_test.dart`, `tui/tui_command_context_test.dart`, `scenario/test_scenario_command_test.dart`, e2e `headless_print_basic_test.dart`.
- `apps/codelab_cli/AGENTS.md` §2.
- Новых пакетов и зависимостей нет; сторож (`rules.dart`) и граф `README.md` не меняются.
