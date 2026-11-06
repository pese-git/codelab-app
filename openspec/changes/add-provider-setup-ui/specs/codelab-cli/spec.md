## ADDED Requirements

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
Клиентские команды `/provider add|list|remove [<id>]` SHALL вызывать те же обработчики, что `codelab provider add|list|remove`. В построчном REPL `/provider add`, пока идёт ход, SHALL печатать `Finish or cancel the current turn first (Ctrl+C), then run /provider add.` и не открывать мастер; без терминала — `/provider add needs a terminal; run "codelab provider add" with flags instead.` Ctrl+C и Esc в мастере REPL SHALL закрывать только мастер (`Provider setup cancelled.`), не завершая REPL; во время записи они игнорируются (решение Q14 design.md, D17). Порт команд собирает `run.dart`; правило «`codelab_setup/io.dart` только из `run.dart`» не меняется (design.md change `add-provider-setup-ui`, D17). После записи встроенный агент сам перечитывает конфиг, и `/model` показывает новую модель без перезапуска.

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
  - `/settings` — список `key value source` по секциям реестра (`source`: `default`, `user`, `project`, `local`, `config` — файл `CODELAB_CONFIG`/`--config`, `env` — переменная окружения); ключ с источником `config` или `env` НЕ SHALL редактироваться: `<key> is set by <config|env>; it cannot be changed here.` (решение Q15 design.md, D17); `trusted_projects` SHALL показываться в списке, но любая запись и сброс SHALL печатать `trusted_projects is a trust boundary; it cannot be changed here.` и НЕ SHALL писать конфиг: граница доверия меняется только явным доверием проекта (решение пользователя 2026-11-06);
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
- **THEN** `config.yaml` содержит `api_key_secret: codelab/<id>` без маркера, секрет сохранён; ни один кадр экрана, `cli_history` и лог CLI не содержат маркера, поле ключа показывает `*`; `/model` показывает новую модель

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

  Успех — `Saved provider "<id>". Models are available in /model.`, код `0`. Ключ не принят (в том числе после подтверждения записи: секрет появился в хранилище или хранилище отказало) или запись не удалась — `codelab: provider add failed: <причина без значений>`, код `1`, файлы не изменены (созданный секрет откатан, D9);
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

