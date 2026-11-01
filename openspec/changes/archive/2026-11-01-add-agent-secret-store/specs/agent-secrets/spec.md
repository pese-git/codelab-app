## ADDED Requirements

### Requirement: Имена секретов
Имя секрета SHALL проверяться одним правилом `SecretNames` ядра: совпадение с `^[a-z0-9][a-z0-9._/-]{0,127}$`, без `..` и без `/` в конце (`agent-core-architecture` §17.5.2; design.md, D2). Правило SHALL применяться к `api_key_secret`, к имени в `${secret:<name>}` и к аргументу подкоманд `secret`. Неверное имя SHALL давать текст `expected a secret name: lowercase letters, digits and . _ / -, up to 128 characters`; само значение в текст НЕ SHALL попадать.

`SecretNames.envOverride(name)` SHALL возвращать `CODELAB_SECRET_` и имя в верхнем регистре, где каждый символ вне `[A-Z0-9]` заменён на `_`. `SecretNames.suggestFor(path)` SHALL возвращать:
- `codelab/<id>` для ключей `providers.<id>.*`;
- `codelab/mcp/<server>/<key>` для `mcp.servers[<server>].env.<KEY>` и `….headers.<Key>` — обе части в нижнем регистре, символы вне `[a-z0-9._-]` заменены на `-`; так же `SecretNames.forMcp(server, key)`;
- `codelab/mcp/<server>/<key>` для ключа `mcp.servers[<server>].<key>` вне `env` и `headers` (например, `token`) — по тому же правилу;
- `codelab/search-<b>` для `tools.web.search.backends.<b>.*`;
- `codelab/<путь>` для любого другого пути: путь нормализуется тем же правилом частей (нижний регистр, символы вне `[a-z0-9._-]` заменены на `-`).

Результат `suggestFor` и `forMcp` SHALL проходить правило имени.

#### Scenario: Переменная переопределения
- **WHEN** вызывается `SecretNames.envOverride("codelab/mcp/github/authorization")`
- **THEN** результат — `CODELAB_SECRET_CODELAB_MCP_GITHUB_AUTHORIZATION`

#### Scenario: Предлагаемое имя MCP
- **WHEN** вызываются `SecretNames.forMcp("GitHub", "Authorization")` и `SecretNames.suggestFor("mcp.servers[GitHub].headers.Authorization")`
- **THEN** оба дают `codelab/mcp/github/authorization`, и имя проходит правило

#### Scenario: Предлагаемое имя ключа элемента MCP и запасной вариант
- **WHEN** вызываются `SecretNames.suggestFor("mcp.servers[GitHub].token")` и `SecretNames.suggestFor("tools.exec.Api Token")`
- **THEN** первое даёт `codelab/mcp/github/token`, второе — имя с префиксом `codelab/`; оба проходят правило

#### Scenario: Неверные имена
- **WHEN** проверяются `Codelab/OpenAI`, `a/../b`, `codelab/`, `my key` и строка из 129 символов
- **THEN** каждое отклонено с текстом правила, текст не содержит проверяемой строки

### Requirement: Резолвер секретов
Ядро SHALL получать значение секрета только через `SecretResolver` (`codelab_agent_core/lib/src/secrets/`, чистый Dart, без `dart:io`). `SecretResolver.secret(name, purpose)` SHALL возвращать `SecretFound(value, source)`, `SecretMissing(backend)` или `SecretUnavailable(backend, reason)` (design.md, D3).

Порядок:
1. Кэш процесса содержит имя → `SecretFound(source: "cache")`.
2. Переменная `SecretNames.envOverride(name)` задана и непуста → её значение, `source: "env"`.
3. `DescribedSecretStore.read(name)`:
   - найдено → `source` — id бэкенда;
   - `null` или пусто → `SecretMissing`;
   - `SecretStoreUnavailableException` → `SecretUnavailable` и предупреждение `secrets.backend.unavailable {backend, reason}`, не чаще одного раза на пару `(backend, reason)` за процесс.

Найденное значение SHALL кэшироваться до конца жизни резолвера, ненайденное НЕ SHALL кэшироваться. Одновременные запросы одного имени SHALL приводить к одному вызову `read`. Переменная переопределения SHALL побеждать хранилище при любом бэкенде. `SecretFound.toString()` НЕ SHALL содержать значение. `SecretResolver.env(variable, purpose)` SHALL читать только окружение, переданное резолверу.

#### Scenario: Переменная побеждает хранилище
- **WHEN** `MemorySecretStore` содержит `codelab/openai = store-value`, а окружение — `CODELAB_SECRET_CODELAB_OPENAI=env-value`
- **THEN** `secret("codelab/openai")` даёт `env-value` с `source: env`, а `read` хранилища не вызывается

#### Scenario: Кэш и отсутствие
- **WHEN** секрет `codelab/a` найден в хранилище, а `codelab/b` отсутствует; оба запрашиваются дважды, а между запросами `codelab/b` записывается в хранилище
- **THEN** `read("codelab/a")` вызван один раз, второй ответ — `source: cache`; `codelab/b` сначала `SecretMissing`, затем `SecretFound`

#### Scenario: Одно обращение на имя
- **WHEN** три вызова `secret("codelab/a")` начинаются до завершения первого `read`
- **THEN** хранилище получает один `read`, все три вызова получают одно значение

#### Scenario: Хранилище недоступно
- **WHEN** `read` бросает `SecretStoreUnavailableException(backend: "file", reason: "<path> has permissions 0644; run: chmod 600 <path>")` на двух разных именах
- **THEN** оба вызова дают `SecretUnavailable`, а в логе ровно одно `secrets.backend.unavailable`

### Requirement: Ключ провайдера при запросе
Ключ провайдера SHALL разрешаться при первом запросе к провайдеру в `createRoutedStreamFunction`, а не при загрузке конфига (design.md, D4):
- `api_key_secret` — через `SecretResolver.secret`;
- `api_key_env` — через `SecretResolver.env`;
- `${secret:<name>}` в `providers.<id>.headers.*` — через `SecretResolver.secret`.

Хост без `SecretResolver` ключ провайдера НЕ SHALL получать: ни из хранилища, ни прямым чтением окружения. Ссылка тогда SHALL давать ошибку хода класса `auth` без HTTP-запроса: `API key variable <VAR> cannot be read: the host has no secret resolver` для `api_key_env`, `API key secret <name> cannot be read: the host has no secret resolver` для `api_key_secret`, `secret <name> cannot be read (providers.<id>.headers.<H>): the host has no secret resolver` для заголовка. Каждый хост, которому нужен ключ провайдера, SHALL передавать резолвер (настольные хосты — `openHostSecrets`, design.md D4, D15).

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

### Requirement: Секреты MCP-серверов конфигурации
Значения `env.*` и `headers.*` MCP-сервера конфигурации с `${secret:<name>}` SHALL храниться в `CoreConfig` шаблоном из литералов и ссылок, а не строкой, и раскрываться рантаймом перед `services.mcp.connect` при создании и загрузке сессии (design.md, D4). Раскрытие SHALL выполняться также для серверов конфига в `AgentSession.setMcpServers`. Сервер с ненайденным секретом НЕ SHALL подключаться: лог `mcp.server.failed {server, transport, reason}` с причиной `secret <name> is not set` или `secret <name> cannot be read: <backend> is unavailable` (имя секрета и бэкенд, никогда значение), сессия создаётся без его инструментов (agent-runtime «MCP-серверы сессии», шаг 3). `AgentSession.close()` или `AgentRuntime.dispose()` во время раскрытия SHALL отбрасывать результат без `connect` и без `mcp.server.failed`. Заголовки HTTP-сервера после раскрытия SHALL идти в порядке файла конфига. `${secret:…}` в серверах `session/new.mcpServers` SHALL оставаться литералом. Литерал `$${secret:x}` SHALL давать строку `${secret:x}` без обращения к резолверу. Без `AgentCoreServices.secrets` ссылка SHALL давать сбой сервера с причиной `no secret store`.

#### Scenario: Заголовок из хранилища
- **WHEN** конфиг объявляет http-сервер `gh` с `headers.Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`, а хранилище содержит `tok-test-secret`
- **THEN** коннектор получает заголовок `Bearer tok-test-secret`, а лог и журнал не содержат `tok-test-secret`

#### Scenario: Порядок заголовков сохраняется
- **WHEN** сервер `gh` задаёт заголовки `X-A: a`, `Authorization: "Bearer ${secret:codelab/mcp/gh/authorization}"`, `X-B: b` в этом порядке, секрет найден
- **THEN** коннектор получает заголовки в порядке `X-A`, `Authorization`, `X-B`

#### Scenario: Закрытие во время раскрытия
- **WHEN** `read` хранилища для сервера `gh` не завершается, а рантайм получает `dispose()`
- **THEN** `connect` для `gh` не вызван, записи `mcp.server.failed` для `gh` нет

#### Scenario: Ненайденный секрет MCP
- **WHEN** у сервера `gh` секрет не задан, а у сервера `docs` ссылок нет
- **THEN** сессия создаётся, `docs` подключён, `gh` — `mcp.server.failed` с причиной `secret codelab/mcp/gh/authorization is not set`

#### Scenario: Ссылка от клиента ACP — литерал
- **WHEN** `session/new.mcpServers` содержит http-сервер с заголовком `${secret:codelab/openai}`
- **THEN** резолвер не вызывается, коннектор получает строку `${secret:codelab/openai}`

#### Scenario: Недоверенный проект не читает секреты
- **WHEN** `<cwd>/.codelab/config.yaml` недоверенного проекта объявляет сервер с `${secret:codelab/openai}`
- **THEN** сервер отброшен правилом доверия, резолвер не вызывается

### Requirement: Бэкенды env и file
`codelab_agent_io` SHALL предоставлять бэкенды `DescribedSecretStore` `env` (только чтение `CODELAB_SECRET_<…>`) и `file` (requirement «Бэкенд file»). Запись и удаление у `env` SHALL давать `SecretStoreUnavailableException("env backend is read-only")`. При записи SHALL отклоняться значение с `\n` или `\r` (`secret value must be a single line`), длиннее 64 КиБ в UTF-8 (`secret value is longer than 64 KiB`) и с непарным суррогатом (`secret value is not valid Unicode (unpaired surrogate)`); `FileSecretStore.write` SHALL сам отклонять недопустимое имя (`invalid secret name`) и значение исключением `SecretStoreUnavailableException`, не доверяя вызывающему (design.md, D5, D14). Текст исключений НЕ SHALL содержать ни значение, ни имя из недопустимого ввода. Порт `SecretStore` SHALL оставаться прежним (§10.3), чтобы бэкенды хранилищ ОС подключались после 1.0 изменением только `openSecretStore` (design.md, D13). Значение секрета НЕ SHALL передаваться в argv дочерних процессов. Дочерние процессы бэкендов SHALL запускаться портом `SecretProcessRunner` по абсолютному пути, без оболочки и без окружения родителя; результат порта — код выхода и признак таймаута, stdout и stderr вычитываются и отбрасываются (design.md, D5).

#### Scenario: env только для чтения
- **WHEN** `EnvSecretStore` с окружением `CODELAB_SECRET_CODELAB_A=v` читает `codelab/a`, затем вызываются `write("codelab/a", "x")` и `delete("codelab/a")`
- **THEN** чтение возвращает `v`, запись и удаление бросают `SecretStoreUnavailableException` с причиной `env backend is read-only`

### Requirement: Бэкенд file
Бэкенд `file` SHALL хранить секреты открытым текстом в `$CODELAB_HOME/secrets.yaml` — отображении «имя → строка» в строгом профиле YAML. Он SHALL выбираться только явным `secrets.backend: file`. Файл SHALL создаваться только записью (`secret set`); чтение, удаление и `names()` отсутствующего файла его НЕ SHALL создавать.

Перед каждым чтением, записью и `names()` бэкенд SHALL отказывать (`SecretStoreUnavailableException`; предупреждение `secrets.file.refused` — не больше одного на процесс и путь), если:
- каталог `$CODELAB_HOME` — символическая ссылка: причина `<home> is a symbolic link; refusing to keep secrets there`;
- каталог `$CODELAB_HOME` доступен на запись группе или остальным (`mode & 0o022 != 0`): причина `<home> is writable by group or others (mode <mode>); run: chmod go-w <home>`; существующий каталог бэкенд НЕ SHALL изменять;
- путь — символическая ссылка: причина `<path> is a symbolic link; refusing to read secrets`;
- права шире `0600` (`mode & 0o077 != 0`): причина `<path> has permissions <mode>; run: chmod 600 <path>`;
- файл больше 1 МиБ: причина `<path> is larger than 1 MiB` (поле события `reason: too_large`).

Каталог `$CODELAB_HOME`, которого нет, SHALL создаваться только записью и сразу получать права `0700` независимо от umask. Перед каждой заменой файла (`write`, `delete` существующего имени) владелец существующего `$CODELAB_HOME` SHALL проверяться no-op `chmod <текущий режим>` через `SecretProcessRunner`; отказ — `<home> is not owned by the current user; refusing to write secrets` (`secrets.file.refused {reason: home_owner}`). Утилита — `/bin/chmod`, при его отсутствии — `/usr/bin/chmod`.

Запись SHALL быть атомарной и закрытой от других пользователей (design.md, D14):
- временный файл SHALL создаваться в приватном каталоге `$CODELAB_HOME/.secrets-tmp/` с уникальным именем `secrets.tmp-<pid>-<counter>-<random>`; каталог получает `chmod 700` и проверяется по типу и режиму, символическая ссылка вместо него — отказ без `chmod`;
- тип и режим `.secrets-tmp` SHALL повторно проверяться после создания временного файла, после `chmod 600` и перед переименованием;
- временный файл SHALL получать права `0600` с проверкой до записи значения и повторно перед переименованием;
- после переименования SHALL проверяться сам `secrets.yaml`: права шире `0600` сначала исправляются `chmod 600`; только если это не удалось, файл SHALL удаляться с отказом `<path> has wider permissions than 0600 after write; the file was removed` (или `…; could not remove the file`) и `secrets.file.refused {reason: wide_after_write}`;
- содержимое больше 1 МиБ SHALL отклоняться до замены (`<path> would be larger than 1 MiB`);
- сбой до переименования SHALL оставлять прежний файл; брошенные временные файлы SHALL удаляться следующей записью, только если это обычные файлы `secrets.tmp-*` старше 10 минут — свежие, чужие и ссылки НЕ SHALL удаляться;
- записи в один файл SHALL идти одной очередью на процесс, общей для всех экземпляров `FileSecretStore`; ключ очереди — нормализованный абсолютный путь с разрешёнными символическими ссылками родительского каталога.

На Windows бэкенд SHALL отказывать: права NTFS `dart:io` не проверяет. При каждом старте хоста с бэкендом `file` SHALL писаться предупреждение `secrets.backend.plaintext {path}`. Конструктор SHALL принимать явный путь, чтобы тестовое хранилище этапа 7 (`CODELAB_TEST_SECRET_STORE`) использовало ту же реализацию с `backend.id == "file"`.

#### Scenario: Права шире 0600
- **WHEN** `secrets.yaml` содержит `codelab/openai` и имеет права `0644`
- **THEN** `read("codelab/openai")` даёт `SecretStoreUnavailableException` с текстом `has permissions 0644; run: chmod 600 <path>`, значение не возвращено и не залогировано, резолвер возвращает `SecretUnavailable`

#### Scenario: Символическая ссылка
- **WHEN** `secrets.yaml` — символическая ссылка на файл с правами `0600`
- **THEN** чтение отклонено с причиной `is a symbolic link`

#### Scenario: Файл создаёт только запись
- **WHEN** файла нет, а выполняются `read`, `delete` и `names()`, затем `write("codelab/a", "v")`
- **THEN** до `write` файла нет; после — файл есть, права `0600`, `read` возвращает `v`

#### Scenario: Атомарная запись
- **WHEN** запись прерывается после создания временного файла и до переименования, а в `$CODELAB_HOME/.secrets-tmp/` остался файл `secrets.tmp-*` убитого процесса старше 10 минут
- **THEN** `secrets.yaml` содержит прежние значения; следующая запись удаляет брошенный временный файл

#### Scenario: Свежие и чужие временные файлы не удаляются
- **WHEN** в `$CODELAB_HOME/.secrets-tmp/` лежат свежий `secrets.tmp-*` другого процесса, такой же файл старше 10 минут и символическая ссылка `secrets.tmp-*` на файл вне каталога, а выполняется запись
- **THEN** удалён только старый обычный файл; свежий файл, ссылка и её цель не тронуты

#### Scenario: Каталог секретов доступен на запись другим
- **WHEN** `$CODELAB_HOME` имеет права `0777` (или `0775`) либо является символической ссылкой, а выполняется `read` или `write`
- **THEN** отказ `SecretStoreUnavailableException` с подсказкой `chmod go-w <home>` (для ссылки — `is a symbolic link`), права каталога не изменены, файл не создан

#### Scenario: Чужой каталог секретов
- **WHEN** существующий `$CODELAB_HOME` с правами `0700` принадлежит другому пользователю (фейковый runner отвечает на no-op `chmod` ненулевым кодом), а выполняется `write`
- **THEN** отказ `<home> is not owned by the current user; refusing to write secrets`, `secrets.file.refused {reason: home_owner}`, `.secrets-tmp` и `secrets.yaml` не созданы и не изменены

#### Scenario: Широкие права после переименования
- **WHEN** после переименования `secrets.yaml` получает права `0644`, а `chmod 600` их исправляет
- **THEN** запись успешна, файл с правами `0600` сохранён; если `chmod 600` не помогает — файл удалён, отказ `has wider permissions than 0600 after write; the file was removed`, событие `reason: wide_after_write`

#### Scenario: Каталог секретов создаёт запись
- **WHEN** `$CODELAB_HOME` нет, а выполняется `write("codelab/a", "v")`
- **THEN** каталог создан с правами `0700`, `.secrets-tmp` — `0700`, `secrets.yaml` — `0600`

#### Scenario: Записи разных экземпляров не теряются
- **WHEN** два экземпляра `FileSecretStore` над одним путём одновременно записывают разные имена
- **THEN** после обеих записей файл содержит оба имени

#### Scenario: file на Windows
- **WHEN** глобальный конфиг на Windows задаёт `secrets.backend: file`
- **THEN** загрузка даёт проблему `secrets.backend: file backend is not supported on Windows; use env with CODELAB_SECRET_* variables`; `FileSecretStore` на подменённой платформе `windows` отказывает каждой операции с тем же текстом без префикса ключа

### Requirement: Выбор бэкенда secrets.backend
Ключ `secrets.backend` (`auto` | `keychain` | `env` | `file`, по умолчанию `auto`) SHALL читаться только из пользовательского слоя и из файла `--config`/`CODELAB_CONFIG`; из проектных слоёв он отбрасывается правилом доверия. Другое значение SHALL давать проблему `value` с текстом `expected one of: auto, keychain, env, file` (design.md, D7).
- `auto` SHALL давать бэкенд `env` на всех ОС, без проб и процессов, с `unavailableReason`: на macOS и Linux — `OS keychain backends are not available in this version; set secrets.backend: file or CODELAB_SECRET_* variables`, на Windows — `OS keychain backends are not available in this version; set CODELAB_SECRET_* variables` (`file` там недоступен). `auto` НЕ SHALL выбирать `file` ни сразу, ни как запасной вариант, даже если `secrets.yaml` существует.
- `keychain` SHALL давать проблему конфигурации `secrets.backend: keychain is not supported yet (supported: auto, env, file)`: хранилища ОС появятся после 1.0.
- `env` SHALL использовать только переменные `CODELAB_SECRET_*`.
- `file` — requirement «Бэкенд file»; на Windows — проблема конфигурации, поэтому на Windows в этой версии доступен только `env`.

Проверка значения для платформы SHALL быть одной (`secretsBackendProblem`) у `ConfigLoader`, `openSecretStore` и `FileSecretStore`, чтобы тексты не расходились. `openSecretStore` с недопустимым значением (`keychain`, незнакомое, `file` на Windows) SHALL бросать `SecretStoreUnavailableException` с тем же текстом, а не `UnsupportedError`: значение приходит и из подкоманд `secret`, которые не загружают конфиг целиком (design.md, D7, D8).

Выбранный бэкенд SHALL логироваться один раз: `secrets.backend.selected {backend, path, reason}`; `reason` у `auto` — `unavailableReason`, у явного выбора — `configured: secrets.backend: env` или `configured: secrets.backend: file`; хост, который принудительно выбирает `env` (`codelab-agent serve --llm-script`), SHALL передавать свою причину — `forced by --llm-script` (design.md, D10, D11).

#### Scenario: auto — env на всех ОС
- **WHEN** `auto` (или ключ не задан) на macOS, Linux и Windows (подменённая платформа)
- **THEN** бэкенд — `env`, ни одного дочернего процесса, `secrets.backend.selected {backend: env, path: null}`; на macOS и Linux причина называет `secrets.backend: file` и `CODELAB_SECRET_*`, на Windows — только `CODELAB_SECRET_*` и не содержит `secrets.backend: file`

#### Scenario: Недопустимое значение у openSecretStore
- **WHEN** `openSecretStore` вызван с `keychain`, `vault` или с `file` на подменённой платформе `windows`
- **THEN** бросается `SecretStoreUnavailableException` с текстом `keychain is not supported yet (supported: auto, env, file)`, `expected one of: auto, keychain, env, file` или `file backend is not supported on Windows; use env with CODELAB_SECRET_* variables` соответственно; `secrets.backend.selected` не пишется

#### Scenario: auto не выбирает file
- **WHEN** `auto`, а в `$CODELAB_HOME` лежит `secrets.yaml` с правами `0600` и секретом `codelab/openai`
- **THEN** бэкенд — `env`, файл не читается, `secret("codelab/openai")` даёт `SecretMissing(env)`

#### Scenario: keychain ещё не поддерживается
- **WHEN** глобальный конфиг задаёт `secrets.backend: keychain`
- **THEN** загрузка даёт проблему `secrets.backend: keychain is not supported yet (supported: auto, env, file)`; `serve` завершается кодом `64` до старта транспорта, `config check` — кодом `1`

#### Scenario: Неизвестный бэкенд
- **WHEN** глобальный конфиг задаёт `secrets.backend: vault`
- **THEN** загрузка даёт проблему `secrets.backend: expected one of: auto, keychain, env, file`

### Requirement: Подкоманды secret
`codelab secret set|delete|list` и `codelab-agent secret set|delete|list` SHALL использовать одну реализацию `SecretCommands` (`codelab_agent_io`); stdout, stderr и коды выхода, которые даёт `SecretCommands`, SHALL совпадать у двух бинарей (design.md, D8). Справка `secret` и сообщения разбора argv МОГУТ различаться: они называют свой бинарь. Подкоманды SHALL работать без запуска агента и без ACP. Бэкенд SHALL браться из `secrets.backend` пользовательского конфига и файла `CODELAB_CONFIG`; другие проблемы конфига НЕ SHALL мешать подкомандам. Если `CODELAB_CONFIG` недопустим (относительный путь или расширение не `.yaml`/`.yml` без учёта регистра — те же проверки, что у загрузчика), подкоманда SHALL писать в stderr `warning: CODELAB_CONFIG ignored: <reason>`, брать бэкенд только из `$CODELAB_HOME/config.yaml` и НЕ SHALL менять из-за этого код выхода.

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
- **WHEN** `config.yaml` содержит `providers.openai.api_key: sk-…` (конфиг невалиден), а запускается `secret set codelab/openai`
- **THEN** подкоманда выполняется, проблема `api_key` её не блокирует

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

### Requirement: Диагностика обращений к секретам
Флаг `serve --debug-secrets` и переменная `CODELAB_DEBUG_SECRETS=1` SHALL включать событие `secrets.lookup {name, purpose, source, found}` уровня `info` на каждое обращение к `SecretResolver`. `name` — имя секрета или переменной, `purpose` — путь ключа конфига, `source` — `cache`, `env` или id бэкенда. Без режима `secrets.lookup` НЕ SHALL писаться. Ни в одном режиме лог НЕ SHALL содержать значение секрета, его длину, префикс из 4 и более символов или хеш (CFG-10).

#### Scenario: Значение не попадает в лог
- **WHEN** `MemorySecretStore` содержит `sk-test-0123456789abcdef` под `api_key_secret` провайдеров `openai` и `org`, резолвер в режиме отладки; первая функция `createRoutedStreamFunction` на фейковом `http.Client` выполняет ход к `openai` и к `org`, затем вторая функция над тем же резолвером (как второй хост или сессия) — тоже к `openai` и к `org`, после чего первая функция выполняет ещё один ход к `openai` (`core/debug-secrets-never-logs-value`)
- **THEN** записи `secrets.lookup` с `found: true` идут по порядку: `openai` — `memory`, `org` — `memory`, `openai` — `cache`, `org` — `cache`; повторный ход первой функции новых записей не добавляет (цепочка провайдера кэшируется на процесс, design.md D4); сырые `LogRecord` (до любой редакции) не содержат значения, ни одной его подстроки длиной 4+, числа `24` в поле, связанном с секретом, и SHA-256 значения в шестнадцатеричном или base64 виде

#### Scenario: Без режима
- **WHEN** тот же прогон без `debug`
- **THEN** записей `secrets.lookup` нет

### Requirement: Секреты настольных хостов и встроенных профилей
Все настольные хосты — `codelab-agent`, встроенный агент desktop-приложения (`embedded-app-desktop`) и CLI (`embedded-cli`) — SHALL строить резолвер одной фабрикой `openHostSecrets` (`codelab_agent_io`) из `codelabHome`, окружения процесса, `secrets.backend` загруженного конфига и признака отладки (design.md, D15). Хост с ядром в отдельном isolate SHALL вызывать фабрику внутри этого isolate из сериализуемых данных; резолвер, его кэш и значения секретов НЕ SHALL пересылаться между isolate. Desktop SHALL использовать те же бэкенды, что CLI (в этой версии — те же переменные и тот же `secrets.yaml`), поэтому секрет, сохранённый `codelab secret set`, виден встроенному агенту приложения.

Известное ограничение до 8.10: найденное значение кэшируется до конца процесса, поэтому работающий агент не видит замену уже прочитанного секрета, сделанную в другом процессе, до перезапуска.

#### Scenario: Резолвер внутри isolate
- **WHEN** тест запускает `Isolate.run`, который получает только `codelabHome`, `secretsBackend: env` и `debug: true`, вызывает `openHostSecrets` с окружением, где задано `CODELAB_SECRET_CODELAB_P`, и разрешает `codelab/p`
- **THEN** isolate возвращает только признак `found: true` и `source: env`; запись `secrets.lookup` сделана логгером внутри isolate и не содержит значения

#### Scenario: Общий секрет CLI и встроенного агента
- **WHEN** `SecretAdmin` над бэкендом `file` во временном `CODELAB_HOME` сохраняет `codelab/p`, а затем `openHostSecrets` с тем же `CODELAB_HOME` и `secrets.backend: file` разрешает имя
- **THEN** значение найдено с `source: file`

#### Scenario: Замена прочитанного секрета требует перезапуска
- **WHEN** резолвер уже нашёл `codelab/p`, после чего другой экземпляр `SecretAdmin` перезаписывает значение
- **THEN** этот резолвер возвращает прежнее значение с `source: cache`; новый резолвер — новое значение

### Requirement: Программная запись секретов
`codelab_agent_io` SHALL предоставлять `SecretAdmin` — программный путь `store`, `delete`, `list` для страницы настроек приложения; `SecretCommands` SHALL быть построен поверх него, так что проверки и тексты причин совпадают. `codelab_setup/lib/io.dart` SHALL реэкспортировать `SecretAdmin`, его результаты, `openSecretStore` и типы их сигнатур — `DescribedSecretStore`, `SecretStoreUnavailableException`, `Logger` и `LogLevel`, чтобы приложения вызывали этот API без импорта `codelab_agent_*` (PKG-4); основной барель `codelab_setup.dart` НЕ SHALL меняться. `store(name, value)` SHALL применять правило `SecretNames`, отклонять пустое, многострочное, длиннее 64 КиБ и с непарным суррогатом значение, коллизию `envOverride` и бэкенд только для чтения типизированным результатом, а не исключением (design.md, D15): `SecretStored`, `SecretUpdated`, `SecretInvalidName`, `SecretInvalidValue`, `SecretCollision`, `SecretReadOnly {backend, variable, fileBackendOffered}` (`fileBackendOffered: false` на Windows), `SecretFailed`; `delete` — `SecretDeleted`, `SecretNotSet`, `SecretInvalidName`, `SecretReadOnly`, `SecretFailed`; `list` — `SecretListing` или `SecretListFailed`. Порядок проверок `store`: имя, бэкенд только для чтения, значение, коллизия, запись. `checkStore(name)` SHALL выполнять проверки имени, бэкенда только для чтения и коллизии без значения и без изменения хранилища, чтобы CLI не читал значение, которое всё равно будет отвергнуто (design.md, D8). Готовый текст подсказки `SecretReadOnly` строит потребитель (`SecretCommands`, страница настроек) с настоящим путём `$CODELAB_HOME`. Значение SHALL передаваться только в памяти: не через argv, stdin или лог; результаты и их `toString` НЕ SHALL содержать значения. Список имён SHALL вести тот же бэкенд, что у CLI.

#### Scenario: Запись из приложения и список в CLI
- **WHEN** `SecretAdmin.store("codelab/openai", "sk-test-0123456789abcdef")` выполняется над бэкендом `file` во временном `CODELAB_HOME`, затем `codelab secret list` с тем же `CODELAB_HOME` и `secrets.backend: file`
- **THEN** результат — `SecretStored`, ни один дочерний процесс не получил значения в argv или stdin, `list` показывает `codelab/openai`

#### Scenario: Отказ без исключения
- **WHEN** `store("Bad Name", "v")` и `store("codelab/a", "a\nb")`
- **THEN** результаты `SecretInvalidName` и `SecretInvalidValue`, хранилище не вызывалось, тексты результатов не содержат значения

#### Scenario: Предварительная проверка без значения
- **WHEN** `checkStore` вызывается для допустимого имени над бэкендом `file`, для `Bad Name`, для любого имени над `env` и для `codelab/a.b` при сохранённом `codelab/a-b`
- **THEN** результаты — `null`, `SecretInvalidName`, `SecretReadOnly` и `SecretCollision` соответственно; файл `secrets.yaml` не создан и не изменён

#### Scenario: Бэкенд только для чтения на Windows
- **WHEN** `store("codelab/openai", "v")` над `env` с подменённой платформой `windows`
- **THEN** результат — `SecretReadOnly(backend: env, variable: CODELAB_SECRET_CODELAB_OPENAI, fileBackendOffered: false)`; на macOS и Linux — `fileBackendOffered: true`
