# client-agent-setup Specification

## Purpose
Общая логика настройки Dart-агента для codelab-app и CLI в мосте `packages/dart/codelab_setup`: состав барелей, доступ к настройкам (`SettingsAccess`), снимок и запись конфига агента (`AgentConfigStore`), значение секрета только в памяти клиента, мастер провайдера с проверкой списка моделей и порядком записи «секрет → конфиг», готовность провайдера, статус ключа и удаление провайдера, черновик MCP-сервера. Значения секретов не попадают в конфиг, UI и журнал. Устройство — `docs/architecture/proposals/dart-agent-and-clients/12-4-first-run-and-settings.md` §12.4.2–§12.4.6; история решений — архив change `2026-11-09-add-provider-setup-ui`.
## Requirements
### Requirement: Состав моста codelab_setup для настройки агента
Мост `packages/dart/codelab_setup` SHALL давать клиентам логику настройки Dart-агента, общую для codelab-app и CLI (`dart-agent-and-clients` §12.4.2; design.md change `add-provider-setup-ui`, D2; design.md change `add-app-skills-page`, D4).

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
- вид расширений агента `AgentExtensionsView` (`ContextFileView`, `SkillEntryView`, `TemplateEntryView`, кандидаты согласия) с построителем `agentExtensionsOf` и правило записи `skillsListEdit` для `skills.disabled` и `skills.extra_roots`;
- реэкспорт чистых типов ядра `ConfigLayer`, `ConfigTarget`, `ConfigSnapshot`, `ConfigEdit` с подклассами, `ConfigConflictException`, `SettingsRegistry`, `SettingDescriptor`, `SettingScope`, `SettingType`, `SecretNames`, `SecretBackendInfo`, `ExtensionScope`, `ExtensionDiagnostic`, `DiagnosticLevel`.

**`io.dart`:**
- `FileAgentConfigStore`;
- `ClientSecretAccess` (spec agent-secrets «Клиентский доступ к секретам»);
- `ioProviderCheck()`;
- `readAgentExtensions` — чтение файлов проекта и навыков папки для вида расширений.

Клиенты НЕ SHALL реализовывать шаги мастера, проверку `/models`, порядок записи, правила корней, доверия и перекрытия навыков и правила записи списков `skills.*` сами (SETUP-8).

#### Scenario: Один автомат для двух клиентов
- **WHEN** тесты app и CLI проводят мастер одними и теми же событиями над фейковыми `ProviderCheck` и `AgentConfigStore`
- **THEN** последовательности состояний и списки `ConfigEdit` совпадают

#### Scenario: Основной барель собирается для web
- **WHEN** выполняется `melos run web-compile`
- **THEN** основной барель `codelab_setup`, включая `AgentExtensionsView` и `agentExtensionsOf`, компилируется без `dart:io`

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
- при правке имя НЕ SHALL меняться: изменённое имя — проблема `Remove the server and add it again to rename it.`;
- имя по правилу ядра, общему с `codelab mcp add` (непустое, без пробелов, `[`, `]` и `"`; решение Q20 design.md), уникальное в эффективном конфиге;
- для `stdio` — команда;
- для `http` — URL `http`/`https` без userinfo;
- ключи `env` и `headers` не пусты.

`toEdits()` SHALL давать одну правку `UpsertMcpServer(map)`. Значение, помеченное «Secret», SHALL заменяться целиком подстановкой `${secret:<SecretNames.forMcp(name, key)>}`. Значение, вписанное пользователем со своей ссылкой (`Bearer ${secret:…}`, `${VAR}`), остаётся текстом.

`secretsToWrite()` SHALL возвращать имена и значения для записи только из таблицы текущего типа (`env` у `stdio`, `headers` у `http`). Значение «не менять» при правке в этот список НЕ SHALL попадать. Два ключа, дающие после нормализации одно имя секрета, SHALL быть проблемой `validate()`.

Вид `McpServerEntryView` SHALL показывать значение заголовка, только если оно целиком ссылка `${…}`; иначе — маску.

#### Scenario: Секретный заголовок
- **WHEN** черновик `github` (`http`) содержит заголовок `Authorization`, помеченный «Secret», со значением `v`
- **THEN** `toEdits()` содержит `Authorization: "${secret:codelab/mcp/github/authorization}"`, `secretsToWrite()` — `codelab/mcp/github/authorization` → `v`, а `toString()` черновика не содержит `v`

#### Scenario: Ошибки черновика
- **WHEN** черновик имеет имя `a b`, тип `http` и URL `https://u:p@h/mcp`
- **THEN** `validate()` возвращает проблемы имени и userinfo, правок нет

### Requirement: Умолчания новой сессии в мосте
Основной барель `codelab_setup` (чистый Dart, web-безопасно) SHALL давать `SessionDefaultsView` и `sessionDefaultsOf(AgentConfigSnapshot snapshot, EditableSettings access)` (design.md change `add-settings-agents-modes`, D6):
- итоговый режим новой сессии из разобранного итога загрузки (`CoreConfig`), а не из сырого листа: псевдонимы (`acceptEdits`, `alwaysAsk`) приводятся к `accept-edits`, `ask`; сочетание `ask` и `plan` даёт `ask` с признаком запрета `write` и `exec`;
- источник режима — `originOf('permissions.mode')`, без листа — `default` с умолчанием профиля хоста `standard`;
- для сочетания `ask` и `plan` источник — слой `user`, только если `permissions.mode` в листьях слоя `user` даёт `ask` (основной id или псевдоним `alwaysAsk`); иначе источник снимка без подмены. Ветки по режиму флага запуска (`autopilot`) представление НЕ SHALL иметь (design.md, D6);
- признак сужения проектом — предупреждение `config.project.untrusted_key` с путём `permissions.mode` в итоге загрузки;
- итоговый `agent.effort` и его источник, без листа — `default` и `medium`;
- предлагаемую цель записи: редактируемый слой источника `permissions.mode`, иначе `user`; `projectLocal` — только если его даёт `access`.

Клиенты НЕ SHALL сами разбирать слои, псевдонимы режимов и правила доверия для этих ключей (SETUP-8).

#### Scenario: Псевдоним и источник
- **WHEN** пользовательский слой задаёт `permissions.mode: acceptEdits`, а `agent.effort` не задан
- **THEN** `sessionDefaultsOf` возвращает режим `accept-edits` с источником `user` и effort `medium` с источником `default`

#### Scenario: Сужение проектом
- **WHEN** пользовательский слой задаёт `standard`, а недоверенный проект в `config.local.yaml` — `bypass`
- **THEN** режим — `standard`, признак сужения истинен

#### Scenario: Источник сочетания ask и plan из слоя user
- **WHEN** пользовательский слой задаёт `permissions.mode: alwaysAsk`, а недоверенный проект — `plan`
- **THEN** режим — `ask` с признаком запрета `write` и `exec`, источник — `user`, предлагаемая цель — `user`

#### Scenario: Сочетание ask и plan без ask в слое user
- **WHEN** `ask` задан не слоем `user` (окружение или `--config`), а недоверенный проект задаёт `plan`
- **THEN** источник режима — источник снимка, а не `user`

#### Scenario: Основной барель без dart:io
- **WHEN** выполняется `melos run web-compile`
- **THEN** `SessionDefaultsView`, `sessionDefaultsOf` и `AgentDefinitionRowView` компилируются в составе основного бареля без `dart:io`

### Requirement: Строки определений агентов в мосте
Мост SHALL давать строки таблицы определений агентов, построенные тем же разбором, что у агента и `config check` (design.md change `add-settings-agents-modes`, D7):
- основной барель — `AgentDefinitionRowView` (имя, описание, источник, «где доступно», инструменты, модель, статус, строка ошибки) и чистая функция построения строк по определениям, диагностике, встроенным типам субагентов и признаку `subagents.enabled`;
- `io.dart` — `agentDefinitionRowsAt` (с отменой внешним токеном `cancel`), которая читает `$CODELAB_HOME/agents` и, только для доверенного проекта, `<project>/.codelab/agents` функцией `codelab_agent_io` тем же загрузчиком файлов проекта, что `config check`, и общей с ним функцией разбора определений (каталог моделей итогового конфига и `parseAgentDefinitions`), с тайм-аутом 5 с (design.md, D20.2); результат SHALL сообщать, существуют ли каталоги `$CODELAB_HOME/agents` и `<project>/.codelab/agents` (по раскрытой символической ссылке: каталог-ссылка существует, битая ссылка — нет; design.md, D21), и явный признак `projectTrusted` (без папки — ложь), чтобы клиент не проверял файловую систему сам и не выводил доверие из диагностики (design.md, D19);
- доверие проекта (канонический путь папки против `trusted_projects`, без раскрытого пути — недоверенный) SHALL считаться одной публичной функцией `codelab_agent_io`, которую вызывают и `config check` (через `loadProjectExtensions`), и мост; вывод `config check` при этом НЕ SHALL меняться (SETUP-8; design.md, D19).

Строки SHALL идти в порядке: `default`, встроенные `general`, `explore`, `review`, `plan`, затем файлы по имени. Файл, отклонённый с диагностикой «модель вне каталога», SHALL получать статус `Model not configured`. Ядро отдаёт её кодом `invalid_value` с сообщением, равным публичной константе ядра (design.md, D18); мост SHALL распознавать её по коду `invalid_value` и точному равенству сообщения этой константе, без своей копии текста, а код диагностики и вывод `config check` НЕ SHALL меняться. Прочий `error` — `Error` со строкой диагностики; `duplicate` — `Not loaded: duplicate name`; пользовательский файл с `shadowed` — `Shadowed by project`. Встроенный тип, который заменило определение с тем же именем и областью `subagent` или `both`, SHALL получать статус `Overridden by <путь>`; при `subagents.enabled: false` встроенные типы SHALL оставаться в строках со статусом `Subagents off` (решение пользователя 2026-11-16, Q12 (а)). Имя строки отклонённого файла — имя файла без `.md`. Тела определений, имена неизвестных ключей и фрагменты файлов НЕ SHALL попадать в строки. У строк отклонённых файлов «где доступно», инструменты и модель SHALL быть пустыми (клиент показывает `—`); модель `session model` — только у `default`, встроенных типов и рабочих определений без модели (design.md, D19).

Вывод `config check` при этом НЕ SHALL меняться (spec agent-configuration «config check показывает диагностику файлов проекта»).

#### Scenario: Тот же разбор, что у config check
- **WHEN** `$CODELAB_HOME/agents/reviewer.md` содержит неизвестный ключ `color` в строке 4
- **THEN** `codelab config check` печатает `warning: …/reviewer.md:4:1: unknown frontmatter key`, а строка моста `reviewer` имеет статус `Error` со строкой `4` и тем же сообщением без `color`

#### Scenario: Недоверенный проект
- **WHEN** папка проекта не в `trusted_projects`, а в `<project>/.codelab/agents/` есть валидный `reviewer.md`
- **THEN** строк из проектного каталога нет, а результат содержит диагностику `untrusted_project` для `<project>/.codelab/agents`

#### Scenario: Определение заменяет встроенный тип
- **WHEN** `$CODELAB_HOME/agents/review.md` валиден со `scope: both`
- **THEN** строка встроенного `review` имеет статус «заменён» с путём `$CODELAB_HOME/agents/review.md` (app показывает `Overridden by ~/.codelab/agents/review.md`), а строка файла `review` — `Available` с «где доступно» `both`

#### Scenario: Выключенные субагенты
- **WHEN** итоговый конфиг задаёт `subagents.enabled: false`
- **THEN** строки `general`, `explore`, `review`, `plan` присутствуют со статусом `Subagents off`

#### Scenario: Модель вне каталога по константе ядра
- **WHEN** `$CODELAB_HOME/agents/docs-writer.md` задаёт `model: openai/gpt-x`, а провайдера `openai` в итоговом конфиге нет
- **THEN** настоящий `parseAgentDefinitions` даёт диагностику `error` с кодом `invalid_value` и сообщением, равным константе ядра, строка моста `docs-writer` имеет статус `Model not configured`, а `codelab config check` печатает ту же диагностику без изменений

#### Scenario: Другой invalid_value не считается моделью
- **WHEN** `migrator.md` задаёт недопустимое значение другого поля (диагностика `invalid_value` с другим сообщением)
- **THEN** строка `migrator` имеет статус `Error` со строкой диагностики, а не `Model not configured`

#### Scenario: Признак наличия каталогов
- **WHEN** во временном `CODELAB_HOME` нет `agents`, а у доверенного проекта есть `.codelab/agents`
- **THEN** результат `agentDefinitionRowsAt` сообщает, что пользовательского каталога нет, а проектный есть; ни один каталог не создан

#### Scenario: Признак доверия в результате
- **WHEN** папка проекта не в `trusted_projects`, а `<project>/.codelab/agents` существует
- **THEN** `agentDefinitionRowsAt` возвращает `projectTrusted: false` и `projectDirectoryExists: true`; без папки — `projectTrusted: false` и `projectDirectory: null`

#### Scenario: Одно правило доверия с config check
- **WHEN** проект открыт по пути-ссылке `/tmp/demo-link`, а в `trusted_projects` записан канонический путь его цели
- **THEN** и мост (`projectTrusted: true`), и `codelab config check` (строки проектных файлов без `note: … the project is not trusted`) считают проект доверенным одной функцией `codelab_agent_io`; вывод `config check` совпадает с выводом до change

#### Scenario: Каталог-ссылка считается существующим
- **WHEN** `<project>/.codelab/agents` доверенного проекта — символическая ссылка на каталог, а `$CODELAB_HOME/agents` — битая ссылка
- **THEN** `agentDefinitionRowsAt` возвращает `projectDirectoryExists: true` и `userDirectoryExists: false`

#### Scenario: Пустые поля отклонённого файла
- **WHEN** `migrator.md` отклонён с диагностикой `error` и задаёт `tools: [read]`, `scope: both`
- **THEN** строка моста `migrator` не содержит инструментов, «где доступно» и модели, а строка `default` содержит модель сессии

### Requirement: Типизированные ошибки и пояснения мастера провайдера
`ProviderSetupFlow` SHALL сопровождать каждое текстовое сообщение шага типизированными данными. По ним клиент строит текст на своём языке и не разбирает строку моста:
- состояния `EnteringBaseUrl`, `ChoosingKey`, `EnteringModelDetails` с ошибкой шага и `Reviewing` с ошибкой правки SHALL нести код ошибки (`errorCode`) из закрытого перечисления: адрес не `http` и не `https`; адрес с userinfo; хранилище секретов только для чтения; пустой ключ; сохранённый ключ уже есть; нечего оставлять; пустое имя переменной окружения; хранилище не записало ключ; окно контекста не положительное; лимит вывода не положительный; id провайдера занят или не подходит под шаблон; цель записи недоступна;
- у `EnteringBaseUrl`, `ChoosingKey` и `EnteringModelDetails` `error` SHALL быть задан тогда и только тогда, когда задан `errorCode`. Ошибку `Reviewing` SHALL сопровождать ровно одно из двух: `errorCode` (ошибка правки) или `refusal` (`PlanRefusal`, отказ записи плана);
- аргументы сообщений SHALL браться из полей состояния. У «сохранённый ключ уже есть» это имя секрета `existingSecret` (задано всегда вместе с этим кодом) и бэкенд `backend.id`. У «только чтение» — подсказка `readOnlyHint` и причина `backend.unavailableReason`, если они есть;
- `ChoosingKey` SHALL нести признак `literalKeyInConfig`: правится провайдер с литеральным ключом в файле конфига, и шаг показывает пояснение `notice`;
- `Reviewing` SHALL нести `notVerified` — вид пропущенной проверки (`unreachable` или `timeout`), если план записывается без проверки; иначе `null`.

Поля `error`, `notice` и `warnings` и их тексты SHALL не меняться: CLI показывает их как раньше. Новые поля SHALL быть аддитивными. Основной барель SHALL оставаться web-безопасным и без зависимости от локали. Тексты, которые мост получает от хранилища секретов или ядра агента, SHALL передаваться как есть. Это причина отказа записи ключа, подсказка бэкенда только для чтения и сообщения проблем конфига `ConfigIssue.message`.

#### Scenario: Пустой ключ
- **WHEN** на шаге ключа при записываемом бэкенде приходит `KeySubmitted(StoreSecret(''))`
- **THEN** состояние — `ChoosingKey` с кодом «пустой ключ» и `error` `Enter the API key.`

#### Scenario: Сохранённый ключ уже есть
- **WHEN** в хранилище есть `codelab/openai`, и пользователь выбирает `StoreSecret` без «Replace it»
- **THEN** `ChoosingKey` несёт код «сохранённый ключ уже есть» и `existingSecret` `codelab/openai`, а `error` — `A stored key codelab/openai already exists in <backend>.`, как до изменения

#### Scenario: Хранилище только для чтения без подсказки
- **WHEN** бэкенд секретов только для чтения, у него нет ни `readOnlyHint`, ни `unavailableReason`, и приходит `KeySubmitted(StoreSecret(…))`
- **THEN** `ChoosingKey` несёт код «хранилище секретов только для чтения» и `error` `The secret store is read-only.`

#### Scenario: Отказ записи плана без кода
- **WHEN** на «Review» приходит `ConfirmSave`, а провайдер с id плана уже появился в конфиге
- **THEN** `Reviewing` несёт `refusal` `providerExists` и `errorCode` `null`, а `error` — `A provider with this id already exists.`

#### Scenario: Ошибка правки на Review
- **WHEN** на «Review» приходит `ReviewEdited(providerId: 'Bad Id')`
- **THEN** `Reviewing` несёт код «id провайдера занят или не подходит под шаблон» и `refusal` `null`

#### Scenario: Литеральный ключ — признак, а не только текст
- **WHEN** правится провайдер с `api_key` в `config.yaml`, и мастер доходит до шага ключа
- **THEN** `ChoosingKey.literalKeyInConfig` — `true`, а `notice` — прежний английский текст

#### Scenario: Пропущенная проверка
- **WHEN** проверка закончилась `timeout`, пользователь подтверждает `SkipCheck`, выбирает модель, и мастер переходит в `Reviewing`
- **THEN** `Reviewing.notVerified` — `timeout`, а `warnings` — `Not verified: timeout`

#### Scenario: CLI не меняется
- **WHEN** мастер CLI добавляет провайдера `openai`, в хранилище уже есть `codelab/openai`, и автомат возвращает шаг ключа с ошибкой «сохранённый ключ уже есть»
- **THEN** CLI печатает строку ошибки `A stored key codelab/openai already exists in <backend>.`, как до изменения

#### Scenario: Ошибка с редактируемым провайдером
- **WHEN** мастер начинает правку провайдера, у которого в `base_url` есть userinfo
- **THEN** первое состояние — `EnteringBaseUrl` с кодом «адрес с userinfo» и `error` `Remove the user name and password from the address.`

### Requirement: Типизированные проблемы черновика MCP-сервера
Каждая проблема `McpDraftProblem`, которую возвращает `McpServerDraft.validate()` (и `McpServerInvalid.problems`), SHALL нести код из закрытого перечисления `McpDraftProblemCode`. По коду клиент строит текст на своём языке и не разбирает строку моста. Коды:
- имя не по правилу ядра;
- переименование при правке;
- имя уже есть в эффективном конфиге;
- пустая команда `stdio`;
- URL не `http` и не `https` или без хоста;
- URL с userinfo;
- ключ `env`/`headers` с пробелами по краям;
- два ключа с одним именем;
- пустое имя ключа;
- пустое значение нового секрета;
- два новых секрета с одним именем секрета.

У четырёх кодов о ключе (пробелы, совпадение, пустое значение секрета, совпадение имени секрета) проблема SHALL нести аргумент — имя ключа. У остальных кодов аргумента НЕ SHALL быть. Значение `env`, `headers`, URL или секрета в аргумент и в текст НЕ SHALL попадать.

Код и текст `message` SHALL строиться в одном месте моста. Текст `message` и его формулировки SHALL не меняться: CLI и прежние потребители показывают их как раньше. Для проблемы «два ключа с одним именем», которую клиент находит до построения черновика, мост SHALL давать способ построить проблему с кодом и тем же текстом, чтобы клиент не писал свою фразу. Новые поля SHALL быть аддитивными. Основной барель SHALL оставаться web-безопасным и без зависимости от локали.

#### Scenario: Ошибки черновика с кодами
- **WHEN** черновик имеет имя `a b`, тип `http` и URL `https://u:p@h/mcp`
- **THEN** `validate()` возвращает проблему с кодом «имя не по правилу ядра» и `message` `Use a name without spaces, [, ] or ".` и проблему с кодом «URL с userinfo» и `message` `Remove the user name and password from the URL.`; аргументов у них нет

#### Scenario: Код с именем ключа
- **WHEN** у `stdio`-черновика `docs` в `env` новый секрет `TOKEN` с пустым значением
- **THEN** `validate()` возвращает проблему поля `env` с кодом «пустое значение нового секрета», аргументом `TOKEN` и `message` `Enter the secret value for TOKEN.`

#### Scenario: Инвариант кода
- **WHEN** тест моста прогоняет `validate()` на всех черновиках своих сценариев
- **THEN** у каждой проблемы задан код, аргумент задан ровно у кодов о ключе, а `message` равен прежнему английскому тексту

#### Scenario: Совпавшие ключи до черновика
- **WHEN** клиент нашёл в форме два значения `headers` с именем `Authorization` и строит проблему средствами моста
- **THEN** проблема несёт код «два ключа с одним именем», аргумент `Authorization` и `message` `Two values are named Authorization.`

#### Scenario: CLI и web без изменений
- **WHEN** основной барель собирается для web, а CLI выводит проблемы черновика
- **THEN** сборка проходит, а тексты проблем совпадают с прежними

### Requirement: Типизированные подписи вида навыков
Вид расширений агента SHALL сопровождать английские подписи типизированными данными, по которым клиент строит подпись на своём языке:
- `SkillEntryView` SHALL нести `overridesScope` — область перекрытого навыка, которую называет `overridesLabel` (`Overrides <user|project|extra> skill`). Если подписи нет или она говорит о другом навыке той же области (`Overrides another skill`), `overridesScope` SHALL быть `null`. Правило выбора области SHALL оставаться в мосте, одно для подписи и поля;
- `SkillRootView` SHALL нести `extraEntry` — элемент `skills.extra_roots` как записан (или путь корня, если элемента нет) у известного корня области `extra`; у корней `project` и `user` и у неизвестного корня — `null`.

Подписи `overridesLabel` и `label` и их тексты SHALL не меняться. Новые поля SHALL быть аддитивными, а основной барель SHALL оставаться web-безопасным.

#### Scenario: Навык перекрывает пользовательский
- **WHEN** навык проекта `review` перекрывает навык `review` пользователя
- **THEN** `overridesLabel` — `Overrides user skill`, `overridesScope` — `user`

#### Scenario: Дополнительная папка навыков
- **WHEN** в `skills.extra_roots` записан `~/.claude/skills`, и из него загружен навык
- **THEN** `root.label` — `~/.claude/skills (extra root)`, `root.extraEntry` — `~/.claude/skills`

### Requirement: Правила правки строк настроек агента
Основной барель `codelab_setup` SHALL давать правило «можно ли править строку настроек агента» одной функцией для всех клиентов (SETUP-8; design.md change `add-app-general-page`, D6):
- `settingKeyEditRefusalOf(String key)` → `SettingEditRefusal?` — отказ по самому ключу до чтения слоёв;
- `settingEditRefusalOf(SettingFieldView row)` → `SettingEditRefusal?` — отказ по ключу, источнику и маске строки; `null` — строку можно менять.

`SettingEditRefusal` SHALL быть закрытой иерархией с ветками:
- `UnknownSetting` — ключа нет в реестре или он не `scope: shared`;
- `TrustBoundarySetting` — `trusted_projects`;
- `SecretSetting` — дескриптор `secret: true` или тип `secretName`;
- `ExternalSourceSetting(source)` — источник `config` (`CODELAB_CONFIG`/`--config`) или `env`;
- `MaskedSetting` — `SettingFieldView.masked`.

Ветки SHALL проверяться в этом порядке. Отказ НЕ SHALL содержать значение ключа, а `toString()` отказа — значение строки.

Клиенты SHALL строить свои тексты по ветке отказа и НЕ SHALL повторять правило. `/settings` CLI SHALL сохранить прежние тексты отказов: `Unknown setting <key>. Run /settings to list them.`, `trusted_projects is a trust boundary; it cannot be changed here.`, `Use codelab secret set <name>`, `<key> is set by <source>; it cannot be changed here.`.

#### Scenario: Порядок веток
- **WHEN** строка `providers.gw.api_key_secret` задана переменной окружения
- **THEN** `settingEditRefusalOf` возвращает `SecretSetting`, а не `ExternalSourceSetting`

#### Scenario: Источник config
- **WHEN** `budget.max_steps` задан файлом `--config`
- **THEN** `settingEditRefusalOf` возвращает `ExternalSourceSetting` с источником `config`

#### Scenario: Замаскированное значение
- **WHEN** `providers.gw.base_url` содержит в query литеральный токен, и строка помечена `masked`
- **THEN** `settingEditRefusalOf` возвращает `MaskedSetting`, а `toString()` отказа и строки не содержат токена

#### Scenario: Тексты CLI не меняются
- **WHEN** пользователь CLI вводит `/settings trusted_projects []`
- **THEN** REPL печатает `trusted_projects is a trust boundary; it cannot be changed here.`, как до этого change

#### Scenario: Обычный ключ можно править
- **WHEN** `compaction.enabled` задан в слое `user`
- **THEN** `settingEditRefusalOf` возвращает `null`

### Requirement: Обзор расширений агента
`readAgentExtensions(snapshot, {codelabHome, environment})` (`io.dart`) SHALL строить `AgentExtensionsView` для папки снимка так, как её увидит сессия агента (design.md change `add-app-skills-page`, D3, D4):
- каноническая папка, доверие (`realpath` против `trusted_projects` конфигурации снимка, fail-closed) и чтение файлов проекта и навыков SHALL выполняться той же функцией `codelab_agent_io`, что у `config check`: один `ProjectFilesLoader`, две фазы параллельно, у каждой таймаут 5 с и своя отмена; фаза навыков — только при `skills.enabled`;
- навыки SHALL строиться `parseSkills` ядра с `skills.*` и правилами разрешений конфигурации снимка; строки выключенных `skills.disabled` навыков SHALL добавляться победителями по имени без учёта `skills.disabled`, с признаком `disabled`;
- перекрытие SHALL определяться по диагностикам `shadowed` ядра без разбора их текста; признак «модели недоступен» — по `SkillCatalog.modelVisible`;
- источник навыка SHALL определяться по номеру корня тем же списком корней, что у загрузчика;
- цепочка контекста SHALL идти в порядке загрузчика; усечение и пропуск по бюджету SHALL считаться `assembleProjectContext` ядра; путь на диске — от `$CODELAB_HOME` или корня обхода;
- шаблоны SHALL строиться `parseCommandTemplates` ядра;
- диагностики уровня `error`/`warning` SHALL относиться к строке навыка по пути его `SKILL.md`, остальные — к разделу; `info` SHALL отбрасываться, кроме признака `untrusted_project`;
- исход фазы (таймаут, исключение — имя типа) SHALL быть значением вида, а не исключением.

Вид НЕ SHALL содержать текстов `AGENTS.md`, тел навыков и шаблонов ни в полях, ни в `toString()` (SETUP-25); исключение — описание шаблона без `description` во frontmatter, которым служит первая строка тела, как в `available_commands_update` агента. Сбой подготовки чтения SHALL давать исход «сбой» с именем типа у обеих фаз. `ConfigCommands.check` SHALL использовать ту же функцию `codelab_agent_io`, вывод `config check` НЕ SHALL меняться.

#### Scenario: Вид совпадает с каталогом сессии
- **WHEN** доверенный проект содержит навыки в `.codelab/skills` и `.agents/skills`, у пользователя есть `~/.agents/skills`, а `skills.disabled: [b]`
- **THEN** включённые строки вида совпадают по именам с `SkillCatalog.skills`, который рантайм построит для сессии этой папки, а `b` присутствует с признаком `disabled`

#### Scenario: Недоверенный проект
- **WHEN** папка не в `trusted_projects`
- **THEN** вид имеет `trusted: false`, навыков и шаблонов проекта нет, цепочка `AGENTS.md` проекта есть

#### Scenario: Таймаут фазы навыков
- **WHEN** порт навыков не отвечает 5 с
- **THEN** вид содержит исход «не прочитано за 5 с» для навыков и полную цепочку контекста и шаблоны

#### Scenario: config check не меняется
- **WHEN** `codelab-agent config check` запускается на наборе папок тестов `config_check_skills_test.dart` и тестов файлов проекта до и после правки
- **THEN** вывод совпадает построчно

#### Scenario: Тела не попадают в вид
- **WHEN** тела `SKILL.md`, шаблона и `AGENTS.md` содержат маркер `sk-test-leak-0123456789`
- **THEN** `toString()` вида и всех строк не содержит маркера

### Requirement: Правила записи skills.disabled и skills.extra_roots
`skillsListEdit(snapshot, key, element, {required bool present})` SHALL давать план записи `SkillsListPlan(layer, base, edits)` или отказ `SkillsListRefused(refusal)` для ключей `skills.disabled` и `skills.extra_roots`; `present: true` — элемент должен оказаться в списке, `false` — выйти из него (design.md change `add-app-skills-page`, D5). Другой ключ SHALL давать `ArgumentError`. `base` SHALL быть снимком целевого слоя из `snapshot.layers`, вызывающий записывает `apply(base, edits)`. Правила:
1. цель — самый верхний слой, чьё значение ключа действует (`origins` итога загрузки: значение, отброшенное правилами доверия, источником не считается; для ключа, который недоверенный проект объединяет с нижними слоями (`skills.disabled`), источник определяется по значениям без проектных слоёв — слои `project` и `projectLocal` недоверенного проекта при выборе пропускаются, а `--config` — источник, только если сам задаёт ключ), если он `user` или `projectLocal`; если ключ не задан нигде — `user` (решения Q2 (а), Q3 (а) design.md);
2. если верхний слой — `project` или файл `--config`, результат SHALL быть отказом `SkillsListNotEditable(<источник>)`; если файл целевого или действующего слоя не прочитан в снимке — отказом `SkillsListLayerUnreadable(<слой>)`;
3. новое значение — сырой список целевого слоя плюс или минус элемент, порядок сохраняется, дублей нет; одна правка `SetValue`, пустой список — `UnsetValue`; если элемент уже в нужном состоянии, план SHALL иметь пустой `edits`;
4. включить имя, выключенное `skills.disabled` недоверенного проекта — в `config.yaml` или `config.local.yaml` (по сырому значению этих слоёв), — SHALL нельзя: отказ `SkillsListDisabledByProject(<источник>)`;
5. `skills.extra_roots` НЕ SHALL писаться в слой `project`, а в `projectLocal` — только для доверенного проекта; выдача согласия (`present: true`) на относительный элемент недоверенного проекта SHALL давать отказ `SkillsListUntrustedProject`, а отзыв (`present: false`) SHALL быть разрешён.

Состояние выключателей вида (`SkillToggle` у `SkillEntryView` и `SkillConsentView`) SHALL вычисляться этой же функцией.

Цели записи SHALL быть только `ConfigTarget.user()` и `ConfigTarget.projectLocal(cwd)` (SETUP-3).

#### Scenario: Ключ не задан
- **WHEN** `skills.disabled` нет ни в одном слое, и выключается `x`
- **THEN** результат — `SetValue('skills.disabled', ['x'])` с целью `user`

#### Scenario: Список в projectLocal
- **WHEN** `skills.disabled: [a]` в `projectLocal`, `[c]` в `user`, и выключается `b`
- **THEN** результат — `SetValue('skills.disabled', ['a', 'b'])` с целью `projectLocal`

#### Scenario: Последний элемент
- **WHEN** `skills.disabled: [a]` в `user`, и включается `a`
- **THEN** результат — `UnsetValue('skills.disabled')` с целью `user`

#### Scenario: Ключ из --config
- **WHEN** `skills.extra_roots` задан в файле `--config`
- **THEN** результат — `SkillsListRefused(SkillsListNotEditable(<путь файла>))`, правок нет

#### Scenario: extra_roots не уходит в проектный слой
- **WHEN** `skills.extra_roots` задан только в `.codelab/config.yaml` проекта (агент его отбрасывает), и даётся согласие на `.claude/skills`
- **THEN** правка идёт в `user`, слой `project` не меняется

#### Scenario: Повторное выключение
- **WHEN** `skills.disabled: [a]` в `user`, и снова выключается `a`
- **THEN** результат — `SkillsListPlan` с целью `user` и пустым `edits`

#### Scenario: Отзыв согласия в недоверенном проекте
- **WHEN** проект недоверенный; для снимка с `skills.extra_roots: [.claude/skills]` в `user` вызывается `present: false`, а для снимка без `skills.extra_roots` — `present: true` с элементом `.claude/skills`
- **THEN** первый вызов — `SkillsListPlan` с целью `user` и `UnsetValue('skills.extra_roots')`; второй — `SkillsListRefused(SkillsListUntrustedProject())`

#### Scenario: Неизвестный ключ
- **WHEN** `skillsListEdit` вызывается с ключом `skills.max_skills`
- **THEN** вызов бросает `ArgumentError`

#### Scenario: Список недоверенного проекта совпадает с объединением
- **WHEN** проект недоверенный, `skills.disabled: [a]` в `user` и `[a]` в `.codelab/config.yaml` проекта, и выключается `b`
- **THEN** результат — `SkillsListPlan` с целью `user` и `SetValue('skills.disabled', ['a', 'b'])`, а не отказ `SkillsListNotEditable`

#### Scenario: Нечитаемый целевой слой
- **WHEN** `$CODELAB_HOME/config.yaml` не разбирается, и выключается навык
- **THEN** результат — `SkillsListRefused(SkillsListLayerUnreadable(user))`, правок нет

