import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/startup_preferences.dart';

/// Состояние строки «Reopen the last project and its tabs».
///
/// Для чего: чистые значения для переключателя. [saveFailed] — запись не
/// удалась: переключатель остаётся в выбранном положении, страница показывает
/// предупреждение с «Retry» (spec app-settings «Открытие последнего проекта
/// при запуске»).
final class StartupSettingsState {
  const StartupSettingsState({
    this.reopenLastProject = true,
    this.saveFailed = false,
  });

  final bool reopenLastProject;
  final bool saveFailed;
}

/// Владелец значения «открывать последний проект» на странице «General»
/// (design.md change `add-app-general-page`, D9).
///
/// Почему отдельный Cubit: значение читается приложением только при старте
/// (`SettingsCubit`), живой подписки на него нет, а строке страницы нужны
/// загрузка, запись и состояние сбоя. Рабочего пространства и подключения у
/// Cubit нет, поэтому переключение не может тронуть открытый проект, сессии и
/// агента.
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы (`CodeLabDependencies.createStartupSettingsCubit`), страница зовёт
/// [load] и закрывает его вместе с собой. [select] записывает выбор сразу;
/// при сбое значение остаётся выбранным, а [retry] повторяет запись. Журнал —
/// только имя типа ошибки, без текста и путей (CFG-10; AGENTS.md §16).
class StartupSettingsCubit extends Cubit<StartupSettingsState> {
  StartupSettingsCubit({
    required StartupPreferences preferences,
    Logger? logger,
  }) : _preferences = preferences,
       _logger = logger,
       super(const StartupSettingsState());

  final StartupPreferences _preferences;
  final Logger? _logger;

  /// Номер последнего выбора пользователя: итог более ранней записи или
  /// чтения не должен менять состояние после более позднего выбора.
  var _latest = 0;

  /// Читает сохранённое значение; нечитаемое — «включено» (порт не бросает).
  Future<void> load() async {
    final attempt = _latest;
    final load = await _preferences.load();
    if (isClosed || attempt != _latest) {
      return;
    }
    emit(StartupSettingsState(reopenLastProject: load.reopenLastProject));
  }

  /// Выбор пользователя: записывает [value] сразу.
  Future<void> select(bool value) async {
    final attempt = ++_latest;
    if (!isClosed) {
      emit(StartupSettingsState(reopenLastProject: value));
    }
    try {
      await _preferences.save(value);
    } on Object catch (error) {
      _logger?.warning(
        'settings.reopen_last_project_save_failed',
        context: {'error_type': error.runtimeType.toString()},
      );
      if (!isClosed && attempt == _latest) {
        emit(StartupSettingsState(reopenLastProject: value, saveFailed: true));
      }
      return;
    }
    _logger?.info(
      'settings.reopen_last_project_changed',
      context: {'enabled': value},
    );
  }

  /// Повторяет запись выбранного значения после сбоя; без сбоя — пусто.
  Future<void> retry() async {
    if (state.saveFailed) {
      await select(state.reopenLastProject);
    }
  }
}
