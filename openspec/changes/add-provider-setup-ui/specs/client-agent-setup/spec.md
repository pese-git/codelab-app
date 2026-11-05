## ADDED Requirements

### Requirement: Состав моста codelab_setup для настройки агента
Мост `packages/dart/codelab_setup` SHALL давать клиентам логику настройки Dart-агента, общую для codelab-app и CLI (`dart-agent-and-clients` §12.4.2; design.md change `add-provider-setup-ui`, D2).

**Основной барель** `codelab_setup.dart` (чистый Dart, web-безопасно):
- `SecretValue`;
- `SettingsAccess` и `resolveSettingsAccess`;
- порт `AgentConfigStore`, `AgentConfigSnapshot`, `ConfigSaveOutcome`;
- модели представления `ProviderEntryView`, `KeyStatusView`, `McpServerEntryView`, `SettingFieldView`;
- `McpServerDraft`;
- `ProviderPreset` и таблица пресетов;
- `ProviderSetupFlow` с состояниями и событиями, `ProviderSetupPlan`, `ProviderSetupCommitter`;
- порт `ProviderCheck`, `HttpProviderCheck`;
- `ProviderReadiness` и `checkProviderReadiness`;
- реэкспорт чистых типов ядра `ConfigLayer`, `ConfigTarget`, `ConfigSnapshot`, `ConfigEdit` с подклассами, `ConfigConflictException`, `SettingsRegistry`, `SettingDescriptor`, `SettingScope`, `SettingType`, `SecretNames`, `SecretBackendInfo`.

**`io.dart`:**
- `FileAgentConfigStore`;
- `ClientSecretAccess` (spec agent-secrets «Клиентский доступ к секретам»);
- `ioProviderCheck()`.

Клиенты НЕ SHALL реализовывать шаги мастера, проверку `/models` и порядок записи сами (SETUP-8).

#### Scenario: Один автомат для двух клиентов
- **WHEN** тесты app и CLI проводят мастер одними и теми же событиями над фейковыми `ProviderCheck` и `AgentConfigStore`
- **THEN** последовательности состояний и списки `ConfigEdit` совпадают

#### Scenario: Основной барель собирается для web
- **WHEN** выполняется `melos run web-compile`
- **THEN** основной барель `codelab_setup` компилируется без `dart:io`

### Requirement: Доступ к настройкам агента
`resolveSettingsAccess` SHALL определять, может ли клиент читать и писать конфиг агента профиля (design.md change `add-provider-setup-ui`, D5):
- встроенный агент — `EditableSettings`;
- stdio-профиль, чья команда — `codelab-agent` и, если клиент уже подключён, `agentInfo.name` в `initialize` равен `codelab-agent`, — `EditableSettings`. `CODELAB_HOME` берётся из `env` профиля, иначе из окружения клиента; файл `--config` из аргументов — только для чтения;
- stdio-профиль другого агента — `NotManaged(agentName)`;
- WebSocket-профиль — `RemoteReadOnly(endpoint)`.

Цели записи `EditableSettings` SHALL быть только `ConfigTarget.user()` и `ConfigTarget.projectLocal(cwd)`. `projectLocal` SHALL предлагаться, только если известна папка проекта. Слой 3 и файл `--config` SHALL быть только для чтения (SETUP-3).

#### Scenario: Доступ по профилю
- **WHEN** `resolveSettingsAccess` вызывается для встроенного агента, для `codelab-agent serve --stdio`, для `python -m other` с `agentInfo.name: other` и для `wss://box:7420`
- **THEN** результаты — `EditableSettings`, `EditableSettings`, `NotManaged('other')` и `RemoteReadOnly(wss://box:7420)`

#### Scenario: Цели без проектного слоя
- **WHEN** `EditableSettings` построен с папкой проекта и с файлом `--config /etc/team.yaml`
- **THEN** цели записи — `user` и `projectLocal(<папка>)`; `project` и `/etc/team.yaml` среди них нет

### Requirement: Снимок и запись конфига агента
`AgentConfigStore.snapshot(cwd)` SHALL возвращать снимки слоёв `user`, `projectLocal` и `project`, итог загрузки (`config`, `issues`, `warnings`, `sources`), источник каждого листового ключа и описание бэкенда секретов. `apply(base, edits)` SHALL записывать правки одним вызовом `ConfigWriter.apply` и переводить результат и исключения ядра в `ConfigSaveOutcome`:
- `ConfigWriteResult` → `ConfigSaved(fingerprint, warnings, restartRequiredKeys)`;
- `ConfigConflictException` → `ConfigConflict(path)`;
- `ConfigInlineSecretException` → `ConfigInlineSecret(key, suggestedSecretName)`; проверяется раньше `ConfigException`;
- `ConfigException(issues)` → `ConfigRejected(issues)`.

Другие исключения НЕ SHALL перехватываться. Конфликт НЕ SHALL разрешаться автоматической перезаписью (SETUP-6).

#### Scenario: Конфликт не перезаписывает файл
- **WHEN** между `snapshot` и `apply` тест меняет `config.yaml`
- **THEN** `apply` возвращает `ConfigConflict` с путём файла, файл содержит правку теста

#### Scenario: Литеральный секрет
- **WHEN** `apply` получает `UpsertMcpServer` с заголовком `Authorization: Bearer sk-test-leak-0123456789`
- **THEN** результат — `ConfigInlineSecret` с ключом заголовка и предложенным именем `codelab/mcp/<server>/authorization`, файл не изменён

### Requirement: Значение секрета в памяти клиента
`SecretValue` SHALL хранить значение ключа или секрета в памяти клиента. `toString()` и JSON-представление SHALL давать `***`, значение доступно только через `reveal()` (SETUP-1). Значение НЕ SHALL попадать в `ProviderSetupState.toString()`, `ProviderSetupPlan`, `toEdits()`, `McpServerDraft.toString()` и журнал. `dispose()` мастера, `Cancel` и `Done` SHALL сбрасывать ссылку на значение.

#### Scenario: Значение не печатается
- **WHEN** мастер с ключом `sk-test-leak-0123456789` проходит все состояния, а тест собирает `toString()` каждого состояния, плана и правок
- **THEN** ни одна строка не содержит маркера

### Requirement: Мастер провайдера
`ProviderSetupFlow` SHALL быть автоматом §12.4.4 (`ChoosingPreset → EnteringBaseUrl → ChoosingKey → Checking → ChoosingModel → [EnteringModelDetails] → Reviewing → Saving → Done`, плюс `CheckFailed`, `SaveFailed`, `Cancelled`) с уточнениями design.md change `add-provider-setup-ui`, D7:
- **пресеты** — OpenAI, Anthropic, OpenRouter, Ollama (без ключа), «Custom OpenAI-compatible», «Custom Anthropic-compatible»;
- **адрес** — `http` или `https`. `http` к хосту вне `localhost`, `127.0.0.0/8` и `::1` — только после подтверждения, которое сбрасывается правкой адреса. Завершающий `/` убирается;
- **ключ** — `StoreSecret` только при записываемом бэкенде (иначе — причина бэкенда), `UseEnvVar`, `NoKey`, при правке — `KeepStoredSecret`. Если секрет `codelab/<id>` уже есть в хранилище, шаг SHALL предлагать «Use the stored key» и «Replace it». Без явного «Replace it» существующий секрет НЕ SHALL перезаписываться (SETUP-5);
- **проверка** — номер попытки. «Retry», «Back», «Cancel» и `dispose()` SHALL делать прежнюю попытку устаревшей; её поздний результат НЕ SHALL менять состояние. `SkipCheck` — только для `unreachable` и `timeout`, после подтверждения и с предупреждением `Not verified: <kind>` в плане (SETUP-4). `notFound` разрешает ручной ввод модели без пропуска;
- **id** — для пресета id пресета, для custom — из хоста (`localhost:1234` → `local-1234`), `[a-z0-9_-]+`, суффиксы `-2`, `-3` при занятом id. При правке id не меняется;
- **`makeDefault`** — `true`, если `agent.default_model` нет;
- **событие не к месту текущего состояния** — игнорируется и пишется в журнал на уровне `debug`; `Cancel` допустим из любого состояния, кроме `Saving` и `Done`.

`ProviderSetupPlan.toEdits()` SHALL давать листовые `SetValue`/`UnsetValue` §12.4.4, шаг 7. Ключи `api_key_secret` и `api_key_env` взаимоисключающие.

#### Scenario: От пресета до записи
- **WHEN** мастер получает `PresetChosen(anthropic)`, адрес по умолчанию, `StoreSecret`, `CheckOk` с моделью `claude-x` (окно известно), `ConfirmSave`
- **THEN** состояния идут в порядке автомата без `EnteringModelDetails`, правки — `kind`, `base_url`, `api_key_secret: codelab/anthropic`, `models.claude-x.context_window`, `agent.default_model`

#### Scenario: Отказ проверки без пропуска
- **WHEN** проверка даёт `unauthorized`
- **THEN** доступны «Retry» и «Back» на шаг ключа, `SkipCheck` игнорируется

#### Scenario: Поздний результат проверки
- **WHEN** проверка ждёт ответа, пользователь нажимает «Back» и меняет адрес, после чего приходит `CheckOk` первой попытки
- **THEN** состояние остаётся `EnteringBaseUrl`, журнал содержит `provider_wizard.check_discarded`

#### Scenario: Существующий секрет
- **WHEN** в хранилище есть `codelab/openai`, и пользователь добавляет провайдера `openai` со `StoreSecret`
- **THEN** шаг ключа предлагает «Use the stored key» и «Replace it»; без выбора «Replace it» запись секрета не выполняется

### Requirement: Проверка списка моделей
`HttpProviderCheck.listModels(kind, baseUrl, key, timeout)` SHALL выполнять (§12.4.4, шаг 4):
- для OpenAI-совместимого вида — `GET <base_url>/models` с `Authorization: Bearer <key>`;
- для Anthropic — `GET <base_url>/v1/models` с `x-api-key` и `anthropic-version`.

Запрос SHALL идти только на введённый адрес, с таймаутом (по умолчанию 10 с) и без следования редиректам: ответ `3xx` SHALL давать `badResponse` со статусом (SETUP-10, SETUP-23). Ключ SHALL уходить только в заголовке авторизации. Итоги:
- `200` с `data[].id` → `CheckOk` с моделями и окном контекста из `context_length`, `context_window` или `max_context_length`;
- `401`/`403` → `unauthorized`;
- `404` → `notFound`;
- ошибка соединения, TLS или таймаут → `unreachable`, `tlsError` или `timeout`;
- прочее → `badResponse`.

Тело ответа об ошибке НЕ SHALL попадать в результат. По таймауту и при отмене соединение SHALL закрываться.

#### Scenario: Заголовки и пути
- **WHEN** `HttpProviderCheck` на `MockClient` проверяет OpenAI-совместимый `https://h/v1` и Anthropic `https://a` с ключом `k`
- **THEN** запросы — `GET https://h/v1/models` с `Authorization: Bearer k` и `GET https://a/v1/models` с `x-api-key: k` и `anthropic-version`

#### Scenario: Редирект не выполняется
- **WHEN** сервер на loopback отвечает на `/v1/models` статусом `302` с `Location` на другой порт
- **THEN** результат — `badResponse(302)`, второй сервер не получил запроса и ключа

#### Scenario: Тело ошибки скрыто
- **WHEN** сервер отвечает `401` с телом `invalid key sk-test-leak-0123456789`
- **THEN** результат — `unauthorized`, ни результат, ни журнал не содержат маркера

### Requirement: Порядок записи провайдера
`ProviderSetupCommitter.commit(plan, base)` SHALL записывать провайдера в порядке «секрет → конфиг» (SETUP-5; design.md change `add-provider-setup-ui`, D9):
1. для `StoreSecret` — `SecretAdmin.store`. Существующий секрет пишется только при `replaceSecret`;
2. `AgentConfigStore.apply(base, plan.toEdits())`;
3. если исход не `ConfigSaved`, а секрет на шаге 1 создан впервые, — `SecretAdmin.delete`. Заменённый ранее существовавший секрет НЕ SHALL удаляться;
4. если запись секрета не удалась, конфиг НЕ SHALL писаться, а мастер SHALL возвращаться на шаг ключа.

Удаление провайдера SHALL удалять секрет только после `ConfigSaved`.

#### Scenario: Откат созданного секрета
- **WHEN** `StoreSecret` записан впервые, а `apply` возвращает `ConfigRejected`
- **THEN** секрет удалён, конфиг не изменён, исход — `SaveFailed` с `ConfigRejected`

#### Scenario: Ранее существовавший секрет сохраняется
- **WHEN** пользователь выбрал «Replace it», секрет перезаписан, а `apply` возвращает `ConfigConflict`
- **THEN** секрет не удалён, исход — `SaveFailed` с `ConfigConflict` и признаком «ключ уже заменён»

#### Scenario: Хранилище отказало
- **WHEN** `SecretAdmin.store` возвращает `SecretFailed`
- **THEN** `apply` не вызывался, мастер на шаге ключа с предложением переменной окружения

### Requirement: Готовность провайдера
`checkProviderReadiness(snapshot, secrets, env)` SHALL возвращать:
- `ProviderReady(model)`;
- `NoProviderConfigured` — нет файла, провайдеров или `agent.default_model`, и других проблем нет;
- `ProviderKeyMissing(providerId, reference, backend)` — у провайдера модели по умолчанию нет ключа: секрета нет в `names()` и нет переменной `CODELAB_SECRET_<…>`, либо не задана `api_key_env`;
- `ConfigBroken(issues)` — прочие проблемы валидатора.

Значения ключей НЕ SHALL читаться.

#### Scenario: Состояния готовности
- **WHEN** функция вызывается для пустого `CODELAB_HOME`, для конфига с `api_key_secret: codelab/p` без секрета, для `api_key_env: K` при незаданной `K`, для `budget.max_steps: 0` и для полного конфига
- **THEN** результаты — `NoProviderConfigured`, `ProviderKeyMissing(reference: secret codelab/p)`, `ProviderKeyMissing(reference: env K)`, `ConfigBroken` и `ProviderReady`

### Requirement: Черновик MCP-сервера
`McpServerDraft` SHALL описывать форму добавления и правки сервера (§12.4.6, шаг 3).

`validate()` SHALL возвращать проблемы до записи:
- имя `[A-Za-z0-9_-]+`, уникальное в эффективном конфиге;
- для `stdio` — команда;
- для `http` — URL `http`/`https` без userinfo;
- ключи `env` и `headers` не пусты.

`toEdits()` SHALL давать одну правку `UpsertMcpServer(map)`. Значение, помеченное «Secret», SHALL заменяться целиком подстановкой `${secret:<SecretNames.forMcp(name, key)>}`. Значение, вписанное пользователем со своей ссылкой (`Bearer ${secret:…}`, `${VAR}`), остаётся текстом.

`secretsToWrite()` SHALL возвращать имена и значения для записи. Значение «не менять» при правке в этот список НЕ SHALL попадать.

#### Scenario: Секретный заголовок
- **WHEN** черновик `github` (`http`) содержит заголовок `Authorization`, помеченный «Secret», со значением `v`
- **THEN** `toEdits()` содержит `Authorization: "${secret:codelab/mcp/github/authorization}"`, `secretsToWrite()` — `codelab/mcp/github/authorization` → `v`, а `toString()` черновика не содержит `v`

#### Scenario: Ошибки черновика
- **WHEN** черновик имеет имя `a b`, тип `http` и URL `https://u:p@h/mcp`
- **THEN** `validate()` возвращает проблемы имени и userinfo, правок нет
