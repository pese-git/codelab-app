import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class CodeLabWorkbenchShortcuts extends StatelessWidget {
  const CodeLabWorkbenchShortcuts({
    required this.child,
    this.onOpenCommandPalette,
    this.onCancel,
    this.onApprove,
    this.onReject,
    this.onInspectorPrevious,
    this.onInspectorNext,
    this.onNewSession,
    this.onToggleSidebar,
    this.onOpenSettings,
    this.onToggleFiles,
    this.enabled = true,
    super.key,
  });

  final Widget child;
  final VoidCallback? onOpenCommandPalette;
  final VoidCallback? onCancel;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final VoidCallback? onInspectorPrevious;
  final VoidCallback? onInspectorNext;

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
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }

    final bindings = <ShortcutActivator, VoidCallback>{};
    if (onOpenCommandPalette != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.keyK, control: true)] =
          onOpenCommandPalette!;
      bindings[const SingleActivator(LogicalKeyboardKey.keyK, meta: true)] =
          onOpenCommandPalette!;
    }
    if (onCancel != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.escape)] = onCancel!;
    }
    if (onNewSession != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.keyN, control: true)] =
          onNewSession!;
      bindings[const SingleActivator(LogicalKeyboardKey.keyN, meta: true)] =
          onNewSession!;
    }
    if (onToggleSidebar != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.keyB, control: true)] =
          onToggleSidebar!;
      bindings[const SingleActivator(LogicalKeyboardKey.keyB, meta: true)] =
          onToggleSidebar!;
    }
    if (onOpenSettings != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.comma, control: true)] =
          onOpenSettings!;
      bindings[const SingleActivator(LogicalKeyboardKey.comma, meta: true)] =
          onOpenSettings!;
    }
    if (onToggleFiles != null) {
      bindings[const SingleActivator(
            LogicalKeyboardKey.keyE,
            control: true,
            shift: true,
          )] =
          onToggleFiles!;
      bindings[const SingleActivator(
            LogicalKeyboardKey.keyE,
            meta: true,
            shift: true,
          )] =
          onToggleFiles!;
    }
    if (onApprove != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.enter, control: true)] =
          onApprove!;
      bindings[const SingleActivator(LogicalKeyboardKey.enter, meta: true)] =
          onApprove!;
    }
    if (onReject != null) {
      bindings[const SingleActivator(
            LogicalKeyboardKey.backspace,
            control: true,
          )] =
          onReject!;
      bindings[const SingleActivator(
            LogicalKeyboardKey.backspace,
            meta: true,
          )] =
          onReject!;
    }
    if (onInspectorPrevious != null) {
      bindings[const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true)] =
          onInspectorPrevious!;
    }
    if (onInspectorNext != null) {
      bindings[const SingleActivator(
            LogicalKeyboardKey.arrowRight,
            alt: true,
          )] =
          onInspectorNext!;
    }

    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(autofocus: true, child: child),
    );
  }
}
