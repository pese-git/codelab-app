import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:structured_log_fluent/structured_log_fluent.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart';

import '../../../../l10n/l10n.dart';

/// Высота, ниже которой закреплённая панель прокручивается, а не сжимается.
///
/// Почему: панель инструментов `FluentLogViewer` не сжимается — при
/// возможной ширине панели (всегда ниже порога master-detail) просмотрщику
/// нужно около 100 px высоты, а заголовку панели — ещё около 44 px. Значение
/// измерено на `structured_log_fluent` 0.1.2+1 с запасом; виджет-тест падает,
/// если новая версия потребует больше, так что значение не уплывёт молча.
/// Без него низкое окно (или промежуточный первый кадр, пока размер окна ещё
/// неизвестен) рисует переполнение `RenderFlex`.
const kDebugLogPaneMinHeight = 170.0;

/// Закреплённая, всегда видимая панель журнала отладки — соседка
/// [WorkbenchInspectorPane], а не вложена в неё
/// (`replace-debug-log-panel-with-fluent/design.md`, решения 2 и 4).
///
/// Почему так: заголовок (название и «Expand») — собственная оболочка дока
/// CodeLab, а тело — встраиваемый [FluentLogViewer] пакета
/// `structured_log_fluent` как есть: поиск, выбор категории (появляется, когда
/// категорий две и больше, например с началом протокольной трассы), фильтр
/// уровней, пауза/очистка и адаптивное разделение master-detail приходят из
/// пакета и здесь не переписываются (ТЗ на `LogCategoryComboBox` и
/// встраиваемый виджет вошло в `structured_log_fluent` `0.1.0-dev.3`/`.4`).
///
/// Как использовать: читает тот же [LogBuffer], что и полноэкранный просмотр,
/// открываемый по [onExpand], но держит свой [LogViewerController]: поиск,
/// уровень и категория принадлежат этой панели и с полноэкранным видом не
/// делятся (уточнение решения 4 «два контроллера, один буфер»). Заголовок и
/// подсказка кнопки — по каталогу, содержимое журнала не переводится (D7).
class WorkbenchDebugLogPane extends StatefulWidget {
  const WorkbenchDebugLogPane({
    required this.logBuffer,
    required this.onExpand,
    super.key,
  });

  /// Shared with the full-screen viewer — same underlying data, independent
  /// filter/pause state (Decision 4).
  final LogBuffer logBuffer;

  /// Called from the header's "Expand" button — opens the same full-screen
  /// viewer that `/logs` does (Decision 4), never two independent paths.
  final VoidCallback onExpand;

  @override
  State<WorkbenchDebugLogPane> createState() => _WorkbenchDebugLogPaneState();
}

class _WorkbenchDebugLogPaneState extends State<WorkbenchDebugLogPane> {
  late final LogViewerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = LogViewerController(widget.logBuffer);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border.all(color: Colors.grey.withAlpha(54)),
        borderRadius: BorderRadius.circular(6),
      ),
      // One tree whether or not the panel is short: switching between
      // layouts at a threshold would rebuild the viewer and drop its state.
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            height: math.max(constraints.maxHeight, kDebugLogPaneMinHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.l10n.workbenchDebugLogTitle,
                          style: theme.typography.subtitle,
                        ),
                      ),
                      Tooltip(
                        message: context.l10n.workbenchDebugLogExpand,
                        child: IconButton(
                          icon: const Icon(FluentIcons.full_screen),
                          onPressed: widget.onExpand,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: FluentLogViewer(controller: _controller)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
