import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Свёрнутый по умолчанию блок технического текста под кнопкой-раскрывашкой.
///
/// Почему: сырой ввод вызова в панели одобрения и сырой текст ошибки в
/// заметке о сбое хода нужны для диагностики, но не должны заслонять
/// понятное человеку содержимое (design D3 change
/// `add-connection-and-error-states`). Не `Expander` из `fluent_ui`: тот
/// читает `PageStorage.of(context)` в `initState` и падает без `Navigator`
/// выше — так рендерятся превью и `codelab_previews_test.dart`.
///
/// Для чего: одна реализация раскрывашки для организмов `codelab_ui`.
///
/// Как использовать: `CodeLabTextDisclosure(label: 'Details', text: raw)`;
/// состояние раскрытия живёт в виджете и сбрасывается при пересоздании.
class CodeLabTextDisclosure extends StatefulWidget {
  const CodeLabTextDisclosure({
    required this.label,
    required this.text,
    super.key,
  });

  final String label;
  final String text;

  @override
  State<CodeLabTextDisclosure> createState() => _CodeLabTextDisclosureState();
}

class _CodeLabTextDisclosureState extends State<CodeLabTextDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Button(
          onPressed: () => setState(() => _expanded = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? FluentIcons.chevron_up : FluentIcons.chevron_down,
                size: 10,
              ),
              const SizedBox(width: 6),
              CodeLabText(widget.label, role: CodeLabTextRole.caption),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 6),
          CodeLabText(widget.text, role: CodeLabTextRole.caption),
        ],
      ],
    );
  }
}
