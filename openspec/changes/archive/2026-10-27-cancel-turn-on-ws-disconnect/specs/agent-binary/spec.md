## MODIFIED Requirements

### Requirement: Команда serve
Бинарь `codelab-agent` (`apps/codelab_agent`) SHALL обслуживать ACP-клиентов командой `serve` ровно с одним транспортом: `--stdio` или `--ws`. Ядро SHALL собираться только через `buildAgentCore` в профиле `agent-serve` (HOST-6), сервер — `AcpAgentServer` пакета `codelab_agent_acp`.

- `serve --stdio`: одно соединение через `StdioServerAcpTransport` на stdin/stdout процесса; сервер получает `localListing` на `LocalExecutionEnv`, поэтому `ls` и `search` включены; `detachGrace` — ноль (отсоединение stdio — конец процесса).
- `serve --ws [--host <host>] [--port <port>] [--token-env <VAR>]`: по умолчанию `127.0.0.1:8765` и `CODELAB_AGENT_TOKEN`; каждое принятое подключение — отдельное соединение того же сервера через `WebSocketServerAcpTransport`; capability `fileListing` выключена с причиной, `localListing` не передаётся; `detachGrace` — ноль, как у stdio: закрытие WebSocket посреди хода отменяет ход (для MVP ход без клиента не может исполнять `fs/*` и `terminal/*`; возобновление хода после переподключения — после MVP).

stdout в режиме `--stdio` SHALL нести только кадры JSON-RPC: одно сообщение — одна строка UTF-8 (R-13).

#### Scenario: Ответ на initialize по stdio
- **WHEN** в stdin процесса `codelab-agent serve --stdio --llm-script test/llm_scripts/hello.json` записана строка `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}`
- **THEN** в stdout приходит одна строка с ответом `id: 1` и `protocolVersion: 1`, а в stdout нет ничего, кроме строк JSON-RPC

#### Scenario: Ход до конца по stdio
- **WHEN** клиент процесса выполняет `initialize`, `session/new` и `session/prompt` со сценарием `hello.json`
- **THEN** приходят `agent_message_chunk` с текстом `hello` и ответ `stopReason: end_turn`

#### Scenario: Два транспорта сразу
- **WHEN** бинарь запущен с `serve --stdio --ws` или с `serve` без транспорта
- **THEN** процесс завершается с кодом `64` и текстом ошибки использования в stderr, сервер не стартует

#### Scenario: Закрытие WebSocket посреди хода отменяет ход
- **WHEN** клиент `serve --ws` закрывает соединение во время `session/prompt`, а затем новое соединение загружает сессию через `session/load` и отправляет `session/prompt`
- **THEN** прежний ход отменён без ожидания переподключения, ожидающие разрешения получили `cancelled`, и новый `session/prompt` выполняется, а не отклоняется как занятой сессией
