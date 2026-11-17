import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_text.dart';

/// Моноширинный блок текста с рамкой, переносом и выделением.
///
/// Почему: ответ `/mcp list` агента вне процесса показывается как есть, без
/// разбора (SETUP-11), и должен читаться как вывод команды, а не как проза.
/// Такой же блок уже нарисован внутри `CodeLabApprovalPrompt` (сырой ввод
/// вызова); второе употребление оправдывает атом (design.md change
/// `add-provider-setup-ui`, D19). Сам `CodeLabApprovalPrompt` на атом не
/// переведён: это отдельная правка (AGENTS.md §19).
///
/// Для чего: только вёрстка. Стиль — роль `CodeLabTextRole.mono`; текст не
/// меняется и не разбирается, переводы строк сохраняются, длинные строки
/// переносятся по ширине родителя, текст выделяется мышью.
///
/// Как использовать: `CodeLabMonospaceBlock(reply)`; ширину задаёт родитель.
class CodeLabMonospaceBlock extends StatelessWidget {
  const CodeLabMonospaceBlock(this.data, {super.key});

  /// Текст блока.
  final String data;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: theme.resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: SelectableText(
          data,
          style: CodeLabText.styleOf(context, CodeLabTextRole.mono),
        ),
      ),
    );
  }
}
