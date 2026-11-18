/// Public API for reusable CodeLab Fluent UI widgets.
library;

export 'src/atomics/atomics.dart';
export 'src/molecules/molecules.dart';
export 'src/organisms/organisms.dart';
export 'src/rendering/rendering.dart';

// Делегат и список языков каталога кита (`add-desktop-localization`, D4): хост
// (app) добавляет `CodeLabLocalizations.delegate` в `localizationsDelegates`
// своего `FluentApp`. Без делегата кит показывает английский. Остальное API
// каталога (`codeLabStringsOf`, сообщения) внутреннее и не экспортируется.
export 'src/l10n/codelab_localizations.dart' show CodeLabLocalizations;
