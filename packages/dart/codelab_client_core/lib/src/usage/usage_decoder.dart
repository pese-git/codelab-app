import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import 'usage_models.dart';
import 'usage_parsing.dart';

/// Разбор параметров `_codelab/session/usage` версии 1 (D2, D8, D9).
///
/// Почему: форма расширения известна одному месту — `_meta.codelab.*`
/// разбирается только в `codelab_client_acp` и ядре клиента, а виджеты и
/// хосты `_meta` не парсят (`AGENTS.md` пакета §5). Одна форма — одна
/// реализация, поэтому интерфейса нет (`AGENTS.md` §13, D8).
///
/// Для чего: превращает сырые `params` в [UsageSnapshot]. Разбор терпимый
/// (расширение — данные стороннего агента): исключений нет; неизвестные поля
/// и причины игнорируются; необязательное поле неверного типа отсутствует в
/// результате, а обязательное (`sessionId`, `seq`, `trigger`, `session.tokens`)
/// отбрасывает снимок целиком (`null`). На каждое неразобранное поле
/// вызывается `onWarning` один раз; в него идут имя поля и короткая причина,
/// но не сырое значение (в журнал не должны попасть данные агента).
///
/// Как использовать: `UsageDecoder().decode(params, onWarning: …)`; ограничение
/// «не чаще раза на сессию и поле» (D14) накладывает вызывающий.
final class UsageDecoder {
  const UsageDecoder();

  /// Разбирает [params]; `null` — снимок отброшен (причина уже в [onWarning]).
  UsageSnapshot? decode(
    Map<String, Object?> params, {
    required void Function(String field, String reason) onWarning,
  }) {
    final sessionId = params['sessionId'];
    if (sessionId is! String || sessionId.isEmpty) {
      onWarning('sessionId', 'required');
      return null;
    }
    final seq = params['seq'];
    if (seq is! int || seq < 1) {
      onWarning('seq', 'required');
      return null;
    }
    final triggerName = params['trigger'];
    if (triggerName is! String) {
      onWarning('trigger', 'required');
      return null;
    }

    // Валюта читается один раз для обоих агрегатов (общее правило с журналом
    // usage, D10): неверный формат — стоимости нет, снимок применяется.
    final currency = UsageCurrency(params['currency'], onWarning);

    final session = parseUsageTotals(
      params['session'],
      'session',
      required: true,
      currency: currency,
      onWarning: onWarning,
    );
    if (session == null) {
      return null;
    }

    final rawTurnId = params['turnId'];
    String? turnId;
    if (rawTurnId is String) {
      turnId = rawTurnId;
    } else if (rawTurnId != null) {
      onWarning('turnId', 'wrong_type');
    }

    final turn = params.containsKey('turn')
        ? parseUsageTotals(
            params['turn'],
            'turn',
            required: false,
            currency: currency,
            onWarning: onWarning,
          )
        : null;

    return UsageSnapshot(
      sessionId: SessionId(sessionId),
      seq: seq,
      trigger: switch (triggerName) {
        'step' => UsageTrigger.step,
        'turn' => UsageTrigger.turn,
        'compaction' => UsageTrigger.compaction,
        'load' => UsageTrigger.load,
        _ => UsageTrigger.unknown,
      },
      turnId: turnId,
      turn: turn,
      session: session,
      context: _context(params['context'], onWarning),
      // `budget` бывает только у снимков с ходом (D7): у `compaction`, `load`
      // и `compactionDiscarded` поле, если агент его всё же прислал, не
      // читается — свёртка всё равно не стала бы его применять.
      budget: turnId == null
          ? null
          : _budget(params['budget'], currency, onWarning),
    );
  }

  /// Поле `budget` снимка (D9, «Разбор»): подполя разбираются независимо,
  /// неверное отбрасывается с предупреждением `budget.<подполе>`; без единого
  /// известного подполя результат `null`. Незнакомые ключи молча игнорируются
  /// (будущий `deadline`, D7).
  UsageBudget? _budget(
    Object? raw,
    UsageCurrency currency,
    UsageWarn onWarning,
  ) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      onWarning('budget', 'wrong_type');
      return null;
    }
    final budget = UsageBudget(
      steps: _count(raw, 'steps', 'used', 'limit', onWarning, _countOf),
      tokens: _count(raw, 'tokens', 'used', 'limit', onWarning, _countOf),
      cost: _cost(raw['cost'], currency, onWarning),
      duration: _count(
        raw,
        'duration',
        'usedMs',
        'limitMs',
        onWarning,
        (used, limit) => BudgetDuration(usedMs: used, limitMs: limit),
      ),
    );
    final empty =
        budget.steps == null &&
        budget.tokens == null &&
        budget.cost == null &&
        budget.duration == null;
    return empty ? null : budget;
  }

  static BudgetCount _countOf(int used, int limit) =>
      BudgetCount(used: used, limit: limit);

  /// Подполе-пара целых ≥ 0 (`steps`, `tokens`, `duration`); `null` — подполя
  /// нет или оно неверно (предупреждение без сырого значения, §16).
  T? _count<T>(
    Map<Object?, Object?> budget,
    String name,
    String usedKey,
    String limitKey,
    UsageWarn onWarning,
    T Function(int used, int limit) make,
  ) {
    final raw = budget[name];
    if (raw == null) {
      return null;
    }
    final used = raw is Map ? usageCount(raw[usedKey]) : null;
    final limit = raw is Map ? usageCount(raw[limitKey]) : null;
    if (used == null || limit == null) {
      onWarning('budget.$name', 'wrong_type');
      return null;
    }
    return make(used, limit);
  }

  /// Подполе `cost`: `limit` — обязательные деньги, `used` — необязательные
  /// (нет `used` — цена неизвестна, D7). Правило денег и валюты — общее со
  /// стоимостью агрегатов (`parseUsageMicros`, [UsageCurrency]); без валюты
  /// подполе отбрасывается тем же предупреждением `currency`.
  BudgetCost? _cost(Object? raw, UsageCurrency currency, UsageWarn onWarning) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      onWarning('budget.cost', 'wrong_type');
      return null;
    }
    final rawLimit = raw['limit'];
    if (rawLimit == null) {
      onWarning('budget.cost', 'wrong_type');
      return null;
    }
    final limitMicros = rawLimit is String ? parseUsageMicros(rawLimit) : null;
    final rawUsed = raw['used'];
    final usedMicros = rawUsed is String ? parseUsageMicros(rawUsed) : null;
    if (limitMicros == null || (rawUsed != null && usedMicros == null)) {
      onWarning('budget.cost', 'wrong_format');
      return null;
    }
    final code = currency.forCost();
    if (code == null) {
      return null;
    }
    return BudgetCost(
      used: usedMicros == null
          ? null
          : Money(micros: usedMicros, currency: code),
      limit: Money(micros: limitMicros, currency: code),
    );
  }

  ContextFillView? _context(
    Object? raw,
    void Function(String field, String reason) onWarning,
  ) {
    if (raw == null) {
      return null;
    }
    if (raw is! Map) {
      onWarning('context', 'wrong_type');
      return null;
    }
    final used = usageCount(raw['used']);
    if (used == null) {
      onWarning('context', 'wrong_type');
      return null;
    }
    int? optional(String key) {
      final value = raw[key];
      final count = usageCount(value);
      if (value != null && count == null) {
        onWarning('context.$key', 'wrong_type');
      }
      return count;
    }

    return ContextFillView(
      used: used,
      size: optional('size'),
      compactAt: optional('compactAt'),
    );
  }

  /// Публичный API: деньги D9 → микроединицы; делегирует [parseUsageMicros].
  static int? parseMicros(String text) => parseUsageMicros(text);
}
