import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import 'journal_lines.dart';

/// Продолжение прерванного хода (agent-sessions «Продолжение прерванного
/// хода», §8.8, SES-10).
void main() {
  const interruptedText =
      'Tool call was interrupted: the agent process stopped before the '
      'result was recorded. The tool may have partially run. Check the '
      'current state (for example, re-read the file) before retrying.';

  SessionSnapshot snapshot(List<String> lines) => parseSessionLines(
    journal([header(), ...lines]),
    id: const SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C'),
  ).snapshot;

  List<MessageRecord> heal(
    SessionSnapshot s, {
    Map<String, ToolMeta> meta = const {},
  }) => healInterruptedTurn(
    s,
    SequentialIdGenerator(),
    FakeClock(start: DateTime.utc(2026, 10, 21, 9)),
    meta: meta,
  );

  test('a crash during the answer leaves nothing to heal', () {
    final s = snapshot([user('u1', null)]);

    expect(findInterruptedCalls(s), isEmpty);
    expect(heal(s), isEmpty);
  });

  test('all results recorded — nothing to heal', () {
    final s = snapshot([
      user('u1', null),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'read', {'path': 'a'}),
        ],
      ),
      toolResult('r1', 'a1', callId: 'c1'),
    ]);

    expect(heal(s), isEmpty);
  });

  test('a crash between calls of a batch heals the missing ones in order', () {
    final s = snapshot([
      user('u1', null),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'read', {'path': 'pubspec.yaml'}),
          ('c2', 'exec', {'command': 'dart test'}),
          ('c3', 'ls', {}),
        ],
      ),
      toolResult('r1', 'a1', callId: 'c1'),
    ]);

    final healed = heal(
      s,
      meta: {
        'c2': ToolMeta(
          title: 'Run dart test',
          kind: ToolKind.execute,
          locations: const [],
        ),
      },
    );

    expect(findInterruptedCalls(s).map((c) => c.id), ['c2', 'c3']);
    expect(healed, hasLength(2));
    final [exec, ls] = healed;
    expect(exec.parentId, 'r1');
    expect(ls.parentId, exec.id);
    expect(exec.outcome, 'interrupted');
    expect(exec.toolMeta?.title, 'Run dart test');
    expect(ls.toolMeta?.title, 'ls');
    expect(ls.toolMeta?.kind, ToolKind.other);
    final result = exec.message as ToolResultMessage;
    expect(result.toolCallId, 'c2');
    expect(result.toolName, 'exec');
    expect(result.isError, isTrue);
    expect((result.content.single as TextContent).text, interruptedText);
    expect(result.timestamp, DateTime.utc(2026, 10, 21, 9));
    expect(exec.timestamp, DateTime.utc(2026, 10, 21, 9));
  });

  test('a crash during the only call heals it', () {
    final s = snapshot([
      user('u1', null),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'exec', {'command': 'sleep 60'}),
        ],
      ),
    ]);

    final healed = heal(s);

    expect(healed.single.parentId, 'a1');
    expect((healed.single.message as ToolResultMessage).toolCallId, 'c1');
  });

  test('only the last answer of the branch is looked at', () {
    final s = snapshot([
      user('u1', null),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'read', {'path': 'a'}),
        ],
      ),
      user('u2', 'a1'),
      answer('a2', 'u2'),
    ]);

    expect(heal(s), isEmpty);
  });

  test('healed ids are unique in the snapshot', () {
    final s = snapshot([
      user('u1', null),
      answer(
        'a1',
        'u1',
        calls: [
          ('c1', 'read', {'path': 'a'}),
          ('c2', 'read', {'path': 'b'}),
        ],
      ),
    ]);

    final healed = heal(s);

    expect(healed.map((r) => r.id).toSet(), hasLength(2));
    expect(healed.every((r) => !s.byId.containsKey(r.id)), isTrue);
  });
}
