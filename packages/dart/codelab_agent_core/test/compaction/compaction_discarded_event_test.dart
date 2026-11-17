import 'dart:async';

import 'package:collection/collection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/compactor.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:codelab_agent_core/src/compaction/summarizer.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/src/session/session_writer.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../session/recording_store.dart';
import 'region.dart';

/// Событие `CompactionDiscarded` компактора (change
/// `fix-discarded-compaction-usage`, D2; критерий «Учёт вызова суммаризатора
/// отброшенного прохода»).
///
/// Красная фаза (задача 1.1): файл не компилируется, пока в `lib/` нет
/// `CompactionDiscarded` (задача 1.3). Записи учёта проверяет
/// `compactor_test.dart` — без новых имён, по поведению.
void main() {
  const sid = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0A');
  const settings = CompactionSettings(
    reserveTokens: 2048,
    keepRecentTokens: 2048,
    keepRecentUserTurns: 1,
  );
  const usage = Usage(
    input: 764,
    output: 171,
    cost: UsageCost(input: 0.0001146, output: 0.0001026),
  );
  const model = 'openai/gpt-4o-mini';

  late RecordingStore store;
  late SessionWriter writer;
  late List<AgentEvent> events;
  late RecordingLogger logger;

  Future<void> journal(RegionBuilder r) async {
    store = RecordingStore();
    logger = RecordingLogger();
    events = [];
    final header = SessionHeader(
      id: sid,
      cwd: '/proj',
      created: DateTime.utc(2026),
      agent: const AgentInfo(name: 'test', version: '0'),
    );
    await store.create(header);
    writer = SessionWriter(
      store: store,
      snapshot: SessionSnapshot.empty(header),
      ids: SequentialIdGenerator(),
      clock: FakeClock(),
      logger: logger,
      onFailure: (_) {},
    );
    for (final record in r.records) {
      await writer.appendBuilt(record);
    }
    store.appended.clear();
  }

  RegionBuilder twoTurns() => RegionBuilder()
    ..user(40)
    ..call('c1', 'read', path: 'lib/a.dart')
    ..result('c1', 'read', 3000)
    ..call('c2', 'edit', path: 'lib/b.dart')
    ..result('c2', 'edit', 50)
    ..assistant(60)
    ..user(30)
    ..assistant(2500);

  RegionBuilder longChain() {
    final r = RegionBuilder()
      ..user(40)
      ..assistant(2000)
      ..user(40);
    for (var i = 0; i < 6; i++) {
      r
        ..call('k$i', 'read')
        ..result('k$i', 'read', 2000);
    }
    return r..assistant(50);
  }

  Future<CompactionOutcome> run(
    Summarizer summarize, {
    CancelToken? cancel,
    CompactionTrigger trigger = CompactionTrigger.afterTurn,
  }) => compact(
    writer: writer,
    trigger: trigger,
    summarize: summarize,
    settings: settings,
    window: 8192,
    systemPrompt: 'You are CodeLab.',
    tools: const [],
    ids: SequentialIdGenerator(prefix: 'cmp'),
    clock: FakeClock(),
    cancel: cancel ?? CancelToken.none,
    emit: events.add,
    logger: logger,
  );

  Summarizer paid(String text) =>
      (request, cancel) async =>
          SummaryResult(text: text, usage: usage, model: model);

  group('CompactionDiscarded (D2)', () {
    test(
      'a pass without gain: the event with the usage, the model and the '
      'estimates of the pass, after the record; no ContextCompacted',
      () async {
        await journal(twoTurns());

        final outcome = await run(paid('x' * 20000));

        expect(outcome, isA<NothingToCompact>());
        final discarded = events.whereType<CompactionDiscarded>().single;
        expect(discarded.usage, usage);
        expect(discarded.model, model);
        final skipped = logger.eventsOf('compaction.skipped').single.fields;
        expect(discarded.tokensBefore, skipped['tokens_before']);
        expect(discarded.tokensAfter, skipped['tokens_after']);
        expect(discarded.sessionId, sid);
        expect(events.whereType<ContextCompacted>(), isEmpty);
      },
    );

    test('the event comes after the record is in the journal (the record '
        'is written first, D1)', () async {
      await journal(twoTurns());
      var recordsAtEvent = -1;
      events = _Spy(() => recordsAtEvent = store.appended.length);

      await run(paid('x' * 20000));

      expect(recordsAtEvent, 1);
    });

    test('a second pass without gain: one ContextCompacted and one '
        'CompactionDiscarded', () async {
      await journal(longChain());
      var calls = 0;

      await run((request, cancel) async {
        calls++;
        return SummaryResult(
          text: calls == 1 ? 'x' * 400 : 'y' * 80000,
          usage: usage,
          model: model,
        );
      });

      expect(events.whereType<ContextCompacted>(), hasLength(1));
      expect(events.whereType<CompactionDiscarded>(), hasLength(1));
      expect(
        events.indexWhere((e) => e is ContextCompacted),
        lessThan(events.indexWhere((e) => e is CompactionDiscarded)),
      );
    });

    test('the manual trigger gives the same event', () async {
      await journal(twoTurns());

      await run(paid('x' * 20000), trigger: CompactionTrigger.manual);

      expect(events.whereType<CompactionDiscarded>(), hasLength(1));
    });

    test('a stale pass (CMP-12, Q6): the event, no ContextCompacted', () async {
      await journal(twoTurns());
      final started = Completer<void>();
      final release = Completer<void>();
      final future = run((request, cancel) async {
        started.complete();
        await release.future;
        return SummaryResult(text: 'y', usage: usage, model: model);
      });
      await started.future;
      await writer.append(
        (id, parent, at) => MessageRecord(
          id: id,
          parentId: parent,
          timestamp: at,
          message: UserMessage(const [TextContent('late')], timestamp: at),
        ),
      );
      release.complete();

      final outcome = await future;

      expect((outcome as NothingToCompact).reason, 'stale');
      final discarded = events.whereType<CompactionDiscarded>().single;
      expect(discarded.usage, usage);
      expect(discarded.model, model);
      expect(events.whereType<ContextCompacted>(), isEmpty);
    });

    test('no cut point, a failed summary and a cancel after the answer: no '
        'event (R3, Q5)', () async {
      await journal(
        RegionBuilder()
          ..user(40)
          ..assistant(100),
      );
      await run(paid('never'));
      expect(events.whereType<CompactionDiscarded>(), isEmpty);

      await journal(twoTurns());
      await run(
        (request, cancel) async => throw const CompactionFailure('down'),
      );
      expect(events.whereType<CompactionDiscarded>(), isEmpty);

      await journal(twoTurns());
      final source = CancelTokenSource();
      await expectLater(
        run((request, cancel) async {
          source.cancel(const UserCancel());
          return SummaryResult(text: 'late', usage: usage, model: model);
        }, cancel: source.token),
        throwsA(isA<CancelledException>()),
      );
      expect(events.whereType<CompactionDiscarded>(), isEmpty);
    });

    test('a failed write of the accounting record leaves compact with the '
        'error and emits no event (SES-8)', () async {
      await journal(twoTurns());
      store.failAppends = true;

      await expectLater(run(paid('x' * 20000)), throwsA(anything));

      expect(events.whereType<CompactionDiscarded>(), isEmpty);
    });
  });

  test('the replay of a journal with the accounting record gives no '
      'CompactionDiscarded', () async {
    await journal(twoTurns());
    await run(paid('x' * 20000));

    final replay = buildReplay(writer.snapshot);

    expect(replay.whereType<CompactionDiscarded>(), isEmpty);
    expect(replay.whereType<ContextCompacted>(), isEmpty);
  });
}

/// Список событий, который вызывает [onAdd] при каждом `CompactionDiscarded`:
/// так тест видит журнал в момент события.
final class _Spy extends DelegatingList<AgentEvent> {
  _Spy(this.onAdd) : super([]);

  final void Function() onAdd;

  @override
  void add(AgentEvent value) {
    if (value is CompactionDiscarded) {
      onAdd();
    }
    super.add(value);
  }
}
