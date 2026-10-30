import 'schema.dart';

/// Проверенные ключи `redact.*` (`agent-core-architecture` §12.4.3, §15.4).
///
/// Почему в ядре, хотя редактора ещё нет: ключи читаются и проверяются уже
/// сейчас (невалидное выражение — ошибка загрузки с путём ключа), а
/// потребитель — редактор секретов — приходит с задачей 8.11 и берёт готовые
/// значения. До него явно заданный ключ даёт `config.key.not_applied`.
///
/// Как использовать: значения по умолчанию — `const RedactSettings()`;
/// `CoreConfig.fromLayers` заполняет поля из слоёв.
final class RedactSettings {
  const RedactSettings({
    this.enabled = true,
    this.layers = redactDefaultLayers,
    this.allowlistBuiltin = redactBuiltinAllowlist,
    this.allowlistPatterns = const [],
    this.exemptTools = const [],
  });

  /// `false` — работает только слой `exact`.
  final bool enabled;

  /// Включённые слои редакции.
  final List<String> layers;

  /// Встроенные записи белого списка (`git_sha`, `uuid`).
  final List<String> allowlistBuiltin;

  /// Свои регулярные выражения белого списка (уже проверены на компиляцию).
  final List<String> allowlistPatterns;

  /// Инструменты вне редакции дополнительно к `write` и `edit`.
  final List<String> exemptTools;
}
