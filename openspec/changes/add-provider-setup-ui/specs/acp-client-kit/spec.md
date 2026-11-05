## MODIFIED Requirements

### Requirement: Ссылка на токен профиля
`ProfileTokenRef.parse(ref)` SHALL понимать две формы `WebSocketProfile.tokenRef` (design.md change `add-app-settings-shell`, D15; design.md change `add-provider-setup-ui`, D13):
- `env:<NAME>` для любой переменной с допустимым именем — ссылка на переменную окружения процесса (`EnvTokenRef`);
- `secret:<имя>`, где имя проходит правило `SecretNames` (`^[a-z0-9][a-z0-9._/-]{0,127}$`, без `..` и пустых сегментов), — ссылка на секрет хранилища агента (`SecretTokenRef`).

Любую другую ссылку, в том числе голое имя секрета без префикса и `secret:` с недопустимым именем, он SHALL возвращать как неподдерживаемую в этой версии. `toString()` неподдерживаемой ссылки SHALL маскировать значение: туда мог попасть вписанный вручную токен.

`ProfileSecretSource(environment, {stored})` SHALL реализовывать `SecretSource` по этому правилу:
- `env:` читает переменную окружения;
- `secret:` читает `ProfileSecrets.read(имя)` порта `stored`.

Результат SHALL быть `null`, и подключение идёт без токена, если:
- переменная пуста или отсутствует;
- секрета нет;
- порт `stored` не передан;
- ссылка не поддерживается.

Источник SHALL использоваться и app, и CLI. Значение токена НЕ SHALL кэшироваться источником: каждое открытие транспорта читает его заново. Метод источника `isSecretMissing(profile)` SHALL возвращать `true`, только если WebSocket-профиль ссылается на `secret:<имя>`, а `ProfileSecrets.isSet(имя)` ложно, либо порт `stored` не передан, либо порт бросил ошибку; значение секрета он НЕ SHALL читать. Для `env:`, профиля без токена, неподдерживаемой ссылки и не-WebSocket-профиля — `false`. Источник сам НЕ SHALL писать в журнал: предупреждение о незаданном секрете (текст — `secretMissingWarning(profileId)`) выдаёт хост перед подключением (spec app-settings и codelab-cli; design.md change `add-provider-setup-ui`, D13).

#### Scenario: Формы ссылки
- **WHEN** `ProfileSecretSource` с окружением `CODELAB_AGENT_TOKEN=t1`, `DEVBOX_TOKEN=t2`, `EMPTY=` и портом `stored`, где секрет `codelab/profiles/dev/token` = `t3`, читает `env:CODELAB_AGENT_TOKEN`, `env:DEVBOX_TOKEN`, `env:EMPTY`, `env:MISSING`, `secret:codelab/profiles/dev/token`, `secret:codelab/missing` и `codelab/profiles/dev/token`
- **THEN** результаты — `t1`, `t2`, `null`, `null`, `t3`, `null` и `null`; `ProfileTokenRef.parse('codelab/profiles/dev/token')` и `ProfileTokenRef.parse('secret:Bad Name')` — неподдерживаемые ссылки

#### Scenario: Без порта хранилища
- **WHEN** `ProfileSecretSource` создан без `stored` и читает `secret:codelab/profiles/dev/token`
- **THEN** результат `null`, исключения нет

#### Scenario: Проверка наличия секрета без чтения значения
- **WHEN** `isSecretMissing` вызывается для профилей с `secret:codelab/profiles/a/token` (задан), `secret:codelab/profiles/b/token` (не задан), `env:MISSING` и без токена
- **THEN** результаты — `false`, `true`, `false`, `false`; `ProfileSecrets.read` не вызывался

#### Scenario: Замена секрета видна при следующем подключении
- **WHEN** источник прочитал `secret:codelab/ws` = `a`, после чего другой процесс заменил значение на `b`, и транспорт открывается снова
- **THEN** второе чтение возвращает `b`

## ADDED Requirements

### Requirement: Порт хранилища секретов профилей
Kit SHALL объявлять порт `ProfileSecrets` (`codelab_client_core/lib/src/connection/profile_secrets.dart`, чистый Dart) с описанием бэкенда (`id`, `writable`, `unavailableReason`), `names()`, `isSet(name)`, `store(name, SecretText)`, `delete(name)` и `read(name)` (design.md, D13). Результаты `store` и `delete` SHALL быть типизированными (`Stored`, `Exists`, `ReadOnly`, `Failed`; `Deleted`, `NotSet`, `ReadOnly`, `Failed`) и НЕ SHALL содержать значения. Реализацию SHALL давать composition root хоста. Kit НЕ SHALL зависеть от `codelab_setup` и пакетов агента.

`SecretText` SHALL оборачивать значение нового токена в памяти: `toString()` и JSON-представление — `***`, значение доступно только через `reveal()`.

Функция kit `selectableProfileTokenSecrets(names)` SHALL отбирать из имён хранилища только те, что начинаются с `codelab/profiles/` и дают `SecretTokenRef` при разборе `secret:<имя>`, по алфавиту и без повторов (удобно для списка выбора). Ключи провайдеров (`codelab/<id>`) и секреты MCP (`codelab/mcp/…`) она НЕ SHALL возвращать (design.md change `add-provider-setup-ui`, D14). Ссылку `secret:<имя>` на другой допустимый секрет, вписанную в `profiles.json` вручную, фильтр не затрагивает: её по-прежнему читает `ProfileSecretSource`.

#### Scenario: Фильтр имён для «Use stored secret»
- **WHEN** `selectableProfileTokenSecrets` получает `codelab/anthropic`, `codelab/mcp/github/authorization`, `codelab/profiles/devbox/token`, `codelab/profiles/Bad Name` и `codelab/profiles/ci/token`
- **THEN** результат — `codelab/profiles/ci/token` и `codelab/profiles/devbox/token` в этом порядке; повторное имя во входе даёт одну строку

#### Scenario: SecretText не печатает значение
- **WHEN** `SecretText('sk-test-leak-0123456789')` попадает в `toString()` черновика профиля, в `jsonEncode` и в текст исключения
- **THEN** ни один результат не содержит `sk-test-leak-0123456789`

### Requirement: Запись профиля с новым токеном
`ProfileCommitter` (kit) SHALL сохранять WebSocket-профиль с вариантом «Store a new token» в порядке «секрет → профиль» (SETUP-19; design.md, D13):
1. перечитать id профилей; занятый id — проблема черновика `idTaken` без записи;
2. `ProfileSecrets.store('codelab/profiles/<id>/token', value)`; `Exists` — проблема черновика `tokenSecretExists` без записи профиля и без отката. `Exists` SHALL возвращаться и тогда, когда имя появилось в хранилище между проверкой и записью (хранилище сообщило «обновлено»): такой секрет не создан этой операцией. `ReadOnly` и `Failed` — `ProfileSaveFailed` без записи профиля;
3. ещё раз перечитать id — после записи секрета; занятый id — проблема `idTaken` и удаление секрета, созданного на шаге 2;
4. `ProfileStore.save` профиля с `tokenRef: secret:codelab/profiles/<id>/token`;
5. если шаг 4 не удался, секрет, созданный на шаге 2, SHALL удаляться.

Для «Use stored secret» SHALL выполняться только шаги 1, 3 и 4 с `tokenRef: secret:<выбранное имя>`. `ProfileSaveFailed` и `RemoveFailed` SHALL нести `errorType` — имя типа исключения без его текста.

`ProfileCommitter.remove(id, {deleteOwnSecret})` SHALL сначала удалять профиль. Только после успеха и только если профиль ссылается на `secret:codelab/profiles/<id>/token`, и ни один другой профиль файла не ссылается на то же имя, он SHALL удалять этот секрет. Секрет, выбранный «Use stored secret» (не собственный), НЕ SHALL удаляться никогда. Ошибка удаления секрета НЕ SHALL восстанавливать профиль.

#### Scenario: Секрет до профиля и откат
- **WHEN** `ProfileCommitter` сохраняет профиль `devbox` с новым токеном, а `ProfileStore.save` бросает исключение
- **THEN** `ProfileSecrets.store` вызван до `save`, после ошибки вызван `delete('codelab/profiles/devbox/token')`, результат — `ProfileSaveFailed`, `profiles.json` не изменён

#### Scenario: Id занят во время записи секрета
- **WHEN** `ProfileCommitter` записал секрет `codelab/profiles/devbox/token`, а к повторной проверке id профиль `devbox` уже создан другим процессом
- **THEN** результат — проблема `idTaken`, секрет удалён, профиль другого процесса не изменён

#### Scenario: Имя секрета появилось между проверкой и записью
- **WHEN** хранилище на `store('codelab/profiles/devbox/token', …)` сообщает, что имя уже было и значение обновлено
- **THEN** результат — проблема `tokenSecretExists`, `ProfileStore.save` не вызывался, `delete` не вызывался

#### Scenario: Тип ошибки без текста
- **WHEN** `ProfileStore.save` бросает исключение, чей `toString()` содержит `sk-test-leak-0123456789`
- **THEN** `ProfileSaveFailed.errorType` — имя типа исключения, ни один результат не содержит маркера

#### Scenario: Существующий секрет не перезаписывается
- **WHEN** в хранилище уже есть `codelab/profiles/devbox/token`, и `ProfileCommitter` сохраняет профиль `devbox` с новым токеном
- **THEN** результат — проблема `tokenSecretExists`, значение секрета не изменено, `ProfileStore.save` не вызывался

#### Scenario: Удаление профиля с собственным секретом
- **WHEN** профиль `devbox` с `tokenRef: secret:codelab/profiles/devbox/token` удаляется с `deleteOwnSecret: true`, а профиль `ci` ссылается на `secret:codelab/ws-ci`
- **THEN** профиль удалён, затем удалён секрет `codelab/profiles/devbox/token`; удаление `ci` с `deleteOwnSecret: true` удаляет профиль и не трогает `codelab/ws-ci`

#### Scenario: Общий секрет не удаляется
- **WHEN** профили `a` и `b` (последний отредактирован вручную) оба ссылаются на `secret:codelab/profiles/a/token`, и `a` удаляется с `deleteOwnSecret: true`
- **THEN** профиль `a` удалён, секрет остаётся

### Requirement: Проверка нового токена до записи
`ProfileProbe.probe(profile, token: SecretText?)` (профиль, построенный из черновика `toProfile`) SHALL передавать транспорту значение нового токена из памяти через одноразовый источник, не записывая его в хранилище (§12.4.9, шаг 5; design.md, D13). Для «Use stored secret» проверка SHALL читать секрет тем же `ProfileSecretSource`, что подключение. Остальные правила проверки (только `initialize`, закрытие транспорта, отмена) SHALL оставаться прежними (требование «Проверка профиля без сессии»).

Пустое значение нового токена SHALL давать явный отказ проверки без открытия транспорта, а не проверку без токена. Резолвер, который не умеет подставить источник секрета (`SecretRebindableResolver.withSecrets`), SHALL давать исход `Unsupported`.

#### Scenario: Пустой новый токен
- **WHEN** проверяется WebSocket-черновик с «Store a new token» и пустым значением
- **THEN** проверка отказывает явно, транспорт не открыт, сервер не получил запроса

#### Scenario: Новый токен проверяется без записи
- **WHEN** черновик WebSocket-профиля с «Store a new token» `t` проверяется на `FakeAcpTransport`, требующем Bearer `t`
- **THEN** исход `Reachable`, транспорт получил заголовок с `t`, `ProfileSecrets.store` не вызывался
