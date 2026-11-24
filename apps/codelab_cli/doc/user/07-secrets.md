# Секреты

Секреты — ключи API и токены — хранятся отдельно от `config.yaml`: в файле лежит только имя секрета. Глава объясняет, как записать, посмотреть, удалить секрет и перенести ключи, записанные в конфигурации прямо значением. Оглавление руководства — [руководство пользователя](../user-guide.md).

## Где хранятся секреты

Бэкенд хранилища выбирает ключ `secrets.backend` в глобальном конфиге. По умолчанию в этой версии работает бэкенд `env`: он только читает переменные `CODELAB_SECRET_<ИМЯ>`, а записать секрет им нельзя.

```bash
codelab secret list
```

```text
Backend: env (OS keychain backends are not available in this version; set secrets.backend: file or CODELAB_SECRET_* variables)
```

Чтобы `codelab` записывал секреты сам, включите файловый бэкенд — [шаг 2 настройки агента](../../../../docs/user/configuration.md#шаг-2-задайте-ключ-api):

```bash
codelab config set secrets.backend file
```

Файловый бэкенд кладёт секреты открытым текстом в `$CODELAB_HOME/secrets.yaml`, и каждая команда напоминает об этом предупреждением.

## Записать, посмотреть, удалить

Значение секрета `codelab secret set <имя>` читает из stdin (в терминале ввод скрыт) и никогда не печатает. Аргументом значение передать нельзя: строка команды остаётся в истории оболочки.

```bash
codelab secret set codelab/openai
codelab secret list
codelab secret delete codelab/openai
```

```text
Stored secret codelab/openai in file
warning: secrets are stored unencrypted in ~/.codelab/secrets.yaml
```

```text
Backend: file
codelab/openai
warning: secrets are stored unencrypted in ~/.codelab/secrets.yaml
```

```text
Deleted secret codelab/openai from file
warning: secrets are stored unencrypted in ~/.codelab/secrets.yaml
```

В скрипте подавайте значение на stdin из файла или из переменной, прочитанной без эха:

```bash
read -rs KEY && printf %s "$KEY" | codelab secret set codelab/openai; unset KEY
```

## Подключить секрет к провайдеру или MCP-серверу

- Провайдер ссылается на секрет ключом `api_key_secret` или флагом `--api-key-secret <имя>`; с `--api-key-stdin` `codelab provider add` сам сохраняет значение как `codelab/<id>` — [провайдеры](06-providers.md).
- MCP-сервер получает заголовки и переменные окружения, значения которых читаются из stdin: `--header-stdin`, `--env-stdin` — [MCP-серверы](08-mcp.md).
- Токен внешнего агента по WebSocket — переменная `CODELAB_AGENT_TOKEN`; профиль из CodeLab app может ссылаться на секрет, и если его нет в хранилище, `codelab` печатает `codelab: profile <id> has no stored secret value; connecting without a token.` и подключается без токена — [профили](05-folder-model-agent.md#профили).

## Перенести ключи из конфигурации в хранилище

Если ключ записан в `config.yaml` прямо значением (`api_key: …`), `codelab config check` предупреждает об этом:

```bash
codelab config check
```

```text
Sources: defaults, ~/.codelab/config.yaml
warning: ~/.codelab/config.yaml:7:5: providers.openai.api_key: a secret is stored in the config file; move it to the secret store: codelab secret migrate
warning: secrets: file backend stores secrets unencrypted in ~/.codelab/secrets.yaml
Default model: openai/gpt-demo (config)
Config: valid
```

`codelab secret migrate` переносит такие значения в хранилище и оставляет в файле ссылку. Сначала посмотрите, что изменится:

```bash
codelab secret migrate --dry-run
```

```text
~/.codelab/config.yaml: providers.openai.api_key -> api_key_secret: codelab/openai (new)
warning: secrets are stored unencrypted in ~/.codelab/secrets.yaml
```

Затем выполните перенос:

```bash
codelab secret migrate
```

```text
Moved providers.openai.api_key in ~/.codelab/config.yaml to secret codelab/openai
restart the agent to use the moved secrets
warning: secrets are stored unencrypted in ~/.codelab/secrets.yaml
```

| Флаг | Что делает |
|---|---|
| `--project`, `--local` | перенести значения из файла проекта или локального файла проекта (без флагов — файл пользователя) |
| `--all` | перенести из всех трёх файлов |
| `--cwd <папка>` | папка, чьи слои проекта читать |
| `--dry-run` | только показать, что изменится |
| `--force` | заменить уже сохранённый секрет с тем же именем (необратимо) |

После переноса перезапустите агента: встроенный агент в `codelab` перечитывает настройки при запуске.

## Что секрет не защищает

До версии 1.0 вывод инструментов, запросы и журналы сессий не очищаются от секретов: то, что в них попало, уходит провайдеру модели и в файлы сессий как есть. Подробнее — [что попадает в логи и журналы](../../../../docs/user/configuration.md#что-попадает-в-логи-и-журналы). Флаг `--debug-secrets` (или переменная `CODELAB_DEBUG_SECRETS=1`) пишет в stderr, какие секреты искал встроенный агент: имя и источник, без значения.

## Смотрите также

- [Провайдеры моделей](06-providers.md)
- [Каталог `CODELAB_HOME`](../../../../docs/ops/codelab-home.md)
- [Переменные окружения](../../../../docs/ops/environment.md)
