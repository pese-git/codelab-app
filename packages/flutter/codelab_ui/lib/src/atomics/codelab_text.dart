import 'package:fluent_ui/fluent_ui.dart';

/// Роль текста в типографике Fluent.
///
/// [mono] — моноширинный текст команд, путей и вывода инструментов: в ленте
/// они должны читаться как код, а не как проза (change
/// `redesign-transcript-rows`, D5).
enum CodeLabTextRole { title, subtitle, body, strong, caption, mono }

class CodeLabText extends StatelessWidget {
  const CodeLabText(
    this.data, {
    this.role = CodeLabTextRole.body,
    this.maxLines,
    this.overflow,
    this.color,
    this.symbols = false,
    super.key,
  });

  final String data;
  final CodeLabTextRole role;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Overrides the role's default color when set — for callers that need to
  /// convey extra meaning (e.g. tone) through text color where there's no
  /// room for a separate badge.
  final Color? color;

  /// Стиль роли [role] в текущей теме — для составного текста
  /// (`Text.rich`), где часть фразы набрана другой ролью, например
  /// моноширинная цель в строке вызова «Read lib/main.dart».
  static TextStyle? styleOf(BuildContext context, CodeLabTextRole role) =>
      _styleForRole(FluentTheme.of(context).typography, role);

  /// Стиль знаков клавиш: системный шрифт темы с кеглем роли [role] (для
  /// измерения ширины плашек без построения виджета, `CodeLabKeycaps.widthOf`).
  static TextStyle? symbolStyleOf(BuildContext context, CodeLabTextRole role) {
    final typography = FluentTheme.of(context).typography;
    return typography.body?.copyWith(
      fontSize: _styleForRole(typography, role)?.fontSize,
      fontFamilyFallback: _symbolFallback,
    );
  }

  /// Набрать [data] знаками системным шрифтом, а не шрифтом роли.
  ///
  /// Почему: в моноширинном шрифте роли [CodeLabTextRole.mono] (`Menlo`)
  /// знаки клавиш ⌘ ⇧ ⌥ ⏎ ⌫ и стрелки нарисованы заметно мельче букв (ручная
  /// проверка на macOS, change `add-app-keyboard-page`). Для чего: плашки
  /// клавиш. Как использовать: `symbols: true` с ролью [CodeLabTextRole.mono];
  /// кегль берётся у роли, шрифт — системный стиль темы (знаки есть в SF и
  /// Segoe UI), запасные шрифты символов перечислены в `_symbolFallback`.
  final bool symbols;

  @override
  Widget build(BuildContext context) {
    final style = symbols
        ? symbolStyleOf(context, role)
        : styleOf(context, role);
    return Text(
      data,
      maxLines: maxLines,
      overflow: overflow,
      style: color == null ? style : style?.copyWith(color: color),
    );
  }
}

TextStyle? _styleForRole(Typography typography, CodeLabTextRole role) {
  return switch (role) {
    CodeLabTextRole.title => typography.title,
    CodeLabTextRole.subtitle => typography.subtitle,
    CodeLabTextRole.body => typography.body,
    CodeLabTextRole.strong => typography.bodyStrong,
    CodeLabTextRole.caption => typography.caption,
    CodeLabTextRole.mono => typography.body?.copyWith(
      fontFamily: 'Menlo',
      fontFamilyFallback: _monoFallback,
      fontSize: 12.5,
    ),
  };
}

/// Запасные моноширинные шрифты: на Windows нет Menlo, на Linux — ни Menlo,
/// ни Consolas.
const _monoFallback = [
  'SF Mono',
  'Consolas',
  'Cascadia Mono',
  'DejaVu Sans Mono',
  'Courier New',
  'monospace',
];

/// Запасные шрифты со знаками клавиш.
///
/// Первым — системный шрифт macOS (SF): шрифт темы Fluent (`Segoe UI`) на
/// macOS отсутствует, и без него знаки брались бы из `Apple Symbols`, где они
/// так же мелки, как в `Menlo` (замер CoreText: в SF ⌘ ⇧ ⏎ ростом с
/// заглавную букву). На Windows и Linux `.AppleSystemUIFont` не найдётся и
/// пропустится; там системный шрифт может не содержать ⏎ и ⌫ — дальше идут
/// шрифты символов.
const _symbolFallback = [
  '.AppleSystemUIFont',
  'Apple Symbols',
  'Segoe UI Symbol',
  'Noto Sans Symbols 2',
  'DejaVu Sans',
];
