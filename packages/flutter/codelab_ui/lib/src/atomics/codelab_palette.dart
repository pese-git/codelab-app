import 'package:fluent_ui/fluent_ui.dart';

import 'codelab_tone.dart';

/// Цвета тонов и ролей кита, которые задаёт тема (`add-app-appearance-page`,
/// D4; spec agent-workbench-ui «Цвета кита из палитры темы»).
///
/// Почему: у Fluent нет ресурсов «цвет успеха текста» и «подсветка diff», а
/// кит раньше зашивал `Colors.green` и `Colors.red`. Пользовательская тема
/// (D-20) должна менять эти цвета, но кит не знает файлов тем и типов
/// `codelab_client_core` (AGENTS.md кита §1): тему в палитру превращает app.
///
/// Для чего: одна точка правды для тонов `success`, `warning`, `danger`,
/// `accent`, цвета ссылок ([info]), фонов diff и выделения ([selection]).
/// Рамки блока одобрения здесь нет: роль `approval_border` app не применяет
/// (решение Q8, `lighten-approval-block`).
///
/// Как использовать: app кладёт палитру в `FluentThemeData.extensions`; виджеты
/// кита читают `CodeLabPalette.of(FluentTheme.of(context))`. Без расширения
/// палитра выводится из Fluent и совпадает с цветами до этого change.
class CodeLabPalette extends ThemeExtension<CodeLabPalette> {
  const CodeLabPalette({
    required this.success,
    required this.warning,
    required this.danger,
    required this.accent,
    required this.info,
    required this.diffAddBackground,
    required this.diffRemoveBackground,
    required this.selection,
  });

  /// Тон `success`.
  final Color success;

  /// Тон `warning`.
  final Color warning;

  /// Тон `danger`.
  final Color danger;

  /// Тон `accent`.
  final Color accent;

  /// Цвет ссылок markdown и просмотра файла; в Fluent-темах равен акценту.
  final Color info;

  /// Фон добавленной строки diff.
  final Color diffAddBackground;

  /// Фон удалённой строки diff.
  final Color diffRemoveBackground;

  /// Фон выделенной строки списков и просмотра.
  final Color selection;

  static final Expando<CodeLabPalette> _derived = Expando(
    'derived codelab palettes',
  );

  /// Палитра темы [theme]: зарегистрированная в `extensions` или выведенная из
  /// Fluent с прежними значениями (кешируется на объект темы).
  static CodeLabPalette of(FluentThemeData theme) {
    final registered = theme.extensions[CodeLabPalette];
    if (registered is CodeLabPalette) return registered;
    return _derived[theme] ??= CodeLabPalette._derive(theme);
  }

  factory CodeLabPalette._derive(FluentThemeData theme) => CodeLabPalette(
    success: Colors.green,
    warning: Colors.warningPrimaryColor,
    danger: Colors.red,
    accent: Colors.blue,
    info: theme.accentColor,
    diffAddBackground: Colors.green.withValues(alpha: 0.18),
    diffRemoveBackground: Colors.red.withValues(alpha: 0.18),
    selection: theme.accentColor.withValues(alpha: 0.18),
  );

  /// Цвет тона [tone]; `neutral` остаётся серым, смысл тона не только в цвете.
  Color toneColor(CodeLabTone tone) => switch (tone) {
    CodeLabTone.neutral => Colors.grey,
    CodeLabTone.accent => accent,
    CodeLabTone.success => success,
    CodeLabTone.warning => warning,
    CodeLabTone.danger => danger,
  };

  @override
  CodeLabPalette copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? accent,
    Color? info,
    Color? diffAddBackground,
    Color? diffRemoveBackground,
    Color? selection,
  }) => CodeLabPalette(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    accent: accent ?? this.accent,
    info: info ?? this.info,
    diffAddBackground: diffAddBackground ?? this.diffAddBackground,
    diffRemoveBackground: diffRemoveBackground ?? this.diffRemoveBackground,
    selection: selection ?? this.selection,
  );

  @override
  CodeLabPalette lerp(ThemeExtension<CodeLabPalette>? other, double t) {
    if (other is! CodeLabPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return CodeLabPalette(
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      danger: mix(danger, other.danger),
      accent: mix(accent, other.accent),
      info: mix(info, other.info),
      diffAddBackground: mix(diffAddBackground, other.diffAddBackground),
      diffRemoveBackground: mix(
        diffRemoveBackground,
        other.diffRemoveBackground,
      ),
      selection: mix(selection, other.selection),
    );
  }
}
