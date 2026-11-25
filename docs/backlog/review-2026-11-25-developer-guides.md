# Backlog: находки при написании руководств разработчика, ревью 2026-11-25

Пункты найдены при написании руководств разработчика по пакетам и приложениям монорепо. Каждое руководство сверялось с кодом ревьюером `architecture-reviewer`. Источники (REV-19…22 — из раздела алгоритмов `packages/dart/codelab_agent_core/doc/algorithms/`; REV-23…28 — из документации механизма маскирования, REV-29…33 — из документации механизма хранения секретов, REV-34…40 — из документации хранения и управления сессиями, REV-41…42 — из документации сторон исполнения approval, инструментов, `fs/*` и `terminal/*`, REV-43…45 — из документации механизма подсчёта usage, REV-46…47 — из документации механизма настроек, REV-48…51 — из OpenSpec changes по пробелам обвязки агента и ADR-0004, подтверждены ревью; найдены позже в тот же день):
- [#471](https://github.com/pese-git/codelab-app/pull/471) — ядро агента;
- [#472](https://github.com/pese-git/codelab-app/pull/472) — слой ACP и сторож;
- [#473](https://github.com/pese-git/codelab-app/pull/473) — агентская сторона;
- [#474](https://github.com/pese-git/codelab-app/pull/474) — `codelab_ui` и desktop;
- [#475](https://github.com/pese-git/codelab-app/pull/475) — клиент без UI и CLI.

Пункты, которые прямо описаны в коде, выборочно перепроверены по коду при заведении: `OutboundQueue` без `onSendFailed` и условие в `HostLogger._dispatch`. Остальное взято из отчётов сессий и их ревью.

Приоритеты и колонки — как в [smoke-2026-10-30.md](smoke-2026-10-30.md).

## Сводка

| ID | P | Тип | Область | Кратко | OpenSpec | Issue |
|---|---|---|---|---|---|---|
| REV-3 | P2 | bug | protocol | `close()` транспортов: падение при вызове из обработчика `events` и `TimeoutException` у WebSocket | нет | [#476](https://github.com/pese-git/codelab-app/issues/476) |
| REV-4 | P3 | spec | protocol | Транспорты расходятся со спеками: тип ошибки отказа рукопожатия, нет логгера `component=transport` | да | [#477](https://github.com/pese-git/codelab-app/issues/477) |
| REV-5 | P2 | bug | protocol | Сгруппированные значения опции `select` (`SessionConfigSelectGroup`) не поддержаны: `session/new` отвергается целиком | да | [#478](https://github.com/pese-git/codelab-app/issues/478) |
| REV-6 | P3 | bug | protocol | `encodeAcpRequest`/`encodeAcpResponse` с неверным типом модели дают `TypeError` вместо типизированной ошибки | нет | [#479](https://github.com/pese-git/codelab-app/issues/479) |
| REV-7 | P3 | tech-debt | testing | Загрузчик golden-фикстур не проверяет то, что задаёт `_schema.json`; `setup.web` не читается | нет | [#480](https://github.com/pese-git/codelab-app/issues/480) |
| REV-8 | P2 | boundary | guard | Сторож: правила `codelab_acp_testing` и `dart_tui` для `apps/codelab_cli` покрывают только `lib/src`, не барель и `bin/` | нет | [#481](https://github.com/pese-git/codelab-app/issues/481) |
| REV-9 | P2 | bug | agent, protocol | `codelab_agent_acp`: `onSendFailed` не подключён, отсоединённые сессии не истекают, `session/list` без проверки capability | да | [#482](https://github.com/pese-git/codelab-app/issues/482) |
| REV-10 | P3 | bug | agent | `HostLogger._dispatch`: условие `!identical(_sinks.first, sink)` после удаления приёмника всегда истинно | нет | [#483](https://github.com/pese-git/codelab-app/issues/483) |
| REV-11 | P2 | bug | cli | `codelab profiles add|remove` на битом `profiles.json` падают с `FormatException` (код 255) вместо кода 64 | нет | [#484](https://github.com/pese-git/codelab-app/issues/484) |
| REV-12 | P2 | bug | client, protocol | `fs/read_text_file`/`fs/write_text_file` с относительным `path` отвечают `-32603` вместо `-32602` | нет | [#485](https://github.com/pese-git/codelab-app/issues/485) |
| REV-13 | P2 | bug | client | `send` из обработчика `SessionHandle.view` теряет промпты, из `promptOutcomes` — обгоняет очередь | да | [#486](https://github.com/pese-git/codelab-app/issues/486) |
| REV-14 | P2 | security | cli | `inlineAgentProfile` цитирует невалидный `ws://…` целиком в stderr | нет | [#487](https://github.com/pese-git/codelab-app/issues/487) |
| REV-15 | P3 | tech-debt | ui | `codelab_ui`: неиспользуемая зависимость `flutter_bloc`, тест превью покрывает не всё, `gen-l10n` падает в свежем checkout | нет | [#488](https://github.com/pese-git/codelab-app/issues/488) |
| REV-16 | P3 | docs | docs | Устаревшие `AGENTS.md`, архитектурные документы и комментарии кода | нет | [#489](https://github.com/pese-git/codelab-app/issues/489) |
| REV-17 | P3 | docs | docs | Стандарт `codelab-docs` §7 запрещает снимки хода агента, хотя их можно честно снять на сценарной модели | нет | [#490](https://github.com/pese-git/codelab-app/issues/490) |
| REV-18 | P3 | tech-debt | agent | Ядро агента: объявленное, но не подключённое (steering, `loop.*`, fallback, `grantForTurn`, `ToolTier.network`, Gemini) | да | [#491](https://github.com/pese-git/codelab-app/issues/491) |
| REV-19 | P2 | bug | agent, config | `compaction.keep_recent_user_turns: 0` (или отрицательное) роняет сжатие с `StateError`; при аварийном сжатии падает весь ход | нет | [#493](https://github.com/pese-git/codelab-app/issues/493) |
| REV-20 | P3 | bug | agent | Рантайм пишет причину пропуска MCP в лог по-русски («сервис MCP не передан») | нет | [#494](https://github.com/pese-git/codelab-app/issues/494) |
| REV-21 | P3 | bug | agent, mcp | Серверы MCP с именами вроде `my.srv` и `my_srv` получают общий префикс инструментов; у агента с ограниченным набором `toolCount` считается суммой | нет | [#495](https://github.com/pese-git/codelab-app/issues/495) |
| REV-22 | P3 | tech-debt | agent | Проверка отмены перед стартом хода потомка ничего не делает, комментарий в коде утверждает обратное | нет | [#497](https://github.com/pese-git/codelab-app/issues/497) |
| REV-23 | P2 | security | client, ui | Строка инструмента и блок одобрения показывают поля без маскирования секретов | нет | [#499](https://github.com/pese-git/codelab-app/issues/499) |
| REV-24 | P2 | security | agent | `describeHttpError` усекает тело ошибки до вычистки секретов: на границе остаётся начало ключа | нет | [#500](https://github.com/pese-git/codelab-app/issues/500) |
| REV-25 | P2 | security | agent | `codelab-agent` пишет в журнал полный текст исключений и стек: ядро передаёт в `error:` сырой объект | нет | [#501](https://github.com/pese-git/codelab-app/issues/501) |
| REV-26 | P3 | security | agent, config | `config get` показывает литерал без известного формата рядом со ссылкой на секрет под секретным именем | нет | [#502](https://github.com/pese-git/codelab-app/issues/502) |
| REV-27 | P3 | bug | client | Ложные срабатывания `SecretRedactor`: подстрока `pass` и слова `Token`, `Basic`, `Digest` в обычном тексте | нет | [#503](https://github.com/pese-git/codelab-app/issues/503) |
| REV-28 | P3 | tech-debt | client, agent | Мелкие расхождения маскирования: пары `{name, value}` на верхнем уровне, экранирование ссылок, ключи `redact.*` без эффекта | да | [#504](https://github.com/pese-git/codelab-app/issues/504) |
| REV-29 | P2 | security | client, protocol | Клиент передаёт внешнему агенту и его командам `terminal/create` всё окружение, включая `CODELAB_SECRET_*` и `*_API_KEY` | да | [#506](https://github.com/pese-git/codelab-app/issues/506) |
| REV-30 | P2 | security | setup, desktop | Токен, вставленный в `${secret:…}` вместо имени, показывается в баннере desktop после удаления MCP-сервера | нет | [#507](https://github.com/pese-git/codelab-app/issues/507) |
| REV-31 | P3 | security | client, transport | Токен профиля WebSocket: `toString` конфигурации печатает токен, `ws://` на удалённый адрес не блокируется при открытии | нет | [#508](https://github.com/pese-git/codelab-app/issues/508) |
| REV-32 | P3 | tech-debt | agent | Хранилище секретов: дублированные тексты проблем `secrets.backend`, лог отказа пишет только первую причину, `_verifyFinal` удаляет весь файл | нет | [#509](https://github.com/pese-git/codelab-app/issues/509) |
| REV-33 | P3 | bug | desktop, embedded | Требует воспроизведения: после замены только ключа в мастере провайдера встроенный агент может ходить со старым ключом до перезапуска | нет | [#510](https://github.com/pese-git/codelab-app/issues/510) |
| REV-34 | P2 | bug | agent, protocol | Два одновременных `session/load` закрытой сессии открывают двух писателей над одним журналом | нет | [#513](https://github.com/pese-git/codelab-app/issues/513) |
| REV-35 | P2 | security | agent, protocol | Мост сессии не проверяет владельца: любое соединение может слать `session/prompt`, `set_mode`, `cancel` в чужую сессию | да | [#514](https://github.com/pese-git/codelab-app/issues/514) |
| REV-36 | P2 | bug | agent, io | Нет блокировки писателя сессии между процессами; ключи `sessions.lease` и `sessions.read_only` объявлены без эффекта | да | [#515](https://github.com/pese-git/codelab-app/issues/515) |
| REV-37 | P3 | bug | cli | `/resume` в REPL возвращает открытую `detached`-сессию без `session/load`: промпты в неё падают | нет | [#516](https://github.com/pese-git/codelab-app/issues/516) |
| REV-38 | P3 | bug | agent, io | Журнал сессии: заголовок-сирота при сбое создания, режим не пишется при создании, `set_mode` после сбоя записи, каталог без `fsync` | нет | [#517](https://github.com/pese-git/codelab-app/issues/517) |
| REV-39 | P3 | bug | agent, cli | `session/list` фильтрует `cwd` сравнением строк; `--continue` смотрит только первую страницу списка | нет | [#518](https://github.com/pese-git/codelab-app/issues/518) |
| REV-40 | P3 | bug | client | После ошибки записи снимок рабочего пространства не пишется повторно, пока состояние не изменится | нет | [#519](https://github.com/pese-git/codelab-app/issues/519) |
| REV-41 | P2 | bug | protocol, client | `StdioAcpTransport.send` пишет без очереди: два одновременных исходящих сообщения клиента падают с `sendFailed` | нет | [#521](https://github.com/pese-git/codelab-app/issues/521) |
| REV-42 | P3 | bug | agent | Агент спрашивает разрешение до проверки возможностей клиента: одобренный вызов `fs`/`terminal` гарантированно падает | да | [#522](https://github.com/pese-git/codelab-app/issues/522) |
| REV-43 | P2 | bug | agent | Отброшенный ответ (overflow до первого блока, повтор после ошибки спаривания) теряет usage: нарушено «usage шага — сумма всех попыток» | нет | [#525](https://github.com/pese-git/codelab-app/issues/525) |
| REV-44 | P3 | observability | client | Лог `usage.received` пишет триггеры `load` и `compactionDiscarded` как `other` | нет | [#526](https://github.com/pese-git/codelab-app/issues/526) |
| REV-45 | P3 | bug | cli | TUI печатает команду агента (`/usage`, `/status`) в ленте дважды | нет | [#527](https://github.com/pese-git/codelab-app/issues/527) |
| REV-46 | P3 | security | client, io | Файлы клиента (`profiles.json` и другие) создаются с правами по `umask`; `args` и `env` stdio-профиля с токеном видны другим локальным пользователям | нет | [#529](https://github.com/pese-git/codelab-app/issues/529) |
| REV-47 | P3 | ux | agent, io | `config get --layer merged` не учитывает доверие к проекту: показывает «выключенный» MCP-сервер, который агент запускает | да | [#530](https://github.com/pese-git/codelab-app/issues/530) |
| REV-48 | P2 | security | agent | Разрешение не перепроверяется после паузы: смена режима или `deny`, пока висит вопрос, не влияет на уже одобренный вызов | да | [#533](https://github.com/pese-git/codelab-app/issues/533) |
| REV-49 | P3 | security | agent | Доверие к проекту не запрашивается заново при изменении проектного конфига | да | [#534](https://github.com/pese-git/codelab-app/issues/534) |
| REV-50 | P3 | bug | agent, io | Allowlist окружения команд агента не содержит переменных Windows (`SystemRoot`, `PATHEXT` и др.) | нет | [#535](https://github.com/pese-git/codelab-app/issues/535) |
| REV-51 | P3 | bug | agent, protocol | Команда CodeLab-агента через клиента (`terminal/create`) не получает фиксированный набор `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0` | нет | [#536](https://github.com/pese-git/codelab-app/issues/536) |

## Карточки

### REV-3. `close()` транспортов: падение при вызове из обработчика `events` и `TimeoutException` у WebSocket (P2)

Источник: [#472](https://github.com/pese-git/codelab-app/pull/472). Issue: [#476](https://github.com/pese-git/codelab-app/issues/476).

**Где:**
- `packages/dart/codelab_acp_transports/lib/src/io/websocket_acp_transport.dart`
- `StdioServerAcpTransport` (`codelab_acp_transports`)

**Факт:**
- `close()`, вызванный синхронно из обработчика `events` у `WebSocketAcpTransport` и `StdioServerAcpTransport`, падает с `Bad state: Cannot fire new event`: контроллеры событий — sync broadcast. Транспорт остаётся в `closing`.
- `WebSocketAcpTransport.close()` вызывает `timeout` без `onTimeout`: при медленном закрытии сокета вызов бросает `TimeoutException`, транспорт остаётся в `closing`.

**Почему важно:** Транспорт застревает в `closing`, владелец не может корректно завершить соединение (`AGENTS.md` §9: явный lifecycle и отмена).

**Что сделать:**
- Сделать `close()` безопасным при вызове из обработчика событий (отложить эмиссию или async-контроллер).
- Дать `timeout` обработчик `onTimeout`, доводящий транспорт до `closed`.
- Тесты на оба случая.

### REV-4. Транспорты расходятся со спеками: тип ошибки отказа рукопожатия, нет логгера `component=transport` (P3)

Источник: [#472](https://github.com/pese-git/codelab-app/pull/472). Issue: [#477](https://github.com/pese-git/codelab-app/issues/477).

**Где:**
- `packages/dart/codelab_acp_transports/lib/`
- `openspec/specs/agent-transports/spec.md`, «Отказ рукопожатия со статусом»
- `openspec/specs/structured-logging/spec.md`

**Факт:**
- Спека требует, чтобы `start()` завершался `AcpTransportException(startFailed)`; код бросает `AcpWebSocketHandshakeRejected`.
- Спека `structured-logging` требует записи с `component=transport`; логгера в пакете нет.

**Почему важно:** Код и утверждённая спецификация противоречат друг другу (`AGENTS.md` §3.1); нельзя молча считать верным любое из двух.

**Что сделать:**
- Решить, что меняется — код или спека, и оформить OpenSpec change.

### REV-5. Сгруппированные значения опции `select` (`SessionConfigSelectGroup`) не поддержаны: `session/new` отвергается целиком (P2)

Источник: [#472](https://github.com/pese-git/codelab-app/pull/472). Issue: [#478](https://github.com/pese-git/codelab-app/issues/478).

**Где:**
- `packages/dart/codelab_acp_protocol/lib/src/acp/session.dart`
- `docs/protocols/acp/protocol/17-Schema.md` (`SessionConfigSelectGroup`)

**Факт:**
- Схема ACP допускает группы значений в опции `select`. Модель их не знает, и ответ `session/new` с такой группой отвергается целиком.

**Почему важно:** Клиент не может открыть сессию с агентом, который использует допустимую по ACP форму (`AGENTS.md` §2, приоритет 2; §7 forward compatibility).

**Что сделать:**
- Поддержать `SessionConfigSelectGroup` в моделях и кодеках, затем в клиенте (показ групп).
- Golden-фикстура ACP со ссылкой на раздел схемы.

### REV-6. `encodeAcpRequest`/`encodeAcpResponse` с неверным типом модели дают `TypeError` вместо типизированной ошибки (P3)

Источник: [#472](https://github.com/pese-git/codelab-app/pull/472). Issue: [#479](https://github.com/pese-git/codelab-app/issues/479).

**Где:**
- `packages/dart/codelab_acp_protocol/lib/src/acp/acp_method_codec.dart`

**Факт:**
- Передача модели не того типа для метода приводит к `TypeError`, а не к типизированной ошибке протокола.

**Почему важно:** `AGENTS.md` §15 и `docs/architecture/error-handling.md`: ошибки типизированы; `TypeError` хуже диагностируется.

**Что сделать:**
- Проверять тип модели и бросать типизированную ошибку; тест.

### REV-7. Загрузчик golden-фикстур не проверяет то, что задаёт `_schema.json`; `setup.web` не читается (P3)

Источник: [#472](https://github.com/pese-git/codelab-app/pull/472). Issue: [#480](https://github.com/pese-git/codelab-app/issues/480).

**Где:**
- `packages/dart/codelab_acp_testing/fixtures/acp/_schema.json`
- загрузчик фикстур `codelab_acp_testing`
- `packages/dart/codelab_acp_testing/test/fixtures_coverage_test.dart`

**Факт:**
- `_schema.json` задаёт `id` в kebab-case и `mode` по умолчанию `standard`; загрузчик ни то, ни другое не проверяет.
- Поле `setup.web` никто не читает.
- `docs/architecture/proposals/agent-core/14-golden-fixtures.md` §14.4 описывает сверку `fs/read_text_file` с `setup.files` — в коде её нет.
- Комментарий о `session/list` в `fixtures_coverage_test.dart` устарел.

**Почему важно:** Фикстура с ошибкой в схеме проходит молча; корпус фикстур — источник протокольных гарантий.

**Что сделать:**
- Валидировать фикстуры по `_schema.json` при загрузке.
- Решить судьбу `setup.web` и сверки `setup.files`.
- Обновить комментарий.

### REV-8. Сторож: правила `codelab_acp_testing` и `dart_tui` для `apps/codelab_cli` покрывают только `lib/src`, не барель и `bin/` (P2)

Источник: [#472](https://github.com/pese-git/codelab-app/pull/472). Issue: [#481](https://github.com/pese-git/codelab-app/issues/481).

**Где:**
- `packages/dart/codelab_architecture_tests/test/support/rules.dart`

**Факт:**
- Правила, ограничивающие импорт `package:codelab_acp_testing/` (только `lib/src/scenario/`) и `dart_tui` в `apps/codelab_cli`, заданы на `lib/src`. Импорт из бареля `lib/` или из `bin/` они не ловят.

**Почему важно:** Граница из корневого `AGENTS.md` §5 проверяется не полностью: тестовый пакет может попасть в рабочий бинарь в обход сторожа.

**Что сделать:**
- Расширить правила на `lib/` и `bin/` с нужными исключениями; красный тест сторожа.

### REV-9. `codelab_agent_acp`: `onSendFailed` не подключён, отсоединённые сессии не истекают, `session/list` без проверки capability (P2)

Источник: [#473](https://github.com/pese-git/codelab-app/pull/473). Issue: [#482](https://github.com/pese-git/codelab-app/issues/482).

**Где:**
- `packages/dart/codelab_agent_acp/lib/src/agent_server.dart:207`
- `packages/dart/codelab_agent_acp/lib/src/connection/outbound_queue.dart`

**Факт:**
- `OutboundQueue` создаётся в `_Connection` без `onSendFailed`: сбой отправки кадра не доходит до соединения.
- Простаивающие отсоединённые сессии не истекают.
- `session/list` не проверяет, объявил ли агент `sessionCapabilities.list`.

**Почему важно:** Сбой отправки теряется молча (`AGENTS.md` §12); сессии копятся; ответ на метод, не объявленный в capabilities, нарушает ACP.

**Что сделать:**
- Подключить `onSendFailed` к закрытию соединения.
- Решить политику истечения отсоединённых сессий.
- Проверять capability в `session/list`.

### REV-10. `HostLogger._dispatch`: условие `!identical(_sinks.first, sink)` после удаления приёмника всегда истинно (P3)

Источник: [#473](https://github.com/pese-git/codelab-app/pull/473). Issue: [#483](https://github.com/pese-git/codelab-app/issues/483).

**Где:**
- `apps/codelab_agent/lib/src/log/host_logger.dart:86`

**Факт:**
- Сбойный приёмник сначала удаляется из `_sinks`, поэтому `_sinks.first` уже не может быть им: проверка ничего не отсекает.

**Почему важно:** Вероятно, задумывалось не сообщать о сбое в тот же приёмник или не уходить в рекурсию; сейчас логика не делает того, что обещает.

**Что сделать:**
- Уточнить замысел и исправить условие; тест со сбойным приёмником.

### REV-11. `codelab profiles add|remove` на битом `profiles.json` падают с `FormatException` (код 255) вместо кода 64 (P2)

Источник: [#475](https://github.com/pese-git/codelab-app/pull/475). Issue: [#484](https://github.com/pese-git/codelab-app/issues/484).

**Где:**
- `apps/codelab_cli/lib/src/profiles/profiles_command.dart`

**Факт:**
- При испорченном `profiles.json` команды завершаются необработанным `FormatException`, код выхода 255.

**Почему важно:** Пользователь видит стек вместо понятной ошибки; скрипты получают не тот код выхода.

**Что сделать:**
- Ловить ошибку разбора, печатать понятное сообщение и выходить с кодом 64; тест.

### REV-12. `fs/read_text_file`/`fs/write_text_file` с относительным `path` отвечают `-32603` вместо `-32602` (P2)

Источник: [#475](https://github.com/pese-git/codelab-app/pull/475). Issue: [#485](https://github.com/pese-git/codelab-app/issues/485).

**Где:**
- обработчики `fs/*` клиента (`codelab_client_acp`)

**Факт:**
- Относительный `path` — ошибка параметров, но клиент отвечает `-32603 Internal error`.

**Почему важно:** Неверный код ошибки JSON-RPC вводит агента в заблуждение; ошибка параметров — `-32602`.

**Что сделать:**
- Отвечать `-32602 Invalid params`; golden-фикстура или тест.
- Связано с сессией канонизации symlink для `fs/*` и `terminal/*`.

### REV-13. `send` из обработчика `SessionHandle.view` теряет промпты, из `promptOutcomes` — обгоняет очередь (P2)

Источник: [#475](https://github.com/pese-git/codelab-app/pull/475). Issue: [#486](https://github.com/pese-git/codelab-app/issues/486).

**Где:**
- `packages/dart/codelab_client_core/` (сессии, очередь промптов)

**Факт:**
- Вызов `send` из обработчика `SessionHandle.view` теряет промпты.
- Вызов `send` из обработчика `promptOutcomes` обгоняет очередь.

**Почему важно:** Корректность состояния (`AGENTS.md` §2, приоритет 4; §9 — реентерабельность подписчиков).

**Что сделать:**
- Определить семантику реентерабельного `send` и закрепить её в спеке; тесты на оба случая.

### REV-14. `inlineAgentProfile` цитирует невалидный `ws://…` целиком в stderr (P2)

Источник: [#475](https://github.com/pese-git/codelab-app/pull/475). Issue: [#487](https://github.com/pese-git/codelab-app/issues/487).

**Где:**
- `apps/codelab_cli/lib/src/profiles/profile_arg.dart`
- `apps/codelab_cli/lib/src/profiles/profiles_command.dart`

**Факт:**
- Невалидный адрес агента из аргумента печатается в stderr целиком.

**Почему важно:** Адрес может содержать учётные данные или токен (userinfo, query) — они попадут в вывод и логи (`AGENTS.md` §10, §16).

**Что сделать:**
- Маскировать адрес в сообщении (как `mask_url` в ядре); тест.

### REV-15. `codelab_ui`: неиспользуемая зависимость `flutter_bloc`, тест превью покрывает не всё, `gen-l10n` падает в свежем checkout (P3)

Источник: [#474](https://github.com/pese-git/codelab-app/pull/474). Issue: [#488](https://github.com/pese-git/codelab-app/issues/488).

**Где:**
- `packages/flutter/codelab_ui/pubspec.yaml`
- `packages/flutter/codelab_ui/test/codelab_previews_test.dart`
- `packages/flutter/codelab_ui/l10n.yaml`

**Факт:**
- `flutter_bloc` объявлен в `pubspec.yaml` кита, но не импортируется.
- Тест превью не вызывает 8 из 56 превью.
- `gen-l10n` в свежем checkout падает без каталога `build/` (`untranslated-messages-file`).

**Почему важно:** Лишняя зависимость противоречит правилу «никакой логики в ките»; непокрытые превью ломаются незаметно; свежий checkout не собирается без ручного шага.

**Что сделать:**
- Убрать `flutter_bloc`.
- Покрыть все превью.
- Создавать каталог или сменить путь `untranslated-messages-file`.

### REV-16. Устаревшие `AGENTS.md`, архитектурные документы и комментарии кода (P3)

Источник: [#473](https://github.com/pese-git/codelab-app/pull/473), [#474](https://github.com/pese-git/codelab-app/pull/474), [#475](https://github.com/pese-git/codelab-app/pull/475). Issue: [#489](https://github.com/pese-git/codelab-app/issues/489).

**Где:**
- корневой `AGENTS.md` §5 (`codelab_setup`)
- `docs/architecture/state-management.md` §11, `layers-and-dependencies.md` §12
- `apps/codelab_desktop/AGENTS.md`, `packages/flutter/codelab_ui/AGENTS.md` §1
- `packages/dart/codelab_agent_io/README.md`, `AGENTS.md`; `home/config.yaml`
- комментарии: `codelab_setup/lib/io.dart`, `test/provider_setup_error_code_test.dart`, `CodeLabShellParts` в `shell_cubit.dart`, `fs_access.dart`/`terminal_access.dart`, `replCommands`, «красные тесты» в заголовках тестов `codelab_client_core`

**Факт:**
- Корневой §5 описывает `codelab_setup` только как «реэкспорт и `config`».
- `state-management.md` §11 и `layers-and-dependencies.md` §12 расходятся с кодом.
- `AGENTS.md` desktop: в списке `ApprovalShortcutSkipReason` нет `palette_open` и `root_dialog`; тексты исхода лежат в `application/`, а не в presentation.
- `AGENTS.md` кита §1 утверждает, что правил сторожа на `codelab_ui/lib` нет — они есть.
- `codelab_agent_io`: README и `AGENTS.md` называют зависимость `path`, которой нет; `home/config.yaml` не используется.
- Doc-комментарий `CodeLabShellParts` говорит о пяти частях, их шесть.

**Почему важно:** Устаревший комментарий или правило — дефект (`AGENTS.md` §15); агенты читают `AGENTS.md` как обязательные правила.

**Что сделать:**
- Обновить перечисленные документы и комментарии; `docs/architecture/` — через `codelab-architect`.

### REV-17. Стандарт `codelab-docs` §7 запрещает снимки хода агента, хотя их можно честно снять на сценарной модели (P3)

Источник: [#475](https://github.com/pese-git/codelab-app/pull/475). Issue: [#490](https://github.com/pese-git/codelab-app/issues/490).

**Где:**
- `.claude/skills/codelab-docs/SKILL.md` §7, «Ход агента»

**Факт:**
- Стандарт требует маркер вместо снимка хода. Руководства CLI и ядра уже содержат реальные снимки хода, снятые на сценарной модели (`--llm-script`, `ScriptedStreamFunction`).

**Почему важно:** Стандарт расходится с практикой и с возможностями кода.

**Что сделать:**
- Описать в §7 допустимый способ снять ход на сценарной модели.

### REV-18. Ядро агента: объявленное, но не подключённое (steering, `loop.*`, fallback, `grantForTurn`, `ToolTier.network`, Gemini) (P3)

Источник: [#471](https://github.com/pese-git/codelab-app/pull/471). Issue: [#491](https://github.com/pese-git/codelab-app/issues/491).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/loop/`, `runtime/agent_runtime.dart`
- `lib/src/config/settings_registry.dart` (`applied: false`)
- `lib/src/llm/provider_factory.dart`, `lib/src/llm/errors.dart`
- `lib/src/permissions/`, `lib/src/tools/agent_tool.dart`

**Факт:**
- `Agent.steer`, `followUp`, хуки `transformContext` и `beforeFinalResponse` есть в цикле, но рантайм их не подключает.
- Ключи `loop.empty_response_retries`, `loop.misuse.*`, `loop.final_response`, `fallback` объявлены с `applied: false`.
- `withFallback` вызывается с цепочкой из одной модели; `AgentErrorClass.fallback` и `AgentError.retrying` нигде не создаются.
- `grantForTurn` вызывается только из тестов; `ToolTier.network` не использует ни один инструмент.
- `ProviderApi.gemini` объявлен, адаптера нет.

**Почему важно:** Мёртвый или наполовину подключённый код вводит в заблуждение и пользователя (ключи конфигурации), и разработчика. Всё это описано в руководстве ядра как «не реализовано».

**Что сделать:**
- По каждому пункту решить: подключить (OpenSpec change) или убрать.

### REV-19. `compaction.keep_recent_user_turns: 0` (или отрицательное) роняет сжатие с `StateError`; при аварийном сжатии падает весь ход (P2)

Источник: раздел алгоритмов руководства ядра, проверено по коду. Issue: [#493](https://github.com/pese-git/codelab-app/issues/493).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/compaction/cut_point.dart` (`findCutPoint`, шаг 5)
- `packages/dart/codelab_agent_core/lib/src/config/resolve.dart` (проверка ключей `compaction.*`)
- `packages/dart/codelab_agent_core/lib/src/config/settings_registry.dart` (дескриптор ключа без `min`)

**Факт:**
- При `keepRecentUserTurns == 0` выражение `userTurns.skip(userTurns.length)` пусто, и `lastUsers.first` бросает `StateError: No element`. Отрицательное значение ведёт к тому же. Воспроизведено временным тестом на `findCutPoint`.
- У ключа нет проверки минимума: `resolve.dart` проверяет `> 0` только у `reserve_tokens`, `keep_recent_tokens` и `context_window_cap`; у дескриптора нет `min`.
- Последствия: после хода — `compaction.failed` и `AgentError(compaction)`; при аварийном сжатии (`preflight`/`overflow`) `_compactEmergency` ловит только `CancelledException`, ход завершается `AgentError(hook)` и `TurnEnded(failed)`, по ACP — `-32603`; `/compact` — `command.builtin.failed`.

**Почему важно:** Одно значение в конфигурации ломает сжатие, а при переполнении окна — каждый ход сессии.

**Что сделать:**
- Проверять ключ при разборе конфигурации (`min: 1` и ошибка значения) — красный тест на разбор.
- Сделать `findCutPoint` устойчивым к пустому хвосту — красный тест.

### REV-20. Рантайм пишет причину пропуска MCP в лог по-русски («сервис MCP не передан») (P3)

Источник: раздел алгоритмов руководства ядра, проверено по коду. Issue: [#494](https://github.com/pese-git/codelab-app/issues/494).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/runtime/agent_runtime.dart` (`_planMcp`, `skipped(server, …)`)

**Факт:**
- Причина пропуска сервера MCP передаётся в лог русским текстом.

**Почему важно:** `AGENTS.md` §15: сообщения логов и ошибок пишутся на английском; лог читают инструменты и пользователи без русского.

**Что сделать:**
- Заменить текст на английский; проверить тест, который его фиксирует.

### REV-21. Серверы MCP с именами вроде `my.srv` и `my_srv` получают общий префикс инструментов; у агента с ограниченным набором `toolCount` считается суммой (P3)

Источник: раздел алгоритмов руководства ядра, проверено по коду. Issue: [#495](https://github.com/pese-git/codelab-app/issues/495).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/runtime/agent_runtime.dart` (сборка `mcpServers` для промпта, фильтр по `mcpServerPrefix`)
- `mcpServerPrefix`/`mcpToolName` (санитизация имени сервера)

**Факт:**
- Имена серверов приводятся к одному префиксу `mcp__my_srv__` (проверено прогоном с фейковым MCP-сервером).
- Если у агента задан набор `tools` или это субагент, `toolCount` сервера считается по префиксу, поэтому каждый из двух серверов получает сумму инструментов обоих.

**Почему важно:** Секция MCP системного промпта сообщает модели неверное число инструментов; префикс не идентифицирует сервер однозначно.

**Что сделать:**
- Считать инструменты по серверу-владельцу, а не по префиксу, или запретить имена серверов, совпадающие после санитизации (ошибка конфигурации).
- Тест на два таких сервера.

### REV-22. Проверка отмены перед стартом хода потомка ничего не делает, комментарий в коде утверждает обратное (P3)

Источник: раздел алгоритмов руководства ядра (`subagents.md`), проверено по коду. Issue: [#497](https://github.com/pese-git/codelab-app/issues/497).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/subagents/subagent_manager.dart` (запуск хода потомка, `if (handle.source.isCancelled) child.agent.abort(...)`)
- `packages/dart/codelab_agent_core/lib/src/loop/agent.dart` (`Agent.abort` → `_turn?.cancel`)

**Факт:**
- До `prompt` у `Agent` нет хода, поэтому `abort` — пустая операция: проверка `isCancelled` перед `prompt` ничего не отменяет.
- Отмену на деле доставляет `onCancel.then(abort)`: его колбэк выполняется микрозадачей после того, как `prompt` выставил `_turn`.
- Комментарий над проверкой («abort до `prompt` не подействует, поэтому проверка здесь») описывает обратное тому, что происходит.

**Почему важно:** Мёртвая ветка и неверный комментарий вводят в заблуждение (`AGENTS.md` §15: устаревший комментарий — дефект) и маскируют, на чём держится отмена потомка (`AGENTS.md` §9, §12).

**Что сделать:**
- Убрать проверку или передавать уже отменённый токен в ход потомка так, чтобы отмена срабатывала без опоры на порядок микрозадач.
- Исправить комментарий; тест на отмену между `SubagentStarted` и началом хода.

### REV-23. Строка инструмента и блок одобрения показывают поля без маскирования секретов (P2)

Источник: документация механизма маскирования (`codelab_agent_core/doc/algorithms/redaction.md`, `codelab_client_acp/doc/redaction.md`), подтверждено ревью безопасности. Issue: [#499](https://github.com/pese-git/codelab-app/issues/499).

**Где:**
- `packages/dart/codelab_client_core/lib/src/transcript/tool_row.dart` (`ToolRowFormatter`: `_labelOf`, `_firstLine`, `summary`, `summaryShort`)
- `packages/dart/codelab_client_core/lib/src/transcript/transcript_projector.dart` (`_command`)
- `apps/codelab_desktop/lib/features/workbench/application/ui_mappers.dart`
- `apps/codelab_cli/lib/src/repl/approval_prompt.dart` (`_command()`)

**Факт:**
- Метка вызова вида `other` — сырой `title` от агента; `secondary` — сырая первая строка вывода упавшего вызова (её показывает app); `summary` и `summaryShort` не проходят `SecretRedactor`.
- Команда в блоке одобрения не маскируется ни в app, ни в REPL.
- CLI `toolRow` и деталь `fetch` с учётными данными в адресе закрывают открытые PR #453 (`redact-tool-row-text`) и #451 (`strip-fetch-url-userinfo`); перечисленные здесь поля в них не входят — сверить при слиянии.

**Почему важно:** Агент — недоверенный источник текста: токен в аргументах команды или в тексте ошибки инструмента попадает на экран и в снимки экрана (`approval-safety`, «Редактирование секретов»; `AGENTS.md` §10, §16).

**Что сделать:**
- Пропустить эти поля через `SecretRedactor` в `codelab_client_core`, а не в каждом клиенте.
- Красные тесты на каждое поле.

### REV-24. `describeHttpError` усекает тело ошибки до вычистки секретов: на границе остаётся начало ключа (P2)

Источник: документация механизма маскирования (`codelab_agent_core/doc/algorithms/redaction.md`, `codelab_client_acp/doc/redaction.md`), подтверждено ревью безопасности. Issue: [#500](https://github.com/pese-git/codelab-app/issues/500).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/llm/providers/http_support.dart` (`describeHttpError`, `maxErrorBodyLength = 2000`, `redactSecrets`)

**Факт:**
- Тело ошибки провайдера сначала усекается до 2000 символов, затем `redactSecrets` ищет известные значения секретов. Ключ, разрезанный границей, уже не совпадает целиком и остаётся префиксом (воспроизведено: текст кончается на `sk-test-a…`).

**Почему важно:** Префикс ключа — частичная утечка секрета в лог, диагностику и ошибку хода (`agent-secrets`, «Сырое значение в теле ошибки»).

**Что сделать:**
- Вычищать секреты до усечения или усекать с запасом длины самого длинного секрета.
- Красный тест с ключом на границе 2000 символов.

### REV-25. `codelab-agent` пишет в журнал полный текст исключений и стек: ядро передаёт в `error:` сырой объект (P2)

Источник: документация механизма маскирования (`codelab_agent_core/doc/algorithms/redaction.md`, `codelab_client_acp/doc/redaction.md`), подтверждено ревью безопасности. Issue: [#501](https://github.com/pese-git/codelab-app/issues/501).

**Где:**
- `apps/codelab_agent/lib/src/log/host_logger.dart` (`error?.toString()` и стек)
- `packages/dart/codelab_agent_core/lib/src/tools/executor.dart` (`tool.present.error`, `tool.validate.error`)
- `packages/dart/codelab_agent_core/lib/src/runtime/agent_runtime.dart` (`mcp.server.failed`)
- `packages/dart/codelab_agent_core/lib/src/subagents/subagent_manager.dart` (три места)
- `packages/dart/codelab_agent_core/lib/src/tools/tasks/task_list.dart`

**Факт:**
- Логгер ядра ничего не маскирует; правило «вместо текста исключения пишется тип» держится дисциплиной вызывающего кода.
- Перечисленные места передают в `error:` сам объект исключения; `HostLogger` пишет его `toString()` и стек в файл и stderr.

**Почему важно:** Текст исключения может содержать аргументы инструмента, адреса и заголовки MCP, ответы провайдеров — секреты попадут в журнал процесса (`structured-logging`, «Маскирование секретов в structured-выводе»).

**Что сделать:**
- Передавать тип ошибки и безопасный код вместо объекта или маскировать `error` в `HostLogger`.
- Сторож или тест, запрещающий сырой объект в `error:` на уровнях выше `debug`.

### REV-26. `config get` показывает литерал без известного формата рядом со ссылкой на секрет под секретным именем (P3)

Источник: документация механизма маскирования (`codelab_agent_core/doc/algorithms/redaction.md`, `codelab_client_acp/doc/redaction.md`), подтверждено ревью безопасности. Issue: [#502](https://github.com/pese-git/codelab-app/issues/502).

**Где:**
- `packages/dart/codelab_agent_io/lib/src/cli/config_output.dart`
- `packages/dart/codelab_agent_core/lib/src/config/inline_secrets.dart`, `secret_references.dart`

**Факт:**
- Значение `headers.Authorization` вида `mypassword123 ${X}` или `Basic dXNlcjpwYXNzd29yZA== ${X}` выводится как есть: шаблоны известных форматов его не узнают, а наличие ссылки делает значение «не литералом» (подтверждено тестом).

**Почему важно:** Под секретным именем литерал рядом со ссылкой — почти всегда учётные данные; вывод `config get` копируют в чаты и issues.

**Что сделать:**
- Под секретным именем скрывать литеральную часть значения целиком, оставляя только ссылки.
- Тест на оба примера.

### REV-27. Ложные срабатывания `SecretRedactor`: подстрока `pass` и слова `Token`, `Basic`, `Digest` в обычном тексте (P3)

Источник: документация механизма маскирования (`codelab_agent_core/doc/algorithms/redaction.md`, `codelab_client_acp/doc/redaction.md`), подтверждено ревью безопасности. Issue: [#503](https://github.com/pese-git/codelab-app/issues/503).

**Где:**
- `packages/dart/codelab_client_acp/lib/src/domain/secret_redaction.dart` (`_sensitiveKeyPattern`, `_authorizationPattern`)

**Факт:**
- Ключи `passport`, `bypass` и текст `passport: X123`, `compass=north` скрываются (подстрока `pass`).
- `Token of appreciation` → `Token <redacted> appreciation`; `Basic auth required` → `Basic <redacted> required` (у правила нет быстрого пути и контекста).

**Почему важно:** Ложные срабатывания портят диагностику и приучают не доверять маскированию; исправлять нужно без ослабления правил для настоящих секретов.

**Что сделать:**
- Сузить правила: границы слова для `pass`, форма значения после схемы авторизации.
- Тесты на ложные и истинные случаи; изменение правил — по дельте `approval-safety`.

### REV-28. Мелкие расхождения маскирования: пары `{name, value}` на верхнем уровне, экранирование ссылок, ключи `redact.*` без эффекта (P3)

Источник: документация механизма маскирования (`codelab_agent_core/doc/algorithms/redaction.md`, `codelab_client_acp/doc/redaction.md`), подтверждено ревью безопасности. Issue: [#504](https://github.com/pese-git/codelab-app/issues/504).

**Где:**
- `packages/dart/codelab_client_acp/lib/src/domain/secret_redaction.dart` (`redactMap`)
- `packages/dart/codelab_agent_core/lib/src/config/secret_references.dart` (`hasSecretReference`, `secretReferencesIn`)
- `packages/dart/codelab_agent_core/lib/src/config/schema.dart`, `redact_settings.dart`

**Факт:**
- `redactMap` верхнего уровня не применяет правило пары `{name, value}`, вложенные пары маскируются.
- Для экранированной ссылки `$${secret:x}` `hasSecretReference` даёт `true`, а `secretReferencesIn` — пустой список.
- Ключи `redact.*` читаются, но объявлены с `applied: false`: универсального редактора на стороне агента нет.

**Почему важно:** Расхождения между соседними функциями дают непредсказуемое поведение; объявленные ключи безопасности без эффекта вводят пользователя в заблуждение.

**Что сделать:**
- Выровнять `redactMap` и разбор ссылок, тесты.
- Решить судьбу `redact.*`: реализовать (OpenSpec change) или убрать из схемы.

Связано: утечка значения `--agent` с `ws://` в stderr уже заведена как REV-14 ([#487](https://github.com/pese-git/codelab-app/issues/487)).

### REV-29. Клиент передаёт внешнему агенту и его командам `terminal/create` всё окружение, включая `CODELAB_SECRET_*` и `*_API_KEY` (P2)

Источник: документация механизма хранения секретов (`codelab_agent_core/doc/algorithms/secrets.md`), подтверждено ревью безопасности. Issue: [#506](https://github.com/pese-git/codelab-app/issues/506).

**Где:**
- `packages/dart/codelab_acp_transports/lib/src/io/stdio_acp_transport.dart` (запуск процесса агента)
- `packages/dart/codelab_client_io/lib/src/platform/terminal_process_runner.dart` (процессы `terminal/create`)

**Факт:**
- Процесс внешнего агента и процессы его команд `terminal/create` получают полное окружение клиента.
- На стороне агента окружение дочерних процессов режется allowlist (`host_variables.dart`, `stdio_process_transport.dart`, `local_execution_env.dart`, `secret_process_runner.dart`), на стороне клиента — нет.

**Почему важно:** Внешний агент — недоверенная сторона: он и любая команда, которую он запустит через клиента, видят все секреты пользователя (`AGENTS.md` §10: secrets не должны утекать; приоритет 1 — безопасность).

**Что сделать:**
- Архитектурное решение: allowlist окружения для процесса агента и `terminal/create` или как минимум снятие `CODELAB_SECRET_*` и `*_API_KEY` (OpenSpec change: меняет наблюдаемое поведение для внешних агентов).
- Красные тесты на оба пути.

### REV-30. Токен, вставленный в `${secret:…}` вместо имени, показывается в баннере desktop после удаления MCP-сервера (P2)

Источник: документация механизма хранения секретов (`codelab_agent_core/doc/algorithms/secrets.md`), подтверждено ревью безопасности. Issue: [#507](https://github.com/pese-git/codelab-app/issues/507).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/config/secret_references.dart` (`secretReferencesIn`)
- `packages/dart/codelab_setup/lib/src/mcp/mcp_secret_cleanup.dart` (`referencedSecrets`)
- `packages/dart/codelab_setup/lib/src/mcp/mcp_server_remover.dart`
- `apps/codelab_desktop/lib/features/settings/presentation/mcp_texts.dart` (`mcpSecretKept(name)`)

**Факт:**
- `secretReferencesIn('${secret:ghp_…}')` возвращает сам токен как имя ссылки (вопреки doc-комментарию); для `${ghp_…}` без `secret:` — пустой список. Подтверждено тестом.
- Очистка секретов при удалении MCP-сервера берёт эти «имена», кладёт их в итог как `kept`, а desktop показывает их в баннере. Удаления не происходит (фильтр `inPageNamespace`).

**Почему важно:** Токен, ошибочно вставленный пользователем, выводится на экран открытым текстом.

**Что сделать:**
- Не возвращать в `secretReferencesIn` ссылки, которые выглядят как токен (`UnusableSecretReference` / `literalSecretTag`), либо фильтровать их в cleanup.
- Тест на цепочку до текста баннера.

### REV-31. Токен профиля WebSocket: `toString` конфигурации печатает токен, `ws://` на удалённый адрес не блокируется при открытии (P3)

Источник: документация механизма хранения секретов (`codelab_agent_core/doc/algorithms/secrets.md`), подтверждено ревью безопасности. Issue: [#508](https://github.com/pese-git/codelab-app/issues/508).

**Где:**
- `packages/dart/codelab_acp_transports/lib/src/transport_configs.dart` (freezed `WebSocketAcpTransportConfig`, сгенерированный `toString`)
- `packages/dart/codelab_client_core/lib/src/connection/transport_resolver.dart`
- `packages/dart/codelab_client_core/lib/src/connection/profile_draft.dart` (`plaintextToRemote`)

**Факт:**
- Сгенерированный `toString` `WebSocketAcpTransportConfig` печатает `token: $token` открытым текстом. Мест, где объект сейчас логируется, не найдено — риск скрытый.
- Токен уходит по `ws://` без TLS на адрес не этой машины: форма профиля только предупреждает (`plaintextToRemote`), открытие транспорта ничего не проверяет.

**Почему важно:** Первое — утечка при любом будущем `log(config)`; второе — передача учётных данных по открытому каналу.

**Что сделать:**
- Переопределить `toString` без токена (или `@JsonKey`-подобная маскировка), тест.
- Решить политику для `ws://` на удалённый хост с токеном: отказ или явное подтверждение.

### REV-32. Хранилище секретов: дублированные тексты проблем `secrets.backend`, лог отказа пишет только первую причину, `_verifyFinal` удаляет весь файл (P3)

Источник: документация механизма хранения секретов (`codelab_agent_core/doc/algorithms/secrets.md`), подтверждено ревью безопасности. Issue: [#509](https://github.com/pese-git/codelab-app/issues/509).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/config/resolve.dart` (`_secretsBackend`)
- `packages/dart/codelab_agent_io/lib/src/secrets/secrets_backend_problem.dart`
- `packages/dart/codelab_agent_io/lib/src/secrets/file_secret_store.dart` (`_refusedPaths`, `_verifyFinal`)

**Факт:**
- Тексты проблем `secrets.backend` заданы в двух местах; сейчас совпадают, но общего источника нет, а спека `agent-secrets` требует одну проверку.
- `_refusedPaths` пишет одну запись лога на путь за процесс: новая причина отказа на том же пути в лог не попадает (`AGENTS.md` §16).
- `_verifyFinal` удаляет весь `secrets.yaml`, если права расширили после `rename`. Так требует спека, но это потеря всех секретов файла; сработать может только при одновременном `chmod` тем же пользователем — стоит обсудить.

**Почему важно:** Расхождение текстов при следующей правке, потеря диагностики и неожиданная потеря данных.

**Что сделать:**
- Один источник текстов проблем.
- Логировать смену причины отказа.
- Обсудить поведение `_verifyFinal` (изменение — через спеку).

### REV-33. Требует воспроизведения: после замены только ключа в мастере провайдера встроенный агент может ходить со старым ключом до перезапуска (P3)

Источник: документация механизма хранения секретов (`codelab_agent_core/doc/algorithms/secrets.md`), подтверждено ревью безопасности. Issue: [#510](https://github.com/pese-git/codelab-app/issues/510).

**Где:**
- `packages/dart/codelab_agent_io/lib/src/secrets/secret_admin.dart` (`SecretAdmin.store` не сбрасывает кэш резолвера)
- `packages/dart/codelab_embedded/lib/src/io/local_opener.dart` (наблюдатель перезагрузки)
- `ConfigWriter.apply` в `codelab_agent_io`

**Факт:**
- `SecretAdmin.store` не сбрасывает кэш `SecretResolver` (так записано в docstring); сброс делает перезагрузка конфигурации.
- Если мастер заменил только ключ, а запись конфигурации оказалась пустой, перезагрузки может не быть — тогда встроенный агент держит старое значение и получает 401. По коду не доказано: не проверено, что делает `ConfigWriter.apply` при пустом наборе правок и срабатывает ли наблюдатель.

**Почему важно:** Пользователь исправил ключ, а агент продолжает падать с 401 до перезапуска.

**Что сделать:**
- Воспроизвести тестом встроенного агента.
- Если подтвердится — сбрасывать кэш после `SecretAdmin.store` или гарантировать перезагрузку.

### REV-34. Два одновременных `session/load` закрытой сессии открывают двух писателей над одним журналом (P2)

Источник: документация механизма хранения и управления сессиями (`codelab_agent_core/doc/algorithms/sessions.md`, `codelab_client_core/doc/session-management.md`), подтверждено ревью кода. Issue: [#513](https://github.com/pese-git/codelab-app/issues/513).

**Где:**
- `packages/dart/codelab_agent_acp/lib/src/agent_server.dart` (обработчик `session/load`, ветка без открытой сессии)

**Факт:**
- Если сессии нет в памяти, обработчик ждёт `_server._runtime.loadSession(...)` и только потом кладёт мост в `_server._sessions[id]`. Маршрутизатор выполняет запросы параллельно, поэтому второй `session/load` того же id в это окно тоже открывает сессию.
- Получаются два `_Session` над одним журналом с разными листьями: записи расходятся на боковые ветки; первая сессия вытесняется из `_server._sessions`, её MCP-серверы и дескриптор журнала утекают.

**Почему важно:** Целостность пользовательских данных (`AGENTS.md` §2, приоритет 3) и явный владелец долгоживущих ресурсов (§9).

**Что сделать:**
- Резервировать id до `await` (например, `Future` открытия в карте), второй запрос ждёт его или получает `sessionBusy`.
- Красный тест на два параллельных `session/load`.

### REV-35. Мост сессии не проверяет владельца: любое соединение может слать `session/prompt`, `set_mode`, `cancel` в чужую сессию (P2)

Источник: документация механизма хранения и управления сессиями (`codelab_agent_core/doc/algorithms/sessions.md`, `codelab_client_core/doc/session-management.md`), подтверждено ревью кода. Issue: [#514](https://github.com/pese-git/codelab-app/issues/514).

**Где:**
- `packages/dart/codelab_agent_acp/lib/src/agent_server.dart` (`_bridge(id)`, обработчики `session/prompt`, `set_mode`, `set_config_option`, `cancel`)

**Факт:**
- `_bridge` ищет сессию только по id; владелец (соединение, которое её открыло или загрузило) не сверяется.
- В `ws`-режиме несколько соединений: одно может управлять сессией другого, а запросы разрешений при этом уходят владельцу.

**Почему важно:** Изоляция сессий между клиентами и связь запроса разрешения с правильной сессией (`AGENTS.md` §10). Требует сверки со спекой: допускает ли ACP управление сессией без `session/load` в этом соединении.

**Что сделать:**
- Сверить с `docs/protocols/acp/` и `openspec/specs/agent-acp-server`.
- Отвечать ошибкой на запросы к сессии, которой соединение не владеет; тест.

### REV-36. Нет блокировки писателя сессии между процессами; ключи `sessions.lease` и `sessions.read_only` объявлены без эффекта (P2)

Источник: документация механизма хранения и управления сессиями (`codelab_agent_core/doc/algorithms/sessions.md`, `codelab_client_core/doc/session-management.md`), подтверждено ревью кода. Issue: [#515](https://github.com/pese-git/codelab-app/issues/515).

**Где:**
- `packages/dart/codelab_agent_io/lib/src/session/jsonl_session_store.dart`
- `packages/dart/codelab_agent_core/lib/src/config/schema.dart` (`sessions.lease`, `sessions.read_only`, `applied: false`)

**Факт:**
- Документация заявляет «одна сессия — один процесс-писатель», но ни блокировки, ни проверки в коде нет: два процесса (`codelab` и `codelab-agent serve` над одним `CODELAB_HOME`) могут писать в один журнал.
- Ключи `sessions.lease`, `sessions.read_only` (и `sessions.window`, `segments`, `search`, `branch_summary`) принимаются схемой с `applied: false`.

**Почему важно:** Записи двух процессов перемешиваются в одном журнале, ремонт при открытии может переписать чужие строки.

**Что сделать:**
- Решить механизм аренды (lease-файл, advisory lock) — OpenSpec change.
- До реализации — явно описать ограничение пользователю.

### REV-37. `/resume` в REPL возвращает открытую `detached`-сессию без `session/load`: промпты в неё падают (P3)

Источник: документация механизма хранения и управления сессиями (`codelab_agent_core/doc/algorithms/sessions.md`, `codelab_client_core/doc/session-management.md`), подтверждено ревью кода. Issue: [#516](https://github.com/pese-git/codelab-app/issues/516).

**Где:**
- `apps/codelab_cli/lib/src/repl/commands/resume.dart`

**Факт:**
- Уже открытую сессию (в том числе `detached`) `/resume` берёт из памяти без `session/load`; она остаётся `detached`, `send` даёт `PromptFailed`. `_reopenIfDetached` спасает только активную сессию.
- Спека `codelab-cli` («Сессии в REPL») говорит, что `/resume` загружает сессию.

**Почему важно:** Пользователь «возобновил» сессию, а работать с ней нельзя; поведение расходится со спекой.

**Что сделать:**
- Для `detached` вызывать `loadSession`; тест.

### REV-38. Журнал сессии: заголовок-сирота при сбое создания, режим не пишется при создании, `set_mode` после сбоя записи, каталог без `fsync` (P3)

Источник: документация механизма хранения и управления сессиями (`codelab_agent_core/doc/algorithms/sessions.md`, `codelab_client_core/doc/session-management.md`), подтверждено ревью кода. Issue: [#517](https://github.com/pese-git/codelab-app/issues/517).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/runtime/agent_runtime.dart` (`createSession`, `_abandon`, `_open`, `_failed`)
- `packages/dart/codelab_agent_io/lib/src/session/jsonl_session_store.dart`

**Факт:**
- Если первая `model_change` не записалась или рантайм останавливают после `store.create` (`CancelledException`), журнал с одним заголовком остаётся и виден в `session/list`; `_abandon` закрывает только MCP и не вызывает `store.close(id)`.
- Режим при создании корневой сессии в журнал не пишется: пока не было `mode_change`, при загрузке режим берётся из текущей конфигурации (у дочерней сессии пишется).
- После сбоя записи `_failed` держится до `TurnStarted`: `set_mode` между ходами отвечает успехом, а `mode_change` молча не пишется.
- `fsync` идёт только по дескриптору файла; каталог после `create` и после `rename` при ремонте не синхронизируется.

**Почему важно:** Пустые сессии в списке, расхождение режима после перезапуска, молчаливая потеря изменения, новый файл может не пережить отключение питания.

**Что сделать:**
- Удалять или помечать журнал при неудачном создании и закрывать дескриптор.
- Писать начальный `mode_change`.
- Отвечать ошибкой `set_mode` при `_failed`.
- Синхронизировать каталог после `create` и `rename`.
- Тесты на каждый случай.

### REV-39. `session/list` фильтрует `cwd` сравнением строк; `--continue` смотрит только первую страницу списка (P3)

Источник: документация механизма хранения и управления сессиями (`codelab_agent_core/doc/algorithms/sessions.md`, `codelab_client_core/doc/session-management.md`), подтверждено ревью кода. Issue: [#518](https://github.com/pese-git/codelab-app/issues/518).

**Где:**
- `packages/dart/codelab_agent_io/lib/src/session/jsonl_session_store.dart` (`entry.summary.cwd == cwd`)
- `apps/codelab_cli/lib/src/session_setup.dart` (`openCliSession(last: true)`)

**Факт:**
- `header.cwd` хранит строку клиента, сравнение сырое: `/a/b/` не найдёт `/a/b`, то же со ссылками и регистром.
- `--continue` выбирает из `workspace.current.sessions` (первая страница) без `loadMoreSessions`. Dart-агент сортирует от новых к старым по 50, поэтому с ним не проявляется; ACP порядок не задаёт — у внешнего агента свежая сессия может не попасть в выбор.

**Почему важно:** Пользователь не находит свою сессию по каталогу или продолжает не ту.

**Что сделать:**
- Нормализовать путь (абсолютный, без завершающего `/`, по возможности `realpath`) при записи и сравнении.
- В `--continue` дочитывать страницы или запрашивать с фильтром; тесты.

### REV-40. После ошибки записи снимок рабочего пространства не пишется повторно, пока состояние не изменится (P3)

Источник: документация механизма хранения и управления сессиями (`codelab_agent_core/doc/algorithms/sessions.md`, `codelab_client_core/doc/session-management.md`), подтверждено ревью кода. Issue: [#519](https://github.com/pese-git/codelab-app/issues/519).

**Где:**
- `packages/dart/codelab_client_core/lib/src/restore/workspace_restorer.dart` (`_drain`, `observe`, `flush`)

**Факт:**
- `_drain` присваивает `_written = next` и после ошибки `store.write`; `observe` с тем же состоянием запись пропускает, `flush` завершается как успешный. На диске остаётся старый снимок.

**Почему важно:** После перезапуска клиент восстанавливает устаревшее состояние; спека `acp-client-kit` требует здесь только диагностики, но повтор записи ожидаем.

**Что сделать:**
- Обновлять `_written` только после успешной записи; тест со сбойным хранилищем.

### REV-41. `StdioAcpTransport.send` пишет без очереди: два одновременных исходящих сообщения клиента падают с `sendFailed` (P2)

Источник: документация сторон исполнения approval, инструментов, `fs/*` и `terminal/*` (`codelab_agent_core/doc/algorithms/execution-sides.md`, `codelab_client_acp/doc/execution-on-client.md`), подтверждено ревью кода. Issue: [#521](https://github.com/pese-git/codelab-app/issues/521).

**Где:**
- `packages/dart/codelab_acp_transports/lib/src/io/stdio_acp_transport.dart` (`send`)
- `packages/dart/codelab_client_acp/lib/src/application/acp_client_application.dart` (`_sendTracedMessage`, общий `catch` ответа на запрос агента)

**Факт:**
- `send` делает `writeln` и `await flush()` без цепочки записей. Если следующий `writeln` приходит, пока предыдущий `flush` не завершён, `IOSink` бросает `StateError`, транспорт отдаёт `sendFailed`. Серверный транспорт пишет через цепочку `_writes` (`stdio_server_acp_transport.dart`), клиентский — нет, своей очереди у клиента тоже нет.
- Наблюдалось в 4 запусках из 4 при отмене `exec` против `codelab-agent serve --stdio`: ответ на `terminal/kill` и ответ на `terminal/wait_for_exit` уходят одновременно, второй падает, общий `catch` шлёт вместо него ошибку `-32603`.
- Гонка возможна у любых двух одновременных исходящих сообщений клиента, включая `session/cancel` и ответ на `session/request_permission`. Если упадёт и повторная отправка, ответ теряется; у вопроса разрешения таймаута нет. Зависнет ли агент — не проверено.

**Почему важно:** Корректность протокола ACP и состояния (`AGENTS.md` §2, приоритеты 2 и 4): потерянный ответ на запрос агента или на вопрос разрешения.

**Что сделать:**
- Сериализовать запись в `StdioAcpTransport.send` (цепочка `Future`, как в серверном транспорте).
- Красный тест: два параллельных `send` по stdio без ошибки и в порядке вызова.

### REV-42. Агент спрашивает разрешение до проверки возможностей клиента: одобренный вызов `fs`/`terminal` гарантированно падает (P3)

Источник: документация сторон исполнения approval, инструментов, `fs/*` и `terminal/*` (`codelab_agent_core/doc/algorithms/execution-sides.md`, `codelab_client_acp/doc/execution-on-client.md`), подтверждено ревью кода. Issue: [#522](https://github.com/pese-git/codelab-app/issues/522).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/runtime/agent_runtime.dart` (хук политики разрешений — первый перед исполнением)
- `packages/dart/codelab_agent_acp/lib/src/acp_client_env.dart` (`readText`, `writeText`, `exec`: проверки `fs.readTextFile`, `fs.writeTextFile`, `terminal`)

**Факт:**
- Возможности клиента (`clientCapabilities.fs`, `terminal`) проверяются только при исполнении в `AcpClientExecutionEnv`; итог — `FileErrorCode.unsupported` или `shellUnavailable`. До этого вызов уже прошёл `session/request_permission`.
- Инструменты `read`, `write`, `edit`, `exec` остаются в схеме модели, даже если клиент их не поддерживает. ACP не нарушен: запросов к клиенту без объявленной возможности агент не шлёт.

**Почему важно:** Пользователь одобряет действие, которое заведомо не выполнится; модель тратит шаги на недоступные инструменты (UX, `AGENTS.md` §2 п.7).

**Что сделать:**
- Решить: скрывать недоступные инструменты из схемы модели или проверять возможность до вопроса — OpenSpec change.
- Тест с клиентом без `fs`/`terminal`.

### REV-43. Отброшенный ответ (overflow до первого блока, повтор после ошибки спаривания) теряет usage: нарушено «usage шага — сумма всех попыток» (P2)

Источник: документация механизма подсчёта usage (`codelab_agent_core/doc/algorithms/usage.md`, `codelab_client_core/doc/usage-accounting.md`), подтверждено ревью кода. Issue: [#525](https://github.com/pese-git/codelab-app/issues/525).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/loop/agent_loop.dart` (`_request`: ветки `continue` около строк 480-493 раньше `_usage += …` около строки 171)

**Факт:**
- При `!started && overflow && _compactEmergency` и при повторе после `badRequest` с ошибкой спаривания (флаг `retried`) цикл делает `continue` до прибавления `response.usage` к usage шага. Ответ не попадает ни в транскрипт, ни в `StepEnded`/`TurnEnded`, ни в журнал usage.
- Денежный случай — тихое переполнение `length` с `output == 0` (`overflow.dart`, `silentOverflow`): блоков нет, `started == false`, а ненулевой `input` уже оплачен провайдеру. У отказа провайдера usage обычно нулевой.
- Требование `openspec/specs/agent-llm/spec.md` «Usage и стоимость»: «Usage шага SHALL быть суммой всех попыток». Решения об исключении в архивных changes нет.

**Почему важно:** Целостность учёта расходов (`AGENTS.md` §2, п. 3–4): пользователь видит меньше, чем заплатил.

**Что сделать:**
- Перед `continue` прибавлять `response.usage` к usage шага (по образцу `failedUsage` в `retry.dart`).
- Красный тест: тихий `length` с ненулевым `input` и последующее аварийное сжатие — usage шага включает отброшенный ответ.

### REV-44. Лог `usage.received` пишет триггеры `load` и `compactionDiscarded` как `other` (P3)

Источник: документация механизма подсчёта usage (`codelab_agent_core/doc/algorithms/usage.md`, `codelab_client_core/doc/usage-accounting.md`), подтверждено ревью кода. Issue: [#526](https://github.com/pese-git/codelab-app/issues/526).

**Где:**
- `packages/dart/codelab_client_acp/lib/src/application/acp_client_application.dart` (`_handleUsageNotification`, около строк 3044-3048)
- `packages/dart/codelab_client_core/lib/src/usage/usage_decoder.dart` (switch по `triggerName`)

**Факт:**
- В лог попадает только закрытый набор `{step, turn, compaction}` (D14/D22 п. 1 change `add-usage-extension`); набор старше триггеров `load` (`add-usage-ledger`) и `compactionDiscarded` (`fix-discarded-compaction-usage`), поэтому они пишутся как `other`.
- Декодер клиента превращает `compactionDiscarded` в `UsageTrigger.unknown`.

**Почему важно:** Наблюдаемость (`AGENTS.md` §16): по логу нельзя отличить снимок при загрузке и отброшенное сжатие от неизвестного триггера.

**Что сделать:**
- Расширить закрытый набор лога и `UsageTrigger` известными триггерами агента; обновить `docs/architecture/observability.md`; тесты.

### REV-45. TUI печатает команду агента (`/usage`, `/status`) в ленте дважды (P3)

Источник: документация механизма подсчёта usage (`codelab_agent_core/doc/algorithms/usage.md`, `codelab_client_core/doc/usage-accounting.md`), подтверждено ревью кода. Issue: [#527](https://github.com/pese-git/codelab-app/issues/527).

**Где:**
- `apps/codelab_cli/lib/src/tui/` (лента ввода TUI; точное место в коде не установлено)

**Факт:**
- В TUI `> /usage` и `> /status` видны в ленте два раза; обычный промпт — один раз. Дубль остаётся после следующих ходов. Проверено снимком `tmux capture-pane` после отрисовки на реальном `codelab` со сценарным агентом. В REPL дубля нет.

**Почему важно:** Лента — история диалога; дубль вводит в заблуждение и расходится с REPL.

**Что сделать:**
- Найти место двойного добавления команды в ленту; красный тест TUI на одну строку команды.

### REV-46. Файлы клиента (`profiles.json` и другие) создаются с правами по `umask`; `args` и `env` stdio-профиля с токеном видны другим локальным пользователям (P3)

Источник: документация механизма настроек клиента и агента (`codelab_agent_core/doc/algorithms/settings.md`, `codelab_client_core/doc/settings-on-client.md`), подтверждено ревью кода. Issue: [#529](https://github.com/pese-git/codelab-app/issues/529).

**Где:**
- `packages/dart/codelab_client_io/lib/src/stores/json_file.dart` (`writeBytesAtomically`: `writeAsBytes` и `rename` без `chmod`)
- `apps/codelab_cli/lib/src/home.dart` (`CodelabHome.ensureExists` — права `0700` каталогу ставит только CLI)
- `apps/codelab_cli/lib/src/profiles/` (`profile_arg.dart`, `profiles_command.dart`: значения `args` и `env` stdio-профиля хранятся как есть)

**Факт:**
- В прогоне `profiles.json` создан с правами `-rw-r--r--`. Токен WebSocket хранится ссылкой (`tokenRef`), но `args` и `env` stdio-профиля лежат открытым текстом; пользователь может положить туда токен.
- Каталогу `$CODELAB_HOME` права `0700` ставит только `CodelabHome.ensureExists` (интерактивные режимы и подкоманда `profiles` терминала); app права не ставит. Если каталог первым создал app, файл читают другие локальные пользователи.

**Почему важно:** Секреты не должны быть доступны другим пользователям машины (`AGENTS.md` §10). Уровень hardening: утечка только если пользователь сам положил токен в `args`/`env`.

**Что сделать:**
- Ставить `0600` файлам в `writeBytesAtomically` и `0700` каталогу `$CODELAB_HOME` и в app (по образцу файлового бэкенда секретов).
- Тест прав на POSIX; предупреждение в документации остаётся.

### REV-47. `config get --layer merged` не учитывает доверие к проекту: показывает «выключенный» MCP-сервер, который агент запускает (P3)

Источник: документация механизма настроек клиента и агента (`codelab_agent_core/doc/algorithms/settings.md`, `codelab_client_core/doc/settings-on-client.md`), подтверждено ревью кода. Issue: [#530](https://github.com/pese-git/codelab-app/issues/530).

**Где:**
- `packages/dart/codelab_agent_io` (подкоманда `config get`, `ConfigCommands`)
- `openspec/specs/agent-configuration/spec.md` (печать сырого значения старшего слоя; сценарий ожидает значение проекта)

**Факт:**
- Прогон: в слое `user` включён stdio-сервер `tools`, недоверенный проект пишет `mcp.servers: [{name: tools, enabled: false}]`. `config get mcp.servers --layer merged` показывает `enabled: false`, `layer: project`; `config check` сообщает, что `mcp.servers` проекта проигнорирован; `/mcp list` в `serve --stdio` показывает `tools` запущенным.
- Так же `get` показывает проектный `permissions.mode: bypass`, который доверие отбрасывает. Поведение соответствует спецификации.

**Почему важно:** Пользователь видит более строгое (или более мягкое) значение, чем действует, — ложное чувство безопасности (`AGENTS.md` §2, п. 1).

**Что сделать:**
- OpenSpec change: помечать в `get` ключи, отброшенные доверием (`ignored by trust`), или флаг с учётом доверия.
- Сценарий спецификации и тест на недоверенный слой.

### REV-48. Разрешение не перепроверяется после паузы: смена режима или `deny`, пока висит вопрос, не влияет на уже одобренный вызов (P2)

Источник: OpenSpec changes по пробелам обвязки агента (`add-final-response-guardrails`, `add-os-sandbox-decision`, ADR-0004), подтверждено ревью кода. Issue: [#533](https://github.com/pese-git/codelab-app/issues/533).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/tools/executor.dart` (`ToolCallExecutor`: между `beforeToolCall` и исполнением перепроверяется только отмена)
- `openspec/changes/add-final-response-guardrails/design.md` (Q3)

**Факт:**
- Пока вызов ждёт ответа на `session/request_permission` (или замка пути), пользователь может переключить режим на `plan`, а перезагрузка конфига — добавить правило `deny`. После одобрения вызов исполняется по решению, принятому до паузы.
- Перепроверки режима, правил и `preflight` путей перед необратимым действием нет; это вынесено из change `add-final-response-guardrails` (Q3, решение пользователя 2026-11-26) в отдельный change.

**Почему важно:** Безопасность (`AGENTS.md` §2 п. 1, §10): решение для одного состояния сессии не должно применяться к другому.

**Что сделать:**
- OpenSpec change в `agent-permissions`: перепроверка режима, правил и путей в `ToolCallExecutor` после паузы, перед исполнением.
- Красные тесты: смена режима на `plan` и новое `deny` во время вопроса.

### REV-49. Доверие к проекту не запрашивается заново при изменении проектного конфига (P3)

Источник: OpenSpec changes по пробелам обвязки агента (`add-final-response-guardrails`, `add-os-sandbox-decision`, ADR-0004), подтверждено ревью кода. Issue: [#534](https://github.com/pese-git/codelab-app/issues/534).

**Где:**
- `packages/dart/codelab_agent_core/lib/src/config/trust.dart` (`applyProjectTrust`)
- `docs/architecture/adr/0004-defer-os-sandbox-harden-workspace-boundary.md` (сценарии S8, S9)

**Факт:**
- Доверие привязано к корню проекта в `trusted_projects`, а не к содержимому `.codelab/config.yaml`. Изменённый конфиг доверенного проекта (`mcp.servers`, `providers`, `permissions`) после перезапуска применяется без вопроса.
- Сторонний агент может переписать `.codelab/config.yaml` через `fs/write_text_file` без одобрения (исключение §10); одобренная команда может переписать `$CODELAB_HOME`.

**Почему важно:** Изменение конфига доверенного проекта — тот же риск, что и первое доверие: запуск процессов MCP и ослабление прав.

**Что сделать:**
- OpenSpec change: отпечаток доверенного проектного конфига и повторный запрос доверия при его изменении (или предупреждение).

### REV-50. Allowlist окружения команд агента не содержит переменных Windows (`SystemRoot`, `PATHEXT` и др.) (P3)

Источник: OpenSpec changes по пробелам обвязки агента (`add-final-response-guardrails`, `add-os-sandbox-decision`, ADR-0004), подтверждено ревью кода. Issue: [#535](https://github.com/pese-git/codelab-app/issues/535).

**Где:**
- `packages/dart/codelab_agent_io/lib/src/env/host_variables.dart` (`hostEnvironmentAllowlist`)
- `packages/dart/codelab_agent_io/lib/src/env/local_execution_env.dart`, `packages/dart/codelab_agent_io/lib/src/mcp/stdio_process_transport.dart`

**Факт:**
- Команды `exec` и stdio-серверы MCP запускаются с `includeParentEnvironment: false` и окружением из `hostEnvironmentAllowlist`. Списка Windows-переменных там нет; без `SystemRoot`, `PATHEXT`, `ComSpec` и подобных многие программы Windows не запускаются.
- Клиентский allowlist `terminal/create` в change `add-os-sandbox-decision` этот список для Windows уже содержит; у агента — нет.

**Почему важно:** Корректность исполнения команд на Windows-целях.

**Что сделать:**
- Добавить Windows-часть в `hostEnvironmentAllowlist` (по образцу клиентского списка), сверка в `codelab_architecture_tests`; тест на Windows-окружении.

### REV-51. Команда CodeLab-агента через клиента (`terminal/create`) не получает фиксированный набор `TERM=dumb`, `PAGER=cat`, `GIT_PAGER=cat`, `GIT_TERMINAL_PROMPT=0` (P3)

Источник: OpenSpec changes по пробелам обвязки агента (`add-final-response-guardrails`, `add-os-sandbox-decision`, ADR-0004), подтверждено ревью кода. Issue: [#536](https://github.com/pese-git/codelab-app/issues/536).

**Где:**
- `packages/dart/codelab_agent_acp/lib/src/acp_client_env.dart` (`AcpClientExecutionEnv.exec`: в `env` запроса только `options.env`)
- `packages/dart/codelab_agent_io/lib/src/env/local_execution_env.dart` (фиксированный набор ENV-6)

**Факт:**
- Локально (`LocalExecutionEnv`) команда получает фиксированный набор ENV-6, через клиента — нет. Одна и та же команда (`git log`, `git push`) через `serve --stdio`/`--ws` может открыть пейджер или запросить пароль и зависнуть до таймаута.
- Решение пользователя 2026-11-26 (Q4 change `add-os-sandbox-decision`): набор добавляет агент в `env` запроса, отдельным change.

**Почему важно:** Одинаковое поведение команд независимо от стороны исполнения; зависание хода на интерактивном запросе.

**Что сделать:**
- `AcpClientExecutionEnv.exec` добавляет фиксированный набор в `env` запроса; красный тест на кадр `terminal/create`; фикстура ACP.
