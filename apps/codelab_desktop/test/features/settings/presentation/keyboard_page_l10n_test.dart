// Страница «Keyboard» на русском (задача 3.4 change `add-app-keyboard-page`;
// design.md D5; spec app-settings «Страница «Keyboard»: язык, доступность и
// узкое окно», сценарии «Русский интерфейс» и «Смена языка с запросом»;
// «…поиск», сценарии «Английский текст при русском интерфейсе» и
// «Переведённый текст при русском интерфейсе»; «…видимость и навигация»,
// поиск страницы по ключевому слову).
//
// Красный до задачи 3.5: страница пустая, ARB-сообщений `settingsKeyboard…`
// нет. Русские формулировки заголовка, подписи, колонок, групп и пустого
// результата — предложенные термины D5 (вычитка — задача 3.6); тексты
// действий и мест тест не знает и проверяет как «кириллица, не английский
// эталон».

import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/presentation/keyboard_page.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/keyboard_rows.dart';
import '../../../support/l10n_app.dart';
import '../../../support/l10n_mix.dart';

const _search = ValueKey('settings-keyboard-search');
const _empty = ValueKey('settings-keyboard-empty');
const _footer = ValueKey('settings-keyboard-footer');
const _ru = Locale('ru');
const _en = Locale('en');
final _cyrillic = RegExp('[а-яА-ЯёЁ]');

Finder _row(String id) => find.byKey(ValueKey('settings-keyboard-row-$id'));
Finder _group(String slug) =>
    find.byKey(ValueKey('settings-keyboard-group-$slug'));
Finder _nav(SettingsPage page) => find.byKey(ValueKey(page.navKey));

List<String> _rowIds(WidgetTester tester) => [
  for (final row in keyboardRows)
    if (_row(row.id).evaluate().isNotEmpty) row.id,
];

List<String> _caps(WidgetTester tester, Finder scope) => [
  for (final text in tester.widgetList<CodeLabText>(
    find.descendant(of: scope, matching: find.byType(CodeLabText)),
  ))
    if (text.role == CodeLabTextRole.mono) text.data,
];

/// Тексты строки (не плашки и не разделитель `/` альтернатив): `CodeLabText`
/// не роли `mono`.
List<String> _texts(WidgetTester tester, Finder scope) => [
  for (final text in tester.widgetList<CodeLabText>(
    find.descendant(of: scope, matching: find.byType(CodeLabText)),
  ))
    if (text.role != CodeLabTextRole.mono && text.data != '/') text.data,
];

Widget _shell(Locale locale) => localizedFluentApp(
  locale: locale,
  SettingsShell(
    pages: const SettingsPages(available: {SettingsPage.keyboard}),
    selected: SettingsPage.keyboard,
    onSelected: (_) {},
    onBack: () {},
    builders: {SettingsPage.keyboard: buildKeyboardPage},
  ),
);

/// Тела-заглушки всех страниц, кроме «Keyboard»: её построитель берётся из
/// рабочей таблицы `settingsPageBuilders` (проверяет регистрацию).
Map<SettingsPage, WidgetBuilder> get _stubBodies => {
  for (final page in SettingsPage.values)
    page: (_) => Text('body of ${page.slug}'),
  SettingsPage.keyboard: settingsPageBuilders[SettingsPage.keyboard]!,
};

Future<void> _pump(WidgetTester tester, Locale locale) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_shell(locale));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(_search), query);
  await tester.pumpAndSettle();
}

void main() {
  final variant = TargetPlatformVariant.only(TargetPlatform.linux);

  testWidgets('русский интерфейс: заголовок, колонки, группы, действия, '
      'места и footer — по-русски, кейкапы те же', (tester) async {
    await _pump(tester, _ru);

    expect(find.text('Сочетания клавиш'), findsOneWidget);
    expect(find.text('Поиск по действию или клавише'), findsOneWidget);
    expect(
      find.text('Только для чтения. Сочетания заданы в приложении.'),
      findsOneWidget,
    );
    for (final header in const ['Действие', 'Сочетание', 'Где']) {
      expect(find.text(header), findsOneWidget, reason: header);
    }
    final titles = {
      'global': 'Общие',
      'navigation': 'Навигация',
      'transcript': 'Лента',
      'composer': 'Поле ввода',
      'approvals': 'Одобрения',
    };
    for (final entry in titles.entries) {
      expect(
        find.descendant(
          of: _group(entry.key),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: entry.key,
      );
    }
    expect(
      find.descendant(
        of: find.byKey(_footer),
        matching: find.text(
          'У команд агента нет сочетаний — открывайте их из палитры команд.',
        ),
      ),
      findsOneWidget,
    );

    expect(_rowIds(tester), hasLength(20));
    for (final row in keyboardRows) {
      final texts = _texts(tester, _row(row.id));
      expect(texts, hasLength(2), reason: '${row.id}: действие и место');
      expect(texts.first, matches(_cyrillic), reason: '${row.id}: действие');
      expect(texts.first, isNot(row.action), reason: row.id);
      // Клавиши не переводятся: те же плашки, что на английском.
      expect(_caps(tester, _row(row.id)), row.linuxCaps, reason: row.id);
    }
  }, variant: variant);

  testWidgets('русские тексты строки перехода и нового места строк решения '
      '(D7, решение пользователя Q4)', (tester) async {
    await _pump(tester, _ru);

    expect(_texts(tester, _row('go-to-approval')), [
      'Перейти к одобрению',
      'Рабочее место, пока ждёт одобрение',
    ]);
    for (final id in const [
      'allow-once',
      'allow-always',
      'reject-once',
      'reject-always',
    ]) {
      expect(
        _texts(tester, _row(id)).last,
        'Ожидающее одобрение с фокусом клавиатуры, когда агент предлагает '
        'этот вариант',
        reason: id,
      );
    }
  }, variant: variant);

  testWidgets('английский текст действия при русском интерфейсе: '
      '«allow always» находит строку с переводом', (tester) async {
    await _pump(tester, _ru);

    await _type(tester, 'allow always');

    expect(_rowIds(tester), ['allow-always']);
    final action = _texts(tester, _row('allow-always')).first;
    expect(action, matches(_cyrillic));
    expect(action, isNot('Allow always'));
  }, variant: variant);

  testWidgets('часть перевода находит строку: перевод «Cancel the running '
      'turn» из app_ru.arb', (tester) async {
    await _pump(tester, _ru);
    expect(_row('cancel-turn'), findsOneWidget);
    final translated = _texts(tester, _row('cancel-turn')).first;
    expect(translated, isNot('Cancel the running turn'));
    expect(translated.length, greaterThan(6));

    await _type(tester, translated.substring(2, translated.length - 2));

    expect(_rowIds(tester), contains('cancel-turn'));
  }, variant: variant);

  testWidgets('«zzz» при русском интерфейсе: строка пустого результата и '
      'footer', (tester) async {
    await _pump(tester, _ru);
    expect(_rowIds(tester), hasLength(20));

    await _type(tester, 'zzz');

    expect(_rowIds(tester), isEmpty);
    expect(
      find.descendant(
        of: find.byKey(_empty),
        matching: find.text('Нет сочетаний по запросу «zzz»'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(_footer), findsOneWidget);
  }, variant: variant);

  testWidgets('смена языка с запросом: запрос и строки те же, текст '
      'пересобран', (tester) async {
    final en = AppLocalizationsEn();
    final ru = AppLocalizationsRu();
    await _pump(tester, _en);
    await _type(tester, 'esc');
    final before = _rowIds(tester);
    expect(before, [
      'close-overlay',
      'leave-settings',
      'cancel-turn',
      'command-menu-close',
    ]);
    expect(find.text('Keyboard shortcuts'), findsOneWidget);

    await tester.pumpWidget(_shell(_ru));
    await tester.pumpAndSettle();

    expect(find.text('Сочетания клавиш'), findsOneWidget);
    expect(find.text('Keyboard shortcuts'), findsNothing);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(_search),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text,
      'esc',
    );
    expect(_rowIds(tester), before);
    await expectNoStaleLanguage(tester, from: en, to: ru);
  }, variant: variant);

  group('поиск страницы по ключевому слову', () {
    Future<void> pumpDefault(WidgetTester tester, Locale locale) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        localizedFluentApp(
          locale: locale,
          SettingsShell(
            pages: defaultSettingsPages,
            selected: SettingsPage.general,
            onSelected: (_) {},
            onBack: () {},
            builders: _stubBodies,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_nav(SettingsPage.keyboard), findsOneWidget);
    }

    Future<void> find_(WidgetTester tester, String query) async {
      await tester.enterText(
        find.byKey(CodeLabSettingsNavigation.searchKey),
        query,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('«сочетание» при русском интерфейсе находит «Клавиатура»', (
      tester,
    ) async {
      await pumpDefault(tester, _ru);

      await find_(tester, 'сочетание');

      expect(_nav(SettingsPage.keyboard), findsOneWidget);
      expect(_nav(SettingsPage.connection), findsNothing);
    });

    testWidgets('при английском интерфейсе «shortcut» находит страницу, а '
        '«сочетание» — нет', (tester) async {
      await pumpDefault(tester, _en);

      await find_(tester, 'shortcut');
      expect(_nav(SettingsPage.keyboard), findsOneWidget);

      await find_(tester, 'сочетание');
      expect(_nav(SettingsPage.keyboard), findsNothing);
    });
  });
}
