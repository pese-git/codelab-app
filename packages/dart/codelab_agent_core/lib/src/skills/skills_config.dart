/// Настройки навыков агента: раздел `skills` конфигурации (design.md change
/// `add-agent-skills`, D11, D16; `agent-core-architecture` §15.4).
///
/// Почему отдельный тип: навыки читают сразу несколько потребителей —
/// рантайм (запрос к порту), `parseSkills` (отключённые и предел), секция
/// каталога и повторное приложение после сжатия. Один неизменяемый объект в
/// `CoreConfig.skills` не даёт им разойтись в значениях и умолчаниях.
///
/// Для чего: хранит проверенные значения ключей `skills.*`; границы значений
/// проверяет схема конфигурации (`resolve.dart`), а не конструктор.
///
/// Как использовать: хост получает значение из `CoreConfig.fromLayers`
/// (`config.skills`); тесты и встроенные хосты без файлов создают его
/// напрямую — поля по умолчанию совпадают с умолчаниями конфигурации.
final class SkillsConfig {
  const SkillsConfig({
    this.enabled = true,
    this.extraRoots = const [],
    this.disabled = const [],
    this.maxSkills = 200,
    this.catalogMaxChars = 8000,
    this.reattachPerSkillTokens = 5000,
    this.reattachTotalTokens = 25000,
  });

  /// `skills.enabled`; `false` сужает capability `skills` до `off`.
  final bool enabled;

  /// `skills.extra_roots` как записаны в конфиге (`~` раскрывает загрузчик,
  /// относительный путь — от `cwd`, Q41).
  final List<String> extraRoots;

  /// `skills.disabled`: имена навыков, которые не попадают в каталог.
  final List<String> disabled;

  /// `skills.max_skills` (1–1000).
  final int maxSkills;

  /// `skills.catalog_max_chars` (1000–64000).
  final int catalogMaxChars;

  /// `skills.reattach.per_skill_tokens` (0–16384); `0` выключает приложение.
  final int reattachPerSkillTokens;

  /// `skills.reattach.total_tokens` (0–200000); `0` выключает приложение.
  final int reattachTotalTokens;
}
