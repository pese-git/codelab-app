## MODIFIED Requirements

### Requirement: Профили подключения CLI
Значение `--agent` (`-a`) SHALL разбираться так:
- `embedded` или `default` — `EmbeddedProfile(hostProfile: 'embedded-cli')`: встроенный агент в процессе CLI (требование «Встроенный агент в CLI»); `default` — алиас `embedded` (design.md change `add-app-settings-shell`, D21). Для выбора агента запись из `profiles.json` НЕ SHALL использоваться. При `default` файл читается только ради предупреждения о старой записи `default`, и любая ошибка этого чтения SHALL игнорироваться. При `embedded` файл НЕ SHALL читаться;
- `stdio:<команда> [аргументы]` — `StdioProfile` с разбором аргументов как в shell (кавычки, экранирование);
- `ws://…` или `wss://…` — `WebSocketProfile` со ссылкой `tokenRef: env:CODELAB_AGENT_TOKEN`: токен читается из переменной `CODELAB_AGENT_TOKEN`;
- иначе — id профиля из `$CODELAB_HOME/profiles.json` (`CODELAB_HOME` по умолчанию — `~/.codelab`), хранимого `JsonFileProfileStore`.

Без `--agent` SHALL всегда использоваться встроенный агент, как с `-a embedded` (решение пользователя 2026-11-04; design.md change `add-app-settings-shell`, D21; заменяет D13, п. 1 change `add-embedded-agent-mode`). Правило одно для REPL, `--ui tui`, `-p` и `test-scenario` (D13, п. 7). Без `--agent` CLI НЕ SHALL читать `profiles.json`, поэтому битый файл не мешает запуску встроенного агента. О неявном выборе встроенного агента и о смене правила CLI НЕ SHALL печатать отдельной строки: выбранный профиль виден с `--verbose` и командой `/profile` (D13, п. 8; D21, п. 2). Битый `profiles.json` — не JSON или JSON неверной структуры — при `-a <id>` SHALL давать код `64` с причиной, а не тихий переход на встроенного агента и не необработанное исключение. Внешний агент выбирается явно: `-a stdio:…`, `-a ws://…` или `-a <id>`.

Id `embedded` и `default` зарезервированы (`reservedProfileIds` kit). Запись с id `default`, лежащая в `profiles.json` от прежней версии, SHALL игнорироваться: `profiles list` её не показывает, `profiles show default` печатает встроенный профиль. При `codelab profiles list`, `codelab profiles show default` и `-a default`, если такая запись есть, CLI SHALL печатать в stderr одно предупреждение `profile "default" in profiles.json is ignored: default is the built-in agent; remove it with codelab profiles remove default`. Команду, аргументы, URL и `env` записи предупреждение НЕ SHALL содержать. Файл автоматически НЕ SHALL перезаписываться, а `codelab profiles remove default` SHALL удалять запись. Подсказки о смене правила выбора CLI НЕ SHALL печатать (D21, п. 2).

Токен WebSocket-профиля SHALL разрешать общий источник kit `ProfileSecretSource` по правилу `ProfileTokenRef` (design.md change `add-app-settings-shell`, D15). Ссылка `env:<NAME>` читает переменную окружения процесса для любого допустимого имени, поэтому профиль, созданный в codelab-app со ссылкой `env:DEVBOX_TOKEN`, работает в CLI. Пустая или отсутствующая переменная и ссылка другого вида дают подключение без токена, как раньше. Значение токена в stdout, stderr и журнал НЕ SHALL попадать. Значение ссылки не вида `env:` тоже НЕ SHALL выводиться: `codelab profiles show` печатает `token: unrecognized token reference (not supported in this version)`, а диагностика называет только id профиля.

Команда `codelab profiles list|show <id>|add <id> <значение --agent>|remove <id>` SHALL работать без запуска агента; значение токена в `profiles.json` НЕ SHALL записываться. Id нового профиля в `profiles add` SHALL проходить общее правило kit `isValidProfileId` (`^[a-z0-9][a-z0-9._-]{0,63}$`); нарушение — код `64` с текстом правила. Профили, сохранённые раньше с другими id (например, с заглавными буквами), SHALL читаться, показываться и выбираться `-a <id>` как прежде, а формат `profiles.json` НЕ SHALL меняться. `embedded` в `profiles add` — ни как id, ни как значение — SHALL давать код `64` и `embedded is built in; use --agent embedded`; `default` — так же, код `64` и `default is the built-in agent; use --agent embedded`. Ошибка подключения SHALL давать понятное сообщение в stderr и код `1` (U-06).

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
- **WHEN** выполняется `codelab profiles add py 'stdio:python -m "codelab agent" --stdio'`, затем `codelab profiles show py`
- **THEN** профиль хранит команду `python` и аргументы `-m`, `codelab agent`, `--stdio`

#### Scenario: Агент не запускается
- **WHEN** `--agent 'stdio:/nonexistent/agent'`
- **THEN** в stderr — сообщение об ошибке подключения с командой, код выхода `1`

#### Scenario: Токен из произвольной переменной
- **WHEN** `profiles.json` содержит WebSocket-профиль `devbox` с `tokenRef: env:DEVBOX_TOKEN`, переменная `DEVBOX_TOKEN` задана, и запускается `codelab -a devbox -p hi` против scripted-агента, требующего этот токен
- **THEN** агент принимает Bearer-токен, ход проходит, stdout и stderr не содержат значения токена

#### Scenario: Старые профили читаются как раньше
- **WHEN** `profiles.json` от прежней версии содержит профиль `Old` (WebSocket, `tokenRef: env:CODELAB_AGENT_TOKEN`), и выполняются `codelab profiles add Dev stdio:x` и `codelab -a Old -p hi`
- **THEN** первая команда завершается кодом `64` с текстом правила id и не меняет файл, а вторая выбирает профиль `Old` с токеном из `CODELAB_AGENT_TOKEN`

#### Scenario: Ссылка не вида env: не выводится
- **WHEN** `profiles.json` содержит WebSocket-профиль `devbox` с `tokenRef: sk-test-leak-0123456789`, и выполняются `codelab profiles show devbox` и `codelab -a devbox -p hi --verbose`
- **THEN** `show` печатает `token: unrecognized token reference (not supported in this version)`; подключение идёт без токена; ни stdout, ни stderr не содержат `sk-test-leak-0123456789`

#### Scenario: -a default при битом profiles.json
- **WHEN** `profiles.json` — не JSON, и запускается `codelab -a default -p hi` из тестовой точки входа со сценарием модели
- **THEN** ход проводит встроенный агент, код `0`, ошибки чтения файла и кода `64` нет
