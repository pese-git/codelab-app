# Тесты, рецепты и частые проблемы

Общая схема тестов агента — уровни, `testing.dart` ядра, golden-фикстуры ACP — описана в [главе 12 руководства по ядру](../../codelab_agent_core/doc/12-testing.md). Здесь — что относится к `codelab_embedded`: правила и карта тестов, рецепты правок и таблица «симптом, причина, что сделать». Запуск тестов и скриптов Melos — в [главе об устройстве](00-architecture-and-debugging.md#запуск-тестов-и-проверок).

## Правила

- Красный тест по критерию спецификации пишется до кода (TDD: [`AGENTS.md`](../AGENTS.md) пакета, §3, и ядра, §2). Сценарии тестов называют требования спецификации [`embedded-agent`](../../../../openspec/specs/embedded-agent/spec.md): «Жизненный цикл встроенного агента», «Локальное исполнение и containment», «Конфигурация и секреты встроенного агента».
- Агент открывается `scriptedEmbeddedAgentOpener` во временном каталоге; клиент — тестовый ACP-клиент `TestAcpClient` (`test/support/acp_client.dart`) на клиентском конце пары. `codelab_client_*` в тестах пакета не нужны: проверяются кадры протокола, а не клиентское состояние.
- Сети нет. У `scriptedEmbeddedAgentOpener` HTTP-клиент бросает на любой запрос; у `localEmbeddedAgentOpener` в тесте передаётся `httpClient: MockClient(...)`.
- Настоящие `~/.codelab` и переменные процесса не читаются: открывателю передаётся свой `environment` с `CODELAB_HOME` во временном каталоге.
- Синхронизация — событиями (`Completer`, `agent.closed`, события транспорта, `TestAcpClient.frames`), а не `Future.delayed`.
- Каждый тест закрывает за собой: `client.close()`, `agent.dispose()`, удаление временного каталога (см. `setUp` и `tearDown` в `test/embedded_agent_test.dart`).
- Тесты процессов и файлов идут на Dart VM и входят в `melos run check`. Прогонов на устройстве в ветках `feature/*` и `hotfix/*` не нужно (корневой [`AGENTS.md`](../../../../AGENTS.md), §21).

## Карта тестов

| Файл | Что проверяет |
|---|---|
| `test/embedded_agent_test.dart` | ход сценарного агента (`hello` и `end_turn`), встроенные команды, локальное исполнение без `fs/*` и `terminal/*`, containment (`../x` и `cwd` вне проекта), разрешения (`reject_once`, `allow_once`), профили, идемпотентность `dispose`, сбой шага остановки (`embedded.agent.dispose_failed`, `closed` не зависает) |
| `test/lifecycle_test.dart` | жизненный цикл: `dispose` при ожидающем разрешении, закрытие клиентом своего конца во время хода, отказ агента: ошибка вне `Future` хода, ошибка `serve`, повторная ошибка (`embedded.agent.failed`, `late_error`) |
| `test/embedded_agent_version_test.dart` | `embeddedAgentVersion` равна `agentInfo.version` в ответе `initialize` |
| `test/embedded_mcp_status_test.dart` | `mcpStatus(sessionId)`: статус без промпта, сбой сервера, пустая и неизвестная сессия |
| `test/embedded_config_reload_test.dart` | правка `config.yaml` снаружи доходит до сессии, замена ключа в `secrets.yaml`, ссылка вне `.codelab`, закрытие источника при срыве открытия |
| `test/secrets_in_config_test.dart` | признак `secretsInConfig` и мигратор через `io.dart` |
| `test/fake_mcp_http_host_test.dart` | `FakeMcpHttpHost`: loopback, `Authorization` вне журнала, освобождение порта; агент с сервером в `mcp.servers` |
| `test/web_smoke_test.dart` | то же, что компилирует `web-compile`, на Dart VM: основной барель собирает агента в памяти и закрывает его |
| `test/io/local_opener_test.dart` | настольный открыватель: ключ из `secrets.yaml` и `CODELAB_SECRET_*`, невалидная конфигурация, конфигурация папки сессии, журнал JSONL, владение HTTP-клиентом, MCP из переданного окружения, чужой профиль |
| `test/io/local_opener_skills_test.dart`, `test/io/scripted_opener_skills_test.dart` | навыки: чтение файла навыка, запись в каталог навыка запрещена, скрипт навыка, PERM-11 |
| `test/io/last_model_memory_test.dart` | память последней модели: у настольного открывателя есть, у сценарного нет |
| `test/io/test_secret_store_process_test.dart` | `CODELAB_TEST_SECRET_STORE` действует только в сборке с `-DCODELAB_ALLOW_TEST_SECRETS=true` (отдельный процесс, зонд `test/io/support/secret_store_probe.dart`) |

## Помощники в `test/support/`

| Файл | Для чего |
|---|---|
| `acp_client.dart` | `TestAcpClient`: `call`, `initialize`, `newSession`, `prompt`; `handlers` — ответы на запросы агента клиенту (`session/request_permission`); `received`, `updates`, `agentText`, `agentRequests`, `lastUpdateOf(toolCallId)`, `frames` |
| `memory_host.dart` | `memoryConfig` и `memoryServices`: сборка агента над памятью, без файловой системы, `createEmbeddedAgent` напрямую |
| `openai_script.dart` | `OpenAiStep` и поддельный провайдер (OpenAI chat completions, SSE) для тестов `localEmbeddedAgentOpener` |
| `fake_mcp_stdio_server.dart` | процесс stdio-сервера MCP для тестов остановки процессов |
| `package_dir.dart` | корень пакета и исполняемый `dart` для процессных тестов (под `flutter test` `Platform.resolvedExecutable` — не `dart`) |

## Какой открыватель брать

| Что проверяю | Открыватель |
|---|---|
| поведение агента на ходе: инструменты, разрешения, команды, жизненный цикл | `scriptedEmbeddedAgentOpener` |
| загрузку конфигурации, секреты, журнал, перезагрузку, файлы проекта | `localEmbeddedAgentOpener` с временным `CODELAB_HOME` и `MockClient` |
| сборку `createEmbeddedAgent` без файловой системы (так компилируется web) | `createEmbeddedAgent` с `memoryConfig` и `memoryServices` |
| отказ `serve` или шаг остановки | сборку с подменой — см. `test/lifecycle_test.dart` (`group('failure of the agent')`): ей нужны `assembleEmbeddedAgent` из `lib/src/assemble.dart` и параметр `serve` |

Параметр `serve` у `assembleEmbeddedAgent` — тестовый шов: он запускает обслуживание соединения вместо `AcpAgentServer.serve`, чтобы воспроизвести ошибку, которую настоящий сервер извне не вызвать. Хосты его не задают. Из-за него `lifecycle_test.dart` импортирует `package:codelab_embedded/src/assemble.dart` напрямую — единственное исключение из правила «публичный API через барель».

## Рецепты

Каждый рецепт ссылается на реальный код и тест. Скелеты с `...` сокращены намеренно, остальные проверены `fvm dart analyze` и `fvm dart test`. Перед правкой прочитайте [`AGENTS.md`](../AGENTS.md) пакета: изменение поведения, ACP-контрактов или публичного API начинается с OpenSpec change (корневой `AGENTS.md`, §17).

### Написать тест встроенного агента

Задача: проверить, что агент делает с запросом клиента. Берите `scriptedEmbeddedAgentOpener` и `TestAcpClient`. Пример: модель просит записать файл, клиент отказывает, файла нет.

```dart
import 'dart:io';

import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import 'support/acp_client.dart';

void main() {
  late Directory temp;
  late Directory project;
  late RecordingLogger logger;
  EmbeddedAgent? agent;
  TestAcpClient? client;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('codelab_embedded_');
    project = Directory('${temp.path}/project')..createSync();
    logger = RecordingLogger();
  });

  tearDown(() async {
    await client?.close();
    await agent?.dispose();
    agent = client = null;
    temp.deleteSync(recursive: true);
  });

  test('запись файла: клиент отказал, файла нет', () async {
    final opener = scriptedEmbeddedAgentOpener(
      llm: {
        'steps': [
          {
            'reply': [
              {
                'toolCall': {
                  'id': 'call_w',
                  'name': 'write',
                  'arguments': {'path': 'new.txt', 'content': 'x'},
                },
              },
            ],
          },
          {
            'reply': [
              {'text': 'понял'},
            ],
          },
        ],
      },
      codelabHome: '${temp.path}/home',
      logger: logger,
    );
    agent = await opener(cwd: project.path, hostProfile: 'embedded-cli');
    client = TestAcpClient(agent!.clientTransport);
    await client!.start();
    await client!.initialize();
    final sessionId = await client!.newSession(project.path);
    client!.handlers['session/request_permission'] = (_) => {
      'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
    };

    final stop = await client!.prompt(sessionId, 'создай new.txt');

    expect(stop, 'end_turn');
    expect(File('${project.path}/new.txt').existsSync(), isFalse);
    expect(client!.agentRequests, ['session/request_permission']);
  });
}
```

Что в этом тесте важно:

- Шаги сценария — блок `llm` фикстур; `steps[].reply` содержит `text` или `toolCall`. Формат сценария — в [главе о тестировании ядра](../../codelab_agent_core/doc/12-testing.md).
- Разрешение запрашивается у клиента: без обработчика `session/request_permission` агент получит от `TestAcpClient` ошибку «метод не найден». Режим разрешений задаётся параметром `permissionMode` открывателя (`bypass` — без вопросов).
- Тест проверяет и обратное: `agentRequests` не содержит `fs/*` и `terminal/*` у профилей `embedded-*` (так проверяет `test/embedded_agent_test.dart`, группа `local execution`).
- Файлы в `test/` называйте по теме требования, а имя теста — по сценарию спецификации.

### Собрать агента над памятью

Задача: проверить сборку без файловой системы и без открывателя: так основной барель собирается для web. В `test/support/memory_host.dart` уже есть `memoryConfig` (профиль `embedded-cli`, модель `p/m`, без `exec` и журнала на диск) и `memoryServices` (всё над памятью, часы и идентификаторы детерминированные).

```dart
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/acp_client.dart';
import 'support/memory_host.dart';

void main() {
  test('агент в памяти: createEmbeddedAgent без файловой системы', () async {
    final logger = RecordingLogger();
    final agent = await createEmbeddedAgent(
      config: memoryConfig(),
      services: memoryServices(
        logger,
        MockClient((_) async => throw StateError('нет сети')),
      ),
    );
    final client = TestAcpClient(agent.clientTransport);
    await client.start();

    final init = await client.initialize();

    expect((init['agentInfo']! as Map)['name'], 'codelab-agent');
    await client.close();
    await agent.dispose();
    await agent.closed;
    expect(logger.eventsOf('host.plan'), hasLength(1));
  });
}
```

Чужой профиль (`memoryConfig(profile: 'agent-serve')`) даёт `HostWiringException` через `Future`, а не синхронно: ошибку ловит `expectLater(..., throwsA(...))`.

### Воспроизвести отказ агента

Задача: проверить поведение при необработанной ошибке. Настоящий сервер ошибку `serve` извне не вызвать, поэтому тесту нужен внутренний `assembleEmbeddedAgent` с параметром `serve`. Это единственное место, где тест импортирует `package:codelab_embedded/src/assemble.dart`.

```dart
import 'dart:async';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/testing.dart';
import 'package:codelab_embedded/codelab_embedded.dart';
import 'package:codelab_embedded/src/assemble.dart';
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'support/memory_host.dart';

void main() {
  test('ошибка serve: агент закрывает конец пары и пишет событие', () async {
    final logger = RecordingLogger();
    final script = LlmScript.fromJson(
      {'steps': <Object?>[]},
      models: const [],
      clock: FakeClock(),
      cwdOf: (_) => null,
    );
    final leaked = <Object>[];
    late EmbeddedAgent agent;
    // «Зона приложения»: всё, что в неё дошло, — ошибка, просочившаяся наружу.
    await runZonedGuarded(() async {
      agent = await assembleEmbeddedAgent(
        config: memoryConfig(model: script.models.first),
        services: memoryServices(
          logger,
          MockClient((_) async => throw StateError('нет сети')),
        ),
        models: FixedModelCatalog(script.models),
        streamFunction: script.function.call,
        serve: (server, transport) async => throw StateError('boom'),
      );
      await agent.closed;
    }, (error, _) => leaked.add(error));

    expect(leaked, isEmpty);
    expect(agent.clientTransport.state, AcpTransportState.failed);
    expect(logger.eventsOf('embedded.agent.failed').single.fields, {
      'error_class': 'StateError',
    });
  });
}
```

Что проверяет тест: ошибка не дошла до зоны приложения (`leaked` пуст), клиентский конец перешёл в `failed`, в лог попал только класс ошибки. Полные варианты (ошибка вне `Future` хода, вторая ошибка как `late_error`) — в группе `failure of the agent` файла `test/lifecycle_test.dart`.

### Добавить порт хоста

Задача: ядру понадобился новый порт (хранилище, загрузчик, источник), и встроенный агент должен его получить. Пример — память последней выбранной модели `lastModel`: она проходит через те же три места, что любой новый порт.

1. Порт и поле в `AgentCoreServices` добавляет ядро — [глава 2 руководства по ядру](../../codelab_agent_core/doc/02-assembly-and-hosts.md). Мост получает готовый тип порта.
2. Поле в `EmbeddedHostServices` (`lib/src/embedded_agent_config.dart`). Необязательное поле с doc-комментарием «почему, для чего, как использовать». Тип берётся из ядра: основной барель обязан остаться web-безопасным, поэтому в поле не может стоять класс `dart:io`.

   ```dart
   const EmbeddedHostServices({
     ...
     this.lastModel,
   });

   /// Память последней выбранной модели; `null` — у сценарного открывателя.
   final LastModelStore? lastModel;
   ```

3. Передача ядру в `assembleEmbeddedAgent` (`lib/src/assemble.dart`): одна строка в `AgentCoreServices(...)`.

   ```dart
   services: AgentCoreServices(
     ...
     lastModel: services.lastModel,
   ),
   ```

4. Реализация в `localEmbeddedAgentOpener` (`lib/src/io/local_opener.dart`): здесь живёт всё, что использует `dart:io` и `codelab_agent_io`.

   ```dart
   lastModel: FileLastModelStore(codelabHome: home, logger: logger),
   ```

5. Решение для сценарного открывателя (`lib/src/testing/scripted_opener.dart`): поле остаётся `null` или получает детерминированную реализацию. Сценарий не должен зависеть от файлов разработчика. Для `lastModel` — `null`, и тест `test/io/last_model_memory_test.dart` проверяет оба поведения.
6. Тест: красный тест по критерию спецификации — до кода. Проверьте и настольный открыватель (`test/io/local_opener_test.dart` или отдельный файл в `test/io/`), и отсутствие порта у сценарного.
7. Прогон: `fvm dart test`, `melos run guard`, `melos run conformance:embedded`. Если поле принадлежит основному барелю и меняет его импорты — ещё `melos run web-compile`.
8. Документация: README пакета и эту главу, если изменилась таблица открывателей в [устройстве](00-architecture-and-debugging.md#два-открывателя).

Что нельзя: добавлять условие на новую возможность внутри `assembleEmbeddedAgent` (правило пакета — расширение встаёт в `EmbeddedHostServices`, профиль или открыватель, а не в условие сборки); создавать `ToolRegistry(`, `Agent(`, `AgentRuntime(` (HOST-6, `host_assembly_guard_test.dart`); создавать `http.Client`, `Clock`, `Random`, `IdGenerator` в основном барели (PKG-6).

### Добавить вызов из клиента

Задача: клиент должен получить встроенного агента. Клиентские приложения уже делают это; рецепт нужен, если появляется новый клиент или composition root.

1. Только в composition root: `package:codelab_embedded/io.dart` (сейчас это `apps/codelab_cli/lib/src/composition_root.dart` и `apps/codelab_desktop/lib/app/`). Правила сторожа в `rules.dart` разрешают импорт только им, поэтому новый composition root — отдельное решение с правкой правил (корневой `AGENTS.md`, §5).
2. Создайте открыватель один раз: `localEmbeddedAgentOpener(environment: ..., logger: ...)`. `environment` — окружение процесса (`CODELAB_HOME`, `CODELAB_SECRET_*`, `CODELAB_CONFIG`); `logger` — адаптер журнала клиента (`CliEmbeddedLogger` в CLI, `CodeLabEmbeddedLogger` в приложении).
3. Отдайте открыватель резолверу транспорта. Резолвер клиента сериализует вызовы: следующий `open` ждёт, пока прежний агент освободится; открытие в полёте при новом `open` или `close()` становится устаревшим, и вернувшийся позже агент сразу освобождается (`EmbeddedOpenCancelledException`). Реализация — `apps/codelab_cli/lib/src/embedded_transport_resolver.dart`; у приложения своя копия, правка в одной требует парной правки в другой.
4. Освобождайте агента: `await agent.dispose()` при смене проекта и выходе. Если клиент закрыл свой конец, агент остановится сам, но `dispose` дописывает журнал сессий и закрывает MCP-процессы.
5. Дайте тестам шов: параметр `embeddedOpener`, который по умолчанию равен `localEmbeddedAgentOpener`. Так тест подставляет `scriptedEmbeddedAgentOpener`, не импортируя `testing.dart` в рабочий код (пример — `apps/codelab_cli/test/e2e/support/embedded_cli_main.dart`: `runCodelab(args, environment: environment, embeddedOpener: opener)`).

Ошибки открытия, которые клиент обязан показать пользователю: `EmbeddedAgentConfigException` (текст в `message`, у CLI — stderr и код `64`, у приложения — баннер соединения) и `HostWiringException` (ошибка проводки, не пользовательская).

## Частые проблемы

Формат: симптом, причина, что сделать. Тексты ошибок и события лога — из кода.

### Сборка и тесты

| Симптом | Причина | Что сделать |
|---|---|---|
| `fvm dart test` не загружает файлы: `The getter 'meta' isn't defined for the type 'ClientCapabilities'` и подобные ошибки в `codelab_agent_acp` | не сгенерирован код (`*.freezed.dart`) в `codelab_acp_protocol` | выполнить генерацию из [запуска из исходников](../../../../docs/user/run-from-source.md#1-подготовка); дождаться конца: тесты, запущенные во время генерации, могут падать |
| процессный тест (`test/io/test_secret_store_process_test.dart`, MCP-тесты в `lifecycle_test.dart`) зависает или не находит `dart` | под `flutter test` `Platform.resolvedExecutable` — не `dart` | брать `dartExecutable()` из `test/support/package_dir.dart` |
| тест висит на `await agent.closed` | агент не получил повода остановиться: клиент не закрыл свой конец и никто не вызвал `dispose()` | вызвать `dispose()` или закрыть клиента; в `tearDown` всегда `agent?.dispose()` |
| ход в тесте не выполняет инструмент, который требует разрешения; среди кадров `session/request_permission`, ответ клиента — ошибка `-32601` | у `TestAcpClient` нет обработчика запроса агента: без него он отвечает ошибкой `no handler`, и агент не получает решения | задать `client.handlers['session/request_permission']` или режим `permissionMode: 'bypass'` открывателя |
| `StateError: the scripted agent has no network` | у сценарного открывателя HTTP-клиент — `MockClient`, который бросает на любой запрос; что-то пошло по HTTP (запрос провайдера или HTTP-сервер MCP) | модель у сценарного агента идёт по `steps`, сети нет; для HTTP-сервера MCP поднимите `FakeMcpHttpHost` и пропишите его `url` в `mcp.servers` конфигурации настольного открывателя |
| после теста остались процессы MCP или занят порт | не вызван `dispose()` агента или `close()` у `FakeMcpHttpHost` | закрывать в `tearDown`; проверка остановки процесса — в `lifecycle_test.dart` (`_alive(pid)`) |
| `StateError: the ACP server asks through AcpPermissionGate` | кто-то вызвал заглушку `_ConnectionGate.request`: ядро спрашивало разрешение, минуя ACP-сервер | агента нужно открывать через `createEmbeddedAgent` или открыватель: они ставят `AcpPermissionGate` соединения сессии; собственный `PermissionGate` мост не принимает |

### Открытие агента

| Симптом | Причина | Что сделать |
|---|---|---|
| `HostWiringException: createEmbeddedAgent accepts profiles embedded-app-desktop, embedded-cli, not agent-serve` | основной барель и `io.dart` принимают только профили `embedded-*` (`lib/src/create_embedded_agent.dart`) | для `agent-serve` и режима разрешений в тестах — `scriptedEmbeddedAgentOpener`; для настольного хоста — профиль `embedded-cli` или `embedded-app-desktop` |
| `EmbeddedAgentConfigException`: `defaults: agent.default_model: no model is configured; add a provider with at least one model` и подсказка `Configure the embedded agent in ~/.codelab/config.yaml; check it with: codelab config check` | в слоях нет провайдера и модели по умолчанию | добавить провайдера ([настройка агента](../../../../docs/user/configuration.md)); проверить `codelab config check` |
| `EmbeddedAgentConfigException`: `CODELAB_HOME: CODELAB_HOME: ~user is not supported, use an absolute path` | в `CODELAB_HOME` форма `~user/...` | указать абсолютный путь или `~` без имени пользователя |
| конфигурация валидна, но первый ход падает с ошибкой провайдера, где названо имя секрета | нет ключа провайдера: это не ошибка открытия (`lib/src/io/local_opener.dart`) | задать ключ: `codelab-agent secret set <имя>`, `CODELAB_SECRET_<ИМЯ>` или `api_key_env` |
| `EmbeddedAgentConfigException` с ключом `secrets.backend` | выбранное хранилище секретов недоступно (например, `keychain` в этой версии не поддерживается) | выбрать `env` или `file` в `secrets.backend` |
| переменная `CODELAB_TEST_SECRET_STORE` не действует и даёт `config.env.unknown` | она читается только в сборке с `-DCODELAB_ALLOW_TEST_SECRETS=true` | запускать с флагом сборки; в релизной сборке так и задумано |
| после правки `config.yaml` новая модель или провайдер не видны сессии | у сценарного открывателя перезагрузки нет; у настольного работает наблюдатель, но `config.watch: false` её отключает | у сценарного — открыть агента заново; у настольного — проверить `config.watch` |
| сессия другой папки получила конфигурацию не той папки | конфигурацию папки сессии читает `FileConfigSource` (`projectConfig`); у сценарного открывателя этого порта нет | в тесте проверять через `localEmbeddedAgentOpener`; у сценарного конфиг чужой папки не читается (`test/embedded_agent_test.dart`, тест `the scripted opener passes no ProjectConfigLoader: a broken project config of another folder does not refuse the session`) |
| `session/new` в папке с битым `.codelab/config.yaml` отклонён (ошибка `-32603` с путём файла и ключом, в логе `config.session.project_invalid`) | конфигурация папки сессии невалидна: настольный открыватель не создаёт сессию без неё | исправить файл, `codelab config check --cwd <папка>` (проверяет `test/io/local_opener_test.dart`, группа `config of the folder of a session`) |

### Поведение работающего агента

| Симптом | Причина | Что сделать |
|---|---|---|
| клиент показывает потерю соединения (`ConnectionLost`), в логе `embedded.agent.failed {error_class: …}` | необработанная ошибка в зоне агента или ошибка `serve`: агент остановлен намеренно, как умирающий процесс | по `error_class` найти тип; текста ошибки в записи нет умышленно (может содержать путь или ответ провайдера). Воспроизвести тестом по [рецепту](#воспроизвести-отказ-агента), добавить `Timer.run(() => throw ...)` в обёртку модели |
| в логе `embedded.agent.late_error` | вторая ошибка пришла, когда агент уже останавливался | обычно следствие первой: смотрите предшествующий `embedded.agent.failed` |
| в логе `embedded.agent.dispose_failed {step: …}` | шаг остановки бросил исключение; остальные шаги выполнились, `closed` завершён | `step` называет ресурс: `shutdown`, `runtime`, `config_source`, `link`, `http`; ищите причину в соответствующем порту |
| `dispose()` занимает до пяти секунд | `AcpAgentServer.shutdown(grace: 5 с)` ждёт отмены ходов | если ход зависает, проверьте отмену в инструменте; в тесте с ожидающим разрешением `dispose` сам отменяет ход |
| клиент не получает `fs/*` и `terminal/*` запросов | у профилей `embedded-*` файлы и команды исполняет хост (`AcpServerConfig.localEnv`); это не дефект | чтобы проверить путь через клиента, нужен профиль `agent-serve` и `scriptedEmbeddedAgentOpener` |
| путь вне проекта: инструмент вернул `Path is outside the workspace` | `BoundedEnv` ядра отклонил выход за корень сессии (`FileErrorCode.outsideWorkspace`) | так и задумано; ход продолжается, ошибка — результат для модели |
| кнопка «Перенести секреты» не пропала после переноса | `secretsInConfig` вычисляется один раз при открытии | переподключить агента: признак обновится |
| `mcpStatus(sessionId)` вернул `null` | сессия неизвестна или уже закрыта | брать порт у открытой сессии; без MCP-серверов порт есть, его `servers` пуст |

### Границы и сторож

| Симптом | Причина | Что сделать |
|---|---|---|
| `melos run guard` красный после нового импорта | основной барель или файл вне `io`/`testing` тянет `dart:io`, `codelab_agent_io`, `testing.dart` или `io.dart`; либо клиент импортирует `io.dart` вне composition root | прочитать сообщение сторожа: оно называет файл, строку и правило; перенести код в `lib/src/io/` или `lib/src/testing/`, либо убрать импорт |
| `melos run web-compile` красный | основной барель стал зависеть от того, что не компилируется в JavaScript и WebAssembly | убрать зависимость; тип из `dart:io` заменить портом ядра (как `closeConfigSource` вместо `FileConfigSource`) |
| `pubspec_allowlist_test.dart` красный | в `dependencies` пакета появилась зависимость вне `embeddedAllowlist` | убрать её; расширение allowlist — только через OpenSpec change |
| `host_assembly_guard_test.dart` красный | в `lib/` появилось `ToolRegistry(`, `Agent(` или `AgentRuntime(` | собирать ядро только через `buildAgentCore` (HOST-6) |
| `embedded_agent_version_test.dart` красный | `embeddedAgentVersion` разошлась с `agentInfo.version` | значение одно на `lib/src/assemble.dart`; парная константа бинаря `agentVersion` в `apps/codelab_agent/lib/src/host/agent_host.dart` — держать равными |
| `conformance:embedded`: фикстура падает у встроенного агента, но проходит у бинаря | расхождение в проводке хостов: у них она продублирована осознанно (MCP-коннектор, `agentInfo`, профиль) | сравнить `lib/src/testing/scripted_opener.dart` и `apps/codelab_agent/lib/src/host/agent_host.dart`; пример: без MCP-коннектора пропадает `mcpCapabilities.http` |

### Производительность

| Симптом | Причина | Что сделать |
|---|---|---|
| бенчмарк на `dart run` показывает p99 больше 8 мс | JIT медленнее AOT; критерий — по сборке AOT (D13, п. 3 в [`design.md`](../../../../openspec/changes/archive/2026-11-02-add-embedded-agent-mode/design.md)) | собрать `dart compile exe` и повторить; режим `sse` с клиентом — [бенчмарк](00-architecture-and-debugging.md#бенчмарк-задержки-потока) |
| интерфейс «подвисает» на длинном ответе | ядро и UI делят один isolate; тяжёлая работа идёт в нём | замерить бенчмарком; решение о переносе ядра в `IsolateAcpLink` принимается по числам (D11, D13 в [`design.md`](../../../../openspec/changes/archive/2026-11-02-add-embedded-agent-mode/design.md)) |

## Смотрите также

- [Устройство и отладка](00-architecture-and-debugging.md);
- [тестирование ядра](../../codelab_agent_core/doc/12-testing.md), [рецепты расширения ядра](../../codelab_agent_core/doc/11-extending.md) и [частые проблемы ядра](../../codelab_agent_core/doc/13-troubleshooting.md);
- [`AGENTS.md`](../AGENTS.md) пакета.
