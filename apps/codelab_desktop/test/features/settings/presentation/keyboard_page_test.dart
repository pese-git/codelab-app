// Страница «Keyboard» (задача 3.3 change `add-app-keyboard-page`; design.md
// D5–D9; spec app-settings «Страница «Keyboard»: видимость и навигация»,
// «…строки таблицы», «…обозначения клавиш», «…поиск», «…язык, доступность и
// узкое окно»).
//
// Красный до задач 3.2 и 3.5: страница — пустая заглушка и не зарегистрирована
// в `defaultSettingsPages`. Ожидаемые тексты — литералы спецификации. Тела
// страницы показывает настоящая оболочка настроек (`SettingsShell`), поэтому
// прокрутка и раскладка навигации те же, что в app; сценарии, где важны
// `shared_preferences`, профили и транспорт, идут через дерево `CodeLabApp`.

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:codelab_desktop/features/settings/presentation/keyboard_page.dart';
import 'package:codelab_desktop/features/settings/presentation/settings_shell.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/in_memory_profile_store.dart';
import '../../../support/keyboard_rows.dart';
import '../../../support/l10n_app.dart';
import '../../../support/press_shortcut.dart';
import '../../../support/test_app_scope.dart';

const _body = ValueKey('settings-keyboard');
const _search = ValueKey('settings-keyboard-search');
const _empty = ValueKey('settings-keyboard-empty');
const _footer = ValueKey('settings-keyboard-footer');

Finder _row(String id) => find.byKey(ValueKey('settings-keyboard-row-$id'));
Finder _group(String slug) =>
    find.byKey(ValueKey('settings-keyboard-group-$slug'));
Finder _nav(SettingsPage page) => find.byKey(ValueKey(page.navKey));

/// Ключи строк таблицы, которые сейчас в дереве.
List<String> _rowKeysOnScreen(WidgetTester tester) => [
  for (final element
      in find
          .byWidgetPredicate(
            (w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith(
                  'settings-keyboard-row-',
                ),
          )
          .evaluate())
    (element.widget.key! as ValueKey<String>).value.substring(
      'settings-keyboard-row-'.length,
    ),
];

/// Тексты плашек строки: `CodeLabText` роли `mono`.
List<String> _caps(WidgetTester tester, Finder scope) => [
  for (final text in tester.widgetList<CodeLabText>(
    find.descendant(of: scope, matching: find.byType(CodeLabText)),
  ))
    if (text.role == CodeLabTextRole.mono) text.data,
];

void _window(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Страница «Keyboard» в оболочке настроек с настоящим построителем.
Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(1280, 900),
}) async {
  _window(tester, size);
  await tester.pumpWidget(
    localizedFluentApp(
      SettingsShell(
        pages: const SettingsPages(available: {SettingsPage.keyboard}),
        selected: SettingsPage.keyboard,
        onSelected: (_) {},
        onBack: () {},
        builders: {SettingsPage.keyboard: buildKeyboardPage},
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Оболочка с рабочим набором страниц и построителями по умолчанию.
Future<void> _pumpDefaultShell(
  WidgetTester tester, {
  SettingsPage selected = SettingsPage.general,
  Size size = const Size(1280, 900),
}) async {
  _window(tester, size);
  await tester.pumpWidget(
    localizedFluentApp(
      SettingsShell(
        pages: defaultSettingsPages,
        selected: selected,
        onSelected: (_) {},
        onBack: () {},
        // Тела прочих страниц не нужны (им требуется scope app); построитель
        // «Keyboard» — из рабочей таблицы, поэтому регистрация проверяется.
        builders: {
          for (final page in SettingsPage.values)
            page: (_) => Text('body of ${page.slug}'),
          SettingsPage.keyboard: settingsPageBuilders[SettingsPage.keyboard]!,
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byKey(_search), query);
  await tester.pumpAndSettle();
}

void main() {
  group('видимость и навигация', () {
    testWidgets('в рабочей сборке пункт стоит после General, выбор открывает '
        'тело страницы', (tester) async {
      await _pumpDefaultShell(tester);

      expect(_nav(SettingsPage.keyboard), findsOneWidget);
      expect(
        tester.getTopLeft(_nav(SettingsPage.keyboard)).dy,
        greaterThan(tester.getTopLeft(_nav(SettingsPage.general)).dy),
      );
      expect(SettingsPage.keyboard.group, SettingsGroup.app);
      expect(defaultSettingsPages.visible, contains(SettingsPage.keyboard));
      expect(settingsPageBuilders, contains(SettingsPage.keyboard));

      await _pumpDefaultShell(tester, selected: SettingsPage.keyboard);
      expect(find.byKey(_body), findsOneWidget);
    });

    testWidgets('узкое окно 600 px не скрывает страницу', (tester) async {
      await _pumpDefaultShell(tester, size: const Size(600, 900));

      expect(_nav(SettingsPage.keyboard), findsOneWidget);
    });

    testWidgets('поиск страницы по ключевому слову «shortcut»', (tester) async {
      await _pumpDefaultShell(tester);

      await tester.enterText(
        find.byKey(CodeLabSettingsNavigation.searchKey),
        'shortcut',
      );
      await tester.pumpAndSettle();

      expect(_nav(SettingsPage.keyboard), findsOneWidget);
      expect(_nav(SettingsPage.connection), findsNothing);
    });

    testWidgets('последняя страница: выбор сохраняется значением keyboard и '
        'восстанавливается', (tester) async {
      final binding = CodeLabTestBinding(project: '/workspace');
      _window(tester, const Size(1440, 900));
      await tester.pumpWidget(
        binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
      );
      await tester.pump();

      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await tester.pumpAndSettle();
      expect(_nav(SettingsPage.keyboard), findsOneWidget);
      await tester.tap(_nav(SettingsPage.keyboard));
      await tester.pumpAndSettle();
      expect(find.byKey(_body), findsOneWidget);

      await pressShortcut(tester, CodeLabShortcut.leaveSettings);
      await tester.pumpAndSettle();
      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await tester.pumpAndSettle();

      expect(find.byKey(_body), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('codelab.settings.last_page'), 'keyboard');

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScopeInTest();
    });

    testWidgets('страница ничего не меняет: профили, ключи '
        'shared_preferences и транспорт', (tester) async {
      final profiles = InMemoryProfileStore([testStdioProfile]);
      final transport = FakeAcpTransport();
      final binding = CodeLabTestBinding(
        project: '/workspace',
        transport: transport,
        profileStore: profiles,
      );
      _window(tester, const Size(1440, 900));
      await tester.pumpWidget(
        binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
      );
      await tester.pump();
      final before = (await SharedPreferences.getInstance()).getKeys().toSet();
      final snapshots = {
        for (final key in before)
          key: (await SharedPreferences.getInstance()).get(key),
      };

      await pressShortcut(tester, CodeLabShortcut.openSettings);
      await tester.pumpAndSettle();
      expect(_nav(SettingsPage.keyboard), findsOneWidget);
      await tester.tap(_nav(SettingsPage.keyboard));
      await tester.pumpAndSettle();
      await _type(tester, 'sidebar');
      await pressShortcut(tester, CodeLabShortcut.leaveSettings);
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      final after = prefs.getKeys().toSet()
        ..remove('codelab.settings.last_page');
      expect(after, before);
      for (final key in before) {
        expect(prefs.get(key), snapshots[key], reason: key);
      }
      expect(profiles.profiles, [testStdioProfile]);
      expect(transport.sentMessages, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScopeInTest();
    });
  });

  group('строки таблицы', () {
    testWidgets('верх страницы: заголовок, поле поиска, подпись, колонки', (
      tester,
    ) async {
      await _pumpPage(tester);

      expect(find.text('Keyboard shortcuts'), findsOneWidget);
      expect(find.byKey(_search), findsOneWidget);
      expect(find.text('Search by action or key'), findsOneWidget);
      expect(
        find.text('Read-only list. Shortcuts are fixed in the app.'),
        findsOneWidget,
      );
      for (final header in const ['Action', 'Shortcut', 'Where']) {
        expect(find.text(header), findsOneWidget, reason: header);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('полный список на Linux: пять групп и 24 строки по порядку, '
        'тексты символ в символ', (tester) async {
      await _pumpPage(tester);

      expect(_rowKeysOnScreen(tester).toSet(), {
        for (final row in keyboardRows) row.id,
      });
      expect(_rowKeysOnScreen(tester), hasLength(24));
      for (final group in keyboardGroups) {
        expect(_group(group.slug), findsOneWidget, reason: group.slug);
        expect(
          find.descendant(
            of: _group(group.slug),
            matching: find.text(group.title),
          ),
          findsOneWidget,
          reason: group.slug,
        );
      }

      // Порядок: группа, затем её строки; всё сверху вниз.
      final order = <Finder>[];
      for (final group in keyboardGroups) {
        order.add(_group(group.slug));
        order.addAll([
          for (final row in keyboardRows.where((r) => r.group == group.slug))
            _row(row.id),
        ]);
      }
      final tops = [for (final f in order) tester.getTopLeft(f).dy];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(tops.toSet(), hasLength(tops.length));

      for (final row in keyboardRows) {
        final finder = _row(row.id);
        expect(
          find.descendant(of: finder, matching: find.text(row.action)),
          findsOneWidget,
          reason: '${row.id}: action',
        );
        expect(
          find.descendant(of: finder, matching: find.text(row.where)),
          findsOneWidget,
          reason: '${row.id}: where',
        );
        expect(_caps(tester, finder), row.linuxCaps, reason: row.id);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('строка «Go to approval» (D7): первая в группе Approvals, '
        'кейкапы ⇧ ⌘ A, место и новое место строк решения', (tester) async {
      await _pumpPage(tester);

      final row = _row('go-to-approval');
      expect(row, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('Go to approval')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text('Workbench, while an approval is pending'),
        ),
        findsOneWidget,
      );
      expect(_caps(tester, row), ['⇧', '⌘', 'A']);
      // Первая строка группы: выше всех строк решения, ниже заголовка.
      final top = tester.getTopLeft(row).dy;
      expect(top, greaterThan(tester.getTopLeft(_group('approvals')).dy));
      for (final id in const [
        'allow-once',
        'allow-always',
        'reject-once',
        'reject-always',
      ]) {
        expect(top, lessThan(tester.getTopLeft(_row(id)).dy), reason: id);
        expect(
          find.descendant(
            of: _row(id),
            matching: find.text(
              'Workbench, earliest pending approval, if it offers this option',
            ),
          ),
          findsOneWidget,
          reason: id,
        );
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('сочетаний без поведения нет', (tester) async {
      await _pumpPage(tester);

      expect(_rowKeysOnScreen(tester), hasLength(24));
      for (final id in _rowKeysOnScreen(tester)) {
        final caps = _caps(tester, _row(id));
        for (final forbidden in const ['/', 'F', r'\', 'D', '`']) {
          expect(caps, isNot(contains(forbidden)), reason: '$id: $forbidden');
        }
        // `I` — только у `toggle-protocol` (Ctrl+Shift+I, D11).
        if (id != 'toggle-protocol') {
          expect(caps, isNot(contains('I')), reason: id);
        }
        // Alt+←/→ — навигация кадров панели Protocol (DSK-18, change
        // `redesign-protocol-pane`, D11); в других строках их нет.
        expect(
          caps.contains('Alt') && (caps.contains('←') || caps.contains('→')),
          id == 'protocol-frame-move',
          reason: id,
        );
      }
      expect(find.textContaining('steering'), findsNothing);
      expect(find.textContaining('Show shortcuts'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('строка «Agent commands» под таблицей, кнопок назначения нет', (
      tester,
    ) async {
      await _pumpPage(tester);

      expect(find.byKey(_footer), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(_footer),
          matching: find.text(
            'Agent commands have no shortcuts; open them from the command '
            'palette.',
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(_footer)).dy,
        greaterThan(tester.getBottomLeft(_row('reject-always')).dy - 1),
      );
      expect(
        find.descendant(
          of: find.byKey(_body),
          matching: find.byWidgetPredicate(
            (w) => w is Button || w is FilledButton || w is HyperlinkButton,
          ),
        ),
        findsNothing,
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('обозначения клавиш', () {
    testWidgets('macOS: toggle-files — ⇧ ⌘ E, allow-once — ⌘ Y, allow-always — '
        '⌥ ⌘ Y, reject-always — ⌥ ⇧ ⌘ Z', (tester) async {
      await _pumpPage(tester);

      expect(_caps(tester, _row('toggle-files')), ['⇧', '⌘', 'E']);
      expect(_caps(tester, _row('allow-once')), ['⌘', 'Y']);
      expect(_caps(tester, _row('allow-always')), ['⌥', '⌘', 'Y']);
      expect(_caps(tester, _row('reject-always')), ['⌥', '⇧', '⌘', 'Z']);
      for (final row in keyboardRows) {
        expect(_caps(tester, _row(row.id)), row.macCaps, reason: row.id);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('Windows: toggle-files — Ctrl Shift E, reject-always — Alt '
        'Shift W', (tester) async {
      await _pumpPage(tester);

      expect(_caps(tester, _row('toggle-files')), ['Ctrl', 'Shift', 'E']);
      expect(_caps(tester, _row('reject-always')), ['Alt', 'Shift', 'W']);
      expect(_caps(tester, _row('allow-once')), ['Alt', 'Shift', 'Y']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

    testWidgets('подпись для чтения с экрана: «Option+Cmd+Y», не '
        'символы', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpPage(tester);

      expect(_row('allow-always'), findsOneWidget);
      final label = tester.getSemantics(_row('allow-always')).label;
      expect(label, contains('Option+Cmd+Y'));
      expect(label, isNot(contains('⌥')));
      handle.dispose();
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  });

  group('поиск', () {
    testWidgets('«sidebar» — только Navigation со строкой toggle-sidebar', (
      tester,
    ) async {
      await _pumpPage(tester);

      await _type(tester, 'sidebar');

      expect(_rowKeysOnScreen(tester), ['toggle-sidebar']);
      expect(_group('navigation'), findsOneWidget);
      for (final slug in const [
        'global',
        'transcript',
        'composer',
        'approvals',
      ]) {
        expect(_group(slug), findsNothing, reason: slug);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('строка «Open folder»: на macOS в группе Global сразу после '
        'new-session, кейкапы ⌘ O', (tester) async {
      await _pumpPage(tester);

      expect(
        find.descendant(
          of: _row('open-folder'),
          matching: find.text('Open a folder as the project'),
        ),
        findsOneWidget,
      );
      expect(_caps(tester, _row('open-folder')), ['⌘', 'O']);
      expect(
        find.descendant(
          of: _row('open-folder'),
          matching: find.text('Workbench'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(_row('open-folder')).dy,
        greaterThan(tester.getTopLeft(_row('new-session')).dy),
      );
      expect(
        tester.getTopLeft(_row('open-folder')).dy,
        lessThan(tester.getTopLeft(_row('open-settings')).dy),
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

    testWidgets('поиск строки «Open folder»: «ctrl o» — только группа '
        'Global со строкой open-folder', (tester) async {
      await _pumpPage(tester);

      await _type(tester, 'ctrl o');

      expect(_rowKeysOnScreen(tester), ['open-folder']);
      expect(_group('global'), findsOneWidget);
      for (final slug in const [
        'navigation',
        'transcript',
        'composer',
        'approvals',
      ]) {
        expect(_group(slug), findsNothing, reason: slug);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('«⌘K» на Linux находит command-palette с кейкапами Ctrl K', (
      tester,
    ) async {
      await _pumpPage(tester);

      await _type(tester, '⌘K');

      expect(_rowKeysOnScreen(tester), ['command-palette']);
      expect(_caps(tester, _row('command-palette')), ['Ctrl', 'K']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('поиск строки перехода: «ctrl shift a» — только группа '
        'Approvals со строкой go-to-approval', (tester) async {
      await _pumpPage(tester);

      await _type(tester, 'ctrl shift a');

      expect(_rowKeysOnScreen(tester), ['go-to-approval']);
      expect(_group('approvals'), findsOneWidget);
      for (final slug in const [
        'global',
        'navigation',
        'transcript',
        'composer',
      ]) {
        expect(_group(slug), findsNothing, reason: slug);
      }
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('«ctrl shift e» — только toggle-files', (tester) async {
      await _pumpPage(tester);

      await _type(tester, 'ctrl shift e');

      expect(_rowKeysOnScreen(tester), ['toggle-files']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('«zzz»: ни таблицы, ни групп, строка пустого результата, '
        'footer на месте', (tester) async {
      await _pumpPage(tester);
      expect(_rowKeysOnScreen(tester), hasLength(24));

      await _type(tester, 'zzz');

      expect(_rowKeysOnScreen(tester), isEmpty);
      for (final group in keyboardGroups) {
        expect(_group(group.slug), findsNothing, reason: group.slug);
      }
      expect(find.byKey(_empty), findsOneWidget);
      expect(find.text('No shortcuts match "zzz"'), findsOneWidget);
      expect(find.byKey(_footer), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('«Where» в поиске не участвует: «files tree»', (tester) async {
      await _pumpPage(tester);
      expect(_rowKeysOnScreen(tester), hasLength(24));

      await _type(tester, 'files tree');

      expect(_rowKeysOnScreen(tester), isEmpty);
      expect(find.byKey(_empty), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('запрос не переживает закрытие страницы', (tester) async {
      await _pumpPage(tester);
      await _type(tester, 'sidebar');
      expect(_rowKeysOnScreen(tester), ['toggle-sidebar']);

      await _pumpPage(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      await _pumpPage(tester);

      expect(_rowKeysOnScreen(tester), hasLength(24));
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });

  group('доступность и узкое окно', () {
    testWidgets(
      'окно 440 px (тело уже 380): таблица прокручивается по горизонтали, '
      'переполнения нет, кейкапы allow-always (Alt Shift Q) видны после прокрутки',
      (tester) async {
        await _pumpPage(tester, size: const Size(440, 900));

        expect(_row('allow-always'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final horizontal = tester
            .widgetList<SingleChildScrollView>(
              find.descendant(
                of: find.byKey(_body),
                matching: find.byType(SingleChildScrollView),
              ),
            )
            .where((s) => s.scrollDirection == Axis.horizontal);
        expect(horizontal, isNotEmpty);

        final last = find.descendant(
          of: _row('allow-always'),
          matching: find.text('Q'),
        );
        await tester.ensureVisible(last);
        await tester.pump();
        final area = tester.getRect(find.byKey(_body));
        expect(tester.getRect(last).right, lessThanOrEqualTo(area.right));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    // Минимальное окно app — 800 px; навигация слева (около 320 px) и поля
    // тела уменьшают область страницы примерно до 400 px, и таблица не должна
    // прятать колонку «Where» за горизонтальной прокруткой (ручная проверка
    // на macOS, D9: прокрутка только для действительно узкой области). Шрифт
    // тестов (Ahem) втрое шире настоящего, поэтому проверяется начало колонки
    // «Where», а не её правый край.
    testWidgets('окно 800x600: все три колонки видны без горизонтальной '
        'прокрутки', (tester) async {
      await _pumpPage(tester, size: const Size(800, 600));

      expect(tester.takeException(), isNull);
      final horizontal = tester
          .widgetList<SingleChildScrollView>(
            find.descendant(
              of: find.byKey(_body),
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .where((s) => s.scrollDirection == Axis.horizontal);
      expect(horizontal, isEmpty, reason: 'таблица помещается без прокрутки');

      final area = tester.getRect(find.byKey(_body));
      final windowRight = tester.view.physicalSize.width;
      // Самое длинное «Where» таблицы: колонка клавиш растёт по самой
      // широкой строке (Alt-стрелки панели Protocol, change
      // `redesign-protocol-pane`), и короткое «Workbench» уже не переносится.
      final where = find.descendant(
        of: _row('allow-once'),
        matching: find.text(
          keyboardRows.firstWhere((r) => r.id == 'allow-once').where,
        ),
      );
      expect(where, findsOneWidget);
      for (final finder in [find.text('Where'), where]) {
        final rect = tester.getRect(finder);
        expect(rect.left, greaterThanOrEqualTo(area.left));
        expect(rect.left, lessThan(area.right));
        expect(rect.left, lessThan(windowRight));
      }
      // Колонки «Action» и «Where» переносят текст, а не обрезают его.
      expect(
        tester.getSize(where).height,
        greaterThan(tester.getSize(find.text('Where')).height),
        reason: 'длинное «Where» переносится на несколько строк',
      );
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

    testWidgets('Tab с пункта навигации «Keyboard» переводит фокус в поле '
        'поиска, а не на строки таблицы', (tester) async {
      await _pumpPage(tester);
      expect(find.byKey(_search), findsOneWidget);

      final searchField = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(_search),
          matching: find.byType(EditableText),
        ),
      );
      final rows = <Element>{
        for (final row in keyboardRows) ..._row(row.id).evaluate(),
      };
      bool inRows(BuildContext? context) {
        var found = false;
        context?.visitAncestorElements((ancestor) {
          if (rows.contains(ancestor)) {
            found = true;
            return false;
          }
          return true;
        });
        return found;
      }

      // Начало сценария спецификации: фокус на пункте `settings-nav-keyboard`.
      final nav = _nav(SettingsPage.keyboard).evaluate().single;
      // Узел фокуса пункта: ближайший сверху от ключа либо первый внутри него.
      final navFocus =
          Focus.maybeOf(nav) ??
          FocusManager.instance.rootScope.descendants.firstWhere(
            (node) => node.canRequestFocus && node.context == nav,
          );
      navFocus.requestFocus();
      await tester.pump();
      expect(searchField.focusNode.hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      expect(searchField.focusNode.hasFocus, isTrue);
      expect(inRows(FocusManager.instance.primaryFocus?.context), isFalse);
    }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
  });
}
