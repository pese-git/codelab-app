/// Сегменты usage статус-строки: общая сборка для TUI и REPL (D12, D23 Т5).
///
/// Почему отдельный файл: статус-строка TUI и строка после хода в REPL
/// показывают одни и те же сегменты «по тем же правилам» (D12), и их состав
/// не должен расходиться. Числа, деньги, процент и «~» — функции
/// `codelab_client_core` (D24, Q16 (а)); здесь только состав сегментов и
/// подписи `ctx`, `↑`, `↓`.
///
/// Для чего: чистая функция без `dart:io` и `dart_tui` (TUI-5) — её зовут
/// `statusLine` (`tui/core`) и `ReplSession` через `TerminalRenderer`.
///
/// Как использовать: `usageSegmentsOf(session.usage)`; поле `null` — сегмент
/// скрыт, `0` не печатается (VIEW-6).
library;

import 'package:codelab_client_core/codelab_client_core.dart';

import 'sanitize.dart';

/// Готовые подписи сегментов usage; `null` — сегмента нет.
final class UsageSegments {
  const UsageSegments({
    this.context,
    this.contextLevel,
    this.tokens,
    this.cost,
  });

  /// `ctx 81%` (Q17 (а)).
  final String? context;

  /// Уровень по тому же целому проценту; цвет выбирает `render` (D12).
  final UsageLevel? contextLevel;

  /// `↑94.0k ↓7.2k`, с «~» перед `↑` при неполных токенах (D6).
  final String? tokens;

  /// `$0.13`, с «~» перед суммой при неполной стоимости (D6).
  final String? cost;

  /// Нет ни одного сегмента.
  bool get isEmpty => context == null && tokens == null && cost == null;
}

/// Сегменты по снимку [usage]; `null`, `unknown`, `awaiting` и снимок без
/// суммы и контекста дают пустой результат (VIEW-6).
///
/// Токены суммы сессии: вход = `input + cacheRead + cacheWrite`, выход —
/// `output` (D11). Сегмент токенов скрыт, если оба числа нулевые; цена
/// `null` скрывает стоимость, а известный нуль печатается `$0.00`.
UsageSegments usageSegmentsOf(UsageView? usage) {
  if (usage == null) return const UsageSegments();
  final context = switch (usage.context) {
    final fill? => usageContextOf(fill),
    null => null,
  };
  final session = usage.session;
  String? tokens;
  String? cost;
  if (session != null) {
    final counts = session.tokens;
    final input = usageInputTokens(counts);
    if (input > 0 || counts.output > 0) {
      final mark = usageTokensPartial(session.partial) ? '~' : '';
      tokens =
          '$mark↑${formatUsageTokens(input)} '
          '↓${formatUsageTokens(counts.output)}';
    }
    if (session.cost case final money?) {
      final mark = usageCostPartial(session.partial) ? '~' : '';
      // Валюту декодер ограничивает `^[A-Z]{3}$`, но сегмент собирается и из
      // `UsageView`, пришедшего не из декодера: очищаем и его.
      cost = sanitizeStatusText('$mark${formatUsageMoney(money)}');
    }
  }
  return UsageSegments(
    context: context == null ? null : 'ctx ${context.label}',
    contextLevel: context?.level,
    tokens: tokens,
    cost: cost,
  );
}

/// Текущее значение опции сессии [name] (`mode`, `model`): по id, затем по
/// категории — так же ищут `/mode` и `/model`.
String? sessionOptionValue(SessionView? session, String name) {
  final options = session?.configOptions ?? const <ConfigOptionView>[];
  return (options.where((o) => o.id == name).firstOrNull ??
          options.where((o) => o.category == name).firstOrNull)
      ?.currentValue;
}

/// Строка статуса после хода в REPL: `─ <режим> · <модель> · ctx N% ·
/// ↑… ↓… · $…` (D12, Q9 (б)); `null`, если нечего показать.
///
/// Без усечения по ширине: требование REPL его не задаёт (D23 Т5). Режим и
/// модель приходят от агента и очищаются от управляющих символов здесь же
/// ([sanitizeStatusText]): ESC в строке статуса мог бы двигать курсор или
/// писать в заголовок окна терминала (§12.2.11, TUI-11).
String? afterTurnStatusLine(SessionView? session) {
  final segments = usageSegmentsOf(session?.usage);
  final parts = [
    ?sessionOptionValue(session, 'mode'),
    ?sessionOptionValue(session, 'model'),
  ].map(sanitizeStatusText).toList();
  parts.addAll([?segments.context, ?segments.tokens, ?segments.cost]);
  return parts.isEmpty ? null : '─ ${parts.join(' · ')}';
}

/// Текст сегмента статус-строки без управляющих символов терминала и без
/// переводов строки: сегмент всегда однострочный.
///
/// Почему: строку статуса собирает клиент, но тексты режима, модели и
/// валюты приходят от агента; каждый сегмент в REPL и TUI проходит через
/// эту функцию ([sanitizeTerminalText] оставляет `\n`, а в строке статуса
/// он ломал бы раскладку).
String sanitizeStatusText(String text) =>
    sanitizeTerminalText(text).replaceAll('\n', ' ');
