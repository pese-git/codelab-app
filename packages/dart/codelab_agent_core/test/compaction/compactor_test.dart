import 'package:collection/collection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/compactor.dart';
import 'package:codelab_agent_core/src/compaction/cut_point.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
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
  RegionBuilder twoTurns({Usage lastUsage = Usage.zero}) => RegionBuilder()
    ..user(40)
    ..call('c1', 'read', path: 'lib/a.dart')
    ..result('c1', 'read', 3000)
    ..call('c2', 'edit', path: 'lib/b.dart')
    ..result('c2', 'edit', 50)
    ..assistant(60)
    ..user(30)
    ..assistant(2500, usage: lastUsage);

  /// Длинная цепочка чтений: оценка выше порога и после первого прохода,
  /// поэтому CMP-5 запускает следующий. [lastUsage] — якорь оценки.
  RegionBuilder longChain({Usage lastUsage = Usage.zero}) {
    final r = RegionBuilder()
      ..user(40)
      ..assistant(2000)
      ..user(40);
    for (var i = 0; i < 6; i++) {
      r
        ..call('k$i', 'read')
        ..result('k$i', 'read', 2000);
    }
    return r..assistant(50, usage: lastUsage);
  }

  Summarizer fixed(String text, {List<SummaryRequest>? seen}) =>
      (request, cancel) async {
        seen?.add(request);
        return summaryOf(text);
      };

  Future<CompactionOutcome> run(
    Summarizer summarize, {
    CancelToken? cancel,
    void Function(LlmContextProjection)? onCompacted,
    String systemPrompt = 'You are CodeLab.',
    List<ToolSchema> tools = const [],
    CompactionAnchor? anchor,
  }) => compact(
    writer: writer,
    trigger: CompactionTrigger.afterTurn,
    summarize: summarize,
    settings: settings,
    window: window,
    systemPrompt: systemPrompt,
    tools: tools,
    ids: SequentialIdGenerator(prefix: 'cmp'),
    clock: FakeClock(),
    cancel: cancel ?? CancelToken.none,
    emit: events.add,
    onCompacted: onCompacted,
    logger: logger,
    anchor: anchor,
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
      'usage': Usage.zero.toJson(),
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
      await journal(longChain());
      var calls = 0;

      // CMP-10 / D1: каждый проход обязан давать выигрыш, поэтому резюме
      // первого прохода короче его региона (раньше здесь было `'x' * 16000`
      // — резюме длиннее региона, такой проход теперь не записывается), но
      // оценка остаётся выше порога, и идёт второй проход.
      final outcome = await run((request, cancel) async {
        calls++;
        return summaryOf(calls == 1 ? 'x' * 400 : 'y' * 40);
      });

      expect(outcome, isA<Compacted>());
      final records = store.appended.map((a) => a.record).toList();
      expect(records, hasLength(2));
      expect(records, everyElement(isA<CompactionRecord>()));
      expect(calls, lessThanOrEqualTo(3));
      expect(events.whereType<ContextCompacted>(), hasLength(2));
    },
  );

  group('consistent estimate after the pass (D1, D2, CMP-5, CMP-10)', () {
    final tools = [
      ToolSchema(name: 'read', description: 'Read a file', parameters: {}),
    ];
    // Постоянная часть (промпт и схемы) по эвристике заметно больше, чем её
    // «настоящая» стоимость у провайдера: так выглядит наблюдение change
    // `fix-compaction-estimate-and-no-gain` (якорь 3043 при эвристике 4450).
    // 12 000 символов: эвристика проекции после (≈5 600) остаётся ниже порога
    // (6 144), поэтому здесь один проход; случай «эвристика выше порога» — в
    // тесте D8 ниже.
    final prompt = 'p' * 12000;

    int heuristic() => estimateTokens(
      buildLlmContext(writer.snapshot).messages,
      systemPrompt: prompt,
      tools: tools,
    );

    test(
      'an anchor below the heuristic of the constant part: tokensAfter is '
      'below tokensBefore and equals before + H(after) − H(before)',
      () async {
        await journal(twoTurns());
        // Якорь на 4000 токенов ниже эвристики всего контекста: ошибка сидит
        // в постоянной части и в регионе, который сжимается, не участвует.
        final hBefore = heuristic();
        await journal(
          twoTurns(lastUsage: Usage(input: hBefore - 4000, output: 0)),
        );

        final outcome =
            await run(
                  fixed('short summary'),
                  systemPrompt: prompt,
                  tools: tools,
                )
                as Compacted;

        final record = store.appended.first.record as CompactionRecord;
        expect(record.tokensBefore, hBefore - 4000);
        expect(record.tokensAfter, lessThan(record.tokensBefore));
        expect(record.tokensAfter, record.tokensBefore + heuristic() - hBefore);
        expect(store.appended, hasLength(1));
        expect(outcome.tokensBefore, record.tokensBefore);
        expect(outcome.tokensAfter, record.tokensAfter);
        final event = events.whereType<ContextCompacted>().single;
        expect(event.tokensBefore, record.tokensBefore);
        expect(event.tokensAfter, record.tokensAfter);
        final done = logger.eventsOf('compaction.done').single.fields;
        expect(done['tokens_before'], record.tokensBefore);
        expect(done['tokens_after'], record.tokensAfter);
      },
    );

    test('with an anchor the record keeps the consistent estimate, not '
        'H(after) (D1, D8)', () async {
      await journal(twoTurns());
      final hBefore = heuristic();
      await journal(
        twoTurns(lastUsage: Usage(input: hBefore - 4000, output: 0)),
      );

      await run(fixed('short summary'), systemPrompt: prompt, tools: tools);

      // Без якоря в проекции после сжатия (§8.7): H(после) — чистая
      // эвристика, а в запись, события и сравнение с порогом идёт
      // согласованное «после», не она (D8).
      final record = store.appended.first.record as CompactionRecord;
      final hAfter = heuristic();
      expect(record.tokensAfter, record.tokensBefore + hAfter - hBefore);
      expect(record.tokensAfter, isNot(hAfter));
    });

    test('without an anchor the behaviour is as before: tokensBefore is '
        'H(before), tokensAfter is H(after) (tasks 3.1)', () async {
      await journal(twoTurns());
      final hBefore = heuristic();

      await run(fixed('short summary'), systemPrompt: prompt, tools: tools);

      final record = store.appended.single.record as CompactionRecord;
      expect(record.tokensBefore, hBefore);
      expect(record.tokensAfter, heuristic());
    });

    // Якорь выше: согласованное «после» первого прохода всё ещё выше порога
    // (D8: решает оно, а не эвристика), резать дальше нечего.
    test('the second pass without a cut point after the first is recorded: '
        'compaction.skipped pass 2, the outcome is the first Compacted '
        '(D3, D8)', () async {
      final longPrompt = 'p' * 22000;
      RegionBuilder build({Usage usage = Usage.zero}) => RegionBuilder()
        ..user(40)
        ..assistant(1100)
        ..assistant(1100)
        ..user(30)
        ..assistant(1000, usage: usage);
      await journal(build());
      final hBefore = estimateTokens(
        buildLlmContext(writer.snapshot).messages,
        systemPrompt: longPrompt,
        tools: tools,
      );
      // После первого прохода в регионе остаются ответ и последний ход
      // (≈2 150 токенов): срезать дальше нечего (ход не больше хвоста), а
      // согласованное «после» (промпт ≈5 500) выше порога.
      await journal(build(usage: Usage(input: hBefore - 1000, output: 0)));
      var calls = 0;

      final outcome = await run(
        (request, cancel) async {
          calls++;
          return summaryOf('short');
        },
        systemPrompt: longPrompt,
        tools: tools,
      );

      expect(calls, 1);
      final first = store.appended.single.record as CompactionRecord;
      expect(
        first.tokensAfter,
        greaterThan(compactionThreshold(window, settings)),
      );
      expect((outcome as Compacted).record, same(first));
      final skipped = logger.eventsOf('compaction.skipped').single.fields;
      expect(skipped['pass'], 2);
      expect(skipped['reason'], 'no cut point');
    });

    // Заменил тест D9 предшественника «Порог проверяется и по эвристике без
    // якоря»: D9 снят, число проходов определяет согласованная оценка
    // (change `anchor-context-estimate-after-compaction`, D8, CMP-5, CMP-11).
    test('the threshold is checked by the consistent estimate: after of the '
        'first pass is within it, H(after) is not, a region for a second '
        'pass exists — one summarizer call, one record, the first Compacted '
        '(D8, CMP-5)', () async {
      final longPrompt = 'p' * 20000;
      await journal(longChain());
      final hBefore = estimateTokens(
        buildLlmContext(writer.snapshot).messages,
        systemPrompt: longPrompt,
        tools: tools,
      );
      // Якорь на 12 000 токенов ниже эвристики (провайдер считает промпт и
      // результаты заметно дешевле `chars / 4`): согласованное «после»
      // укладывается в порог, а эвристика проекции после — нет.
      await journal(
        longChain(lastUsage: Usage(input: hBefore - 12000, output: 0)),
      );
      var calls = 0;

      final outcome = await run(
        (request, cancel) async {
          calls++;
          return summaryOf(calls == 1 ? 'x' * 400 : 'y' * 40);
        },
        systemPrompt: longPrompt,
        tools: tools,
      );

      final threshold = compactionThreshold(window, settings);
      final record = store.appended.single.record as CompactionRecord;
      expect(record.tokensAfter, lessThanOrEqualTo(threshold));
      expect(
        estimateTokens(
          buildLlmContext(writer.snapshot).messages,
          systemPrompt: longPrompt,
          tools: tools,
        ),
        greaterThan(threshold),
        reason: 'H(after) is above the threshold',
      );
      expect(
        compactionRegion(writer.snapshot).region,
        isNotEmpty,
        reason: 'a second pass would have a region',
      );
      expect(calls, 1);
      expect(store.appended, hasLength(1));
      expect((outcome as Compacted).record, same(record));
      expect(logger.eventsOf('compaction.skipped'), isEmpty);
    });

    // CMP-11 и «Сжатие сразу после сжатия» (D8): «до» нового прохода
    // продолжает шкалу прошлой записи, а не возвращается к эвристике.
    test('a compaction right after a compaction: tokensBefore is tokensAfter '
        'of the first record plus H of the new messages (D8); without the '
        'anchor parameter — the former heuristic', () async {
      final prompt = 'p' * 12000;
      await journal(twoTurns());
      final hBefore = estimateTokens(
        buildLlmContext(writer.snapshot).messages,
        systemPrompt: prompt,
        tools: tools,
      );
      await journal(
        twoTurns(lastUsage: Usage(input: hBefore - 4000, output: 0)),
      );
      LlmContextProjection? first;
      await run(
        fixed('first'),
        systemPrompt: prompt,
        tools: tools,
        onCompacted: (p) => first = p,
      );
      final firstRecord = store.appended.single.record as CompactionRecord;
      final anchor = compactionAnchorOf(
        first!,
        systemPrompt: prompt,
        tools: tools,
      );
      expect(anchor, isNotNull);
      expect(anchor!.tokens, firstRecord.tokensAfter);
      // Новые сообщения после первой записи: ход с чтением и ответ.
      final more = RegionBuilder()
        ..call('c3', 'read', path: 'lib/c.dart')
        ..result('c3', 'read', 3000)
        ..user(30)
        ..assistant(2500);
      var added = 0;
      for (final record in more.records.cast<MessageRecord>()) {
        added += estimateMessageTokens(record.message);
        await writer.append(
          (id, parent, at) => MessageRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            message: record.message,
          ),
        );
      }
      store.appended.clear();
      final snapshot = writer.snapshot;
      final heuristicBefore = estimateTokens(
        buildLlmContext(snapshot).messages,
        systemPrompt: prompt,
        tools: tools,
      );

      await run(
        fixed('second'),
        systemPrompt: prompt,
        tools: tools,
        anchor: anchor,
      );

      final second = store.appended.single.record as CompactionRecord;
      expect(second.tokensBefore, firstRecord.tokensAfter + added);
      expect(second.tokensBefore, isNot(heuristicBefore));

      // Без параметра — прежняя эвристика (границы нет).
      await journal(
        twoTurns(lastUsage: Usage(input: hBefore - 4000, output: 0)),
      );
      await run(fixed('first'), systemPrompt: prompt, tools: tools);
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
      store.appended.clear();
      await run(fixed('second'), systemPrompt: prompt, tools: tools);
      expect(
        (store.appended.single.record as CompactionRecord).tokensBefore,
        heuristicBefore,
      );
    });

    // D3: `raw`, который сессия фиксирует по проекции из `onCompacted`,
    // совпадает с `raw` пробной проекции компактора, поэтому сразу после
    // записи оценка равна `tokensAfter` (CMP-11).
    test(
      'the anchor of the projection from onCompacted: raw is H of the '
      'trial projection, the estimate equals tokensAfter (D3, CMP-11)',
      () async {
        final prompt = 'p' * 12000;
        await journal(twoTurns());
        final hBefore = estimateTokens(
          buildLlmContext(writer.snapshot).messages,
          systemPrompt: prompt,
          tools: tools,
        );
        await journal(
          twoTurns(lastUsage: Usage(input: hBefore - 4000, output: 0)),
        );
        LlmContextProjection? rebuilt;

        await run(
          fixed('short'),
          systemPrompt: prompt,
          tools: tools,
          onCompacted: (p) => rebuilt = p,
        );

        final record = store.appended.single.record as CompactionRecord;
        final anchor = compactionAnchorOf(
          rebuilt!,
          systemPrompt: prompt,
          tools: tools,
        );
        expect(anchor, isNotNull);
        expect(anchor!.tokens, record.tokensAfter);
        expect(
          anchor.raw,
          estimateTokens(rebuilt!.messages, systemPrompt: prompt, tools: tools),
        );
        expect(
          estimateContextTokens(
            rebuilt!.messages,
            systemPrompt: prompt,
            tools: tools,
            compaction: anchor,
          ),
          record.tokensAfter,
        );
        // Предпосылка: эвристика «после» отличается от `tokensAfter`.
        expect(anchor.raw, isNot(record.tokensAfter));
      },
    );

    test(
      'a chain of passes: tokensBefore of the second record is '
      'tokensAfter of the first; every record shrinks the estimate',
      () async {
        await journal(longChain(lastUsage: const Usage(input: 9000)));
        var calls = 0;

        await run((request, cancel) async {
          calls++;
          return summaryOf(calls == 1 ? 'x' * 400 : 'y' * 40);
        });

        final records = [
          for (final a in store.appended) a.record as CompactionRecord,
        ];
        expect(records, hasLength(2));
        expect(records[1].tokensBefore, records[0].tokensAfter);
        for (final record in records) {
          expect(record.tokensAfter, lessThan(record.tokensBefore));
        }
      },
    );

    test('a summary longer than the region: NothingToCompact, nothing is '
        'written, compaction.skipped without the summary (CMP-10)', () async {
      await journal(twoTurns());
      final before = store.inner.textOf(sid);
      var compacted = 0;

      final outcome = await run(
        fixed('x' * 20000),
        onCompacted: (_) => compacted++,
      );

      expect(outcome, isA<NothingToCompact>());
      expect((outcome as NothingToCompact).reason, 'no reduction');
      expect(store.appended, isEmpty);
      expect(store.inner.textOf(sid), before);
      expect(events.whereType<ContextCompacted>(), isEmpty);
      expect(compacted, 0);
      final skipped = logger.eventsOf('compaction.skipped').single;
      expect(skipped.level, LogLevel.info);
      expect(skipped.fields.keys, {
        'session_id',
        'trigger',
        'pass',
        'reason',
        'tokens_before',
        'tokens_after',
      });
      expect(skipped.fields['session_id'], sid.value);
      expect(skipped.fields['trigger'], 'afterTurn');
      expect(skipped.fields['pass'], 1);
      expect(skipped.fields['reason'], 'no reduction');
      expect(
        skipped.fields['tokens_after'] as int,
        greaterThanOrEqualTo(skipped.fields['tokens_before'] as int),
      );
      expect(skipped.toString(), isNot(contains('xxxx')));
    });

    test('a second pass without gain: the first record stays, the result is '
        'its Compacted, compaction.skipped has pass 2', () async {
      await journal(longChain());
      var calls = 0;

      final outcome = await run((request, cancel) async {
        calls++;
        return summaryOf(calls == 1 ? 'x' * 400 : 'y' * 80000);
      });

      expect(calls, 2);
      expect(store.appended.map((a) => a.record), hasLength(1));
      expect(events.whereType<ContextCompacted>(), hasLength(1));
      final first = store.appended.single.record as CompactionRecord;
      expect((outcome as Compacted).record, same(first));
      expect(logger.eventsOf('compaction.skipped').single.fields['pass'], 2);
    });
  });

  test(
    'nothing to compact: compaction.skipped with reason no cut point',
    () async {
      await journal(
        RegionBuilder()
          ..user(40)
          ..assistant(100),
      );

      final seen = <SummaryRequest>[];
      final outcome = await run(fixed('never', seen: seen));

      expect(outcome, isA<NothingToCompact>());
      expect((outcome as NothingToCompact).reason, 'no cut point');
      // Суммаризатор не вызван: срез ищется до запроса к модели (spec «Нет
      // точки среза»).
      expect(seen, isEmpty);
      expect(store.appended, isEmpty);
      final skipped = logger.eventsOf('compaction.skipped').single;
      expect(skipped.level, LogLevel.info);
      expect(skipped.fields['session_id'], sid.value);
      expect(skipped.fields['trigger'], 'afterTurn');
      expect(skipped.fields['pass'], 1);
      expect(skipped.fields['reason'], 'no cut point');
      // Полей оценок нет: проход не дошёл до них (spec «Нет точки среза», D3).
      expect(skipped.fields.keys, {'session_id', 'trigger', 'pass', 'reason'});
    },
  );

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
        return summaryOf('too late');
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
