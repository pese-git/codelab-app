# codelab-cli Specification

## Purpose
Терминальный клиент `codelab` (`apps/codelab_cli`) на чистом Dart поверх общего клиентского слоя `codelab_client_core`: разбор команд и флагов, профили подключения, построчный REPL со стримингом, одобрения, slash-команды, клавиши и история ввода. Состояния сессий, очереди и одобрений у CLI нет — их владелец kit. Устройство — `docs/architecture/proposals/dart-agent-and-clients/09-11-stage-6-cli-mvp.md` и §12.2.
## Requirements
### Requirement: Команда codelab и разбор флагов
Терминальный клиент `apps/codelab_cli` SHALL собираться в бинарь `codelab` (`melos run build:cli` → `build/bin/codelab`). Без подкоманды и без `-p`/`-f` `codelab [опции] [первое сообщение]` SHALL запускать REPL; подкоманды MVP — `profiles` и `test-scenario`; `--version` и `--help` SHALL печатать версию и справку и выходить с кодом `0`. Флаги MVP — по таблице `09-11-stage-6-cli-mvp.md` без пометки этапа и с пометкой «этап 6», кроме перечисленных в design.md, D1 как перенесённые. Флаг или подкоманда, не зарегистрированные в этой сборке, SHALL давать код `64` и строку `Unknown flag` / `Unknown command` в stderr без запуска агента. Флаг `--ui line|tui` SHALL выбирать интерактивный режим: `line` (по умолчанию) — построчный REPL, `tui` — полноэкранный режим (capability `codelab-tui`). `--ui tui` SHALL давать код `64` без запуска агента, если stdin или stdout не TTY (`--ui tui needs a terminal on stdin and stdout`) и вместе с `-p`/`-f` (`--ui applies only to the interactive mode`); неизвестное значение — код `64`. Ошибка разбора SHALL оставлять stdout пустым. Клиент НЕ SHALL импортировать Flutter и `package:codelab_agent_*`.

#### Scenario: Неизвестный флаг
- **WHEN** запускается `codelab --output-format stream-json -p hi`
- **THEN** процесс завершается с кодом `64`, stdout пуст, в stderr — `Unknown flag`, агент не запускается

#### Scenario: Версия
- **WHEN** запускается `codelab --version`
- **THEN** в stdout одна строка с версией клиента, код выхода `0`

#### Scenario: TUI без терминала
- **WHEN** запускается `codelab --ui tui` со stdout в pipe
- **THEN** процесс завершается с кодом `64`, в stderr — `--ui tui needs a terminal on stdin and stdout`, агент не запускается

#### Scenario: TUI с headless
- **WHEN** запускается `codelab --ui tui -p hi`
- **THEN** процесс завершается с кодом `64`, stdout пуст, агент не запускается

### Requirement: Профили подключения CLI
Значение `--agent` (`-a`) SHALL разбираться так: `stdio:<команда> [аргументы]` — `StdioProfile` с разбором аргументов как в shell (кавычки, экранирование); `ws://…` или `wss://…` — `WebSocketProfile`, токен которого читается из переменной `CODELAB_AGENT_TOKEN` через `SecretSource`; `embedded` — код `64` и `Embedded agent is not available in this build.` до этапа 7; иначе — id профиля из `$CODELAB_HOME/profiles.json` (`CODELAB_HOME` по умолчанию — `~/.codelab`), хранимого `JsonFileProfileStore`. Без `--agent` SHALL использоваться профиль `default`; если файла или профиля нет — код `64` и `No default agent profile. Pass --agent or run "codelab profiles add default stdio:<command>".`, агент не запускается. Команда `codelab profiles list|show <id>|add <id> <значение --agent>|remove <id>` SHALL работать без запуска агента; значение токена в `profiles.json` НЕ SHALL записываться. Ошибка подключения SHALL давать понятное сообщение в stderr и код `1` (U-06).

#### Scenario: Нет профиля по умолчанию
- **WHEN** запускается `codelab -p hi` с пустым `CODELAB_HOME`
- **THEN** код выхода `64`, в stderr — подсказка `codelab profiles add default …`, процесс агента не запускается

#### Scenario: Профиль stdio с кавычками
- **WHEN** выполняется `codelab profiles add py 'stdio:python -m "codelab agent" --stdio'`, затем `codelab profiles show py`
- **THEN** профиль хранит команду `python` и аргументы `-m`, `codelab agent`, `--stdio`

#### Scenario: Агент не запускается
- **WHEN** `--agent 'stdio:/nonexistent/agent'`
- **THEN** в stderr — сообщение об ошибке подключения с командой, код выхода `1`

### Requirement: Поверхности вывода
Поверхность вывода REPL SHALL выбираться один раз при старте по первому подходящему условию: stdout не TTY → `raw` (текст ответа байт в байт, без ANSI и разбора markdown, мысли не печатаются, строки инструментов — простым текстом в stderr); `TERM=dumb`, непустой `NO_COLOR` или `--no-color` → `plain` (без SGR-последовательностей); иначе → `ansi`. Текст из сессии (ответ, мысли, заголовки и детали инструментов, сообщения об ошибках) SHALL выводиться без управляющих символов C0 (кроме `\t` и `\n`), DEL и C1; каждая напечатанная строка с атрибутами SHALL кончаться их сбросом.

#### Scenario: Вывод в pipe
- **WHEN** REPL получает промпт со stdin не TTY и stdout в pipe, агент отвечает markdown-текстом
- **THEN** stdout не содержит байта `0x1B`, а текст ответа совпадает с конкатенацией дельт `agent_message_chunk`

#### Scenario: NO_COLOR в терминале
- **WHEN** REPL запущен в PTY с `NO_COLOR=1`
- **THEN** вывод не содержит SGR-последовательностей

### Requirement: Рендер хода в REPL
REPL SHALL печатать ответ агента по мере прихода дельт (`AgentTextItem` из `SessionView`), не повторяя уже напечатанное (U-01). Мысли (`ThoughtItem`) SHALL печататься до ответа и приглушённо (`ESC[2m`) на `ansi`, а режим `/thoughts dim|collapsed|hidden` SHALL менять показ до конца процесса (U-08). Вызов инструмента SHALL выводиться одной строкой: значок статуса, название, деталь (команда или путь из `ToolCallView`) и время для завершённого вызова; сериализованный `rawInput` в строках инструментов, статуса и предупреждений НЕ SHALL появляться (U-09). Изменение `SessionView.plan` SHALL печатать план целиком; заметки (`NoticeItem`) — отдельной строкой.

#### Scenario: Потоковый ответ
- **WHEN** агент присылает три `agent_message_chunk` и `end_turn`
- **THEN** в выводе текст трёх дельт подряд ровно один раз, затем строка ввода

#### Scenario: Мысли приглушённо
- **WHEN** агент присылает `agent_thought_chunk`, затем ответ, в PTY без `NO_COLOR`
- **THEN** текст мыслей окружён `ESC[2m` и стоит до ответа

#### Scenario: Строка инструмента без JSON
- **WHEN** агент вызывает `exec` с `rawInput`, содержащим вложенный объект `env`
- **THEN** строка инструмента содержит название и команду, но не содержит `{` и `"env"`

### Requirement: Редактор строки и клавиши
Ввод SHALL идти через редактор строки в raw-режиме `stdin`, когда stdin и stdout — TTY; иначе — построчным чтением без raw-режима. Все клавиши SHALL задаваться одной таблицей действий (`lib/src/input/key_bindings.dart`), из которой строятся обработка и `/help keys`; две клавиши одной области НЕ SHALL быть привязаны к разным действиям. Поведение MVP: Enter — отправить (во время хода — в очередь с сообщением `queued: <n>`); Alt+Enter, Ctrl+J и `\` в конце строки + Enter — новая строка; Esc и Ctrl+C во время хода — `session/cancel`; Esc вне хода — очистить строку; Ctrl+C вне хода — очистить строку, повтор в течение 1 с — выход; Ctrl+D на пустой строке — выход; ↑/↓ — история; Tab в строке, начинающейся с `/`, — дополнение команды; Ctrl+L — очистить экран. История SHALL сохраняться между запусками в `$CODELAB_HOME/cli_history` (U-07). Выход из raw-режима любым путём (команда, сигнал, исключение) SHALL возвращать терминал в исходный режим.

#### Scenario: Esc отменяет ход
- **WHEN** во время хода в PTY нажат Esc
- **THEN** агент получает `session/cancel`, ход завершается `cancelled`, REPL снова принимает ввод

#### Scenario: Двойной Ctrl+C выходит
- **WHEN** вне хода Ctrl+C нажат дважды за 1 с
- **THEN** процесс завершается с кодом `0`, терминал в исходном режиме

#### Scenario: История между запусками
- **WHEN** в первом запуске отправлен промпт `first`, а во втором нажата ↑
- **THEN** в строке ввода — `first`

### Requirement: Одобрение в REPL
Запрос одобрения из `SessionView.pendingApprovals` SHALL показываться блоком: заголовок с видом и риском, команда или путь, рабочая папка, и подсказка только с вариантами, которые предложил агент: `y` — `allow_once`, `a` — `allow_always`, `n` — `reject_once`, `N` — `reject_always`, `?` — показать `rawInput` целиком и снова спросить (U-02). Выбор SHALL отправлять `optionId` выбранного варианта через `SessionHandle.respond`. Esc или Ctrl+C SHALL отменять ход, а ожидающий запрос — получать исход `cancelled`. Enter без выбора НЕ SHALL ничего делать; клавиша варианта, которого агент не предложил, НЕ SHALL ничего отправлять. Пока ждёт одобрение, ввод промпта SHALL быть недоступен; несколько запросов SHALL показываться по одному в порядке прихода.

#### Scenario: Разрешить один раз
- **WHEN** агент запрашивает одобрение с вариантами `allow_once` и `reject_once`, и пользователь нажимает `y`
- **THEN** агент получает `optionId` варианта `allow_once`, ход продолжается

#### Scenario: Отклонить
- **WHEN** на тот же запрос пользователь нажимает `n`
- **THEN** агент получает `optionId` варианта `reject_once`, ход продолжается

#### Scenario: Вариант не предложен
- **WHEN** агент не предложил `allow_always`, и пользователь нажимает `a`
- **THEN** ответ не отправляется, блок одобрения остаётся

### Requirement: Slash-меню и клиентские команды
Строка, начинающаяся с `/`, SHALL разбираться как команда. Каталог SHALL строиться `CommandCatalog` из команд клиента и `SessionView.agentCommands`; клиентская команда SHALL иметь приоритет, а одноимённая команда агента SHALL быть доступна как `/agent:<имя>`; команда агента SHALL отправляться промптом `/<имя> [аргументы]`. Новое `available_commands_update` SHALL сразу менять каталог. Tab SHALL дополнять имя по `CommandCatalog.search`: один кандидат — подставить, несколько — показать список с пометкой команд агента (U-03). Клиентские команды MVP: `/help`, `/help keys`, `/exit`, `/quit`, `/new`, `/sessions`, `/resume <n или id>`, `/mode [id]`, `/model [id]`, `/config [id] [значение]`, `/cancel`, `/queue`, `/queue drop <n>`, `/queue clear`, `/profile [id]`, `/reconnect`, `/plan`, `/clear`, `/thoughts dim|collapsed|hidden` (U-04). `/mode` и `/model` без аргумента SHALL показывать значения опции конфигурации с отметкой текущего; с аргументом — отправлять `session/set_config_option`; неизвестное значение SHALL давать сообщение без запроса (U-05). Неизвестная команда SHALL давать сообщение `Unknown command /<имя>` без запроса к агенту.

#### Scenario: Меню объединяет команды агента
- **WHEN** агент объявил команды `compact` и `plan`, и пользователь вводит `/` и Tab
- **THEN** список содержит команды клиента и `compact`, `plan` с пометкой агента; `/plan` выполняет клиентскую команду, `/agent:plan` отправляет промпт `/plan`

#### Scenario: Выбор модели
- **WHEN** агент предлагает опцию `model` со значениями `a` и `b`, и пользователь вводит `/model b`
- **THEN** агент получает `session/set_config_option` с `configId: model` и `value: b`

#### Scenario: Неизвестная модель
- **WHEN** пользователь вводит `/model zzz`
- **THEN** печатается сообщение о неизвестном значении, `session/set_config_option` не отправляется

### Requirement: Очередь промптов в REPL
Промпт, отправленный во время хода, SHALL вставать в очередь `SessionHandle.queue` kit и уходить автоматически после завершения хода (U-15). `/queue` SHALL показывать элементы с номерами; `/queue drop <n>` — удалять n-й; `/queue clear` — очищать очередь. Своей очереди CLI НЕ SHALL заводить.

#### Scenario: Очередь уходит после хода
- **WHEN** во время хода пользователь отправляет `second`
- **THEN** печатается `queued: 1`, а после `end_turn` агент получает `session/prompt` с `second`

### Requirement: Сессии в REPL
REPL SHALL создавать новую сессию в `--cwd` (по умолчанию — текущая папка) или загружать сессию по `--resume <id>` (`session/load`) или последнюю сессию папки по `--continue` (`session/list`). `/sessions` SHALL печатать сессии папки с номерами и заголовками из `SessionSummaryView`; `/resume <n или id>` — загружать сессию; `/new` — создавать новую в той же папке; `/reconnect` — переподключаться и перезагружать активную сессию; `/profile <id>` — подключаться к другому профилю. Без поддержки `session/load` у агента `--resume`, `--continue` и `/resume` SHALL давать сообщение без запроса.

#### Scenario: Продолжить последнюю сессию
- **WHEN** в папке есть две сессии, и запускается `codelab --continue`
- **THEN** загружается более поздняя сессия, её история печатается, и новый промпт уходит в неё

### Requirement: Сигналы CLI
SIGINT и SIGTERM SHALL отменять идущий ход (`session/cancel`), закрывать транспорт и завершать дочерний процесс агента; повторный сигнал SHALL завершать процесс сразу. В REPL SIGINT вне raw-режима SHALL вести себя как Ctrl+C. Код выхода — `130` для SIGINT и `143` для SIGTERM в headless; REPL по SIGTERM SHALL выходить с кодом `143`. На Windows SIGTERM не отслеживается.

#### Scenario: SIGTERM во время хода
- **WHEN** во время хода REPL получает SIGTERM
- **THEN** агент получает `session/cancel`, процесс агента завершён, CLI выходит с кодом `143`, терминал в исходном режиме

### Requirement: Подкоманда codelab config
`codelab config check [--cwd <dir>]` SHALL работать без запуска агента и без подключения по ACP. Она вызывает общую реализацию `ConfigCommands` через `package:codelab_setup/io.dart` (design.md change `add-agent-configuration`, D13, D14), поэтому её вывод и коды выхода совпадают с `codelab-agent config` (capability `agent-configuration`). Корень состояния — `CODELAB_HOME` (по умолчанию `~/.codelab`); `config check` его не изменяет. `cwd` — `--cwd` подкоманды, иначе общий `-C`/`--cwd`, иначе текущий каталог; значение передаётся загрузчику как есть, без лексической нормализации, — канонизирует путь загрузчик, как у `codelab-agent`. Проверяется окружение процесса `codelab`; профиль подключения не учитывается, поэтому флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `config` — ошибка использования с кодом `64`. `codelab config` без подкоманды — код `64` и `config needs a subcommand: codelab config check [--cwd <dir>]` в stderr. Остальные подкоманды `config` (`get`, `set`, `unset`, `path`, `migrate`) в этой сборке НЕ SHALL регистрироваться: код `64` и `Unknown command config <sub>` в stderr. Клиент НЕ SHALL импортировать `package:codelab_agent_*` напрямую.

#### Scenario: Проверка конфига из CLI
- **WHEN** `codelab config check --cwd <dir>` запускается для каталога, где глобальный `config.yaml` задаёт провайдера и `agent.default_model`, а `<dir>/.codelab/config.yaml` содержит `budget.max_steps: 0`
- **THEN** stdout содержит проблему `budget.max_steps` с файлом и строкой, последняя строка `Config: invalid (issues: 1)`, код `1`, ни один процесс агента не запущен (`cli/config-check-reports-issues`)

#### Scenario: Подкоманда записи ещё не зарегистрирована
- **WHEN** запускается `codelab config set budget.max_steps 10` или `codelab config migrate`
- **THEN** код `64`, в stderr — `Unknown command config set` (соответственно `Unknown command config migrate`), файлы конфига не изменены

#### Scenario: Неизвестная подкоманда config
- **WHEN** запускается `codelab config frobnicate`
- **THEN** код `64`, stdout пуст, stderr содержит `Unknown command config frobnicate`, процесс агента не запущен

#### Scenario: config без подкоманды
- **WHEN** запускается `codelab config`
- **THEN** код `64`, stdout пуст, stderr содержит `config needs a subcommand: codelab config check [--cwd <dir>]`

#### Scenario: --cwd подкоманды сильнее общего
- **WHEN** запускается `codelab -C <a> config check --cwd <b>`, где проектный конфиг `<b>` содержит проблему, а `<a>` — валидный
- **THEN** проверяется `<b>`: stdout содержит проблему из `<b>/.codelab/config.yaml`, код `1`

#### Scenario: Без --cwd подкоманды берётся общий
- **WHEN** запускается `codelab -C <b> config check` из другого каталога
- **THEN** проверяется `<b>`, вывод и код те же, что у `codelab config check --cwd <b>`

#### Scenario: Относительный путь и `..` канонизирует загрузчик
- **WHEN** `codelab config check --cwd <rel>` и `codelab-agent config check --cwd <rel>` запускаются из одного каталога с одинаковыми `CODELAB_HOME` и окружением, где `<rel>` — относительный путь, содержащий `..`
- **THEN** stdout, stderr и код выхода двух бинарей совпадают; CLI не нормализует путь сам до передачи загрузчику

#### Scenario: Флаги подключения с config — ошибка использования
- **WHEN** запускается `codelab --agent <cmd> config check`, `codelab -p hi config check` или `codelab --prompt-file <f> config check`
- **THEN** код `64`, stdout пуст, в stderr — ошибка использования; процесс агента не запущен, конфиг не проверяется

#### Scenario: config check не меняет CODELAB_HOME
- **WHEN** `codelab config check` запускается с пустым временным `CODELAB_HOME`
- **THEN** после выхода в `CODELAB_HOME` нет `sessions/`, `profiles.json` и `cli_history`

### Requirement: Домашний каталог CLI CODELAB_HOME
Домашний каталог CLI (`profiles.json`, `cli_history`) — `CODELAB_HOME`, по умолчанию `$HOME/.codelab` (`%USERPROFILE%\.codelab` на Windows); его SHALL вычислять `CodelabHome.resolve` (design.md change `add-agent-project-files`, D17; решение пользователя 2026-10-30). Значение `CODELAB_HOME`, равное `~` или начинающееся с `~/`, SHALL раскрываться так же, как у агента (agent-configuration «Корень состояния CODELAB_HOME»): `~` заменяется `HOME`, а если он не задан или пуст, `USERPROFILE`. Так `codelab` и `codelab-agent` с одним окружением видят один каталог. Любое другое значение, начинающееся с `~` (`~user/…`, `~\…`), SHALL быть ошибкой использования (`UsageError`, код `64`) с текстом `CODELAB_HOME: ~user is not supported, use an absolute path`. Значение `~` или `~/…` при неизвестном домашнем каталоге (`HOME` и `USERPROFILE` не заданы или пусты) SHALL быть ошибкой использования с кодом `64` и текстом `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`. Тексты совпадают с агентом. Пустой `CODELAB_HOME` SHALL считаться незаданным. `codelab config check` передаёт окружение процесса загрузчику агента без изменений, поэтому его корень состояния определяет agent-configuration.

#### Scenario: Тильда раскрывается в HOME
- **WHEN** `codelab profiles add default stdio:agent` запускается с `CODELAB_HOME='~/cl'` (буквально) и `HOME=<tmp>`
- **THEN** профиль записан в `<tmp>/cl/profiles.json`; каталога `./~` нет

#### Scenario: Тильда без домашнего каталога
- **WHEN** `codelab -p hi` запускается с `CODELAB_HOME='~/cl'` без `HOME` и `USERPROFILE`
- **THEN** код `64`, stderr содержит `CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an absolute path`, агент не запускается

#### Scenario: ~user — ошибка использования
- **WHEN** `codelab -p hi` или `codelab config check` запускается с `CODELAB_HOME='~bob/cl'` и `HOME=<tmp>`
- **THEN** код `64`, stderr содержит `CODELAB_HOME: ~user is not supported, use an absolute path`, агент не запускается, каталог `./~bob` не создаётся

