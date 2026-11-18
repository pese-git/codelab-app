import 'dart:ui';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/platform/app_language_preferences.dart';
import '../../l10n/app_localizations.dart';

/// Узкий порт языка для Cubit-ов, которые хранят текст в состоянии.
///
/// ЗАГЛУШКА красных тестов задачи 1.3: реализация — задача 1.4
/// (`add-desktop-localization`, D2, D5).
abstract interface class AppStrings {
  /// Каталог текущего языка.
  AppLocalizations get current;

  /// Новый каталог ровно один раз на смену языка.
  Stream<AppLocalizations> get changes;
}

/// Состояние языка интерфейса.
///
/// ЗАГЛУШКА задачи 1.3 (реализация — 1.4).
final class AppLanguageState {
  const AppLanguageState({
    required this.preference,
    required this.locale,
    required this.strings,
    this.saveFailed = false,
  });

  final AppLanguagePreference preference;
  final Locale locale;
  final AppLocalizations strings;
  final bool saveFailed;
}

/// Единственный владелец языка интерфейса (D2).
///
/// ЗАГЛУШКА красных тестов задачи 1.3: реализация — задача 1.4.
final class AppLanguageCubit extends Cubit<AppLanguageState>
    implements AppStrings {
  AppLanguageCubit({
    required AppLanguagePreferences preferences,
    required AppLanguagePreference preference,
    required Locale locale,
    Logger? logger,
  }) : super(
         AppLanguageState(
           preference: preference,
           locale: locale,
           strings: lookupAppLocalizations(locale),
         ),
       );

  @override
  AppLocalizations get current => state.strings;

  @override
  Stream<AppLocalizations> get changes => const Stream.empty();

  /// Применяет язык синхронно и затем сохраняет его.
  Future<void> select(AppLanguagePreference preference) async {
    throw UnimplementedError('add-desktop-localization 1.4');
  }
}
