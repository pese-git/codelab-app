// Переключение профилей с участием встроенного агента (REPL `/profile`,
// `reconnect`; design.md change `add-embedded-agent-mode`, D6; AGENTS.md §9:
// поздние события старого соединения не меняют актуальное).
//
// Резолвер освобождает прежнего агента (`dispose`), пока прежний транспорт ещё
// у `AcpClientApplication`; закрытие старого транспорта не должно
// переводить новое соединение в `disconnected` или `failed`.

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_cli/src/composition_root.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_embedded/codelab_embedded.dart' show EmbeddedAgent;
import 'package:codelab_embedded/testing.dart';
import 'package:test/test.dart';

import 'support/cli_process.dart';

const _script = {
  'model': {
    'provider': 'scripted',
    'modelId': 'scripted-1',
    'contextWindow': 32768,
  },
  'steps': <Object?>[],
};

/// Пропускает очередь событий, чтобы доставились уже стоящие в ней сообщения.
Future<void> _pump() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late Directory tmp;
  late CliRuntime runtime;
  late List<ConnectionView> seen;
  late List<EmbeddedAgent> agents;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('codelab_switch_');
    agents = [];
    final scripted = scriptedEmbeddedAgentOpener(
      llm: _script,
      codelabHome: '${tmp.path}/home',
      logger: const CliEmbeddedLogger.silent(),
      sessionsDir: '${tmp.path}/sessions',
    );
    runtime = buildCliRuntime(
      environment: {'CODELAB_HOME': '${tmp.path}/home'},
      stderr: StringBuffer(),
      verbose: false,
      embeddedOpener: ({required cwd, required hostProfile}) async {
        final agent = await scripted(cwd: cwd, hostProfile: hostProfile);
        agents.add(agent);
        return agent;
      },
    );
    seen = [];
    runtime.workspace.state.listen((state) => seen.add(state.connection));
  });
  tearDown(() async {
    await runtime.dispose();
    tmp.deleteSync(recursive: true);
  });

  Future<void> expectUsable({EmbeddedAgent? replaced}) async {
    // Достаточно живого соединения: сессия создаётся, а состояние не
    // откатилось в `disconnected` или `failed`.
    final session = await runtime.workspace.newSession();
    expect(session.id.value, isNotEmpty);
    // Поздние события старого транспорта: ждём, пока прежний агент закрыт
    // (после `dispose` резолвера), и пропускаем очередь событий.
    await replaced?.closed;
    await _pump();
    expect(runtime.workspace.current.connection, isA<Connected>());
  }

  test('/profile embedded twice in a row: the second agent replaces the '
      'first, the connection stays Connected', () async {
    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );

    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );

    expect(agents, hasLength(2));
    await expectUsable(replaced: agents.first);
    expect(seen.last, isA<Connected>());
  });

  test('embedded then a stdio agent: the old agent is disposed, the new '
      'connection is not hit by its closing', () async {
    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );
    final stdio = inlineAgentProfile(await scriptedAgent(tmp), id: 'stdio');

    await runtime.workspace.connect(stdio!, projectDirectory: tmp.path);

    await expectUsable(replaced: agents.first);
  });

  test('stdio then embedded', () async {
    final stdio = inlineAgentProfile(await scriptedAgent(tmp), id: 'stdio');
    await runtime.workspace.connect(stdio!, projectDirectory: tmp.path);

    await runtime.workspace.connect(
      embeddedCliProfile,
      projectDirectory: tmp.path,
    );

    await expectUsable();
  });
}
