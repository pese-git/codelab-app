import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/compaction/compactor.dart';
import 'package:codelab_agent_core/src/compaction/cut_point.dart';
import 'package:codelab_agent_core/src/compaction/estimate.dart';
import 'package:codelab_agent_core/src/compaction/settings.dart';
import 'package:codelab_agent_core/src/compaction/summarizer.dart';
import 'package:codelab_agent_core/src/session/projections.dart';
import 'package:codelab_agent_core/src/session/session_writer.dart';
import 'package:codelab_agent_core/src/session/tree.dart';
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

    test('a summary longer than the region: NothingToCompact, no compaction '
        'record, the only new record is the accounting one (D1), '
        'compaction.skipped without the summary (CMP-10)', () async {
      await journal(twoTurns());
      final before = store.inner.textOf(sid);
      final contextBefore = _context(writer);
      var compacted = 0;

      final outcome = await run(
        fixed('x' * 20000),
        onCompacted: (_) => compacted++,
      );

      expect(outcome, isA<NothingToCompact>());
      expect((outcome as NothingToCompact).reason, 'no reduction');
      // Характеризационная правка (change `fix-discarded-compaction-usage`,
      // D1, R2): раньше тут было «журнал не изменился». Теперь единственная
      // новая запись — служебная запись учёта; записей `compaction` нет,
      // проекция и транскрипт те же.
      final record = store.appended.single.record;
      expect(record, isA<CustomRecord>());
      expect((record as CustomRecord).customType, _discardedType);
      expect(writer.snapshot.records.whereType<CompactionRecord>(), isEmpty);
      expect(
        store.inner.textOf(sid),
        startsWith(before!),
        reason: 'the journal only grows by the accounting record',
      );
      expect(_context(writer), contextBefore);
      expect(events.whereType<ContextCompacted>(), isEmpty);
      expect(compacted, 0);
      final skipped = logger.eventsOf('compaction.skipped').single;
      expect(skipped.level, LogLevel.info);
      // D6: в логе прибавились `usage_record_id` и `summary_model`.
      expect(skipped.fields.keys, {
        'session_id',
        'trigger',
        'pass',
        'reason',
        'tokens_before',
        'tokens_after',
        'usage_record_id',
        'summary_model',
      });
      expect(skipped.fields['session_id'], sid.value);
      expect(skipped.fields['trigger'], 'afterTurn');
      expect(skipped.fields['pass'], 1);
      expect(skipped.fields['reason'], 'no reduction');
      expect(skipped.fields['usage_record_id'], record.id);
      expect(
        skipped.fields['tokens_after'] as int,
        greaterThanOrEqualTo(skipped.fields['tokens_before'] as int),
      );
      expect(skipped.toString(), isNot(contains('xxxx')));
    });

    test('a second pass without gain: the first record stays, then the '
        'accounting record of pass 2; the result is the first Compacted, '
        'compaction.skipped has pass 2', () async {
      await journal(longChain());
      var calls = 0;

      final outcome = await run((request, cancel) async {
        calls++;
        return summaryOf(calls == 1 ? 'x' * 400 : 'y' * 80000);
      });

      expect(calls, 2);
      expect(events.whereType<ContextCompacted>(), hasLength(1));
      // Характеризационная правка (change `fix-discarded-compaction-usage`,
      // D1, R2): после записи `compaction` первого прохода — одна запись
      // учёта второго, отброшенного прохода (`pass: 2`).
      final appended = store.appended.map((a) => a.record).toList();
      expect(appended, hasLength(2));
      final first = appended.first as CompactionRecord;
      expect((outcome as Compacted).record, same(first));
      final discarded = appended.last as CustomRecord;
      expect(discarded.customType, _discardedType);
      expect(discarded.parentId, first.id);
      expect((discarded.data! as Map)['pass'], 2);
      expect(
        writer.snapshot.records.whereType<CompactionRecord>(),
        hasLength(1),
      );
      final skipped = logger.eventsOf('compaction.skipped').single.fields;
      expect(skipped['pass'], 2);
      expect(skipped['usage_record_id'], discarded.id);
    });
  });

  // Учёт оплаченного вызова суммаризатора у прохода, который не записан
  // (change `fix-discarded-compaction-usage`, D1, Q1 (а), Q6 (а); критерий
  // «Учёт вызова суммаризатора отброшенного прохода»). События
  // `CompactionDiscarded` проверяет `compaction_discarded_event_test.dart`.
  group('a discarded pass is accounted (D1)', () {
    const usage = Usage(
      input: 764,
      output: 171,
      cost: UsageCost(input: 0.0001146, output: 0.0001026),
    );
    const model = 'openai/gpt-4o-mini';

    Summarizer paid(String text) =>
        (request, cancel) async =>
            SummaryResult(text: text, usage: usage, model: model);

    test('the record: custom, the fields of D1, no summary text, not '
        'durable, a child of the leaf', () async {
      await journal(twoTurns());
      final leaf = writer.snapshot.leafId;

      await run(paid('x' * 20000));

      final appended = store.appended.single;
      expect(appended.durable, isFalse);
      final record = appended.record as CustomRecord;
      expect(record.customType, 'codelab.compaction_discarded');
      expect(record.parentId, leaf);
      expect(writer.snapshot.leafId, record.id);
      final skipped = logger.eventsOf('compaction.skipped').single.fields;
      expect(record.data, {
        'reason': 'no reduction',
        'trigger': 'afterTurn',
        'pass': 1,
        'tokensBefore': skipped['tokens_before'],
        'tokensAfter': skipped['tokens_after'],
        'summaryModel': model,
        'usage': usage.toJson(),
      });
      expect(skipped['summary_model'], model);
      expect(skipped['usage_record_id'], record.id);
      expect(jsonEncode(record.toJson()), isNot(contains('xxxx')));
    });

    test('no cut point, a failed summary and a cancel right after the '
        'answer write no accounting record (R3, Q5)', () async {
      await journal(
        RegionBuilder()
          ..user(40)
          ..assistant(100),
      );
      await run(paid('never'));
      expect(store.appended, isEmpty);

      await journal(twoTurns());
      await run(
        (request, cancel) async => throw const CompactionFailure('down'),
      );
      expect(store.appended, isEmpty);

      await journal(twoTurns());
      final source = CancelTokenSource();
      await expectLater(
        run((request, cancel) async {
          source.cancel(const UserCancel());
          return SummaryResult(text: 'late', usage: usage, model: model);
        }, cancel: source.token),
        throwsA(isA<CancelledException>()),
      );
      expect(store.appended, isEmpty);
    });

    test('the next compaction gets the accounting record in its region and '
        'finds the same cut point and request as without it', () async {
      // Контроль: тот же журнал, прямо без записи учёта.
      await journal(longChain());
      final controlSeen = <SummaryRequest>[];
      final control =
          await run(fixed('x' * 400, seen: controlSeen)) as Compacted;

      await journal(longChain());
      await run(paid('x' * 400000));
      expect(
        store.appended.single.record,
        isA<CustomRecord>(),
        reason: 'precondition: the discarded pass wrote the record',
      );
      store.appended.clear();
      final seen = <SummaryRequest>[];
      final outcome = await run(fixed('x' * 400, seen: seen)) as Compacted;

      expect(outcome.record.firstKeptId, control.record.firstKeptId);
      expect(
        seen.first.region.map((m) => m.id),
        controlSeen.first.region.map((m) => m.id),
      );
      expect(seen.first.previousSummary, controlSeen.first.previousSummary);
      expect(
        seen.first.turnPrefix?.length,
        controlSeen.first.turnPrefix?.length,
      );
      expect(store.appended.last.record, isA<CompactionRecord>());
    });

    test(
      'a mode change during the summary of a pass without gain stays on '
      'the active branch: the accounting record is its child (SES-16)',
      () async {
        await journal(twoTurns());
        final started = Completer<void>();
        final release = Completer<void>();
        final future = run((request, cancel) async {
          started.complete();
          await release.future;
          return SummaryResult(text: 'x' * 20000, usage: usage, model: model);
        });
        await started.future;
        final change = await writer.append(
          (id, parent, at) => ModeChangeRecord(
            id: id,
            parentId: parent,
            timestamp: at,
            modeId: 'plan',
          ),
        );
        release.complete();

        final outcome = await future;

        expect(outcome, isA<NothingToCompact>());
        final record = store.appended.last.record as CustomRecord;
        expect(record.customType, _discardedType);
        expect(record.parentId, change.id);
        expect(writer.snapshot.leafId, record.id);
        expect(
          pathToLeaf(writer.snapshot).map((r) => r.id),
          containsAllInOrder([change.id, record.id]),
        );
        final reopened = await store.inner.open(sid);
        expect(buildLlmContext(reopened).modeId, 'plan');
      },
    );

    test('a stale pass (a message during the summary) is accounted too, '
        'reason stale, a child of the current leaf (CMP-12, Q6)', () async {
      await journal(twoTurns());
      final started = Completer<void>();
      final release = Completer<void>();
      final future = run((request, cancel) async {
        started.complete();
        await release.future;
        return SummaryResult(
          text: 'secret summary',
          usage: usage,
          model: model,
        );
      });
      await started.future;
      final late = await writer.append(
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
      final record = store.appended.last.record as CustomRecord;
      expect(record.customType, _discardedType);
      expect(record.parentId, late.id);
      expect(writer.snapshot.leafId, record.id);
      expect((record.data! as Map)['reason'], 'stale');
      expect((record.data! as Map)['usage'], usage.toJson());
      expect(writer.snapshot.records.whereType<CompactionRecord>(), isEmpty);
      final skipped = logger.eventsOf('compaction.skipped').single;
      expect(skipped.level, LogLevel.warning);
      expect(skipped.fields['reason'], 'stale');
      expect(skipped.fields['usage_record_id'], record.id);
      expect(skipped.toString(), isNot(contains('secret summary')));
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

  // CMP-12, SES-16: запись сжатия ложится на текущий лист
  // (change `fix-config-change-during-background-compaction`, D2, D3).
  group('record goes to the current leaf (CMP-12)', () {
    /// Записи состояния, которые сессия пишет, пока резюме ещё считается.
    final stateRecords =
        <(String, SessionRecord Function(String id, String? parent))>[
          (
            'mode_change',
            (id, parent) => ModeChangeRecord(
              id: id,
              parentId: parent,
              timestamp: DateTime.utc(2026),
              modeId: 'plan',
            ),
          ),
          (
            'model_change',
            (id, parent) => ModelChangeRecord(
              id: id,
              parentId: parent,
              timestamp: DateTime.utc(2026),
              provider: 'test',
              modelId: 'model-2',
            ),
          ),
          (
            'config_change effort',
            (id, parent) => ConfigChangeRecord(
              id: id,
              parentId: parent,
              timestamp: DateTime.utc(2026),
              optionId: 'effort',
              value: 'high',
            ),
          ),
          (
            'config_change agent',
            (id, parent) => ConfigChangeRecord(
              id: id,
              parentId: parent,
              timestamp: DateTime.utc(2026),
              optionId: 'agent',
              value: 'reviewer',
            ),
          ),
          (
            'session_info',
            (id, parent) => SessionInfoRecord(
              id: id,
              parentId: parent,
              timestamp: DateTime.utc(2026),
              title: 'Title',
              source: 'auto',
            ),
          ),
        ];

    /// Суммаризатор, который ждёт [release] после старта; [started] —
    /// запрос резюме ушёл.
    Summarizer held(
      String text, {
      required Completer<void> started,
      required Completer<void> release,
    }) => (request, cancel) async {
      if (!started.isCompleted) {
        started.complete();
      }
      await release.future;
      return summaryOf(text);
    };

    Future<void> pump() async {
      for (var i = 0; i < 40; i++) {
        await Future<void>.value();
      }
    }

    for (final (name, build) in stateRecords) {
      test('$name during the summary stays on the active branch', () async {
        // Контрольный прогон без смены: те же числа.
        await journal(twoTurns());
        LlmContextProjection? controlRebuilt;
        final control =
            await run(fixed('summary'), onCompacted: (p) => controlRebuilt = p)
                as Compacted;

        await journal(twoTurns());
        final leafBefore = writer.snapshot.leafId;
        final started = Completer<void>();
        final release = Completer<void>();
        LlmContextProjection? rebuilt;
        final future = run(
          held('summary', started: started, release: release),
          onCompacted: (p) => rebuilt = p,
        );
        await started.future;
        final change = await writer.append(
          (id, parent, at) => build(id, parent),
        );
        release.complete();
        final outcome = await future as Compacted;

        expect(change.parentId, leafBefore);
        expect(outcome.record.parentId, change.id);
        expect(writer.snapshot.leafId, outcome.record.id);
        expect(
          pathToLeaf(writer.snapshot).map((r) => r.id),
          containsAllInOrder([change.id, outcome.record.id]),
        );
        expect(outcome.tokensBefore, control.tokensBefore);
        expect(outcome.tokensAfter, control.tokensAfter);
        expect(outcome.record.firstKeptId, control.record.firstKeptId);
        expect(outcome.record.summary, control.record.summary);
        // Сообщения после перестроения те же, что без смены: записи
        // состояния не меняют контекст модели.
        expect(rebuilt!.messages, hasLength(controlRebuilt!.messages.length));
        expect(
          [for (final m in rebuilt!.messages) m.toJson()],
          [for (final m in controlRebuilt!.messages) m.toJson()],
        );
        expect(
          writer.snapshot.records.map((r) => r.id).toSet(),
          hasLength(writer.snapshot.records.length),
        );
      });
    }

    test('a message during the summary is stale: nothing is written', () async {
      await journal(twoTurns());
      final started = Completer<void>();
      final release = Completer<void>();
      var rebuilt = 0;
      final future = run(
        held('secret summary', started: started, release: release),
        onCompacted: (_) => rebuilt++,
      );
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

      expect(outcome, isA<NothingToCompact>());
      expect((outcome as NothingToCompact).reason, 'stale');
      expect(writer.snapshot.records.whereType<CompactionRecord>(), isEmpty);
      expect(events.whereType<ContextCompacted>(), isEmpty);
      expect(rebuilt, 0);
      final skipped = logger.eventsOf('compaction.skipped').single;
      expect(skipped.level, LogLevel.warning);
      expect(skipped.fields['session_id'], sid.value);
      expect(skipped.fields['trigger'], 'afterTurn');
      expect(skipped.fields['pass'], 1);
      expect(skipped.fields['reason'], 'stale');
      expect(skipped.fields['blocking_type'], 'message');
      expect(skipped.toString(), isNot(contains('secret summary')));
    });

    test('an unknown record kind is stale too (fail-closed)', () async {
      await journal(twoTurns());
      final started = Completer<void>();
      final release = Completer<void>();
      final future = run(held('s', started: started, release: release));
      await started.future;
      await writer.append(
        (id, parent, at) => CustomRecord(
          id: id,
          parentId: parent,
          timestamp: at,
          customType: 'host',
        ),
      );
      release.complete();

      final outcome = await future;

      expect((outcome as NothingToCompact).reason, 'stale');
      expect(writer.snapshot.records.whereType<CompactionRecord>(), isEmpty);
      expect(
        logger.eventsOf('compaction.skipped').single.fields['blocking_type'],
        'custom',
      );
    });

    test('a record id taken during the summary gets a new id', () async {
      await journal(twoTurns());
      final started = Completer<void>();
      final release = Completer<void>();
      final future = run(held('s', started: started, release: release));
      await started.future;
      final change = await writer.append(
        (id, parent, at) => ModeChangeRecord(
          id: id,
          parentId: parent,
          timestamp: at,
          modeId: 'plan',
        ),
      );
      // Предусловие: id записи сжатия (первый id генератора компактора) уже
      // занят записью состояния.
      expect(change.id, '00000001');
      release.complete();

      final record = (await future as Compacted).record;

      expect(record.id, isNot(change.id));
      expect(record.parentId, change.id);
      expect(
        writer.snapshot.records.map((r) => r.id).toSet(),
        hasLength(writer.snapshot.records.length),
      );
    });

    test('a parentId cycle on the way to the start leaf is stale, not a '
        'hang', () async {
      await journal(twoTurns());
      final started = Completer<void>();
      final release = Completer<void>();
      final future = run(held('s', started: started, release: release));
      await started.future;
      ModeChangeRecord loop(String id, String parent) => ModeChangeRecord(
        id: id,
        parentId: parent,
        timestamp: DateTime.utc(2026),
        modeId: 'plan',
      );
      await writer.appendBuilt(loop('x', 'y'));
      await writer.appendBuilt(loop('y', 'x'));
      release.complete();

      final outcome = await future;

      expect((outcome as NothingToCompact).reason, 'stale');
      expect(
        logger.eventsOf('compaction.skipped').single.fields['blocking_type'],
        'missing',
      );
    });

    test('stale on the second pass keeps the first Compacted', () async {
      await journal(longChain());
      final started = Completer<void>();
      final release = Completer<void>();
      var calls = 0;

      final future = run((request, cancel) async {
        calls++;
        if (calls == 1) {
          return summaryOf('x' * 400);
        }
        started.complete();
        await release.future;
        return summaryOf('y' * 40);
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

      expect(outcome, isA<Compacted>());
      expect(
        writer.snapshot.records.whereType<CompactionRecord>(),
        hasLength(1),
      );
      final skipped = logger.eventsOf('compaction.skipped').single.fields;
      expect(skipped['pass'], 2);
      expect(skipped['reason'], 'stale');
      expect(skipped['blocking_type'], 'message');
    });

    test('cancel while the record waits in the queue writes nothing '
        '(CMP-3, CMP-4)', () async {
      await journal(twoTurns());
      final source = CancelTokenSource();
      final gate = Completer<void>();
      store.appendGate = gate.future;
      // Смена режима держит очередь писателя на хранилище.
      final change = writer.append(
        (id, parent, at) => ModeChangeRecord(
          id: id,
          parentId: parent,
          timestamp: at,
          modeId: 'plan',
        ),
      );
      final summarized = Completer<void>();
      final future = run((request, cancel) async {
        summarized.complete();
        return summaryOf('summary');
      }, cancel: source.token);
      final outcome = expectLater(future, throwsA(isA<CancelledException>()));
      await summarized.future;
      await pump();
      // Предусловие: резюме готово, смена держит очередь на хранилище, записи
      // сжатия нет; отмена срабатывает уже в построителе после отпускания.
      expect(store.waiting, 1);
      expect(writer.snapshot.records.whereType<CompactionRecord>(), isEmpty);
      source.cancel(const UserCancel());
      gate.complete();
      await change;

      await outcome;
      expect(writer.snapshot.records.whereType<CompactionRecord>(), isEmpty);
      expect(events.whereType<ContextCompacted>(), isEmpty);
      // Отмена в очереди писателя — вне учёта (R3, Q5 (а)): записи учёта нет.
      expect(writer.snapshot.records.whereType<CustomRecord>(), isEmpty);
    });
  });
}

/// `customType` записи учёта отброшенного прохода (change
/// `fix-discarded-compaction-usage`, D1). Константы ядра ещё нет (красная
/// фаза), поэтому тест держит литерал: он же фиксирует формат журнала.
const _discardedType = 'codelab.compaction_discarded';

/// Сообщения контекста модели по снимку писателя в JSON: сравнение «до» и
/// «после» не зависит от идентичности объектов.
List<Map<String, Object?>> _context(SessionWriter writer) => [
  for (final m in buildLlmContext(writer.snapshot).messages) m.toJson(),
];

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
