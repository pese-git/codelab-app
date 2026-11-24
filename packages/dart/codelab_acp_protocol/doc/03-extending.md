# Расширение пакета

Глава для тех, кто вносит в пакет изменение схемы ACP: новый метод, поле, вид `session/update` или значение перечисления. Каждый рецепт — список шагов, скелет кода и перечень тестов, которые подскажут, что вы что-то забыли.

## Перед началом

1. **Источник — схема.** Метод, поле или значение добавляется только если оно есть в [`17-Schema.md`](../../../../docs/protocols/acp/protocol/17-Schema.md) или утверждено спецификацией `openspec/specs/`. Выдумывать методы, поля, состояния и семантику ACP запрещено (корневой `AGENTS.md`, §3.4). Если поведение не определено, остановитесь и предложите OpenSpec change.
2. **Нужен OpenSpec change.** Правка модели меняет контракт всех пакетов, которые зависят от этого (`codelab_client_acp`, `codelab_agent_acp`, `codelab_acp_transports`, `codelab_acp_testing`, `codelab_client_core`, `codelab_embedded` и приложения). Порядок — в [`acp-boundary.md`, §44 и §47](../../../../docs/architecture/acp-boundary.md). Красный тест коммитится до кода, но сам `git commit` — только по просьбе пользователя.
3. **Правила пакета** — в [`AGENTS.md`](../AGENTS.md): чистый Dart, типизированные модели, типизированные ошибки, forward compatibility по [главе 02](02-compatibility.md).
4. **Комментарии на русском** по схеме «почему / для чего / как использовать» (корневой `AGENTS.md`, §15). Ссылайтесь на раздел схемы и на решение change.

После любой правки запустите генерацию (`build_runner`, [глава 00](00-getting-started.md#подготовка)), а в конце — набор проверок из последнего раздела главы.

## Рецепт 1. Добавить поле в существующее сообщение

Образец — `Implementation.title` (`lib/src/acp/initialize.dart`). Схема: [`Implementation`](../../../../docs/protocols/acp/protocol/17-Schema.md) имеет `name`, `version`, необязательные `title` и `_meta`.

Шаги:

1. Добавьте поле в `factory` модели. Обязательное — `required`, необязательное — `T?`, с умолчанием — `@Default(...)`.
2. Добавьте ключ в `allowedKeys` метода `fromJson` — иначе поле отвергнет проверка корневых ключей («unsupported root field»).
3. Прочитайте поле в `fromJson`, используя хелперы файла (`_requiredString`, `_optionalString`, `_optionalInt` …; недостающий хелпер скопируйте из соседнего файла).
4. Запишите поле в `toJson`: необязательное — `if (title != null) 'title': title`.
5. Запустите `build_runner`.
6. Добавьте проверки в тест модели: круговой проход «модель → `toJson` → `fromJson`», отказ на неверном типе и случай «поля нет».

Скелет (так выглядит реальный `Implementation`):

```dart
@freezed
sealed class Implementation with _$Implementation {
  const Implementation._();

  const factory Implementation({
    required String name,
    required String version,
    String? title, // новое поле
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _Implementation;

  factory Implementation.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'implementation',
      allowedKeys: {'name', 'version', 'title', '_meta'}, // и здесь
    );

    return Implementation(
      name: _requiredString(source, 'name'),
      version: _requiredString(source, 'version'),
      title: _optionalString(source, 'title'), // читаем
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {
      'name': name,
      'version': version,
      if (title != null) 'title': title, // пишем
      if (meta != null) '_meta': meta,
    };
  }
}
```

Что подскажет, если забыли: без шага 2 реальный кадр с полем отвергается («… contains unsupported root field "title"»), а кодирование проходит; без шага 4 поле тихо теряется при пересылке — это ловит только круговой тест, поэтому пишите его.

Если поле нужно только как расширение CodeLab, не добавляйте его в модель: кладите в `_meta.codelab` ([глава 02](02-compatibility.md#расширения-codelab)).

## Рецепт 2. Добавить метод

В реестре нет метода `authenticate`, хотя он есть в схеме. Рецепт показан на нём: это реальные схема и форма сообщений. Показан способ, а не решение его добавлять: агент CodeLab отвечает на `authenticate` кодом `-32601` по спецификации [`agent-acp-server`](../../../../openspec/specs/agent-acp-server/spec.md), поэтому добавление нужно начинать с OpenSpec change.

Схема метода ([`17-Schema.md`, `authenticate`](../../../../docs/protocols/acp/protocol/17-Schema.md)): запрос `AuthenticateRequest` с обязательным `methodId` и `_meta`, ответ `AuthenticateResponse` только с `_meta`.

Шаги:

1. Создайте файл модели `lib/src/acp/<имя>.dart` с директивой `part '<имя>.freezed.dart';`. Образец ответа без полей — `SetSessionModeResponse` в `session.dart`.
2. В `acp_method_codec.dart` добавьте: импорт файла, константу имени, определение `AcpMethodDefinition<…>.request` (для уведомления — `.notification`, без результата), запись в `acpMethodRegistry` и две функции-обёртки `_encode…` (они нужны, потому что определение — `const`, а `toJson` — метод экземпляра).
3. Экспортируйте файл из `lib/codelab_acp_protocol.dart`.
4. Запустите `build_runner`.
5. Обновите тест `acp_method_codec_test.dart`: набор в `registers current MVP methods` сравнивается целиком, поэтому с новым методом он падает, пока вы не добавите имя.
6. Добавьте фикстуру в `codelab_acp_testing` (ниже) и обновите числа и таблицы в README пакета и в [главе 01](01-design.md).

Скелет модели (файл `authenticate.dart`):

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import '../json_rpc/json_value.dart';
import '../json_rpc/protocol_error.dart';
import 'acp_validation.dart';

part 'authenticate.freezed.dart';

/// Параметры `authenticate` (`17-Schema.md`, `AuthenticateRequest`).
@freezed
sealed class AuthenticateRequest with _$AuthenticateRequest {
  const AuthenticateRequest._();

  const factory AuthenticateRequest({
    required String methodId,
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _AuthenticateRequest;

  factory AuthenticateRequest.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'authenticateRequest',
      allowedKeys: {'methodId', '_meta'},
    );

    return AuthenticateRequest(
      methodId: _requiredString(source, 'methodId'),
      meta: _optionalObject(source, '_meta'),
    );
  }

  JsonObject toJson() {
    return {'methodId': methodId, if (meta != null) '_meta': meta};
  }
}

/// Ответ на `authenticate` — пустой объект, кроме `_meta`.
@freezed
sealed class AuthenticateResponse with _$AuthenticateResponse {
  const AuthenticateResponse._();

  const factory AuthenticateResponse({
    @JsonKey(name: '_meta') JsonObject? meta,
  }) = _AuthenticateResponse;

  factory AuthenticateResponse.fromJson(Object? value) {
    final source = requireAcpObject(
      value,
      path: 'authenticateResponse',
      allowedKeys: {'_meta'},
    );

    return AuthenticateResponse(meta: _optionalObject(source, '_meta'));
  }

  JsonObject toJson() {
    return {if (meta != null) '_meta': meta};
  }
}

JsonObject? _optionalObject(JsonObject source, String field) {
  if (!source.containsKey(field) || source[field] == null) {
    return null;
  }

  return requireJsonObject(source[field], path: field);
}

String _requiredString(JsonObject source, String field) {
  final value = source[field];
  if (value is String) {
    return value;
  }

  throw JsonRpcProtocolException.invalidShape('$field must be a string.');
}
```

Изменения в `acp_method_codec.dart`:

```dart
import 'authenticate.dart';

const authenticateMethod = 'authenticate';

const acpAuthenticate =
    AcpMethodDefinition<AuthenticateRequest, AuthenticateResponse>.request(
      method: authenticateMethod,
      decodeParams: AuthenticateRequest.fromJson,
      encodeParams: _encodeAuthenticateRequest,
      decodeResult: AuthenticateResponse.fromJson,
      encodeResult: _encodeAuthenticateResponse,
    );

// в acpMethodRegistry:
//   authenticateMethod: acpAuthenticate,

JsonObject _encodeAuthenticateRequest(AuthenticateRequest value) =>
    value.toJson();
JsonObject _encodeAuthenticateResponse(AuthenticateResponse value) =>
    value.toJson();
```

И экспорт в барель:

```dart
export 'src/acp/authenticate.dart';
```

Тест модели (по образцу `set_session_mode_test.dart`):

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('authenticate DTOs', () {
    test('round-trips request and response', () {
      const request = AuthenticateRequest(methodId: 'agent', meta: {'k': 1});
      expect(AuthenticateRequest.fromJson(request.toJson()), request);
      expect(decodeAcpParams(authenticateMethod, request.toJson()), request);
      const response = AuthenticateResponse();
      expect(AuthenticateResponse.fromJson(response.toJson()), response);
      expect(acpMethodRegistry, contains(authenticateMethod));
    });

    test('rejects unknown root fields and a missing methodId', () {
      expect(
        () => AuthenticateRequest.fromJson({'methodId': 'a', 'x': 1}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
      expect(
        () => AuthenticateRequest.fromJson({}),
        throwsA(isA<JsonRpcProtocolException>()),
      );
    });
  });
}
```

### Шаг в фикстурах

Новый метод без фикстуры останавливает тесты `codelab_acp_testing`: проверка покрытия читает `acpMethodRegistry` и требует фикстуру каждой роли ([как она работает](../../codelab_acp_testing/doc/03-testing-and-coverage.md#как-работает-проверка-покрытия)). Вывод при добавленном `authenticate`:

```text
  Expected: empty
    Actual: Set:['authenticate']
  add a fixture with the agent role or an agentPendingCoverage entry
```

Что делать:

1. Напишите фикстуру `packages/dart/codelab_acp_testing/fixtures/acp/<область>-<сценарий>.json` по [инструкции пакета](../../codelab_acp_testing/doc/04-recipes-and-troubleshooting.md#как-написать-новую-фикстуру): `spec` ссылается на якорь файла в `docs/protocols/acp/protocol/`, кадры — по схеме.
2. Если одна из сторон метод ещё не умеет, внесите его в `pendingCoverage` (клиентская роль) или `agentPendingCoverage` (агентская) в соответствующем тесте с комментарием «почему». Список только сокращается.
3. Прогоните `conformance:client`, `conformance:agent` и `conformance:embedded`.

Научить клиент и агента обрабатывать метод — отдельная работа в `codelab_client_acp` и `codelab_agent_acp`: реестр только разбирает и пишет параметры, маршрутизацию по имени делают приёмники.

## Рецепт 3. Добавить вид `session/update`

Сейчас все десять видов схемы реализованы, поэтому скелет ниже использует вымышленное имя `example_kind` и поле `label`. Это заглушки для примера, а не ACP: настоящее имя и поля берите из схемы ([`SessionUpdate`](../../../../docs/protocols/acp/protocol/17-Schema.md)).

Шаги в `lib/src/acp/session_update.dart`:

1. Добавьте фабрику в `SessionUpdate` — это запечатанный класс, и вариант с новым именем сразу делает исчерпывающие `switch` в других пакетах неполными: анализатор покажет все места, где вид надо обработать.
2. Добавьте строку вида в `SessionUpdate.knownKinds`.
3. Добавьте новые имена полей в множество `allowedKeys` метода `SessionUpdate.fromJson`. Это общее множество для всех видов, и без него поле отвергается как лишнее.
4. Добавьте ветку в `switch` метода `fromJson` в форме `'example_kind' => SessionUpdate.exampleKind(`. Форма важна: проверка корпуса ищет виды регулярным выражением `'([a-z_]+)' => SessionUpdate\.` (`protocolSessionUpdateKinds` в `codelab_acp_testing`).
5. Добавьте ветку в `switch` метода `toJson`.
6. Запустите `build_runner`.
7. Добавьте тест в `session_update_test.dart` (круговой проход, отказ на неверной форме) и фикстуру (как в рецепте 2).

Скелет:

```dart
// 1. Фабрика в sealed class SessionUpdate:
const factory SessionUpdate.exampleKind({
  required String label,
  @JsonKey(name: '_meta') JsonObject? meta,
}) = ExampleKindUpdate;

// 2. static const knownKinds = { …, 'example_kind' };

// 3. allowedKeys в fromJson: добавить 'label'.

// 4. Ветка в switch метода fromJson:
'example_kind' => SessionUpdate.exampleKind(
  label: _requiredString(source, 'label'),
  meta: _optionalObject(source, '_meta'),
),

// 5. Ветка в switch метода toJson:
ExampleKindUpdate(:final label, :final meta) => {
  'sessionUpdate': 'example_kind',
  'label': label,
  '_meta': ?meta,
},
```

Что подскажут тесты при ошибках:

- без шага 3 тест падает: `sessionUpdate contains unsupported root field "label"; use _meta for extensions.`;
- без шага 2 **все тесты пакета проходят**, а `unsupportedSessionUpdateKind` для нового вида возвращает его имя. Приёмник тогда молча пропускает настоящее обновление как незнакомое. Тест `knownKinds matches what SessionUpdate.fromJson understands` проверяет только виды из множества и этого не ловит: следите за шагом 2 сами;
- проверка покрытия фикстурами в `codelab_acp_testing` сообщает `Actual: Set:['example_kind']`, пока нет фикстуры.

## Рецепт 4. Добавить значение перечисления

Для строгих перечислений (`StopReason`, `ToolCallStatus`, `PermissionOptionKind`, `Role`, `PlanEntryStatus`, `PlanEntryPriority`) шагов два: добавьте элемент с именем на проводе (`maxTurnRequests('max_turn_requests')`) и тест на круговой проход с новым значением. `fromJson` перебирает `values`, поэтому править его не нужно.

Новый элемент перечисления ломает исчерпывающие `switch` в пакетах-потребителях: это намеренно, анализатор покажет места, где значение надо обработать.

`ToolKind` устроен иначе: незнакомую строку он сводит к `other`, а добавить известный вид значит добавить элемент в перечисление (как `switchMode('switch_mode')`) и обновить тесты `tool_kind_test.dart`.

## Рецепт 5. Сделать разбор терпимым

Терпимость — исключение, и каждое исключение закреплено требованием спецификации. Вводить её можно только там, где сообщение приходит от внешнего процесса и проверка ничего не защищает. Запросы агента клиенту (`session/request_permission`, `fs/*`, `terminal/*`) остаются строгими: они касаются безопасности ([глава 02](02-compatibility.md)).

Варианты, как сделать терпимость:

- **Лишние корневые поля** — не нужно ничего менять: терпимость уже включена в `decodeAcpResult` и для `session/update`. Чтобы включить её для новой функции кодека, оберните вызов в `tolerateUnknownRootFields(() => …)`.
- **Незнакомое значение внутри «открытого» перечисления** — по образцу `ToolKind.fromJson`: вернуть запасное значение, а исходную строку отдавать отдельной функцией по сырому объекту (`unrecognizedToolKind`), чтобы приёмник мог записать предупреждение: пакет сам журнал не пишет.
- **Незнакомый вариант объединения** — по образцу `McpServer.unknown`: вариант-«контейнер» с сырым объектом, чей `toJson` отдаёт его без изменений. Потребитель обязан обработать этот вариант.
- **Элемент списка, который можно пропустить** — по образцу `parseSessionConfigOptionList`: вернуть `null` на незнакомом элементе и отфильтровать их.

Для каждого случая добавьте тесты в обе стороны: незнакомое принимается, а структурно неверное по-прежнему отвергается. Образцы — `response_tolerance_test.dart` и `session_update_tolerance_test.dart`.

## Рецепт 6. Расширение CodeLab

Расширение — не модель ACP, поэтому в этом пакете оно не появляется. Правила из спецификации: данные — в `_meta` (ключ `codelab` внутри `_meta`), имена методов — с префиксом `_`, и каждое расширение вводит OpenSpec change. Пакет сохраняет `_meta` как есть, а читают его потребители:

```dart
// Чтение блока расширений из модели, которую разобрал этот пакет.
final codelab = request.clientCapabilities.meta?['codelab'];
```

Разбор значений и проверку версий делает соседний пакет (`CodelabExtensions.parse` в `codelab_client_acp`). Подробности и примеры кадров — в [главе 02](02-compatibility.md#расширения-codelab).

## Что проверить в конце

Для правки моделей или кодеков ([`AGENTS.md`](../AGENTS.md), «Проверки»):

```bash
cd packages/dart/codelab_acp_protocol
fvm dart format --set-exit-if-changed lib test
fvm dart analyze
fvm dart test
cd ../../..
fvm dart run melos run protocol-conformance
fvm dart run melos run conformance:client
fvm dart run melos run conformance:agent
```

Дополнительно: `guard`, если менялись `pubspec.yaml` или импорты; `fvm dart test` в `codelab_acp_testing`, если менялся реестр методов или `SessionUpdate`; `conformance:embedded` и `test:e2e:cli:embedded`, если задет встроенный агент. Документацию (README пакета, главы этого руководства) обновляйте в том же change.
