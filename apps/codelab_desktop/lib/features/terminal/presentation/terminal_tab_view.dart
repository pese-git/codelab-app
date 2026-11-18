import 'package:codelab_ui/codelab_ui.dart';

import '../../../core/platform/user_shell_launcher.dart'
    show UserShellStartFailure;
import '../../../l10n/app_localizations.dart';
import '../application/terminal_tab.dart';

/// Превращает состояние вкладки в готовые строки и тон тега статуса.
///
/// Почему отдельная функция: `CodeLabTerminalPane` в ките не знает про
/// `TerminalTabStatus` (`codelab_ui/AGENTS.md` §1), а подпись и тон — это
/// отображение, а не политика (`add-integrated-terminal`, D3).
///
/// Как использовать: панель зовёт её на каждую вкладку состояния Cubit.
/// Текст ошибки старта не показывается: берётся только вариант
/// `UserShellStartFailure`, без путей (D9), и подпись по каталогу [l10n]
/// (`add-desktop-localization`, D5 п. 4: текст собирает presentation).
CodeLabTerminalTab terminalTabViewOf(TerminalTab tab, AppLocalizations l10n) {
  final (label, tone) = switch (tab.status) {
    TerminalTabStarting() => (l10n.terminalStatusStarting, CodeLabTone.neutral),
    TerminalTabRunning() => (l10n.terminalStatusRunning, CodeLabTone.success),
    TerminalTabExited(:final exitCode) when exitCode == 0 => (
      l10n.terminalStatusExitedWithCode(0),
      CodeLabTone.neutral,
    ),
    TerminalTabExited(:final exitCode) when exitCode != null => (
      l10n.terminalStatusExitedWithCode(exitCode),
      CodeLabTone.warning,
    ),
    TerminalTabExited() => (l10n.terminalStatusExited, CodeLabTone.neutral),
    TerminalTabFailed(:final reason) => (
      switch (reason) {
        UserShellStartFailure.shellNotFound =>
          l10n.terminalFailureShellNotFound,
        UserShellStartFailure.folderNotFound =>
          l10n.terminalFailureFolderNotFound,
        UserShellStartFailure.ptyUnavailable => l10n.terminalFailureUnavailable,
      },
      CodeLabTone.danger,
    ),
  };
  return CodeLabTerminalTab(
    id: tab.id,
    title: l10n.terminalTabTitle(tab.number),
    statusLabel: label,
    statusTone: tone,
  );
}
