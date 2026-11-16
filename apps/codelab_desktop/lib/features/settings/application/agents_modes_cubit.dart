import 'dart:async';

import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace, ConnectionProfile;
import 'package:codelab_setup/codelab_setup.dart' show ConfigLayer;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'agents_modes_state.dart';
import 'provider_settings_session.dart';

export 'agents_modes_state.dart';

/// Страница «Agents & modes»: режим и effort новых сессий (design.md change
/// `add-settings-agents-modes`, D2–D6, D11, D12).
///
/// ЗАГЛУШКА итерации 1, задача 1.1: сигнатуры публичного API зафиксированы
/// красными тестами, логики нет — состояние остаётся [AgentsModesLoading].
/// Реализация — задача 1.3 по образцу `ProviderSettingsCubit`.
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы, страница зовёт [reload] и закрывает Cubit вместе с собой. Запись
/// — один `AgentConfigStore.apply` сессии страницы; агенту Cubit ничего не
/// отправляет (Q2 (а)).
class AgentsModesCubit extends Cubit<AgentsModesState> {
  AgentsModesCubit({
    required ClientWorkspace workspace,
    required Future<ConnectionProfile> Function() defaultProfile,
    required ProviderSettingsOpener open,
    required Map<String, String> environment,
    required String? codelabHome,
    required String? Function() projectDirectory,
    Logger? logger,
  }) : super(const AgentsModesLoading());

  /// Читает доступ и снимок конфига; повторный вызов отбрасывает результат
  /// прежней загрузки (D11).
  Future<void> reload() async {}

  /// Записывает режим [id] в выбранную цель. `bypass` не пишется до
  /// [confirmBypass] (D5), `autopilot` и неизвестные id игнорируются.
  Future<void> selectMode(String id) async {}

  /// «Use bypass» в `agents-modes-bypass-confirm`: записывает `bypass`.
  Future<void> confirmBypass() async {}

  /// «Cancel» или Esc в `agents-modes-bypass-confirm`: записи нет, событие
  /// `agents_modes.bypass_cancelled`.
  void cancelBypass() {}

  /// Записывает effort [id] (`low`, `medium`, `high`) в выбранную цель.
  Future<void> selectEffort(String id) async {}

  /// Переключатель `agents-modes-target`: [layer] — `user` или `projectLocal`.
  void selectTarget(ConfigLayer layer) {}
}
