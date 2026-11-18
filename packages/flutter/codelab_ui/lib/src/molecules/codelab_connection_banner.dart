import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';
import '../l10n/strings.dart';

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
/// снова установлено. [message] — причина от ядра клиента. [extraAction] —
/// действие хоста, которое виджет не интерпретирует (например, «Add provider»
/// для встроенного агента без провайдера, change `add-provider-setup-ui`,
/// D26): ставится перед стандартными кнопками, пока соединение не
/// переподключается.
class CodeLabConnectionBanner extends StatelessWidget {
  const CodeLabConnectionBanner({
    required this.status,
    this.message,
    this.onReconnect,
    this.reconnectLabel,
    this.onConfigureConnection,
    this.extraAction,
    super.key,
  });

  final CodeLabConnectionBannerStatus status;
  final String? message;
  final VoidCallback? onReconnect;

  /// Подпись кнопки повтора; хост без ручного Connect передаёт `Retry`
  /// (design.md change `require-project-folder`, D18). `null` — текст кита
  /// («Reconnect»/«Переподключиться», `add-desktop-localization`, D4).
  final String? reconnectLabel;
  final VoidCallback? onConfigureConnection;
  final Widget? extraAction;

  @override
  Widget build(BuildContext context) {
    final reconnecting = status == CodeLabConnectionBannerStatus.reconnecting;
    final reason = message;
    final strings = codeLabStringsOf(context);
    return InfoBar(
      title: Text(switch (status) {
        CodeLabConnectionBannerStatus.lost => strings.codeLabBannerLost,
        CodeLabConnectionBannerStatus.failed => strings.codeLabBannerFailed,
        CodeLabConnectionBannerStatus.reconnecting =>
          strings.codeLabBannerReconnecting,
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
                ?extraAction,
                if (onReconnect != null)
                  CodeLabButton(
                    label: reconnectLabel ?? strings.codeLabActionReconnect,
                    icon: FluentIcons.refresh,
                    // Основная кнопка одна: с действием хоста оно и есть
                    // основное, «Reconnect» — обычная.
                    emphasis: extraAction == null
                        ? CodeLabButtonEmphasis.primary
                        : CodeLabButtonEmphasis.secondary,
                    onPressed: onReconnect,
                  ),
                if (onConfigureConnection != null)
                  CodeLabButton(
                    label: strings.codeLabBannerConnectionSettings,
                    icon: FluentIcons.settings,
                    onPressed: onConfigureConnection,
                  ),
              ],
            ),
    );
  }
}
