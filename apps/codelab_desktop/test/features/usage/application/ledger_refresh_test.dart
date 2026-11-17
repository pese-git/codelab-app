// Красные тесты задачи 1.4 change `add-desktop-usage-pane`: правило
// обновления журнала usage (design.md, D3, Q4; agent-workbench-ui «Панель
// Usage»: «Журнал после хода», «Журнал не догоняет снимки», «Сбой загрузки
// журнала», «Смена сессии в фокусе»).
//
// Две группы. Чистая функция `ledgerRefreshNeeded` проверяется таблицей
// условий. Владелец вызова — `ActiveSessionCubit` (одна подписка на
// `SessionHandle.view`, D1, D3): его тесты идут на двойниках сессии и
// рабочего пространства, как `active_session_status_bar_test.dart`, и
// считают вызовы `refreshUsageLedger`. Опроса по таймеру нет: запрос
// появляется только как следствие показа панели или новой ревизии сессии.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_acp/codelab_client_acp.dart' show AcpSession;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/usage/application/ledger_refresh.dart';
import 'package:codelab_desktop/features/workbench/application/active_session_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:flutter_test/flutter_test.dart';

const _tokens = TokenCounts(input: 1, output: 1, cacheRead: 0, cacheWrite: 0);

UsageLedgerView _ledgerView(int seq, {String session = 'a'}) => UsageLedgerView(
  sessionId: SessionId(session),
  seq: seq,
  total: const UsageTotals(tokens: _tokens),
);

bool _needed({
  bool paneShown = true,
  SessionStatusView status = SessionStatusView.idle,
  UsageLedgerState ledger = const UsageLedgerState.idle(),
  int lastSeq = 10,
  int? requestedForSeq,
}) => ledgerRefreshNeeded(
  paneShown: paneShown,
  status: status,
  ledger: ledger,
  lastSeq: lastSeq,
  requestedForSeq: requestedForSeq,
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

/// Рабочее пространство: считает запросы журнала.
final class _Workspace extends Fake implements ClientWorkspace {
  final Map<String, _Handle> handles = {};
  final List<({String session, bool rebuild})> requests = [];

  @override
  SessionHandle? session(SessionId id) => handles[id.value];

  @override
  Stream<PromptOutcome> get promptOutcomes => const Stream.empty();

  @override
  Future<void> refreshUsageLedger(SessionId id, {bool rebuild = false}) async {
    requests.add((session: id.value, rebuild: rebuild));
  }
}

SessionView _view(
  int revision, {
  SessionStatusView status = SessionStatusView.idle,
  UsageLedgerState ledger = const UsageLedgerState.idle(),
  int lastSeq = 10,
  UsageSupport support = UsageSupport.reported,
}) => SessionView(
  revision: revision,
  status: status,
  usage: UsageView(support: support, lastSeq: lastSeq),
  usageLedger: ledger,
);

AcpSession _session(String id) => AcpSession(id: SessionId(id), cwd: '/work');

void main() {
  group('ledgerRefreshNeeded (D3)', () {
    test('журнал idle, панель показана, сессия свободна — нужен', () {
      expect(_needed(), isTrue);
    });

    test('панель не показана — не нужен', () {
      expect(_needed(paneShown: false), isFalse);
    });

    test('во время хода (running, cancelling) — не нужен', () {
      expect(_needed(status: SessionStatusView.running), isFalse);
      expect(_needed(status: SessionStatusView.cancelling), isFalse);
    });

    test('loaded с seq меньше lastSeq — нужен; с равным и большим — нет', () {
      expect(_needed(ledger: UsageLedgerState.loaded(_ledgerView(7))), isTrue);
      expect(
        _needed(ledger: UsageLedgerState.loaded(_ledgerView(10))),
        isFalse,
      );
      expect(
        _needed(ledger: UsageLedgerState.loaded(_ledgerView(11))),
        isFalse,
      );
    });

    test('loading, failed и unavailable автоматически не повторяются', () {
      expect(_needed(ledger: const UsageLedgerState.loading()), isFalse);
      expect(
        _needed(
          ledger: const UsageLedgerState.failed(
            UsageLedgerFailure(
              kind: UsageLedgerFailureKind.agentError,
              code: -32603,
            ),
          ),
        ),
        isFalse,
      );
      expect(_needed(ledger: const UsageLedgerState.unavailable()), isFalse);
    });

    test('для значения lastSeq запрос уже уходил — не нужен', () {
      expect(_needed(requestedForSeq: 10), isFalse);
      expect(
        _needed(
          ledger: UsageLedgerState.loaded(_ledgerView(9)),
          requestedForSeq: 10,
        ),
        isFalse,
      );
    });

    test('новый lastSeq снова открывает один запрос', () {
      expect(
        _needed(
          ledger: UsageLedgerState.loaded(_ledgerView(9)),
          lastSeq: 11,
          requestedForSeq: 10,
        ),
        isTrue,
      );
    });
  });

  group('ActiveSessionCubit владеет обновлением журнала (D1, D3)', () {
    late _Workspace workspace;
    late ActiveSessionCubit cubit;
    late _Handle a;
    late _Handle b;

    setUp(() {
      workspace = _Workspace();
      a = workspace.handles['a'] = _Handle('a', _view(1));
      b = workspace.handles['b'] = _Handle('b', _view(1));
      cubit = ActiveSessionCubit(
        changes: ShellChanges(),
        workspace: workspace,
        diagnostics: ShellDiagnostics(),
      );
    });

    tearDown(() => cubit.close());

    test('показ панели запускает один запрос без rebuild', () {
      cubit.show(_session('a'));
      expect(workspace.requests, isEmpty, reason: 'панель ещё не показана');

      cubit.usagePaneShown(true);

      expect(workspace.requests, [(session: 'a', rebuild: false)]);
    });

    test('скрытая панель запросов не делает', () {
      cubit.show(_session('a'));

      a.emit(_view(2, lastSeq: 11));

      expect(workspace.requests, isEmpty);
    });

    test('после скрытия панели новые снимки не запрашивают журнал', () {
      cubit.show(_session('a'));
      cubit.usagePaneShown(true);
      cubit.usagePaneShown(false);
      workspace.requests.clear();

      a.emit(_view(2, lastSeq: 12));

      expect(workspace.requests, isEmpty);
    });

    test('журнал загружен (seq 7), ход идёт и завершается: ровно один '
        'запрос после перехода в idle, во время хода — ни одного', () {
      a.emit(
        _view(2, ledger: UsageLedgerState.loaded(_ledgerView(7)), lastSeq: 7),
      );
      cubit.show(_session('a'));
      cubit.usagePaneShown(true);
      expect(workspace.requests, isEmpty, reason: 'журнал догоняет снимки');

      a.emit(
        _view(
          3,
          status: SessionStatusView.running,
          ledger: UsageLedgerState.loaded(_ledgerView(7)),
          lastSeq: 9,
        ),
      );
      a.emit(
        _view(
          4,
          status: SessionStatusView.running,
          ledger: UsageLedgerState.loaded(_ledgerView(7)),
          lastSeq: 10,
        ),
      );
      expect(workspace.requests, isEmpty, reason: 'во время хода запросов нет');

      a.emit(
        _view(5, ledger: UsageLedgerState.loaded(_ledgerView(7)), lastSeq: 10),
      );

      expect(workspace.requests, [(session: 'a', rebuild: false)]);
    });

    test('журнал не догоняет снимки: второй запрос для того же lastSeq не '
        'уходит, новый снимок открывает следующий', () {
      cubit.show(_session('a'));
      cubit.usagePaneShown(true);
      expect(workspace.requests, hasLength(1));

      // Агент ответил журналом с seq 9 при lastSeq 10.
      a.emit(
        _view(2, ledger: UsageLedgerState.loaded(_ledgerView(9)), lastSeq: 10),
      );
      a.emit(
        _view(3, ledger: UsageLedgerState.loaded(_ledgerView(9)), lastSeq: 10),
      );
      expect(workspace.requests, hasLength(1));

      a.emit(
        _view(4, ledger: UsageLedgerState.loaded(_ledgerView(9)), lastSeq: 11),
      );

      expect(workspace.requests, hasLength(2));
    });

    test('сбой загрузки не повторяется автоматически', () {
      cubit.show(_session('a'));
      cubit.usagePaneShown(true);
      workspace.requests.clear();

      a.emit(
        _view(
          2,
          ledger: const UsageLedgerState.failed(
            UsageLedgerFailure(
              kind: UsageLedgerFailureKind.agentError,
              code: -32603,
            ),
          ),
        ),
      );
      a.emit(
        _view(
          3,
          ledger: const UsageLedgerState.failed(
            UsageLedgerFailure(
              kind: UsageLedgerFailureKind.agentError,
              code: -32603,
            ),
          ),
        ),
      );

      expect(workspace.requests, isEmpty);
    });

    test('агент без журнала: запросов нет даже при показанной панели', () {
      a.emit(_view(2, ledger: const UsageLedgerState.unavailable()));
      cubit.show(_session('a'));

      cubit.usagePaneShown(true);

      expect(workspace.requests, isEmpty);
    });

    test('смена сессии в фокусе: данные панели — сессии B, запрос уходит '
        'для B, поздняя ревизия A ничего не меняет', () {
      cubit.show(_session('a'));
      cubit.usagePaneShown(true);
      workspace.requests.clear();

      cubit.show(_session('b'));

      expect(workspace.requests, [(session: 'b', rebuild: false)]);
      expect(cubit.state.sessionId, 'b');
      final before = cubit.state.usage;

      a.emit(_view(2, lastSeq: 99));

      expect(cubit.state.usage, same(before));
      expect(workspace.requests, hasLength(1));
      expect(b.id.value, 'b');
    });
  });
}
