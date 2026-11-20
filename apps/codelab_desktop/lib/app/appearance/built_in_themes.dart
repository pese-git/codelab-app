import 'package:codelab_client_core/codelab_client_core.dart';

/// Идентификаторы встроенных тем в порядке показа (D6).
const kBuiltInThemeIds = ['light', 'dark', 'high-contrast'];

/// Встроенная тема [id] как [ThemeFile] с полным набором ролей.
///
/// ЗАГЛУШКА для красных тестов 4.3 (`add-app-appearance-page`, D6): у `light`
/// и `dark` роли — `default` (стандартная тема Fluent), у `high-contrast` —
/// палитра из D6. Настоящие значения — задача 4.4.
ThemeFile builtInThemeFile(String id) => ThemeFile(
  name: id,
  base: switch (id) {
    'light' => ThemeBase.light,
    'high-contrast' => ThemeBase.highContrast,
    _ => ThemeBase.dark,
  },
  roles: {for (final role in ThemeRole.values) role: const DefaultColor()},
);
