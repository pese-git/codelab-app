# `codelab-agent`: тестирование

Уровни тестов и golden-фикстуры ACP описаны в [главе 12 руководства по ядру](../../../packages/dart/codelab_agent_core/doc/12-testing.md). Здесь — что есть у бинаря: какие тесты, как запустить процесс, как поднять хост в тесте и что прогонять при правках.

## Правила

- Красный тест по критерию спецификации пишется до кода (TDD, [`AGENTS.md`](../AGENTS.md) приложения, §3, и ядра, §2). Сценарии тестов называют требования [`agent-binary`](../../../openspec/specs/agent-binary/spec.md): «Команда serve», «Конфиг бинаря из файлов, окружения и флагов», «Логи бинаря», «Жизненный цикл процесса».
- Живого провайдера и сети нет. Модель — сценарий (`--llm-script`, файлы в `test/llm_scripts/`) или локальный HTTP-сервер самого теста с ключом из `CODELAB_SECRET_*` (`secret_store_process_test.dart`).
- `CODELAB_HOME` — временный каталог теста. Настоящие `~/.codelab` и ключи разработчика не читаются: процесс получает окружение только из теста.
- Значения секретов в тестах только тестовые. Тест, который проверяет утечки, ищет значение во всём stdout, stderr и логе.
- Процессные тесты запускают настоящий бинарь (kernel), поэтому они входят в `fvm dart test` приложения и в `melos run check`; прогонов на устройстве в ветках `feature/*` и `hotfix/*` не нужно (корневой [`AGENTS.md`](../../../AGENTS.md), §21).

## Запуск

```bash
cd apps/codelab_agent
fvm dart test
```

Один файл:

```bash
fvm dart test test/serve_flags_test.dart
fvm dart test test/stdio_process_test.dart --name "hello"
```

Скрипты Melos, которые затрагивают приложение (из корня репозитория):

| Скрипт | Что проверяет | Когда нужен |
|---|---|---|
| `fvm dart run melos run guard` | границы: нет `package:flutter/`, `package:fluent_ui/`, `package:codelab_client_acp/` и `package:codelab_ui/` в `lib/` и `bin/`, нет `ToolRegistry(`, `Agent(`, `AgentRuntime(`, `dependencies` в allowlist | изменились импорты, `pubspec.yaml`, файлы в `lib/` |
| `fvm dart run melos run test:e2e:cli:dart-agent` | сквозные тесты `codelab` (через PTY) против `codelab-agent` с `--llm-script`; ядро компилируется самим тестом | изменились `apps/codelab_cli`, `apps/codelab_agent` или клиентский слой между ними |
| `fvm dart run melos run conformance:agent` | корпус ACP-фикстур против `AcpAgentServer` (пакет `codelab_agent_acp`) | изменилась ACP-проекция или фикстуры; сам бинарь корпус не проигрывает, кроме транспортных фикстур |

Транспортные фикстуры корпуса (кадрирование stdio, Bearer для WebSocket) проигрывает против процесса бинаря `test/transport_conformance_test.dart`.

Запуск одного файла e2e против бинаря, из корня репозитория:

```bash
CODELAB_E2E_AGENT=dart fvm dart test apps/codelab_cli/test/e2e/headless_print_basic_test.dart --exclude-tags scripted-only
```

Тег `python-agent` объявлен в `apps/codelab_cli/dart_test.yaml`; при запуске из корня репозитория этот файл не читается, поэтому `dart test` печатает предупреждение. Оно ожидаемо.

## Карта тестов

Названия файлов говорят, что они проверяют; справка по группам:

| Группа | Файлы | Что проверяют |
|---|---|---|
| разбор флагов | `serve_flags_test.dart` | `parseServeArgs`: транспорт, модели, `--config`, `--max-steps`, режим, лог, `CODELAB_HOME`, предконфигурация провайдера; справка скрывает `--llm-script` и `--sessions-dir` |
| хост в процессе теста | `agent_host_test.dart`, `agent_host_config_test.dart`, `agent_host_project_config_test.dart`, `agent_host_project_files_test.dart`, `agent_host_secrets_test.dart`, `agent_host_skills_test.dart`, `agent_host_skill_files_test.dart`, `agent_host_ws_commands_test.dart` | `AgentHost.build` над `InProcessAcpLink`: сценарий, провайдеры из конфигурации, слои проекта, файлы проекта, секреты, навыки, команды `--ws` |
| процесс `serve` | `stdio_process_test.dart`, `ws_auth_test.dart`, `stdio_profile_boundary_test.dart`, `transport_conformance_test.dart` | настоящий бинарь по stdio и WebSocket: кадры, коды выхода, сигналы, Bearer, граница «описание stdio-агента — бинарь» |
| конфигурация и перезагрузка | `config_command_process_test.dart`, `config_invalid_process_test.dart`, `config_reload_process_test.dart`, `config_untrusted_project_process_test.dart`, `config_mcp_servers_test.dart`, `config_mcp_ws_test.dart`, `optional_default_model_process_test.dart`, `project_files_process_test.dart` | `config check`, невалидная конфигурация (`64`), правка файла у работающего процесса, недоверенный проект, MCP из конфигурации, модель без `default_model`, файлы проекта |
| подкоманды записи и секреты | `config_write_command_process_test.dart`, `provider_preconfig_process_test.dart`, `secret_command_process_test.dart`, `secret_store_process_test.dart`, `secret_migrate_process_test.dart`, `mcp_add_stdin_process_test.dart` | `config set\|unset`, `provider`, `mcp add`, `secret set\|delete\|list\|migrate`, ключ из хранилища; значение секрета не попадает в вывод |
| MCP | `mcp_stdio_process_test.dart`, `mcp_reconnect_process_test.dart` | настоящий stdio-сервер MCP, переподключение после падения сервера |
| логи и сценарии | `log_sinks_test.dart`, `llm_scripts_load_test.dart`, `config_run_test.dart` | приёмники лога, формат файла, сценарии e2e, неожиданное исключение в `config check` |

Что проверяет каждое требование, можно найти по имени сценария в заголовке файла: первый doc-комментарий называет спецификацию и `design.md` change.

## Помощники в `test/support/`

| Файл | Для чего |
|---|---|
| `agent_process.dart` | `AgentProcess`: запуск бинаря как процесса. Один раз на изолят компилируется kernel в `apps/codelab_agent/.dart_tool/codelab_test_kernels/codelab_agent.dill` и запускается `dart <файл>.dill` — тот же код, но быстрее `dart run`. Методы: `sendLine`, `sendJson`, `responseTo(id)`, `nextStdoutLine`, `stderrContains(текст)`, `closeStdin`, `kill`, `exitCode`; `stderrText` и `stdoutText` — всё накопленное |
| `build_host.dart` | `buildHost(options, cwd:, logger:)` — `AgentHost.build` с конфигурацией, загруженной для временного `cwd` (тест не читает `.codelab/` своего каталога) |
| `acp_peer.dart` | `AcpPeer`: клиентская сторона ACP над `InProcessAcpLink`: `call`, `openSession`, `newSession`, `prompt`, `agentText`, `notifications`. Запросы агента клиенту (`fs/*`, `terminal/*`) он не обслуживает |
| `client_acp_peer.dart` | `ClientAcpPeer`: клиентская сторона, которая обслуживает запросы агента (`fs/*`, `terminal/*`, `session/request_permission`) через `handlers` по имени метода; `requests` хранит запросы агента в порядке прихода |
| `transport_starter.dart` | `connectAgentProcess`: подключает транспортный драйвер фикстур к процессу бинаря (stdio и WebSocket, токен фикстуры) |
| `skills_rig.dart` | `SkillsRig`: временные `CODELAB_HOME`, домашний каталог пользователя и папка проекта, хост с моделью-сценарием и ACP-клиент; шаги сценария `callJson` и `textJson` |
| `fake_mcp_stdio_server.dart`, `fake_mcp_crashing_server.dart` | процессы stdio-серверов MCP: обычный и падающий |

## Сценарий модели для теста

Файл сценария — JSON с блоком `llm`. Минимальный `test/llm_scripts/hello.json` (отвечает текстом `hello` и завершает ход):

```json
{
  "llm": {
    "model": { "provider": "scripted", "modelId": "scripted-1", "contextWindow": 32768 },
    "steps": [
      { "reply": [ { "text": "hello" } ], "stopReason": "stop" }
    ]
  }
}
```

Формат шагов и вызовов инструментов — [глава о тестировании ядра](../../../packages/dart/codelab_agent_core/doc/12-testing.md). Тест, которому нужен свой сценарий, пишет файл во временный каталог и передаёт путь `--llm-script` (`writeScript` в `agent_host_test.dart`). `--sessions-dir <каталог>` включает журнал сессий сценария на диске: без него сессии в памяти, а агент не объявляет `loadSession`.

## Рецепты тестов

Процессный тест и тест хоста проверены `fvm dart analyze` и `fvm dart test`. Корень каталога тестов — `apps/codelab_agent/test/`, помощники берутся из `support/`.

### Процессный тест

Запускает бинарь, говорит с ним по stdio и проверяет код выхода и stderr. Закрытие stdin — штатное завершение: код `0`.

```dart
import 'dart:io';

import 'package:test/test.dart';

import 'support/agent_process.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_demo_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('stdio: initialize отвечает, закрытие stdin даёт код 0', () async {
    final agent = await AgentProcess.start(
      ['serve', '--stdio', '--llm-script', 'test/llm_scripts/hello.json'],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
    );
    agent.sendJson({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': 1,
        'clientCapabilities': <String, Object?>{},
      },
    });

    final response = await agent.responseTo(1);
    await agent.closeStdin();

    expect((response['result']! as Map)['protocolVersion'], 1);
    expect(await agent.exitCode, 0);
    expect(agent.stderrText, contains('serve.stdio.start'));
  });
}
```

`AgentProcess.start` заменяет окружение целиком (оставляя `PATH` и `HOME`), поэтому ключи разработчика процессу не видны; `CODELAB_HOME` задаёт тест. Путь сценария относителен каталогу приложения: `workingDirectory` по умолчанию — `apps/codelab_agent`, тест можно запускать и из корня репозитория.

### Тест хоста в процессе

Не запускает процесс: поднимает `AgentHost` на `InProcessAcpLink` и проверяет сборку. Быстрее процессного и позволяет читать `host.core`, `host.configSource` и записи лога.

```dart
import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'support/acp_peer.dart';
import 'support/build_host.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_host_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test('--ws сужает профиль: нет листинга файлов и MCP', () async {
    final script = File('${temp.path}/script.json')
      ..writeAsStringSync('{"llm": {"steps": []}}');
    final options = parseServeArgs(
      ['serve', '--ws', '--llm-script', script.path],
      environment: {'CODELAB_HOME': '${temp.path}/home'},
    );
    final logger = RecordingLogger();
    final host = await buildHost(options, cwd: temp.path, logger: logger);
    addTearDown(() => host.shutdown(grace: Duration.zero));

    final link = InProcessAcpLink();
    unawaited(host.createServer().serve(link.agent));
    await link.client.start();
    final peer = AcpPeer(link.client);
    final session = await peer.openSession(temp.path);

    final plan = logger.eventsOf('host.plan').single;
    expect(
      (plan.fields['off']! as Map).keys,
      containsAll(['fileListing', 'mcp']),
    );
    expect(plan.fields['profile'], 'agent-serve');
    expect(session, isNotEmpty);
    await peer.dispose();
  });
}
```

`buildHost` — помощник, а не часть барела: он нужен потому, что `AgentHost.build` требует готовый результат загрузки конфигурации, а тест не должен читать `.codelab/` каталога, из которого его запустили.

## Что прогонять при правке

| Правка | Что прогнать |
|---|---|
| флаг `serve` | `fvm dart test test/serve_flags_test.dart`, затем весь пакет |
| сборка хоста (`agent_host.dart`) | тесты `agent_host_*`, процессные тесты затронутого режима, `melos run guard` |
| транспорт, сигналы, коды выхода | `stdio_process_test.dart`, `ws_auth_test.dart`, `transport_conformance_test.dart` |
| подкоманда | процессный тест команды и тест разбора; проверка, что значение секрета не попало в вывод |
| логи | `log_sinks_test.dart`; в stdout не должно появиться ничего, кроме кадров ACP |
| путь, которым `codelab` работает с `codelab-agent` | `melos run test:e2e:cli:dart-agent` |

## Смотрите также

- [Тестирование ядра](../../../packages/dart/codelab_agent_core/doc/12-testing.md);
- [устройство бинаря](internals.md);
- [рецепты](recipes.md);
- [частые проблемы](troubleshooting.md).
