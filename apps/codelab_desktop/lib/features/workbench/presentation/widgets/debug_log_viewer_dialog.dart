import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';

/// Полноэкранный просмотр журнала (список записей слева, детали справа).
///
/// Почему отдельный диалог: вид Log панели Protocol показывает область
/// сессии в фокусе, а полный буфер без неё нужен для разбора сбоев
/// (`replace-debug-log-panel-with-fluent/design.md`, решение 4; change
/// `redesign-protocol-pane`, D8).
///
/// Для чего: оборачивает `FluentLogViewerPage` пакета `structured_log_fluent`
/// как есть. `showDialog` кладёт маршрут, поэтому `Navigator.canPop` истинно и
/// кнопка «назад» страницы появляется без своей обвязки; Esc закрывает
/// диалог, барьер затемняет рабочее место, а `CodeLabShellState` при
/// открытии и закрытии не меняется.
///
/// Как использовать: единственный путь открытия — [show] из кнопки `Expand`
/// вида Log; `/logs` теперь открывает вид Log, а не этот диалог.
class DebugLogViewerDialog extends StatelessWidget {
  const DebugLogViewerDialog({required this.controller, super.key});

  final LogViewerController controller;

  static Future<void> show(BuildContext context, LogBuffer logBuffer) {
    final controller = LogViewerController(logBuffer);
    return showDialog<void>(
      context: context,
      builder: (_) => DebugLogViewerDialog(controller: controller),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return SizedBox(
      width: size.width,
      height: size.height,
      child: FluentLogViewerPage(controller: controller),
    );
  }
}
