import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart' show ThemeLibrary;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/platform/app_appearance_preferences.dart';
import '../../core/platform/system_accent_source.dart';
import 'app_appearance_start.dart';
import 'built_in_themes.dart';
import 'fluent_theme_builder.dart';

/// Состояние оформления app (D13).
///
/// ЗАГЛУШКА для красных тестов 4.5 (`add-app-appearance-page`).
final class AppAppearanceState {
  const AppAppearanceState({
    required this.settings,
    required this.resolvedLight,
    required this.resolvedDark,
    this.systemAccentSupported = false,
    this.saveFailed = false,
    this.fallback = AppearanceFallback.none,
  });

  final AppAppearanceSettings settings;

  /// Готовые темы двух режимов (с расширениями `CodeLabPalette` и
  /// `CodeLabCodeTheme`).
  final FluentThemeData resolvedLight;
  final FluentThemeData resolvedDark;
  final bool systemAccentSupported;
  final bool saveFailed;
  final AppearanceFallback fallback;

  AppearanceMode get mode => settings.mode;
  String get lightTheme => settings.lightTheme;
  String get darkTheme => settings.darkTheme;
  bool get systemAccent => settings.systemAccent;

  ThemeMode get themeMode => ThemeMode.system;
}

/// Единственный владелец применённого оформления (D13).
///
/// ЗАГЛУШКА: хранит начальное состояние и ничего не делает; переходы,
/// запись, чтение файлов, подписка на акцент — задача 4.6.
final class AppAppearanceCubit extends Cubit<AppAppearanceState> {
  AppAppearanceCubit({
    required AppAppearancePreferences preferences,
    required ThemeLibrary library,
    required SystemAccentSource accentSource,
    required AppAppearanceStart start,
    Logger? logger,
    Duration closeWriteTimeout = const Duration(seconds: 3),
  }) : super(
         AppAppearanceState(
           settings: start.settings,
           resolvedLight: buildFluentTheme(builtInThemeFile('light')),
           resolvedDark: buildFluentTheme(builtInThemeFile('dark')),
         ),
       );

  Future<void> setMode(AppearanceMode mode) async {}

  /// Назначает тему [id] её режиму; пользовательскую читает из каталога.
  Future<void> useTheme(String id) async {}

  /// Возвращает режиму [brightness] встроенную тему по умолчанию.
  Future<void> resetTheme(Brightness brightness) async {}

  Future<void> setSystemAccent(bool enabled) async {}

  /// Перечитывает файл темы [id], если она назначена режиму.
  Future<void> reloadTheme(String id) async {}

  /// Перечитывает системный акцент (открытие страницы «Appearance», Linux).
  Future<void> refreshSystemAccent() async {}

  /// Повторяет запись текущего выбора после сбоя.
  Future<void> retrySave() async {}
}
