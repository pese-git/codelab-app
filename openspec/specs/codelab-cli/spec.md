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
Значение `--agent` (`-a`) SHALL разбираться так:
- `embedded` или `default` — `EmbeddedProfile(hostProfile: 'embedded-cli')`: встроенный агент в процессе CLI (требование «Встроенный агент в CLI»); `default` — алиас `embedded` (design.md change `add-app-settings-shell`, D21). Для выбора агента запись из `profiles.json` НЕ SHALL использоваться. При `default` файл читается только ради предупреждения о старой записи `default`, и любая ошибка этого чтения SHALL игнорироваться. При `embedded` файл НЕ SHALL читаться;
- `stdio:<команда> [аргументы]` — `StdioProfile` с разбором аргументов как в shell (кавычки, экранирование);
- `ws://…` или `wss://…` — `WebSocketProfile` со ссылкой `tokenRef: env:CODELAB_AGENT_TOKEN`: токен читается из переменной `CODELAB_AGENT_TOKEN`;
- иначе — id профиля из `$CODELAB_HOME/profiles.json` (`CODELAB_HOME` по умолчанию — `~/.codelab`), хранимого `JsonFileProfileStore`.

Без `--agent` SHALL всегда использоваться встроенный агент, как с `-a embedded` (решение пользователя 2026-11-04; design.md change `add-app-settings-shell`, D21; заменяет D13, п. 1 change `add-embedded-agent-mode`). Правило одно для REPL, `--ui tui`, `-p` и `test-scenario` (D13, п. 7). Без `--agent` CLI НЕ SHALL читать `profiles.json`, поэтому битый файл не мешает запуску встроенного агента. О неявном выборе встроенного агента и о смене правила CLI НЕ SHALL печатать отдельной строки: выбранный профиль виден с `--verbose` и командой `/profile` (D13, п. 8; D21, п. 2). Битый `profiles.json` — не JSON или JSON неверной структуры — при `-a <id>` SHALL давать код `64` с причиной, а не тихий переход на встроенного агента и не необработанное исключение. Внешний агент выбирается явно: `-a stdio:…`, `-a ws://…` или `-a <id>`.

Id `embedded` и `default` зарезервированы (`reservedProfileIds` kit). Запись с id `default`, лежащая в `profiles.json` от прежней версии, SHALL игнорироваться: `profiles list` её не показывает, `profiles show default` печатает встроенный профиль. При `codelab profiles list`, `codelab profiles show default` и `-a default`, если такая запись есть, CLI SHALL печатать в stderr одно предупреждение `profile "default" in profiles.json is ignored: default is the built-in agent; remove it with codelab profiles remove default`. Команду, аргументы, URL и `env` записи предупреждение НЕ SHALL содержать. Файл автоматически НЕ SHALL перезаписываться, а `codelab profiles remove default` SHALL удалять запись. Подсказки о смене правила выбора CLI НЕ SHALL печатать (D21, п. 2).

Токен WebSocket-профиля SHALL разрешать общий источник kit `ProfileSecretSource` по правилу `ProfileTokenRef` (design.md change `add-app-settings-shell`, D15). Ссылка `env:<NAME>` читает переменную окружения процесса для любого допустимого имени, поэтому профиль, созданный в codelab-app со ссылкой `env:DEVBOX_TOKEN`, работает в CLI. Ссылка `secret:<имя>` читает секрет из того же хранилища секретов агента, что codelab-app (`ClientSecretAccess` через `codelab_setup/io.dart`, порт `ProfileSecrets`; design.md change `add-provider-setup-ui`, D4, D13): переменная `CODELAB_SECRET_<…>`, затем бэкенд `secrets.backend`. Пустая или отсутствующая переменная, отсутствующий секрет и ссылка другого вида дают подключение без токена, как раньше. Для отсутствующего секрета `secret:` CLI SHALL перед подключением писать в stderr `codelab: profile <id> has no stored secret value; connecting without a token.` (с `--verbose` — и событие `connection_profile.token_secret_missing` с единственным полем `profile_id`; design.md change `add-provider-setup-ui`, D13). Правило одно для REPL, `--ui tui`, `-p` и `codelab test-scenario`: драйвер фикстур читает `secret:` из того же хранилища (`ClientSecretAccess`). У `codelab test-scenario` нет флага `--verbose`, поэтому драйвер фикстур выводит только строку предупреждения в stderr, без события журнала. Значение токена в stdout, stderr и журнал НЕ SHALL попадать. `codelab profiles show` SHALL печатать `token: env <NAME>`, `token: secret <имя> (set)` или `token: secret <имя> (missing)` (наличие — без чтения значения). Значение ссылки другого вида НЕ SHALL выводиться: `codelab profiles show` печатает `token: unrecognized token reference (not supported in this version)`, а диагностика называет только id профиля.

Команда `codelab profiles list|show <id>|add <id> <значение --agent>|remove <id>` SHALL работать без запуска агента; значение токена в `profiles.json` НЕ SHALL записываться. Id нового профиля в `profiles add` SHALL проходить общее правило kit `isValidProfileId` (`^[a-z0-9][a-z0-9._-]{0,63}$`); нарушение — код `64` с текстом правила. Профили, сохранённые раньше с другими id (например, с заглавными буквами), SHALL читаться, показываться и выбираться `-a <id>` как прежде, а формат `profiles.json` НЕ SHALL меняться. `embedded` в `profiles add` — ни как id, ни как значение — SHALL давать код `64` и `embedded is built in; use --agent embedded`; `default` — так же, код `64` и `default is the built-in agent; use --agent embedded`. Ошибка подключения SHALL давать понятное сообщение в stderr и код `1` (U-06); stdio-профиль в нём описывается командой и числом аргументов, без их значений (требование «Аргументы stdio-профиля в выводе CLI»).

#### Scenario: Без профиля по умолчанию запускается встроенный агент
- **WHEN** CLI из тестовой точки входа со сценарием модели (design.md change `add-embedded-agent-mode`, D8) запускается как `codelab -p hi` с временным `CODELAB_HOME` без `profiles.json`
- **THEN** ход проводит встроенный агент, дочерний процесс агента не запускается, stdout содержит ответ сценария, код `0`

#### Scenario: Без профиля и без конфига
- **WHEN** рабочий `codelab -p hi` запускается с пустым временным `CODELAB_HOME` (нет `profiles.json` и `config.yaml`)
- **THEN** код `64`, stdout пуст, stderr содержит проблему конфигурации встроенного агента и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`; ни один процесс агента не запущен

#### Scenario: profiles.json неверной структуры при -a <id>
- **WHEN** `profiles.json` — корректный JSON неверной структуры (например, массив вместо объекта или профиль без обязательного поля), и запускается `codelab -a dev -p hi`
- **THEN** код `64`, stderr содержит причину чтения профилей, stdout пуст, агент не запускается

#### Scenario: Без --agent битый profiles.json не мешает встроенному агенту
- **WHEN** CLI из тестовой точки входа со сценарием модели запускается как `codelab -p hi`, а `profiles.json` в `CODELAB_HOME` — не JSON
- **THEN** ход проводит встроенный агент, код `0`, файл `profiles.json` не прочитан и не изменён

#### Scenario: -a default — встроенный агент
- **WHEN** `profiles.json` содержит запись `default` со `stdio:<scripted-агент>`, и запускаются `codelab -p hi` и `codelab -a default -p hi`
- **THEN** обе команды проводит встроенный агент, процесс из записи не запускается; вторая пишет в stderr одно предупреждение `profile "default" in profiles.json is ignored: default is the built-in agent; remove it with codelab profiles remove default` без команды записи; первая предупреждения не пишет и `profiles.json` не читает

#### Scenario: default зарезервирован в profiles add
- **WHEN** выполняются `codelab profiles add default stdio:x` и `codelab profiles add x default`
- **THEN** обе дают код `64` и `default is the built-in agent; use --agent embedded`, `profiles.json` не изменён

#### Scenario: Старая запись default в списке
- **WHEN** `profiles.json` содержит записи `default` (stdio, команда `/opt/secret-agent`) и `dev`, и выполняются `codelab profiles list` и `codelab profiles show default`
- **THEN** список содержит `dev` и не содержит `default`; `show default` печатает встроенный профиль; каждая команда пишет одно предупреждение в stderr, ни одно не содержит `/opt/secret-agent`, файл не изменён

#### Scenario: Удаление старой записи default
- **WHEN** при той же старой записи выполняется `codelab profiles remove default`
- **THEN** код `0`, `profiles.json` больше не содержит `default`, а следующий `codelab profiles list` не пишет предупреждения

#### Scenario: Встроенный агент явно
- **WHEN** запускается `codelab -a embedded -p hi` при профиле `default` в `profiles.json`
- **THEN** ход проводит встроенный агент, процесс из `default` не запускается, `profiles.json` не читается (при `-a embedded`)

#### Scenario: embedded нельзя сохранить профилем
- **WHEN** выполняется `codelab profiles add x embedded` или `codelab profiles add embedded stdio:x`
- **THEN** код `64`, в stderr — `embedded is built in; use --agent embedded`, `profiles.json` не изменён

#### Scenario: Профиль stdio с кавычками
- **WHEN** выполняется `codelab profiles add py 'stdio:python -m "codelab agent" --stdio'`
- **THEN** код `0`; запись `py` в `$CODELAB_HOME/profiles.json` хранит `command` `python` и `args` `["-m", "codelab agent", "--stdio"]`; следующий `codelab profiles show py` печатает `command: python` и `args: 3 (values hidden)`

#### Scenario: Агент не запускается
- **WHEN** запускается `codelab -p hi --agent 'stdio:/nonexistent/agent --stdio'`
- **THEN** код выхода `1`, stdout пуст, stderr содержит `codelab: cannot start the agent "/nonexistent/agent" with 1 argument:` и не содержит `--stdio`

#### Scenario: Токен из произвольной переменной
- **WHEN** `profiles.json` содержит WebSocket-профиль `devbox` с `tokenRef: env:DEVBOX_TOKEN`, переменная `DEVBOX_TOKEN` задана, и запускается `codelab -a devbox -p hi` против scripted-агента, требующего этот токен
- **THEN** агент принимает Bearer-токен, ход проходит, stdout и stderr не содержат значения токена

#### Scenario: Старые профили читаются как раньше
- **WHEN** `profiles.json` от прежней версии содержит профиль `Old` (WebSocket, `tokenRef: env:CODELAB_AGENT_TOKEN`), и выполняются `codelab profiles add Dev stdio:x` и `codelab -a Old -p hi`
- **THEN** первая команда завершается кодом `64` с текстом правила id и не меняет файл, а вторая выбирает профиль `Old` с токеном из `CODELAB_AGENT_TOKEN`

#### Scenario: Токен из хранилища секретов
- **WHEN** `secrets.backend: file`, секрет `codelab/profiles/devbox/token` сохранён `codelab secret set`, `profiles.json` содержит WebSocket-профиль `devbox` с `tokenRef: secret:codelab/profiles/devbox/token`, и запускаются `codelab profiles show devbox` и `codelab -a devbox -p hi` против scripted-агента, требующего этот токен
- **THEN** `show` печатает `token: secret codelab/profiles/devbox/token (set)`, агент принимает Bearer-токен, ход проходит, ни stdout, ни stderr не содержат значения

#### Scenario: Незаданный секрет токена
- **WHEN** `profiles.json` содержит WebSocket-профиль `ci` с `tokenRef: secret:codelab/profiles/ci/token`, секрета нет, и запускается `codelab -a ci -p hi`
- **THEN** stderr содержит `profile ci has no stored secret value; connecting without a token.` без имени секрета, подключение идёт без токена

#### Scenario: test-scenario читает секрет профиля
- **WHEN** `secrets.backend: file`, секрет `codelab/profiles/devbox/token` сохранён, и запускается `codelab test-scenario --agent devbox` против scripted-агента, требующего этот токен
- **THEN** фикстуры проигрываются с Bearer-токеном, stdout и stderr не содержат значения

#### Scenario: Ссылка не вида env: не выводится
- **WHEN** `profiles.json` содержит WebSocket-профиль `devbox` с `tokenRef: sk-test-leak-0123456789` (не `env:` и не `secret:`), и выполняются `codelab profiles show devbox` и `codelab -a devbox -p hi --verbose`
- **THEN** `show` печатает `token: unrecognized token reference (not supported in this version)`; подключение идёт без токена; ни stdout, ни stderr не содержат `sk-test-leak-0123456789`

#### Scenario: -a default при битом profiles.json
- **WHEN** `profiles.json` — не JSON, и запускается `codelab -a default -p hi` из тестовой точки входа со сценарием модели
- **THEN** ход проводит встроенный агент, код `0`, ошибки чтения файла и кода `64` нет

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

#### Scenario: Одноимённые команды клиента и Dart-агента
- **WHEN** CLI подключён к Dart-агенту или встроенному агенту, агент объявил встроенные `compact`, `mode`, `model`, `status`, `mcp`, `help`, и пользователь вводит `/` и Tab
- **THEN** список содержит клиентские `/help`, `/mode`, `/model` и `/config`, команды агента `/compact`, `/status`, `/mcp` с пометкой агента и одноимённые команды агента как `/agent:help`, `/agent:mode`, `/agent:model`; `/help` печатает справку клиента без `session/prompt`, `/agent:help` отправляет промпт `/help` и печатает ответ агента (`cli/slash-menu-merges-agent-commands`, U-03; design.md change `add-agent-builtin-slash-commands`, D10)

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
`codelab config path|get|set|unset|check` SHALL работать без запуска агента и без подключения по ACP. Подкоманды вызывают общую реализацию `ConfigCommands` через `package:codelab_setup/io.dart` (design.md change `add-agent-configuration`, D13, D14; design.md change `add-config-writer-and-reload`, D6), поэтому их вывод и коды выхода совпадают с `codelab-agent config` (capability `agent-configuration`).

**Корень и `cwd`.** Корень состояния — `CODELAB_HOME` (по умолчанию `~/.codelab`). `config check`, `config path` и `config get` его не изменяют; `config set` и `config unset` меняют только файл выбранного слоя. `cwd` берётся по порядку: `--cwd` подкоманды, общий `-C`/`--cwd`, текущий каталог. Значение передаётся загрузчику как есть, без лексической нормализации, — канонизирует путь загрузчик, как у `codelab-agent`. Проверяется окружение процесса `codelab`; профиль подключения не учитывается.

**Ошибки использования** — код `64`:
- флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `config`;
- `codelab config` без подкоманды — текст `config needs a subcommand: codelab config path|get|set|unset|check` в stderr;
- неизвестная подкоманда (в том числе `migrate`) — `Unknown command config <sub>` в stderr;
- ошибка разбора аргументов `config set` и `config unset` — фиксированная фраза `invalid arguments for config set` (`… config unset`) и справка `config` без цитирования слов argv: значение могло начинаться с `-` и оказаться разобранным как флаг (design.md change `add-config-writer-and-reload`, D6).

Клиент НЕ SHALL импортировать `package:codelab_agent_*` напрямую.

#### Scenario: Проверка конфига из CLI
- **WHEN** `codelab config check --cwd <dir>` запускается для каталога, где глобальный `config.yaml` задаёт провайдера и `agent.default_model`, а `<dir>/.codelab/config.yaml` содержит `budget.max_steps: 0`
- **THEN** stdout содержит проблему `budget.max_steps` с файлом и строкой, последняя строка `Config: invalid (issues: 1)`, код `1`, ни один процесс агента не запущен (`cli/config-check-reports-issues`)

#### Scenario: Запись совпадает с бинарём агента
- **WHEN** `codelab config set budget.max_steps 10` и `codelab-agent config set budget.max_steps 10` запускаются с одинаковыми копиями `CODELAB_HOME` и окружением
- **THEN** stdout, stderr, код выхода и итоговые байты `config.yaml` у двух бинарей совпадают (`apps/codelab_cli/test/e2e/config_write_command_test.dart`)

#### Scenario: Запись в локальный слой проекта
- **WHEN** запускается `codelab -C <dir> config set permissions.mode plan --local`
- **THEN** создан `<dir>/.codelab/config.local.yaml` с `permissions.mode: plan`, глобальный конфиг не изменён

#### Scenario: Неизвестная подкоманда config
- **WHEN** запускается `codelab config migrate` или `codelab config frobnicate`
- **THEN** код `64`, stdout пуст, stderr содержит `Unknown command config migrate` (соответственно `frobnicate`), процесс агента не запущен, файлы конфига не изменены

#### Scenario: config без подкоманды
- **WHEN** запускается `codelab config`
- **THEN** код `64`, stdout пуст, stderr содержит `config needs a subcommand: codelab config path|get|set|unset|check`

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
- **WHEN** запускается `codelab --agent <cmd> config check`, `codelab -p hi config set budget.max_steps 1` или `codelab --prompt-file <f> config check`
- **THEN** код `64`, stdout пуст, в stderr — ошибка использования; процесс агента не запущен, конфиг не проверяется и не меняется

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

### Requirement: Подкоманда codelab secret
`codelab secret set|delete|list|migrate` SHALL работать без запуска агента и без подключения по ACP. Подкоманда вызывает общую реализацию `SecretCommands` через `package:codelab_setup/io.dart`, поэтому её вывод и коды выхода совпадают с `codelab-agent secret` (capability `agent-secrets`, «Подкоманды secret»). Корень состояния — `CODELAB_HOME` по правилу `CodelabHome.resolve`. `package:codelab_setup/io.dart` SHALL импортироваться только из `lib/src/run.dart`.

Флаги подключения и запроса (`-a`/`--agent`, `-m`/`--model`, `--mode`, `-r`/`--resume`, `-c`/`--continue`, `-p`/`--print`, `-f`/`--prompt-file`, `--approve`, `--timeout`, `--ui`) вместе с `secret` SHALL быть ошибкой использования с кодом `64` и сообщением `codelab: --<flag> does not apply to secret` (то же для `-C`/`--cwd` верхнего уровня). Исключение — флаги подкоманды `secret migrate`: `--project`, `--local`, `--all`, `--cwd <dir>`, `--dry-run`, `--force` после слова `migrate` SHALL разбираться как её флаги (capability `agent-secrets`, «Подкоманда secret migrate»; design.md change `add-config-literal-secrets-and-migrate`, D7); `--all` вместе с `--project` или `--local` — код `64`. `codelab secret` без подкоманды или с неизвестной подкомандой — код `64` и `codelab: secret needs a subcommand: set, delete, list or migrate` в stderr; `set` без имени — `codelab: secret set needs the secret name`; `delete` не с одним именем — `codelab: secret delete needs exactly one name`; `list` с аргументами — `codelab: secret list takes no arguments`; `migrate` с позиционными аргументами — `codelab: secret migrate takes no arguments`; ошибка разбора argv — `codelab: invalid arguments for secret`, если `secret` есть в argv где угодно, в том числе при ошибке флага верхнего уровня до `secret`; текст исключения `package:args` НЕ SHALL печататься. Все эти ошибки дают код `64` и справку `secret` (`Usage: codelab secret set|delete|list|migrate`) в stderr. Ни одно из этих сообщений НЕ SHALL цитировать присланные слова: среди них может быть значение секрета (capability `agent-secrets`, «Подкоманды secret»). Справка `codelab --help` SHALL содержать строку `codelab secret set|delete|list|migrate   manage secrets (set reads the value on stdin)`. Справка `secret` и `codelab --help` SHALL содержать строку `Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.` (решение пользователя 2026-11-04 R8-7; design.md change `add-config-literal-secrets-and-migrate`, D13).

Значение секрета НЕ SHALL попадать в stdout, `profiles.json`, `cli_history` и лог CLI. `codelab secret` НЕ SHALL создавать `sessions/`, `profiles.json` и `cli_history` в `CODELAB_HOME`.

#### Scenario: Совпадение с бинарём агента
- **WHEN** `codelab secret set codelab/x extra-arg` и `codelab-agent secret set codelab/x extra-arg` запускаются с одним окружением
- **THEN** у обоих код `64`, stderr содержит `pass the secret value on stdin, not as an argument`, stdout пуст и одинаков

#### Scenario: Флаги подключения с secret
- **WHEN** запускается `codelab -p hi secret list`
- **THEN** код `64`, stdout пуст, хранилище не вызывалось, агент не запущен

#### Scenario: --cwd с secret
- **WHEN** запускается `codelab -C /tmp secret list`
- **THEN** код `64`, stderr содержит `codelab: --cwd does not apply to secret` и справку `secret`, хранилище не вызывалось

#### Scenario: Ошибка верхнего парсера с secret
- **WHEN** запускается `codelab --no-such-flag secret list`
- **THEN** код `64`, stderr содержит `codelab: invalid arguments for secret` и справку `secret` и не содержит `no-such-flag` и текста `package:args` (`Could not find an option`)

#### Scenario: Подкоманда не меняет CODELAB_HOME
- **WHEN** `codelab secret list` запускается с пустым временным `CODELAB_HOME` и `secrets.backend: env` в `CODELAB_CONFIG`
- **THEN** после выхода в `CODELAB_HOME` нет `sessions/`, `profiles.json`и `cli_history`; `secrets.yaml` не создан

#### Scenario: migrate совпадает с бинарём агента
- **WHEN** `codelab secret migrate --all --dry-run --cwd <dir>` и `codelab-agent secret migrate --all --dry-run --cwd <dir>` запускаются с одним `CODELAB_HOME` и конфигом с литеральными секретами
- **THEN** stdout и коды выхода совпадают байт в байт, ни один вывод не содержит значений

#### Scenario: --cwd подкоманды migrate и -C верхнего уровня
- **WHEN** запускается `codelab secret migrate --project --cwd /tmp/p`, а отдельно — `codelab -C /tmp/p secret migrate`
- **THEN** первая команда работает со слоем проекта `/tmp/p`; вторая — код `64` с `codelab: --cwd does not apply to secret`

#### Scenario: Предупреждение о 1.0 в справке
- **WHEN** запускаются `codelab --help` и `codelab secret` без подкоманды
- **THEN** stderr или stdout каждой содержит строку `Note: before 1.0, tool output, prompts and session logs are not redacted: secrets they contain reach the model provider and session files as is.`

### Requirement: Встроенный агент в CLI
Composition root CLI SHALL регистрировать `EmbeddedTransportResolver` рядом с `ioTransportResolver`. Этот резолвер открывает встроенного агента через `localEmbeddedAgentOpener` из `package:codelab_embedded/io.dart` с профилем хоста `embedded-cli`, окружением процесса `codelab` и `cwd` = рабочая папка сессии (`-C`/`--cwd`, иначе текущий каталог; design.md change `add-embedded-agent-mode`, D2, D6). Импортировать `package:codelab_embedded/io.dart` SHALL только `lib/src/composition_root.dart`. Пакеты `package:codelab_agent_*` CLI по-прежнему НЕ SHALL импортировать.

Требования к резолверу и режимам:
- **Невалидный конфиг** встроенного агента (`EmbeddedAgentConfigException`) — код `64`. Текст исключения идёт в stderr, stdout остаётся пустым. В REPL и в `-p` сообщение одно.
- **Флаг `--debug-secrets`** (без значения) SHALL включать `secrets.lookup` встроенного агента и выводить эти события в stderr даже без `--verbose`: поля `name`, `purpose`, `source`, `found`, без значений секретов. Остальной лог агента от флага не появляется. Флаг действует только со встроенным агентом, на внешнего не влияет; `CODELAB_DEBUG_SECRETS=1` работает так же (design.md change `add-agent-secret-store`, D15; change `add-embedded-agent-mode`, D13, п. 9).
- **Логи встроенного агента** SHALL идти в логгер CLI: с `--verbose` — в stderr, иначе — никуда, кроме `secrets.lookup` при `--debug-secrets`. stdout headless не засоряется.
- **Выход** CLI (конец REPL, `--ui tui`, конец `-p`, `SIGINT`/`SIGTERM` по требованию «Сигналы CLI») SHALL дожидаться `dispose` встроенного агента до завершения процесса: журнал сессии дописан. Коды выхода `-p` встроенного агента — те же, что у внешнего. Подробности (design.md change `add-embedded-agent-mode`, D6, «Выход CLI»):
  - ожидание ограничено таймаутом CLI, большим grace `server.shutdown` агента (5 s). По истечении CLI пишет событие `embedded.close_timeout` уровня `warning` в логгер CLI, а в stderr — всегда, независимо от `--verbose` и `--debug-secrets`, одну строку `codelab: the embedded agent did not stop in <N> s` (<N> — таймаут; без текста ошибки), и завершается с прежним кодом;
  - обработчики `SIGINT`/`SIGTERM` снимаются только после `dispose` агента. Сигнал, пришедший, пока идёт `dispose` (в REPL, `--ui tui` и `-p`), завершает процесс сразу с кодом `130` (`SIGINT`) или `143` (`SIGTERM`), как у внешнего агента; повторный сигнал во время отмены хода — тоже;
  - ошибка сборки или работы режима не пропускает `dispose`: закрытие резолвера выполняется в `finally`.
- **Одобрения** встроенного агента SHALL идти тем же путём, что у внешнего: вопрос REPL `y / a / n`, политика `--approve` в `-p` (по умолчанию `reject`).

#### Scenario: Невалидный конфиг встроенного агента
- **WHEN** запускается `codelab -a embedded -p hi -C <dir>`, где `<dir>/.codelab/config.yaml` содержит `budget.max_steps: 0`
- **THEN** код `64`, stdout пуст, stderr содержит проблему `budget.max_steps` с файлом и строкой и подсказку `Configure the embedded agent in <home>/config.yaml; check it with: codelab config check`

#### Scenario: Отказ по умолчанию в headless
- **WHEN** `codelab -a embedded -p "write file"` идёт со сценарием, где модель зовёт `write`, без `--approve`
- **THEN** вызов отклонён, в stderr — строка решения `codelab: permission "<title>": reject_once (policy)` (формат cli-headless, SJ-11), файл не изменён

#### Scenario: Журнал дописан при SIGTERM
- **WHEN** во время хода встроенного агента процессу `codelab -p` приходит `SIGTERM`
- **THEN** код выхода `143`, журнал сессии в `$CODELAB_HOME/sessions` содержит итоговую запись хода со `stopReason: aborted` (итог хода в ACP — `cancelled`)

#### Scenario: Второй сигнал при зависшем dispose
- **WHEN** после первого `SIGTERM` `dispose` встроенного агента не завершается, и процессу приходит второй `SIGTERM`
- **THEN** процесс завершается сразу с кодом `143`, не дожидаясь `dispose`

#### Scenario: Отладка секретов
- **WHEN** запускается `codelab -a embedded --debug-secrets -p hi` без `--verbose` с ключом провайдера в `CODELAB_SECRET_CODELAB_P`
- **THEN** stderr содержит событие `secrets.lookup` с именем `codelab/p` и источником `env`, но не значение ключа и не другие события лога агента; stdout содержит только ответ

#### Scenario: Без --debug-secrets лог агента молчит
- **WHEN** запускается `codelab -a embedded -p hi` без `--verbose` и без `--debug-secrets`
- **THEN** stderr не содержит ни `secrets.lookup`, ни других событий лога встроенного агента

### Requirement: Подкоманды codelab provider и codelab mcp
`codelab provider add|list|remove` и `codelab mcp add|list|remove` SHALL вызывать общие `ProviderCommands` и `McpServerCommands` через `package:codelab_setup/io.dart` (только из `lib/src/run.dart`). Вывод, коды выхода и записанные байты SHALL совпадать с `codelab-agent provider|mcp` (design.md change `add-config-writer-and-reload`, D6). Флаги подключения и запроса вместе с `provider` и `mcp` — ошибка использования `64`, как у `codelab config`.

**`cwd`.** `provider list` и `mcp list` SHALL принимать `--cwd` подкоманды; порядок — `--cwd` подкоманды, общий `-C`/`--cwd`, текущий каталог. У `provider add|remove` и `mcp add|remove` `--cwd` подкоманды нет: папка — общий `-C`/`--cwd`, иначе текущий каталог.

**Ошибки использования** (код `64`, справка команды в stderr, stdout пуст); присланные слова argv НЕ SHALL цитироваться — среди них мог оказаться ключ или значение заголовка:
- неизвестная подкоманда или лишние позиционные аргументы — `codelab: unknown provider arguments (<n>)` (`… mcp …`), где `<n>` — число лишних слов; текст совпадает с `codelab-agent`, кроме имени бинаря;
- ошибка разбора аргументов (неизвестный флаг, флаг без значения) — `codelab: invalid arguments for provider` (`… mcp`).

`codelab provider add` без клиентских флагов и с полным набором флагов ядра SHALL вести себя как `codelab-agent provider add`. Клиент добавляет (design.md change `add-provider-setup-ui`, D15; spec client-agent-setup «Мастер провайдера»):
- **мастер на TTY.** Без клиентских флагов и без единого флага ядра (`--kind`, `--base-url`, `--model`, `--context-window`, `--api-key-secret`, `--api-key-env`, `--api-key-stdin`, `--default`; `--local`, `--project` и id к ним не относятся), когда stdin и stdout — терминал, SHALL запускаться интерактивный мастер `ProviderSetupFlow`: выбор пресета, адрес, ключ (скрытый ввод, как `codelab secret set`), проверка `/models`, модель, сводка `Provider "<id>" … ? Save? [Y/n]` (артборд `CliSetup`). Вариант «Store in <backend> as "codelab/<id>"» SHALL предлагаться только при записываемом бэкенде, иначе SHALL печататься причина бэкенда. Заголовки отказов проверки — как в app (`Key rejected (<код>)`, `Server unreachable`, `Timed out after 10 s`, `TLS error`, `Unexpected response (<код>)`, `Model list not found (404)`), строка `GET … → <код> · <n> ms` не печатается (design.md D24); ошибка окна контекста — `Context window must be a positive number.`. С `--project` мастер не запускается: `codelab: --project is not supported by the provider wizard; use --local or the user config`, код `64`. Ctrl+C — код `130`, файлы не изменены. После записи — `Saved provider "<id>". Models are available in /model.`;
- **клиентские флаги** `--preset <id>`, `--skip-check`, `--yes` SHALL проводить тот же автомат без вопросов, событиями из флагов ядра (design.md D15, решение Q13). Без `--preset` пресет SHALL выбираться по `--kind`: `openai-compatible` → `custom-openai`, `anthropic` → `custom-anthropic`. Проверка `/models` SHALL выполняться до записи всегда; `--skip-check` разрешает запись только при отказе `unreachable` или `timeout`, прочие отказы и отказ без `--skip-check` — код `1` и `codelab: provider check failed: <kind> (<scheme://host:port>)`, файлы не изменены (SETUP-4). Ошибки использования (код `64`, справка `provider`, значения не цитируются):
  - недостающее значение — `codelab: missing required options: <флаги>`;
  - неизвестный `--preset` — `codelab: unknown --preset; use openai, anthropic, openrouter, ollama, custom-openai or custom-anthropic`; неизвестный `--kind` без `--preset` — `codelab: unknown --kind; use openai-compatible or anthropic`; `--context-window` не целое положительное — `codelab: --context-window: expected a positive whole number`; `--kind` другого вида, чем пресет, — `codelab: --kind does not match --preset`;
  - `--kind gemini` — `codelab: --kind gemini is not supported with --preset, --yes or --skip-check; use the core flags only`; `--api-key-secret` — `codelab: --api-key-secret is not supported with --preset, --yes or --skip-check; use --api-key-stdin or --api-key-env`; `--project` — `codelab: --project is not supported with --preset, --yes or --skip-check; use --local or the user config`;
  - `http://` к нелокальному хосту (в том числе с `--yes`, SETUP-10) — `codelab: --base-url sends the key unencrypted to <host>; use https, or run "codelab provider add" on a terminal to confirm`;
  - без `--yes` и без терминала — `codelab: provider add needs --yes without a terminal`; без `--yes` на терминале — сводка и `? Save? [Y/n]`.

  Успех — `Saved provider "<id>". Restart codelab to use its models.` для провайдера с ключом и `Saved provider "<id>". Models are available in /model.` без ключа (Q17), код `0`. Ключ не принят (в том числе после подтверждения записи: секрет появился в хранилище или хранилище отказало) или запись не удалась — `codelab: provider add failed: <причина без значений>`, код `1`, файлы не изменены (созданный секрет откатан, D9);
- с флагами ядра без клиентских флагов (полный или неполный набор, на TTY или нет) и без флагов без TTY — `ProviderCommands.add` ядра без изменений, неполный набор — ошибка использования `64`, как раньше. Ключ `--api-key-stdin` SHALL читаться скрытым вводом `StdinSecretInput`, как у `codelab secret set`. Значение ключа НЕ SHALL попадать в stdout, `profiles.json`, `cli_history` и лог CLI.

Справка `codelab --help` SHALL содержать строки `codelab provider add|list|remove` и `codelab mcp add|list|remove`. Агентская команда `/mcp` в REPL доступна по своему имени, а агентская `/config` — как `/agent:config`, потому что клиентская `/config` имеет приоритет (требование «Slash-меню и клиентские команды»).

#### Scenario: provider list
- **WHEN** `secrets.backend: file`, конфиг задаёт провайдера `gw` с `api_key_secret: codelab/gw`, секрет сохранён, и запускается `codelab provider list`
- **THEN** первая строка — `Secrets: file`, строка `gw` содержит `secret codelab/gw: found` и не содержит значения; вывод совпадает с `codelab-agent provider list`

#### Scenario: mcp add и remove
- **WHEN** запускается `codelab mcp add docs --type stdio --command docs-mcp --arg --stdio`, затем `codelab mcp list`, затем `codelab mcp remove docs`
- **THEN** первый — код `0` и элемент `docs` в конце `mcp.servers`, второй печатает `docs`, `stdio`, `user`, `enabled`, третий удаляет элемент; комментарии файла сохранены

#### Scenario: provider add без флагов без TTY
- **WHEN** запускается `codelab provider add gw` со stdin из pipe
- **THEN** код `64`, одна строка stderr называет `--kind`, `--model` и `--context-window`, файлы не изменены

#### Scenario: Мастер provider add на TTY
- **WHEN** в PTY запускается `codelab provider add` против `config.yaml` с комментариями, пользователь выбирает «Custom OpenAI-compatible», вводит адрес тестового сервера без ключа, выбирает модель из списка и подтверждает
- **THEN** код `0`, `config.yaml` совпадает с golden `provider_add_config.yaml` (комментарии и порядок сохранены), stdout содержит `Saved provider "local-<port>"`

#### Scenario: Флаги без пропуска проверки
- **WHEN** запускается `codelab provider add gw --preset openai --base-url http://127.0.0.1:<закрытый порт>/v1 --model m --context-window 8000 --api-key-env GW_KEY --yes`
- **THEN** код `1`, stderr содержит `provider check failed: unreachable (http://127.0.0.1:<порт>)`, `config.yaml` не изменён

#### Scenario: Неполный набор флагов ядра на TTY
- **WHEN** в PTY запускается `codelab provider add gw --kind openai-compatible`
- **THEN** вопросов нет, код, stdout и stderr побайтово совпадают с `codelab-agent provider add gw --kind openai-compatible`, файлы не изменены

#### Scenario: --yes не подтверждает http к нелокальному хосту
- **WHEN** запускается `codelab provider add gw --preset custom-openai --base-url http://gw.example:8080/v1 --model m --context-window 8000 --yes`
- **THEN** код `64`, stderr содержит `codelab: --base-url sends the key unencrypted to gw.example`, запроса к `/models` нет, `config.yaml` не изменён

#### Scenario: Ключ мастера не утекает
- **WHEN** в мастере на TTY при `secrets.backend: file` вводится ключ `sk-test-leak-0123456789`
- **THEN** ключ не отображается на экране, `config.yaml` содержит только `api_key_secret: codelab/<id>`, а stdout, stderr, `cli_history` и лог CLI не содержат маркера

#### Scenario: Неизвестная подкоманда provider не цитируется
- **WHEN** запускаются `codelab provider frob` и `codelab-agent provider frob`
- **THEN** у обоих код `64`, stdout пуст, stderr содержит `unknown provider arguments (1)` и справку `provider`, не содержит `frob`

#### Scenario: --cwd у provider list и mcp list
- **WHEN** запускается `codelab -C <a> mcp list --cwd <b>`, где сервер `docs` задан только в `<b>/.codelab/config.local.yaml` доверенного проекта
- **THEN** код `0`, stdout содержит строку `docs` со слоем `local`; вывод совпадает с `codelab-agent mcp list --cwd <b>`

### Requirement: Флаги stdin у codelab mcp add
`codelab mcp add` SHALL разбирать флаги `--header-stdin <Name>`, `--header-scheme <Scheme>` и `--env-stdin <NAME>` и передавать их общей реализации `McpServerCommands` через `package:codelab_setup/io.dart` (capability `agent-configuration`, «Значение заголовка или переменной mcp add из stdin»; design.md change `add-config-literal-secrets-and-migrate`, D11). stdout, stderr и код выхода SHALL совпадать с `codelab-agent mcp add` при одном окружении и одном stdin. Справка `mcp` SHALL перечислять эти флаги. stdin SHALL читаться только при одном из флагов `-stdin`.

#### Scenario: Совпадение с бинарём агента
- **WHEN** `codelab mcp add gh --type http --url https://h --header-stdin Authorization --header-scheme Bearer` и та же команда `codelab-agent` запускаются с одним `CODELAB_HOME` (`secrets.backend: file`) и одним значением в stdin
- **THEN** коды `0`, stdout совпадает байт в байт, байты записанного `config.yaml` совпадают, значение не напечатано

### Requirement: Мастер первого запуска CLI
Когда CLI запускает встроенного агента (без `--agent`, `-a embedded`, `-a default`) в интерактивном режиме (REPL или `--ui tui`), а stdin и stdout — терминал, точка сборки режимов `run.dart` SHALL до запуска агента вычислять `checkProviderReadiness` (spec client-agent-setup «Готовность провайдера»; design.md change `add-provider-setup-ui`, D16):
- `ProviderReady` — обычный старт;
- `ConfigBroken` — мастер НЕ SHALL запускаться и файл НЕ SHALL переписываться; старт идёт прежним путём (код `64` и проблемы конфига в stderr);
- `NoProviderConfigured` — текст `No model provider is configured for the embedded agent.` и `Let's set one up. Press Ctrl+C to quit; run "codelab provider add" later to change it.`, затем мастер с целью `user` и `makeDefault: true`. После записи — `Saved provider "<id>". Starting the embedded agent…` и обычный старт; Ctrl+C или отмена — код `130`, файлы не изменены;
- `ProviderKeyMissing` — мастер НЕ SHALL запускаться и конфиг НЕ SHALL меняться (решение Q12 design.md, D16):
  - ссылка `secret <имя>` и записываемый бэкенд — вопрос `Store a key for "<id>" in <backend>? [Y/n]`; при «да» — скрытый ввод `? API key ›` (пустое значение — `Enter the API key.` и ввод снова) и запись только секрета `<имя>`: успех — `Saved the key as "<имя>" in <backend>. Starting the embedded agent…`, отказ хранилища — `Could not store the key: <reason>`; при «нет» — `Starting without a key for "<id>". Store it later with: codelab secret set <имя>`;
  - ссылка `secret <имя>` и бэкенд только для чтения — `No writable secret store (<reason>). Set <CODELAB_SECRET_…> or the provider's api_key_env variable.`;
  - ссылка `env <VAR>` — `The key for "<id>" is read from <VAR>, which is not set. Set it and restart codelab.`;
  - после любой из этих строк — обычный старт; Ctrl+C на вопросе или в поле — код `130`, ничего не записано.

Если мастер `NoProviderConfigured` не смог записать провайдера, CLI SHALL печатать `codelab: provider setup failed: <причина без значений>` и продолжать старт прежним путём (код `64` и проблема конфига от встроенного агента).

Без TTY, в `-p` и для внешних агентов (`-a stdio:…`, `-a ws://…`, `-a <id>`) мастер НЕ SHALL запускаться, и поведение SHALL оставаться прежним (решение Q4 design.md).

#### Scenario: Первый запуск в PTY
- **WHEN** в PTY с пустым временным `CODELAB_HOME` и тестовым хранилищем секретов запускается `codelab`, пользователь выбирает «Custom OpenAI-compatible» с адресом тестового сервера, вводит ключ и выбирает модель
- **THEN** `config.yaml` содержит `api_key_secret`, ключ есть только в тестовом хранилище, REPL стартует и выполняет ход на scripted-провайдере

#### Scenario: Без TTY мастера нет
- **WHEN** `codelab -p hi` запускается с пустым временным `CODELAB_HOME`
- **THEN** ни одного вопроса, код и stderr — как в сценарии «Без профиля и без конфига» требования «Профили подключения CLI»

#### Scenario: Сломанный конфиг не переписывается
- **WHEN** в PTY запускается `codelab`, а `config.yaml` содержит `budget.max_steps: 0`
- **THEN** мастер не запускается, код `64`, stderr называет `budget.max_steps`, файл не изменён

#### Scenario: Ключ провайдера отсутствует
- **WHEN** в PTY при `secrets.backend: file` конфиг задаёт провайдера `gw` с моделью и `api_key_secret: codelab/gw`, секрета нет, запускается `codelab`, пользователь отвечает Enter и вводит `sk-test-leak-0123456789`
- **THEN** stdout содержит `Saved the key as "codelab/gw" in file. Starting the embedded agent…`, секрет `codelab/gw` сохранён, `config.yaml` побайтово не изменён, REPL стартует; ни экран, ни `cli_history` не содержат маркера

#### Scenario: Ключ из незаданной переменной
- **WHEN** в PTY конфиг задаёт провайдера `gw` с моделью и `api_key_env: GW_KEY`, переменная не задана, и запускается `codelab`
- **THEN** stdout содержит `The key for "gw" is read from GW_KEY, which is not set. Set it and restart codelab.`, вопроса нет, REPL стартует, конфиг не изменён

#### Scenario: Внешний агент
- **WHEN** в PTY запускается `codelab -a 'stdio:<scripted-агент>'` с пустым `CODELAB_HOME`
- **THEN** мастер не запускается, REPL подключается к внешнему агенту

### Requirement: Команды /provider и /settings в REPL и TUI
Клиентские команды `/provider add|list|remove [<id>]` SHALL вызывать те же обработчики, что `codelab provider add|list|remove`. В построчном REPL `/provider add`, пока идёт ход, SHALL печатать `Finish or cancel the current turn first (Ctrl+C), then run /provider add.` и не открывать мастер; без терминала — `/provider add needs a terminal; run "codelab provider add" with flags instead.` Ctrl+C и Esc в мастере REPL SHALL закрывать только мастер (`Provider setup cancelled.`), не завершая REPL; во время записи они игнорируются (решение Q14 design.md, D17). Порт команд собирает `run.dart`; правило «`codelab_setup/io.dart` только из `run.dart`» не меняется (design.md change `add-provider-setup-ui`, D17). После записи провайдера без ключа встроенный агент сам перечитывает конфиг, и `/model` показывает новую модель без перезапуска; CLI печатает `Saved provider "<id>". Models are available in /model.`. Провайдер с ключом (`api_key_secret` или `api_key_env`) агент применяет только после перезапуска (agent-configuration, правило перечитывания R0-4), поэтому CLI SHALL печатать `Saved provider "<id>". Restart codelab to use its models.` и НЕ SHALL обещать модель в `/model` (решение Q17 design.md).

**Мастер `/provider add`** SHALL идти на автомате `ProviderSetupFlow`, что и `codelab provider add`:
- в построчном REPL — вопросами терминала;
- в `--ui tui` — модальным экраном TUI с шагами и текстами артборда `CliSetup` (решение пользователя Q7).

В экране TUI:
- ключ SHALL отображаться маской `*`. Ctrl+R показывает и снова прячет значение, Ctrl+U очищает поле;
- значение ключа НЕ SHALL попадать в строки кадра (кроме показа по Ctrl+R в поле ключа), историю композера, `cli_history`, строку статуса и лог CLI;
- буфер поля SHALL очищаться после отправки шага, при отмене и закрытии экрана;
- пока экран открыт, клавиши SHALL получать только он: Enter НЕ SHALL отправлять промпт, Esc SHALL отменять мастер, а не ход. Во время записи Esc SHALL быть заблокирован;
- клавиши зоны одобрения НЕ SHALL обрабатываться. Пришедший запрос разрешения SHALL показываться в строке статуса и отвечаться только после закрытия экрана.

**`/settings`** (U-19) SHALL работать по ключам `SettingsRegistry` со `scope: shared` (решение пользователя Q6):
- **в REPL:**
  - `/settings` — список `key value source` по секциям реестра (`source`: `default`, `user`, `project`, `local`, `config` — файл `CODELAB_CONFIG`/`--config`, `env` — переменная окружения); ключ с источником `config` или `env`, а также с источником `local` или `project` у профиля без цели `projectLocal` (stdio-агент без «Run in the project folder») НЕ SHALL редактироваться: `<key> is set by <config|env|local|project>; it cannot be changed here.` (в TUI явный `ctrl+u` пишет в `user`); строка, значение которой замаскировано (литеральный секрет, в том числе в элементе списка), НЕ SHALL ни записываться, ни сбрасываться (`--reset`, `r`): `Use codelab secret set <name>`; исключение записи — `codelab: <key>: write failed (<тип>)` без текста исключения, а несостоявшееся перечитывание после записи — хвост ` (could not reload the config)` у строки исхода (решение Q15 design.md, D17); `trusted_projects` SHALL показываться в списке, но любая запись и сброс SHALL печатать `trusted_projects is a trust boundary; it cannot be changed here.` и НЕ SHALL писать конфиг: граница доверия меняется только явным доверием проекта (решение пользователя 2026-11-06);
  - `/settings <key>` — пикер значений для `enumeration` и `bool`, для остальных типов — подсказка формата;
  - `/settings <key> <value>` — запись в слой `user`, с `--local` — в `projectLocal` текущей папки, если у настроек профиля есть эта цель (встроенный агент; stdio-агент `codelab-agent` — только при «Run in the project folder»), иначе `This agent has no project-local config; run without --local.` без записи; пути и окружение — агента профиля (`CODELAB_HOME` из `env` профиля, файл `--config` — источник `config`, design.md D5, D17); разбор — как у `codelab config set`; после записи — `Updated <key> in <path>`, ошибка разбора — `<key>: expected <expected>` без значения;
  - `/settings <key> --reset` — удаление ключа из этого слоя: `Removed <key> from <path>`, ключа в слое нет — `<key> is not set in <path>`;
  - неизвестный ключ или ключ не `scope: shared` — `Unknown setting <key>. Run /settings to list them.`; конфликт записи — `The config file changed; run the command again.`;
- **в `--ui tui`** — полноэкранный экран по артборду `CliSettings`:
  - шапка с путями слоёв, столбец разделов, таблица `key · value · source`, строка-подсказка, полоса клавиш `↑↓ move · enter edit · ←→ choose · tab section · r reset · esc close`;
  - разделы — секции реестра, строки — только ключи реестра со `scope: shared` (разделов артборда без ключей реестра нет, design.md D17, D24);
  - значение по умолчанию записывается в слой, где ключ определён, если он редактируемый, иначе в `user`; `ctrl+u` записывает в `user`;
  - ключ, заданный проектным `<cwd>/.codelab/config.yaml`, SHALL записываться в `.codelab/config.local.yaml` с подсказкой об этом;
  - `r` удаляет ключ из редактируемого слоя;
  - ключи-карты (`map`, `mapList`) SHALL быть только для чтения: Enter показывает `Edit with codelab mcp add` для `mcp.servers` и `Edit <key> in the config file or with codelab config set` для прочих, `r` удаляет ключ из редактируемого слоя; списки (`stringList`, `pathList`) SHALL правиться в поле с разбором как у `codelab config set`;
- **в обоих режимах:**
  - ключи `secret: true` и типа `secretName` НЕ SHALL редактироваться: `Use codelab secret set <name>`;
  - после записи ключа `restartRequired` — пометка `(applies after restart)`; в REPL — в конце строки `Updated …`/`Removed …`.

Для удалённого и стороннего агента `/provider add|remove` и запись `/settings` SHALL печатать `Provider settings are read-only for a remote agent. Run "codelab provider add" on the agent host.` (для стороннего — `… are managed by <agentName>.`) и НЕ SHALL писать конфиг (SETUP-2). Экран `/settings` TUI в этом случае открывается только для чтения. Слой 3 `/settings` и `/provider` НЕ SHALL писать (SETUP-3).

#### Scenario: Изменение настройки
- **WHEN** в REPL встроенного агента выполняется `/settings agent.effort high`, затем `/settings`
- **THEN** печатается `Updated agent.effort in <home>/config.yaml`, `~/.codelab/config.yaml` содержит `agent.effort: high` с сохранёнными комментариями, список показывает `agent.effort high user`

#### Scenario: /provider add во время хода
- **WHEN** в REPL идёт ход, и пользователь вводит `/provider add`
- **THEN** печатается `Finish or cancel the current turn first (Ctrl+C), then run /provider add.`, вопросов мастера нет, ход продолжается

#### Scenario: trusted_projects не редактируется
- **WHEN** в REPL встроенного агента выполняются `/settings`, затем `/settings trusted_projects '["/tmp/x"]'` и `/settings trusted_projects --reset`
- **THEN** список содержит строку `trusted_projects` с текущим значением и источником; обе команды печатают `trusted_projects is a trust boundary; it cannot be changed here.`, `config.yaml` побайтово не изменён

#### Scenario: Секретный ключ не редактируется
- **WHEN** выполняется `/settings providers.openai.api_key_secret x`
- **THEN** печатается `Use codelab secret set <name>`, конфиг не изменён

#### Scenario: Удалённый агент
- **WHEN** REPL подключён к `ws://` scripted-агенту, и выполняются `/provider add` и `/settings agent.effort high`
- **THEN** обе команды печатают строку только для чтения, локальный `config.yaml` не изменён

#### Scenario: Мастер в TUI
- **WHEN** в PTY с `--ui tui`, `secrets.backend: file` и тестовым сервером `/models` пользователь вводит `/provider add`, выбирает «Custom OpenAI-compatible», вводит адрес, ключ `sk-test-leak-0123456789` и модель из списка и подтверждает
- **THEN** `config.yaml` содержит `api_key_secret: codelab/<id>` без маркера, секрет сохранён; ни один кадр экрана, `cli_history` и лог CLI не содержат маркера, поле ключа показывает `*`; транскрипт содержит `Saved provider "<id>". Restart codelab to use its models.`

#### Scenario: Esc в мастере TUI не отменяет ход
- **WHEN** во время хода в `--ui tui` открыт мастер `/provider add`, и пользователь нажимает Enter на пустом поле и затем Esc
- **THEN** промпт не отправлен, мастер закрыт без записи, ход продолжается

#### Scenario: Одобрение при открытом мастере
- **WHEN** в `--ui tui` открыт мастер, и агент присылает `session/request_permission`
- **THEN** строка статуса показывает ожидающее одобрение, клавиши `y`/`n` вводятся в поле мастера и не отвечают на запрос; после закрытия мастера зона одобрения показывает запрос

#### Scenario: Экран настроек в TUI
- **WHEN** в `--ui tui` выполняется `/settings`, пользователь выбирает `permissions.mode`, стрелками меняет значение на `ask` и нажимает Enter
- **THEN** экран показывает разделы реестра без Display, Input и Updates, `~/.codelab/config.yaml` содержит `permissions.mode: ask`, строка показывает `user` и пометку `(applies after restart)`

#### Scenario: Карта на экране настроек TUI
- **WHEN** в `--ui tui` на экране `/settings` пользователь выбирает строку `mcp.servers` и нажимает Enter
- **THEN** поле правки не открывается, строка-подсказка показывает `Edit with codelab mcp add`, `config.yaml` не изменён

#### Scenario: Ключ проектного слоя в TUI
- **WHEN** `budget.max_steps` задан в `<cwd>/.codelab/config.yaml` доверенного проекта, и пользователь меняет его на экране `/settings` в TUI
- **THEN** значение записано в `<cwd>/.codelab/config.local.yaml`, проектный файл не изменён; с `ctrl+u` — в `~/.codelab/config.yaml`

### Requirement: Отказ подключения из-за токена
Если WebSocket-агент отклоняет рукопожатие со статусом 401 или 403, CLI SHALL печатать в stderr причину `the agent rejected the token (HTTP <код>)`, если токен был отправлен, и `the agent requires a token (HTTP <код>)`, если нет (нет ссылки, переменная не задана, у `secret:` нет значения), вместо общего текста сбоя транспорта (design.md change `add-provider-setup-ui`, D25; spec acp-client-kit «Отказ рукопожатия из-за токена»). Причина SHALL ставиться после того же префикса, что у остальных ошибок подключения этого места:
- `codelab: cannot start the agent <адрес>: <причина>.` — старт REPL, `--ui tui` и `-p`;
- `codelab: cannot connect to <адрес>: <причина>.` — после `/profile`;
- `codelab: cannot reconnect: <причина>.` — `/reconnect` и переподключение.

`<адрес>` — по требованию «Адрес WebSocket-профиля в выводе CLI». Остальные ошибки подключения SHALL печататься как раньше, код выхода `-p` при отказе подключения SHALL оставаться `1`. Значение токена, ссылка и имя переменной НЕ SHALL попадать в stdout, stderr и лог CLI.

#### Scenario: Отправленный токен отклонён
- **WHEN** `CODELAB_AGENT_TOKEN=sk-test-leak-0123456789`, и запускается `codelab -a ws://127.0.0.1:<порт> -p hi` против сервера, отвечающего на рукопожатие `401`
- **THEN** код `1`, stderr содержит `codelab: cannot start the agent ws://127.0.0.1:<порт>: the agent rejected the token (HTTP 401).`, ни stdout, ни stderr не содержат маркера

#### Scenario: Токена нет
- **WHEN** переменная `CODELAB_AGENT_TOKEN` не задана (или профиль ссылается на `secret:` без значения), и запускается `codelab -a ws://127.0.0.1:<порт> -p hi` против сервера, отвечающего `403`
- **THEN** код `1`, stderr содержит `cannot start the agent ws://127.0.0.1:<порт>: the agent requires a token (HTTP 403).`

#### Scenario: Отказ после /profile в REPL
- **WHEN** в REPL выполняется `/profile devbox`, а сервер профиля `devbox` отвечает `401` на отправленный токен
- **THEN** печатается `codelab: cannot connect to <origin devbox>: the agent rejected the token (HTTP 401).`, REPL продолжает работу

#### Scenario: Отказ при переподключении
- **WHEN** в REPL выполняется `/reconnect`, а сервер отвечает `401` на отправленный токен
- **THEN** печатается `codelab: cannot reconnect: the agent rejected the token (HTTP 401).`

#### Scenario: Прочие ошибки без изменений
- **WHEN** сервер отвечает на рукопожатие `500` или порт закрыт
- **THEN** stderr содержит прежнюю строку того же префикса без слов о токене, код `-p` — `1`

### Requirement: Адрес WebSocket-профиля в выводе CLI
Везде, где CLI называет WebSocket-профиль в выводе (`describeProfile`: строки ошибок подключения, `--verbose`, `/profile`), адрес SHALL печататься только origin-ом `scheme://host:port` — без пути, query, fragment и userinfo, как `profileOrigin` у codelab-app (решение оркестратора, ревью `feature/ws-unauthorized-message`; design.md change `add-provider-setup-ui`, D25). Это видимое изменение вывода: путь (например, `/acp`) больше не печатается. Stdio-профили описываются как раньше.

#### Scenario: Query и userinfo не выводятся
- **WHEN** запускается `codelab -a 'ws://user:pass@127.0.0.1:<порт>/acp?t=sk-test-leak-0123456789#x' -p hi` против закрытого порта
- **THEN** stderr содержит `ws://127.0.0.1:<порт>` и не содержит `/acp`, `t=`, маркера, `user`, `pass` и `#x`

### Requirement: Аргументы stdio-профиля в выводе CLI
CLI НЕ SHALL печатать значения аргументов stdio-профиля (`StdioProfile.args`) ни в stdout, ни в stderr: пользователь может вписать в аргументы секрет (`--api-key sk-…` или позиционным аргументом), а маскирование по шаблонам такие формы не распознаёт (design.md change `redact-cli-stdio-profile-args`, D1). Правило одно для профиля из `--agent stdio:…`, из `/profile stdio:…` и из `profiles.json`, для REPL, `--ui tui`, `-p` (в том числе с `--verbose`), подкоманды `profiles` и `codelab test-scenario`. Команда (`StdioProfile.command`) SHALL печататься как есть; вместо аргументов SHALL печататься их число `N` в форме `1 argument` при `N = 1` и `<N> arguments` иначе (D2):
- описание профиля в ошибке запуска и подключения — `"<command>"` при `N = 0` и `"<command>" with <N> argument(s)` иначе: `codelab: cannot start the agent "<command>" with <N> arguments: <причина>` и `codelab: cannot connect to "<command>" with <N> arguments: <причина>`;
- `/profile` без аргументов — `Profile <id> (<label>): stdio <описание>` с тем же описанием. Скобки с `label` SHALL опускаться, если `label` пуст или начинается с `stdio:`, `ws://` или `wss://` (значение `--agent`, из которого создан профиль), — то же правило, что заголовок профиля в codelab-app (spec app-settings «Список профилей на странице «Connection»»; D3);
- `codelab profiles list` — `<id>  stdio: <command>` при `N = 0` и `<id>  stdio: <command> (<N> argument(s))` иначе;
- `codelab profiles show` — строка `args: 0` при `N = 0` и `args: <N> (values hidden)` иначе; значения аргументов видны только в `$CODELAB_HOME/profiles.json`;
- ошибка разбора значения `stdio:…` — `Invalid agent command: <причина>.` (например, `Invalid agent command: no command.`), код `64`; значение `--agent` в тексте НЕ SHALL повторяться (D4);
- причина сбоя запуска процесса агента (в строках выше, в журнале `--verbose` и в строке `FAIL` драйвера фикстур) НЕ SHALL содержать аргументов: транспорт отдаёт ошибку запуска без них (spec agent-transports «Ошибка запуска stdio transport без аргументов»; D8), а драйвер фикстур печатает для ошибки запуска процесса только текст ОС (D9).

Значение `--agent`, которое CLI ищет как id профиля, может быть командной строкой с секретом, если пользователь забыл префикс `stdio:`. Поэтому тексты ошибок выбора профиля НЕ SHALL повторять это значение (D6): неизвестный профиль в `-a <value>` и `/profile <value>` — `Unknown agent profile. Run "codelab profiles list".` (код `64` вне REPL и TUI), неверное значение в `codelab profiles add <id> <value>` — `Invalid agent: use "stdio:<command> [args]", ws:// or wss://.` (код `64`, `profiles.json` не меняется).

Формат `profiles.json` и хранимые значения `args` и `label` НЕ SHALL меняться. Адрес WebSocket-профиля это требование не меняет (требование «Адрес WebSocket-профиля в выводе CLI»); правило скобок `label` в `/profile` общее для всех типов профилей (D3).

#### Scenario: Ошибка запуска без значений аргументов
- **WHEN** запускается `codelab -p hi --agent 'stdio:/nonexistent/agent --api-key sk-test-leak-0123456789 sk-test-leak-0123456789'`
- **THEN** код выхода `1`, stdout пуст, stderr содержит `codelab: cannot start the agent "/nonexistent/agent" with 3 arguments:` и не содержит `sk-test-leak-0123456789` и `--api-key`

#### Scenario: Ошибка запуска с --verbose
- **WHEN** запускается `codelab -p hi --verbose --agent 'stdio:/nonexistent/agent --api-key sk-test-leak-0123456789 sk-test-leak-0123456789'`
- **THEN** код выхода `1`; ни stdout, ни stderr (включая записи журнала с полем `cause`) не содержат `sk-test-leak-0123456789` и `--api-key`

#### Scenario: Ошибка запуска в --ui tui
- **WHEN** полноэкранный режим стартует с профилем, команда которого `/nonexistent/agent`, а аргументы — `--api-key`, `sk-test-leak-0123456789`, `sk-test-leak-0123456789`, и агент не запускается; затем в нём выполняется `/profile broken` для такого же профиля из `profiles.json`
- **THEN** строки `codelab: cannot start the agent "/nonexistent/agent" with 3 arguments:` и `codelab: cannot connect to "/nonexistent/agent" with 3 arguments:` не содержат `sk-test-leak-0123456789` и `--api-key`

#### Scenario: Подключение к другому профилю из REPL
- **WHEN** `profiles.json` содержит stdio-профиль `broken` с командой `/nonexistent/agent` и аргументами `--api-key`, `sk-test-leak-0123456789`, `sk-test-leak-0123456789`, и в REPL выполняется `/profile broken`
- **THEN** вывод содержит `codelab: cannot connect to "/nonexistent/agent" with 3 arguments:` и не содержит `sk-test-leak-0123456789`

#### Scenario: /profile без значений аргументов
- **WHEN** REPL запущен с `--agent 'stdio:my-agent --api-key sk-test-leak-0123456789 sk-test-leak-0123456789'`, и выполняется `/profile`
- **THEN** вывод содержит `Profile inline: stdio "my-agent" with 3 arguments`, не содержит `(stdio:` и `sk-test-leak-0123456789`

#### Scenario: /profile с заданным label
- **WHEN** текущий профиль — запись `profiles.json` `dev` с `label` `Dev agent`, командой `codelab-agent` и без аргументов, и выполняется `/profile`
- **THEN** вывод содержит `Profile dev (Dev agent): stdio "codelab-agent"`

#### Scenario: profiles list и show без значений аргументов
- **WHEN** `profiles.json` содержит stdio-профиль `dev` с командой `my-agent` и аргументами `--api-key`, `sk-test-leak-0123456789`, `sk-test-leak-0123456789`, и stdio-профиль `bare` с командой `bare-agent` без аргументов, и выполняются `codelab profiles list`, `codelab profiles show dev` и `codelab profiles show bare`
- **THEN** `list` печатает `dev   stdio: my-agent (3 arguments)` и `bare  stdio: bare-agent`; `show dev` печатает `command: my-agent` и `args: 3 (values hidden)`; `show bare` печатает `args: 0`; ни stdout, ни stderr трёх команд не содержат `sk-test-leak-0123456789`, `profiles.json` не изменён

#### Scenario: Ошибка разбора без значения --agent
- **WHEN** запускается `codelab -p hi --agent 'stdio:my-agent --api-key sk-test-leak-0123456789 sk-test-leak-0123456789 "oops'` (незакрытая кавычка)
- **THEN** код `64`, stdout пуст, stderr содержит `Invalid agent command: ` с причиной разбора и не содержит `sk-test-leak-0123456789`, агент не запускается

#### Scenario: Значение --agent без префикса stdio: не повторяется
- **WHEN** выполняются `codelab -p hi -a 'my-agent --api-key sk-test-leak-0123456789'`, `codelab -p hi -a sk-test-leak-0123456789` и `codelab profiles add dev 'my-agent --api-key sk-test-leak-0123456789'`
- **THEN** каждая команда завершается кодом `64` с пустым stdout; первые две пишут в stderr `Unknown agent profile. Run "codelab profiles list".`, третья — `Invalid agent: use "stdio:<command> [args]", ws:// or wss://.`; ни stderr, ни stdout не содержат `sk-test-leak-0123456789`, `profiles.json` не изменён, агент не запускается

