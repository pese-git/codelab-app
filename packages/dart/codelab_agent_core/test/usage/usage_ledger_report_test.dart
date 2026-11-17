import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart';
import '../permissions/fake_gate.dart';

/// Отчёт журнала usage и файл `usage.json` на фейковом порту в памяти
/// (agent-sessions «Файл usage.json и порт UsageLedgerStore»; design.md
/// change `add-usage-ledger`, D3, D12). Задача 1.2.
///
/// Сессия — настоящая, ходы — по `ScriptedStreamFunction`; порт —
/// `_FakeStore` с записью обращений и воротами записи, чтобы проверять
/// параллельность без `Future.delayed` (PKG-6).
void main() {
  late _FakeStore store;
  late CoreHarness h;
  late AgentSession session;

  Map<String, Object?> answer(String text, int input) => {
    'reply': [
      {'text': text},
    ],
    'usage': {
      'input': input,
      'output': 5,
      'cost': {'input': 0.001},
    },
  };

  /// Сессия с [turns] завершёнными ходами; [withStore] `false` — без порта.
  Future<void> open({int turns = 2, bool withStore = true}) async {
    store = _FakeStore();
    h = CoreHarness.build(
      baseEnv: MemoryExecutionEnv(cwd: '/proj'),
      narrow: noExec,
      gate: FakeGate(),
      usageLedger: withStore ? store : null,
      steps: [for (var i = 0; i < 6; i++) answer('answer $i', 100 + i)],
    );
    session = await h.core.runtime.createSession(SessionSpec(cwd: '/proj'));
    for (var i = 0; i < turns; i++) {
      await session.prompt([TextContent('task $i')]);
    }
  }

  tearDown(() async => h.core.runtime.dispose());

  test('no file: rebuilt with the reason missing, and the file is written '
      '(byte for byte the serialization)', () async {
    await open();

    final report = await session.usageLedger();

    expect(report.state, UsageLedgerFileState.rebuilt);
    expect(report.reason, UsageLedgerRebuildReason.missing);
    expect(report.ledger.turns, hasLength(2));
    expect(store.writes, hasLength(1));
    expect(store.files[session.id], report.ledger.serialize());
  });

  test('a repeat call: upToDate, no write', () async {
    await open();
    await session.usageLedger();

    final report = await session.usageLedger();

    expect(report.state, UsageLedgerFileState.upToDate);
    expect(report.reason, isNull);
    expect(store.writes, hasLength(1));
    expect(report.ledger.turns, hasLength(2));
  });

  test('a record appended after the write: stale, the file is replaced, '
      'source.records grows', () async {
    await open();
    final first = await session.usageLedger();
    await session.prompt([const TextContent('one more')]);

    final report = await session.usageLedger();

    expect(report.state, UsageLedgerFileState.rebuilt);
    expect(report.reason, UsageLedgerRebuildReason.stale);
    expect(report.ledger.records, greaterThan(first.ledger.records));
    expect(report.ledger.turns, hasLength(3));
    expect(store.writes, hasLength(2));
  });

  test('the same records count but another lastRecordId: stale (a replaced '
      'record, D3)', () async {
    await open();
    final first = await session.usageLedger();
    final last = first.ledger.lastRecordId!;
    final text = store.files[session.id]!;
    expect(text, contains('"lastRecordId":"$last"'));
    store.files[session.id] = text.replaceFirst(
      '"lastRecordId":"$last"',
      '"lastRecordId":"other-record"',
    );

    final report = await session.usageLedger();

    expect(report.state, UsageLedgerFileState.rebuilt);
    expect(report.reason, UsageLedgerRebuildReason.stale);
    expect(store.files[session.id], first.ledger.serialize());
  });

  test('a broken JSON file: invalid', () async {
    await open();
    store.files[session.id] = 'this is not json';

    final report = await session.usageLedger();

    expect(report.state, UsageLedgerFileState.rebuilt);
    expect(report.reason, UsageLedgerRebuildReason.invalid);
    expect(store.files[session.id], report.ledger.serialize());
  });

  test('version 2: invalid', () async {
    await open();
    store.files[session.id] = '{"version":2}\n';

    final report = await session.usageLedger();

    expect(report.reason, UsageLedgerRebuildReason.invalid);
  });

  test('rebuild: true recomputes a fresh file: explicit', () async {
    await open();
    await session.usageLedger();

    final report = await session.usageLedger(rebuild: true);

    expect(report.state, UsageLedgerFileState.rebuilt);
    expect(report.reason, UsageLedgerRebuildReason.explicit);
    expect(store.writes, hasLength(2));
    expect(store.writes.last, store.writes.first);
  });

  test('a failed write: notSaved with the reason, the warning, the report '
      'still given, the journal unchanged', () async {
    await open();
    final journal = (h.sessions as MemorySessionStore).textOf(session.id);
    store.failWith = const UsageLedgerStoreException('Permission denied');

    final report = await session.usageLedger();

    expect(report.state, UsageLedgerFileState.notSaved);
    expect(report.saveError, 'Permission denied');
    expect(report.ledger.turns, hasLength(2));
    final warning = h.logger.eventsOf('usage.ledger.write_failed').single;
    expect(warning.level, LogLevel.warning);
    expect(warning.fields['session_id'], session.id.value);
    expect(warning.fields['reason'], 'Permission denied');
    expect((h.sessions as MemorySessionStore).textOf(session.id), journal);
  });

  test('no port: inMemory, no access to any store', () async {
    await open(withStore: false);

    final report = await session.usageLedger();

    expect(report.state, UsageLedgerFileState.inMemory);
    expect(report.ledger.turns, hasLength(2));
    expect(store.reads, 0);
    expect(store.writes, isEmpty);
  });

  test('usageLedgerInMemory neither reads nor writes the file (D8)', () async {
    await open();

    final report = await session.usageLedgerInMemory();

    expect(report.state, UsageLedgerFileState.inMemory);
    expect(report.ledger.turns, hasLength(2));
    expect(store.reads, 0);
    expect(store.writes, isEmpty);
  });

  test('two calls at once with no file: one rebuild and one write, the same '
      'ledger for both', () async {
    await open();

    final reports = await Future.wait([
      session.usageLedger(),
      session.usageLedger(),
    ]);

    expect(store.writes, hasLength(1));
    expect(reports[0].ledger.serialize(), reports[1].ledger.serialize());
    expect(reports[0].state, reports[1].state);
    expect(h.logger.eventsOf('usage.ledger.rebuild'), hasLength(1));
  });

  test(
    'rebuild during an ordinary call: one more operation after it',
    () async {
      await open();
      store.gate = Completer<void>();

      final ordinary = session.usageLedger();
      await store.writeStarted;
      final rebuilt = session.usageLedger(rebuild: true);
      await pumpEventQueue();
      // Вторая запись не началась: идёт первая.
      expect(store.writeCalls, 1);

      store.gate!.complete();
      final reports = await Future.wait([ordinary, rebuilt]);

      expect(store.writeCalls, 2);
      expect(reports[0].reason, UsageLedgerRebuildReason.missing);
      expect(reports[1].reason, UsageLedgerRebuildReason.explicit);
    },
  );

  test('close waits for a started write', () async {
    await open();
    store.gate = Completer<void>();
    final pending = session.usageLedger();
    await store.writeStarted;

    var closed = false;
    final closing = session.close().then((_) => closed = true);
    await pumpEventQueue();

    expect(closed, isFalse);
    store.gate!.complete();
    await closing;
    await pending;
    expect(closed, isTrue);
    expect(store.files[session.id], isNotNull);
  });

  test('after close(): the report is in memory, the file is neither read '
      'nor written (D3: close waits for the write that has begun, a new one '
      'does not start)', () async {
    await open();
    await session.close();

    final report = await session.usageLedger();
    final rebuilt = await session.usageLedger(rebuild: true);

    expect(report.state, UsageLedgerFileState.inMemory);
    expect(rebuilt.state, UsageLedgerFileState.inMemory);
    expect(report.ledger.turns, hasLength(2));
    expect(store.reads, 0);
    expect(store.writes, isEmpty);
  });

  test(
    'the log usage.ledger.rebuild has reason, records, duration_ms',
    () async {
      await open();

      final report = await session.usageLedger();

      final log = h.logger.eventsOf('usage.ledger.rebuild').single;
      expect(log.level, LogLevel.info);
      expect(log.fields['session_id'], session.id.value);
      expect(log.fields['reason'], 'missing');
      expect(log.fields['records'], report.ledger.records);
      expect(log.fields['duration_ms'], isA<int>());
    },
  );

  test('a fresh file is not rewritten and the log has no rebuild', () async {
    await open();
    await session.usageLedger();
    final before = h.logger.eventsOf('usage.ledger.rebuild').length;

    await session.usageLedger();

    expect(h.logger.eventsOf('usage.ledger.rebuild'), hasLength(before));
  });

  test('the model without a price in the session catalog is in the report; '
      'the ledger text has no price flag (Q4)', () async {
    await open();

    final report = await session.usageLedger();

    // Модель теста — без цен в каталоге сессии.
    expect(report.noPriceModels, {'test/model-1'});
    expect(report.ledger.serialize(), isNot(contains('noPrice')));
  });
}

/// Порт файла в памяти: обращения, сбой записи и ворота записи для тестов
/// параллельности.
final class _FakeStore implements UsageLedgerStore {
  final files = <SessionId, String>{};
  final writes = <String>[];
  var reads = 0;
  var writeCalls = 0;

  /// Если задан, `write` бросает его.
  UsageLedgerStoreException? failWith;

  /// Если задан, `write` ждёт его завершения до записи.
  Completer<void>? gate;

  final _started = Completer<void>();

  /// Первая запись началась.
  Future<void> get writeStarted => _started.future;

  @override
  Future<String?> read(SessionId id) async {
    reads++;
    return files[id];
  }

  @override
  Future<void> write(SessionId id, String content) async {
    writeCalls++;
    if (!_started.isCompleted) {
      _started.complete();
    }
    await gate?.future;
    if (failWith case final error?) {
      throw error;
    }
    files[id] = content;
    writes.add(content);
  }
}
