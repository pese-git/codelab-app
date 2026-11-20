import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// Собирает `FluentThemeData` из [theme] (D4).
///
/// ЗАГЛУШКА для красных тестов 4.3/4.5: возвращает стандартную тему режима
/// без расширений и без ролей. [systemAccent] перекрывает роль `accent`.
/// Настоящая сборка — задача 4.4.
FluentThemeData buildFluentTheme(ThemeFile theme, {Color? systemAccent}) =>
    FluentThemeData(
      brightness: theme.base == ThemeBase.light
          ? Brightness.light
          : Brightness.dark,
    );
