// Проверка актуальности сгенерированного кода локализации (скрипт Melos
// `l10n:check`, change `add-desktop-localization`, D3).
//
// ЗАГЛУШКА красных тестов задачи 1.7: реализация — задача 1.8.
//
// Как использовать (контракт для теста 1.7):
//   fvm dart run tool/l10n_check.dart [--package <каталог>]...
// Без аргументов проверяются `apps/codelab_desktop` и
// `packages/flutter/codelab_ui`. Для каждого пакета ARB перегенерируются во
// временный каталог (`flutter gen-l10n`) и сравниваются с рабочими
// `*_localizations*.dart`. Расхождение — код выхода 1 и имя файла в выводе.

import 'dart:io';

void main(List<String> args) {
  stdout.writeln('l10n_check: not implemented (add-desktop-localization 1.8)');
}
