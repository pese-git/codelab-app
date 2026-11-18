/// Public API for reusable CodeLab Fluent UI widgets.
library;

export 'src/atomics/atomics.dart';
export 'src/molecules/molecules.dart';
export 'src/organisms/organisms.dart';
export 'src/rendering/rendering.dart';

// ЗАГЛУШКА красной фазы задачи 2.1 change `add-desktop-localization`: экспорт
// делегата кита (D4), без которого тесты не подключают `CodeLabLocalizations`.
// Задача 2.2 оставляет его и дополняет каталог.
export 'src/l10n/codelab_localizations.dart' show CodeLabLocalizations;
