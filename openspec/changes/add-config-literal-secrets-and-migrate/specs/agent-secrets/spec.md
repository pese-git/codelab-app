## MODIFIED Requirements

### Requirement: Ключ провайдера при запросе
Ключ провайдера SHALL разрешаться при первом запросе к провайдеру в `createRoutedStreamFunction`, а не при загрузке конфига (design.md, D4):
- `api_key_secret` — через `SecretResolver.secret`;
- `api_key_env` — через `SecretResolver.env`;
- `${secret:<name>}` в `providers.<id>.headers.*` — через `SecretResolver.secret`;
- литеральный `api_key` из файла конфига (R8-4; design.md change `add-config-literal-secrets-and-migrate`, D4) — как есть, без резолвера: `ProviderConfig.apiKey`; литерал длиной от 8 символов SHALL входить в `ProviderConfig.secrets` и вычищаться из текстов ошибок провайдера, более короткий — нет. Порог 8 действует только для литерального `api_key` из файла; ключи из хранилища и окружения SHALL вычищаться без порога;
- `api_key: ${VAR}` и `api_key: ${secret:<name>}` — ссылка, как в заголовках (R8-8): `${VAR}` раскрывается при загрузке, `${secret:<name>}` — через `SecretResolver.secret` при запросе.

Не-HTTP исключения транспорта (например, `FormatException`) SHALL попадать в текст ошибки хода только через `redactSecrets` или именем типа.

Ссылка `api_key_env`, `api_key_secret` или `${secret:…}`, чьё значение похоже на секрет (`literalSecretTag != null`), НЕ SHALL разрешаться: ошибка хода `auth` без HTTP-запроса с текстом `API key reference providers.<id>.<key> looks like a secret value, not a name; run: codelab secret migrate`; значение НЕ SHALL попадать в текст и в `secrets.lookup`.

Хост без `SecretResolver` ключ провайдера НЕ SHALL получать: ни из хранилища, ни прямым чтением окружения — кроме подстановки `${VAR}` в `api_key` и `headers`, которую раскрывает загрузка конфига (R8-8; design.md change `add-config-literal-secrets-and-migrate`, D4). Ссылка тогда SHALL давать ошибку хода класса `auth` без HTTP-запроса: `API key variable <VAR> cannot be read: the host has no secret resolver` для `api_key_env`, `API key secret <name> cannot be read: the host has no secret resolver` для `api_key_secret`, `secret <name> cannot be read (providers.<id>.headers.<H>): the host has no secret resolver` для заголовка. Каждый хост, которому нужен ключ провайдера, SHALL передавать резолвер (настольные хосты — `openHostSecrets`, design.md D4, D15).

Ответы:
- `SecretMissing` для ключа SHALL давать ошибку хода класса `auth` без HTTP-запроса с текстом `API key secret <name> is not set. Run: codelab secret set <name>`;
- `SecretMissing` для заголовка SHALL давать ошибку `auth` с текстом `secret <name> is not set (providers.<id>.headers.<H>). Run: codelab secret set <name>`;
- `SecretUnavailable` SHALL давать ошибку `auth` с текстом, который называет бэкенд, причину и переменную `SecretNames.envOverride(name)`.

После неудачи следующий запрос SHALL разрешать ссылку заново. Цепочка провайдера с найденными значениями SHALL кэшироваться на процесс. В `ProviderConfig.secrets` SHALL входить и собранные строки (ключ, значение заголовка вроде `Bearer <v>`), и сырые найденные значения каждой ссылки — для вычистки текстов ошибок провайдера. Отмена хода во время ожидания хранилища SHALL завершать поток ошибкой класса `aborted` (`LlmErrorClass.aborted`, `StopReason.aborted`, LLM-7), не дожидаясь хранилища. Текст ошибки, журнал и лог НЕ SHALL содержать значение секрета.

#### Scenario: Ключ из хранилища
- **WHEN** провайдер `openai` задаёт `api_key_secret: codelab/openai`, хранилище содержит `sk-test-0123456789abcdef`, а сессия выбирает `openai/gpt-4o`
- **THEN** запрос к фейковому HTTP-клиенту несёт `Authorization: Bearer sk-test-0123456789abcdef`, хранилище прочитано один раз за два хода

#### Scenario: Секрет не задан
- **WHEN** провайдер задаёт `api_key_secret: codelab/openai`, хранилище пусто, переменной нет
- **THEN** ход завершается ошибкой `API key secret codelab/openai is not set. Run: codelab secret set codelab/openai` класса `auth`, HTTP-запроса нет; после записи секрета следующий ход выполняется без перезапуска

#### Scenario: Отмена во время ожидания хранилища
- **WHEN** `read` хранилища не завершается, а ход отменяется через 100 мс
- **THEN** поток провайдера завершается ошибкой класса `aborted` (`StopReason.aborted`) не позже чем через 1 с после отмены, HTTP-запроса нет

#### Scenario: Хост без резолвера
- **WHEN** `createRoutedStreamFunction` вызван без `secrets`, провайдер задаёт `api_key_env: OPENAI_API_KEY`, а переменная задана в окружении процесса
- **THEN** ход завершается ошибкой `auth` `API key variable OPENAI_API_KEY cannot be read: the host has no secret resolver`, HTTP-запроса нет; то же для `api_key_secret: codelab/openai` с текстом `API key secret codelab/openai cannot be read: the host has no secret resolver`

#### Scenario: Сырое значение в теле ошибки
- **WHEN** провайдер задаёт `headers.Authorization: "Bearer ${secret:codelab/gw}"`, хранилище содержит `tok-test-raw-value`, а сервер отвечает `401` с телом, где есть только `tok-test-raw-value` без `Bearer `
- **THEN** текст ошибки хода класса `auth` не содержит `tok-test-raw-value`

#### Scenario: Ссылка-значение в заголовке провайдера
- **WHEN** провайдер `gw` задаёт `headers.X-Api-Key: "${secret:ghp_abcdefghijklmnopqrstuvwxyz0123456789}"`, и сессия делает ход его моделью
- **THEN** ход завершается ошибкой `auth` без HTTP-запроса с текстом `API key reference providers.gw.headers.X-Api-Key looks like a secret value, not a name; run: codelab secret migrate`; хранилище не вызывалось

#### Scenario: Короткий литеральный ключ
- **WHEN** `providers.local.api_key: ollama`, и сервер отвечает `401` с телом `ollama model not found`
- **THEN** текст ошибки хода содержит `ollama` без маркера

#### Scenario: Литеральный ключ в файле
- **WHEN** `config.yaml` задаёт `providers.p.api_key: sk-test-literal-0123456789`, а провайдер отвечает `401` с телом, содержащим этот ключ
- **THEN** запрос шёл с этим ключом без обращения к хранилищу; текст ошибки хода не содержит значения

### Requirement: Секреты MCP-серверов конфигурации
Значения `env.*` и `headers.*` MCP-сервера конфигурации с `${secret:<name>}` SHALL храниться в `CoreConfig` шаблоном из литералов и ссылок, а не строкой (design.md change `add-agent-secret-store`, D4). Раскрывать их SHALL коннектор перед каждой попыткой подключения сервера — первой и повторной — функцией раскрытия `McpConnectRequest.expandSecrets` (`McpSecretExpander`), которую рантайм строит над `AgentCoreServices.secrets` при создании и загрузке сессии, в `AgentSession.setMcpServers` и при перезагрузке конфигурации (design.md change `add-config-writer-and-reload`, D11). Раскрытая копия SHALL жить только в одной попытке; значение секрета НЕ SHALL храниться в коннекторе между попытками, поэтому после `SecretResolver.invalidate()` следующая попытка берёт новое значение.
Ссылка, чьё имя похоже на значение секрета (`literalSecretTag(name) != null`; capability `agent-configuration`, «Литеральные секреты в файле конфига»), хранится в шаблоне маркером и НЕ SHALL разрешаться: функция раскрытия SHALL бросать `McpSecretsException` с текстом `secret reference mcp.servers[<server>].<key> looks like a secret value, not a name; run: codelab secret migrate`, сервер SHALL переходить в `failed` с этим текстом без значения, хранилище НЕ SHALL вызываться (design.md change `add-config-literal-secrets-and-migrate`, D4).


Сервер с ненайденным секретом НЕ SHALL подключаться: функция раскрытия бросает `McpSecretsException(reason)`, транспорт сервера не открывается, сервер SHALL оставаться в списке сессии в состоянии `failed` с `lastError` — `reason` — и повторяться по расписанию задержек (capability `agent-mcp-client`, «Переподключение и состояние серверов сессии»). На первом сбое SHALL писаться `mcp.server.failed {server, transport, reason}` с причиной `secret <name> is not set` или `secret <name> cannot be read: <backend> is unavailable` (имя секрета и бэкенд, никогда значение). Сессия создаётся без инструментов этого сервера (agent-runtime «MCP-серверы сессии», шаг 3).

`AgentSession.close()` или `AgentRuntime.dispose()` во время раскрытия SHALL отбрасывать попытку: транспорт не открывается, `mcp.server.failed` не пишется, таймера повтора нет, процессов серверов не остаётся. `createSession` / `loadSession`, прерванные `dispose()`, SHALL завершаться `CancelledException`.

Заголовки HTTP-сервера после раскрытия SHALL идти в порядке файла конфига. `${secret:…}` в серверах `session/new.mcpServers` SHALL оставаться литералом: функция раскрытия для них не вызывается. Литерал `$${secret:x}` SHALL давать строку `${secret:x}` без обращения к резолверу. Без `AgentCoreServices.secrets` ссылка SHALL давать сбой попытки с причиной `no secret store`.

#### Scenario: Заголовок из хранилища
- **WHEN** конфиг объявляет http-сервер `gh` с `headers.Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`, а хранилище содержит `tok-test-secret`
- **THEN** транспорт попытки получает заголовок `Bearer tok-test-secret`, а лог, журнал и `McpServerSummary` не содержат `tok-test-secret`

#### Scenario: Порядок заголовков сохраняется
- **WHEN** сервер `gh` задаёт заголовки `X-A: a`, `Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`, `X-B: b` в этом порядке, секрет найден
- **THEN** транспорт получает заголовки в порядке `X-A`, `Authorization`, `X-B`

#### Scenario: Закрытие во время раскрытия
- **WHEN** `read` хранилища для сервера `gh` не завершается, а рантайм получает `dispose()` во время `createSession` (или сессия — `close()` во время `setMcpServers`)
- **THEN** транспорт `gh` не открывался, записи `mcp.server.failed` для `gh` нет, таймера повтора нет, процессов серверов не осталось; `createSession` завершается `CancelledException`

#### Scenario: Ненайденный секрет MCP
- **WHEN** у сервера `gh` секрет не задан, а у сервера `docs` ссылок нет
- **THEN** сессия создаётся, `docs` подключён, `gh` в списке сессии в состоянии `failed` с `lastError` `secret codelab/mcp/gh/authorization is not set` без инструментов, лог `mcp.server.failed` с той же причиной

#### Scenario: Секрет появился после сбоя
- **WHEN** у сервера `gh` секрет не задан при создании сессии, а затем записан в хранилище
- **THEN** очередная попытка по расписанию раскрывает его заново и подключает `gh` без перезагрузки и перезапуска

#### Scenario: Ссылка от клиента ACP — литерал
- **WHEN** `session/new.mcpServers` содержит http-сервер с заголовком `${secret:codelab/openai}`
- **THEN** резолвер не вызывается, транспорт получает строку `${secret:codelab/openai}`

#### Scenario: Недоверенный проект не читает секреты
- **WHEN** `<cwd>/.codelab/config.yaml` недоверенного проекта объявляет сервер с `${secret:codelab/openai}`
- **THEN** сервер отброшен правилом доверия, резолвер не вызывается

#### Scenario: Ссылка-значение у MCP-сервера
- **WHEN** сервер `gh` задаёт `headers.Authorization: "Bearer ${secret:ghp_abcdefghijklmnopqrstuvwxyz0123456789}"`
- **THEN** сервер `failed` с текстом `secret reference mcp.servers[gh].headers.Authorization looks like a secret value, not a name; run: codelab secret migrate`, хранилище не вызывалось, ни лог, ни `lastError` не содержат значения


### Requirement: Подкоманды secret
`codelab secret set|delete|list|migrate` и `codelab-agent secret set|delete|list|migrate` SHALL использовать одну реализацию `SecretCommands` (`codelab_agent_io`); stdout, stderr и коды выхода, которые даёт `SecretCommands`, SHALL совпадать у двух бинарей (design.md, D8). Справка `secret` и сообщения разбора argv МОГУТ различаться: они называют свой бинарь. Подкоманды SHALL работать без запуска агента и без ACP. Бэкенд SHALL браться из `secrets.backend` пользовательского конфига и файла `CODELAB_CONFIG`; другие проблемы конфига НЕ SHALL мешать подкомандам `set`, `delete`, `list`; подкоманда `migrate` SHALL загружать конфиг полностью (требование «Подкоманда secret migrate»), потому что ей нужны находки всех слоёв. Если `CODELAB_CONFIG` недопустим (относительный путь или расширение не `.yaml`/`.yml` без учёта регистра — те же проверки, что у загрузчика), подкоманда SHALL писать в stderr `warning: CODELAB_CONFIG ignored: <reason>`, брать бэкенд только из `$CODELAB_HOME/config.yaml` и НЕ SHALL менять из-за этого код выхода.

Если `CODELAB_HOME` не задана или пуста и при этом `HOME` и `USERPROFILE` не заданы или пусты, подкоманды `secret` SHALL отказывать с кодом `64` и сообщением `cannot find the home folder: set CODELAB_HOME or HOME` в stderr без справки `secret` (ошибка окружения), не открывая хранилище, не читая stdin и не создавая файлов и каталогов. Запасного каталога `./.codelab` у подкоманд `secret` нет: `secrets.yaml` не должен попасть в текущий каталог, например в git-репозиторий (design.md, D8). Поведение `serve` и `config check` это правило не меняет.

- `set <name>`:
  - значение читается только из stdin: с TTY — скрытым вводом с подсказкой в stderr; без TTY — весь поток без одного завершающего `\n` или `\r\n`;
  - проверки, не требующие значения (имя, бэкенд только для чтения, коллизия), выполняются `SecretAdmin.checkStore` до чтения stdin;
  - бэкенд `env` (в том числе при `auto`) — код `1`, stdin не читается, stderr подсказывает добавить `secrets.backend: file` в `<CODELAB_HOME>/config.yaml` (секреты будут в открытом `secrets.yaml` с правами `0600`) или задать переменную `envOverride(name)`; на Windows — только переменную;
  - успех — код `0` и `Stored secret <name> in <backend>`; существующее имя перезаписывается без вопроса и без флага `--force`, stdout — `Updated secret <name> in <backend>`.
- `delete <name>`: код `0` и `Deleted secret <name> from <backend>`; отсутствующее имя — код `0` и `Secret <name> was not set in <backend>`.
- `list`:
  - первая строка — `Backend: <id>` или `Backend: env (<reason>)`;
  - затем имена по алфавиту;
  - затем строка `Environment overrides: <VAR>, …`, если в окружении есть переменные `CODELAB_SECRET_*`;
  - код `0`.
- `migrate` — требование «Подкоманда secret migrate»; stdin НЕ SHALL читаться.

Ошибки с кодом `64` делятся на два класса:
- **ошибка использования** — код `64`, сообщение и справка `secret` в stderr: неверное имя; значение аргументом (`pass the secret value on stdin, not as an argument`, аргумент не печатается); нет подкоманды или она неизвестна; ошибка разбора argv. Ошибка разбора argv SHALL печатать только `<бинарь>: invalid arguments for secret` и справку, без присланных слов: среди них может быть значение секрета. Это относится к любой ошибке разбора, если `secret` есть в argv, — в том числе к ошибке флага верхнего уровня, стоящего до `secret`; текст исключения `package:args` НЕ SHALL печататься. Лишние слова в argv других команд `codelab-agent` (`serve`, `config`) тоже НЕ SHALL цитироваться: сообщение называет только их число (`unexpected arguments (N)`, `codelab-agent: unknown config arguments (N)`);
- **ошибка значения** — код `64` и только сообщение, без справки, ничего не записывается: пустое значение или EOF — `empty secret value`; перевод строки внутри значения — `secret value must be a single line`; недопустимый UTF-8 — `secret value must be valid UTF-8`; длиннее 64 КиБ или с непарным суррогатом — причина `SecretAdmin`; коллизия `envOverride` с переменной другого сохранённого имени — `secret name <name> collides with <other> (both map to <VAR>)`.

Скрытый ввод с TTY SHALL выключать эхо и канонический режим терминала и обрабатывать Backspace и Ctrl+D сам; Enter завершает ввод, Ctrl+D на пустом вводе — конец потока. Длина значения НЕ SHALL ограничиваться длиной канонической строки терминала. Байты после первого перевода строки (вставка нескольких строк) SHALL давать ошибку значения `secret value must be a single line`; уже поступивший остаток ввода SHALL вычитываться до восстановления режимов терминала. Режимы терминала SHALL восстанавливаться при любом завершении чтения и по `SIGINT`; `SIGINT` во время ввода завершает процесс кодом `130`.

Ни одна подкоманда НЕ SHALL печатать значение или длину секрета. Ошибка хранилища (в том числе отказ бэкенда `file` по правам) SHALL давать код `1`. С бэкендом `file` каждая подкоманда SHALL писать в stderr `warning: secrets are stored unencrypted in <path>`.

#### Scenario: Значение аргументом
- **WHEN** запускается `codelab secret set codelab/openai sk-test-0123456789abcdef`
- **THEN** код `64`, stderr содержит `pass the secret value on stdin, not as an argument` и не содержит `sk-test-0123456789abcdef`, хранилище не вызывалось

#### Scenario: Значение из stdin без TTY
- **WHEN** в stdin `codelab-agent secret set codelab/openai` подана строка `sk-test-0123456789abcdef\n`, бэкенд — фейк с записью
- **THEN** записано значение без завершающего `\n`, stdout — `Stored secret codelab/openai in <backend>`, код `0`

#### Scenario: Перезапись существующего секрета
- **WHEN** `codelab/openai` уже сохранён, а `secret set codelab/openai` получает новое значение из stdin
- **THEN** значение заменено, stdout — `Updated secret codelab/openai in <backend>`, код `0`

#### Scenario: Конфиг с ключом значением не мешает set
- **WHEN** `config.yaml` невалиден (`budget.max_steps: 0`) и содержит `providers.openai.api_key: sk-…`, а запускается `secret set codelab/openai`
- **THEN** подкоманда выполняется, проблемы конфига её не блокируют

#### Scenario: Коллизия переменной
- **WHEN** сохранён `codelab/a-b`, а запускается `secret set codelab/a.b`
- **THEN** код `64`, stderr называет оба имени и переменную `CODELAB_SECRET_CODELAB_A_B`

#### Scenario: Только чтение при auto
- **WHEN** конфиг не задаёт `secrets.backend` (`auto` = `env`), на macOS или Linux запускается `secret set codelab/openai`
- **THEN** код `1`, stdin не читается, stderr содержит `secrets.backend: file` и `CODELAB_SECRET_CODELAB_OPENAI`

#### Scenario: Сохранение в file
- **WHEN** глобальный конфиг задаёт `secrets.backend: file`, в stdin `secret set codelab/openai` подана строка `sk-test-0123456789abcdef`
- **THEN** код `0`, `<CODELAB_HOME>/secrets.yaml` создан с правами `0600`, stderr содержит `warning: secrets are stored unencrypted`, stdout и stderr не содержат значения

#### Scenario: Одинаковый вывод двух бинарей
- **WHEN** `codelab secret list` и `codelab-agent secret list` запускаются с одним окружением, `secrets.backend: env` и `CODELAB_SECRET_X=1`
- **THEN** stdout, stderr и коды совпадают; stdout содержит `Environment overrides: CODELAB_SECRET_X` и не содержит `1` как значение

#### Scenario: Ошибка значения без справки
- **WHEN** в stdin `secret set codelab/openai` без TTY подан пустой поток, бэкенд — фейк с записью
- **THEN** код `64`, stderr — `empty secret value` без справки `secret`, хранилище не записывалось

#### Scenario: Недопустимый UTF-8
- **WHEN** в stdin `secret set codelab/openai` без TTY поданы байты `0xff 0xfe`, бэкенд — фейк с записью
- **THEN** код `64`, stderr — `secret value must be valid UTF-8` без справки, хранилище не записывалось

#### Scenario: Ошибка разбора argv не цитирует слово
- **WHEN** запускается `codelab-agent secret set codelab/openai --sk-test-0123456789abcdef`
- **THEN** код `64`, stderr содержит `invalid arguments for secret` и справку `secret` и не содержит `sk-test-0123456789abcdef`

#### Scenario: Вставка нескольких строк в TTY
- **WHEN** `secret set codelab/openai` читает с TTY (фейковый `SecretInput`), и ввод содержит `line1\nline2`
- **THEN** код `64`, stderr — `secret value must be a single line`, хранилище не записывалось

#### Scenario: Слова secret после другой команды
- **WHEN** запускается `codelab-agent serve --stdio secret set codelab/x sk-test-0123456789abcdef`
- **THEN** код `64`, stdout и stderr не содержат `sk-test-0123456789abcdef` и ни одной его подстроки из 4 и более символов

#### Scenario: Недопустимый CODELAB_CONFIG
- **WHEN** `secret list` запускается с `CODELAB_CONFIG=relative.yaml`, а `$CODELAB_HOME/config.yaml` задаёт `secrets.backend: env`
- **THEN** stderr содержит `warning: CODELAB_CONFIG ignored:`, первая строка stdout — `Backend: env`, код `0`

#### Scenario: Нет домашнего каталога
- **WHEN** `secret set codelab/openai` (с `secrets.backend: file` в `CODELAB_CONFIG`) или `secret list` запускается с пустыми `CODELAB_HOME`, `HOME` и `USERPROFILE` в текущем каталоге `<tmp>`
- **THEN** код `64`, stderr содержит `cannot find the home folder: set CODELAB_HOME or HOME` и не содержит справки `secret`, stdin не читался, в `<tmp>` не создан `.codelab/` и `secrets.yaml`

#### Scenario: Ошибка флага верхнего уровня перед secret
- **WHEN** запускается `codelab --sk-test-0123456789abcdef secret list`
- **THEN** код `64`, stderr содержит `codelab: invalid arguments for secret` и справку `secret` и не содержит `sk-test-0123456789abcdef`

## ADDED Requirements

### Requirement: Подкоманда secret migrate
`SecretCommands.migrate` (оба бинаря) SHALL быть обёрткой над движком `SecretMigrator` (`codelab_agent_io`), который возвращает типизированный отчёт без значений; CLI SHALL вызывать тот же движок через `package:codelab_setup/io.dart`, codelab-app — через `package:codelab_embedded/io.dart` (design.md change `add-config-literal-secrets-and-migrate`, D7). Синтаксис: `secret migrate [--project | --local | --all] [--cwd <dir>] [--dry-run] [--force]`.

Команда SHALL загружать конфиг обычным `ConfigLoader` со всеми проверками; любая проблема загрузки — код `1` с проблемой. Переносятся находки `findInlineSecrets` применяемых слоёв:
- `api_key`/`apiKey` провайдера и литерал в `api_key_env`/`api_key_secret` → `api_key_secret: <name>` (`api_key`, `apiKey`, `api_key_env` удаляются той же правкой);
- прочие ключи `inlineSecretKeys` провайдера или элемента `mcp.servers` → значение сохраняется в хранилище **до** удаления ключа; stdout получает `action required: reference ${secret:<name>} in <место>`;
- участок секрета в строке `headers`/`env` → `${secret:<name>}` на месте участка, остальное сохраняется; второй и следующие участки одного значения — `<name>-2`, `<name>-3`;
- литерал в `${secret:<литерал>}` → значение секрета, ссылка `${secret:<name>}`.

`<name>` SHALL быть `suggestedSecretName` находки.

Не переносятся (строка `not migrated: …` без значения, код выхода не меняется):
- элементы `mcp.servers[*].args` с подсказкой `--env <NAME>='${secret:…}'`;
- недоверенные проектные слои — значение такого слоя НЕ SHALL попадать в хранилище;
- значение, которое отклонила бы проверка `secretValueProblem` (перевод строки, например PEM; больше 64 КиБ; непарный суррогат), — строка `not migrated: <key> cannot be stored (<причина>)`;
- `CODELAB_CONFIG`.

Слои: по умолчанию `user`; `--project`, `--local` — для `--cwd` (иначе каталога процесса); `--all` — `user`, `project`, `local`; `--all` с `--project`/`--local` — код `64`.

Порядок:
1. Без записи: находки; проверка доверия писателя для каждой правки проектного слоя; `SecretAdmin.checkStore`; конфликты имён; кандидат каждого файла через `ConfigLoader.validateCandidate` без новых проблем. Отказ на этом шаге НЕ SHALL оставлять записей.
2. Конфликт имени:
   - внутри запуска то же значение — один секрет; другое — следующее свободное имя `<name>-2`, `<name>-3` в порядке слоёв (`user`, `project`, `local`), затем порядка файла (так же разводятся имена `forMcp` разных серверов, совпавшие после нормализации);
   - с хранилищем то же значение — `Reused secret <name> for <ключ> in <path>`, другое без `--force` — код `1` до записи с текстом `secret <name> already exists with a different value; rerun with --force to replace it`;
   - `--force` — замена со строкой `warning: replaced the existing secret <name>; the previous value cannot be restored; also referenced by: <ключи>` (ключи всех слоёв загруженного конфига, ссылающиеся на это имя; без таких ключей хвоста нет).
3. По файлу: секреты, затем одна атомарная `ConfigWriter.apply`; `ConfigConflictException` — одно перечитывание.
4. Сбой записи конфига после сохранения секретов — код `1`, stderr называет сохранённые имена, файл не изменён; повторный запуск SHALL переиспользовать их.

`--dry-run` SHALL выполнять шаги 1–2 и печатать план `<path>: <ключ> -> <ссылка> (new|reuse|replace)` без записи; код — как у настоящего запуска. Вывод: `Moved <ключ> in <path> to secret <name>`, при переносе последней строкой `restart the agent to use the moved secrets`; без находок — `Nothing to migrate`. Бэкенд только для чтения — код `1` с подсказкой `secrets.backend: file` или переменных `CODELAB_SECRET_<…>` (имена без значений). Значения, длины, префиксы и хеши НЕ SHALL попадать в stdout, stderr и лог. Коды: `0`, `1` (хранилище, конфликт, писатель, кандидат, загрузка), `64` (использование).

#### Scenario: Перенос ключа провайдера и смешанного заголовка
- **GIVEN** `secrets.backend: file`; `config.yaml` с комментариями содержит `providers.lm.api_key: sk-<30 символов>` и сервер `gh` с `Authorization: "Bearer ghp_<36 символов> ${X}"`
- **WHEN** запускается `codelab-agent secret migrate`
- **THEN** код `0`; хранилище содержит `codelab/lm` и `codelab/mcp/gh/authorization`; в файле `api_key_secret: codelab/lm` и `Bearer ${secret:codelab/mcp/gh/authorization} ${X}`; комментарии на месте; предупреждений `config.secret.in_file` больше нет; вывод и лог без значений

#### Scenario: Токен MCP-сервера без поля в схеме
- **WHEN** элемент `mcp.servers` `gh` содержит `token: ghp_<36 символов>`, запускается `secret migrate`
- **THEN** секрет `codelab/mcp/gh/token` сохранён до удаления ключа `token` из файла; stdout содержит `action required: reference ${secret:codelab/mcp/gh/token} in mcp.servers[gh].env or .headers`

#### Scenario: Пробный запуск
- **WHEN** тот же файл и `secret migrate --dry-run`
- **THEN** код `0`, план со статусом `new`; файл и хранилище не изменены

#### Scenario: Бэкенд только для чтения
- **WHEN** `secrets.backend` не задан, запускается `secret migrate`
- **THEN** код `1`, подсказка `secrets.backend: file` и имена `CODELAB_SECRET_CODELAB_LM`, `CODELAB_SECRET_CODELAB_MCP_GH_AUTHORIZATION`; файл не изменён

#### Scenario: Конфликт имени
- **WHEN** `codelab/lm` уже сохранён с другим значением
- **THEN** без `--force` — код `1`, файл и хранилище не изменены, `--dry-run` даёт тот же код; с `--force` — код `0` и `warning: replaced the existing secret codelab/lm; the previous value cannot be restored`

#### Scenario: Одно имя у двух находок
- **WHEN** пользовательский и проектный слой (`--all`, доверенный проект) задают `providers.lm.api_key` с разными значениями
- **THEN** код `0`; пользовательский слой получает `api_key_secret: codelab/lm`, проектный — `codelab/lm-2`; `--dry-run` показывает оба имени со статусом `new`

#### Scenario: Значение, которое хранилище не примет
- **WHEN** `mcp.servers[gh].env.KEY` содержит многострочный PEM-блок
- **THEN** строка `not migrated: mcp.servers[gh].env.KEY cannot be stored (secret value must be a single line)` без значения; остальные находки перенесены; код `0`; `--dry-run` показывает ту же строку

#### Scenario: --force называет ссылающиеся ключи
- **WHEN** пользовательский слой ссылается `api_key_secret: codelab/lm`, хранилище содержит `codelab/lm`, а проектный слой содержит литеральный `providers.lm.api_key` с другим значением; запускается `secret migrate --project --force`
- **THEN** stdout содержит `warning: replaced the existing secret codelab/lm; the previous value cannot be restored; also referenced by: providers.lm.api_key_secret (user)`

#### Scenario: Недоверенный проект
- **WHEN** проект вне `trusted_projects` содержит `providers.p.api_key: sk-<30 символов>`, запускается `secret migrate --all`
- **THEN** строка `not migrated: <path> is an untrusted project config`; хранилище не содержит этого значения; проектный файл не изменён

#### Scenario: Повтор после сбоя записи конфига
- **WHEN** секреты сохранены, а запись файла сорвалась (шов писателя), и команда запускается повторно
- **THEN** первый запуск — код `1`, stderr называет `codelab/lm`, файл не изменён; второй — `Reused secret codelab/lm …`, файл перенесён, код `0`

#### Scenario: args не переносятся
- **WHEN** `mcp.servers[gh].args` содержит `ghp_<36 символов>`
- **THEN** `args` не изменён, строка `not migrated: mcp.servers[gh].args[1] looks like a secret (github)` без значения; код `0`

### Requirement: Имя секрета, похожее на значение
`secret set` и `secret delete` у обоих бинарей SHALL отклонять имя с `literalSecretTag(name) != null` ошибкой использования `64` с текстом `the secret name looks like a secret value; pass the value on stdin`; имя НЕ SHALL печататься, хранилище НЕ SHALL вызываться. `SecretNames.problem` НЕ SHALL меняться.

#### Scenario: Токен вместо имени
- **WHEN** запускается `codelab secret set ghp_<36 символов>`
- **THEN** код `64`, stderr содержит `the secret name looks like a secret value` и не содержит `ghp_`; вывод `codelab-agent` совпадает
