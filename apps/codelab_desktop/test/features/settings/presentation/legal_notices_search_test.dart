// Красные тесты поиска по пакетам вкладки «Third-party notices» (задача 4.4
// change `add-app-legal-page`; spec app-settings «Страница «Legal»: поиск по
// пакетам», все сценарии; design.md D5–D7, D11; артборды `NoticesSearch`,
// `NoticesMatch`, `NoticesEmpty`).
//
// Реализация — задача 4.5: `features/settings/presentation/legal_page.dart`.
// Выдачу считает чистая функция (`package_license_search_test.dart`), а
// состояние — `LegalPageCubit` (`legal_page_cubit_test.dart`); здесь — что
// видно: подсветка `TextSpan`, счётчик, крестик, пустой блок, раскрытие,
// отсутствие следов запроса.
//
// Ключи (spec): `settings-legal-packages-search`, `-count`, `-clear`,
// `-empty`, `-empty-clear`, `settings-legal-package-<name>`,
// `settings-legal-notices-records`. Строки ARB (глоссарий): `Search packages`,
// `Search packages by name`, `Clear search`, `{count} packages`,
// `{matched} of {total} packages` (ICU `plural`), `No packages match`,
// `No package name contains “{query}”. The notices register above is not
// affected by search.`; на `ru` — `{matched} из {total} пакета`.

import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import '../../../support/test_app_scope.dart' show CodeLabTestBinding;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;

import '../../../support/legal_fixture.dart';

/// Маркер запроса: не должен встретиться ни в журнале, ни в хранилищах.
const _marker = 'marker-query-7f3a';

Finder _key(String value) => find.byKey(ValueKey(value));

Finder _package(String name) => _key('settings-legal-package-$name');

/// Строки пакетов, показанные сейчас (ключ `settings-legal-package-<name>`,
/// но не `settings-legal-packages-…`).
List<String> _shownPackages(WidgetTester tester) => [
  for (final element
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'settings-legal-package-',
                ),
          )
          .evaluate())
    (element.widget.key! as ValueKey<String>).value.substring(
      'settings-legal-package-'.length,
    ),
];

String _fieldText(WidgetTester tester) => tester
    .widget<EditableText>(
      find.descendant(
        of: _key('settings-legal-packages-search'),
        matching: find.byType(EditableText),
        matchRoot: true,
      ),
    )
    .controller
    .text;

/// Куски полужирного текста в имени пакета (`Text.rich` с `TextSpan`, D6).
List<String> _boldPieces(WidgetTester tester, String name) {
  final paragraph = find
      .descendant(
        of: _package(name),
        matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText() == name,
        ),
      )
      .first;
  final rich = tester.widget<RichText>(paragraph);
  final pieces = <String>[];
  rich.text.visitChildren((span) {
    if (span is TextSpan && (span.text ?? '').isNotEmpty) {
      final weight = span.style?.fontWeight;
      if (weight != null && weight.value >= 600) {
        pieces.add(span.text!);
      }
    }
    return true;
  });
  return pieces;
}

Future<void> _openNotices(
  WidgetTester tester,
  LegalFixture fixture, {
  Locale locale = const Locale('en'),
}) async {
  final binding = await openLegalPage(
    tester,
    fixture,
    locale: locale,
    size: const Size(1400, 3000),
  );
  // На русском вкладки длиннее окна и прокручиваются по горизонтали (D6).
  await tester.ensureVisible(_key('settings-legal-tab-third-party-notices'));
  await tester.tap(_key('settings-legal-tab-third-party-notices'));
  await tester.pumpAndSettle();
  _binding = binding;
}

late CodeLabTestBinding _binding;

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(_key('settings-legal-packages-search'), query);
  await tester.pumpAndSettle();
}

Finder _count(String text) => find.descendant(
  of: _key('settings-legal-packages-count'),
  matching: find.text(text),
);

LegalFixture _fourPackages() => LegalFixture(
  packages: [
    legalPackage('flutter'),
    legalPackage('flutter_bloc'),
    legalPackage('fpdart'),
    legalPackage('val_latex_flutter'),
  ],
);

void main() {
  group('поле', () {
    testWidgets('подсказка «Search packages» и доступное имя «Search packages '
        'by name»', (tester) async {
      final handle = tester.ensureSemantics();
      await _openNotices(tester, _fourPackages());

      expect(_key('settings-legal-packages-search'), findsOneWidget);
      expect(find.text('Search packages'), findsOneWidget);
      expect(find.bySemanticsLabel('Search packages by name'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('без запроса: все пакеты, «4 packages», крестика нет', (
      tester,
    ) async {
      await _openNotices(tester, _fourPackages());

      expect(_shownPackages(tester), [
        'flutter',
        'flutter_bloc',
        'fpdart',
        'val_latex_flutter',
      ]);
      expect(_count('4 packages'), findsOneWidget);
      expect(_key('settings-legal-packages-clear'), findsNothing);
      expect(_key('settings-legal-packages-empty'), findsNothing);
    });
  });

  group('совпадение', () {
    testWidgets('«Совпадение без учёта регистра»: FLUTTER оставляет три '
        'пакета по порядку, подсвечено flutter, записи реестра видны', (
      tester,
    ) async {
      await _openNotices(tester, _fourPackages());

      await _type(tester, 'FLUTTER');

      expect(_shownPackages(tester), [
        'flutter',
        'flutter_bloc',
        'val_latex_flutter',
      ]);
      expect(_count('3 of 4 packages'), findsOneWidget);
      for (final name in ['flutter', 'flutter_bloc', 'val_latex_flutter']) {
        expect(_boldPieces(tester, name), ['flutter'], reason: name);
      }
      expect(_key('settings-legal-notices-records'), findsOneWidget);
      expect(
        find.textContaining('JetBrains Mono', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('«Все вхождения подсвечены»: aa_aa — оба aa, текст имени '
        'и подпись для чтения с экрана прежние', (tester) async {
      final handle = tester.ensureSemantics();
      await _openNotices(
        tester,
        LegalFixture(packages: [legalPackage('aa_aa')]),
      );

      await _type(tester, 'aa');

      expect(_boldPieces(tester, 'aa_aa'), ['aa', 'aa']);
      expect(find.text('aa_aa', findRichText: true), findsOneWidget);
      expect(find.bySemanticsLabel('aa_aa'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('без запроса имена не подсвечены, текст и подпись те же', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _openNotices(tester, _fourPackages());

      expect(_boldPieces(tester, 'flutter'), isEmpty);
      expect(find.text('flutter', findRichText: true), findsOneWidget);
      expect(find.bySemanticsLabel('flutter'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('раскрытие пакета при запросе работает как без запроса', (
      tester,
    ) async {
      await _openNotices(tester, _fourPackages());
      await _type(tester, 'flutter');
      expect(
        find.text('license-text-flutter_bloc-1', findRichText: true),
        findsNothing,
      );

      await tester.tap(_package('flutter_bloc'));
      await tester.pumpAndSettle();

      expect(
        find.text('license-text-flutter_bloc-1', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('пустой запрос', () {
    testWidgets('три пробела: все пакеты, «4 packages», крестика нет', (
      tester,
    ) async {
      await _openNotices(tester, _fourPackages());

      await _type(tester, '   ');

      expect(_shownPackages(tester), hasLength(4));
      expect(_count('4 packages'), findsOneWidget);
      expect(_key('settings-legal-packages-clear'), findsNothing);
      expect(_boldPieces(tester, 'flutter'), isEmpty);
    });
  });

  group('крестик', () {
    testWidgets('есть только при непустом запросе, подписан «Clear search», '
        'очищает поле и возвращает полный список', (tester) async {
      final handle = tester.ensureSemantics();
      await _openNotices(tester, _fourPackages());
      expect(_key('settings-legal-packages-clear'), findsNothing);

      await _type(tester, 'fp');
      expect(_key('settings-legal-packages-clear'), findsOneWidget);
      expect(find.bySemanticsLabel('Clear search'), findsWidgets);
      expect(_shownPackages(tester), ['fpdart']);

      await tester.tap(_key('settings-legal-packages-clear'));
      await tester.pumpAndSettle();

      expect(_fieldText(tester), isEmpty);
      expect(_shownPackages(tester), hasLength(4));
      expect(_count('4 packages'), findsOneWidget);
      expect(_key('settings-legal-packages-clear'), findsNothing);
      handle.dispose();
    });
  });

  group('ничего не найдено', () {
    testWidgets('блок вместо списка, «0 of 4 packages», записи реестра '
        'видны', (tester) async {
      await _openNotices(tester, _fourPackages());

      await _type(tester, 'reqwest');

      expect(_shownPackages(tester), isEmpty);
      expect(_key('settings-legal-packages-empty'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('settings-legal-packages-empty'),
          matching: find.text('No packages match'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _key('settings-legal-packages-empty'),
          matching: find.text(
            'No package name contains “reqwest”. The notices register above '
            'is not affected by search.',
          ),
        ),
        findsOneWidget,
      );
      expect(_count('0 of 4 packages'), findsOneWidget);
      expect(_key('settings-legal-notices-records'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('settings-legal-packages-empty-clear'),
          matching: find.text('Clear search'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('«Очистка из пустого блока»: поле пусто, все пакеты, '
        '«4 packages»', (tester) async {
      await _openNotices(tester, _fourPackages());
      await _type(tester, 'reqwest');

      await tester.tap(_key('settings-legal-packages-empty-clear'));
      await tester.pumpAndSettle();

      expect(_fieldText(tester), isEmpty);
      expect(_shownPackages(tester), hasLength(4));
      expect(_count('4 packages'), findsOneWidget);
      expect(_key('settings-legal-packages-empty'), findsNothing);
    });

    testWidgets('запрос в блоке экранирован: bidi-символ виден как \\u202e', (
      tester,
    ) async {
      await _openNotices(tester, _fourPackages());

      await _type(tester, 'a\u202Eb');

      // Сырого символа нет в блоке; в самом поле он остаётся, это ввод.
      expect(
        find.descendant(
          of: _key('settings-legal-packages-empty'),
          matching: find.textContaining('\u202E'),
        ),
        findsNothing,
      );
      expect(
        find.text(
          'No package name contains “a\\u202eb”. The notices register above '
          'is not affected by search.',
        ),
        findsOneWidget,
      );
    });
  });

  group('русский интерфейс', () {
    testWidgets('21 пакет, flutter: «5 из 21 пакета», имена не '
        'переведены', (tester) async {
      final packages = [
        for (final name in [
          'flutter',
          'flutter_bloc',
          'flutter_test',
          'flutter_svg',
          'val_latex_flutter',
        ])
          legalPackage(name),
        for (var i = 1; i <= 16; i++)
          legalPackage('pkg_${i.toString().padLeft(2, '0')}'),
      ];
      await _openNotices(
        tester,
        LegalFixture(packages: packages),
        locale: const Locale('ru'),
      );
      expect(_count('21 пакет'), findsOneWidget);

      await _type(tester, 'flutter');

      expect(_count('5 из 21 пакета'), findsOneWidget);
      expect(_shownPackages(tester), hasLength(5));
      expect(find.text('flutter_bloc', findRichText: true), findsOneWidget);
      expect(find.text('Поиск пакетов'), findsOneWidget);
    });

    testWidgets('пустой блок на русском: запрос в «ёлочках»', (tester) async {
      await _openNotices(tester, _fourPackages(), locale: const Locale('ru'));

      await _type(tester, 'reqwest');

      expect(find.text('Нет подходящих пакетов'), findsOneWidget);
      expect(
        find.text(
          'Ни одно имя пакета не содержит «reqwest». Поиск не меняет реестр '
          'уведомлений выше.',
        ),
        findsOneWidget,
      );
      expect(_count('0 из 4 пакетов'), findsOneWidget);
    });
  });

  group('запрос не сохраняется и не пишется в журнал', () {
    testWidgets('уход со страницы и возврат: поле пусто, журнал и '
        'shared_preferences без маркера', (tester) async {
      final fixture = _fourPackages();
      await _openNotices(tester, fixture);
      await _type(tester, _marker);
      final nav = _binding.scope.resolve<NavigationCubit>();

      nav.back();
      await tester.pumpAndSettle();
      await nav.openSettings(source: SettingsOpenSource.sidebar);
      await tester.pumpAndSettle();
      await tester.tap(_key('settings-legal-tab-third-party-notices'));
      await tester.pumpAndSettle();

      expect(_fieldText(tester), isEmpty);
      expect(_count('4 packages'), findsOneWidget);
      expect('${fixture.logger.entries}', isNot(contains(_marker)));
      expect(
        '${_binding.scope.resolve<LogBuffer>().entries.value}',
        isNot(contains(_marker)),
      );
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        expect('${prefs.get(key)}', isNot(contains(_marker)), reason: key);
        expect(key, isNot(contains(_marker)));
      }
    });

    testWidgets('ввод и очистка запроса не добавляют событий в журнал '
        'портов страницы', (tester) async {
      final fixture = _fourPackages();
      await _openNotices(tester, fixture);
      final before = fixture.logger.entries.length;

      await _type(tester, 'flut');
      await _type(tester, 'reqwest');
      await tester.tap(_key('settings-legal-packages-empty-clear'));
      await tester.pumpAndSettle();
      await _type(tester, 'http');
      await tester.tap(_key('settings-legal-packages-clear'));
      await tester.pumpAndSettle();

      expect(fixture.logger.entries.length, before);
    });
  });
}
