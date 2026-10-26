import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'journal_lines.dart';
import 'session_store_contract.dart';

void main() {
  group('contract', () {
    sessionStoreContract(() async => MemorySessionStore());
  });

  test('the text of a journal is one JSON record per line', () async {
    final store = MemorySessionStore();
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    await store.create(
      SessionHeader(
        id: id,
        cwd: '/work/demo',
        created: DateTime.utc(2026, 10, 21, 8),
        agent: const AgentInfo(name: 'codelab-agent', version: '0.1.0'),
      ),
    );

    expect(store.textOf(id), '${header()}\n');
  });

  test('putText seeds a journal, open repairs it in memory', () async {
    final store = MemorySessionStore();
    const id = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');
    final whole = journal([header(), user('a', null), answer('b', 'a')]);
    store.putText(id, whole.substring(0, whole.length - 10));

    final snapshot = await store.open(id);

    expect(snapshot.records.map((r) => r.id), ['a']);
    expect(snapshot.repair.quarantinedLines, 1);
    expect(store.textOf(id), journal([header(), user('a', null)]));
  });
}
