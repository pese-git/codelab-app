import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_ui/codelab_ui.dart' show CodeLabLocalizations;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Страница настроек под `FluentApp` с языком, который тест меняет на лету
/// (`add-desktop-localization`, итерация 5, D5 «Уточнение итерации 5»,
/// D9).
///
/// Почему: Cubit-ы страниц «MCP servers», «Agents & modes» и «Skills &
/// extensions» не подписаны на `AppStrings`: состояние типизировано, а текст
/// строит presentation по `context.l10n`. Поэтому смена языка для этих
/// страниц — это только смена `locale` у `FluentApp`; настоящий
/// `AppLanguageCubit` и composition root нужны лишь для самой подписки, а её
/// проверяют тесты итераций 2–4. Помощник даёт сменить язык у уже показанной
/// страницы без пересоздания Cubit-а, чтобы проверить, что состояние
/// (баннеры, InfoBar, черновик редактора) переживает смену и показывается на
/// новом языке.
///
/// Как использовать: `final language = PageLanguage(const Locale('ru'))`;
/// `tester.pumpWidget(language.wrap(page))`; смена —
/// `await language.select(tester, const Locale('en'))`.
final class PageLanguage {
  PageLanguage(Locale initial) : _locale = ValueNotifier(initial);

  final ValueNotifier<Locale> _locale;

  /// Текущий язык страницы.
  Locale get locale => _locale.value;

  /// Оборачивает [page] в `FluentApp` с делегатами app и кита.
  Widget wrap(Widget page) => ValueListenableBuilder<Locale>(
    valueListenable: _locale,
    builder: (context, locale, _) => FluentApp(
      locale: locale,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        CodeLabLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: page,
    ),
  );

  /// Переключает язык и ждёт пересборки дерева.
  Future<void> select(WidgetTester tester, Locale locale) async {
    _locale.value = locale;
    await tester.pumpAndSettle();
  }

  /// Освобождает уведомитель; вызывается в `addTearDown`.
  void dispose() => _locale.dispose();
}

/// Проверяет, что ни одной из английских фраз [english] нет на экране ни
/// целым текстом, ни частью текста (в том числе в `RichText`).
///
/// Почему: новые сообщения итерации 5 ещё не лежат в каталоге, поэтому
/// `expectNoStaleLanguage` их не видит; английскую основу и хвост фразы на
/// русском экране ловит явный список (spec app-settings «Проблемы черновика
/// MCP-сервера на русском», «Режим и баннер записи на русском»).
void expectNoEnglish(Iterable<String> english) {
  for (final phrase in english) {
    expect(
      find.textContaining(phrase, findRichText: true),
      findsNothing,
      reason: 'на экране осталась английская фраза: "$phrase"',
    );
  }
}
