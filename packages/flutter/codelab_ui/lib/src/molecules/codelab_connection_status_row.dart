import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../l10n/strings.dart';

enum CodeLabConnectionStatus {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,

  /// Установленное соединение оборвалось само (design D1 change
  /// `add-connection-and-error-states`); тон — как у [failed].
  lost,
  failed,
}

class CodeLabConnectionStatusRow extends StatelessWidget {
  const CodeLabConnectionStatusRow({
    required this.status,
    required this.transportLabel,
    required this.profileLabel,
    this.detail,
    super.key,
  });

  final CodeLabConnectionStatus status;
  final String transportLabel;
  final String profileLabel;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Гибкий, как и подписи профиля: в окне телефона (390 px) строка
        // иначе переполнялась (change `redesign-workbench-shell`, 5.3).
        Flexible(
          child: CodeLabStatusIndicator(
            label: _statusLabel(context),
            tone: _statusTone,
          ),
        ),
        const SizedBox(width: 10),
        CodeLabBadge(label: transportLabel, tone: CodeLabTone.accent),
        const SizedBox(width: 6),
        Flexible(
          child: CodeLabText(
            profileLabel,
            role: CodeLabTextRole.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (detail != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: CodeLabText(
              detail!,
              role: CodeLabTextRole.caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }

  String _statusLabel(BuildContext context) {
    final strings = codeLabStringsOf(context);
    return switch (status) {
      CodeLabConnectionStatus.idle => strings.codeLabConnectionIdle,
      CodeLabConnectionStatus.connecting => strings.codeLabConnectionConnecting,
      CodeLabConnectionStatus.connected => strings.codeLabConnectionConnected,
      CodeLabConnectionStatus.reconnecting =>
        strings.codeLabConnectionReconnecting,
      CodeLabConnectionStatus.disconnected =>
        strings.codeLabConnectionDisconnected,
      CodeLabConnectionStatus.lost => strings.codeLabConnectionLost,
      CodeLabConnectionStatus.failed => strings.codeLabConnectionFailed,
    };
  }

  CodeLabStatusTone get _statusTone {
    return switch (status) {
      CodeLabConnectionStatus.idle => CodeLabStatusTone.idle,
      CodeLabConnectionStatus.connecting => CodeLabStatusTone.warning,
      CodeLabConnectionStatus.connected => CodeLabStatusTone.active,
      CodeLabConnectionStatus.reconnecting => CodeLabStatusTone.warning,
      CodeLabConnectionStatus.disconnected => CodeLabStatusTone.warning,
      CodeLabConnectionStatus.lost ||
      CodeLabConnectionStatus.failed => CodeLabStatusTone.danger,
    };
  }
}
