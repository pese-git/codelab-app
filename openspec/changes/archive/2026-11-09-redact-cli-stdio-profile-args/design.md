## Context

CLI описывает stdio-профиль строкой `[command, ...args].join(' ')` в пяти местах `apps/codelab_cli/lib/src/`:

1. `session_setup.dart`, `describeProfile`: строки `codelab: cannot start the agent …` (`repl/repl.dart`, `tui/tui_runner.dart`, `headless/headless_runner.dart`) и `codelab: cannot connect to …` (`repl/repl.dart`, `tui/tui_command_context.dart`).
2. `repl/commands/profile.dart`: `/profile` без аргументов печатает `Profile <id> (<label>): stdio <command args…>`. У профиля из `--agent stdio:…` `label` — исходная строка `--agent` (`profiles/profile_arg.dart`, `inlineAgentProfile`), то есть аргументы печатаются дважды. `ProfileCommand` общий для REPL и TUI.
3. `profiles/profiles_command.dart`, `_summary`: `codelab profiles list` — `stdio: <command args…>`.
4. `profiles/profiles_command.dart`, `_show`: `codelab profiles show` — `args: <JSON>`.
5. `profiles/profile_arg.dart`: `Invalid agent command "<value>": <reason>.` повторяет весь `--agent`.

Причина сбоя запуска несёт аргументы. `StdioAcpTransport.start()` (`codelab_acp_transports`, `lib/src/io/stdio_acp_transport.dart`) кладёт исходный `ProcessException` в `cause` ошибки `AcpTransportException(startFailed)` события `AcpTransportFailure` и пробрасывает его же (`rethrow`). `ProcessException.toString()` — `ProcessException: <message>\n  Command: <executable> <arguments>`. Отсюда две утечки помимо строк CLI:
- `cause` для потребителей ошибки: `AcpClientApplication` пишет в журнал `'cause': error.cause?.toString()` (`acp_client_application.dart`, `_recordDiagnostic`). Сейчас там `AcpTransportException`, а её `toString()` (`AcpTransportException($code): $message`) вложенный `cause` не печатает, поэтому журнал `--verbose` CLI на этом пути аргументов не содержит; проверено вручную с отключённым D8. Журнал при этом пишет `'cause': entry.cause` после `...entry.context` (`_logDiagnosticEntry`), и ключ из `context` затирается. А `DiagnosticEntry.context['cause']` до D8 содержал полную строку `ProcessException … Command: <exe> <args>` и уходил в `diagnosticStream` и инспектор app — это реальный канал, его и закрывает D8. Кроме того, вложенный `ProcessException` с аргументами остаётся доступным любому коду, который разбирает `cause` (`classifyProbeFailure`, диагностика app, будущий журнал). `SecretRedactor` маскирует `Token\s+X`, но не `--api-key X` и не позиционный секрет, поэтому опираться на него нельзя. Тест `-p --verbose` (задача 6.3) — регрессионная защита, а не доказательство D8;
- `codelab test-scenario`: драйвер фикстур (`codelab_acp_testing`, `agent_conformance.dart`) вызывает `client.start()` напрямую, и `_play` (`scenario/test_scenario_command.dart`) печатает `describeFailure(error)` — то есть `ProcessException.toString()` — в stdout.

В REPL, TUI и `-p` до этого change причина печаталась без аргументов: `AcpClientApplication` заворачивает ошибку старта в `AcpClientApplicationException('Failed to connect ACP transport.')`, и `describeStartFailure` → `describeFailure` печатает только этот текст. `FormatException` разбора (`parseShellWords`, kit) несёт значение в `source`, но CLI печатает только `message` (`Unterminated single quote`, `Trailing backslash` и т. п.).

После PR #248 (`develop` 7c71453) в дельте `add-provider-setup-ui` есть требование «Адрес WebSocket-профиля в выводе CLI»: `describeProfile` для WS — `profileOrigin(uri)`, причина — `describeStartFailure`. Этот change ветки WS в `describeProfile` и `describeStartFailure` не меняет; `/profile` теперь печатает WS-профиль через `describeProfile`, то есть origin-ом, как и требует «Адрес WebSocket-профиля в выводе CLI» (D3).

App уже показывает только команду (`profileSummary`, `apps/codelab_desktop/lib/features/settings/application/profile_view.dart`; spec app-settings «Список профилей на странице «Connection»», вторая строка — «команду stdio без аргументов»), а заголовок при `label` из значения `--agent` — `id` (`profileTitle`). Дельта `app-settings` не нужна.

Ограничения: корневой `AGENTS.md` §2 (безопасность выше UX), §10 (секреты не попадают в вывод), §16 (маскирование), §13 (без новых абстракций), §19; `apps/codelab_cli/AGENTS.md` §2.

## Goals / Non-Goals

**Goals:** ни одно значение аргумента stdio-профиля не попадает в stdout, stderr и журнал CLI, включая `--verbose` и `test-scenario`; ошибка запуска stdio-транспорта не несёт аргументов ни для одного клиента; описание профиля одинаково во всех строках; поведение совпадает с app.

**Non-Goals:** WebSocket-адреса (требование «Адрес WebSocket-профиля в выводе CLI» change `add-provider-setup-ui`), маскирование по шаблонам, формат `profiles.json`, `UnsupportedConnectionProfileException` kit (FU2), код app.

## Decisions

### D1. Значения аргументов не печатаются нигде; печатается их число

Аргументы stdio-профиля CLI показывает только числом. Команда (`StdioProfile.command`) печатается как есть, полным путём, как в app: без неё нельзя понять, какой агент не запустился.

Альтернативы:
- маскировать по шаблонам (`SecretRedactor`) — отклонено: он ловит `Token\s+X`, `key=value`, `Bearer …` и PEM, но не `--api-key X` и не позиционный секрет, а расширение шаблонов даёт ложное чувство защиты;
- маскировать значение после флагов с именами `token|key|secret|password` — отклонено: список имён никогда не полон, позиционный секрет остаётся;
- печатать аргументы без значений флагов (`--api-key ***`) — отклонено по той же причине: что считать значением, по строке не определить;
- не печатать даже число — отклонено: число отличает «агент без аргументов» от «агента с аргументами» в диагностике, а значений не раскрывает.

Цена: `profiles show` больше не показывает разбор аргументов. Посмотреть значения можно только в `$CODELAB_HOME/profiles.json`. Это осознанная потеря (приоритет 1 выше UX, §2).

### D2. Один формат числа аргументов

Число аргументов `N` записывается как `1 argument` при `N = 1` и `<N> arguments` при остальных `N`. Одна функция рядом с `describeProfile` в `session_setup.dart`; `profiles_command.dart` и `repl/commands/profile.dart` её импортируют. Форматы:

| Вывод | `N = 0` | `N > 0` |
|---|---|---|
| `describeProfile` (ошибки запуска и подключения) | `"<command>"` | `"<command>" with <N> argument(s)` |
| `/profile` | `Profile <id>[ (<label>)]: stdio "<command>"` | `Profile <id>[ (<label>)]: stdio "<command>" with <N> argument(s)` |
| `profiles list` | `<id>  stdio: <command>` | `<id>  stdio: <command> (<N> argument(s))` |
| `profiles show` | `args: 0` | `args: <N> (values hidden)` |

Примеры: `codelab: cannot start the agent "codelab-agent" with 2 arguments: Failed to connect ACP transport.`; `dev  stdio: codelab-agent (2 arguments)`; `args: 3 (values hidden)`.

Кавычки вокруг команды в `describeProfile` остаются, как сейчас: путь с пробелами читается однозначно. В `profiles list` их нет, как и раньше.

Альтернатива — `(+2 args)` или `[2 args]` — отклонена: сокращение `args` в человеческом тексте хуже читается, а одна формулировка во всех местах проще тестировать.

### D3. `/profile`: описание через `describeProfile`, правило `label` как у `profileTitle`

`/profile` без аргументов печатает `Profile <id> (<label>): <описание>`. Скобки с `label` опускаются, если `label` после `trim()` пуст или начинается с `stdio:`, `ws://` или `wss://` — так CLI заполняет `label` профиля из значения `--agent` (`inlineAgentProfile`, в том числе у `profiles add`). Правило одно для всех типов профилей, как у `profileTitle` app: у WS-профиля из `--agent` скобки тоже исчезают. Адрес WS-профиля в `/profile` печатается через `describeProfile` — только origin, как требует «Адрес WebSocket-профиля в выводе CLI» change `add-provider-setup-ui` (там `/profile` назван явно, а в `develop` ветка ещё печатала полный URL). Для stdio описание — `stdio ` и `describeProfile(profile)`.

Правило живёт функцией в `profiles/profile_arg.dart`, рядом с кодом, который заполняет `label` из `--agent`.

Альтернатива — перенести `profileTitle` в kit (`codelab_client_core`) и вызывать из app и CLI — отклонена в этом change: это публичный API kit и правка app ради трёх строк; кандидат на отдельную задачу, если правило понадобится третьему потребителю (§13).

### D4. Ошибка разбора `stdio:…` без значения `--agent`

`Invalid agent command "<value>": <reason>.` заменяется на `Invalid agent command: <reason>.`, а `Invalid agent command "<value>": no command.` — на `Invalid agent command: no command.`. Причина — только `FormatException.message`, без `source`. Код выхода `64` не меняется.

### D5. Спецификация: новое требование и уточнение «Профили подключения CLI»

Правило D1–D4 — новое требование `codelab-cli` «Аргументы stdio-профиля в выводе CLI». Требование «Профили подключения CLI» меняется через MODIFIED: сценарии «Профиль stdio с кавычками» (проверка через `profiles.json`) и «Агент не запускается» (команда без аргументов), фраза про ошибку подключения ссылается на новое требование.

Текст MODIFIED взят из дельты активного change `add-provider-setup-ui` (`specs/codelab-cli/spec.md`), а не из `openspec/specs/`: итерация 1 того change уже в `develop` (токены `secret:`), и его текст требования — актуальное поведение. Дельта `add-provider-setup-ui` этим change не правится; порядок архивации — риск и follow-up FU1.

### D6. Значение `--agent` не повторяется в ошибках выбора профиля

Значение `--agent`, не похожее на `stdio:…`, `ws://…`, `wss://…`, `embedded` и `default`, CLI считает id профиля. Если пользователь забыл префикс `stdio:` (`-a 'my-agent --api-key sk-…'`), это значение — командная строка с секретом. Поэтому два текста больше не цитируют значение:
- `resolveAgentProfile` (`profiles/profile_arg.dart`; `-a <value>` и `/profile <value>` в REPL и TUI): `Unknown agent profile "<value>". Run "codelab profiles list".` → `Unknown agent profile. Run "codelab profiles list".`, код `64` (в REPL и TUI — строка без выхода, как сейчас);
- `codelab profiles add <id> <value>`: `Invalid agent "<value>": use "stdio:<command> [args]", ws:// or wss://.` → `Invalid agent: use "stdio:<command> [args]", ws:// or wss://.`, код `64`. Id нового профиля в тексте правила id (`Invalid profile id "<id>": …`) остаётся: это id, а не значение `--agent`.

Альтернатива — печатать значение, если оно похоже на id (без пробелов или по правилу `isValidProfileId`), — отклонена: голый токен без пробелов (`-a sk-test-leak-0123456789`) проходит и проверку на пробелы, и `isValidProfileId`, а профили прежних версий с заглавными буквами её не проходят. Надёжно отличить id от секрета по строке нельзя (то же рассуждение, что в D1). Пользователь видит свой ввод в командной строке; список id даёт `codelab profiles list`.

Не меняются `codelab: Unknown agent profile "<id>".` у `profiles show <id>` и `profiles remove <id>`: аргумент там по смыслу — id, а не значение `--agent`, и форма `stdio:` там не принимается.

### D7. Пакеты, исполнители, зависимости, сторож

| Пакет | Что меняется | Исполнитель |
|---|---|---|
| `codelab_acp_transports` | `StdioAcpTransport.start()`: ошибка запуска без аргументов (D8), тест | `[protocol]` |
| `codelab_client_io` | только регрессионный тест `classifyProbeFailure` на ошибке с аргументами (D8) | `[client]` |
| `apps/codelab_cli` | тексты D1–D6, `_play` драйвера фикстур (D9), тесты, `AGENTS.md` | `[client]` |

`codelab_client_acp` (`_recordDiagnostic`) и `codelab_acp_testing` (`agent_conformance.dart`) не меняются: причина исправлена в источнике (D8). Код app не меняется — app получает исправление через транспорт. Новых пакетов и зависимостей нет. Единственный новый импорт — `dart:io show ProcessException` в `apps/codelab_cli/lib/src/session_setup.dart` (вторая линия D9); исключение записано в `apps/codelab_cli/AGENTS.md` §2; `io.dart` транспорта уже содержит `dart:io`, барель остаётся web-безопасным. Правило сторожа в `codelab_architecture_tests/test/support/rules.dart` не нужно, граф `README.md` не меняется.

### D8. Транспорт отдаёт ошибку запуска без аргументов

`StdioAcpTransport.start()` ловит `ProcessException` от `Process.start` и заменяет его копией `ProcessException(error.executable, const [], error.message, error.errorCode)`. Копия уходит и в `cause` ошибки `AcpTransportException(startFailed)` события `AcpTransportFailure`, и наружу: `Error.throwWithStackTrace(copy, stackTrace)` вместо `rethrow`, с исходным стеком. Остальные ошибки запуска передаются как раньше. Так одно место закрывает утечку для всех потребителей: журнал `--verbose` CLI и app (`'cause': error.cause?.toString()`), драйвер фикстур, `describeFailure`, будущие клиенты.

Почему копия, а не новый тип: `classifyProbeFailure` (`codelab_client_io`) проверяет `current is ProcessException` и `errorCode` (ENOENT → `CommandNotFound`), а агентские пакеты и CLI ловят `on ProcessException`. Тип, `message` и `errorCode` сохраняются, контракт ловли не меняется. `executable` остаётся: команду печатают и CLI, и app (D1).

Альтернативы:
- обернуть в собственный тип транспорта (`AcpTransportException` наружу вместо `ProcessException`) — отклонено: меняет контракт ловли и ломает `classifyProbeFailure`, нужно бы переносить errno-логику;
- санировать `ProcessException` в kit (`_recordDiagnostic`, `describeFailure`) — отклонено: мест несколько (`codelab_client_acp`, `codelab_client_core`, драйвер фикстур в `codelab_acp_testing` вызывает транспорт мимо kit), каждое новое место пришлось бы помнить;
- расширить `SecretRedactor` — отклонено по D1.

Поведение транспорта — capability `agent-transports`, новое требование «Ошибка запуска stdio transport без аргументов». Дельта `acp-client-kit` не нужна: сценарий «Классификация отсутствующей команды» не меняется и дополнен регрессионным тестом.

### D9. Драйвер фикстур: для ошибки запуска процесса — только текст ОС

`_play` (`scenario/test_scenario_command.dart`) печатает `the agent did not run the fixture: <причина>`, где причина для `ProcessException` — `ProcessException.message` (например, `No such file or directory`), для остальных ошибок — `describeFailure(error)`, как раньше. Это вторая линия защиты на случай, если ошибка придёт не из `StdioAcpTransport` (connector драйвера, будущие транспорты): строка `Command: …` в stdout драйвера не попадает никогда. То же правило действует в `describeStartFailure` (`session_setup.dart`) для строк `cannot start the agent` и `cannot connect to` в REPL, `--ui tui` и `-p`: сырой `ProcessException` от резолвера (не обёрнутый `AcpClientApplication`) печатается как `message`, остальные ошибки — как раньше (тесты задачи 7.1). Имя команды строка `FAIL` не называет — она стоит под id фикстуры, а профиль задан флагом `--agent` того же запуска.

Альтернатива — `describeProfile` в строке `FAIL` — отклонена: драйвер подставляет `{fixture}` в аргументы, и формат строки фикстуры спецификации `cli-scenario-driver` пришлось бы менять ради дублирования флага.

## Risks / Trade-offs

- [Потеря диагностики `profiles show`] → значения видны в `profiles.json`; строка `args: <N> (values hidden)` говорит, что они скрыты намеренно.
- [Секрет в самой команде, например `stdio:TOKEN=sk-… agent`] → `parseShellWords` даёт команду `TOKEN=sk-…`, и она печатается как есть. Такой профиль не запускается (это не путь к исполняемому файлу). Принято: app печатает команду так же; вне scope.
- [Противоречие с требованием «Адрес WebSocket-профиля в выводе CLI» change `add-provider-setup-ui`] → его текст заканчивается фразой «Stdio-профили описываются как раньше». После архивации обоих change эта фраза противоречит требованию «Аргументы stdio-профиля в выводе CLI». Дельта `add-provider-setup-ui` здесь не правится; см. FU1.
- [Совместимость с требованием «Отказ подключения из-за токена»] → противоречия нет: оно задаёт причину для WS 401/403 и ссылается на `<адрес>` WS-профиля, а этот change — описание stdio-профиля и причину сбоя запуска процесса.
- [Ошибка запуска транспорта меняется для всех клиентов] → тип, `message` и `errorCode` сохранены (D8); пропадают только `arguments`. Регрессионный тест `classifyProbeFailure` и существующие тесты app на `CommandNotFound` это проверяют.
- [Порядок архивации с `add-provider-setup-ui`] → оба change переписывают требование «Профили подключения CLI» целиком. Если `add-provider-setup-ui` архивируется после этого change, его текст откатит уточнённые сценарии «Профиль stdio с кавычками», «Агент не запускается» и фразу про ошибку подключения. Дельта `add-provider-setup-ui` здесь не правится; см. FU1.
- [Сообщение «Unknown agent profile» без id] → при опечатке в id пользователь не видит, что именно не найдено; компенсирует `codelab profiles list` в тексте (D6).
- Race, cancellation и late events не затрагиваются: меняются только тексты; permissions, containment и ACP — тоже.

## Follow-ups (вне scope)

- FU1. Порядок архивации с `add-provider-setup-ui` (D5). Текст MODIFIED «Профили подключения CLI» сверен с дельтой после PR #248: он совпадает с её версией, кроме трёх правок этого change, новое не откатывается. Рекомендуемый порядок — архивировать `add-provider-setup-ui` первым, затем этот change. Иначе перед архивацией `add-provider-setup-ui` перенести в его дельту сценарии «Профиль stdio с кавычками», «Агент не запускается» и фразу про ошибку подключения. В любом порядке фразу «Stdio-профили описываются как раньше» требования «Адрес WebSocket-профиля в выводе CLI» заменить на «Stdio-профили — по требованию «Аргументы stdio-профиля в выводе CLI»». Решение — при архивации, с согласия пользователя.
- FU2. `UnsupportedConnectionProfileException` (kit, `client_workspace_exception.dart`) цитирует `label` профиля, а у профиля из `--agent` это вся командная строка. В CLI для stdio ветка недостижима (резолверы есть для всех типов), но app и будущие клиенты могут показать текст. Отдельная задача kit.
- FU3. REPL делит строку slash-команды по пробелам (`command_router.dart`), поэтому `/profile stdio:my-agent --api-key …` берёт только первое слово: аргументы молча теряются, а строку ввода REPL повторяет эхом. Эхо — ввод пользователя, не вывод профиля. Потеря аргументов — отдельная задача; сценарии этого change используют `/profile <id>` из `profiles.json`.
- FU4. `codelab profiles list` (`ws: <uri>`) и `codelab profiles show` (`uri: <uri>`) печатают адрес WS-профиля целиком, с query и userinfo. Требование «Адрес WebSocket-профиля в выводе CLI» эти места не называет; это отдельный change в том же классе утечек.
- FU5. Коллизия ключа `cause` в `_logDiagnosticEntry` (`acp_client_application.dart`): вложенная причина из `context` теряется в журнале. После D8 её безопасно логировать под отдельным ключом (AGENTS.md §16).
