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
- stdio-профиль, у команды которого базовое имя `codelab-agent` (параметр `command`), — `EditableSettings`. Самоназвание агента из `initialize` МОЖЕТ только опровергнуть это решение, когда клиенту оно доступно; в этой версии его в `WorkspaceState` нет, и решение принимается по команде (design.md change `add-provider-setup-ui`, D5). `CODELAB_HOME` берётся из `env` профиля, иначе из окружения клиента; файл `--config` из аргументов — только для чтения;
- stdio-профиль с другой командой — `NotManaged(agentName)`, где `agentName` — базовое имя команды;
- WebSocket-профиль — `RemoteReadOnly(endpoint)`.

Цели записи `EditableSettings` SHALL быть только `ConfigTarget.user()` и `ConfigTarget.projectLocal(cwd)`. `projectLocal` SHALL предлагаться, только если известна папка проекта. Слой 3 и файл `--config` SHALL быть только для чтения (SETUP-3).

#### Scenario: Доступ по профилю (согласовано пользователем 2026-11-06)
- **WHEN** `resolveSettingsAccess` вызывается для встроенного агента, для команды `/usr/local/bin/codelab-agent serve --stdio`, для `python -m other` и для `wss://box:7420`
- **THEN** результаты — `EditableSettings`, `EditableSettings`, `NotManaged('python')` и `RemoteReadOnly(wss://box:7420)`

#### Scenario: Цели без проектного слоя
- **WHEN** `EditableSettings` построен с папкой проекта и с файлом `--config /etc/team.yaml`
- **THEN** цели записи — `user` и `projectLocal(<папка>)`; `project` и `/etc/team.yaml` среди них нет

### Requirement: Снимок и запись конфига агента
`AgentConfigStore.snapshot(cwd)` SHALL возвращать снимки слоёв `user`, `projectLocal` и `project`, итог загрузки (`config`, `issues`, `warnings`, `sources`), источник каждого листового ключа (`origins: Map<String, ConfigSourceView>` — вид источника и подпись) и описание бэкенда секретов. `apply(base, edits)` SHALL записывать правки одним вызовом `ConfigWriter.apply` и переводить результат и исключения ядра в `ConfigSaveOutcome`:
- `ConfigWriteResult` → `ConfigSaved(fingerprint, warnings, restartRequiredKeys)`;
- `ConfigConflictException` → `ConfigConflict(path)`;
- `ConfigInlineSecretException` → `ConfigInlineSecret(key, suggestedSecretName)`; проверяется раньше `ConfigException`;
- `ConfigException(issues)` → `ConfigRejected(issues)`.

Другие исключения НЕ SHALL перехватываться. Конфликт НЕ SHALL разрешаться автоматической перезаписью (SETUP-6).

Слой 3 недоверенного проекта (не в `trusted_projects`) SHALL не попадать ни в слияние листьев снимка, в том числе запасное, когда загрузчик не дал итогового конфига, ни в источник листа `origins` (design.md change `add-provider-setup-ui`, D10). `supportsProviderCheck(kind)` и адрес по умолчанию для вида SHALL давать мост; проверка поддерживается для `openai-compatible` и `anthropic`. `displayBaseUrl(url)` SHALL возвращать адрес без userinfo, query и fragment.

#### Scenario: Недоверенный проект не виден
- **WHEN** `<cwd>/.codelab/config.yaml` недоверенного проекта задаёт провайдера `evil`, а пользовательский конфиг — `anthropic`, в том числе при битом пользовательском слое (запасное слияние)
- **THEN** снимок не содержит листьев `providers.evil`, `origins` не ссылается на проектный файл

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
- **адрес** — `http` или `https`, иначе ошибка шага `Enter an http or https address.`. `http` к хосту вне `localhost`, `127.0.0.0/8` и `::1` (правило `isLocalHost` kit) — только после подтверждения. Подтверждение SHALL относиться к адресу, который сейчас в поле: другой `http`-адрес SHALL требовать нового подтверждения. Завершающий `/` убирается. Адрес с userinfo SHALL отклоняться ошибкой шага `Remove the user name and password from the address.`; query и fragment допустимы;
- **ключ** — `StoreSecret` только при записываемом бэкенде (иначе — причина бэкенда), `UseEnvVar`, `NoKey`, при правке — `KeepStoredSecret`. Если секрет `codelab/<id>` уже есть в хранилище, шаг SHALL предлагать «Use the stored key» и «Replace it». Без явного «Replace it» существующий секрет НЕ SHALL перезаписываться (SETUP-5);
- **проверка** — номер попытки. «Retry», «Back», «Cancel» и `dispose()` SHALL делать прежнюю попытку устаревшей; её поздний результат НЕ SHALL менять состояние. `SkipCheck` — только для `unreachable` и `timeout`, после подтверждения и с предупреждением `Not verified: <kind>` в плане (SETUP-4). `notFound` разрешает ручной ввод модели без пропуска;
- **id** — для пресета id пресета, для custom — из хоста, `[a-z0-9_-]+`, суффиксы `-2`, `-3` при занятом id. Для любого локального хоста (`isLocalHost`: `localhost`, `::1`, `127.x.x.x`) имя хоста SHALL заменяться на `local`, с суффиксом `-<port>` при явном порте: `localhost:1234` → `local-1234`, `127.0.0.1:18765` → `local-18765` (уточнение координатора по итогам ручной проверки итерации 3; раньше правило касалось только `localhost`). Переименование на «Review» SHALL сбрасывать выбор «Replace it»: замена относилась к секрету прежнего имени. При правке id не меняется;
- **`makeDefault`** — `true`, если `agent.default_model` нет; при `forceDefault` (первый запуск CLI, баннер встроенного агента без провайдера) снять его нельзя;
- **окно контекста** — из ответа `/models`, иначе из встроенного каталога моделей ядра; модель из списка с известным окном идёт сразу в `Reviewing`, модель без окна и модель, введённая вручную, — в `EnteringModelDetails` с подсказкой из каталога, иначе `32000`. План SHALL писать `context_window` модели всегда;
- **правка** (`editing`) — старт с `EnteringBaseUrl`, вид, id и слой записи — те же, что у провайдера. Правку, для которой `providerEditRefusal` даёт отказ (`notEditable`, `multipleLayers`, `layerUnreadable`), автомат SHALL отклонять без записи. Userinfo из `base_url` конфига НЕ SHALL показываться: поле адреса — без userinfo, с ошибкой шага `Remove the user name and password from the address.`. Текущая модель провайдера выделена, «Make default» отражает, указывает ли `agent.default_model` на этого провайдера. Для литерального ключа в файле конфига варианта «оставить ключ» НЕ SHALL быть, а новый источник ключа SHALL удалять литерал той же записью (`UnsetValue` `providers.<id>.api_key`);
- **«Back»** — `ChoosingKey → EnteringBaseUrl`, `Checking → ChoosingKey`, `CheckFailed → ChoosingKey` при `unauthorized`, иначе `EnteringBaseUrl`; источник и значение ключа при «Back» с шага ключа и после него НЕ SHALL сохраняться;
- **событие не к месту текущего состояния** — игнорируется и пишется в журнал на уровне `debug`; `Cancel` допустим из любого состояния, кроме `Saving` и `Done`.

`ProviderSetupPlan.toEdits()` SHALL давать листовые `SetValue`/`UnsetValue` §12.4.4, шаг 7. Ключи `api_key_secret` и `api_key_env` взаимоисключающие.

#### Scenario: От пресета до записи
- **WHEN** мастер получает `PresetChosen(anthropic)`, адрес по умолчанию, `StoreSecret`, `CheckOk` с моделью `claude-x` (окно известно), `ConfirmSave`
- **THEN** состояния идут в порядке автомата без `EnteringModelDetails`, правки — `kind`, `base_url`, `api_key_secret: codelab/anthropic`, `models.claude-x.context_window`, `agent.default_model`

#### Scenario: Адрес с userinfo
- **WHEN** на шаге адреса вводится `https://u:sk-test-leak-0123456789@llm.example/v1`, затем `https://llm.example/v1?api-version=2024-10-01`
- **THEN** первый адрес отклонён ошибкой `Remove the user name and password from the address.`, мастер остаётся в `EnteringBaseUrl`, ни состояние, ни журнал не содержат маркера; второй принят

#### Scenario: Подсказка окна из каталога
- **WHEN** проверка возвращает модель `claude-sonnet-5-5` без поля окна (она есть во встроенном каталоге ядра), и пользователь выбирает её; затем другой прогон, где пользователь вводит вручную `my-model`
- **THEN** первый прогон идёт в `Reviewing` с окном из встроенного каталога ядра; второй — в `EnteringModelDetails` с подсказкой `32000`; в обоих планах есть `models.<m>.context_window`

#### Scenario: Правка провайдера с литеральным ключом
- **WHEN** правится провайдер `old` с `api_key` в `config.yaml`, и пользователь выбирает `UseEnvVar(OLD_KEY)`
- **THEN** шаг ключа не предлагает оставить прежний ключ; правки содержат `SetValue(providers.old.api_key_env)` и `UnsetValue(providers.old.api_key)`, а ни одно состояние не содержит значения литерала

#### Scenario: Отказ проверки без пропуска
- **WHEN** проверка даёт `unauthorized`
- **THEN** доступны «Retry» и «Back» на шаг ключа, `SkipCheck` игнорируется

#### Scenario: Поздний результат проверки
- **WHEN** проверка ждёт ответа, пользователь нажимает «Back» дважды (на шаг ключа, затем на шаг адреса) и меняет адрес, после чего приходит `CheckOk` первой попытки
- **THEN** состояние остаётся `EnteringBaseUrl`, журнал содержит `provider_wizard.check_discarded`

#### Scenario: Существующий секрет
- **WHEN** в хранилище есть `codelab/openai`, и пользователь добавляет провайдера `openai` со `StoreSecret`
- **THEN** шаг ключа предлагает «Use the stored key» и «Replace it»; без выбора «Replace it» запись секрета не выполняется

#### Scenario: Переименование после Replace it
- **WHEN** в хранилище есть `codelab/openai`, пользователь выбирает «Replace it» с новым ключом, а на «Review» меняет id на `openai-work`, и в хранилище есть `codelab/openai-work`
- **THEN** план имеет `secretName: codelab/openai-work` и `replaceSecret: false`; «Save» не перезаписывает ни `codelab/openai`, ни `codelab/openai-work`, мастер возвращается на шаг ключа с вариантами «Use the stored key» и «Replace it»

#### Scenario: Подтверждение http для изменённого адреса
- **WHEN** пользователь вводит `http://llm.example/v1`, подтверждает его, возвращается на шаг адреса и вводит `http://other.example/v1`; в другом прогоне вводит `http://127.0.0.1:18765/v1` для пресета «Custom OpenAI-compatible»
- **THEN** второй адрес снова требует подтверждения, журнал содержит два `provider_wizard.insecure_address`; во втором прогоне подтверждения нет, а id провайдера — `local-18765`

#### Scenario: Edit с userinfo в конфиге
- **WHEN** правится провайдер, у которого в `config.yaml` `base_url: https://u:sk-test-leak-0123456789@llm.example/v1`
- **THEN** шаг адреса показывает `https://llm.example/v1` с ошибкой `Remove the user name and password from the address.`; ни одно состояние, ни журнал не содержат `u:` и маркера

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

Тело ответа об ошибке НЕ SHALL попадать в результат. `listModels` SHALL принимать отмену (`cancel`); по таймауту и при отмене соединение SHALL закрываться, а результат отменённой проверки — не возвращаться потребителю как исход.

#### Scenario: Отмена закрывает соединение
- **WHEN** проверка ждёт ответа сервера на loopback, и потребитель отменяет её
- **THEN** соединение закрыто (сервер видит разрыв), исход отмены не принимается за `unreachable` или `timeout`

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
1. для `StoreSecret` — `SecretAdmin.store`. Существующий секрет пишется только при `replaceSecret`; без него committer SHALL перед записью заново проверить имя в хранилище и, если оно появилось, не писать ни секрет, ни конфиг и вернуть мастер на шаг ключа с вариантами «Use the stored key» и «Replace it»;
2. `AgentConfigStore.apply(base, plan.toEdits())`;
3. если исход не `ConfigSaved`, а секрет на шаге 1 создан впервые, — `SecretAdmin.delete`. Заменённый ранее существовавший секрет НЕ SHALL удаляться;
4. если запись секрета не удалась, конфиг НЕ SHALL писаться, а мастер SHALL возвращаться на шаг ключа;
5. исключение `apply` SHALL обрабатываться как неудачная запись: созданный секрет удаляется, исход несёт только имя типа исключения.

Удаление провайдера SHALL удалять секрет только после `ConfigSaved` и только если по свежему снимку после записи ни одна строка конфига на него не ссылается — ни `api_key_secret`, ни подстановка `${secret:<имя>}` в любом значении (заголовки провайдеров, `env` и `headers` MCP) (уточнение SETUP-24; design.md change `add-provider-setup-ui`, D9).

#### Scenario: Откат созданного секрета
- **WHEN** `StoreSecret` записан впервые, а `apply` возвращает `ConfigRejected`
- **THEN** секрет удалён, конфиг не изменён, исход — `SaveFailed` с `ConfigRejected`

#### Scenario: Ранее существовавший секрет сохраняется
- **WHEN** пользователь выбрал «Replace it», секрет перезаписан, а `apply` возвращает `ConfigConflict`
- **THEN** секрет не удалён, исход — `SaveFailed` с `ConfigConflict` и признаком «ключ уже заменён»

#### Scenario: Ключ, на который ссылается MCP-сервер
- **WHEN** удаляется провайдер `gw` с `api_key_secret: codelab/gw` и флажком удаления ключа, а заголовок MCP-сервера `docs` содержит `${secret:codelab/gw}`
- **THEN** провайдер удалён, секрет `codelab/gw` остаётся; если ссылка `docs` появилась между снимком и записью, перепроверка по свежему снимку тоже оставляет секрет

#### Scenario: Секрет появился до записи
- **WHEN** на шаге ключа секрета `codelab/openai` не было, пользователь выбрал `StoreSecret`, а до «Save» другой процесс записал `codelab/openai`
- **THEN** ни секрет, ни конфиг не записаны, мастер на шаге ключа предлагает «Use the stored key» и «Replace it»

#### Scenario: Исключение записи конфига
- **WHEN** `StoreSecret` записан впервые, а `apply` бросает исключение, чей `toString()` содержит `sk-test-leak-0123456789`
- **THEN** секрет удалён, исход — неудачная запись с именем типа исключения, ни исход, ни журнал не содержат маркера

#### Scenario: Хранилище отказало
- **WHEN** `SecretAdmin.store` возвращает `SecretFailed`
- **THEN** `apply` не вызывался, мастер на шаге ключа с предложением переменной окружения

### Requirement: Готовность провайдера
`checkProviderReadiness(snapshot, secrets, env)` SHALL возвращать:
- `ProviderReady(model)`;
- `NoProviderConfigured` — нет ни одного провайдера с моделью (нет файла, нет провайдеров или у них нет моделей), и других проблем нет; признак SHALL вычислять функция моста `providerSetupNeeded(snapshot)`, общая для CLI и app: все проблемы загрузки — вида `value` ключа `agent.default_model`, и при этом среди них есть проблема с событием `config.model.none` либо в конфиге нет ни одного провайдера. Отсутствие ключа `agent.default_model` само по себе мастера не требует: агент стартует с первой моделью первого провайдера (design.md change `optional-default-model`, D3–D4). Текст проблем НЕ SHALL разбираться (design.md change `add-provider-setup-ui`, D26);
- `ProviderKeyMissing(providerId, reference, backend)` — у провайдера модели по умолчанию (`CoreConfig.defaultModel`: явный ключ или первая модель первого провайдера) нет ключа: секрета нет в `names()` и нет переменной `CODELAB_SECRET_<…>`, либо не задана `api_key_env`;
- `ConfigBroken(issues)` — прочие проблемы валидатора.

Значения ключей НЕ SHALL читаться.

#### Scenario: Признак «нет провайдера» по типизированным проблемам
- **WHEN** `providerSetupNeeded` получает снимки настоящего загрузчика: пустой `CODELAB_HOME`; провайдер `gw` без `agent.default_model`; `agent.default_model: gw/m` без провайдеров; пустой `CODELAB_HOME` плюс `budget.max_steps: 0`; провайдер `gw` и `agent.default_model: gw/typo`
- **THEN** результаты — `true`, `false`, `true`, `false`, `false`

#### Scenario: Состояния готовности
- **WHEN** функция вызывается для пустого `CODELAB_HOME`, для конфига с `api_key_secret: codelab/p` без секрета, для `api_key_env: K` при незаданной `K`, для `budget.max_steps: 0`, для полного конфига и для провайдера `gw` с моделью `m` и заданной `api_key_env` без `agent.default_model`
- **THEN** результаты — `NoProviderConfigured`, `ProviderKeyMissing(reference: secret codelab/p)`, `ProviderKeyMissing(reference: env K)`, `ConfigBroken`, `ProviderReady` и `ProviderReady(gw/m)`

### Requirement: Статус ключа и удаление провайдера
`KeyStatusView` SHALL иметь пять видов: ключ в хранилище (`Key: in <backend>`), ключ отсутствует в хранилище (`Key: missing in <backend>`), переменная окружения (`Key: env <VAR> (set|not set)`), без ключа (`No key`) и литеральный ключ в файле конфига `KeyLiteralInConfig` (`Key: in config file (plain text)`). Ни один вид НЕ SHALL содержать значения ключа.

План удаления провайдера (`ProviderRemover`) SHALL отказывать до записи типизированно: `unknownProvider`, `notEditable`, `multipleLayers` (листья провайдера в нескольких слоях), `layerUnreadable` (файл слоя не читается), `lastProvider`, `newDefaultRequired`, `newDefaultInvalid`, `defaultOverridden` (`agent.default_model` задан в слое выше слоя провайдера) (design.md change `add-provider-setup-ui`, D9).

#### Scenario: Литеральный ключ
- **WHEN** провайдер `old` задан в `config.yaml` с `api_key: sk-test-leak-0123456789`
- **THEN** статус ключа — `KeyLiteralInConfig` с подписью `Key: in config file (plain text)`, ни вид, ни его `toString()` не содержат маркера

#### Scenario: Провайдер в двух слоях
- **WHEN** `providers.gw.kind` задан в `user`, а `providers.gw.models` — в `projectLocal`, и строится план удаления `gw`
- **THEN** результат — отказ `multipleLayers`, файлы не изменены

#### Scenario: Модель по умолчанию из верхнего слоя
- **WHEN** провайдер `gw` и `agent.default_model: gw/m` заданы в `user`, а `agent.default_model` переопределён в `projectLocal`, и строится план удаления `gw`
- **THEN** результат — отказ `defaultOverridden`, файлы не изменены

### Requirement: Черновик MCP-сервера
`McpServerDraft` SHALL описывать форму добавления и правки сервера (§12.4.6, шаг 3).

`validate()` SHALL возвращать проблемы до записи:
- имя по правилу ядра, общему с `codelab mcp add` (непустое, без пробелов, `[`, `]` и `"`; решение Q20 design.md), уникальное в эффективном конфиге;
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
