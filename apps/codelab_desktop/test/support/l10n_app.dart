import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// `FluentApp` с делегатами app и Fluent для тестов виджетов без scope.
///
/// Почему: тестовые экраны берут текст через `context.l10n`, а без делегатов
/// `AppLocalizations.of` падает (`add-desktop-localization`, D9). Язык по
/// умолчанию — `en`, поэтому `find.text('…')` на английском остаются верными.
///
/// Как использовать: `tester.pumpWidget(localizedFluentApp(child))`; для
/// проверки перевода — `locale: const Locale('ru')`.
Widget localizedFluentApp(Widget child, {Locale locale = const Locale('en')}) =>
    FluentApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
