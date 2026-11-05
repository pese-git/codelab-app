import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Одна пара «подпись — значение» для [CodeLabKeyValueList].
///
/// Почему: значение строки в макете бывает обычным текстом, моноширинным
/// путём или смесью («In keychain-macos as `codelab/anthropic`»); отдельная
/// модель не даёт вызывающему собирать `TextSpan` самому.
///
/// Как использовать: [value] — обычный текст, [monoValue] — моноширинный
/// хвост сразу после него; нужен хотя бы один из двух.
class CodeLabKeyValueEntry {
  const CodeLabKeyValueEntry({required this.label, this.value, this.monoValue})
    : assert(
        value != null || monoValue != null,
        'нужно значение: value или monoValue',
      );

  /// Подпись слева, вторичным цветом.
  final String label;

  /// Обычный текст значения.
  final String? value;

  /// Моноширинная часть значения (путь, идентификатор) после [value].
  final String? monoValue;
}

/// Таблица «подпись — значение» в раскрытом Expander.
///
/// Почему: раскрытая карточка провайдера (`Key / Last check / Source`) и
/// экран подключения повторяют одну сетку `.kv` артбордов `Providers` и
/// `Connection`: колонка подписей 140 px, зазор 16 px по горизонтали и 8 px
/// по вертикали (design.md change `add-provider-setup-ui`, D19).
///
/// Для чего: только вёрстка; ни логики, ни знания о провайдерах. Теги и
/// кнопки действий строки остаются в заголовке и подвале Expander владельца
/// (как на артборде), а не здесь.
///
/// Как использовать: `CodeLabKeyValueList(entries: [...])` внутри
/// `CodeLabExpanderCard`. Длинные значения переносятся; пустой список
/// занимает нулевую высоту.
class CodeLabKeyValueList extends StatelessWidget {
  const CodeLabKeyValueList({required this.entries, super.key});

  final List<CodeLabKeyValueEntry> entries;

  static const _labelWidth = 140.0;
  static const _columnGap = 16.0;
  static const _rowGap = 8.0;

  @override
  Widget build(BuildContext context) {
    final secondary = FluentTheme.of(context).resources.textFillColorSecondary;
    final body = CodeLabText.styleOf(context, CodeLabTextRole.body);
    final mono = CodeLabText.styleOf(context, CodeLabTextRole.mono);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: _rowGap),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _labelWidth,
                child: CodeLabText(entries[i].label, color: secondary),
              ),
              const SizedBox(width: _columnGap),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: body,
                    children: [
                      if (entries[i].value case final value?)
                        TextSpan(text: value),
                      if (entries[i].monoValue case final value?)
                        TextSpan(text: value, style: mono),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
