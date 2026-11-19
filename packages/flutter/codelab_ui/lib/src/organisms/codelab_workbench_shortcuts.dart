import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Сочетания клавиш рабочего места: палитра, новая сессия, настройки, сайдбар,
/// панель Files, переход к одобрению и Esc отмены хода.
///
/// Почему: активаторы берутся из каталога [CodeLabShortcut], а не объявляются
/// здесь литералами, иначе страница «Keyboard» разошлась бы с привязками
/// (change `add-app-keyboard-page`, D3). Параметры одобрения и навигации
/// инспектора (`onApprove`, `onReject`, `onInspectorPrevious`,
/// `onInspectorNext`) удалены: app их не передавал, одобрение привязывает свои
/// клавиши само, а Alt+←/→ зарезервированы за инспектором (DSK-18), но не
/// привязаны (решение пользователя Q2).
///
/// Как использовать: хост передаёт колбэки только для доступных действий;
/// без колбэка сочетание не привязано.
class CodeLabWorkbenchShortcuts extends StatelessWidget {
  const CodeLabWorkbenchShortcuts({
    required this.child,
    this.onOpenCommandPalette,
    this.onCancel,
    this.onNewSession,
    this.onToggleSidebar,
    this.onOpenSettings,
    this.onToggleFiles,
    this.onGoToApproval,
    this.enabled = true,
    super.key,
  });

  final Widget child;

  /// Cmd/Ctrl+K — открыть палитру команд.
  final VoidCallback? onOpenCommandPalette;

  /// Esc — отменить идущий ход (и закрыть палитру, как решает хост).
  final VoidCallback? onCancel;

  /// Cmd/Ctrl+N — новая сессия (A13, шаг 3; change
  /// `redesign-workbench-shell`).
  final VoidCallback? onNewSession;

  /// Cmd/Ctrl+B — свернуть или развернуть сайдбар; что именно, решает хост
  /// по классу раскладки.
  final VoidCallback? onToggleSidebar;

  /// Cmd/Ctrl+, — открыть настройки (spec app-settings «Переход в настройки
  /// и обратно», DSK-24; change `add-app-settings-shell`). Что именно
  /// открывается, решает хост; на экране настроек сочетание не привязывают.
  final VoidCallback? onOpenSettings;

  /// Cmd/Ctrl+Shift+E — открыть или закрыть панель Files (A13, шаг 3; spec
  /// workspace-file-browser «Панель Files в доке инструментов»). Хост
  /// передаёт колбэк, только когда панель доступна; без колбэка сочетание не
  /// привязано (Cmd/Ctrl+` терминала — другое сочетание).
  final VoidCallback? onToggleFiles;

  /// Cmd/Ctrl+Shift+A — перейти к ожидающему одобрению (change
  /// `fix-approval-focus`, D3, D4). Хост передаёт колбэк всегда, а наличие
  /// цели проверяет при нажатии: иначе привязка появлялась бы и пропадала с
  /// каждым снимком состояния, и нажатие между снимком и перестроением
  /// терялось бы. Колбэк только прокручивает и ставит фокус на полосу, ответа
  /// не отправляет (AGENTS.md §10).
  final VoidCallback? onGoToApproval;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    final bindings = <ShortcutActivator, VoidCallback>{
      if (onOpenCommandPalette != null)
        ...CodeLabShortcut.commandPalette.bind(onOpenCommandPalette!),
      if (onCancel != null) ...CodeLabShortcut.cancelTurn.bind(onCancel!),
      if (onNewSession != null)
        ...CodeLabShortcut.newSession.bind(onNewSession!),
      if (onToggleSidebar != null)
        ...CodeLabShortcut.toggleSidebar.bind(onToggleSidebar!),
      if (onOpenSettings != null)
        ...CodeLabShortcut.openSettings.bind(onOpenSettings!),
      if (onToggleFiles != null)
        ...CodeLabShortcut.toggleFiles.bind(onToggleFiles!),
      if (onGoToApproval != null)
        ...CodeLabShortcut.goToApproval.bind(onGoToApproval!),
    };

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );
  }
}
