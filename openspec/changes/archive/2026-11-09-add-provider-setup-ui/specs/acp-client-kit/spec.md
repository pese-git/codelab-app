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

### Requirement: Инкрементальная проекция транскрипта
`TranscriptProjector` SHALL строить `TranscriptItem` сессии инкрементально по новым `session/update`: дельты `agent_message_chunk` и `agent_thought_chunk` подряд дописываются в один элемент того же вида, любое другое обновление закрывает отрезок; `tool_call` с известным `toolCallId` обновляет существующий элемент, а не добавляет второй; статус и одобрение вызова берутся из read-модели хода ядра клиента; запрос разрешения привязывается к `ToolCallItem` по `toolCallId`, а для вызова без `tool_call` — к элементу вызова в конце хода; сорвавшийся ход добавляет `NoticeItem` вида `error` с типизированным сбоем хода (`PromptFailure`), завершённый ход без вывода агента — `NoticeItem` вида `emptyTurn`; ход, завершённый с `stopReason` `max_tokens`, `max_turn_requests` или `refusal`, — `NoticeItem` вида `turnStopped` всегда, даже при выводе агента, и вместо `emptyTurn` у хода без вывода (решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q33, D27). Заметка `turnStopped` SHALL строиться только по `stopReason` ответа на `session/prompt`: у ходов реплея `session/load` его нет, и заметки у них нет (Q36). Тексты `turnStopped`: `max_tokens` — `The model reached its token limit, so the turn ended.`; `max_turn_requests` — `The turn reached the limit of model requests.`; `refusal` — `The agent refused to continue.`. Повторно обработанный снимок сессии SHALL быть no-op. Для любой последовательности обновлений результат инкрементальной проекции SHALL совпадать с проекцией с нуля по всем ходам сессии.

#### Scenario: Свойство на корпусе фикстур
- **WHEN** выполняется `transcript_projector_test.dart: incremental projection equals full rebuild for every fixture`
- **THEN** для каждой фикстуры корпуса с ролью `client` на каждом шаге инкрементальная проекция равна проекции с нуля

#### Scenario: Повторная доставка tool_call
- **WHEN** агент дважды присылает `tool_call` с одним `toolCallId`
- **THEN** транскрипт содержит один `ToolCallItem` на прежней позиции с полями второго кадра

#### Scenario: Заметка о сбое несёт причину агента
- **WHEN** ход срывается ответом агента, как в фикстуре `acp/prompt-failed-provider-auth`
- **THEN** `NoticeItem` вида `error` этого хода несёт `PromptFailure.agent` с `errorClass: "auth"`, сообщением агента и `retryable: false`

#### Scenario: Ход упёрся в лимит токенов после размышлений
- **WHEN** ход содержит только `agent_thought_chunk` и завершается ответом агента с `stopReason: max_tokens`
- **THEN** транскрипт хода содержит `ThoughtItem` и один `NoticeItem` вида `turnStopped` с текстом `The model reached its token limit, so the turn ended.`; `NoticeItem` вида `emptyTurn` нет

#### Scenario: Отказ агента после текста
- **WHEN** ход содержит `agent_message_chunk` и завершается с `stopReason: refusal`
- **THEN** после `AgentTextItem` хода есть `NoticeItem` вида `turnStopped` с текстом `The agent refused to continue.`; ход `end_turn` и `cancelled` такой заметки не получает

#### Scenario: Реплей session/load без заметки исхода
- **WHEN** сессия загружена через `session/load`, и в реплее истории есть ход, который при живом выполнении завершился с `stopReason: max_tokens` (реплей ACP не передаёт `stopReason`, `03-Session Setup.md`, «Loading a Session»), а после загрузки новый ход той же сессии завершается с `stopReason: max_tokens`
- **THEN** ход реплея не получает `NoticeItem` вида `turnStopped`, а новый ход получает; исход хода клиент не хранит и не восстанавливает (решение пользователя 2026-11-09, design.md change `add-provider-setup-ui`, Q36)

## ADDED Requirements

### Requirement: Неизвестный уровень риска вызова
Клиентский уровень риска одобрения (`ApprovalRiskLevel` пакета `codelab_client_acp`) SHALL иметь значение `unknown` для вызова, вид которого (`ToolKind` ACP) — `other` или не передан; `read`, `search` и `think` остаются `readOnly`. `unknown` SHALL ранжироваться выше `readOnly` и ниже `localWrite`, а решение режима разрешений клиента для него SHALL требовать явного одобрения (AGENTS.md §10: неизвестная потенциально опасная capability не считается безопасной; решение пользователя 2026-11-08, design.md change `add-provider-setup-ui`, Q32, D27). Новых полей и значений ACP это не вводит.

#### Scenario: Вид other
- **WHEN** агент запрашивает разрешение на вызов с `kind: other` без содержимого diff и терминала
- **THEN** уровень риска одобрения — `unknown`, инспектор показывает `unknown`, CLI — `unknown risk`

#### Scenario: Вид не передан
- **WHEN** `tool_call` пришёл без `kind`
- **THEN** уровень риска — `unknown`, а не `readOnly`


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

### Requirement: Отказ рукопожатия из-за токена
Kit SHALL определять отказ WebSocket-агента из-за токена одной web-безопасной функцией (`codelab_client_core/lib/src/connection/token_rejection.dart`; design.md, D25):
- `tokenRejectionStatus(error)` SHALL возвращать 401 или 403, найденные по цепочке `cause` ошибки (`AcpClientApplicationException` → `AcpTransportException` → `AcpWebSocketHandshakeRejected`) на ограниченную глубину, и `null` для любого другого статуса и ошибки. Текст ошибок НЕ SHALL разбираться;
- `describeTokenRejection(error, {tokenSent})` SHALL возвращать `the agent rejected the token (HTTP <код>)` при `tokenSent` и `the agent requires a token (HTTP <код>)` без него, а для прочих ошибок — `null`;
- `profileTokenSent(profile, SecretSource?)` SHALL отвечать, был ли токен отправлен, не читая значения: для `ProfileSecretSource` с `secret:` — через `isSet` порта, для `env:` — по наличию непустой переменной;
- `describeConnectFailureByToken(error, profile, SecretSource?)` SHALL сначала вычислять `tokenRejectionStatus(error)` и только при 401 или 403 обращаться к `profileTokenSent`; для прочих ошибок источник секретов НЕ SHALL вызываться, а результат — `null`. Результат — строчный текст `describeTokenRejection` без точки; хосты оформляют его сами.

`classifyProbeFailure` (`codelab_client_io`) SHALL определять `Unauthorized` через `tokenRejectionStatus`: таблица статусов одна для проверки профиля и подключения. Тексты согласованы с исходами проверки D12 change `add-app-settings-shell`.

#### Scenario: Статус по цепочке причин
- **WHEN** `tokenRejectionStatus` получает `AcpClientApplicationException`, чья причина — `AcpTransportException` с причиной `AcpWebSocketHandshakeRejected(401)`; затем такую же цепочку с `500`; затем `SocketException`
- **THEN** результаты — `401`, `null`, `null`

#### Scenario: Текст по отправленному токену
- **WHEN** `describeTokenRejection` получает отказ `403` с `tokenSent: true`, затем с `tokenSent: false`, затем ошибку без статуса
- **THEN** результаты — `the agent rejected the token (HTTP 403)`, `the agent requires a token (HTTP 403)` и `null`

#### Scenario: При прочей ошибке источник не вызывается
- **WHEN** `describeConnectFailureByToken` получает `SocketException` (или отказ `500`) для WebSocket-профиля с `secret:codelab/profiles/a/token` и источником-шпионом
- **THEN** результат `null`, ни `isSet`, ни `read` источника не вызывались; при отказе `401` вызван только `isSet`, `read` — нет

#### Scenario: Токен отправлен или нет
- **WHEN** `profileTokenSent` проверяет WebSocket-профили с `env:SET` (переменная непуста), `env:EMPTY`, `secret:<имя без значения>`, без токена и stdio-профиль
- **THEN** результаты — `true`, `false`, `false`, `false`, `false`; значение секрета не читалось

