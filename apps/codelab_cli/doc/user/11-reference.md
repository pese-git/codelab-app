# Справочник флагов и команд

Глава собирает флаги `codelab`, подкоманды и ссылки на главы, где они объяснены. Тексты справки сняты с `codelab`. Оглавление руководства — [руководство пользователя](../user-guide.md).

## `codelab --help`

```bash
codelab --help
```

```text
Usage:
  codelab [options] [first message]   interactive REPL
  codelab -p "<prompt>" [options]     headless: one turn, answer in stdout
  codelab profiles list|show <id>|add <id> <agent>|remove <id>
  codelab config check [--cwd <dir>]
  codelab config path|get|set|unset ...   read and edit config files
  codelab provider add|list|remove ...    manage LLM providers in config
  codelab provider add                    on a terminal: guided setup (or --preset <id> --yes ...)
  codelab mcp add|list|remove ...         manage MCP servers in config
  codelab secret set|delete|list|migrate   manage secrets (set reads the value on stdin)
  codelab test-scenario <file-or-dir>... --agent <profile> [--filter <glob>] [--timeout <d>] [--junit <file>]

Options:
-a, --agent=<profile>       Agent profile id, "embedded", "default" (the embedded agent), "stdio:<command> [args]", ws:// or wss:// URL (default: the embedded agent).
-C, --cwd=<dir>             Session folder.
-m, --model=<id>            Model option.
    --mode=<id>             Mode option.
-r, --resume=<sessionId>    Load a session instead of a new one.
-c, --continue              Load the latest session of the folder.
-p, --print=<prompt>        Headless: run one prompt and print the answer.
-f, --prompt-file=<file>    Headless: prompt from a file, "-" for stdin.
    --approve=<policy>      Headless approval policy.
                            [reject (default), read-only, allow-all]
    --timeout=<duration>    Headless: limit per turn, e.g. 90s or 10m.
    --ui=<mode>             Interactive mode: line-by-line REPL or full-screen TUI.
                            [line (default), tui]
    --no-color              No ANSI colors.
-v, --verbose               Connection diagnostics in stderr.
    --debug-secrets         Embedded agent: log secret lookups (names, never values).
    --version               Print the version.
-h, --help                  Print this help.

Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.
```

## Общие флаги

| Флаг | Что делает | Где описан |
|---|---|---|
| `-a`, `--agent <профиль>` | агент: встроенный (`embedded`, `default`, по умолчанию), `stdio:<команда> [аргументы]`, `ws://…`, `wss://…` или id профиля | [агент](05-folder-model-agent.md#выбрать-агента) |
| `-C`, `--cwd <папка>` | папка сессии; по умолчанию текущая | [папка, модель, режим](05-folder-model-agent.md#выбрать-папку-модель-и-режим) |
| `-m`, `--model <id>` | модель до первого запроса | там же |
| `--mode <id>` | режим сессии до первого запроса | там же |
| `-r`, `--resume <id>` | открыть сессию по идентификатору | [сессии](02-repl.md#сессии) |
| `-c`, `--continue` | продолжить последнюю сессию папки | там же |
| `-p`, `--print <запрос>` | один запрос без диалога | [запрос без диалога](04-headless.md) |
| `-f`, `--prompt-file <файл>` | запрос из файла; `-` — из stdin | там же |
| `--approve <правило>` | `reject` (по умолчанию), `read-only`, `allow-all` | [разрешения без человека](04-headless.md#разрешения-без-человека) |
| `--timeout <длительность>` | предел времени хода: `90s`, `10m`, `1h30m` | [запрос без диалога](04-headless.md#отправить-запрос) |
| `--ui <режим>` | `line` (по умолчанию) или `tui` | [полноэкранный режим](03-tui.md) |
| `--no-color` | вывод без цветов | — |
| `-v`, `--verbose` | диагностика соединения в stderr | — |
| `--debug-secrets` | в stderr — имена секретов, которые искал встроенный агент | [секреты](07-secrets.md#что-секрет-не-защищает) |
| `--version` | печатает `codelab 0.1.0` | — |
| `-h`, `--help` | справка | — |

Без флагов и слов `codelab` запускает диалог. Слова после флагов становятся первым сообщением: `codelab Объясни структуру проекта`.

## Подкоманды

| Подкоманда | Что делает | Глава |
|---|---|---|
| `codelab profiles list \| show <id> \| add <id> <агент> \| remove <id>` | профили подключения | [профили](05-folder-model-agent.md#профили) |
| `codelab provider add \| list \| remove` | провайдеры моделей | [провайдеры](06-providers.md) |
| `codelab mcp add \| list \| remove` | MCP-серверы | [MCP](08-mcp.md) |
| `codelab secret set \| delete \| list \| migrate` | секреты | [секреты](07-secrets.md) |
| `codelab config check \| path \| get \| set \| unset` | проверка и правка настроек | [настройки](09-config.md) |
| `codelab test-scenario <путь>…` | проверка агента фикстурами | [`test-scenario`](10-test-scenario.md) |

Справку подкоманды печатает она сама, если запустить её без аргументов (код `64`). Флаги записи:

| Подкоманда | Флаги |
|---|---|
| `config check` | `--cwd` |
| `config path` | `--project`, `--local`, `--cwd` |
| `config get <ключ>` | `--layer user\|project\|local\|merged`, `--cwd` |
| `config set <ключ> <значение>`, `config unset <ключ>` | `--project`, `--local`, `--cwd` |
| `provider add [<id>]` | `--kind`, `--base-url`, `--model`, `--context-window`, `--api-key-secret`, `--api-key-env`, `--api-key-stdin`, `--default`, `--preset`, `--skip-check`, `--yes`, `--project`, `--local` |
| `provider list` | `--cwd` |
| `provider remove <id>` | `--project`, `--local` |
| `mcp add <имя>` | `--type`, `--command`, `--arg`, `--env`, `--url`, `--header`, `--header-stdin`, `--header-scheme`, `--env-stdin`, `--disabled`, `--project`, `--local` |
| `mcp list` | `--cwd` |
| `mcp remove <имя>` | `--project`, `--local` |
| `secret migrate` | `--project`, `--local`, `--all`, `--cwd`, `--dry-run`, `--force` |
| `test-scenario` | `--agent`, `--filter`, `--timeout`, `--junit` |

У `provider add`, `provider remove`, `mcp add` и `mcp remove` своего `--cwd` нет: папку проекта для `--project` и `--local` задаёт общий `-C`. У `config` есть свой `--cwd`, он сильнее общего `-C`. У `secret` общий `-C` не допускается вовсе: `secret` с `-C` завершается с кодом `64`, а у `secret migrate` есть свой `--cwd`.

## Команды в диалоге

Список команд `/…` и клавиш — в [главе о диалоге](02-repl.md#команды-со-слэшем); клавиши полноэкранного режима — в [главе о нём](03-tui.md#клавиши).

## Коды выхода

| Код | Значение |
|---|---|
| `0` | успех |
| `1` | ошибка хода или соединения; `config check` нашёл ошибки; в `test-scenario` есть `FAIL`; `profiles show` или `profiles remove` с несуществующим id |
| `64` | ошибка использования: неверный флаг, нет запроса, неизвестный профиль, несуществующая папка, невалидная конфигурация встроенного агента (например, не настроена модель) |
| `130` | отмена: Ctrl+C, истёкший `--timeout`, Ctrl+C в мастере, ответ `n` на вопрос `? Save? [Y/n]` в `provider add` |
| `143` | завершение по `SIGTERM` |

Подробнее — [коды выхода в эксплуатации](../operations.md#коды-выхода).

## Переменные окружения и файлы

- `CODELAB_HOME` — каталог настроек (по умолчанию `~/.codelab`), `CODELAB_CONFIG`, `CODELAB_SECRET_<ИМЯ>`, `CODELAB_AGENT_TOKEN`, `CODELAB_DEBUG_SECRETS` — [переменные окружения](../../../../docs/ops/environment.md).
- `NO_COLOR` (непустая) и `TERM=dumb` выключают цвета; `LC_ALL`, `LC_CTYPE`, `LANG` со значением `UTF-8` включают символы Unicode — [эксплуатация](../operations.md#переменные-окружения).
- Файлы клиента и общие файлы с CodeLab app — [`CODELAB_HOME`](../../../../docs/ops/codelab-home.md) и [файлы `codelab`](../operations.md#файлы).

## Переходная команда `codelab serve`

`codelab serve …` запускает отдельный бинарь `codelab-agent` и в справке не указана. Команда временная: используйте `codelab-agent serve` — [переход с Python-агента](../../../../docs/user/migrating-from-python-agent.md#профили-и-скрипты-с-codelab-serve).

## Смотрите также

- [Обзор](00-overview.md)
- [Если что-то пошло не так](12-troubleshooting.md)
