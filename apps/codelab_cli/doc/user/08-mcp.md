# MCP-серверы

MCP (Model Context Protocol) — протокол, по которому агент подключает внешние серверы с инструментами. Глава объясняет, как записать MCP-сервер в конфигурацию из `codelab`, как посмотреть и удалить серверы и как управлять ими во время диалога. Что такое инструменты MCP и как агент ими пользуется — в [руководстве агента о MCP](../../../codelab_agent/doc/user/08-mcp.md); формат записи `mcp.servers` — в [настройке агента](../../../../docs/user/configuration.md#mcp-серверы). Оглавление руководства — [руководство пользователя](../user-guide.md).

`codelab mcp` правит файлы конфигурации и сам к серверу не подключается: подключает агент при старте.

## Добавить сервер

Сервер типа `stdio` — программа, которую агент запускает сам:

```bash
codelab mcp add files --type stdio --command my-mcp-server --arg /data
```

```text
Updated mcp.servers[files] in ~/.codelab/config.yaml
```

Предупреждение `agent.default_model: no model is configured` команды записи печатают, пока в конфигурации нет модели: правка при этом сохраняется. Сервер типа `http` — адрес, по которому сервер уже работает:

```bash
codelab mcp add tracker --type http --url https://mcp.example.com --header 'X-Team=${TEAM}'
```

| Флаг | Что задаёт |
|---|---|
| `<имя>` | имя сервера в конфигурации |
| `--type` | `stdio` или `http` |
| `--command`, `--arg` | программа сервера `stdio` и её аргументы; `--arg` повторяется |
| `--env KEY=VALUE` | переменная окружения сервера `stdio`; повторяется |
| `--url` | адрес сервера `http` |
| `--header KEY=VALUE` | заголовок запроса к серверу `http`; повторяется |
| `--header-stdin <Имя>`, `--header-scheme <Схема>` | заголовок, значение которого читается из stdin; схема (`Bearer`) добавляется перед значением |
| `--env-stdin <ИМЯ>` | переменная окружения сервера `stdio`, значение которой читается из stdin |
| `--disabled` | записать сервер с `enabled: false` |
| `--project`, `--local` | записать в файл проекта или в локальный файл проекта вместо файла пользователя |

Секреты в значениях заголовков и переменных пишите ссылками `${secret:имя}` или `${ПЕРЕМЕННАЯ}`, а не значением.

## Передать секрет через stdin

`--header-stdin` и `--env-stdin` читают одно значение из stdin (по одному флагу на вызов), сохраняют его в хранилище секретов и записывают в файл только ссылку на него:

```bash
printf %s "$TOKEN" | codelab mcp add tracker --type http --url https://mcp.example.com --header-stdin Authorization --header-scheme Bearer
```

```text
Stored secret codelab/mcp/tracker/authorization in file
Updated mcp.servers[tracker] in ~/.codelab/config.yaml
warning: agent.default_model: no model is configured; add a provider with at least one model
warning: secrets are stored unencrypted in ~/.codelab/secrets.yaml
```

В файл при этом попадает `Authorization: 'Bearer ${secret:codelab/mcp/tracker/authorization}'`. Для записи в хранилище нужен `secrets.backend: file` — [секреты](07-secrets.md). Без него команда отвечает `secret store env is read-only…` и ничего не записывает.

## Посмотреть и удалить

```bash
codelab mcp list
```

```text
tracker  type: http  layer: user  enabled: true
files  type: stdio  layer: user  enabled: true
```

В строке — имя, тип, слой конфигурации, откуда взят сервер, и включён ли он. `codelab mcp list --cwd <папка>` читает слои проекта другой папки.

```bash
codelab mcp remove tracker
```

`--project` и `--local` у `remove` выбирают файл. Если такого сервера в файле нет, команда пишет `mcp.servers[<имя>] is not set in <файл>`.

После правки конфигурации перезапустите `codelab`: встроенный агент читает MCP-серверы при старте. В диалоге сервером управляет команда агента `/mcp`: она показывает серверы, перечитывает их, включает и выключает. Пока серверов нет, она отвечает `No MCP servers.` Состояние серверов показывает и `/status`.

Полный синтаксис печатает `codelab mcp` без аргументов.

## Смотрите также

- [Секреты](07-secrets.md)
- [MCP-серверы в настройке агента](../../../../docs/user/configuration.md#mcp-серверы)
- [Справочник флагов и команд](11-reference.md)
