import 'dart:math' as math;

import '../config/core_config.dart';

/// Пороги сжатия для окна модели (`agent-core-architecture` §9.4).
///
/// Почему доли окна: фиксированные значения, рассчитанные на окно 200 000,
/// больше всего окна у моделей на 8 000 — сжатие срабатывало бы на каждом
/// ходу или никогда. Верхние границы не дают большим моделям держать в
/// хвосте 100 000 токенов, которые дорого пересылать на каждом шаге.
///
/// Как использовать: сессия вызывает [CompactionSettings.forWindow] с окном
/// [effectiveContextWindow] и переопределениями `CoreConfig.compaction`;
/// [shouldCompact] решает про `afterTurn`, [findCutPoint] берёт
/// [keepRecentTokens] и [keepRecentUserTurns].
final class CompactionSettings {
  const CompactionSettings({
    required this.reserveTokens,
    required this.keepRecentTokens,
    required this.keepRecentUserTurns,
  });

  /// Шаги §9.4; заданные [overrides] заменяют вычисленные значения и
  /// проходят те же ограничения сверху `w/4` и `w/2`.
  factory CompactionSettings.forWindow(
    int window, {
    CompactionOverrides? overrides,
  }) {
    // Крошечное окно: запас не больше четверти, хвост не больше половины.
    final reserveCap = math.max(128, window ~/ 4);
    final keepCap = math.max(256, window ~/ 2);
    final r0 = math.min(16384, math.max(1024, window ~/ 4));
    final k0 = math.min(20000, math.max(2048, window ~/ 2));
    return CompactionSettings(
      reserveTokens: math.min(overrides?.reserveTokens ?? r0, reserveCap),
      keepRecentTokens: math.min(overrides?.keepRecentTokens ?? k0, keepCap),
      keepRecentUserTurns: overrides?.keepRecentUserTurns ?? 1,
    );
  }

  /// Запас под ответ модели и служебный текст.
  final int reserveTokens;

  /// Сколько свежего хвоста сохранить дословно.
  final int keepRecentTokens;

  /// Минимум последних ходов пользователя в хвосте (CMP-7).
  final int keepRecentUserTurns;
}

/// Порог `afterTurn`: окно минус запас.
int compactionThreshold(int window, CompactionSettings s) =>
    window - s.reserveTokens;

/// Оценка строго выше порога.
bool shouldCompact(int contextTokens, int window, CompactionSettings s) =>
    contextTokens > compactionThreshold(window, s);
