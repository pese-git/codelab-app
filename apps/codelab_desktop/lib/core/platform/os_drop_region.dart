import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

/// Область, принимающая файлы и папки, перетащенные из файлового менеджера ОС.
///
/// Почему: Flutter на десктопе не отдаёт события внешнего перетаскивания
/// (`DragTarget` работает только внутри дерева виджетов), а плагин
/// `desktop_drop` — нативная зависимость (`AGENTS.md` §11,
/// `platform-integration.md` §37). Его типы не должны проникать в application
/// и presentation (design.md change `add-empty-project-screen`, D3,
/// `technology-stack.md` §20и).
///
/// Для чего: единственный файл с `package:desktop_drop/` (правило сторожа).
/// Переводит события плагина в три колбэка и больше ничего не решает: что
/// можно открыть, определяет application по видам путей (D4).
///
/// Как использовать: оберните область, в которой принимается бросок.
/// [onDropped] получает путь каждого элемента или `null`, если у элемента нет
/// локального пути (пустой `path`). [onEntered] и [onExited] — перетаскиваемые
/// элементы вошли в область или покинули её; после броска плагин выход не
/// шлёт, поэтому подсветку снимают и по [onDropped].
class OsDropRegion extends StatelessWidget {
  const OsDropRegion({
    required this.child,
    required this.onDropped,
    this.onEntered,
    this.onExited,
    super.key,
  });

  final Widget child;
  final VoidCallback? onEntered;
  final VoidCallback? onExited;
  final ValueChanged<List<String?>> onDropped;

  @override
  Widget build(BuildContext context) => DropTarget(
    onDragEntered: (_) => onEntered?.call(),
    onDragExited: (_) => onExited?.call(),
    onDragDone: (details) => onDropped([
      for (final file in details.files) file.path.isEmpty ? null : file.path,
    ]),
    child: child,
  );
}
