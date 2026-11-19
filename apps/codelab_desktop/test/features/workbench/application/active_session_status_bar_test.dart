// Тесты подписки `ActiveSessionCubit` на `SessionHandle.view` (change
// `add-usage-extension`, D23 Т1; AGENTS.md §9: у долгоживущей подписки есть
// владелец, переподписка не плодит дубликаты, поздние события старой сессии
// не меняют актуальное состояние, подписка отменяется в `close()`).
//
// Сессии и рабочее пространство — двойники: нужен только поток `view`
// каждой сессии, настоящий транспорт не требуется.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_acp/codelab_client_acp.dart' show AcpSession;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/workbench/application/active_session_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_part.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/app_strings.dart';
import '../../../support/fake_usage_csv_saver.dart';

/// Сессия с управляемым потоком `view`; `emit` публикует новую ревизию.
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

  bool get hasListener => _view.hasListener;

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
}

SessionView _view(int revision, {String model = 'gpt-5'}) => SessionView(
  revision: revision,
  status: SessionStatusView.idle,
  configOptions: [
    ConfigOptionView(
      id: 'model',
      name: 'Model',
      currentValue: model,
      category: 'model',
      values: const [],
    ),
  ],
  usage: const UsageView(),
);

AcpSession _session(String id) => AcpSession(id: SessionId(id), cwd: '/work');

void main() {
  late _Workspace workspace;
  late ActiveSessionCubit cubit;
  late _Handle a;
  late _Handle b;

  setUp(() {
    workspace = _Workspace();
    a = workspace.handles['a'] = _Handle('a', _view(1));
    b = workspace.handles['b'] = _Handle('b', _view(1, model: 'gpt-4'));
    cubit = ActiveSessionCubit(
      changes: ShellChanges(),
      workspace: workspace,
      diagnostics: ShellDiagnostics(),
      usageCsvSaver: FakeUsageCsvSaver(),
      strings: FixedAppStrings(AppLocalizationsEn()),
    );
  });

  test('a new revision of the shown session refreshes the status bar', () {
    cubit.show(_session('a'));
    expect(cubit.state.statusBar?.modelLabel, 'gpt-5');

    a.emit(_view(2, model: 'gpt-6'));

    expect(cubit.state.statusBar?.modelLabel, 'gpt-6');
  });

  test('switching the session resubscribes; a late snapshot of A shown '
      'while B is on screen changes nothing', () {
    cubit.show(_session('a'));
    cubit.show(_session('b'));

    expect(a.hasListener, isFalse);
    expect(b.hasListener, isTrue);
    final before = cubit.state.statusBar;
    expect(before?.modelLabel, 'gpt-4');

    a.emit(_view(2, model: 'late-a'));

    expect(cubit.state.statusBar, before);
    expect(cubit.state.sessionId, 'b');
  });

  test('showing the same session again does not duplicate the '
      'subscription', () async {
    cubit.show(_session('a'));
    cubit.show(_session('a'));

    var emissions = 0;
    final sub = cubit.stream.listen((_) => emissions++);
    a.emit(_view(2, model: 'gpt-6'));
    await pumpEventQueue();
    await sub.cancel();

    expect(emissions, 1);
  });

  test('showMissing cancels the subscription and clears the row', () {
    cubit.show(_session('a'));
    cubit.showMissing('gone');

    expect(a.hasListener, isFalse);
    expect(cubit.state.statusBar, isNull);
  });

  test('close() cancels the subscription to SessionHandle.view', () async {
    cubit.show(_session('a'));
    expect(a.hasListener, isTrue);

    await cubit.close();

    expect(a.hasListener, isFalse);
  });
}
