# Тестирование ACP-сервера

Сервер проверяется без процессов, сокетов и провайдера: кадры идут по паре транспортов в памяти тем же кодеком, что на проводе, модель играет сценарий, время и идентификаторы детерминированы. Глава показывает уровни тестов, стенды `test/support/`, корпус golden-фикстур и то, как добавить тест. Общие правила тестов агента — в [главе ядра о тестировании](../../codelab_agent_core/doc/12-testing.md), правила TDD — в [`AGENTS.md`](../AGENTS.md) пакета (§3) и ядра (§2).

## Уровни тестов

Пакет содержит около 17 тыс. строк тестов. Весь набор: 544 теста, 5 пропущены (см. ниже).

| Уровень | Где | Что проверяет |
|---|---|---|
| чистые функции | `test/projection/`, `config_options_test.dart`, `subagent_chain_test.dart` | `projectEvent` строка за строкой, `turnResponse`, опции и цепочки: без сервера, на значениях |
| маленькие части соединения | `outbound_queue_test.dart`, `acp_client_env_test.dart`, `acp_permission_gate_test.dart` | очередь, окружение, шлюз на `ClientChannel` (агентский конец без сервера и fake-клиент) |
| сервер целиком | `initialize_test.dart`, `session_new_test.dart`, `session_load_test.dart`, `session_list_test.dart`, `prompt_test.dart`, `cancel_test.dart`, `detach_test.dart`, `local_env_test.dart`, … | методы ACP через `ServerHarness`: кадры туда и обратно |
| мост | `session_bridge_echo_test.dart`, `session_bridge_replay_test.dart`, `usage_bridge_test.dart`, `subagent_tool_tree_bridge_test.dart` | `SessionBridge` с фальшивой сессией: гонки смены настроек, реплей, учёт usage, состояние потомков |
| usage | `usage_*_test.dart` | уведомление `_codelab/session/usage`, журнал, бюджет, засев при `session/load` |
| субагенты | `subagent_*_test.dart`, `session_load_subagent*_test.dart` | вызов `agent`, дерево потомков, реплей |
| устойчивость | `test/robustness/` | плохие кадры, закрытый вход при открытом выходе |
| контракт | `test/contract/client_application_contract_test.dart` | настоящий `AcpClientApplication` из `codelab_client_acp` против `AcpAgentServer` |
| conformance | `test/conformance_test.dart` | корпус golden-фикстур ACP на роли агента |

Название и первая строка doc-комментария теста ссылаются на раздел спецификации [`agent-acp-server`](../../../../openspec/specs/agent-acp-server/spec.md) и инвариант (`ACP-3`, `ACP-5`, …): тесты прослеживаются до требований.

### Проекция

Таблицу `projectionTable` охраняют три теста `test/projection/`:

- `every_agent_event_is_projected_test.dart` читает исходник иерархии `AgentEvent` в ядре регулярным выражением и требует, чтобы ключи таблицы совпадали с подтипами: подтип без строки или строка без подтипа — провал (ACP-6). Строки `StepEnded`, `TurnEnded`, `ContextCompacted` обязаны называть `_codelab/session/usage`.
- `event_projection_test.dart` проверяет кадры строка за строкой (`projectEvent(...).toJson()`) и итог хода (ACP-1, ACP-5, ACP-7).
- `tool_kind_mapping_test.dart` проверяет, что каждый `ToolKind` ядра переводится в `acp.ToolKind` по имени с тем же именем на проводе, и что `switchMode` в ядре не появляется.

Сам `switch` в `projectEvent` исчерпывающий: новый подтип без ветки не скомпилируется. Тест ловит обратное расхождение.

## Стенд `ServerHarness`

`ServerHarness.start(...)` ([`test/support/server_harness.dart`](../test/support/server_harness.dart)) собирает ядро так же, как хост собрал бы его для профиля `agent-serve`: `buildAgentCore` с журналом `JournalStore` (память, но «постоянный» для сборки), окружением хоста в памяти, сценарной моделью `ScriptedStreamFunction`, часами `FakeClock` и идентификаторами `SequentialIdGenerator`. Сервер подключается к клиенту парой `InProcessAcpLink`.

Ключевые параметры `start`:

| Параметр | Зачем |
|---|---|
| `steps` | шаги сценарной модели (тот же формат, что `llm.steps` в фикстурах) |
| `profile`, `narrow` | профиль и сужение возможностей хоста |
| `localListing`, `localEnv` | локальный листинг и окружение встроенного режима |
| `detachGrace` | окно переподключения |
| `slow` | агентский конец отдаёт каждый кадр с задержкой: проверка порядка «уведомления, затем ответ» на медленном транспорте (ACP-3) |
| `mcp`, `projectFiles`, `skillFiles`, `trustedProjects` | порты для MCP, файлов проекта и навыков |
| `configSource`, `projectConfig`, `rootConfig` | перезагрузка конфигурации и конфигурация папки сессии |
| `wrapRuntime`, `wrapLogger` | подмена рантайма (посмотреть `SessionSpec`) и логгера (заставить запись бросить) |

Клиентская сторона — `TestClient` (в том же файле): `request(method, params)` ждёт ответ по числовому id, `notify` шлёт уведомление, `handlers['fs/read_text_file'] = …` отвечает на запросы агента, `serveFiles(MemoryExecutionEnv)` играет `fs/*` по файлам в памяти, `next()` отдаёт следующий кадр агента, `drain()` — все пришедшие, `received` хранит все кадры по порядку, `TestClient.updates(frames)` выбирает из них поля `update`. Помощники стенда: `initialize()`, `newSession()` (возвращает `sessionId` и снимает `available_commands_update`), `prompt(sessionId, text)`, `connect()` (второе соединение к тому же серверу), `dispose()`.

Минимальный тест на стенде (файл `test/…_test.dart` рядом с остальными; проверен запуском):

```dart
import 'package:test/test.dart';

import 'support/server_harness.dart';

void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  test('текстовый ход заканчивается end_turn', () async {
    h = await ServerHarness.start(
      steps: [
        {
          'reply': [
            {'text': 'Привет'},
          ],
          'stopReason': 'stop',
        },
      ],
    );
    await h.initialize();
    final sessionId = await h.newSession();

    final response = await h.prompt(sessionId, 'Привет');

    expect(response.resultMap, {'stopReason': 'end_turn'});
    final kinds = TestClient.updates(
      h.client.received,
    ).map((update) => update['sessionUpdate']);
    expect(kinds, contains('agent_message_chunk'));
  });
}
```

Если запросов агента к клиенту в тесте нет, `handlers` не нужны. Если модель просит инструмент, который читает файл, подключите `h.client.serveFiles(MemoryExecutionEnv(cwd: '/work/demo'))` до `prompt`; если инструмент требует разрешения, клиент отвечает на `session/request_permission` обработчиком или вручную (`h.client.next()` и `respond`); образец — [`cancel_test.dart`](../test/cancel_test.dart).

### `ClientChannel`: шлюз и окружение без сервера

Для `AcpPermissionGate` и `AcpClientExecutionEnv` сервер не нужен. `ClientChannel.open()` ([`test/support/client_channel.dart`](../test/support/client_channel.dart)) собирает агентский конец так же, как `_Connection`: очередь, реестр запросов и маршрутизатор; на другом конце — `FakeClient`. Возможности клиента по умолчанию — `fs` и `terminal`. Часы `FakeClock` позволяют проверить таймауты без ожидания.

Тест на шлюз: клиент выбирает вариант, которого агент не предлагал (проверен запуском):

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcRequest;
import 'package:codelab_agent_acp/src/acp_permission_gate.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';

void main() {
  test('вариант, которого не предлагали, — rejectOnce', () async {
    final ch = await ClientChannel.open();
    final gate = AcpPermissionGate(ch.link, logger: ch.logger);
    ch.client.handlers['session/request_permission'] =
        (JsonRpcRequest _) => {
          'outcome': {'outcome': 'selected', 'optionId': 'allow_forever'},
        };

    final decision = await gate.request(
      PermissionRequest(
        toolCallId: 'call_1',
        tool: 'exec',
        kind: ToolKind.execute,
        tier: ToolTier.exec,
        title: 'echo hi',
        rawInput: const {'command': 'echo hi'},
        pattern: 'echo hi',
        allowAlwaysOffered: true,
      ),
      CancelToken.none,
    );

    expect(decision, PermissionDecision.rejectOnce);
    expect(ch.logger.eventsOf('acp.permission.unknown_option'), hasLength(1));
  });
}
```

`ch.logger` — `RecordingLogger` ядра: записи лога доступны тесту по имени события.

### Тест проекции

Проекцию проверяет вызов функции без сервера. Событие строится конструктором ядра (`MessageDelta(s, delta:, partial:)` и т. п.), результат сравнивается как JSON (проверено запуском):

```dart
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' as acp;
import 'package:codelab_agent_acp/src/event_projection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

void main() {
  const s = SessionId('sess_1');

  test('ThoughtDelta даёт agent_thought_chunk', () {
    final updates = projectEvent(
      ThoughtDelta(
        s,
        delta: 'hmm',
        partial: AssistantMessage(
          content: const [],
          model: ModelRef(
            provider: 'scripted',
            id: 'scripted-1',
            api: ProviderApi.openaiChat,
            baseUrl: Uri.parse('http://localhost/v1'),
            contextWindow: 1000,
            maxOutputTokens: 100,
          ),
          usage: Usage.zero,
          stopReason: StopReason.stop,
          timestamp: DateTime.utc(2026),
        ),
      ),
      configOptions: () => const <acp.SessionConfigOption>[],
    );

    expect(updates.single.toJson(), {
      'sessionUpdate': 'agent_thought_chunk',
      'content': {'type': 'text', 'text': 'hmm'},
    });
  });
}
```

В тестах пакета эту сборку `ModelRef` берут готовой — `scriptedModel` из `test/support/server_harness.dart`.

## Conformance на golden-фикстурах

Golden-фикстура — JSON-сценарий обмена клиента и агента; один файл проверяет обе стороны протокола. Формат, матчеры (`$any`, `$capture`, `$partial`, …) и переменные (`${cwd}`, `${sessionId}`) — в [README `codelab_acp_testing`](../../codelab_acp_testing/README.md#golden-фикстуры) и спецификации [`acp-golden-fixtures`](../../../../openspec/specs/acp-golden-fixtures/spec.md). Корпус — [`codelab_acp_testing/fixtures/acp/`](../../codelab_acp_testing/fixtures/acp) (85 фикстур).

`test/conformance_test.dart` для каждой фикстуры из `loadFixtureCorpus()` вызывает `runAgentFixture(fixture, startAgent)`. Драйвер играет клиента: шлёт кадры `c2a`, сравнивает ответы агента с `a2c` и отвечает на запросы агента по фикстуре. Агента поднимает фабрика `startAgent`: она собирает ядро и сервер так же, как бинарь `codelab-agent` по stdio:

- профиль и режим — из `setup` фикстуры; файлы и команды идут через клиента (`AcpClientExecutionEnv`), листинг — локально (`LocalExecutionEnv` над временным `cwd`);
- модель — `ScriptedStreamFunction.fromJson(setup.llm)`; после прогона `verify()` проверяет, что все шаги модели использованы;
- журнал сессий — `JournalStore` в памяти; с меткой `usageLedger` в `extensions` фикстуры — настоящие файлы во временном каталоге;
- `ProjectFilesLoader` из `codelab_agent_io` (только `dev_dependency`) с пустым временным `CODELAB_HOME`: домашний каталог разработчика не должен влиять на кадры;
- MCP — поддельные серверы из `setup.mcp`.

Ключи `setup.config`, которые принимает фабрика, ограничены списком (`agent`, `budget`, `compaction`, `mcp`, `providers`, `skills`, `trusted_projects`); любой другой — `FormatException` с путём ключа (`config.bogus`). Это намеренно: молча проигнорированная настройка сделала бы фикстуру ложно зелёной. Три теста в конце файла проверяют это громкое поведение и проверку лишнего вызова MCP.

### Запуск

Из корня репозитория:

```bash
melos run conformance:agent
```

Скрипт запускает `fvm dart test packages/dart/codelab_agent_acp/test/conformance_test.dart`. С переменной `CODELAB_TEST_REPORT_DIR` он пишет JSON-отчёт `dart/codelab_agent_acp.conformance.json`. Скрипт входит в `melos run check`. Прямой запуск из каталога пакета (проверен): `fvm dart test test/conformance_test.dart`.

Итог прогона (88 тестов: 85 фикстур и три контрольных теста фабрики; около 20 с на этой машине):

```text
00:18 +83 ~5: the factory still rejects an unknown config key
00:18 +83 ~5: the factory rejects an mcp.servers entry that is not a fake
00:18 +83 ~5: an unexpected tools/call of a fake MCP server fails verify()
00:18 +83 ~5: All tests passed!
```

### Что пропускается

Пять фикстур драйвер агента пропускает с причиной (`markTestSkipped`):

| Фикстура | Причина |
|---|---|
| `acp/errors-unknown-session-update-tolerated`, `acp/prompt-update-plan`, `acp/tool-kind-unknown-tolerated` | роли только `[client]`: проверяют клиента |
| `acp/stdio-framing-large-line`, `acp/ws-auth-bearer-required` | `setup.transport`: их играет драйвер транспорта против бинаря, а не этот прогон |

Остальные клиентские стороны корпуса проверяют [`melos run conformance:client`](../../codelab_client_acp/README.md) и `conformance:embedded` (встроенный агент в процессе CLI).

### Когда фикстура разошлась с кодом

Расхождение исправляется в коде агента. Фикстура меняется только со ссылкой на спецификацию ACP в её поле `spec` (правила — в `acp-golden-fixtures`, «Правила изменения фикстур»). Чтобы увидеть, где именно разошлись кадры, запустите одну фикстуру: драйвер бросает `AgentFixtureFailure` с `fixtureId`, `frameIndex` (номер кадра), ожидаемым и фактическим значением и списком расхождений.

## `dart_test.yaml` и тег `slow`

`dart_test.yaml` пакета объявляет один тег — `slow`. Помечен файл `usage_ledger_size_test.dart` (`@Tags(['slow'])`): замер размера и времени ответа журнала usage на 1000 ходов по 40 шагов. Лимит времени для такого теста вчетверо больше обычного (`timeout: 4x`). Из обычного прогона тег не исключается: `fvm dart test` и `melos run check` запускают такие тесты, поэтому правка журнала usage проверяется ими же.

## Какие проверки запускать

Состав проверок перед pull request — [корневой `AGENTS.md`, §21](../../../../AGENTS.md). Для этого пакета обычно:

| Что изменено | Что запустить |
|---|---|
| код или тесты пакета | `fvm dart format --set-exit-if-changed <файлы>`, `fvm dart analyze` и `fvm dart test` в каталоге пакета |
| проекция, проводные поля, ACP-проекция агента | то же и `melos run conformance:agent`; если затронут общий ACP — `conformance:client` и `protocol-conformance` |
| `pubspec.yaml` пакета, импорты между пакетами | `melos run guard` |
| встроенный режим (`localEnv`) или мост `codelab_embedded` | `melos run conformance:embedded`, `melos run test:e2e:cli:embedded` |

Прогоны на устройстве (`test:e2e:app:*`) — только в ветке `release/<версия>`.

## Смотрите также

- [`codelab_acp_testing`](../../codelab_acp_testing/README.md) — фикстуры и драйверы.
- [Тестирование агента (ядро)](../../codelab_agent_core/doc/12-testing.md) — `ScriptedStreamFunction`, `RecordingLogger`, `FakeClock`.
- [Рецепты и частые проблемы](05-extending-and-troubleshooting.md).
