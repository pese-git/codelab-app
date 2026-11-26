# Диалог (построчный режим)

Построчный режим — режим `codelab` по умолчанию. Он печатает ответы в обычный поток терминала, поэтому историю можно прокручивать и копировать средствами терминала. Глава объясняет, как писать сообщения, какие есть клавиши и команды `/…`, как отвечать на запросы разрешений, отменять ход, возвращаться к сессиям. Оглавление руководства — [руководство пользователя](../user-guide.md).

## Начать и закончить

1. Запустите `codelab` в папке проекта. Можно сразу передать первое сообщение: `codelab Объясни структуру проекта`.
2. Пишите сообщения и отправляйте их Enter. Новая строка внутри сообщения — Alt+Enter или Ctrl+J.
3. Пока агент отвечает, можно отправить следующее сообщение. Оно встанет в очередь, и `codelab` напечатает `queued: 1`. После ответа очередь уйдёт сама.
4. Выход — Ctrl+D на пустой строке, `/exit`, `/quit` или двойной Ctrl+C.

Так выглядит очередь. Сервер модели в примере недоступен, поэтому оба хода кончаются ошибкой после четырёх попыток (снимок сокращён в середине строк `error:`):

```text
> Привет
> queued: 1
> /queue
  1. второй вопрос
error: request failed after 4 attempts in 5.8 s: attempt 1 network (connection failed: …); … (network)
─ standard · lmstudio/qwen/qwen3-1.7b · ctx 9%
> второй вопрос
error: request failed after 4 attempts in 4.6 s: attempt 1 network (connection failed: …); … (network)
─ standard · lmstudio/qwen/qwen3-1.7b · ctx 9%
>
```

<!-- screenshot: текстовый снимок хода с ответом агента, вызовом инструмента и строкой статуса — нужен живой провайдер модели -->

История ввода сохраняется между запусками в `$CODELAB_HOME/cli_history` (стрелки ↑ и ↓ листают её). Это файл с правами `0600`; про файлы `codelab` — [эксплуатация](../operations.md#файлы).

## Клавиши

| Клавиша | Что делает |
|---|---|
| Enter | отправить сообщение; во время ответа — поставить в очередь |
| Alt+Enter, Ctrl+J | новая строка в сообщении |
| Esc, Ctrl+C во время ответа | отменить ответ |
| Esc вне ответа | очистить строку ввода |
| Ctrl+C вне ответа | очистить строку; второе нажатие за 1 секунду — выход |
| Ctrl+D | выход на пустой строке |
| ↑, ↓ | предыдущее и следующее сообщение из истории |
| Tab | дополнить команду после `/` |
| Ctrl+L | очистить экран |
| ←, →, Home, End, Ctrl+A, Ctrl+E | двигать курсор |
| Backspace, Delete, Ctrl+U | удалять символ и всё до начала строки |

Полный список клавиш печатает `/help keys`:

```text
> /help keys
Enter      send the prompt; while a turn runs, queue it
Alt+Enter  insert a new line
Ctrl+J     insert a new line
Esc        (during a turn) cancel the running turn
Ctrl+C     (during a turn) cancel the running turn
Esc        (no turn) clear the input line
Ctrl+C     (no turn) clear the input line; press again within 1s to exit
Ctrl+D     exit on an empty line
Up         previous prompt from the history
Down       next prompt from the history
Tab        complete a /command
Ctrl+L     clear the screen
Left       move the cursor left
Right      move the cursor right
Home       move to the start of the line
Ctrl+A     move to the start of the line
End        move to the end of the line
Ctrl+E     move to the end of the line
Backspace  delete the character before the cursor
Delete     delete the character under the cursor
Ctrl+U     delete to the start of the line
```

## Строка статуса

После каждого хода `codelab` печатает приглушённую строку статуса: режим, модель, заполнение контекста, токены и стоимость сессии.

```text
─ standard · lmstudio/qwen/qwen3-1.7b · ctx 12% · ↑13.9k ↓1.2k
```

Сегмент стоимости (`$0.13`) появляется, когда агент знает цену модели (ключи `providers.<id>.models.<модель>.cost_input` и `cost_output`). Если цена не задана, как обычно у локальной модели, сегмента нет.

- Строка идёт после ответа, отмены или ошибки хода. Сообщение, поставленное в очередь, её не печатает.
- Сегменты, о которых агент не сообщил, пропускаются. Если неизвестно всё, строки нет. Нулевые токены сессии тоже скрыты: сегмент `↑… ↓…` не печатается, когда оба числа равны нулю.
- `↑` — токены на входе (с кэшем), `↓` — на выходе; суммы за всю сессию. «~» перед числом значит, что оно приблизительное: агент прислал usage не для всех шагов или не знает цену. Подсказки у «~» нет: терминал её не показывает.
- Без цвета (`--no-color`, `NO_COLOR`, `TERM=dumb`) строка печатается без оформления. Если вывод перенаправлен в файл или канал, и в режиме `-p` её нет: поток остаётся ответом агента.

## Команды со слэшем

Строка, которая начинается с `/`, — команда. `/help` печатает команды `codelab` и команды агента:

```text
> /help
Commands:
  /help [keys]                                     show the commands, or the keys with "keys"
  /exit                                            exit
  /quit                                            exit
  /new                                             start a new session in this folder
  /sessions                                        list the sessions of this folder
  /resume <n|id>                                   open a session from /sessions or by id
  /mode [value]                                    show or set the mode
  /model [value]                                   show or set the model
  /config [id] [value]                             show or set a config option
  /cancel                                          cancel the running turn
  /queue [drop <n>|clear]                          show, drop or clear queued prompts
  /profile [id]                                    show the agent profile or connect to another
  /reconnect                                       reconnect and reload the session
  /plan                                            show the current plan
  /clear                                           clear the screen
  /thoughts dim|collapsed|hidden                   show thoughts dimmed, collapsed or not at all
  /provider add|list|remove [<id>] [--local]       add, list or remove model providers
  /settings [<key> [<value> | --reset]] [--local]  show or change agent settings
Agent commands:
  /compact  Compact the session history
  /agent:mode  Switch the session mode
  /agent:model  Switch the model
  /status  Show the model, mode, working directory and MCP servers
  /usage  Show token usage and cost of the session
  /agent:config  Reload or check the agent config
  /mcp  List, reload, enable or disable MCP servers
  /agent:help  List commands
  …
Run /help keys for the keys.
```

Многоточие в конце списка команд агента заменяет строки, которые пришли из ваших личных навыков: навык проекта или пользователя появляется как команда `/skill:<имя>`.

Команды `codelab` выполняются сразу, без запроса к агенту. Команды агента уходят агенту сообщением. Если имя совпадает, побеждает команда `codelab`, а команда агента доступна с префиксом `agent:` — например, `/agent:help`. Список команд агента зависит от агента и его настроек; их смысл описан в [руководстве агента](../../../codelab_agent/doc/user/06-project-context.md#встроенные-команды-агента).

### Команды `codelab`

| Команда | Что делает |
|---|---|
| `/help [keys]` | печатает команды; `/help keys` — клавиши |
| `/exit`, `/quit` | выйти |
| `/new` | начать новую сессию в этой папке (`New session <id>.`) |
| `/sessions` | список сессий папки с номерами; текущая помечена `*` |
| `/resume <номер или id>` | открыть сессию из списка `/sessions` или по идентификатору |
| `/mode [значение]` | показать режим сессии или сменить его |
| `/model [значение]` | показать модель или сменить её |
| `/config [id] [значение]` | показать или задать другие опции сессии, которые предлагает агент |
| `/cancel` | отменить идущий ход (`Nothing to cancel.`, если хода нет) |
| `/queue [drop <n> \| clear]` | показать очередь сообщений, убрать сообщение номер `n` или очистить очередь |
| `/profile [id]` | показать профиль агента или переключиться на другой |
| `/reconnect` | переподключиться к агенту и загрузить сессию заново |
| `/plan` | показать текущий план агента (`No plan yet.`, если плана нет) |
| `/clear` | очистить экран |
| `/thoughts dim\|collapsed\|hidden` | показывать размышления модели приглушённо, свёрнуто или не показывать |
| `/provider add\|list\|remove [<id>] [--local]` | добавить, показать или удалить провайдера модели |
| `/settings [<ключ> [<значение> \| --reset]] [--local]` | показать или изменить настройки агента |

Подробнее о некоторых командах:

- `/mode` без значения печатает режимы агента и отмечает текущий `*`. Что значит каждый режим — в [главе о разрешениях](../../../codelab_agent/doc/user/05-permissions.md#режимы).

  ```text
  > /mode
  Mode (mode):
      plan  Plan
      ask  Ask
    * standard  Standard
      accept-edits  Accept edits
      bypass  Bypass
  ```

- `/model` печатает модели из конфигурации; `/model <id>` переключает модель:

  ```text
  > /model
  Model (model):
    * lmstudio/qwen/qwen3-1.7b  qwen/qwen3-1.7b
  ```

- `/config` без аргументов печатает все опции сессии и допустимые значения: `mode` и `model` — две из них.
- `/profile` показывает, к какому агенту вы подключены: `Profile embedded (Embedded agent): embedded embedded-cli`. `/profile <id>` подключает другой профиль — [профили](05-folder-model-agent.md#выбрать-агента).
- `/provider add` запускает ту же пошаговую настройку, что мастер первого запуска. Во время хода и без терминала она не открывается. `--local` пишет в файл `.codelab/config.local.yaml` проекта. Подробнее — [провайдеры моделей](06-providers.md).
- `/settings` без аргументов печатает строки `ключ  значение  источник`, где источник — слой конфигурации (`default`, `user`, …). `/settings <ключ>` предлагает выбрать значение или подсказывает формат, `/settings <ключ> <значение>` записывает его в файл пользователя (с `--local` — в локальный файл проекта), `/settings <ключ> --reset` удаляет ключ из слоя. Файл проекта (`.codelab/config.yaml`) этой командой не правится. Подробнее — [проверка и правка настроек](09-config.md#настройки-из-диалога).

### Команды агента

Эти команды выполняет агент, а `codelab` показывает его ответ. Примеры из встроенного агента (набор зависит от версии и настроек):

```text
> /status
Model: lmstudio/qwen/qwen3-1.7b
Mode: standard
Working directory: ~/projects/demo
MCP servers: none
Config: ok
─ standard · lmstudio/qwen/qwen3-1.7b
```

Встроенные команды агента (`/status`, `/usage`, `/compact`, `/mcp` и другие), шаблоны команд проекта и навыки (`/skill:<имя>`) описаны в [главе агента о контексте проекта](../../../codelab_agent/doc/user/06-project-context.md#встроенные-команды-агента). Команды агента зависят от его версии и настроек; актуальный список печатает `/help`.

## Разрешения

Перед опасным действием — например, запуском команды или записью файла — агент может спросить разрешение. `codelab` показывает, что агент хочет сделать, и ждёт клавишу:

| Клавиша | Ответ |
|---|---|
| `y` | разрешить один раз |
| `a` | разрешать всегда |
| `n` | отклонить один раз |
| `N` | отклонять всегда |
| `?` | показать запрос целиком и спросить снова |
| Esc, Ctrl+C | отменить ответ агента |

Работают только варианты, которые предложил агент. Если агент не предложил «разрешать всегда», клавиша `a` ничего не отправит.

Так выглядит блок, когда агент хочет изменить файл (режим `standard`; тестовая модель попросила правку `README.md`, папка проекта замаскирована):

```text
> edit the title
* Edit README.md
Permission: Edit README.md (local write)
  command: README.md
  cwd: ~/projects/demo
  [y] allow once  [a] allow always  [n] reject once  [N] reject always  [?] details  [Esc] cancel
```

После `y` агент делает правку и ход заканчивается (`done` — ответ тестовой модели):

```text
+ Edit README.md 7.5s
done
─ standard · scripted/scripted-1 · ctx 8%
>
```

Какие действия спрашивают, чем отличаются режимы `ask`, `standard`, `accept-edits`, `bypass` и что такое критические команды — в главе агента о разрешениях: [режимы](../../../codelab_agent/doc/user/05-permissions.md#режимы), [критические действия](../../../codelab_agent/doc/user/05-permissions.md#критические-действия).

## Отменить ход и управлять очередью

- Esc или Ctrl+C во время ответа отменяют ход; `/cancel` делает то же командой.
- Сообщения, отправленные во время ответа, ждут в очереди. `/queue` печатает очередь (`The queue is empty.`, если она пуста), `/queue drop 1` убирает первое сообщение, `/queue clear` очищает всю очередь.

## Сессии

Агент хранит историю разговоров по папкам проекта.

- `codelab --continue` (`-c`) — продолжить последнюю сессию папки.
- `codelab --resume <id>` (`-r`) — открыть сессию по идентификатору.
- `/sessions` — список сессий этой папки с номерами; `/resume <номер или id>` — открыть сессию; `/new` — начать новую.

```text
> /sessions
* 1. <session-id> (<session-id>)
```

У сессии, в которой уже есть сообщения, в списке показано начало первого сообщения, затем идентификатор в скобках и время.

Если сессии с таким идентификатором нет, `codelab --resume <id>` завершается с ошибкой `ACP request session/load failed: Session not found: <id>`, а `/resume` с неверным номером отвечает `No session <n> in the last /sessions list.` Как агент хранит сессии и журналы — в [главе агента о сессиях](../../../codelab_agent/doc/user/09-sessions.md).

## Недавние проекты

Диалог и полноэкранный режим (в том числе с `--resume` и `--continue`) добавляют папку сессии в список недавних проектов: он общий с CodeLab app, и папка появится в его списке «Projects». Headless `-p`, `test-scenario` и подкоманды (`config`, `profiles` и другие) список не меняют. Список хранится в `$CODELAB_HOME/recent_projects.json` — [подробности](../../../../docs/ops/codelab-home.md#общие-файлы).

## Смотрите также

- [Полноэкранный режим](03-tui.md) — тот же диалог в отдельном экране
- [Справочник флагов и команд](11-reference.md)
- [Если что-то пошло не так](12-troubleshooting.md)
