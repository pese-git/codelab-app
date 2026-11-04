// Признак «ход идёт» для `Restart agent` (change
// `add-config-literal-secrets-and-migrate`, D8, п. 5): учитываются все
// сессии рабочего места, а не только активная.

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart'
    show SessionStatusView, SessionSummaryView, WorkspaceState;
import 'package:codelab_desktop/features/workbench/application/secret_migration_turns.dart';
import 'package:flutter_test/flutter_test.dart';

WorkspaceState _workspace(
  Map<String, SessionStatusView> statuses, {
  String? active,
}) => WorkspaceState(
  activeSessionId: active == null ? null : SessionId(active),
  sessions: [
    for (final entry in statuses.entries)
      SessionSummaryView(
        id: SessionId(entry.key),
        cwd: '/work/app',
        status: entry.value,
      ),
  ],
);

void main() {
  test('ход в неактивной сессии считается идущим', () {
    final state = _workspace({
      'a': SessionStatusView.idle,
      'b': SessionStatusView.running,
    }, active: 'a');
    expect(anyTurnRunning(state), isTrue);
  });

  test('cancelling тоже занимает сессию', () {
    expect(
      anyTurnRunning(_workspace({'a': SessionStatusView.cancelling})),
      isTrue,
    );
  });

  test('idle, failed, notLoaded и detached ход не считаются', () {
    expect(
      anyTurnRunning(
        _workspace({
          'a': SessionStatusView.idle,
          'b': SessionStatusView.failed,
          'c': SessionStatusView.notLoaded,
          'd': SessionStatusView.detached,
        }),
      ),
      isFalse,
    );
    expect(anyTurnRunning(const WorkspaceState()), isFalse);
  });

  test('поток: начальное значение первым, затем только смены', () async {
    final states = StreamController<WorkspaceState>();
    final seen = <bool>[];
    final sub = turnActivityOf(
      _workspace({'a': SessionStatusView.running}),
      states.stream,
    ).listen(seen.add);

    states
      ..add(_workspace({'a': SessionStatusView.running}))
      ..add(_workspace({'a': SessionStatusView.idle}))
      ..add(
        _workspace({
          'a': SessionStatusView.idle,
          'b': SessionStatusView.running,
        }),
      );
    await pumpEventQueue();

    expect(seen, [true, false, true]);
    await sub.cancel();
    await states.close();
  });
}
