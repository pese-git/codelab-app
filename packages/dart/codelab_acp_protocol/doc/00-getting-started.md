# Начало работы и тесты

Эта глава для разработчика, который впервые открыл `codelab_acp_protocol`. Она отвечает на практические вопросы: как подготовить пакет, как прогнать его тесты и скрипты Melos, как разобрать конкретный кадр, какие тесты есть и в какой файл идти с задачей. Устройство пакета объясняют следующие главы; сюда они ссылаются по месту.

Пакет — чистый Dart без Flutter и без `dart:io`. У него нет исполняемого файла и нет состояния: он только превращает строки JSON в типизированные модели ACP и обратно. Поэтому «запустить» его можно двумя способами: тестом или маленьким скриптом, который читает кадр.

## Подготовка

Шаги подготовки репозитория описаны в [запуске из исходников](../../../../docs/user/run-from-source.md#1-подготовка). Для этого пакета нужно три вещи; команды выполняются из корня репозитория.

1. Установите [FVM](https://fvm.app). Версия Flutter SDK лежит в `.fvmrc`; все команды Dart идут через `fvm`.
2. Поставьте SDK и свяжите пакеты:

   ```bash
   fvm install
   fvm flutter pub get
   fvm dart run melos bootstrap
   ```

3. Создайте сгенерированный код. Модели описаны через `freezed`, а файлы `*.freezed.dart` лежат в `.gitignore`: без них пакет не компилируется. В новом worktree и после любой правки модели запустите в каталоге пакета:

   ```bash
   cd packages/dart/codelab_acp_protocol
   fvm dart run build_runner build --delete-conflicting-outputs
   ```

   Команда создаёт `*.freezed.dart` рядом с исходниками. Если вы поменяли модель и не запустили команду, анализатор и тесты работают с устаревшим сгенерированным кодом и сообщают об ошибках в нём.

Проверка формата и анализатор — как в любом пакете:

```bash
fvm dart format --set-exit-if-changed lib test
fvm dart analyze
```

В чистом дереве формат ничего не меняет, а анализатор отвечает `No issues found!`.

## Тесты

Все тесты пакета запускаются из его каталога:

```bash
cd packages/dart/codelab_acp_protocol
fvm dart test
```

Последняя строка вывода показывает число пройденных тестов (на момент написания — 135):

```text
00:00 +135: All tests passed!
```

Один файл или один тест по имени:

```bash
fvm dart test test/session_update_tolerance_test.dart
fvm dart test test/session_update_tolerance_test.dart -n "messageId"
```

То же из корня репозитория делает скрипт Melos `protocol-conformance`: в корневом `pubspec.yaml` он определён как `fvm dart test packages/dart/codelab_acp_protocol/test`, то есть запускает только тесты этого пакета.

```bash
fvm dart run melos run protocol-conformance
```

### Какие скрипты Melos проверяют протокольный слой

Модели пакета используют обе стороны протокола, поэтому проверки не ограничиваются самим пакетом. Описания взяты из секции `melos` корневого `pubspec.yaml`.

| Скрипт | Что запускает | Когда нужен |
|---|---|---|
| `protocol-conformance` | тесты этого пакета | любая правка `lib/` или `test/` |
| `conformance:client` | золотые фикстуры ACP против `AcpClientApplication` (клиентская роль) | изменены модели, кодеки, ошибки |
| `conformance:agent` | тот же корпус против `AcpAgentServer` (роль агента) | то же |
| `conformance:embedded` | корпус против встроенного агента в процессе CLI (`codelab test-scenario … --agent embedded`) | то же, если задет встроенный агент |
| `guard` | сторож границ: импорты между пакетами, allowlist зависимостей | изменён `pubspec.yaml` или импорты |

Для изменения моделей или кодеков [AGENTS.md пакета](../AGENTS.md) требует `protocol-conformance`, `conformance:client` и `conformance:agent` (корневой `AGENTS.md`, §21). Полный `melos run check` запускают по просьбе пользователя или в ветке выпуска.

Короткий вывод `conformance:client` в чистом дереве (фикстуры с другой ролью пропускаются, это нормально):

```text
00:05 +48 ~37: packages/dart/codelab_client_acp/test/fixtures/client_fixture_conformance_test.dart: acp/ws-auth-bearer-required
  acp/ws-auth-bearer-required has roles [agent] without "client"
00:05 +48 ~37: All tests passed!
```

## Карта тестов

В `test/` 15 файлов. Каждый проверяет одну группу сообщений или одно свойство кодека. Почти все модели проверяются одинаково: круговой проход «модель → JSON → модель» и отказы на неверной форме.

| Файл | Что проверяет |
|---|---|
| `json_rpc_codec_test.dart` | кадр JSON-RPC: запрос, уведомление, ответ с `result: null`, ответ с ошибкой; битый JSON, неверная форма кадра, неверный `id`, ответ сразу с `result` и `error` |
| `acp_method_codec_test.dart` | реестр из 17 методов; `decode…`/`encode…` по имени метода; отказ на неизвестном методе и на неверном направлении (запрос ↔ уведомление); `_meta` как точка расширения; лишнее корневое поле; перевод в типизированные ошибки |
| `protocol_error_test.dart` | соответствие `AcpProtocolErrorKind` кодам JSON-RPC, содержимое `error.data`, код `-32002` |
| `protocol_conformance_test.dart` | сквозной проход через строку: запрос, уведомление, ответ; лишнее поле вне `_meta` отвергается; ответ-ошибка не декодируется как результат |
| `response_tolerance_test.dart` | `decodeAcpResult` игнорирует незнакомые корневые поля на любой глубине; невалидная форма по-прежнему отвергается; остальные декодеры строгие |
| `session_update_tolerance_test.dart` | то же для `session/update` (поле `messageId`, настоящий `usage_update`); `unsupportedSessionUpdateKind`; список `SessionUpdate.knownKinds` совпадает с разбором |
| `tool_kind_test.dart` | мягкий разбор `ToolKind`: незнакомая строка даёт `other`, не-строка — ошибку; `switch_mode`; `unrecognizedToolKind` |
| `initialize_test.dart` | рукопожатие `initialize`: возможности, `authMethods`, значения по умолчанию, версия протокола, терпимость объектов возможностей |
| `session_test.dart` | `session/new`, `load`, `list`, `set_config_option`; MCP-серверы разных видов; опции конфигурации неизвестного типа |
| `set_session_mode_test.dart` | `session/set_mode`: запрос, пустой ответ, запись в реестре |
| `prompt_test.dart` | `session/prompt`: блоки содержимого, `stopReason`, `session/cancel` |
| `session_update_test.dart` | все виды `session/update` и `SessionNotification` |
| `permission_test.dart` | `session/request_permission`: варианты, исходы, статусы вызовов |
| `fs_test.dart` | `fs/read_text_file`, `fs/write_text_file`; абсолютные пути POSIX, Windows и UNC |
| `terminal_test.dart` | пять методов `terminal/*`; `cwd` как абсолютный путь |

Каждый файл подробно описан его собственными именами тестов: `fvm dart test <файл> -r expanded` печатает их списком.

### Золотые фикстуры

Корпус фикстур лежит не здесь, а в [`codelab_acp_testing`](../../codelab_acp_testing/doc/01-fixture-format.md): `packages/dart/codelab_acp_testing/fixtures/acp/`. Фикстура — JSON-файл со сценарием обмена: кадры `c2a` (клиент → агент) и `a2c` (агент → клиент). Её проигрывают и против клиента, и против агента, поэтому она проверяет модели этого пакета с обеих сторон сразу. Формат и правила — в [`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md).

Проверка покрытия корпуса зависит от этого пакета: новый метод или вид `sessionUpdate` без фикстуры останавливает тесты `codelab_acp_testing`. Как она устроена — в [руководстве по тестовому пакету](../../codelab_acp_testing/doc/03-testing-and-coverage.md#как-работает-проверка-покрытия), что делать — в [главе 03](03-extending.md#шаг-в-фикстурах).

## Разбор кадра в отдельном скрипте

Чаще всего нужно ответить на вопрос «почему пакет не принимает вот этот кадр». Положите скрипт в `test/scratch/decode_frame.dart` (каталог в репозитории не хранится, не коммитьте его) и подставьте нужные строки в `main`. Скрипт делает то же, что приёмник кадров: сначала разбирает кадр JSON-RPC, затем параметры, и при ошибке показывает, какой код получил бы отправитель.

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

/// Разбирает одну строку кадра так, как это делает получатель.
void inspect(String line) {
  final JsonRpcMessage message;
  try {
    message = decodeJsonRpcMessage(line);
  } on JsonRpcProtocolException catch (error) {
    final protocolError = AcpProtocolError.fromException(error);
    print('кадр: ${error.kind.name}: ${error.message}');
    print('  -> ${protocolError.jsonRpcCode} ${protocolError.jsonRpcMessage}');
    return;
  }

  try {
    switch (message) {
      case JsonRpcRequest():
        print('запрос ${message.method}: ${decodeAcpRequestParams(message)}');
      case JsonRpcNotification():
        print(
          'уведомление ${message.method}: '
          '${decodeAcpNotificationParams(message)}',
        );
      case JsonRpcResponse():
        print('ответ id=${message.id.toJsonValue()}');
    }
  } on JsonRpcProtocolException catch (error) {
    final protocolError = AcpProtocolError.fromException(
      error,
      phase: AcpProtocolErrorPhase.params,
      method: message is JsonRpcRequest ? message.method : null,
    );
    print('параметры: ${error.kind.name}: ${error.message}');
    print('  -> ${protocolError.jsonRpcCode} ${protocolError.jsonRpcMessage}');
  }
}

void main() {
  // tool_call с видом, которого нет в схеме: разбор мягкий.
  inspect(
    '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1",'
    '"update":{"sessionUpdate":"tool_call","toolCallId":"call_future",'
    '"title":"Future tool","kind":"future_kind","status":"pending"}}}',
  );
  // Лишнее поле в корне параметров запроса: строгий разбор.
  inspect(
    '{"jsonrpc":"2.0","id":1,"method":"session/prompt","params":'
    '{"sessionId":"s1","prompt":[{"type":"text","text":"hi"}],"xVendor":true}}',
  );
  // Метод вне реестра.
  inspect('{"jsonrpc":"2.0","id":1,"method":"foo/bar","params":{}}');
  // Оборванный JSON.
  inspect('{"jsonrpc":"2.0",');
  // Неверный тип поля.
  inspect(
    '{"jsonrpc":"2.0","id":11,"method":"session/prompt","params":'
    '{"sessionId":"s1","prompt":"not a list"}}',
  );
  // Вид session/update, которого нет в пакете.
  inspect(
    '{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"s1",'
    '"update":{"sessionUpdate":"usage_update","used":1200,"size":32768}}}',
  );
}
```

Запуск из каталога пакета:

```bash
fvm dart run test/scratch/decode_frame.dart
```

Вывод (первая строка сокращена в середине):

```text
уведомление session/update: SessionNotification(sessionId: SessionId(value: s1), update: SessionUpdate.toolCall(toolCall: ToolCall(toolCallId: ToolCallId(value: call_future), title: Future tool, kind: ToolKind.other, … meta: null)), meta: null)
параметры: invalidShape: promptRequest contains unsupported root field "xVendor"; use _meta for extensions.
  -> -32602 Invalid params
параметры: unknownMethod: ACP method "foo/bar" is not registered.
  -> -32601 Method not found
кадр: invalidJson: Unexpected end of input
  -> -32700 Parse error
параметры: invalidShape: prompt must be an array.
  -> -32602 Invalid params
параметры: invalidShape: sessionUpdate "usage_update" is not supported.
  -> -32602 Invalid params
```

Что видно из вывода:

- незнакомый `kind` инструмента не ошибка: он стал `ToolKind.other`;
- лишнее поле `xVendor` в запросе — ошибка, а в сообщении назван тип (`promptRequest`) и подсказка про `_meta`;
- `usage_update` декодер отвергает, и это ожидаемо: клиент сначала спрашивает `unsupportedSessionUpdateKind` и пропускает такое обновление (подробнее — [глава 02](02-compatibility.md#неизвестный-вид-sessionupdate)).

Тот же приём работает в тесте: положите строку в `jsonDecode`, оберните в `JsonRpcMessage.notification(...)` и вызовите `decodeAcpNotificationParams` — так сделаны `session_update_tolerance_test.dart` и `tool_kind_test.dart`. Кадры для проверки берите из настоящих источников: из лога обмена, из фикстур `codelab_acp_testing/fixtures/acp/` или из чужого агента.

### Как найти модель по тексту ошибки

Первое слово сообщения — это `path`, который модель передала в `requireAcpObject`. Он совпадает с именем модели в нижнем регистре первой буквы: `promptRequest` → `PromptRequest`. Поиск по исходникам находит файл и список допустимых ключей:

```bash
grep -rn "path: 'promptRequest'" lib
```

Если в сообщении нет имени модели (`prompt must be an array.`), это ошибка поля внутри модели: ищите по имени поля и по тексту `must be`.

## Что изменить — куда смотреть

| Задача | Файл в `lib/src` | Тест |
|---|---|---|
| добавить поле в существующее сообщение | файл модели в `acp/`: `initialize`, `session`, `prompt`, `session_update`, `permission`, `fs`, `terminal`, `tool_call` | тест с тем же именем |
| добавить метод | `acp/acp_method_codec.dart` и файл модели; экспорт в `lib/codelab_acp_protocol.dart` | `acp_method_codec_test.dart`, файл модели, фикстура в `codelab_acp_testing` |
| добавить вид `session/update` | `acp/session_update.dart` (фабрика, `knownKinds`, `allowedKeys`, `fromJson`, `toJson`) | `session_update_test.dart`, фикстура |
| изменить, что считается ошибкой формы кадра | `json_rpc/json_rpc_message.dart`, `json_rpc/json_value.dart` | `json_rpc_codec_test.dart` |
| изменить код или текст ошибки JSON-RPC | `json_rpc/protocol_error.dart` | `protocol_error_test.dart` |
| изменить терпимость к лишним полям | `acp/acp_validation.dart`, `acp/acp_method_codec.dart` | `response_tolerance_test.dart`, `session_update_tolerance_test.dart` |
| изменить разбор вида инструмента | `acp/tool_call.dart` | `tool_kind_test.dart` |
| сменить перечень значений (`StopReason`, `PermissionOptionKind` и т. п.) | файл модели, где объявлено перечисление | тест группы |

Пошаговые рецепты — в [главе 03](03-extending.md). Любую правку модели предваряет OpenSpec change: она меняет контракт всех пакетов, которые зависят от этого (корневой `AGENTS.md`, §17).
