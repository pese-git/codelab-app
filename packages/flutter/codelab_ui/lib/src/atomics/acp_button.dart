import 'package:fluent_ui/fluent_ui.dart';

import 'acp_icon.dart';
import 'acp_tone.dart';

enum AcpButtonEmphasis { primary, secondary }

class AcpButton extends StatelessWidget {
  const AcpButton({
    required this.label,
    required this.onPressed,
    this.emphasis = AcpButtonEmphasis.secondary,
    this.icon,
    this.isLoading = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final AcpButtonEmphasis emphasis;
  final IconData? icon;

  /// Shows the spinner in place of [icon]. Purely visual — it does not
  /// disable the button; pass `onPressed: null` explicitly for that. A
  /// caller that needs a spinner while still accepting presses (e.g. the
  /// prompt composer's Send button, which must stay pressable — to queue,
  /// not send — while a turn is running; see add-prompt-queue/design.md,
  /// Goals) can now do so, which an implicit "loading implies disabled"
  /// coupling here would have ruled out.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final child = _AcpButtonContent(
      label: label,
      icon: icon,
      isLoading: isLoading,
    );

    return switch (emphasis) {
      AcpButtonEmphasis.primary => FilledButton(
        onPressed: onPressed,
        child: child,
      ),
      AcpButtonEmphasis.secondary => Button(onPressed: onPressed, child: child),
    };
  }
}

class AcpIconButton extends StatelessWidget {
  const AcpIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.tone = AcpTone.neutral,
    super.key,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final AcpTone tone;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      icon: AcpIcon(icon, tone: tone),
      onPressed: onPressed,
    );

    if (tooltip == null) {
      return button;
    }

    return Tooltip(message: tooltip, child: button);
  }
}

class _AcpButtonContent extends StatelessWidget {
  const _AcpButtonContent({
    required this.label,
    required this.icon,
    required this.isLoading,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLoading)
          const SizedBox.square(
            dimension: 14,
            child: ProgressRing(strokeWidth: 2),
          )
        else if (icon != null)
          Icon(icon, size: 14),
        if (isLoading || icon != null) const SizedBox(width: 8),
        Text(label, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
