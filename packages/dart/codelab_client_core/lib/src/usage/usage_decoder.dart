import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';

import 'usage_models.dart';

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

    // Валюта нужна только стоимости; читается один раз для обоих агрегатов.
    final currency = params['currency'];
    final currencyText = currency is String && currency.isNotEmpty
        ? currency
        : null;
    var currencyWarned = false;
    String? currencyFor() {
      if (currencyText == null && !currencyWarned) {
        currencyWarned = true;
        onWarning('currency', 'required_with_cost');
      }
      return currencyText;
    }

    final session = _totals(
      params['session'],
      'session',
      required: true,
      currencyFor: currencyFor,
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
        ? _totals(
            params['turn'],
            'turn',
            required: false,
            currencyFor: currencyFor,
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
        _ => UsageTrigger.unknown,
      },
      turnId: turnId,
      turn: turn,
      session: session,
      context: _context(params['context'], onWarning),
    );
  }

  /// Агрегат [name] (`turn` или `session`); `null` при [required] — снимок
  /// отброшен, иначе — поля нет.
  UsageTotals? _totals(
    Object? raw,
    String name, {
    required bool required,
    required String? Function() currencyFor,
    required void Function(String field, String reason) onWarning,
  }) {
    if (raw == null && !required) {
      return null;
    }
    if (raw is! Map) {
      onWarning(name, required ? 'required' : 'wrong_type');
      return null;
    }
    final tokens = _tokens(raw['tokens']);
    if (tokens == null) {
      onWarning('$name.tokens', required ? 'required' : 'wrong_type');
      return null;
    }

    final steps = raw['steps'];
    if (steps != null && (steps is! int || steps < 0)) {
      onWarning('$name.steps', 'wrong_type');
    }

    Money? cost;
    final rawCost = raw['cost'];
    if (rawCost != null) {
      final micros = rawCost is String ? parseMicros(rawCost) : null;
      final currency = micros == null ? null : currencyFor();
      if (micros == null) {
        onWarning('$name.cost', 'wrong_format');
      } else if (currency != null) {
        cost = Money(micros: micros, currency: currency);
      }
    }

    final partial = <UsagePartial>{};
    final rawPartial = raw['partial'];
    if (rawPartial is List) {
      for (final reason in rawPartial) {
        // Незнакомые причины и не строки — молча (D2, правила совместимости).
        for (final known in UsagePartial.values) {
          if (reason == known.name) {
            partial.add(known);
          }
        }
      }
    } else if (rawPartial != null) {
      onWarning('$name.partial', 'wrong_type');
    }

    return UsageTotals(
      tokens: tokens,
      cost: cost,
      steps: steps is int && steps >= 0 ? steps : 0,
      partial: Set.unmodifiable(partial),
    );
  }

  TokenCounts? _tokens(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final input = _count(raw['input']);
    final output = _count(raw['output']);
    final cacheRead = _count(raw['cacheRead']);
    final cacheWrite = _count(raw['cacheWrite']);
    if (input == null ||
        output == null ||
        cacheRead == null ||
        cacheWrite == null) {
      return null;
    }
    return TokenCounts(
      input: input,
      output: output,
      cacheRead: cacheRead,
      cacheWrite: cacheWrite,
      // `reasoning` необязателен: неверный тип — поля просто нет.
      reasoning: _count(raw['reasoning']),
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
    final used = _count(raw['used']);
    if (used == null) {
      onWarning('context', 'wrong_type');
      return null;
    }
    int? optional(String key) {
      final value = raw[key];
      final count = _count(value);
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

  /// Целое ≥ 0 или `null`.
  static int? _count(Object? value) =>
      value is int && value >= 0 ? value : null;

  /// Деньги D9 → микроединицы; `null` — строка не по формату.
  ///
  /// Формат `^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$`: без знака, экспоненты и
  /// больше 6 знаков. Целая часть ограничена 9 цифрами: `micros` держится в
  /// 2^53 и на web, где `int` — число с плавающей точкой; миллиарда
  /// долларов за сессию достаточно (предел — решение D22: точное целое на web). Разбор целочисленный — без
  /// `double`, поэтому строка и число совпадают точно.
  static int? parseMicros(String text) {
    final match = _moneyPattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    final whole = int.parse(match.group(1)!);
    final fraction = (match.group(2) ?? '').padRight(6, '0');
    return whole * 1000000 + int.parse(fraction);
  }
}

final _moneyPattern = RegExp(r'^(0|[1-9][0-9]{0,8})(?:\.([0-9]{1,6}))?$');
