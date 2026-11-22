import 'package:fluent_ui/fluent_ui.dart';

/// Тонкий перетаскиваемый разделитель между двумя изменяемыми панелями.
///
/// Почему: колонки workbench и панель Protocol (таблица над панелью
/// выбранного) делят одну механику перетаскивания (change
/// `redesign-protocol-pane`, D12).
///
/// Для чего: сообщает смещение указателя вдоль оси изменения размера через
/// [onDelta] на каждом шаге и вызывает [onDragEnd] по окончании жеста;
/// собственного размера не хранит — владелец решает, как применить и
/// ограничить смещение.
///
/// Как использовать: [axis] — направление самой **линии** разделителя.
/// [Axis.vertical] (по умолчанию) — вертикальная линия между колонками:
/// курсор `resizeColumn`, [onDelta] получает `dx`. [Axis.horizontal] —
/// горизонтальная линия между строками: курсор `resizeRow`, [onDelta]
/// получает `dy`.
class CodeLabResizeHandle extends StatelessWidget {
  const CodeLabResizeHandle({
    required this.onDelta,
    this.onDragEnd,
    this.axis = Axis.vertical,
    this.width = 8,
    super.key,
  });

  final ValueChanged<double> onDelta;
  final VoidCallback? onDragEnd;

  /// Направление линии разделителя.
  final Axis axis;

  /// Толщина зоны захвата поперёк линии — шире видимой линии, чтобы не
  /// целиться в пиксель; вдоль линии зона занимает всю доступную длину.
  final double width;

  static const double _lineWidth = 1;

  @override
  Widget build(BuildContext context) {
    final vertical = axis == Axis.vertical;
    final line = Container(
      width: vertical ? _lineWidth : null,
      height: vertical ? null : _lineWidth,
      color: Colors.grey.withAlpha(64),
    );
    return MouseRegion(
      cursor: vertical
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) =>
            onDelta(vertical ? details.delta.dx : details.delta.dy),
        onPanEnd: onDragEnd == null ? null : (_) => onDragEnd!(),
        child: SizedBox(
          width: vertical ? width : null,
          height: vertical ? null : width,
          child: Center(child: line),
        ),
      ),
    );
  }
}
