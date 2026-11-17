/// Форматирование usage для отображения (D24, решения Q16 (а), Q17 (а)).
///
/// Почему отдельная функция kit: desktop и CLI (TUI и REPL) показывают одни и
/// те же числа, и правило округления не должно жить в двух местах — иначе
/// экраны разойдутся (D24, альтернативы отклонены пользователем).
///
/// Для чего: хосты собирают из этих строк свои сегменты (состав сегментов —
/// у хоста: D11, D12) и сами выбирают цвет по [UsageLevel].
///
/// Как использовать: `formatUsageMoney(totals.cost!)`,
/// `formatUsageTokens(tokens.input)`, `usageContextOf(usage.context!)`;
/// «~» ставит хост по [usageTokensPartial] и [usageCostPartial] (D6).
///
/// Web-безопасно: только целые (`BigInt` — из `dart:core`), без `double`,
/// `intl` и локали; разделитель дробной части — всегда точка.
library;

import 'usage_models.dart';

/// Уровень заполнения контекста: тон хоста (`CodeLabTone`, SGR) выбирает он
/// сам (D24, Q17 (а)).
enum UsageLevel {
  /// Меньше 80 %.
  normal,

  /// От 80 % (D2, D5).
  warning,

  /// От 95 %.
  danger,
}

/// Готовая подпись контекста и её уровень.
class UsageContextLabel {
  const UsageContextLabel({required this.label, required this.level});

  /// `79%`, `<1%`, `125%` — без пробела перед `%`.
  final String label;

  /// Уровень по тому же целому проценту, что и [label] (Q17 (а)).
  final UsageLevel level;

  @override
  bool operator ==(Object other) =>
      other is UsageContextLabel &&
      other.label == label &&
      other.level == level;

  @override
  int get hashCode => Object.hash(label, level);

  @override
  String toString() => 'UsageContextLabel($label, $level)';
}

/// Деньги: `$1.20`, `$0.0041`, `12.34 EUR` (D24).
///
/// От 0,01 — два знака, половина вверх; ниже — две значащие цифры от первой
/// ненулевой без хвостовых нулей; нуль — `0.00`. Отрицательная сумма (не
/// бывает по D9) показывается как нуль, а не бросает.
String formatUsageMoney(Money money) {
  final micros = money.micros < 0 ? 0 : money.micros;
  final number = _moneyNumber(micros);
  return money.currency == 'USD' ? '\$$number' : '$number ${money.currency}';
}

String _moneyNumber(int micros) {
  if (micros >= 10000) {
    // Сначала делим, потом прибавляем: `micros + 5000` переполнило бы `int`
    // на огромных значениях с провода.
    final cents = micros ~/ 10000 + (micros % 10000 >= 5000 ? 1 : 0);
    final fraction = (cents % 100).toString().padLeft(2, '0');
    return '${cents ~/ 100}.$fraction';
  }
  if (micros == 0) return '0.00';
  // Шаг округления оставляет две значащие цифры (`0.0046`), для `< 100`
  // микро значащие цифры уже исчерпаны.
  final step = micros >= 1000
      ? 100
      : micros >= 100
      ? 10
      : 1;
  final rounded = (micros + step ~/ 2) ~/ step * step;
  // Округление до 0,01 (`0.009995`) не должно давать `0.010000`.
  if (rounded >= 10000) return '0.01';
  final digits = rounded.toString().padLeft(6, '0');
  final trimmed = digits.replaceFirst(RegExp(r'0+$'), '');
  return '0.$trimmed';
}

/// Токены: `999`, `94.0k`, `1.2M` (D24), половина вверх, один знак.
String formatUsageTokens(int count) {
  if (count < 1000) return count < 0 ? '0' : '$count';
  if (count < 1000000) {
    final tenths = (count * 10 + 500) ~/ 1000;
    if (tenths >= 10000) return '1.0M';
    return '${tenths ~/ 10}.${tenths % 10}k';
  }
  final tenths = count ~/ 100000 + (count % 100000 >= 50000 ? 1 : 0);
  return '${tenths ~/ 10}.${tenths % 10}M';
}

/// Предел суммы токенов: 2^53 − 1 — наибольшее целое, точное и на web, где
/// `int` — число с плавающей точкой (D22).
const _maxSafeCount = 9007199254740991;

/// Токены входа сессии: `input + cacheRead + cacheWrite` (D11, D24).
///
/// Почему в kit: desktop и CLI показывают одно и то же «↑»; сумма чисел с
/// провода (декодер проверяет лишь неотрицательность) на VM переполнила бы
/// `int` и дала отрицательное значение, а на web потеряла бы точность.
///
/// Как использовать: `formatUsageTokens(usageInputTokens(totals.tokens))`.
/// Сумма насыщается на 2^53 − 1; слагаемые неотрицательны.
int usageInputTokens(TokenCounts tokens) {
  var sum = 0;
  for (final value in [tokens.input, tokens.cacheRead, tokens.cacheWrite]) {
    if (value >= _maxSafeCount - sum) return _maxSafeCount;
    sum += value;
  }
  return sum;
}

/// Подпись и уровень контекста; `null` — сегмент скрыт (D24, Q17 (а)).
///
/// Скрыт без `size`, при `size ≤ 0` и при `used = 0`. Процент целый, вниз;
/// `<1%` при `0 < used` и нулевом проценте; больше 100 % показывается как
/// есть. Считается через `BigInt`: `used × 100` у огромных значений с провода
/// переполнило бы `int` (D22 п. 4).
UsageContextLabel? usageContextOf(ContextFillView context) {
  final size = context.size;
  if (size == null || size <= 0 || context.used <= 0) return null;
  final percent =
      (BigInt.from(context.used) * BigInt.from(100) ~/ BigInt.from(size))
          .toInt();
  final level = percent >= 95
      ? UsageLevel.danger
      : percent >= 80
      ? UsageLevel.warning
      : UsageLevel.normal;
  return UsageContextLabel(
    label: percent == 0 ? '<1%' : '$percent%',
    level: level,
  );
}

/// Токены неполны: `noUsage` или `beforeLoad` (D6, D24). `noPrice` токены не
/// занижает.
bool usageTokensPartial(Set<UsagePartial> partial) =>
    partial.contains(UsagePartial.noUsage) ||
    partial.contains(UsagePartial.beforeLoad);

/// Стоимость неполна при любой причине (D6, D24).
bool usageCostPartial(Set<UsagePartial> partial) => partial.isNotEmpty;

/// Точная десятичная запись суммы для экспорта (D5 change
/// `add-desktop-usage-pane`; acp-client-kit «Точная запись суммы usage»).
///
/// Заглушка задачи 1.2: реализация — задача 1.3.
String formatUsageMoneyExact(Money money) => throw UnimplementedError();
