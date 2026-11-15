import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import 'journal_helpers.dart';

/// Лог `subagent.heal_failed` на настоящем файловом хранилище (design.md
/// change `add-subagents-and-tasks`, D46, п. 5): журнал потомка потерян —
/// корень открывается, а в логе нет ни пути журнала, ни текста исключения
/// (в `FileSystemException` и `SessionNotFound` путь есть).
void main() {
  test('журнал ребёнка в статусе running удалён: корень открывается, '
      'heal_failed без error и без пути журнала', () async {
    final root = tempRoot('jsonl_heal_', addTearDown);
    final cwd = tempRoot('jsonl_heal_cwd_', addTearDown);
    const id = '01JB8Q2W6R9T3M5K7N1P4X8Z0A';
    const kid = '01JB8Q3A1D2E3F4G5H6J7K8M9N';
    final store = storeAt(root);
    await store.create(headerOf(id, cwd: cwd));
    Future<void> put(Map<String, Object?> json) => store.append(
      const SessionId(id),
      SessionRecord.fromJson({
        'timestamp': '2026-10-21T08:00:00.000Z',
        ...json,
      }),
    );
    await put({
      'type': 'message',
      'id': 'aaaaaaaa',
      'parentId': null,
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': 'run'},
        ],
        'timestamp': '2026-10-21T08:00:00.000Z',
      },
    });
    await put({
      'type': 'message',
      'id': 'bbbbbbbb',
      'parentId': 'aaaaaaaa',
      'message': {
        'role': 'assistant',
        'content': [
          {
            'type': 'toolCall',
            'id': 'c1',
            'name': 'agent',
            'arguments': {'description': 'Kid job', 'prompt': 'kid'},
          },
        ],
        'model': {'provider': 'test', 'id': 'model-1'},
        'usage': {
          'input': 0,
          'output': 0,
          'cacheRead': 0,
          'cacheWrite': 0,
          'cost': {
            'input': 0.0,
            'output': 0.0,
            'cacheRead': 0.0,
            'cacheWrite': 0.0,
          },
        },
        'stopReason': 'toolUse',
        'timestamp': '2026-10-21T08:00:00.000Z',
      },
    });
    await put({
      'type': 'subagent',
      'id': 'cccccccc',
      'parentId': 'bbbbbbbb',
      'subagentId': 'sub_aaaaaaaa',
      'toolCallId': 'c1',
      'agent': 'general',
      'description': 'Kid job',
      'childSessionId': kid,
      'journal':
          '${cwdSlug(cwd)}/2026-10-21T08-00-00-000Z_$id/subagents/'
          '2026-10-21T08-00-00-000Z_$kid.jsonl',
      'status': 'running',
    });
    await store.close(const SessionId(id));
    final logger = RecordingLogger();
    final core = buildAgentCore(
      profile: HostProfile.of('embedded-cli'),
      services: AgentCoreServices(
        baseEnv: LocalExecutionEnv(cwd: cwd),
        logger: logger,
        clock: FakeClock(start: t0),
        ids: SequentialIdGenerator(),
        sessions: storeAt(root),
      ),
      config: CoreConfig(
        defaultModel: ModelRef(
          provider: 'test',
          id: 'model-1',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://localhost:8080/v1'),
          contextWindow: 32000,
          maxOutputTokens: 4096,
        ),
      ),
      streamFunction: ScriptedStreamFunction.fromJson({'steps': const []}).call,
    );

    await core.runtime.loadSession(
      const SessionId(id),
      const SessionHostPorts(),
    );

    final failed = logger.eventsOf('subagent.heal_failed').single;
    expect(failed.fields['subagent_id'], 'sub_aaaaaaaa');
    expect(failed.fields['error_class'], isA<String>());
    expect(failed.error, isNull, reason: 'текст ошибки содержит путь');
    expect('${failed.fields} ${failed.stack}', isNot(contains('.jsonl')));
    await core.runtime.dispose();
  });
}
