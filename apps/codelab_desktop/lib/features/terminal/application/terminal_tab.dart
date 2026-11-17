import '../../../core/platform/user_shell_launcher.dart';

/// Статус вкладки терминала: закрытая иерархия вместо набора флагов
/// (`AGENTS.md` §8; `add-integrated-terminal`, D3).
///
/// Для чего: невозможные сочетания («запускается и вышла») непредставимы;
/// presentation сопоставляет статус с подписью и тоном тега через `switch`.
sealed class TerminalTabStatus {
  const TerminalTabStatus();
}

/// Процесс запускается (`start` ещё не вернулся).
final class TerminalTabStarting extends TerminalTabStatus {
  const TerminalTabStarting();

  @override
  bool operator ==(Object other) => other is TerminalTabStarting;

  @override
  int get hashCode => (TerminalTabStarting).hashCode;
}

/// Процесс работает.
final class TerminalTabRunning extends TerminalTabStatus {
  const TerminalTabRunning();

  @override
  bool operator ==(Object other) => other is TerminalTabRunning;

  @override
  int get hashCode => (TerminalTabRunning).hashCode;
}

/// Процесс вышел сам. [exitCode] `null` — код неизвестен (D4, «Код выхода»).
final class TerminalTabExited extends TerminalTabStatus {
  const TerminalTabExited(this.exitCode);

  final int? exitCode;

  @override
  bool operator ==(Object other) =>
      other is TerminalTabExited && other.exitCode == exitCode;

  @override
  int get hashCode => Object.hash(TerminalTabExited, exitCode);
}

/// Процесс не запустился; [reason] — вариант без путей и текста пакета.
final class TerminalTabFailed extends TerminalTabStatus {
  const TerminalTabFailed(this.reason);

  final UserShellStartFailure reason;

  @override
  bool operator ==(Object other) =>
      other is TerminalTabFailed && other.reason == reason;

  @override
  int get hashCode => Object.hash(TerminalTabFailed, reason);
}

/// Вкладка в состоянии: идентификатор, заголовок и статус.
///
/// Процесс и модель эмулятора здесь не лежат — они в реестре Cubit (D3);
/// модель для виджета отдаёт `TerminalTabsCubit.terminalOf(id)`.
final class TerminalTab {
  const TerminalTab({
    required this.id,
    required this.title,
    required this.status,
  });

  final String id;
  final String title;
  final TerminalTabStatus status;

  TerminalTab withStatus(TerminalTabStatus status) =>
      TerminalTab(id: id, title: title, status: status);

  @override
  bool operator ==(Object other) =>
      other is TerminalTab &&
      other.id == id &&
      other.title == title &&
      other.status == status;

  @override
  int get hashCode => Object.hash(id, title, status);
}
