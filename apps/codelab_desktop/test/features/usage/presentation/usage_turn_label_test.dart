// Заголовок хода в «По ходам»: текст с кавычками собирает presentation по
// каталогу, application отдаёт только индекс и заголовок промпта (D5 п. 2/4,
// change `add-desktop-localization`). CSV строится из `turn.title` журнала и
// от языка не зависит.

import 'package:codelab_desktop/features/usage/presentation/usage_pane_view.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final ru = lookupAppLocalizations(const Locale('ru'));

  test('en: прежний текст N · “title”', () {
    expect(usageTurnLabelText(2, 'Fix the build', en), '2 · “Fix the build”');
  });

  test('ru: кавычки-ёлочки «title»', () {
    expect(usageTurnLabelText(2, 'Fix the build', ru), '2 · «Fix the build»');
  });

  test('без заголовка (null или пустой) — только номер', () {
    expect(usageTurnLabelText(1, null, en), '1');
    expect(usageTurnLabelText(1, '', ru), '1');
  });
}
