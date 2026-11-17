## ADDED Requirements

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

## MODIFIED Requirements

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
