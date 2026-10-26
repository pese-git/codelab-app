import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/tree.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'journal_lines.dart';

/// Дерево записей (agent-sessions «Идентификаторы и дерево записей», §8.4).
void main() {
  SessionSnapshot snapshot(List<String> lines) => parseSessionLines(
    journal([header(), ...lines]),
    id: const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C'),
  ).snapshot;

  List<String> ids(List<SessionRecord> path) => [for (final r in path) r.id];

  test('the path to the leaf is root-first', () {
    final s = snapshot([user('a', null), answer('b', 'a'), user('c', 'b')]);

    expect(ids(pathToLeaf(s)), ['a', 'b', 'c']);
  });

  test('after a leaf record the next record is a sibling', () {
    // Схема §8.4: после leaf → p7d2 запись n1m2 — сиблинг q1w2.
    final s = snapshot([
      modelChange('k3f9', null),
      user('p7d2', 'k3f9'),
      answer('q1w2', 'p7d2'),
      leaf('z9x8', 'q1w2', target: 'p7d2'),
      user('n1m2', 'p7d2', text: 'refine'),
      answer('b5v6', 'n1m2'),
    ]);

    expect(s.leafId, 'b5v6');
    expect(ids(pathToLeaf(s)), ['k3f9', 'p7d2', 'n1m2', 'b5v6']);
  });

  test('an explicit leaf id selects another branch', () {
    final s = snapshot([user('a', null), answer('b', 'a'), answer('c', 'a')]);

    expect(ids(pathToLeaf(s, leafId: 'b')), ['a', 'b']);
  });

  test('a cycle of parents ends the walk with session.cycle', () {
    final logger = RecordingLogger();
    final s = snapshot([user('a', 'b'), answer('b', 'a')]);

    final path = pathToLeaf(s, logger: logger);

    expect(ids(path), ['a', 'b']);
    expect(logger.eventsOf('session.cycle'), hasLength(1));
  });

  test('a missing parent ends the walk with session.broken_link', () {
    final logger = RecordingLogger();
    final s = snapshot([answer('b', 'gone'), user('c', 'b')]);

    final path = pathToLeaf(s, logger: logger);

    expect(ids(path), ['b', 'c']);
    expect(logger.eventsOf('session.broken_link').single.fields, {
      'id': 'gone',
    });
  });

  test('no leaf — an empty path', () {
    expect(pathToLeaf(snapshot([])), isEmpty);
  });

  test('leafAfter follows rule 2', () {
    final s = snapshot([user('a', null), leaf('l', 'a', target: 'x')]);

    expect(leafAfter(s.records.first), 'a');
    expect(leafAfter(s.records.last), 'x');
  });
}
