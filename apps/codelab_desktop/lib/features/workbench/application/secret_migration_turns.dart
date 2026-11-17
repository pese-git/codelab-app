import 'package:codelab_client_core/codelab_client_core.dart'
    show SessionStatusView, WorkspaceState;

/// Идёт ли ход хотя бы в одной сессии рабочего места.
///
/// Почему не только активная сессия: `Restart agent` переподключает агента, а
/// это обрывает любой идущий ход — и фоновый в неактивной сессии тоже
/// (design.md change `add-config-literal-secrets-and-migrate`, D8, п. 5).
///
/// Для чего: источник признака «ход идёт» для `SecretMigrationCubit`;
/// `WorkspaceState.sessions` — статусы всех сессий проекта (`running`,
/// `cancelling` — сессия занята).
bool anyTurnRunning(WorkspaceState state) => state.sessions.any(
  (session) =>
      session.status == SessionStatusView.running ||
      session.status == SessionStatusView.cancelling,
);

/// Поток «ход идёт»: сначала значение по [initial], затем его смены по
/// [states]. Первое событие нужно, чтобы Cubit, созданный посреди хода, не
/// считал `Restart agent` доступной.
Stream<bool> turnActivityOf(
  WorkspaceState initial,
  Stream<WorkspaceState> states,
) {
  Stream<bool> values() async* {
    yield anyTurnRunning(initial);
    yield* states.map(anyTurnRunning);
  }

  // `distinct` поверх всего потока: первое событие не дублируется, если
  // следующее состояние рабочего места даёт то же значение.
  return values().distinct();
}
