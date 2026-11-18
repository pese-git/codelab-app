// Красные тесты правок ревью change `add-desktop-usage-pane` (D3, D5, D13):
// события `usage_pane.export` и `usage_pane.refresh`, результат порта
// `UsageCsvSaver` с классом ошибки и кэш подписей шагов в
// `ActiveSessionCubit`.
//
// Cubit собирается на двойниках сессии и рабочего пространства (как
// `ledger_refresh_test.dart`), логгер — `RecordingLogger`. Проверяются
// точные наборы полей: путь, подписи шагов и хода, токены и деньги в
// запись попасть не должны (`AGENTS.md` §16, D13).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show SessionId, ToolCallId, ToolKind;
import 'package:codelab_client_acp/codelab_client_acp.dart' show AcpSession;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/usage_csv_saver.dart';
import 'package:codelab_desktop/features/workbench/application/active_session_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_usage_csv_saver.dart';
import '../../../support/recording_logger.dart';

const _tokens = TokenCounts(
  input: 100,
  output: 20,
  cacheRead: 0,
  cacheWrite: 0,
);

final class _Handle extends Fake implements SessionHandle {
  _Handle(String id, this._current) : id = SessionId(id);

  @override
  final SessionId id;

  SessionView _current;
  final StreamController<SessionView> _view =
      StreamController<SessionView>.broadcast(sync: true);

  @override
  SessionView get current => _current;

  @override
  Stream<SessionView> get view => _view.stream;

  void emit(SessionView next) {
    _current = next;
    _view.add(next);
  }
}

final class _Workspace extends Fake implements ClientWorkspace {
  final Map<String, _Handle> handles = {};

  @override
  SessionHandle? session(SessionId id) => handles[id.value];

  @override
  Stream<PromptOutcome> get promptOutcomes => const Stream.empty();

  @override
  Future<void> refreshUsageLedger(SessionId id, {bool rebuild = false}) async {}
}

/// Порт, бросающий исключение вместо результата.
final class _ThrowingSaver implements UsageCsvSaver {
  @override
  Future<UsageCsvSaveResult> save({
    required String suggestedName,
    required String csv,
  }) async => throw const FormatException('/secret/path/out.csv');
}

ToolCallItem _call(String path) => ToolCallItem(
  id: 'tool-t1',
  toolCallId: const ToolCallId('t1'),
  title: 'Read',
  details: ToolCallView(
    kind: ToolKind.read,
    status: ToolCallStatusView.succeeded,
    rawInput: {'path': path},
  ),
);

UsageLedgerView _ledger() => UsageLedgerView(
  sessionId: const SessionId('s1'),
  seq: 10,
  total: const UsageTotals(
    tokens: _tokens,
    cost: Money(micros: 41, currency: 'USD'),
    steps: 2,
  ),
  turnCount: 1,
  turns: [
    UsageLedgerTurn(
      index: 1,
      title: 'Secret title',
      total: const UsageTotals(tokens: _tokens, steps: 2),
      steps: const [
        UsageLedgerStep(index: 0, tokens: _tokens, toolCallIds: ['t1']),
        UsageLedgerStep(index: 1, tokens: _tokens),
      ],
    ),
  ],
);

final _loaded = UsageLedgerState.loaded(_ledger());

SessionView _view(
  int revision, {
  UsageLedgerState? ledger,
  List<TranscriptItem> transcript = const [],
  int lastSeq = 10,
}) => SessionView(
  revision: revision,
  status: SessionStatusView.idle,
  usage: UsageView(support: UsageSupport.reported, lastSeq: lastSeq),
  usageLedger: ledger ?? _loaded,
  transcript: transcript,
);

AcpSession _session(String id) => AcpSession(id: SessionId(id), cwd: '/work');

void main() {
  late _Workspace workspace;
  late _Handle a;
  late RecordingLogger logger;
  late FakeUsageCsvSaver saver;
  late ActiveSessionCubit cubit;

  ActiveSessionCubit open(UsageCsvSaver port) => ActiveSessionCubit(
    changes: ShellChanges(),
    workspace: workspace,
    diagnostics: ShellDiagnostics(),
    usageCsvSaver: port,
    usageLogger: logger,
  );

  setUp(() {
    workspace = _Workspace();
    a = workspace.handles['a'] = _Handle('a', _view(1));
    logger = RecordingLogger();
    saver = FakeUsageCsvSaver();
    cubit = open(saver)..show(_session('a'));
  });

  tearDown(() => cubit.close());

  List<Map<String, Object?>> events(String name) => [
    for (final e in logger.entries)
      if (e['event'] == name) e,
  ];

  group('usage_pane.export (D13)', () {
    test(
      'saved: outcome, turns и steps; ни пути, ни подписей, ни денег',
      () async {
        final result = await cubit.exportUsageCsv();

        expect(result, isA<UsageCsvSaved>());
        expect(events('usage_pane.export'), [
          {
            'event': 'usage_pane.export',
            'level': 'info',
            'outcome': 'saved',
            'turns': 1,
            'steps': 2,
          },
        ]);
      },
    );

    test('cancelled: событие с outcome cancelled (отказ в диалоге)', () async {
      saver.result = const UsageCsvCancelled();

      final result = await cubit.exportUsageCsv();

      expect(result, isA<UsageCsvCancelled>());
      final event = events('usage_pane.export').single;
      expect(event['outcome'], 'cancelled');
      expect(event.containsKey('error_class'), isFalse);
    });

    test(
      'failed: error_class — класс из результата порта, без текста',
      () async {
        saver.result = const UsageCsvFailed('FileSystemException');

        final result = await cubit.exportUsageCsv();

        expect(result, isA<UsageCsvFailed>());
        final event = events('usage_pane.export').single;
        expect(event['outcome'], 'failed');
        expect(event['error_class'], 'FileSystemException');
        expect(event.values.whereType<String>().join(), isNot(contains('/')));
      },
    );

    test(
      'порт бросил исключение: failed и runtimeType, без сообщения',
      () async {
        await cubit.close();
        cubit = open(_ThrowingSaver())..show(_session('a'));

        final result = await cubit.exportUsageCsv();

        expect(result, isA<UsageCsvFailed>());
        final event = events('usage_pane.export').single;
        expect(event['outcome'], 'failed');
        expect(event['error_class'], 'FormatException');
        expect(event.toString(), isNot(contains('secret')));
      },
    );

    test('нечего экспортировать: порт не вызывается, события нет', () async {
      await cubit.close();
      cubit = open(saver);

      await cubit.exportUsageCsv();

      expect(saver.saved, isEmpty);
      expect(events('usage_pane.export'), isEmpty);
    });
  });

  group('usage_pane.refresh (D3, D13)', () {
    test('показ, автообновление, Retry и Rebuild: только session_id, '
        'rebuild и reason', () async {
      a.emit(_view(2, ledger: const UsageLedgerState.idle()));
      cubit.usagePaneShown(true);
      a.emit(
        _view(
          3,
          lastSeq: 11,
          ledger: UsageLedgerState.loaded(
            UsageLedgerView(
              sessionId: const SessionId('s1'),
              seq: 5,
              total: const UsageTotals(tokens: _tokens),
            ),
          ),
        ),
      );
      await pumpEventQueue();
      await cubit.refreshUsageLedger();
      await cubit.refreshUsageLedger(rebuild: true);

      final refresh = events('usage_pane.refresh');
      expect(
        [for (final e in refresh) e['reason']],
        ['shown', 'seq', 'retry', 'manual'],
      );
      for (final e in refresh) {
        expect(e.keys.toSet(), {
          'event',
          'level',
          'session_id',
          'rebuild',
          'reason',
        });
        expect(e['session_id'], 'a');
      }
      expect(
        [for (final e in refresh) e['rebuild']],
        [false, false, false, true],
      );
    });
  });

  group('кэш подписей шагов (D4)', () {
    test('tool_call_update с новым title/входом без новой записи ленты '
        'обновляет подпись шага', () {
      a.emit(_view(2, transcript: [_call('lib/a.dart')]));
      cubit.show(_session('a'));
      final before = cubit.state.usage.turns.single.steps.first.title;
      expect(before, contains('a.dart'));

      // Ревизия с теми же usage и журналом (идентичные объекты) и ленты той
      // же длины: изменился только вызов.
      a.emit(
        a.current.copyWith(revision: 3, transcript: [_call('lib/b.dart')]),
      );

      expect(
        cubit.state.usage.turns.single.steps.first.title,
        contains('b.dart'),
      );
    });

    test('ничего не менялось: данные панели — тот же объект', () {
      final call = _call('lib/a.dart');
      a.emit(_view(2, transcript: [call]));
      cubit.show(_session('a'));
      final before = cubit.state.usage;

      a.emit(a.current.copyWith(revision: 3, transcript: [call]));

      expect(cubit.state.usage, same(before));
    });
  });
}
