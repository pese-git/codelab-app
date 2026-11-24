# Установка и запуск

Эта глава — про отдельную программу `codelab-agent`. Встроенному агенту в app и `codelab` она не нужна: он уже входит в клиент. После главы вы соберёте программу, подключите модель и запустите агента по stdio или по сети.

## Перед началом

- Репозиторий CodeLab и FVM. Готового установщика в этой версии нет: до выпуска 1.0 агент собирается из исходников — [запуск из исходников](../../../../docs/user/run-from-source.md).
- Ключ провайдера модели или локальная модель (LM Studio, Ollama), которой ключ не нужен.

## Собрать программу

1. Подготовьте репозиторий по [запуску из исходников](../../../../docs/user/run-from-source.md#1-подготовка).
2. Соберите агента:

   ```bash
   fvm dart run melos run build:agent
   ```

   Появится файл `build/bin/codelab-agent`.
3. Проверьте, что программа запускается:

   ```bash
   build/bin/codelab-agent
   ```

   Без команды программа печатает справку и завершается с кодом `64`. Флага `--version` у неё нет.

Начало справки:

```text
codelab-agent: missing command: codelab-agent serve

Usage: codelab-agent serve (--stdio | --ws) [options]
       codelab-agent config check|path|get|set|unset ...
       codelab-agent provider add|list|remove ...
       codelab-agent mcp add|list|remove ...
       codelab-agent secret set|delete|list|migrate

Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.
…
```

Дальше справка перечисляет флаги `serve`: полный список с переменными окружения — в [эксплуатации](../operations.md#флаги-serve).

Чтобы вызывать программу по имени, добавьте `build/bin` в `PATH`. В примерах ниже она записана как `codelab-agent`.

## Подключить модель

Агенту нужен хотя бы один провайдер с одной моделью. Команды ниже записывают их в `~/.codelab/config.yaml` — тот же файл читают app и `codelab`.

1. Добавьте провайдера. Пример для локального сервера LM Studio:

   ```bash
   codelab-agent provider add local --kind openai-compatible \
     --base-url http://127.0.0.1:1234/v1 --model qwen/qwen3-1.7b \
     --context-window 32768 --default
   ```

   ```text
   Updated providers.local in ~/.codelab/config.yaml
   ```

   Для провайдера с ключом добавьте `--api-key-env <ИМЯ_ПЕРЕМЕННОЙ>` или `--api-key-secret <имя>`. Значение ключа аргументом не передаётся — [как задать ключ](../../../../docs/user/configuration.md#шаг-2-задайте-ключ-api).
2. Проверьте конфигурацию:

   ```bash
   codelab-agent config check
   ```

   ```text
   Sources: defaults, ~/.codelab/config.yaml
   Default model: local/qwen/qwen3-1.7b (config)
   Config: valid
   ```

   Код выхода `0` значит, что конфигурация годится. Без провайдера команда сообщает `agent.default_model: no model is configured; add a provider with at least one model` и завершается кодом `1`.

Подробнее о провайдерах и моделях — в главе [«Модель и провайдеры»](03-model-and-providers.md).

## Запустить `serve --stdio`

Режим для клиентов, которые сами запускают агента: Zed, `codelab` с профилем `stdio:…`. Обычно вы не запускаете его руками: клиент делает это сам, а вы вносите команду в настройки клиента — [подключение к клиентам](02-connect-clients.md).

Если запустить вручную, программа молча ждёт кадры ACP на stdin. Логи она пишет в stderr, а stdout занимает протоколом. Завершить — `Ctrl+D` (код `0`) или `Ctrl+C` (код `130`).

```bash
codelab-agent serve --stdio
```

Рабочая папка проекта — текущая папка процесса: оттуда агент берёт `.codelab/config.yaml`. Клиент передаёт папку сессии отдельно, при создании сессии.

Пример проверки без клиента (отправка `initialize` и ответ) — в [эксплуатации](../operations.md#serve---stdio).

## Запуск по сети: `serve --ws`

Режим для агента, к которому клиенты подключаются по сети.

1. Задайте токен в переменной окружения. Без непустого токена программа не запустится:

   ```bash
   export CODELAB_AGENT_TOKEN="<token>"
   ```
2. Запустите агента:

   ```bash
   codelab-agent serve --ws --port 8765
   ```

   В stderr появятся строки запуска (первую, про бэкенд секретов, мы опустили):

   ```text
   2026-11-24T21:14:20.435808Z info host.config.loaded {sources: [defaults, ~/.codelab/config.yaml], warnings: 0, project_root: ~/projects/demo, transport: ws, models: [local/qwen/qwen3-1.7b]}
   2026-11-24T21:14:20.435915Z info project_files.skipped {reason: project files are not read over WebSocket, transport: ws}
   2026-11-24T21:14:20.438871Z info host.plan {profile: agent-serve, tools: [read, write, edit, task_create, task_update, task_list, task_get, exec], off: {fileListing: WebSocket: клиент может быть не на этой машине, mcp: stdio MCP servers are disabled over WebSocket}}
   2026-11-24T21:14:20.439241Z info serve.ws.listening {host: 127.0.0.1, port: 8765}
   ```

   Строка `serve.ws.listening` значит, что порт открыт. По умолчанию программа слушает только `127.0.0.1`.
3. Клиент подключается по `ws://<адрес>:8765` и передаёт заголовок `Authorization: Bearer <token>`. Запрос без токена получает ответ `401`, обычный HTTP-запрос — `426`.

Что отключено в этом режиме, показывает таблица в [обзоре](00-overview.md#три-способа-запустить-агента). Соединение идёт без шифрования; перед выходом за пределы машины прочитайте [сеть и безопасность](../operations.md#сеть-и-безопасность).

## Команды без сервера

Те же файлы настроек можно менять командами `codelab-agent`. Сервер они не запускают. Эти подкоманды общие с `codelab`: можно вызывать как `codelab …`.

| Команда | Что делает |
|---|---|
| `config check` | читает конфигурацию как `serve` и печатает источники, ошибки и предупреждения; код `1` при ошибках |
| `config path [--project \| --local]` | показывает пути файлов слоёв и есть ли они |
| `config get <ключ>` | показывает значение ключа и слой, откуда оно взято; секретоподобные значения маскирует |
| `config set <ключ> <значение>`, `config unset <ключ>` | правят файл, сохраняя комментарии; `--project` и `--local` выбирают файл проекта |
| `provider add`, `provider list`, `provider remove` | провайдеры и модели |
| `mcp add`, `mcp list`, `mcp remove` | MCP-серверы — [глава 8](08-mcp.md) |
| `secret set`, `secret delete`, `secret list`, `secret migrate` | секреты; значение читается только из stdin |

Слои конфигурации, ключи и секреты — в [настройке агента](../../../../docs/user/configuration.md). Запущенный агент подхватывает часть правок сам, остальные — после перезапуска; команда `config set` пишет, какой случай ваш: `note: restart the agent to apply: <ключ>`.

## Смотрите также

- [Эксплуатация `codelab-agent`](../operations.md) — флаги, переменные окружения, логи, коды выхода.
- [Подключение к клиентам](02-connect-clients.md)
- [Оглавление руководства](../user-guide.md)
