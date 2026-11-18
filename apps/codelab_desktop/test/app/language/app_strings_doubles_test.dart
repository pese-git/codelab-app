// Самотест двойников порта AppStrings (задача 1.4 change
// `add-desktop-localization`; design.md D9; `testing.md` §30а).

import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/app_strings.dart';

void main() {
  test('FixedAppStrings отдаёт один каталог и не шлёт событий', () async {
    final strings = FixedAppStrings(AppLocalizationsEn());

    expect(strings.current.localeName, 'en');
    await expectLater(strings.changes, emitsDone);
  });

  test('TestAppStrings: emit меняет current и шлёт событие', () async {
    final strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
    final received = <String>[];
    final sub = strings.changes.listen((s) => received.add(s.localeName));

    strings.emit(AppLocalizationsRu());
    await Future<void>.delayed(Duration.zero);

    expect(strings.current.localeName, 'ru');
    expect(received, ['ru']);
    await sub.cancel();
  });

  test('TestAppStrings: hasListener показывает подписку и отписку', () async {
    final strings = TestAppStrings(AppLocalizationsEn());
    addTearDown(strings.close);
    expect(strings.hasListener, isFalse);

    final sub = strings.changes.listen((_) {});
    expect(strings.hasListener, isTrue);

    await sub.cancel();
    expect(strings.hasListener, isFalse);
  });
}
