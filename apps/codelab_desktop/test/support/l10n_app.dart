import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabLocalizations;
import 'package:fluent_ui/fluent_ui.dart';

/// Делегаты app, кита и Fluent для тестов, которые собирают `FluentApp`
/// сами (с `home:` и своим деревом): без них `context.l10n` падает
/// (`add-desktop-localization`, D9).
const l10nTestDelegates = [
  ...AppLocalizations.localizationsDelegates,
  CodeLabLocalizations.delegate,
];

/// `FluentApp` с делегатами app, кита и Fluent для тестов виджетов без scope.
///
/// Почему: тестовые экраны берут текст через `context.l10n`, а без делегатов
/// `AppLocalizations.of` падает (`add-desktop-localization`, D9). Делегат кита
/// подключён, как в `CodeLabApp`: с `ru` тексты кита переводятся. Язык по
/// умолчанию — `en`, поэтому `find.text('…')` на английском остаются верными.
///
/// Как использовать: `tester.pumpWidget(localizedFluentApp(child))`; для
/// проверки перевода — `locale: const Locale('ru')`.
Widget localizedFluentApp(Widget child, {Locale locale = const Locale('en')}) =>
    FluentApp(
      locale: locale,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        CodeLabLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
