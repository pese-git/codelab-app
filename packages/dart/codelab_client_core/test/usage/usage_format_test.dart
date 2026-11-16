// Форматирование usage для отображения (задача 3.0 change
// `add-usage-extension`; design.md, D24, D22 п. 4, Q16 (а), Q17 (а); spec
// agent-workbench-ui «Формат денег», «Процент вниз», «Меньше одного
// процента»; codelab-tui «Форматы чисел», «Цвет по целому проценту»).
//
// Красные тесты: `lib/src/usage/usage_format.dart` ещё нет (задача 3.0a),
// файл не компилируется. Имена функций и типа ниже выбраны тестом, а не
// спецификацией («Имена — исполнителю», D24): `formatUsageMoney`,
// `formatUsageTokens`, `usageContextOf` → `UsageContextLabel?` (`label`,
// `level`), `UsageLevel` (`normal`, `warning`, `danger`),
// `usageTokensPartial`, `usageCostPartial`. Исполнитель вправе
// переименовать, но тогда меняет и тест.
//
// Функция общая для desktop и CLI: одинаковые числа на двух экранах — смысл
// решения Q16 (а). Только целые, без `double` и локали (web-безопасность).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

Money _usd(int micros) => Money(micros: micros, currency: 'USD');

ContextFillView _ctx(int used, [int? size]) =>
    ContextFillView(used: used, size: size);

void main() {
  group('деньги', () {
    // Микроединицы: 1.2 → 1 200 000, 0.0041 → 4 100 и так далее.
    for (final (micros, text) in [
      (0, r'$0.00'),
      (1200000, r'$1.20'),
      (125000, r'$0.13'),
      (1234567, r'$1.23'),
      (10000, r'$0.01'),
      (4100, r'$0.0041'),
      (4000, r'$0.004'),
      (4567, r'$0.0046'),
      (9995, r'$0.01'),
      (9999, r'$0.01'),
      (1, r'$0.000001'),
    ]) {
      test('$micros микро → $text', () {
        expect(formatUsageMoney(_usd(micros)), text);
      });
    }

    test('валюта не USD — суффикс через пробел', () {
      expect(
        formatUsageMoney(const Money(micros: 12340000, currency: 'EUR')),
        '12.34 EUR',
      );
    });

    test('огромная сумма не переполняет целые', () {
      // Сумма с провода может быть любой; формат не должен бросать.
      expect(
        formatUsageMoney(_usd(9007199254740993)),
        startsWith(r'$9007199254.'),
      );
    });
  });

  group('токены', () {
    for (final (count, text) in [
      (0, '0'),
      (999, '999'),
      (1000, '1.0k'),
      (7249, '7.2k'),
      (94049, '94.0k'),
      (999949, '999.9k'),
      (999950, '1.0M'),
      (1000000, '1.0M'),
      (1234567, '1.2M'),
    ]) {
      test('$count → $text', () {
        expect(formatUsageTokens(count), text);
      });
    }
  });

  group('контекст', () {
    test('без size, при size <= 0 и при used = 0 сегмента нет', () {
      expect(usageContextOf(_ctx(5000)), isNull);
      expect(usageContextOf(_ctx(5000, 0)), isNull);
      expect(usageContextOf(_ctx(5000, -1)), isNull);
      expect(usageContextOf(_ctx(0, 200000)), isNull);
    });

    for (final (used, label, level) in [
      (159200, '79%', UsageLevel.normal),
      (160000, '80%', UsageLevel.warning),
      (189999, '94%', UsageLevel.warning),
      (190000, '95%', UsageLevel.danger),
      (500, '<1%', UsageLevel.normal),
      (1999, '<1%', UsageLevel.normal),
      (2000, '1%', UsageLevel.normal),
      (200000, '100%', UsageLevel.danger),
      (250000, '125%', UsageLevel.danger),
    ]) {
      test('$used из 200000 → $label, $level', () {
        final context = usageContextOf(_ctx(used, 200000))!;
        expect(context.label, label);
        expect(context.level, level);
      });
    }

    test('огромные used и size считаются без переполнения (D22 п. 4)', () {
      const huge = 1 << 62;
      expect(usageContextOf(_ctx(huge, huge))!.label, '100%');
      expect(usageContextOf(_ctx(huge, (1 << 63) - 1))!.label, '50%');
      expect(usageContextOf(_ctx(huge, huge))!.level, UsageLevel.danger);
    });
  });

  group('«~»', () {
    test('токены неполны при noUsage или beforeLoad, но не при noPrice', () {
      expect(usageTokensPartial(const {}), isFalse);
      expect(usageTokensPartial({UsagePartial.noUsage}), isTrue);
      expect(usageTokensPartial({UsagePartial.beforeLoad}), isTrue);
      expect(usageTokensPartial({UsagePartial.noPrice}), isFalse);
      expect(
        usageTokensPartial({UsagePartial.noPrice, UsagePartial.noUsage}),
        isTrue,
      );
    });

    test('стоимость неполна при любой причине', () {
      expect(usageCostPartial(const {}), isFalse);
      for (final reason in UsagePartial.values) {
        expect(usageCostPartial({reason}), isTrue, reason: '$reason');
      }
    });
  });
}
