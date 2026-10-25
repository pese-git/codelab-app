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

/// agent-compaction «Запись сжатия и пересборка» (задача 9.1,
/// `agent-core-architecture` §9.8; CMP-2, CMP-3, CMP-4, CMP-5).
void main() {
  const sid = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0A');
  const settings = CompactionSettings(
    reserveTokens: 2048,
    keepRecentTokens: 2048,
    keepRecentUserTurns: 1,
  );
  const window = 8192;

  late RecordingStore store;
  late SessionWriter writer;
  late List<AgentEvent> events;
  late RecordingLogger logger;

  /// Журнал из записей [r], записанный через писатель.
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

  /// Две реплики пользователя: первая — с чтением и правкой файлов.
  RegionBuilder twoTurns() => RegionBuilder()
    ..user(40)
    ..call('c1', 'read', path: 'lib/a.dart')
    ..result('c1', 'read', 3000)
    ..call('c2', 'edit', path: 'lib/b.dart')
    ..result('c2', 'edit', 50)
    ..assistant(60)
    ..user(30)
    ..assistant(2500);

  Summarizer fixed(String text, {List<SummaryRequest>? seen}) =>
      (request, cancel) async {
        seen?.add(request);
        return text;
      };

  Future<CompactionOutcome> run(
    Summarizer summarize, {
    CancelToken? cancel,
    void Function(LlmContextProjection)? onCompacted,
  }) => compact(
    writer: writer,
    trigger: CompactionTrigger.afterTurn,
    summarize: summarize,
    settings: settings,
    window: window,
    systemPrompt: 'You are CodeLab.',
    tools: const [],
    ids: SequentialIdGenerator(prefix: 'cmp'),
    clock: FakeClock(),
    cancel: cancel ?? CancelToken.none,
    emit: events.add,
    onCompacted: onCompacted,
    summaryModel: 'test/model-1',
    logger: logger,
  );

  test('writes a durable compaction record and rebuilds the context', () async {
    await journal(twoTurns());
    LlmContextProjection? rebuilt;
    var journalAtEvent = '';
    events = _Spy(() => journalAtEvent = store.inner.textOf(sid)!);

    final outcome = await run(
      fixed('summary one'),
      onCompacted: (p) => rebuilt = p,
    );

    final compacted = outcome as Compacted;
    final appended = store.appended.single;
    expect(appended.durable, isTrue);
    final record = appended.record as CompactionRecord;
    expect(record, same(compacted.record));
    expect(record.summary, 'summary one');
    expect(record.firstKeptId, twoTurns().records[6].id);
    expect(record.tokensBefore, greaterThan(record.tokensAfter));
    expect(record.tokensAfter, compacted.tokensAfter);
    expect(record.details, {
      'readFiles': ['lib/a.dart'],
      'modifiedFiles': ['lib/b.dart'],
      'splitTurn': false,
      'summaryModel': 'test/model-1',
    });
    expect(rebuilt!.messages.map((m) => m.runtimeType), [
      UserMessage,
      UserMessage,
      AssistantMessage,
    ]);
    expect(
      rebuilt!.messages.length,
      buildLlmContext(writer.snapshot).messages.length,
    );
    final event = events.whereType<ContextCompacted>().single;
    expect(event.tokensBefore, record.tokensBefore);
    expect(event.tokensAfter, record.tokensAfter);
    expect(journalAtEvent, contains('"type":"compaction"'));
  });

  test(
    'core/compaction-iterative-summary: the region starts after the last one',
    () async {
      await journal(twoTurns());
      await run(fixed('first'));
      // Новые записи дописываются после записи сжатия — от текущего листа.
      final more = RegionBuilder()
        ..call('c3', 'read', path: 'lib/c.dart')
        ..result('c3', 'read', 3000)
        ..user(30)
        ..assistant(2500);
      for (final record in more.records.cast<MessageRecord>()) {
        await writer.append(
          (id, parent, at) => MessageRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            message: record.message,
          ),
        );
      }
      final seen = <SummaryRequest>[];

      await run(fixed('second', seen: seen));

      final request = seen.single;
      expect(request.previousSummary, 'first');
      expect(request.region.first.id, twoTurns().records[6].id);
      expect(request.fileOps.read, containsAll(['lib/a.dart', 'lib/c.dart']));
      expect(request.fileOps.modified, ['lib/b.dart']);
    },
  );

  test(
    'a second pass runs while the estimate is above the threshold',
    () async {
      final r = RegionBuilder()
        ..user(40)
        ..assistant(2000)
        ..user(40);
      for (var i = 0; i < 6; i++) {
        r
          ..call('k$i', 'read')
          ..result('k$i', 'read', 2000);
      }
      r.assistant(50);
      await journal(r);
      var calls = 0;

      final outcome = await run((request, cancel) async {
        calls++;
        return 'x' * 16000;
      });

      expect(outcome, isA<Compacted>());
      final records = store.appended.map((a) => a.record).toList();
      expect(records, hasLength(2));
      expect(records, everyElement(isA<CompactionRecord>()));
      expect(calls, lessThanOrEqualTo(3));
      expect(events.whereType<ContextCompacted>(), hasLength(2));
    },
  );

  test('nothing to compact', () async {
    await journal(
      RegionBuilder()
        ..user(40)
        ..assistant(100),
    );

    final outcome = await run(fixed('never'));

    expect(outcome, isA<NothingToCompact>());
    expect(store.appended, isEmpty);
  });

  test('a failed summary leaves the journal as it was (CMP-3)', () async {
    await journal(twoTurns());
    final before = store.inner.textOf(sid);

    final outcome = await run(
      (request, cancel) async => throw const CompactionFailure('model down'),
    );

    expect(outcome, isA<CompactionFailed>());
    expect(store.inner.textOf(sid), before);
    final error = events.whereType<AgentError>().single;
    expect(error.cls, AgentErrorClass.compaction);
    expect(error.retrying, isFalse);
    expect(logger.eventsOf('compaction.failed'), hasLength(1));
    expect(events.whereType<ContextCompacted>(), isEmpty);
  });

  test('a cancel during the summary is CancelledException (CMP-4)', () async {
    await journal(twoTurns());
    final before = store.inner.textOf(sid);

    await expectLater(
      run((request, cancel) async => throw const CancelledException(null)),
      throwsA(isA<CancelledException>()),
    );
    expect(store.inner.textOf(sid), before);
  });

  test('a cancel right after the summary writes nothing', () async {
    await journal(twoTurns());
    final before = store.inner.textOf(sid);
    final source = CancelTokenSource();

    await expectLater(
      run((request, cancel) async {
        source.cancel(const UserCancel());
        return 'too late';
      }, cancel: source.token),
      throwsA(isA<CancelledException>()),
    );
    expect(store.inner.textOf(sid), before);
  });
}

/// Список событий, который вызывает [onAdd] при каждом `ContextCompacted`:
/// так тест видит журнал в момент события.
final class _Spy extends DelegatingList<AgentEvent> {
  _Spy(this.onAdd) : super([]);

  final void Function() onAdd;

  @override
  void add(AgentEvent value) {
    if (value is ContextCompacted) {
      onAdd();
    }
    super.add(value);
  }
}
