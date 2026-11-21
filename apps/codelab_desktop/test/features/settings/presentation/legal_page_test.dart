// Красные тесты страницы «Legal» (задача 4.3 change `add-app-legal-page`; spec
// app-settings «Страница «Legal»: видимость и вкладки», «…документы на языке
// интерфейса», «…ссылки внутри документов», «…вкладка «License»», «…вкладка
// «Third-party notices»» — все сценарии, кроме поиска по пакетам, его
// проверяет `legal_notices_search_test.dart`; design.md D1, D2, D6–D8, D10,
// D12; артборды `Legal`, `Terms`, `License`, `Notices`).
//
// Реализация — задача 4.5: `features/settings/presentation/legal_page.dart`
// (`buildLegalPage`, `LegalPage`). Страница идёт в настоящем дереве app
// (`CodeLabApp`), порты — двойники `LegalFixture`: документы, реестр и ссылки
// не зависят от `rootBundle` и `LicenseRegistry`. Состояние и переходы
// проверяет `legal_page_cubit_test.dart`; здесь — что видно и какие ключи
// есть.
//
// Ключи (spec): `settings-legal`, `settings-legal-tab-<slug>`,
// `settings-legal-source`, `settings-legal-load-failed`,
// `settings-legal-link-failed`, `settings-legal-license-summary`,
// `settings-legal-license-notices-link`, `settings-legal-license-text`,
// `settings-legal-notices-records`, `settings-legal-packages-info`,
// `settings-legal-packages-loading`, `settings-legal-package-<name>`,
// `settings-legal-packages-count`. Ключей, которых в spec нет, этот тест не
// вводит.
//
// ARB (глоссарий «Страница «Legal»»): `settingsPageLegal`,
// `settingsLegalDocumentsLabel`, вкладки, подпись источника, сообщения
// сбоев, краткое содержание MIT, «Notices register»; тест сверяет
// видимые строки на `en` и `ru`.

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:codelab_desktop/app/build_version.dart';
import 'package:codelab_desktop/app/language/app_language_cubit.dart';
import 'package:codelab_desktop/app/navigation/navigation_cubit.dart';
import 'package:codelab_desktop/core/platform/app_language_preferences.dart';
import 'package:codelab_desktop/core/platform/external_link_opener.dart';
import 'package:codelab_desktop/features/settings/application/package_license_search.dart';
import 'package:codelab_ui/codelab_ui.dart'
    show CodeLabImagePlaceholder, CodeLabMarkdown;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/legal_fixture.dart';

const _tabs = [
  'privacy-policy',
  'terms-of-use',
  'license',
  'third-party-notices',
];

Finder _key(String value) => find.byKey(ValueKey(value));

Finder _tab(String slug) => _key('settings-legal-tab-$slug');

String _source(String asset) =>
    'Bundled with CodeLab $codelabDesktopVersion as $asset · readable offline';

String _sourceRu(String asset) =>
    'Поставляется с CodeLab $codelabDesktopVersion как $asset · доступно без '
    'сети';

/// Выбрана ли вкладка (семантика `selected`, spec: «выбранная вкладка
/// объявляется выбранной»).
bool _selected(WidgetTester tester, String slug) =>
    tester.getSemantics(_tab(slug)).flagsCollection.isSelected ==
    Tristate.isTrue;

Finder _text(String value) => find.textContaining(value, findRichText: true);

Future<void> _pick(WidgetTester tester, String slug) async {
  // На русском вкладки длиннее окна и прокручиваются по горизонтали (D6).
  await tester.ensureVisible(_tab(slug));
  await tester.tap(_tab(slug));
  await tester.pumpAndSettle();
}

void main() {
  group('видимость и вкладки', () {
    testWidgets('пункт навигации открывает «Privacy policy»: текст и подпись '
        'источника', (tester) async {
      final handle = tester.ensureSemantics();
      final fixture = LegalFixture();
      await openLegalPage(tester, fixture);

      expect(_key('settings-legal'), findsOneWidget);
      expect(_selected(tester, 'privacy-policy'), isTrue);
      expect(_text('privacy-en-body'), findsWidgets);
      expect(
        find.descendant(
          of: _key('settings-legal-source'),
          matching: find.text(_source('assets/legal/PRIVACY.md')),
        ),
        findsOneWidget,
      );
      // Остальные документы не читаются, пока их вкладка не открыта (D7).
      expect(fixture.reads, ['assets/legal/PRIVACY.md']);
      handle.dispose();
    });

    testWidgets('четыре вкладки идут в порядке §12.7.7а, группа подписана '
        '«Legal documents»', (tester) async {
      final handle = tester.ensureSemantics();
      await openLegalPage(tester, LegalFixture());

      final xs = [for (final s in _tabs) tester.getTopLeft(_tab(s)).dx];
      expect(xs, [...xs]..sort());
      expect(xs.toSet(), hasLength(4));
      for (final label in [
        'Privacy policy',
        'Terms of use',
        'License',
        'Third-party notices',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.bySemanticsLabel('Legal documents'), findsOneWidget);
      expect(find.text('Legal'), findsWidgets);
      handle.dispose();
    });

    testWidgets('подпись источника меняется с вкладкой', (tester) async {
      await openLegalPage(tester, LegalFixture());
      final expected = {
        'terms-of-use': 'assets/legal/TERMS.md',
        'license': 'assets/legal/LICENSE',
        'third-party-notices': 'assets/legal/THIRD_PARTY_NOTICES.md',
        'privacy-policy': 'assets/legal/PRIVACY.md',
      };

      for (final entry in expected.entries) {
        await _pick(tester, entry.key);

        expect(
          find.descendant(
            of: _key('settings-legal-source'),
            matching: find.text(_source(entry.value)),
          ),
          findsOneWidget,
          reason: entry.key,
        );
      }
    });

    testWidgets('«Принимать нечего»: ни флажка, ни кнопки согласия, '
        'shared_preferences не меняются', (tester) async {
      await openLegalPage(tester, LegalFixture());
      final before = (await SharedPreferences.getInstance()).getKeys();

      for (final slug in _tabs) {
        await _pick(tester, slug);

        expect(find.byType(Checkbox), findsNothing, reason: slug);
        expect(find.byType(ToggleSwitch), findsNothing, reason: slug);
        expect(find.byType(RadioButton), findsNothing, reason: slug);
        expect(find.textContaining('Accept'), findsNothing, reason: slug);
        expect(find.textContaining('I agree'), findsNothing, reason: slug);
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys(), before);
      expect(prefs.getKeys().where((k) => k.contains('legal')), isEmpty);
    });

    testWidgets('кнопок артбордов нет в этой сборке (D12)', (tester) async {
      await openLegalPage(tester, LegalFixture());

      for (final slug in _tabs) {
        await _pick(tester, slug);

        for (final absent in [
          'Copy link',
          'Open on the web',
          'Copy all',
          'Open LICENSE',
          'On this page',
          'In short',
        ]) {
          expect(find.text(absent), findsNothing, reason: '$slug: $absent');
        }
      }
    });

    testWidgets('«Последняя страница без вкладки»: после ухода с «License» '
        'открывается «Privacy policy»', (tester) async {
      final handle = tester.ensureSemantics();
      final binding = await openLegalPage(tester, LegalFixture());
      await _pick(tester, 'license');
      final nav = binding.scope.resolve<NavigationCubit>();

      nav.back();
      await tester.pumpAndSettle();
      await nav.openSettings(source: SettingsOpenSource.sidebar);
      await tester.pumpAndSettle();

      expect(_key('settings-legal'), findsOneWidget);
      expect(_selected(tester, 'privacy-policy'), isTrue);
      expect(_selected(tester, 'license'), isFalse);
      handle.dispose();
    });

    testWidgets('узкое окно на русском: подписи вкладок целиком, без '
        'переполнения', (tester) async {
      final handle = tester.ensureSemantics();
      await openLegalPage(
        tester,
        LegalFixture(),
        locale: const Locale('ru'),
        size: const Size(800, 700),
      );

      expect(tester.takeException(), isNull);
      for (final label in [
        'Политика конфиденциальности',
        'Условия использования',
        'Лицензия',
        'Сторонние уведомления',
      ]) {
        final finder = find.text(label);
        expect(finder, findsWidgets, reason: label);
        final widget = tester.widget<Text>(finder.last);
        expect(widget.overflow, isNot(TextOverflow.ellipsis), reason: label);
      }
      expect(find.bySemanticsLabel('Правовые документы'), findsOneWidget);
      handle.dispose();
    });
  });

  group('документы на языке интерфейса', () {
    testWidgets('en: «Privacy policy» — PRIVACY.md', (tester) async {
      await openLegalPage(tester, LegalFixture());

      expect(_text('privacy-en-body'), findsWidgets);
      expect(_text('privacy-ru-body'), findsNothing);
    });

    testWidgets('ru: «Terms of use» — TERMS.ru.md, подпись на русском', (
      tester,
    ) async {
      final fixture = LegalFixture();
      await openLegalPage(tester, fixture, locale: const Locale('ru'));

      await _pick(tester, 'terms-of-use');

      expect(_text('terms-ru-body'), findsWidgets);
      expect(_text('terms-en-body'), findsNothing);
      expect(
        find.descendant(
          of: _key('settings-legal-source'),
          matching: find.text(_sourceRu('assets/legal/TERMS.ru.md')),
        ),
        findsOneWidget,
      );
      expect(fixture.reads, contains('assets/legal/TERMS.ru.md'));
    });

    testWidgets('смена языка при открытой странице показывает редакцию '
        'нового языка на той же вкладке', (tester) async {
      final handle = tester.ensureSemantics();
      final binding = await openLegalPage(tester, LegalFixture());
      await _pick(tester, 'terms-of-use');

      await tester.runAsync(
        () => binding.scope.resolve<AppLanguageCubit>().select(
          AppLanguagePreference.ru,
        ),
      );
      await tester.pumpAndSettle();

      expect(_selected(tester, 'terms-of-use'), isTrue);
      expect(_text('terms-ru-body'), findsWidgets);
      expect(_text('terms-en-body'), findsNothing);
      handle.dispose();
    });

    testWidgets('ресурс не читается: InfoBar без пути, остальные вкладки '
        'работают, журнал назвал тип', (tester) async {
      final fixture = LegalFixture(failing: {'assets/legal/TERMS.md'});
      await openLegalPage(tester, fixture);

      await _pick(tester, 'terms-of-use');

      final bar = tester.widget<InfoBar>(_key('settings-legal-load-failed'));
      expect(bar.severity, InfoBarSeverity.warning);
      expect(find.text("Couldn't load this document."), findsOneWidget);
      // Путь есть только в подписи источника; в самом InfoBar его нет.
      expect(find.textContaining('/secret/path'), findsNothing);
      expect(
        find.descendant(
          of: _key('settings-legal-load-failed'),
          matching: find.textContaining('TERMS'),
        ),
        findsNothing,
      );
      expect(_text('terms-en-body'), findsNothing);
      await _pick(tester, 'privacy-policy');
      expect(_text('privacy-en-body'), findsWidgets);
      expect(_key('settings-legal-load-failed'), findsNothing);
      final event = fixture.logger.entries.singleWhere(
        (e) => e['event'] == 'legal.document_load_failed',
      );
      expect(event['tab'], 'terms_of_use');
      expect(event['error_type'], 'StateError');
    });

    testWidgets('InfoBar сбоя на русском', (tester) async {
      await openLegalPage(
        tester,
        LegalFixture(failing: {'assets/legal/PRIVACY.ru.md'}),
        locale: const Locale('ru'),
      );

      expect(find.text('Не удалось загрузить документ.'), findsOneWidget);
      expect(find.text("Couldn't load this document."), findsNothing);
    });
  });

  group('ссылки внутри документов', () {
    testWidgets('относительная ссылка на LICENSE переключает вкладку без '
        'сети', (tester) async {
      final handle = tester.ensureSemantics();
      final fixture = LegalFixture();
      await openLegalPage(tester, fixture);
      await _pick(tester, 'terms-of-use');

      await tester.tap(_text('license-link'));
      await tester.pumpAndSettle();

      expect(_selected(tester, 'license'), isTrue);
      expect(fixture.links.opened, isEmpty);
      handle.dispose();
    });

    testWidgets('https открывается через ExternalLinkOpener', (tester) async {
      final fixture = LegalFixture();
      await openLegalPage(tester, fixture);
      await _pick(tester, 'terms-of-use');

      await tester.tap(_text('web-link'));
      await tester.pumpAndSettle();

      expect(fixture.links.opened, [Uri.parse('https://example.com/terms')]);
      expect(_key('settings-legal-link-failed'), findsNothing);
    });

    testWidgets('ссылка на неизвестный файл неактивна', (tester) async {
      final handle = tester.ensureSemantics();
      final fixture = LegalFixture();
      await openLegalPage(tester, fixture);
      await _pick(tester, 'terms-of-use');

      await tester.tap(_text('unknown-link'));
      await tester.pumpAndSettle();

      expect(fixture.links.opened, isEmpty);
      expect(_selected(tester, 'terms-of-use'), isTrue);
      expect(_key('settings-legal-link-failed'), findsNothing);
      handle.dispose();
    });

    for (final outcome in [
      ExternalLinkOutcome.failed,
      ExternalLinkOutcome.rejectedScheme,
    ]) {
      testWidgets('исход ${outcome.name}: InfoBar без адреса', (tester) async {
        final fixture = LegalFixture();
        fixture.links.outcome = outcome;
        await openLegalPage(tester, fixture);
        await _pick(tester, 'terms-of-use');

        await tester.tap(_text('web-link'));
        await tester.pumpAndSettle();

        final bar = tester.widget<InfoBar>(_key('settings-legal-link-failed'));
        expect(bar.severity, InfoBarSeverity.warning);
        expect(find.text("Couldn't open the link."), findsOneWidget);
        expect(find.textContaining('example.com'), findsNothing);
        // Смена вкладки убирает заметку.
        await _pick(tester, 'privacy-policy');
        expect(_key('settings-legal-link-failed'), findsNothing);
      });
    }
  });

  // D8: изображения в правовых текстах не загружаются, а заглушка не
  // предлагает «Show image» (`canLoadImage` страницы всегда `false`).
  group('изображения в документах', () {
    testWidgets('https-изображение — заглушка без «Show image»; порт '
        'ссылок и загрузка не вызываются', (tester) async {
      final fixture = LegalFixture(
        assets: {
          ...legalFixtureAssets,
          'assets/legal/PRIVACY.md':
              '# Privacy EN\n\nimage-doc-body\n\n'
              '![x](https://example.com/a.png)\n',
        },
      );
      await openLegalPage(tester, fixture);

      expect(_text('image-doc-body'), findsWidgets);
      expect(find.byType(CodeLabImagePlaceholder), findsOneWidget);
      expect(find.text('Show image'), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(fixture.links.opened, isEmpty);
    });
  });

  // Ручная проверка macOS: таблица раздела 2 `PRIVACY*.md` обрезалась
  // горизонтальной прокруткой. Документы Legal переносят текст таблиц.
  group('таблицы в документах', () {
    const table =
        '| A | B | C | D |\n|---|---|---|---|\n'
        '| table-cell-one | two | three | four-last-column |\n';

    testWidgets('документ и записи реестра включают перенос таблиц, '
        'горизонтальной прокрутки в документе нет', (tester) async {
      final fixture = LegalFixture(
        assets: {
          ...legalFixtureAssets,
          'assets/legal/PRIVACY.md': '# Privacy EN\n\n$table',
        },
      );
      await openLegalPage(tester, fixture);

      final markdown = tester.widget<CodeLabMarkdown>(
        find.byType(CodeLabMarkdown),
      );
      expect(markdown.wrapTables, isTrue);
      expect(_text('four-last-column'), findsWidgets);
      expect(
        tester
            .widgetList<Scrollable>(
              find.descendant(
                of: find.byType(CodeLabMarkdown),
                matching: find.byType(Scrollable),
              ),
            )
            .where((s) => s.axis == Axis.horizontal),
        isEmpty,
      );
      expect(tester.takeException(), isNull);

      await _pick(tester, 'third-party-notices');
      expect(
        tester.widget<CodeLabMarkdown>(find.byType(CodeLabMarkdown)).wrapTables,
        isTrue,
      );
    });
  });

  group('вкладка «License»', () {
    testWidgets('краткое содержание MIT из трёх строк и оговорка', (
      tester,
    ) async {
      await openLegalPage(tester, LegalFixture());

      await _pick(tester, 'license');

      expect(_key('settings-legal-license-summary'), findsOneWidget);
      for (final text in [
        'Allowed',
        'Use, copy, modify, merge, publish, distribute, sublicense and sell '
            'copies',
        'Condition',
        'Keep the copyright and license notice in copies or substantial '
            'portions',
        'No warranty',
        'Provided “as is”; the authors are not liable for damages',
        'This summary is not the license. The full text below is what '
            'applies.',
      ]) {
        expect(
          find.descendant(
            of: _key('settings-legal-license-summary'),
            matching: find.text(text),
          ),
          findsOneWidget,
          reason: text,
        );
      }
    });

    testWidgets('ru: краткое содержание на русском, полный текст как есть', (
      tester,
    ) async {
      await openLegalPage(tester, LegalFixture(), locale: const Locale('ru'));

      await _pick(tester, 'license');

      expect(
        find.descendant(
          of: _key('settings-legal-license-summary'),
          matching: find.text('Разрешено'),
        ),
        findsOneWidget,
      );
      expect(find.text('Allowed'), findsNothing);
      expect(
        find.descendant(
          of: _key('settings-legal-license-text'),
          matching: find.text(legalLicenseText, findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.text('Сторонние компоненты'), findsOneWidget);
    });

    testWidgets('полный текст LICENSE совпадает с ресурсом побайтно, '
        'моноширинно и с выделением', (tester) async {
      await openLegalPage(tester, LegalFixture());

      await _pick(tester, 'license');

      final text = find.descendant(
        of: _key('settings-legal-license-text'),
        matching: find.byType(SelectableText),
      );
      expect(text, findsOneWidget);
      expect(tester.widget<SelectableText>(text).data, legalLicenseText);
      expect(
        find.textContaining('MIT License', findRichText: true),
        findsWidgets,
      );
    });

    // Ручная проверка macOS: ссылка была `HyperlinkButton` в `Wrap` с
    // отступами кнопки, а открывающая « оставалась отдельно от неё. Ссылка —
    // часть текста абзаца и переносится вместе с ним.
    testWidgets('ссылка «Сторонние уведомления» — часть текста абзаца: '
        'кавычки и ссылка в одном RichText', (tester) async {
      await openLegalPage(tester, LegalFixture(), locale: const Locale('ru'));
      await _pick(tester, 'license');

      final link = _key('settings-legal-license-notices-link');
      expect(link, findsOneWidget);
      final paragraph = find.ancestor(
        of: link,
        matching: find.byType(RichText),
      );
      expect(paragraph, findsWidgets);
      final plain = tester
          .widget<RichText>(paragraph.first)
          .text
          .toPlainText(includePlaceholders: true);
      // Ссылка стоит между кавычками внутри одного абзаца, без кнопки с
      // собственными отступами.
      expect(plain, contains('\uFFFC'));
      // Кавычки при ссылке — в том же абзаце (внутри её неделимой группы).
      for (final quote in ['«', '».']) {
        expect(
          find.ancestor(
            of: find.text(quote),
            matching: find.byWidget(tester.widget(paragraph.first)),
          ),
          findsOneWidget,
          reason: 'знак «$quote» вне абзаца ссылки',
        );
      }
      expect(find.byType(HyperlinkButton), findsNothing);
      expect(find.text('Сторонние уведомления'), findsWidgets);
    });

    // Ручная проверка macOS (окно 900 px, ru): после `WidgetSpan` разрешён
    // перенос, и закрывающая «».» уезжала на новую строку отдельно от ссылки.
    testWidgets('«».» не отрывается от ссылки при любой ширине окна', (
      tester,
    ) async {
      await openLegalPage(tester, LegalFixture(), locale: const Locale('ru'));
      await _pick(tester, 'license');
      final link = _key('settings-legal-license-notices-link');

      for (var width = 800.0; width <= 1300; width += 6) {
        tester.view.physicalSize = Size(width, 900);
        await tester.pumpAndSettle();

        final paragraphFinder = find
            .ancestor(of: link, matching: find.byType(RichText))
            .first;
        final paragraph = tester.renderObject<RenderParagraph>(paragraphFinder);
        final length = paragraph.text
            .toPlainText(includePlaceholders: true)
            .length;
        // Последний знак абзаца: после исправления это сама группа «ссылка
        // и знаки при ней», до него — «.» после ссылки.
        final last = paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: length - 1, extentOffset: length),
            )
            .single
            .toRect()
            .shift(paragraph.localToGlobal(Offset.zero));
        final linkRect = tester.getRect(link);
        expect(
          linkRect.center.dy,
          inInclusiveRange(last.top, last.bottom),
          reason: 'ширина $width: хвост абзаца и ссылка на разных строках',
        );
      }
    });

    for (final (name, activate) in [
      ('Enter', LogicalKeyboardKey.enter),
      ('Space', LogicalKeyboardKey.space),
    ]) {
      testWidgets('ссылка доступна как ссылка и открывается с клавиатуры '
          '(Tab, $name)', (tester) async {
        final handle = tester.ensureSemantics();
        await openLegalPage(tester, LegalFixture());
        await _pick(tester, 'license');
        final link = _key('settings-legal-license-notices-link');
        expect(tester.getSemantics(link).flagsCollection.isLink, isTrue);

        bool focusInsideLink() {
          final focus = FocusManager.instance.primaryFocus?.context;
          if (focus == null) return false;
          var inside = false;
          focus.visitAncestorElements((e) {
            if (e.widget.key ==
                const ValueKey('settings-legal-license-notices-link')) {
              inside = true;
              return false;
            }
            return true;
          });
          return inside;
        }

        for (var i = 0; i < 40 && !focusInsideLink(); i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
        }
        expect(focusInsideLink(), isTrue);
        await tester.sendKeyEvent(activate);
        await tester.pumpAndSettle();

        expect(_selected(tester, 'third-party-notices'), isTrue);
        handle.dispose();
      });
    }

    testWidgets('абзац «Third-party components» со ссылкой на вкладку '
        'уведомлений', (tester) async {
      final handle = tester.ensureSemantics();
      await openLegalPage(tester, LegalFixture());
      await _pick(tester, 'license');

      expect(find.text('Third-party components'), findsOneWidget);
      expect(_key('settings-legal-license-notices-link'), findsOneWidget);
      await tester.tap(_key('settings-legal-license-notices-link'));
      await tester.pumpAndSettle();

      expect(_selected(tester, 'third-party-notices'), isTrue);
      handle.dispose();
    });
  });

  group('вкладка «Third-party notices»', () {
    testWidgets('записи реестра офлайн: подпись, запись, без служебных '
        'разделов', (tester) async {
      await openLegalPage(tester, LegalFixture());

      await _pick(tester, 'third-party-notices');

      final records = _key('settings-legal-notices-records');
      expect(records, findsOneWidget);
      expect(
        find.descendant(
          of: records,
          matching: find.text(
            'Entries of the CodeLab third-party notices register, as kept in '
            'the repository.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: records,
          matching: find.textContaining('JetBrains Mono', findRichText: true),
        ),
        findsWidgets,
      );
      expect(_text('record-body-marker'), findsWidgets);
      expect(_text('Формат записи'), findsNothing);
      expect(_text('<Название источника>'), findsNothing);
      expect(_text('intro-marker-text'), findsNothing);
      expect(find.text('Notices register'), findsOneWidget);
      expect(find.text('Package licenses'), findsOneWidget);
    });

    testWidgets('ru: подпись реестра на русском, записи как есть', (
      tester,
    ) async {
      await openLegalPage(tester, LegalFixture(), locale: const Locale('ru'));

      await _pick(tester, 'third-party-notices');

      expect(
        find.text(
          'Записи реестра сторонних уведомлений CodeLab в том виде, в каком '
          'они хранятся в репозитории.',
        ),
        findsOneWidget,
      );
      expect(find.text('Реестр уведомлений'), findsOneWidget);
      expect(find.text('Лицензии пакетов'), findsOneWidget);
      expect(_text('JetBrains Mono'), findsWidgets);
    });

    testWidgets('без раздела «Записи» показывается весь файл без заголовка '
        'первого уровня', (tester) async {
      final assets = {
        ...legalFixtureAssets,
        'assets/legal/THIRD_PARTY_NOTICES.md':
            '# Third-party notices\n\nwhole-file-marker\n',
      };
      await openLegalPage(tester, LegalFixture(assets: assets));

      await _pick(tester, 'third-party-notices');

      expect(_text('whole-file-marker'), findsWidgets);
      expect(
        find.descendant(
          of: _key('settings-legal-notices-records'),
          matching: find.text('Third-party notices'),
        ),
        findsNothing,
      );
    });

    testWidgets('InfoBar «Package licenses» уровня info', (tester) async {
      await openLegalPage(tester, LegalFixture());

      await _pick(tester, 'third-party-notices');

      final bar = tester.widget<InfoBar>(_key('settings-legal-packages-info'));
      expect(bar.severity, InfoBarSeverity.info);
      expect(
        find.text(
          'Every package the build collected, including development tools of '
          'the workspace. A longer list is safe; a missing license would '
          'not be.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('«Пакет из записи с двумя именами»: alpha — 2 licenses, '
        'beta — 1 license, счётчик 2 packages', (tester) async {
      final fixture = LegalFixture(
        packages: [legalPackage('alpha', 2), legalPackage('beta')],
      );
      await openLegalPage(tester, fixture);

      await _pick(tester, 'third-party-notices');

      final alpha = _key('settings-legal-package-alpha');
      final beta = _key('settings-legal-package-beta');
      expect(alpha, findsOneWidget);
      expect(beta, findsOneWidget);
      expect(
        find.descendant(of: alpha, matching: find.text('2 licenses')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: beta, matching: find.text('1 license')),
        findsOneWidget,
      );
      expect(tester.getTopLeft(alpha).dy, lessThan(tester.getTopLeft(beta).dy));
      expect(
        find.descendant(
          of: _key('settings-legal-packages-count'),
          matching: find.text('2 packages'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('пакет свёрнут, развёрнутый показывает тексты лицензий '
        'как есть', (tester) async {
      await openLegalPage(
        tester,
        LegalFixture(packages: [legalPackage('alpha', 2)]),
      );
      await _pick(tester, 'third-party-notices');
      expect(
        find.text('license-text-alpha-1', findRichText: true),
        findsNothing,
      );

      await tester.tap(_key('settings-legal-package-alpha'));
      await tester.pumpAndSettle();

      expect(
        find.text('license-text-alpha-1', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.text('license-text-alpha-2', findRichText: true),
        findsOneWidget,
      );
    });

    testWidgets('пока реестр собирается — индикатор, затем список', (
      tester,
    ) async {
      final fixture = LegalFixture()..registryGate = Completer();
      await openLegalPage(tester, fixture);

      await tester.tap(_tab('third-party-notices'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(_key('settings-legal-packages-loading'), findsOneWidget);
      expect(_key('settings-legal-package-alpha'), findsNothing);
      // Записи реестра уведомлений видны сразу.
      expect(_key('settings-legal-notices-records'), findsOneWidget);

      fixture.registryGate!.complete((
        packages: <PackageLicense>[legalPackage('alpha')],
        failed: false,
      ));
      await tester.pumpAndSettle();

      expect(_key('settings-legal-packages-loading'), findsNothing);
      expect(_key('settings-legal-package-alpha'), findsOneWidget);
    });

    testWidgets('«Сбой реестра лицензий»: записи и собранный пакет видны, '
        'журнал назвал packages и failed', (tester) async {
      final fixture = LegalFixture(
        packages: [legalPackage('alpha')],
        failedRegistry: true,
      );
      await openLegalPage(tester, fixture);

      await _pick(tester, 'third-party-notices');

      expect(_key('settings-legal-notices-records'), findsOneWidget);
      expect(_text('JetBrains Mono'), findsWidgets);
      expect(_key('settings-legal-package-alpha'), findsOneWidget);
      final event = fixture.logger.entries.singleWhere(
        (e) => e['event'] == 'legal.licenses_collected',
      );
      expect(event['packages'], 1);
      expect(event['failed'], isTrue);
    });
  });
}
