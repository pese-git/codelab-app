import 'package:fluent_ui/fluent_ui.dart';
import 'package:xterm2/ui.dart' show TerminalTheme, TerminalThemes;

/// Тема эмулятора из `FluentTheme`: фон, текст, курсор и выделение следуют
/// теме приложения, палитра ANSI остаётся стандартной (D3).
///
/// Почему не вся палитра из Fluent: цвета ANSI несут смысл для программ
/// (красный — ошибка), и подмена их акцентами темы ломает вывод утилит.
///
/// Как использовать: зовётся в `build` виджета терминала, результат — в
/// `TerminalView.theme`.
TerminalTheme terminalThemeOf(FluentThemeData theme) {
  const base = TerminalThemes.defaultTheme;
  final background = theme.scaffoldBackgroundColor;
  final foreground = theme.typography.body?.color ?? base.foreground;
  return TerminalTheme(
    cursor: theme.accentColor.defaultBrushFor(theme.brightness),
    selection: theme.accentColor
        .defaultBrushFor(theme.brightness)
        .withAlpha(80),
    foreground: foreground,
    background: background,
    black: base.black,
    white: base.white,
    red: base.red,
    green: base.green,
    yellow: base.yellow,
    blue: base.blue,
    magenta: base.magenta,
    cyan: base.cyan,
    brightBlack: base.brightBlack,
    brightRed: base.brightRed,
    brightGreen: base.brightGreen,
    brightYellow: base.brightYellow,
    brightBlue: base.brightBlue,
    brightMagenta: base.brightMagenta,
    brightCyan: base.brightCyan,
    brightWhite: base.brightWhite,
    searchHitBackground: base.searchHitBackground,
    searchHitBackgroundCurrent: base.searchHitBackgroundCurrent,
    searchHitForeground: base.searchHitForeground,
  );
}
