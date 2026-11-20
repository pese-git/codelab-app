// Тесты `CodeLabSettingsRow` (задача 1.4 change `add-app-settings-shell`;
// D16): заголовок, описание, `trailing`, ключ теста.

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpRow(WidgetTester tester, Widget row) => tester.pumpWidget(
    FluentApp(
      home: Center(child: SizedBox(width: 600, child: row)),
    ),
  );

  testWidgets('shows title, description and the trailing control', (
    tester,
  ) async {
    var toggled = false;
    await pumpRow(
      tester,
      CodeLabSettingsRow(
        title: 'Connect on start',
        description: 'Connect to the default profile when CodeLab opens.',
        trailing: ToggleSwitch(checked: toggled, onChanged: (v) => toggled = v),
      ),
    );

    expect(find.text('Connect on start'), findsOneWidget);
    expect(
      find.text('Connect to the default profile when CodeLab opens.'),
      findsOneWidget,
    );
    expect(find.byType(ToggleSwitch), findsOneWidget);
  });

  testWidgets('works without a description or trailing control', (
    tester,
  ) async {
    await pumpRow(tester, const CodeLabSettingsRow(title: 'Only title'));

    expect(find.text('Only title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the test key passed by the owner', (tester) async {
    await pumpRow(
      tester,
      const CodeLabSettingsRow(
        key: ValueKey('settings-row-demo'),
        title: 'Keyed',
      ),
    );

    expect(find.byKey(const ValueKey('settings-row-demo')), findsOneWidget);
  });

  testWidgets('a wide fixed trailing shrinks on a narrow row and the title '
      'stays on one line', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 368,
            child: CodeLabSettingsRow(
              title: 'Default model',
              description: 'Used by new sessions.',
              leading: FluentIcons.settings,
              trailing: SizedBox(
                key: ValueKey('wide-trailing'),
                width: 260,
                child: Text('control'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text('Default model')).height, lessThan(24));
    expect(
      tester.getSize(find.byKey(const ValueKey('wide-trailing'))).width,
      lessThan(260),
    );
  });

  testWidgets('on a wide row the trailing keeps its own width', (tester) async {
    await pumpRow(
      tester,
      const CodeLabSettingsRow(
        title: 'Default model',
        trailing: SizedBox(
          key: ValueKey('wide-trailing'),
          width: 260,
          child: Text('control'),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const ValueKey('wide-trailing'))).width,
      260,
    );
  });

  // Перенос описаний на узком окне (задача 7.5 change `add-app-general-page`,
  // D17): страница «General» не должна обрезать смысл строки многоточием, а
  // остальные страницы остаются на двух строках.
  group('descriptionMaxLines', () {
    const long =
        'Включено: открывать последний проект и его открытые сессии. '
        'Выключено: начинать с недавних проектов в боковой панели. '
        'Применится при следующем запуске, когда окно уже закрыто и открыто.';

    CodeLabText descriptionOf(WidgetTester tester) =>
        tester.widget<CodeLabText>(
          find.byWidgetPredicate((w) => w is CodeLabText && w.data == long),
        );

    testWidgets('по умолчанию — две строки с многоточием, как у прочих '
        'страниц', (tester) async {
      await pumpRow(
        tester,
        const CodeLabSettingsRow(title: 'Title', description: long),
      );

      final text = descriptionOf(tester);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('null — без ограничения и без многоточия', (tester) async {
      await pumpRow(
        tester,
        const CodeLabSettingsRow(
          title: 'Title',
          description: long,
          descriptionMaxLines: null,
        ),
      );

      final text = descriptionOf(tester);
      expect(text.maxLines, isNull);
      expect(text.overflow, isNot(TextOverflow.ellipsis));
    });

    testWidgets('null: описание показано целиком, высота больше двух '
        'строк', (tester) async {
      await pumpRow(
        tester,
        const CodeLabSettingsRow(title: 'Title', description: long),
      );
      final clamped = tester.getSize(find.byType(CodeLabSettingsRow)).height;
      await pumpRow(
        tester,
        const CodeLabSettingsRow(
          title: 'Title',
          description: long,
          descriptionMaxLines: null,
        ),
      );
      final full = tester.getSize(find.byType(CodeLabSettingsRow)).height;

      expect(full, greaterThan(clamped));
    });

    testWidgets('явное число строк применяется', (tester) async {
      await pumpRow(
        tester,
        const CodeLabSettingsRow(
          title: 'Title',
          description: long,
          descriptionMaxLines: 3,
        ),
      );

      expect(descriptionOf(tester).maxLines, 3);
    });
  });

  // `footer` (ручная проверка macOS, change `add-app-appearance-page`): элемент
  // под строкой заголовка рисуется внутри карточки, а не отдельным блоком под
  // ней.
  group('footer', () {
    Finder card() => find
        .ancestor(
          of: find.text('Row title'),
          matching: find.byType(DecoratedBox),
        )
        .last;

    testWidgets('рисуется внутри карточки строки, под заголовком и описанием', (
      tester,
    ) async {
      await pumpRow(
        tester,
        const CodeLabSettingsRow(
          title: 'Row title',
          description: 'Row description',
          footer: Text('Footer content', key: ValueKey('row-footer')),
        ),
      );

      expect(
        find.descendant(
          of: card(),
          matching: find.byKey(const ValueKey('row-footer')),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-footer'))).dy,
        greaterThan(tester.getBottomLeft(find.text('Row description')).dy),
      );
      // Та же горизонтальная подложка 16, что у заголовка.
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('row-footer'))).dx,
        tester.getTopLeft(find.text('Row title')).dx,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('без footer высота строки прежняя', (tester) async {
      await pumpRow(
        tester,
        const CodeLabSettingsRow(title: 'Row title', description: 'Row text'),
      );
      final before = tester.getSize(card()).height;

      await pumpRow(
        tester,
        const CodeLabSettingsRow(
          title: 'Row title',
          description: 'Row text',
          footer: SizedBox(height: 30),
        ),
      );

      expect(tester.getSize(card()).height, greaterThan(before));
      await pumpRow(
        tester,
        const CodeLabSettingsRow(title: 'Row title', description: 'Row text'),
      );
      expect(tester.getSize(card()).height, before);
    });

    testWidgets('footer и trailing вместе не переполняют строку', (
      tester,
    ) async {
      await pumpRow(
        tester,
        CodeLabSettingsRow(
          title: 'Row title',
          trailing: ToggleSwitch(checked: false, onChanged: (_) {}),
          footer: const Text('Footer'),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
