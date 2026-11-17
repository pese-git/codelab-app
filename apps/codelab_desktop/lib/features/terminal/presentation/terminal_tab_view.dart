import 'package:codelab_ui/codelab_ui.dart';

import '../application/terminal_tab.dart';

/// Превращает состояние вкладки в готовые строки и тон тега статуса.
///
/// Почему отдельная функция: `CodeLabTerminalPane` в ките не знает про
/// `TerminalTabStatus` (`codelab_ui/AGENTS.md` §1), а подпись и тон — это
/// отображение, а не политика (`add-integrated-terminal`, D3).
///
/// Как использовать: панель зовёт её на каждую вкладку состояния Cubit.
/// Текст ошибки старта не показывается: берётся только вариант
/// `UserShellStartFailure.message`, без путей (D9).
CodeLabTerminalTab terminalTabViewOf(TerminalTab tab) {
  final (label, tone) = switch (tab.status) {
    TerminalTabStarting() => ('Starting', CodeLabTone.neutral),
    TerminalTabRunning() => ('Running', CodeLabTone.success),
    TerminalTabExited(:final exitCode) when exitCode == 0 => (
      'Exited 0',
      CodeLabTone.neutral,
    ),
    TerminalTabExited(:final exitCode) when exitCode != null => (
      'Exited $exitCode',
      CodeLabTone.warning,
    ),
    TerminalTabExited() => ('Exited', CodeLabTone.neutral),
    TerminalTabFailed(:final reason) => (reason.message, CodeLabTone.danger),
  };
  return CodeLabTerminalTab(
    id: tab.id,
    title: tab.title,
    statusLabel: label,
    statusTone: tone,
  );
}
