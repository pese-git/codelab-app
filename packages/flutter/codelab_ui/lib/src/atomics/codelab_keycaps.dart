/// Кейкапы сочетания: заглушка сигнатур для красного теста 2.1 change
/// `add-app-keyboard-page` (D6, D9).
///
/// Почему: страница «Keyboard» показывает клавиши плашками, а читается
/// сочетание словами; общий виджет кита нужен и странице, и превью.
///
/// Для чего: по плашке на клавишу комбинации (`CodeLabTextRole.mono`), для
/// альтернатив (`↑ / ↓`) — плашки через разделитель; одна подпись
/// `Semantics` словами, текст плашек из семантики исключён.
///
/// Как использовать: сейчас виджет ничего не рисует (заглушка); поведение —
/// задача 2.2. Платформу выбирает каталог по `defaultTargetPlatform` (D4).
library;

import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_shortcuts.dart';

class CodeLabKeycaps extends StatelessWidget {
  const CodeLabKeycaps({required this.combos, super.key});

  /// Комбинации одной строки: несколько — альтернативы.
  final List<CodeLabKeyCombo> combos;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
