/// Общий терпимый разбор агрегата расхода для `UsageDecoder` и
/// `UsageLedgerDecoder` (change `add-usage-ledger`, D10).
///
/// Почему отдельный файл: правила денег (микроединицы без `double`, не более
/// 9 цифр целой части), валюты (`^[A-Z]{3}$`) и причин (`partial`, незнакомые
/// отбрасываются) должны быть в ОДНОМ месте — иначе снимок и журнал разойдутся
/// (D10: «у двух декодеров одно правило денег»).
///
/// Для чего: функции возвращают разобранное значение или `null` и сообщают о
/// неразобранном поле через `onWarning(field, reason)` — только имя поля и
/// короткая причина, без сырого значения (§16). Исключений нет.
library;

import 'usage_models.dart';

/// Допустимый код валюты (ISO 4217): три заглавные латинские буквы.
final RegExp _isoCurrency = RegExp(r'^[A-Z]{3}$');

/// Приёмник предупреждений разбора: поле и короткая причина.
typedef UsageWarn = void Function(String field, String reason);

/// Валюта корня снимка или журнала, прочитанная один раз для всех стоимостей.
///
/// Формат — ISO 4217: значение уходит в строки статуса хостов, и произвольный
/// текст агента (в том числе управляющие символы) туда не допускается. Поле
/// необязательное: снимок не отбрасывается, стоимость пропадает; причина —
/// `wrong_format` (без сырого значения), а стоимость без валюты — одно
/// предупреждение `required_with_cost`.
final class UsageCurrency {
  UsageCurrency(Object? raw, UsageWarn onWarning) : _onWarning = onWarning {
    if (raw is String) {
      if (_isoCurrency.hasMatch(raw)) {
        _code = raw;
      } else {
        _warned = true;
        onWarning('currency', 'wrong_format');
      }
    }
  }

  final UsageWarn _onWarning;
  String? _code;
  var _warned = false;

  /// Код валюты для стоимости; `null` — стоимости не будет.
  String? forCost() {
    if (_code == null && !_warned) {
      _warned = true;
      _onWarning('currency', 'required_with_cost');
    }
    return _code;
  }
}

/// Строка агента, очищенная для показа в терминале (журнал usage: `title`,
/// `model`, `ledger.reason`, `toolCallIds`).
///
/// Почему: хосты печатают эти строки в терминал, а ESC, OSC и BEL в них могли
/// бы двигать курсор, писать в заголовок окна или звонить (§16, `AGENTS.md`
/// пакета §5; ревью итерации 3). Поэтому удаляются управляющие символы C0
/// (U+0000–U+001F), DEL и C1 (U+007F–U+009F) — остаётся только обычный пробел
/// U+0020; табуляция и переводы строк тоже удаляются.
///
/// Предел [maxRunes] считается в рунах (кодовых точках), а не в единицах
/// UTF-16, чтобы не разрезать суррогатную пару. Значения пределов — у
/// вызывающего: `title` — 64 руны (подпись хода по словам пользователя, D1:
/// одна строка списка), `model` и идентификатор вызова — 128 (идентификаторы
/// провайдеров и вызовов не длиннее), `ledger.reason` — 64 (короткий код).
String sanitizeUsageText(String text, {required int maxRunes}) {
  final kept = <int>[];
  for (final rune in text.runes) {
    if (rune == 0x20 || (rune > 0x20 && rune < 0x7f) || rune > 0x9f) {
      kept.add(rune);
      if (kept.length == maxRunes) {
        break;
      }
    }
  }
  return String.fromCharCodes(kept);
}

/// Целое ≥ 0 или `null`.
int? usageCount(Object? value) => value is int && value >= 0 ? value : null;

/// Токены агрегата; `null` — не разобрались обязательные четыре счётчика.
/// `reasoning` необязателен: неверный тип — поля просто нет.
TokenCounts? parseUsageTokens(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final input = usageCount(raw['input']);
  final output = usageCount(raw['output']);
  final cacheRead = usageCount(raw['cacheRead']);
  final cacheWrite = usageCount(raw['cacheWrite']);
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
    reasoning: usageCount(raw['reasoning']),
  );
}

/// Стоимость поля `cost` объекта [raw] под именем [name]; `null` — цены нет.
Money? parseUsageCost(
  Map<Object?, Object?> raw,
  String name,
  UsageCurrency currency,
  UsageWarn onWarning,
) {
  final rawCost = raw['cost'];
  if (rawCost == null) {
    return null;
  }
  final micros = rawCost is String ? parseUsageMicros(rawCost) : null;
  if (micros == null) {
    onWarning('$name.cost', 'wrong_format');
    return null;
  }
  final code = currency.forCost();
  return code == null ? null : Money(micros: micros, currency: code);
}

/// Причины неполноты поля `partial`; незнакомые строки и не-строки — молча.
Set<UsagePartial> parseUsagePartial(
  Map<Object?, Object?> raw,
  String name,
  UsageWarn onWarning,
) {
  final rawPartial = raw['partial'];
  final partial = <UsagePartial>{};
  if (rawPartial is List) {
    for (final reason in rawPartial) {
      for (final known in UsagePartial.values) {
        if (reason == known.name) {
          partial.add(known);
        }
      }
    }
  } else if (rawPartial != null) {
    onWarning('$name.partial', 'wrong_type');
  }
  return Set.unmodifiable(partial);
}

/// Агрегат [name] (`turn`, `session`, `total`, …); `null` при [required] —
/// отброшен объект, иначе — поля нет.
UsageTotals? parseUsageTotals(
  Object? raw,
  String name, {
  required bool required,
  required UsageCurrency currency,
  required UsageWarn onWarning,
}) {
  if (raw == null && !required) {
    return null;
  }
  if (raw is! Map) {
    onWarning(name, required ? 'required' : 'wrong_type');
    return null;
  }
  final tokens = parseUsageTokens(raw['tokens']);
  if (tokens == null) {
    onWarning('$name.tokens', required ? 'required' : 'wrong_type');
    return null;
  }
  final steps = raw['steps'];
  if (steps != null && (steps is! int || steps < 0)) {
    onWarning('$name.steps', 'wrong_type');
  }
  // D2 change `fix-usage-pane-live-cards`: `turns` читается у любого
  // агрегата; неверный тип — `null` и предупреждение без сырого значения
  // (AGENTS.md §10, §16), снимок применяется.
  final turns = raw['turns'];
  if (turns != null && (turns is! int || turns < 0)) {
    onWarning('$name.turns', 'wrong_type');
  }
  return UsageTotals(
    tokens: tokens,
    cost: parseUsageCost(raw, name, currency, onWarning),
    steps: steps is int && steps >= 0 ? steps : 0,
    turns: turns is int && turns >= 0 ? turns : null,
    partial: parseUsagePartial(raw, name, onWarning),
  );
}

/// Деньги D9 → микроединицы; `null` — строка не по формату.
///
/// Формат `^(0|[1-9][0-9]*)(\.[0-9]{1,6})?$`: без знака, экспоненты и больше 6
/// знаков. Целая часть ограничена 9 цифрами: `micros` держится в 2^53 и на
/// web, где `int` — число с плавающей точкой (D22). Разбор целочисленный —
/// без `double`, поэтому строка и число совпадают точно.
int? parseUsageMicros(String text) {
  final match = _moneyPattern.firstMatch(text);
  if (match == null) {
    return null;
  }
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(6, '0');
  return whole * 1000000 + int.parse(fraction);
}

final _moneyPattern = RegExp(r'^(0|[1-9][0-9]{0,8})(?:\.([0-9]{1,6}))?$');
