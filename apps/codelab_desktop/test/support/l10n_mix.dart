import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Проверяет, что после смены языка на экране не осталось строк языка [from].
///
/// ЗАГЛУШКА красных тестов задачи 1.5: реализация — задача 1.6
/// (`add-desktop-localization`, D9, главная защита от смеси языков).
Future<void> expectNoStaleLanguage(
  WidgetTester tester, {
  required AppLocalizations from,
  required AppLocalizations to,
}) async {
  throw UnimplementedError('add-desktop-localization 1.6');
}
