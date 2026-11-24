# Backlog: находки при написании руководств разработчика, ревью 2026-11-25

Пункты найдены при написании руководств разработчика по пакетам и приложениям монорепо. Каждое руководство сверялось с кодом ревьюером `architecture-reviewer`. Источники:
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
