# Начало работы с кодом ACP-сервера

Глава показывает, как подготовить репозиторий, прогнать тесты пакета, увидеть настоящие кадры ACP от запущенного агента без живого провайдера и включить подробный лог. В конце — карта «что изменить — куда смотреть».

ACP (Agent Client Protocol) — протокол, по которому клиент и агент обмениваются сообщениями JSON-RPC. Пакет `codelab_agent_acp` — сторона агента: он принимает запросы клиента и отправляет ему уведомления и свои запросы.

## Подготовка репозитория

Все команды Dart идут через `fvm`. Пакеты протокола и ядра используют сгенерированный код (`*.freezed.dart`, `*.g.dart`); в Git его нет. Без генерации пакет не соберётся: анализатор жалуется на `switch`, который «не покрывает» типы. Шаги генерации и сборки описаны в [запуске из исходников](../../../../docs/user/run-from-source.md#1-подготовка), коротко:

```bash
fvm dart run melos exec -c 1 --depends-on=build_runner -- "fvm dart run build_runner build --delete-conflicting-outputs"
```

Команда идёт несколько минут. Сгенерированные файлы лежат в `.gitignore`.

## Тесты пакета

Тесты запускаются в каталоге пакета. Весь набор:

```bash
cd packages/dart/codelab_agent_acp
fvm dart test
```

Набор проходит целиком: 544 теста, 5 из них пропущены. Пропущены фикстуры, у которых нет роли `agent` или которые играет не этот драйвер (подробно — [глава 4](04-testing.md#что-пропускается)). Один файл:

```bash
fvm dart test test/cancel_test.dart
```

```text
00:00 +0: loading test/cancel_test.dart
00:00 +0: cancel during the model stream answers cancelled
00:00 +1: cancel during a permission request: the call is cancelled
00:00 +2: cancel during terminal/wait_for_exit: kill, output, release
00:00 +3: cancel without a turn is logged and sends nothing
00:00 +4: session/cancel sent as a request is also answered with null
00:00 +5: All tests passed!
```

Один тест из файла — по части названия: `--name "permission request"`. Корпус golden-фикстур агента — `melos run conformance:agent` из корня репозитория (см. [главу 4](04-testing.md#conformance-на-golden-фикстурах)).

## Живой обмен кадрами без провайдера

Бинарь `codelab-agent` (`apps/codelab_agent`) подключает к этому пакету транспорт stdio. Скрытый флаг `--llm-script <файл>` подставляет вместо провайдера сценарную модель: ответы берутся из JSON-файла, сеть не нужна. Флаг нужен только тестам и разработке. Файл сценария содержит объект `llm` с шагами модели — тот же, что в golden-фикстурах ([глава ядра о тестировании](../../codelab_agent_core/doc/12-testing.md)). Запускайте агента с отдельным `CODELAB_HOME` и без ключей провайдеров в окружении (`env -u`): настоящий домашний каталог и ключи разработке не нужны.

Сервер читает по одному кадру JSON-RPC в строке из stdin и пишет ответы в stdout. Запишите три запроса в файл:

```bash
mkdir -p ~/demo/home
cat > ~/demo/in.jsonl <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{}}}
{"jsonrpc":"2.0","id":2,"method":"session/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"session/fly","params":{}}
EOF
```

Запустите агента из корня репозитория на сценарии `hello.json` из тестов агента:

```bash
env -u ANTHROPIC_API_KEY -u OPENAI_API_KEY CODELAB_HOME=~/demo/home \
  fvm dart run apps/codelab_agent/bin/codelab_agent.dart serve --stdio \
  --llm-script apps/codelab_agent/test/llm_scripts/hello.json < ~/demo/in.jsonl
```

stdin закрывается, но сервер сначала отвечает на уже принятые запросы и только потом закрывает соединение (`AcpAgentServer.serve`), поэтому все три ответа успевают прийти. Вывод этого запуска:

```text
{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"agentCapabilities":{"loadSession":false,"mcpCapabilities":{"http":true,"sse":false},"promptCapabilities":{"audio":false,"embeddedContext":true,"image":true},"sessionCapabilities":{}},"agentInfo":{"name":"codelab-agent","version":"0.1.0","title":"CodeLab Agent"},"authMethods":[]}}
{"jsonrpc":"2.0","id":2,"result":{"sessions":[]}}
{"jsonrpc":"2.0","id":3,"error":{"code":-32601,"message":"Method not found: session/fly"}}
```

Что видно:

- `loadSession` равен `false` и `sessionCapabilities` пуст: на сценарии журналы сессий лежат в памяти, а возможность `sessionPersistence` у профиля выключена ([`initialize`](01-structure.md#initialize-и-возможности-агента)).
- Блока `_meta.codelab` в ответе нет: клиент не прислал `clientCapabilities._meta.codelab`.
- Неизвестный метод получает `-32601`, а соединение живёт и отвечает на следующие кадры.

Дальше, с запросом `session/new` и ходом `session/prompt`, вручную работать неудобно: нужен клиент, который отвечает на запросы агента (`session/request_permission`, `fs/*`, `terminal/*`). Для разработки подходит маленький скрипт на Dart, который запускает агента процессом, шлёт кадры и отвечает на запросы по таблице. Примеры кадров этого руководства получены именно так (сценарии `exec` и `cancel` — модель просит выполнить `echo hi` или `sleep 30`; клиент разрешает вызов и играет терминал). Если скрипт не нужен, ту же трассу показывают golden-фикстуры, например [`tool-exec-terminal-embed.json`](../../codelab_acp_testing/fixtures/acp/tool-exec-terminal-embed.json).

## Подробный лог

Лог — события вида `имя {поля}` с уровнем. Ключи полей, уровни и маскирование описывает [глава ядра о наблюдаемости](../../codelab_agent_core/doc/10-observability-and-errors.md#журнал-диагностики). Пакет пишет события с префиксом `acp.` (полный список — [в главе 5](05-extending-and-troubleshooting.md#события-лога-пакета)) и `mcp.`. Подробный лог включает `--log-level debug`:

```bash
env -u ANTHROPIC_API_KEY CODELAB_HOME=~/demo/home \
  fvm dart run apps/codelab_agent/bin/codelab_agent.dart serve --stdio \
  --llm-script apps/codelab_agent/test/llm_scripts/hello.json \
  --log-level debug < ~/demo/in.jsonl 2>&1 >/dev/null
```

В stderr агента попадают строки лога (в stdout только протокол; строка `host.plan` и поля путей сокращены):

```text
2026-11-24T18:21:05.326409Z debug acp.extensions.negotiated {keys: []}
2026-11-24T18:21:05.342241Z info serve.stop {exit_code: 0}
```

`acp.extensions.negotiated` показывает, какие расширения `_meta.codelab` клиент согласовал; пустой список — клиент ничего не объявил. Ход с отменой, по данным такого же запуска, оставляет в логе:

```text
debug permission.asked {tool_call_id: call_1, tool: exec, tier: exec, critical: false}
info acp.cancel {session_id: <session-id>}
```

Отмена без идущего хода пишет `acp.cancel.no_turn {session_id: <session-id>}` и ничего не отправляет клиенту.

## Быстрая ориентация

| Что нужно изменить | Куда смотреть |
|---|---|
| какой обработчик отвечает на метод ACP | `_Connection._onRequest` в [`agent_server.dart`](../lib/src/agent_server.dart); [глава 1](01-structure.md#какой-обработчик-отвечает-на-метод) |
| что приходит в `initialize` | `_Connection._initialize` и `_codelabExtensions` там же |
| код и текст ошибки JSON-RPC | [`connection/acp_error.dart`](../lib/src/connection/acp_error.dart), `InboundRouter._answer` в [`connection/inbound_router.dart`](../lib/src/connection/inbound_router.dart) |
| порядок исходящих кадров | [`connection/outbound_queue.dart`](../lib/src/connection/outbound_queue.dart), `Reply.after` |
| как событие ядра становится `session/update` | `projectEvent` и `projectionTable` в [`event_projection.dart`](../lib/src/event_projection.dart) |
| итог хода, `stopReason`, ошибка хода | `turnResponse` там же |
| история при `session/load` | [`replay.dart`](../lib/src/replay.dart), `SessionBridge.replayInto` |
| ход, отмена, отсоединение, переподключение | [`session_bridge.dart`](../lib/src/session_bridge.dart) |
| режимы и опции сессии | [`config_options.dart`](../lib/src/config_options.dart), `_setConfigOption` в `agent_server.dart` |
| блоки промпта клиента | [`prompt_content.dart`](../lib/src/prompt_content.dart) |
| вопрос о разрешении | [`acp_permission_gate.dart`](../lib/src/acp_permission_gate.dart) |
| файлы и терминалы через клиента | [`acp_client_env.dart`](../lib/src/acp_client_env.dart) |
| ожидание ответа клиента, таймауты, разрыв | [`connection/client_requests.dart`](../lib/src/connection/client_requests.dart), `AcpTimeouts` |
| цепочки `toolCallId` вызовов потомков | [`subagent_chain.dart`](../lib/src/subagent_chain.dart) |
| usage: `_codelab/session/usage`, журнал | [`usage_accounting.dart`](../lib/src/usage_accounting.dart), `SessionBridge._sendUsage` |

## Смотрите также

- [Устройство пакета](01-structure.md) — следующая глава.
- [Начало работы с ядром](../../codelab_agent_core/doc/00-getting-started.md) — запуск агента без пакета ACP, журнал сессии.
- [`docs/user/run-from-source.md`](../../../../docs/user/run-from-source.md) — сборка и запуск из исходников.
