import 'package:codelab_client_core/codelab_client_core.dart';

/// Идентификаторы встроенных тем в порядке показа (design.md change
/// `add-app-appearance-page`, D6).
const kBuiltInThemeIds = ['light', 'dark', 'high-contrast'];

Rgb _rgb(int value) => Rgb(value);

/// Встроенная тема [id] как [ThemeFile] с полным набором ролей (D6).
///
/// Почему кодом, а не JSON-ресурсом: встроенным темам не нужен разбор, а тест
/// контраста (D8) проверяет их напрямую.
///
/// Для чего: `light` и `dark` — «стандартная тема Fluent своего режима»: все
/// роли `default`, цвета выводит сборщик из `FluentThemeData` и кита, поэтому
/// вид app не меняется. `high-contrast` — тёмная база с палитрой артборда
/// (собственный макет проекта); роли, которых в артборде нет (`muted`,
/// `selection`, `code.function`, `code.variable`, `code.operator`,
/// `code.attribute`), остаются `default` и берутся из `dark` с подгонкой
/// контраста к `#000000`.
///
/// Как использовать: база пользовательской темы (`extends`) — встроенная тема с
/// тем же именем (`ThemeBase.jsonName`); незнакомый [id] даёт `dark`.
ThemeFile builtInThemeFile(String id) {
  // У `high-contrast` база — `dark`: режим тёмный, а явные роли лежат в самой
  // теме (у пользовательской темы `extends: high-contrast` базой служит именно
  // эта тема, см. `buildFluentTheme`).
  final base = id == 'light' ? ThemeBase.light : ThemeBase.dark;
  final roles = <ThemeRole, ThemeColorValue>{
    for (final role in ThemeRole.values) role: const DefaultColor(),
    if (id == 'high-contrast') ...{
      ThemeRole.text: _rgb(0xFFFFFF),
      ThemeRole.accent: _rgb(0x7FD4FF),
      ThemeRole.info: _rgb(0x7FD4FF),
      ThemeRole.success: _rgb(0x7CFC8A),
      ThemeRole.warning: _rgb(0xFFD75F),
      ThemeRole.error: _rgb(0xFF8080),
      ThemeRole.diffAddBg: _rgb(0x003D12),
      ThemeRole.diffRemoveBg: _rgb(0x4A0000),
      ThemeRole.codeBackground: _rgb(0x000000),
      ThemeRole.codeComment: _rgb(0xC8C8C8),
      ThemeRole.codeKeyword: _rgb(0xFF9DF5),
      ThemeRole.codeString: _rgb(0x7CFC8A),
      ThemeRole.codeType: _rgb(0x7FD4FF),
      ThemeRole.codeNumber: _rgb(0xFFC66B),
    },
  };
  return ThemeFile(
    name: id == 'light' || id == 'high-contrast' ? id : 'dark',
    base: base,
    roles: roles,
  );
}
