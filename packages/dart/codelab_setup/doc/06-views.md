# Представления

Глава описывает `lib/src/views/` (1351 строка) и связанные виды: модели, которые экран показывает в списках и таблицах. Вид — неизменяемый объект без значений секретов, построенный чистой функцией по снимку конфига ([глава 02](02-config-store.md)). Клиент не разбирает слои, источники и правила доверия сам (SETUP-8): он получает готовый итог.

Общее у всех видов:

- Строятся по `AgentConfigSnapshot`; файлы не читают (исключение — `readAgentExtensions`, [глава 05](05-agent-extensions.md)).
- Значения секретов не раскрывают (SETUP-1): статус ключа строится по именам, значения карт скрыты, `toString()` печатает ключ и источник, но не значение.
- Поля только для чтения. Править по значению из вида нельзя: для записи берётся сырое значение из снимка или слоя.

## Провайдеры: `ProviderEntryView`, `KeyStatusView`

Файлы `provider_entry_view.dart` и `key_status_view.dart`. Экспортируются барелем: `ProviderEntryView`, `providerEntriesOf`, а у `KeyStatusView` — все варианты.

```dart
final entries = await providerEntriesOf(
  snapshot,
  environment: agentEnvironment,       // для api_key_env и CODELAB_SECRET_<имя>
  isSecretSet: secrets.isSet,          // есть ли секрет с таким именем
);
```

`providerEntriesOf` возвращает провайдеров по алфавиту `id`. Для каждого:

| Поле | Значение |
|---|---|
| `id`, `kind`, `models` | идентификатор, `providers.<id>.kind` (или `null`), ссылки `<провайдер>/<модель>` по алфавиту |
| `baseUrl` | адрес как в конфиге, только для запроса Check; на экран и в журнал не выводится |
| `displayBaseUrl` | адрес без userinfo, query и fragment (`displayBaseUrl()`); `null`, если адреса нет или он не разбирается |
| `key` | `KeyStatusView` |
| `source`, `editable` | где определён провайдер; правится только если все его листья в слоях `user` и `projectLocal` |
| `isDefault` | `agent.default_model` указывает на этого провайдера |

Ошибка `isSecretSet` (хранилище недоступно) пробрасывается вызывающему: Cubit показывает `storeUnavailable`.

### Статус ключа

`KeyStatusView` — запечатанная иерархия. Статус строится по **именам**, значение не читается:

| Вариант | Условие | `label` |
|---|---|---|
| `KeyInSecretStore(name, backendId)` | `api_key_secret` и секрет есть; при переопределении `CODELAB_SECRET_<имя>` в окружении `backendId` — `env` | `Key: in <бэкенд>` |
| `KeySecretMissing(name, backendId)` | `api_key_secret`, а секрета нет | `Key: missing in <бэкенд>` |
| `KeyFromEnv(name, isSet)` | `api_key_env`; `isSet` — непустое значение в окружении агента | `Key: env <NAME> (set)` или `(not set)` |
| `KeyLiteralInConfig` | в файле литеральный `api_key` (R8-4) | `Key: in config file (plain text)` |
| `KeyNone` | ключа нет | `No key` |

Литеральный ключ — отдельный вариант, потому что «No key» про такого провайдера было бы ложью, а показывать значение нельзя; `codelab secret migrate` переносит его в хранилище.

### Разбор ключей `providers.*`

Плоский ключ вида `providers.<id>.models.qwen2.5-coder.context_window` нельзя разбирать по точкам: ядро не квотирует точку в обычном сегменте, и id модели оказался бы разорван. Поэтому `_split` берёт id провайдера до первой точки (id мастера — `[a-z0-9_-]+`) или в кавычках, а модель выделяет по известным именам полей (`context_window`, `max_output_tokens`, `name`). Внутренние функции `providerIdsOf`, `modelsOf`, `providerOriginsOf`, `providerString` барелем не экспортируются; ими пользуются мастер и `ProviderRemover`.

## Строки настроек: `SettingFieldView`

Файл `setting_field_view.dart`. Терминальный `/settings` и страница «General» приложения показывают одну таблицу `key · value · source`. Вид — одна строка таблицы; строит `settingFieldsOf(snapshot)`.

| Поле | Значение |
|---|---|
| `key` | конкретный ключ: `*` дескриптора заменена на id провайдера и модели, например `providers.gw.base_url` |
| `descriptor` | `SettingDescriptor` реестра ядра: тип, границы, `restartRequired`, слои |
| `value` | заданное значение, уже очищенное `displaySafeConfigValue` (литеральный секрет — `<redacted>`); `null` — не задано или тип `map`/`mapList` |
| `source` | `ConfigSourceView`; `null` — значение по умолчанию |
| `masked` | значение изменено маскированием; клиент по нему не открывает поле правки |
| `entryCount` | число записей у `map` и `mapList` (`mcp.servers`, `permissions.tools`); содержимое не раскрывается |

Производные свойства: `sourceName` (`default`, `user`, `project`, `local`, `config`, `env`), `editable` (значение по умолчанию, слои `user` и `projectLocal`), `restartRequired`, `displayValue`, `effectiveValue`.

`settingFieldsOf` берёт ключи реестра с `scope: shared` в порядке реестра. Ключи `providers.*` раскрываются по id провайдеров снимка, `providers.*.models.*` — ещё и по их моделям; провайдеру без записи в конфиге строк нет. Ключи `fileOnly` (литеральный `api_key`, `agent.fallback`) не показываются.

Данные реального прогона на временном `CODELAB_HOME` с провайдером `gw` (`api_key_secret: codelab/gw`), свёрнутые в колонки `key | displayValue | sourceName` (сам прогон печатал поля строки отдельно):

```text
agent.default_model | (not set) | default
providers.gw.kind | openai-compatible | user
providers.gw.base_url | https://gw.test/v1 | user
providers.gw.api_key_secret | codelab/gw | user
providers.gw.models.m.context_window | 8000 | user
providers.gw.models.m.max_output_tokens | (not set) | default
```

### Можно ли править строку: `SettingEditRefusal`

Файл `setting_edit_rules.dart`. Терминал и приложение решают одно и то же: какие строки клиент не переписывает. Без общего правила второй клиент завёл бы своё, и секретный ключ мог бы стать редактируемым в одном из них. Мост отдаёт только причину отказа и данные для текста; тексты и перевод строит клиент.

| Отказ | Когда |
|---|---|
| `UnknownSetting(key)` | ключа нет в реестре или он не `scope: shared` |
| `TrustBoundarySetting` | `trusted_projects`: граница доверия, клиент её показывает и не меняет |
| `SecretSetting(key)` | ключ хранит секрет или тип `secretName`: правится только через `codelab secret set <name>` |
| `ExternalSourceSetting(key, source)` | значение задано `--config` или окружением |
| `MaskedSetting(key)` | значение замаскировано (литеральный секрет) |

Функции: `settingKeyEditRefusalOf(key)` проверяет только ключ, `settingEditRefusalOf(row)` — строку целиком. Порядок проверок: неизвестный или не `shared`, граница доверия, секрет, затем источник (`config`/`env`), затем маска. Порядок важен: секрет из окружения остаётся `SecretSetting` (текст «Use `codelab secret set`»), а не `ExternalSourceSetting`. `null` — править можно. Слой записи правило не выбирает.

В реальном прогоне строка `providers.gw.api_key_secret` получила `SecretSetting(providers.gw.api_key_secret)`, а остальные строки провайдера — `null`.

## Умолчания новой сессии

Файл `session_defaults_view.dart`. Страница «Agents & modes» показывает режим разрешений и уровень рассуждения, которые получит новая сессия. `sessionDefaultsOf(snapshot, access)` возвращает `SessionDefaultsView`:

| Поле | Значение |
|---|---|
| `mode` (`ModeChoiceView`) | `id` — основной id режима (`plan`, `ask`, `standard`, `accept-edits`, `bypass`; псевдонимы приведены к основному); `source`; `narrowedByProject` (недоверенный проект пытался смягчить режим и был сужен); `blocksWriteAndExec` (сочетание `ask` и `plan`) |
| `effort` (`EffortChoiceView`) | `low`, `medium` или `high` и источник; без листа действует `medium` |
| `suggestedTarget` | слой записи: слой источника `permissions.mode`, если он редактируемый и доступен `EditableSettings`; иначе `user` |

Итог берётся из разобранного `snapshot.loaded.config`, то есть псевдонимы и сочетание `ask`+`plan` разобрал ядро, а не страница. Источник — из `snapshot.originOf`, сужение — из предупреждения `config.project.untrusted_key` с ключом `permissions.mode`. Без итога загрузки действуют умолчания профиля хоста: `standard` и `medium`. Режим `autopilot` сюда не попадает: он задаётся только флагом запуска агента.

Особый случай: сочетание `ask` и `plan` не совпадает ни с одним слоем, и снимок приписывает ему внешний источник `env`. Если `ask` действительно задан в слое `user`, источником отдаётся слой `user` (D4 change `add-settings-agents-modes`), иначе источник остаётся как в снимке.

## Строка MCP-сервера

`McpServerEntryView` (`mcp_server_entry_view.dart`) строит `mcpServerEntriesOf(snapshot)`: серверы эффективного конфига в порядке слияния слоёв. Строка строится по **элементу слоя-источника**, потому что элемент-переопределение `projectLocal` заменяет сервер целиком. Подробности слоёв, «Disable here» и записи — в [главе 04](04-mcp-servers.md).

| Поле | Значение |
|---|---|
| `name`, `kind` | имя и `McpTransportKind` |
| `command`, `args`, `url` | команда stdio (`null` у http), аргументы, адрес http (`null` у stdio) — после маскирования |
| `env`, `headers` | таблицы после маскирования |
| `enabled`, `disabledHere` | включён ли; отключён ли переопределением слоя 3 |
| `source`, `editable` | файл слоя элемента; правится только в `user` и `projectLocal`, не «disabled here» |
| `masked` | хотя бы одно значение замаскировано |

Свойство `target` — «цель» строки: команда с аргументами или адрес.

Правила маскирования лежат в `mcp_masking.dart` и общие с формой (`McpServerDraft.maskedValues`):

- `command`, `url`, `env.<KEY>` — `displaySafeConfigValue` по пути листа `mcp.servers[<имя>].<поле>` (правило имени ключа и шаблона значения);
- `args` — `maskMcpArgs` (значения после ключей вида `--api-key` и встроенные токены; длина и порядок сохраняются);
- `headers` — показываются только чистые ссылки `${…}`, остальное — `<redacted>` (`hidesConfigLiteral`): токен бывает и под нейтральным именем вроде `X-Workspace`.

Реальный прогон: сервер `docs` с заголовком `Authorization: Bearer sk-live-…` в списке получил `headers={Authorization: <redacted>}` и `masked=true`.

Для правки используется не вид, а `mcpServerElementOf(snapshot, name)`: сырой элемент слоя (`McpServerLayerElement`), как в файле, со ссылками `${secret:…}` и `${VAR}`.

## Определения агентов

`AgentDefinitionRowView`, `AgentRowStatus`, `AgentRowScope` и `agentDefinitionRowsOf` описаны в [главе 05](05-agent-extensions.md#определения-агентов). Барель экспортирует только эти четыре имени.

## Как добавить новый вид

Чаще всего вид нужен, когда на страницу приходит новое поле. Правила:

1. Вид — неизменяемый класс в `lib/src/views/` с полями `final`; запечатанная иерархия там, где клиент ветвится.
2. Построитель — чистая функция, принимает `AgentConfigSnapshot` и только нужные порты; без `dart:io`.
3. `toString()` печатает ключ или имя, не значения.
4. Экспортируйте файл из `lib/codelab_setup.dart` (с `show`, если часть файла внутренняя).
5. Тест — на `snapshotOf` или `RealHome` ([глава 07](07-testing.md)); проверьте, что секрет-маркер не попадает в `toString()` (пример — группа «секреты (SETUP-1)» в `test/views/setting_field_view_test.dart`).

Полные рецепты — [глава 08](08-extending.md).
