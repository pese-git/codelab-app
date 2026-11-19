// `startWithoutRestore()` и `restoreProject()`: взаимоисключение и повторные
// вызовы (задача 3.1 change `add-app-general-page`; spec acp-client-kit
// «Старт без восстановления рабочего пространства», D9).

import 'dart:convert';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/kit_agent.dart';

const _withLoad = AgentCapabilities(loadSession: true);

final _snapshot = jsonEncode({
  'version': 1,
  'windows': {
    'main': {
      'projectDirectory': '/work',
      'activeSessionId': 's-42',
      'openSessions': [
        {'id': 's-42', 'cwd': '/work'},
      ],
    },
  },
});

void main() {
  late KitAgent agent;
  late InMemoryWorkspaceSnapshotStore store;

  setUp(() {
    store = InMemoryWorkspaceSnapshotStore(_snapshot);
    agent = KitAgent(capabilities: _withLoad, snapshots: store);
  });
  tearDown(() => agent.dispose());

  List<String> sentMethods() => [
    for (final message in agent.transport.sentMessages)
      if (message is JsonRpcRequest) message.method,
  ];

  test('startWithoutRestore, затем restoreProject: проект не возвращается, '
      'снимок не восстанавливается', () async {
    agent.workspace.startWithoutRestore();

    expect(await agent.workspace.restoreProject(), isNull);
    await agent.start();

    expect(sentMethods(), [initializeMethod]);
    expect(agent.workspace.current.sessions, isEmpty);
  });

  test('restoreProject, затем startWithoutRestore: пустая операция, '
      'восстановление идёт', () async {
    expect(await agent.workspace.restoreProject(), '/work');
    agent.workspace.startWithoutRestore();

    final load = agent.next(sessionLoadMethod);
    final connecting = agent.start();
    agent.respond(await load, const <String, Object?>{});
    await connecting;

    expect(sentMethods(), [initializeMethod, sessionLoadMethod]);
    expect(agent.workspace.current.activeSessionId, const SessionId('s-42'));
  });

  test('повторный startWithoutRestore: пустая операция, снимок по-прежнему '
      'пишется', () async {
    agent.workspace.startWithoutRestore();
    agent.workspace.startWithoutRestore();
    agent.workspace.selectProject('/work/other');
    await agent.workspace.flushSnapshot();

    final saved = jsonDecode(store.value!) as Map<String, Object?>;
    final window = (saved['windows']! as Map)['main'] as Map;
    expect(window['projectDirectory'], '/work/other');
    expect(window['openSessions'], isEmpty);
  });

  test('повторный restoreProject после startWithoutRestore не оживляет '
      'снимок', () async {
    agent.workspace.startWithoutRestore();
    expect(await agent.workspace.restoreProject(), isNull);
    expect(await agent.workspace.restoreProject(), isNull);
    agent.workspace.selectProject('/work');
    await agent.start();

    expect(sentMethods(), [initializeMethod]);
  });

  test('повторный restoreProject не читает снимок второй раз и возвращает тот '
      'же проект', () async {
    final counting = _CountingStore(_snapshot);
    final other = KitAgent(capabilities: _withLoad, snapshots: counting);
    addTearDown(other.dispose);

    expect(await other.workspace.restoreProject(), '/work');
    // Снимок между вызовами меняется: второй вызов не должен его увидеть.
    counting.value = null;
    expect(await other.workspace.restoreProject(), '/work');

    expect(counting.reads, 1);
  });

  test('одновременные restoreProject читают снимок один раз', () async {
    final counting = _CountingStore(_snapshot);
    final other = KitAgent(capabilities: _withLoad, snapshots: counting);
    addTearDown(other.dispose);

    final results = await Future.wait([
      other.workspace.restoreProject(),
      other.workspace.restoreProject(),
    ]);

    expect(results, ['/work', '/work']);
    expect(counting.reads, 1);
  });
}

/// Хранилище, считающее чтения: «повторный вызов — пустая операция».
final class _CountingStore implements WorkspaceSnapshotStore {
  _CountingStore(this.value);

  String? value;
  var reads = 0;

  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String snapshot) async => value = snapshot;

  @override
  Future<void> clear() async => value = null;
}
