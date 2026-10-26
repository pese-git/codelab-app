import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/cut_point.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:test/test.dart';

import 'region.dart';

/// agent-compaction «Точка среза» (задача 8.1, `agent-core-architecture`
/// §9.6; CMP-1, CMP-7).
void main() {
  const keep4096 = CompactionSettings(
    reserveTokens: 2048,
    keepRecentTokens: 4096,
    keepRecentUserTurns: 1,
  );

  /// Ни один результат хвоста не отделён от своего вызова (CMP-1).
  void expectPaired(List<SessionRecord> region, int firstKept) {
    final calls = <String>{};
    for (final record in region.skip(firstKept)) {
      if (record case MessageRecord(:final message)) {
        if (message is AssistantMessage) {
          calls.addAll(message.toolCalls.map((c) => c.id));
        }
        if (message is ToolResultMessage) {
          expect(calls, contains(message.toolCallId));
        }
      }
    }
  }

  test('golden: the example of §9.6', () {
    final r = RegionBuilder()
      ..user(40)
      ..call('c1', 'exec')
      ..result('c1', 'exec', 5200)
      ..assistant(60)
      ..modeChange('plan')
      ..user(30)
      ..call('c2', 'read')
      ..result('c2', 'read', 3900)
      ..assistant(400);

    final cut = findCutPoint(r.records, keep4096)!;

    expect(cut.firstKeptIndex, 4);
    expect(r.records[cut.firstKeptIndex], isA<ModeChangeRecord>());
    expect(cut.splitTurn, isFalse);
  });

  test('a long batch of calls on the boundary is not torn apart', () {
    final r = RegionBuilder()
      ..user(40)
      ..assistant(50)
      ..user(30)
      ..calls(['b1', 'b2', 'b3', 'b4', 'b5'], 'read');
    for (final id in ['b1', 'b2', 'b3', 'b4', 'b5']) {
      r.result(id, 'read', 1000);
    }
    r.assistant(100);

    final cut = findCutPoint(r.records, keep4096)!;

    final first = r.records[cut.firstKeptIndex] as MessageRecord;
    expect(first.message, isA<UserMessage>());
    expect(cut.firstKeptIndex, 2);
    expectPaired(r.records, cut.firstKeptIndex);
  });

  test('service records right before the cut stay with the tail', () {
    final r = RegionBuilder()
      ..user(40)
      ..assistant(5000)
      ..plan()
      ..modelChange()
      ..user(30)
      ..assistant(4500);

    final cut = findCutPoint(r.records, keep4096)!;

    expect(cut.firstKeptIndex, 2);
    expect(r.records[2], isA<PlanRecord>());
  });

  test('one huge turn is split inside: splitTurn and turnStartIndex', () {
    final r = RegionBuilder()
      ..user(40)
      ..call('c1', 'read')
      ..result('c1', 'read', 3000)
      ..call('c2', 'read')
      ..result('c2', 'read', 3000)
      ..call('c3', 'read')
      ..result('c3', 'read', 3000)
      ..assistant(50);

    final cut = findCutPoint(r.records, keep4096)!;

    expect(cut.splitTurn, isTrue);
    expect(cut.turnStartIndex, 0);
    expect(cut.firstKeptIndex, 5);
    final first = r.records[cut.firstKeptIndex] as MessageRecord;
    expect(first.message, isA<AssistantMessage>());
    expectPaired(r.records, cut.firstKeptIndex);
  });

  test('everything fits into the tail — null', () {
    final r = RegionBuilder()
      ..user(40)
      ..assistant(100)
      ..user(30)
      ..assistant(200);

    expect(findCutPoint(r.records, keep4096), isNull);
  });

  test('no messages — null', () {
    final r = RegionBuilder()..modeChange('plan');

    expect(findCutPoint(r.records, keep4096), isNull);
  });

  test('a service user message is not a user turn', () {
    // Если бы подсказка цикла считалась ходом, хвост начался бы с неё
    // (индекс 2); на деле ход пользователя один, и срез идёт внутри него.
    const keep3000 = CompactionSettings(
      reserveTokens: 2048,
      keepRecentTokens: 3000,
      keepRecentUserTurns: 1,
    );
    final r = RegionBuilder()
      ..user(40)
      ..assistant(3000)
      ..nudge(20)
      ..assistant(3000);

    final cut = findCutPoint(r.records, keep3000)!;

    expect(cut.firstKeptIndex, 3);
    expect(cut.splitTurn, isTrue);
    expect(cut.turnStartIndex, 0);
  });
}
