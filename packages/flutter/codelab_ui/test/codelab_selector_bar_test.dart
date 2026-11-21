// Молекула `CodeLabSelectorBar` — вкладки-переключатель разделов (задача 3.1
// change `add-app-legal-page`; design.md D6; spec app-settings «Страница
// «Legal»: видимость и вкладки», сценарий «Узкое окно на русском»).
//
// Реализация — задача 3.2: `lib/src/molecules/codelab_selector_bar.dart`,
// `CodeLabSelectorBar<T>({items, value, onChanged, semanticLabel})` и
// `CodeLabSelectorItem<T>({value, label, key})`. Проверяется поведение, а не
// пиксели: ключи, нажатие и клавиши, семантика, узкая ширина, цвета темы.

import 'dart:ui' show Tristate;

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

const _items = [
  CodeLabSelectorItem<String>(
    value: 'privacy',
    label: 'Политика конфиденциальности',
    key: ValueKey('tab-privacy'),
  ),
  CodeLabSelectorItem<String>(
    value: 'terms',
    label: 'Условия использования',
    key: ValueKey('tab-terms'),
  ),
  CodeLabSelectorItem<String>(
    value: 'license',
    label: 'Лицензия',
    key: ValueKey('tab-license'),
  ),
  CodeLabSelectorItem<String>(
    value: 'notices',
    label: 'Сторонние уведомления',
    key: ValueKey('tab-notices'),
  ),
];

Widget _app(
  Widget bar, {
  double width = 800,
  Brightness brightness = Brightness.light,
}) => FluentApp(
  theme: FluentThemeData(brightness: brightness),
  home: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: width, child: bar),
  ),
);

CodeLabSelectorBar<String> _bar({
  String value = 'privacy',
  ValueChanged<String>? onChanged,
}) => CodeLabSelectorBar<String>(
  items: _items,
  value: value,
  onChanged: onChanged ?? (_) {},
  semanticLabel: 'Legal documents',
);

void main() {
  group('ключи и подписи', () {
    testWidgets('ключи вкладок задаёт вызывающий, подписи видны', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_bar()));

      for (final item in _items) {
        expect(find.byKey(item.key!), findsOneWidget);
        expect(find.text(item.label), findsOneWidget);
      }
    });
  });

  group('нажатие', () {
    testWidgets('нажатие на другую вкладку вызывает onChanged', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(_app(_bar(onChanged: picked.add)));

      await tester.tap(find.byKey(const ValueKey('tab-terms')));
      await tester.pumpAndSettle(const Duration(seconds: 1));

      expect(picked, ['terms']);
    });

    testWidgets(
      'повторное нажатие на выбранную вкладку не вызывает onChanged',
      (tester) async {
        final picked = <String>[];
        await tester.pumpWidget(_app(_bar(onChanged: picked.add)));

        await tester.tap(find.byKey(const ValueKey('tab-privacy')));
        await tester.pumpAndSettle(const Duration(seconds: 1));

        expect(picked, isEmpty);
      },
    );
  });

  group('клавиатура', () {
    testWidgets('Tab переводит фокус на вкладку, Enter выбирает её', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(_app(_bar(onChanged: picked.add)));

      // Первая вкладка — выбранная; вторая получает фокус вторым Tab.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(picked, ['terms']);
    });

    testWidgets('Space выбирает вкладку с фокусом', (tester) async {
      final picked = <String>[];
      await tester.pumpWidget(_app(_bar(onChanged: picked.add)));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(picked, ['terms']);
    });

    testWidgets('Enter на выбранной вкладке не вызывает onChanged', (
      tester,
    ) async {
      final picked = <String>[];
      await tester.pumpWidget(_app(_bar(onChanged: picked.add)));

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(picked, isEmpty);
    });
  });

  group('семантика', () {
    testWidgets('у группы есть подпись, у выбранной вкладки — selected', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(_bar(value: 'terms')));

      expect(find.bySemanticsLabel('Legal documents'), findsOneWidget);
      Tristate selected(String key) => tester
          .getSemantics(find.byKey(ValueKey(key)))
          .flagsCollection
          .isSelected;
      expect(selected('tab-terms'), Tristate.isTrue);
      expect(selected('tab-privacy'), Tristate.isFalse);
      expect(selected('tab-license'), Tristate.isFalse);
      expect(
        tester
            .getSemantics(find.byKey(const ValueKey('tab-terms')))
            .flagsCollection
            .isButton,
        isTrue,
      );
      handle.dispose();
    });
  });

  group('узкая ширина', () {
    testWidgets('в 400 px длинные русские подписи без многоточия и '
        'переполнения, есть горизонтальная прокрутка', (tester) async {
      await tester.pumpWidget(_app(_bar(), width: 400));

      expect(tester.takeException(), isNull);
      for (final item in _items) {
        final text = tester.widget<Text>(find.text(item.label));
        expect(
          text.overflow,
          isNot(TextOverflow.ellipsis),
          reason: 'подпись «${item.label}» обрезана многоточием',
        );
      }
      final scrollables = tester.widgetList<Scrollable>(
        find.byType(Scrollable),
      );
      expect(
        scrollables.any((s) => s.axis == Axis.horizontal),
        isTrue,
        reason: 'вкладки не помещаются и должны прокручиваться по горизонтали',
      );
    });

    testWidgets('последнюю вкладку можно прокрутить в видимую область', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_bar(), width: 400));

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tab-notices')),
        100,
        scrollable: find.byType(Scrollable).first,
      );

      final rect = tester.getRect(find.byKey(const ValueKey('tab-notices')));
      expect(rect.right, lessThanOrEqualTo(400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('в широком окне прокрутки нет: вкладки помещаются', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_bar(), width: 1200));

      final right = tester
          .getRect(find.byKey(const ValueKey('tab-notices')))
          .right;
      expect(right, lessThanOrEqualTo(1200));
      expect(tester.takeException(), isNull);
    });
  });

  group('цвета из FluentTheme', () {
    for (final brightness in Brightness.values) {
      testWidgets('подпись выбранной вкладки — textFillColorPrimary темы '
          '(${brightness.name})', (tester) async {
        await tester.pumpWidget(_app(_bar(), brightness: brightness));

        final resources = FluentThemeData(brightness: brightness).resources;
        final text = tester.widget<Text>(
          find.text('Политика конфиденциальности'),
        );
        final color =
            text.style?.color ??
            DefaultTextStyle.of(
              tester.element(find.text('Политика конфиденциальности')),
            ).style.color;
        expect(color, resources.textFillColorPrimary);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
