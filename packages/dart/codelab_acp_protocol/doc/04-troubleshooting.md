# Частые проблемы разработчика

Глава собирает случаи, с которыми сталкивается тот, кто меняет пакет или встраивает его. Каждый случай записан одинаково: симптом, причина, что сделать. Тексты ошибок взяты из кода пакета и из реальных запусков; рядом указан файл, где они появляются. Кадр можно разобрать скриптом из [главы 00](00-getting-started.md#разбор-кадра-в-отдельном-скрипте).

Случаи по теме:

- кадр и метод: [метод не зарегистрирован](#метод-не-зарегистрирован), [ответ без `result` и `error`](#ответ-без-result-и-error), [`result: null` не принимается](#result-null-не-принимается), [запрос и уведомление перепутаны](#запрос-и-уведомление-перепутаны);
- поля и значения: [лишнее корневое поле](#лишнее-корневое-поле), [неизвестный вид `session/update`](#неизвестный-вид-sessionupdate), [неподдерживаемое значение дискриминатора](#неподдерживаемое-значение-дискриминатора), [путь не абсолютный](#путь-не-абсолютный), [весь `session/new` отвергнут из-за групп опций](#весь-sessionnew-отвергнут-из-за-групп-опций);
- код и тесты: [`TypeError` при кодировании](#typeerror-при-кодировании), [`must be a JSON object` на верном объекте](#must-be-a-json-object-на-верном-объекте), [ошибки про `*.freezed.dart`](#ошибки-про-freezeddart), [тесты `codelab_acp_testing` красные после правки](#тесты-codelab_acp_testing-красные-после-правки), [`conformance:client` пишет про роли](#conformanceclient-пишет-про-роли).

## Метод не зарегистрирован

**Симптом.** Декодер бросает `JsonRpcProtocolException` с `kind == unknownMethod`:

```text
ACP method "foo/bar" is not registered.
```

**Причина.** Имени нет в `acpMethodRegistry` (`requireAcpMethod`, `lib/src/acp/acp_method_codec.dart`). Это может быть опечатка, метод расширения (`_codelab/session/usage`, `_vendor/…`), метод схемы, которого нет в пакете (`authenticate`), или метод более новой версии ACP.

**Что сделать.**

1. Сверьте имя со [схемой](../../../../docs/protocols/acp/protocol/17-Schema.md).
2. Для расширений ничего менять в пакете не нужно: приёмник маршрутизирует такие методы по «сырому» имени до вызова декодера ([глава 02](02-compatibility.md#расширения-codelab)).
3. Для запроса с неизвестным методом ответьте `-32601`: `AcpProtocolError.unknownMethod(method).toJsonRpcError()`. Для уведомления ответа нет.
4. Если метод стандартный и нужен, добавьте его по [рецепту 2](03-extending.md#рецепт-2-добавить-метод).

## Ответ без `result` и `error`

**Симптом.** `decodeJsonRpcMessage` бросает `invalidShape`:

```text
response messages must include exactly one of result or error.
```

Код JSON-RPC при переводе — `-32600 Invalid Request`.

**Причина.** В кадре есть `id`, но нет `method`, а полей `result` и `error` нет совсем либо есть оба (`json_rpc_message.dart`). Ключ `result` должен присутствовать, даже если значение пусто: `{"jsonrpc":"2.0","id":1,"result":null}` допустим, `{"jsonrpc":"2.0","id":1}` — нет. Кадр без `id` и без `method` даёт `response messages must include id.`

**Что сделать.** Исправьте отправителя. Если кадр пишете вы, собирайте его через `JsonRpcMessage.response(...)` и `encodeJsonRpcMessage`: ответ без ошибки всегда пишет `result`, а ответ с `error` не пишет его.

## `result: null` не принимается

**Симптом.** `decodeAcpResult(sessionPromptMethod, null)` бросает `invalidShape`:

```text
promptResponse must be a JSON object.
```

**Причина.** Результат — всегда объект. Пустое значение `null` пакет принимает только там, где ACP показывает такой ответ: `session/load` (`LoadSessionResponse.fromJson`, пример из `03-Session Setup.md`), `fs/write_text_file`, `terminal/kill` и `terminal/release`. Остальные ответы агента с `result: null` отвергаются.

**Что сделать.** Проверьте, что агент отвечает объектом (`{}` для пустого результата, как `session/set_mode`). Не расширяйте `null` на другие методы без требования схемы.

## Запрос и уведомление перепутаны

**Симптом.** `invalidShape` с текстом `session/update must be a notification.` или `session/prompt must be encoded as a request.` и подобным.

**Причина.** Функции кодека различают вид метода (`AcpRequestMethod` или `AcpNotificationMethod`):

| Вызов | Бросает, если метод… |
|---|---|
| `decodeAcpRequestParams(request)` | уведомление (`session/cancel`, `session/update`) |
| `decodeAcpNotificationParams(notification)` | запрос |
| `encodeAcpRequest` | уведомление |
| `encodeAcpNotification` | запрос |

Кроме того, `decodeAcpResponseResult` бросает `cannot decode an error response result.` для ответа с ошибкой.

**Что сделать.** Выбирайте функцию по типу `JsonRpcMessage` (`JsonRpcRequest`, `JsonRpcNotification`, `JsonRpcResponse`), как в скрипте из главы 00. Ответ с ошибкой разбирайте по `response.error`, а не как результат.

## Лишнее корневое поле

**Симптом.**

```text
promptRequest contains unsupported root field "xVendor"; use _meta for extensions.
```

Код при переводе — `-32602 Invalid params` (фаза `params`).

**Причина.** Строгий разбор: в корне объекта схемы нет такого ключа. Три типичные ситуации:

1. Кадр пришёл в запросе, который разбирается строго (запросы клиента, `session/request_permission`, `fs/*`, `terminal/*`). Терпимость есть только в результатах ответов, в `session/update` и в объектах возможностей `initialize` ([таблица в главе 02](02-compatibility.md#что-строго-что-терпимо)).
2. Поле действительно есть в схеме, но не добавлено в `allowedKeys` модели (или в общее множество `allowedKeys` метода `SessionUpdate.fromJson`).
3. Это расширение, а не поле схемы.

**Что сделать.** Для случая 1 исправьте отправителя: расширения идут в `_meta`. Для случая 2 добавьте поле по [рецепту 1](03-extending.md#рецепт-1-добавить-поле-в-существующее-сообщение). Для случая 3 переложите данные в `_meta.codelab`. Не делайте запрос агента клиенту терпимым к лишним полям: это граница безопасности.

## Неизвестный вид `session/update`

**Симптом.** `decodeAcpNotificationParams` бросает `invalidShape`:

```text
sessionUpdate "usage_update" is not supported.
```

**Причина.** `SessionUpdate.fromJson` знает десять видов (`SessionUpdate.knownKinds`); `usage_update` и другие виды из более новых версий ACP или от конкретных агентов в их число не входят.

**Что сделать.** Перед декодером вызовите `unsupportedSessionUpdateKind(notification.params)`: если она вернула строку, пропустите обновление без ошибки (так делает клиент, `_handleSessionUpdate` в `codelab_client_acp`). Если вид настоящий и нужный, добавьте его по [рецепту 3](03-extending.md#рецепт-3-добавить-вид-sessionupdate), и обязательно внесите в `knownKinds`: без этого приёмник продолжит молча пропускать его, а тесты пакета останутся зелёными.

## Неподдерживаемое значение дискриминатора

**Симптом.** Одно из сообщений:

```text
contentBlock.type "video" is not supported.
toolCallContent.type "…" is not supported.
requestPermissionOutcome "maybe" is not supported.
stopReason has an unsupported value.
toolCall.status has an unsupported value.
permissionOption.kind has an unsupported value.
```

**Причина.** Эти значения разбираются строго. Незнакомое значение отвергает всё сообщение: например, `stopReason: "paused"` в ответе на `session/prompt` отвергает ответ целиком, хотя `decodeAcpResult` терпим к лишним полям. Терпимость к лишним *полям* и к незнакомым *значениям* — разные вещи.

**Что сделать.** Сверьтесь со схемой: значение есть там — добавьте его ([рецепт 4](03-extending.md#рецепт-4-добавить-значение-перечисления)); нет — это ошибка агента, и приёмник должен показать её, а не прятать (корневой `AGENTS.md`, §2: нельзя скрывать protocol error). Исключения с мягким разбором — `ToolKind`, `McpServerUnknown` и опции конфигурации незнакомого типа ([глава 02](02-compatibility.md)).

## Путь не абсолютный

**Симптом.** Запрос `fs/*` или `terminal/create` отвергается:

```text
path must be a non-empty absolute path.
```

**Причина.** Для `path` в `fs/read_text_file`, `fs/write_text_file` и для `cwd` в `terminal/create` пакет требует абсолютный путь: POSIX (`/…`), Windows с диском (`C:\…` или `C:/…`) или UNC (`\\server\share`). Пакет платформенно-независимый и не использует `dart:io`, поэтому сам распознаёт все три формы (`fs.dart`, `terminal.dart`).

**Что сделать.** Исправьте отправителя: относительный путь в ACP недопустим. Пакет проверяет только форму. Ограничение рабочей папкой сессии — обязанность приёмника: путь вне папки отклоняется как ошибка безопасности до выполнения операции (корневой `AGENTS.md`, §10).

## Весь `session/new` отвергнут из-за групп опций

**Симптом.** Ответ на `session/new` отвергается с текстом:

```text
sessionConfigValueId must be a non-empty string.
```

**Причина.** В схеме `SessionConfigSelectOptions` бывает плоским списком или списком групп (`group`, `name`, `options`). Пакет разбирает только плоский список, поэтому запись-группа падает в `SessionConfigSelectOption.fromJson` (там нет поля `value`). Воспроизводится на `decodeAcpResult(sessionNewMethod, {…'configOptions': [{'type': 'select', …, 'options': [{'group': 'g1', 'name': 'Group', 'options': […]}]}]})`.

**Что сделать.** Это расхождение пакета со схемой, а не ошибка агента. Нужен OpenSpec change на модель сгруппированных значений ([рецепт 1](03-extending.md#рецепт-1-добавить-поле-в-существующее-сообщение) и [рецепт 5](03-extending.md#рецепт-5-сделать-разбор-терпимым)); обходного пути в пакете нет.

## `TypeError` при кодировании

**Симптом.** `encodeAcpRequest`, `encodeAcpParams` или `encodeAcpResponse` падают не `JsonRpcProtocolException`, а `TypeError`:

```text
type '_CancelNotification' is not a subtype of type 'InitializeRequest' of 'value'
```

А для метода-уведомления `encodeAcpResponse` падает так:

```text
type '_CancelNotification' is not a subtype of type 'Never' of 'value'
```

**Причина.** Реестр хранит определения с типами `Object`, и проверка «эта модель подходит к этому методу» происходит во время выполнения, на приведении типа. Это ошибка программиста, а не вход от удалённой стороны, поэтому типизированной ошибки протокола для неё нет.

**Что сделать.** Передавайте модель, которая соответствует методу (по таблице из [главы 01](01-design.md#реестр-методов)). Если хотите проверку на этапе компиляции, берите типизированные определения: `acpInitialize.encodeParams(request)` принимает только `InitializeRequest`. В обработчике входящих кадров ловите `JsonRpcProtocolException`, а не `Exception`.

## `must be a JSON object` на верном объекте

**Симптом.** Тест или код передаёт в `fromJson` словарь, который выглядит как объект, но получает:

```text
agentCapabilities must be a JSON object.
```

**Причина.** `requireJsonObject` принимает только `Map<String, Object?>`, а вложенный пустой литерал `{}` в контексте `Object?` Dart выводит как `Map<dynamic, dynamic>`: такой словарь не проходит проверку. Воспроизводится на `AgentCapabilities.fromJson({'sessionCapabilities': {'list': {}}})`; с `<String, Object?>{}` и с результатом `jsonDecode(...)` тот же словарь принимается. Сообщение при этом не отличает «не объект» от «объект с неподходящим типом ключей».

**Что сделать.** В тестах строите вложенные пустые объекты как `<String, Object?>{}` или берите данные из `jsonDecode`, как сделаны `session_update_tolerance_test.dart` и `tool_kind_test.dart`. Данные из других разборщиков (YAML и т. п.) приводите к `Map<String, Object?>` до вызова.

## Ошибки про `*.freezed.dart`

**Симптом.** Анализатор и тесты падают на отсутствующем файле:

```text
error - src/acp/fs.dart:8:6 - Target of URI doesn't exist: 'package:codelab_acp_protocol/src/acp/fs.freezed.dart'. … - uri_does_not_exist
error - src/acp/fs.dart:11:39 - Classes can only mix in mixins and classes. - mixin_of_non_class
```

Тест при этом не загружается: `Failed to load "test/fs_test.dart"`.

**Причина.** Файлы `*.freezed.dart` не хранятся в git. Они пропали в новом worktree или после чистки.

**Что сделать.** Запустите в каталоге пакета `fvm dart run build_runner build --delete-conflicting-outputs`. Для всего репозитория — команда из [запуска из исходников](../../../../docs/user/run-from-source.md#1-подготовка).

## Тесты `codelab_acp_testing` красные после правки

**Симптом.** После добавления метода или вида `session/update` падают `fixtures_coverage_test.dart` и `fixtures_agent_coverage_test.dart` (вывод — в [главе 03](03-extending.md#шаг-в-фикстурах)).

**Причина.** Проверка покрытия требует фикстуру каждой роли для каждого метода и вида обновления: [как она работает](../../codelab_acp_testing/doc/03-testing-and-coverage.md#как-работает-проверка-покрытия).

**Что сделать.** Добавьте фикстуру ([инструкция](../../codelab_acp_testing/doc/04-recipes-and-troubleshooting.md#как-написать-новую-фикстуру)). Запись в `pendingCoverage` или `agentPendingCoverage` допускайте только с комментарием «почему»: список должен только сокращаться.

## `conformance:client` пишет про роли

**Симптом.** В выводе много строк вида:

```text
acp/ws-auth-bearer-required has roles [agent] without "client"
```

и счётчик `~37`.

**Причина.** Не ошибка. Фикстура с ролью `agent` пропускается клиентским драйвером, фикстура с ролью `client` — агентским (поле `roles`, [формат фикстуры](../../codelab_acp_testing/doc/01-fixture-format.md#верхний-уровень)). Итог — `All tests passed!`.

**Что сделать.** Ничего. Красным считается только `-N` в счётчике и итоговая строка `Some tests failed.`

## Смотрите также

- [Совместимость](02-compatibility.md) — строгость и терпимость по видам сообщений.
- [Устройство](01-design.md) — коды ошибок и функции кодека.
- [Начало работы и тесты](00-getting-started.md) — скрипт разбора кадра и команды проверки.
