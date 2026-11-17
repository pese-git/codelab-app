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
