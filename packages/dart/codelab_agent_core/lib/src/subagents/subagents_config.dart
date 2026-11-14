/// Настройки субагентов: раздел `subagents` конфигурации (design.md change
/// `add-subagents-and-tasks`, D17, D22; `agent-core/17-3-subagents.md`
/// §17.3.10).
///
/// Почему отдельный тип: лимиты читаются при каждом `spawn`, а не копируются
/// в сессию, поэтому живая перезагрузка (`config set` + reload) действует на
/// следующий запуск без перезапуска агента.
///
/// Для чего: значения по умолчанию и диапазоны — в схеме (`schema.dart`) и
/// реестре настроек; здесь только применённые значения. Ключи следующих
/// этапов (`background`, `follow_ups`) в базе отсутствуют (CFG-5).
///
/// Как использовать: `CoreConfig.subagents`; тесты создают значение
/// напрямую (`SubagentsConfig(maxDepth: 1)`).
final class SubagentsConfig {
  const SubagentsConfig({
    this.enabled = true,
    this.maxDepth = 3,
    this.maxConcurrent = 3,
    this.maxPerTurn = 10,
    this.maxSteps = 30,
    this.maxTokens,
    this.maxCost,
    this.maxDuration = const Duration(minutes: 10),
    this.reportMaxBytes = 16384,
    this.progressInterval = const Duration(seconds: 2),
    this.heartbeatInterval = const Duration(seconds: 15),
    this.cancelGrace = const Duration(seconds: 10),
  });

  /// `false` — ни схемы `agent`, ни секции промпта в новых сессиях.
  final bool enabled;

  /// 1–3: глубина вложенности; у потомка глубины `maxDepth` нет `agent`.
  final int maxDepth;

  /// Слоты одновременно работающих потомков на всё дерево.
  final int maxConcurrent;

  /// Запусков на всё дерево за ход корневой сессии.
  final int maxPerTurn;

  /// Бюджет шагов, токенов, стоимости и времени одного потомка.
  final int maxSteps;
  final int? maxTokens;
  final double? maxCost;
  final Duration maxDuration;

  /// Предел отчёта ребёнка в байтах UTF-8.
  final int reportMaxBytes;

  /// Частота строк прогресса и «сердцебиения» вызова `agent`.
  final Duration progressInterval, heartbeatInterval;

  /// Сколько вызов `agent` ждёт остановки детей после отмены.
  final Duration cancelGrace;
}
