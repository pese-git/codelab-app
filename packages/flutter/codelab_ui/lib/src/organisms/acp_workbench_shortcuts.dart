import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';

class AcpWorkbenchShortcuts extends StatelessWidget {
  const AcpWorkbenchShortcuts({
    required this.child,
    this.onOpenCommandPalette,
    this.onCancel,
    this.onApprove,
    this.onReject,
    this.onInspectorPrevious,
    this.onInspectorNext,
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
