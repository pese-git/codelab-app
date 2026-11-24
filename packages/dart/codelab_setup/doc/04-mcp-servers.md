# MCP-серверы

Глава описывает подсистему `lib/src/mcp/` (1611 строк) и строку списка `McpServerEntryView`. Она отвечает на вопрос страницы «MCP servers»: как показать серверы из конфига, как проверить форму, как записать сервер вместе с его секретами и как удалить так, чтобы не потерять чужой секрет. Что такое MCP-сервер для агента и как ядро запускает его, объясняют [руководство ядра](../../codelab_agent_core/doc/06-tools.md) и пакет [`codelab_agent_mcp`](../../codelab_agent_mcp/README.md). Здесь — только клиентская сторона настройки.

Подсистему использует приложение (`mcp_settings_cubit.dart`, `mcp_page.dart`). Терминал серверы настраивает подкомандой `codelab mcp`, которая живёт в `codelab_agent_io`.

## Как хранится сервер

Серверы лежат в списке `mcp.servers` каждого слоя конфига. Элемент — карта с ключом `name`:

```yaml
mcp:
  servers:
    - name: docs
      type: http
      url: https://mcp.test/mcp
      headers:
        Authorization: ${secret:codelab/mcp/docs/authorization}
```

Тип транспорта — `McpTransportKind`: `stdio` (поля `command`, `args`, `env`) или `http` (поля `url`, `headers`). Тип определяет `mcpTransportKindOf(element)` (`mcp_transport_kind.dart`): явный `type: http` — `http`; без `type` элемент с `url` и без `command` тоже `http`; остальное — `stdio`. Форму и строку списка читает одна функция: две копии разошлись бы.

При слиянии слоёв `UpsertMcpServer` заменяет элемент по `name` **целиком**. Значит, любая правка строится из **сырого** элемента слоя, а не из замаскированного вида. Иначе запись `{name, enabled}` стёрла бы команду, адрес, `env` и `headers`. Отсюда два типа:

- `McpServerEntryView` — вид для показа, значения очищены от секретов ([глава 06](06-views.md#строка-mcp-сервера));
- сырой элемент: `mcpServerElementOf(snapshot, name)` возвращает `McpServerLayerElement(layer, element)` для правки.

## Слои и эффективный список

`mcp_layers.dart` (внутренний файл) собирает серверы эффективного конфига в порядке слияния слоёв ядра: порядок первого появления, сервер с тем же `name` в слое выше заменяется на месте целиком. Функция `effectiveMcpServers(snapshot)` возвращает `EffectiveMcpServer(name, layer, element, projectElement)`.

Почему мост повторяет слияние, а не берёт `loaded.values['mcp.servers']`: строке нужен слой-источник каждого элемента (редактируемость, запись в нужный файл), а итоговый список его не хранит. Расхождение порядка ловит тест «порядок слияния» (`test/views/mcp_server_entry_view_test.dart`) на снимке настоящего `FileAgentConfigStore`.

Слой недоверенного проекта отбрасывается целиком: `layerMcpServers` проверяет `isIgnoredByTrust(loaded, layer, 'mcp.servers')` (CFG-3). Серверов такого слоя в списке нет.

Два правила слоя 3:

- Сервер слоя `project` клиент не правит и не удаляет (SETUP-3). Вместо этого его можно «выключить здесь».
- **«Disable here»** — переопределение `{name, enabled: false}` в слое `projectLocal`. Его признак `isDisableHereOverride`: ровно ключи `name` и `enabled`. Для такой строки `McpServerEntryView.disabledHere` истинно, описание берётся из проектного элемента, источник — проектный файл. **«Enable here»** убирает это переопределение.

## Черновик формы: `McpServerDraft`

Файл `mcp_server_draft.dart`. Форма приложения и CLI проверяет одно и то же до записи.

### Значения `env` и `headers`

Значение в таблицах — `McpValueDraft`, запечатанная иерархия из трёх видов:

| Вид | Конструктор | Что попадёт в конфиг |
|---|---|---|
| `McpTextValue` | `McpValueDraft.text('…')` | текст как есть: литерал, `${VAR}` или `Bearer ${secret:…}`. Литеральный секрет писатель конфига отклонит (`ConfigInlineSecret`) |
| `McpNewSecret` | `McpValueDraft.secret(SecretValue)` | значение уходит в хранилище под именем `SecretNames.forMcp(сервер, ключ)`, в конфиг пишется `${secret:<имя>}` |
| `McpStoredSecret` | `McpValueDraft.stored('${secret:…}')` | «не менять»: ссылка из файла остаётся |

`toString()` значений не печатает (SETUP-1).

### Создание и правка

```dart
// Новый сервер.
final draft = McpServerDraft(
  name: 'docs',
  kind: McpTransportKind.http,
  url: 'https://mcp.test/mcp',
  headers: {'Authorization': McpValueDraft.secret(SecretValue(token))},
);

// Правка: из сырого элемента слоя, с сохранением неизвестных ключей.
final edit = McpServerDraft.fromElement(element).copyWith(enabled: false);
```

`fromElement` сохраняет ключи элемента, которых форма не знает (`call_timeout` и др.), в приватном `_extra` и дописывает их при `toEdits()`. Значение, равное ровно `${secret:<имя>}`, превращается в `McpStoredSecret`, остальные — в `McpTextValue`.

### Проверка: `validate()`

`validate({Set<String> existingNames})` возвращает список `McpDraftProblem`; пустой список — черновик годится. Каждая проблема имеет поле формы (`McpDraftField`: `name`, `command`, `url`, `env`, `headers`), английский `message` (для CLI), типизированный `code` и `argument` (имя ключа у кодов о ключе). Код и текст создаёт одна фабрика `McpDraftProblem.of`, поэтому они не расходятся. Значения URL, секретов и заголовков ни в `argument`, ни в `message` не попадают.

| Код `McpDraftProblemCode` | Текст `message` | Когда |
|---|---|---|
| `nameInvalid` | `Use a name without spaces, [, ] or ".` | имя нарушает `isValidMcpServerName` ядра |
| `renameNotAllowed` | `Remove the server and add it again to rename it.` | при правке имя сменилось |
| `nameTaken` | `A server with this name already exists.` | имя есть в `existingNames` |
| `commandEmpty` | `Enter the command.` | пустая команда stdio |
| `urlInvalid` | `Enter an http or https URL.` | не http/https или нет хоста |
| `urlHasUserinfo` | `Remove the user name and password from the URL.` | в адресе пароль |
| `keyHasSpaces` | `Remove spaces around the name <ключ>.` | пробелы по краям имени ключа |
| `keyDuplicate` | `Two values are named <ключ>.` | два значения с одним ключом (создаёт клиент, `validate()` код не возвращает) |
| `keyEmpty` | `Enter a name for every value.` | пустое имя ключа |
| `secretValueEmpty` | `Enter the secret value for <ключ>.` | пустое значение нового секрета |
| `secretNameCollision` | `Two secret values get the same secret name; rename <ключ>.` | два секрета получили одно имя в хранилище |

Запрет переименования записан сознательно: `UpsertMcpServer` заменил бы элемент по новому имени, а старый остался бы, и секреты `codelab/mcp/<имя>/` потеряли бы владельца.

Имена секретов после нормализации `SecretNames.forMcp` (нижний регистр, недопустимые символы заменяются `-`) могут совпасть у разных ключей, поэтому `_tableProblems` собирает занятые имена, включая сохранённые ссылки других ключей, и сообщает `secretNameCollision`. Код `keyDuplicate` `validate()` не возвращает: карта не хранит два одинаковых ключа, поэтому дубликаты находит клиент до построения черновика и создаёт проблему через `McpDraftProblem.of`. Ключи, различающиеся только пробелами по краям, дают `keyHasSpaces`.

Проверка на проверенном запуске: черновик `name: 'a b'`, адрес `https://u:p@h/`, заголовок `'X '` дал `nameInvalid` (поле `name`), `urlHasUserinfo` (поле `url`) и `keyHasSpaces` (поле `headers`, аргумент `X `).

### Правки и секреты

- `toEdits()` — одна правка `UpsertMcpServer` с элементом целиком. Для недопустимого черновика (проверка без уникальности имени) возвращает пустой список. Правило элемента: `name`, `type`, затем поля активного транспорта, `enabled: false` только когда выключен, затем `_extra`.
- `secretsToWrite()` — карта «имя секрета → значение» только для таблицы активного типа (stdio — `env`, http — `headers`). Значения неактивной таблицы в элемент не попадают, и секрет без ссылки остался бы сиротой.
- `maskedValues` — ключи, значения которых список маскирует (`command`, `url`, `args`, `env.<KEY>`, `headers.<KEY>`). Форма по ним показывает «пусто = не менять» вместо значения, чтобы не раскрыть то, что скрыл список. Правило маскирования одно с `McpServerEntryView` — файл `mcp_masking.dart`.

## Запись: `McpServerCommitter`

Файл `mcp_server_committer.dart`. Порядок тот же, что у провайдера, — «секрет, затем конфиг, с откатом созданных секретов» (SETUP-5, SETUP-6): в обратном порядке получился бы конфиг со ссылкой на несуществующий секрет, а сервер с такой ссылкой не стартует. Порт секретов — тот же `ProviderKeys` ([глава 03](03-provider-wizard.md#порт-providerkeys)); второго порта нет.

```dart
final committer = McpServerCommitter(config: store, keys: keys);
final outcome = await committer.commit(
  draft,
  snapshot.layers[ConfigLayer.user]!,   // base: слой, куда пишем
  replaceSecrets: {'codelab/mcp/docs/authorization'},  // выбор «Replace it»
  cwd: snapshot.cwd,                    // для свежего снимка после записи
);
```

Шаги `commit`:

1. `draft.validate()`; проблемы — `McpServerInvalid(problems)`, ничего не записано.
2. `occupiedSecrets(draft, replaceSecrets:)` проверяет **все** имена до первой записи, частичной записи нет. Занятые имена — `McpSecretAppeared(names)`. Исключение хранилища превращается в `McpServerNotSaved(errorType)` (имя типа без текста).
3. Секреты пишутся по одному: `ProviderKeyCreated` → в `created` (откатывается), `ProviderKeyReplaced` → в `replaced` (не откатывается: прежнего значения нет), `ProviderKeyRefused` → откат созданных и `McpSecretNotStored(reason, rollback, notRolledBack)`.
4. `apply(base, draft.toEdits())`. Не `ConfigSaved` — откат созданных секретов и `McpServerNotSaved(outcome | errorType, replacedSecrets, rollback, notRolledBack)`.
5. `ConfigSaved` — `McpServerCommitted(saved, replacedSecrets, secrets)`. Поле `secrets` — судьба секретов, на которые прежний элемент ссылался, а новый — нет (сняли «Secret», сменили тип): `_cleanUp` удаляет их по общему правилу очистки.

Прогон на фейках (`FakeProviderKeys`, `FakeConfigStore`): запись сервера `docs` с новым секретом в заголовке дала `McpServerCommitted(0 replaced)`; журнал портов — `stored codelab/mcp/docs/authorization`, `write codelab/mcp/docs/authorization`, затем `apply`. При конфликте записи (`ConfigConflict`) результат — `McpServerNotSaved(ConfigConflict(...), rollback: deleted)`, а в журнале секретов после `write` добавился `delete`.

### Переключатели без секретов

| Метод | Что пишет | Отказы (`McpServerRefusal`) |
|---|---|---|
| `setEnabled(snapshot, name, enabled:)` | сырой элемент слоя целиком с изменённым `enabled` | `unknownServer`, `notEditable` (слой 3 или «disabled here»), `layerUnreadable` |
| `disableHere(snapshot, name, access:)` | `{name, enabled: false}` в `projectLocal` для сервера слоя 3 | `noProjectTarget` (нет цели `projectLocal` в `access.targets`), `unknownServer`, `notProject`, `layerUnreadable` |

Результат — `McpServerWritten(saved)`, `McpServerNotWritten(outcome | errorType)` или `McpServerRefused(reason)`. Отказ приходит **до** обращения к файлу и хранилищу. Нечитаемый `config.local.yaml` (слоя нет в снимке) — отказ `layerUnreadable`, а не конфликт записи.

## Удаление: `McpServerRemover`

Файл `mcp_server_remover.dart`. Порядок — «одна запись, затем секреты» (SETUP-24).

```dart
final remover = McpServerRemover(config: store, keys: keys);

// Что показать в подтверждении (чистая функция, ничего не пишет).
final candidates = McpServerRemover.secretCandidatesOf(snapshot, 'docs');

final outcome = await remover.remove(snapshot, name: 'docs');
```

1. Сервер слоя 3 и «disabled here» удалить нельзя (`notEditable`); неизвестный — `unknownServer`; слой не читается — `layerUnreadable`.
2. `RemoveMcpServer(name)` — одна запись в слой сервера. Не записано — `McpServerRemovalNotSaved`; секреты не тронуты.
3. Кандидаты на удаление — все секреты, на которые ссылался элемент в `env` и `headers` (`referencedSecrets`). **Удаляются только те, что в пространстве страницы** `codelab/mcp/<имя>/` (`inPageNamespace`); остальные (`${secret:shared}`) принадлежат пользователю и остаются с исходом `SecretCleanup.kept`. Пространство общее у `GitHub` и `github`: `SecretNames.forMcp` приводит имя к нижнему регистру, поэтому удаление по префиксу без проверки ссылок небезопасно.
4. Очистка: `cleanUpSecrets` читает свежий снимок и удаляет секрет, только если на него не осталось ссылок.

`cleanUpSecrets` сначала проверяет, что безопасность доказана, и иначе помечает все кандидаты `SecretCleanup.failed`, ничего не удаляя:

- свежий снимок получить не удалось;
- любой из трёх слоёв не читается (`fresh.isReadable(layer)` ложно) — `FileAgentConfigStore.snapshot` читает все три, отсутствующий файл считается пустым слоем;
- есть проблемы загрузчика вида `syntax` или `profile`.

Дальше для каждого кандидата: ссылка есть в снимке — `stillReferenced`; иначе `keys.delete`: `deleted`, `alreadyAbsent` или `failed` (исключение хранилища тоже `failed`).

`McpServerRemoved(saved, secrets)` — `secrets` отображает имя секрета на итог.

## Перезапуск: `restartRequiredServers` и `restartRequiredProviders`

Файл `mcp_restart.dart`. Агент не применяет часть изменений «на лету»: новый `stdio`-сервер не запускается без перезапуска, `http`-сервер с подстановкой `${…}` не отправляет секрет на новый адрес (R0-1, R0-4, R6-1). Это граница безопасности, и правило одно — `planConfigReload` ядра ([конфигурация ядра](../../codelab_agent_core/doc/09-config-prompts-commands.md)). Мост лишь вызывает его и выбирает имена:

- `restartRequiredServers(before, after)` — имена **включённых** серверов, которые агент отложит до перезапуска;
- `restartRequiredProviders(before, after)` — id провайдеров: новый провайдер «с ключом» и смена адреса или аутентификации существующего такого провайдера.

Оба снимка — из `AgentConfigStore.snapshot`; сравнивается снимок страницы до записи со свежим. Если у любого снимка нет `loaded.config`, результат пуст. Правку без смены соединения (`call_timeout`), удаление и выключение функции в список не включают.

## Тесты подсистемы

| Файл | Что проверяет |
|---|---|
| `test/mcp_server_draft_test.dart`, `mcp_draft_problem_code_test.dart` | проверки формы, коды проблем, сохранение неизвестных ключей |
| `test/mcp_server_commit_test.dart` (808 строк) | порядок «секрет, конфиг, откат», конфликты, `McpSecretAppeared`, переключатели |
| `test/mcp_server_remove_test.dart` (696 строк) | удаление с секретами, fail-safe свежего снимка, «Disable here» и «Enable here», `secretCandidatesOf` |
| `test/mcp_restart_test.dart` | имена серверов и провайдеров, ждущих перезапуска |
| `test/views/mcp_server_entry_view_test.dart` | строки списка, маскирование, порядок слияния |

Снимки для этих тестов строят `mcpSnapshot` и `freshMcpSnapshot` из `test/support/mcp_snapshots.dart`.
