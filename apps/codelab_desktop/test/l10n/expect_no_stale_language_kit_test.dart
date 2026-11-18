// Красный самотест помощника expectNoStaleLanguage с каталогом кита (задача
// 3.3 change `add-desktop-localization`; design.md D9, перенесено из
// итерации 2).
//
// Помощник — главная защита от смеси языков, но он читал только каталог app
// (`lib/l10n/app_<язык>.arb`). Текст кита (`codelab_ui_<язык>.arb`) — «Running»
// тега вызова, «Awaiting approval», «Copy» — остаётся на экране при
// неисправном пересоздании и должен ловиться так же. Тест красный, пока
// помощник не читает каталог кита (задача 3.4, `test/support/l10n_mix.dart`).

import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_app.dart';
import '../support/l10n_mix.dart';

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  testWidgets('экран со строкой кита en («Running»), не пересобранной на ru, '
      'даёт падение', (tester) async {
    // Строка взята у кита при сборке на `en` и больше не зависит от языка:
    // так выглядит текст, «застрявший» в состоянии.
    await tester.pumpWidget(localizedFluentApp(const Text('Running')));
    await tester.pumpWidget(
      localizedFluentApp(const Text('Running'), locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();

    await expectLater(
      expectNoStaleLanguage(tester, from: en, to: ru),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('строка кита, взятая из его каталога на ru, проходит', (
    tester,
  ) async {
    Widget screen() => Builder(
      builder: (context) =>
          Text(CodeLabLocalizations.of(context)!.codeLabCallRunning),
    );
    await tester.pumpWidget(localizedFluentApp(screen()));
    await tester.pumpWidget(
      localizedFluentApp(screen(), locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Выполняется'), findsOneWidget);
    await expectNoStaleLanguage(tester, from: en, to: ru);
  });

  testWidgets('текст, которого нет в каталогах (ответ агента), ложного '
      'срабатывания не даёт', (tester) async {
    await tester.pumpWidget(
      localizedFluentApp(
        const Text('Done. 3 files changed.'),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();

    await expectNoStaleLanguage(tester, from: en, to: ru);
  });
}
