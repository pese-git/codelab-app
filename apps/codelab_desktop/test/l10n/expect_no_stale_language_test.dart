// Красный самотест помощника expectNoStaleLanguage (задача 1.5 change
// `add-desktop-localization`; design.md D9).
//
// Помощник — главная защита от смеси языков: он обязан падать на экране, где
// строка каталога `en` осталась после перехода на `ru`, и молчать, когда
// экран пересобран. Сам помощник ломаться молча не должен, поэтому он
// проверяется отдельно.

import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_desktop/l10n/l10n.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/l10n_app.dart';
import '../support/l10n_mix.dart';

void main() {
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  testWidgets('экран со строкой en, не пересобранной на ru, даёт падение', (
    tester,
  ) async {
    // Строка взята из каталога en при сборке и больше не зависит от языка:
    // так выглядит текст, «застрявший» в состоянии Cubit-а.
    final frozen = en.settingsLanguageTitle;
    await tester.pumpWidget(localizedFluentApp(Text(frozen)));
    await tester.pumpWidget(
      localizedFluentApp(Text(frozen), locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();

    await expectLater(
      expectNoStaleLanguage(tester, from: en, to: ru),
      throwsA(isA<TestFailure>()),
    );
  });

  testWidgets('экран, пересобранный через context.l10n, проходит', (
    tester,
  ) async {
    Widget screen() =>
        Builder(builder: (context) => Text(context.l10n.settingsLanguageTitle));
    await tester.pumpWidget(localizedFluentApp(screen()));
    await tester.pumpWidget(
      localizedFluentApp(screen(), locale: const Locale('ru')),
    );
    await tester.pumpAndSettle();

    expect(find.text(ru.settingsLanguageTitle), findsOneWidget);
    await expectNoStaleLanguage(tester, from: en, to: ru);
  });

  testWidgets('строка, одинаковая в en и ru (эндоним), ложного срабатывания '
      'не даёт', (tester) async {
    await tester.pumpWidget(
      localizedFluentApp(Text(en.settingsLanguageEnglish)),
    );
    await tester.pumpWidget(
      localizedFluentApp(
        Text(en.settingsLanguageEnglish),
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();

    await expectNoStaleLanguage(tester, from: en, to: ru);
  });
}
