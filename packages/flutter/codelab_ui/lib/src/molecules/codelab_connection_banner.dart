import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Состояние соединения, о котором сообщает [CodeLabConnectionBanner].
enum CodeLabConnectionBannerStatus {
  /// Установленное соединение оборвалось само.
  lost,

  /// Попытка подключения или переподключения не удалась.
  failed,

  /// Идёт переподключение.
  reconnecting,
}

/// Баннер состояния соединения над лентой.
///
/// Почему: экран подключения виден только при пустой ленте, и при обрыве
/// посреди работы пользователь видел лишь статус в шапке и недоступный
/// композер (spec `agent-workbench-ui` «Connection banner above a non-empty
/// transcript»).
///
/// Для чего: молекула без логики на fluent `InfoBar` (design D6 change
/// `add-connection-and-error-states`): заголовок и причина по [status],
/// действия Reconnect и Connection settings, пока соединение потеряно или
/// подключиться не удалось, и индикатор прогресса во время переподключения.
/// Баннер отражает состояние, а не событие, поэтому кнопки закрытия нет.
///
/// Как использовать: хост кладёт виджет над непустой лентой, пока
/// соединение `lost`, `failed` или `reconnecting`, и убирает, когда оно
/// снова установлено. [message] — причина от ядра клиента.
class CodeLabConnectionBanner extends StatelessWidget {
  const CodeLabConnectionBanner({
    required this.status,
    this.message,
    this.onReconnect,
    this.onConfigureConnection,
    super.key,
  });

  final CodeLabConnectionBannerStatus status;
  final String? message;
  final VoidCallback? onReconnect;
  final VoidCallback? onConfigureConnection;

  @override
  Widget build(BuildContext context) {
    final reconnecting = status == CodeLabConnectionBannerStatus.reconnecting;
    final reason = message;
    return InfoBar(
      title: Text(switch (status) {
        CodeLabConnectionBannerStatus.lost => 'Connection to the agent lost',
        CodeLabConnectionBannerStatus.failed =>
          'Could not connect to the agent',
        CodeLabConnectionBannerStatus.reconnecting => 'Reconnecting…',
      }),
      content: reason == null || reconnecting
          ? null
          : Text(reason, maxLines: 3, overflow: TextOverflow.ellipsis),
      severity: switch (status) {
        CodeLabConnectionBannerStatus.lost => InfoBarSeverity.warning,
        CodeLabConnectionBannerStatus.failed => InfoBarSeverity.error,
        CodeLabConnectionBannerStatus.reconnecting => InfoBarSeverity.info,
      },
      isLong: true,
      action: reconnecting
          ? const SizedBox.square(
              dimension: 16,
              child: ProgressRing(strokeWidth: 2),
            )
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onReconnect != null)
                  CodeLabButton(
                    label: 'Reconnect',
                    icon: FluentIcons.refresh,
                    emphasis: CodeLabButtonEmphasis.primary,
                    onPressed: onReconnect,
                  ),
                if (onConfigureConnection != null)
                  CodeLabButton(
                    label: 'Connection settings',
                    icon: FluentIcons.settings,
                    onPressed: onConfigureConnection,
                  ),
              ],
            ),
    );
  }
}
