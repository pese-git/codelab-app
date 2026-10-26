import 'package:acp_protocol/acp_protocol.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'session_views.freezed.dart';

/// Опция конфигурации сессии (`session/new`, `config_option_update`,
/// ответ `session/set_config_option`) для отображения.
///
/// Почему: UI и CLI показывают опции одинаково, а DTO протокола не
/// предназначен для долгоживущего представления (`AGENTS.md` §7; перенос
/// `_configOptionsFor` из `CodeLabShellCubit`, design D9).
@freezed
abstract class ConfigOptionView with _$ConfigOptionView {
  const factory ConfigOptionView({
    required String id,
    required String name,
    String? description,
    required String currentValue,
    required List<ConfigOptionValueView> values,
  }) = _ConfigOptionView;

  /// Представление опции вида `select` — единственного вида в ACP.
  factory ConfigOptionView.of(SessionConfigOption option) => switch (option) {
    SessionConfigSelect(
      :final id,
      :final name,
      :final currentValue,
      :final options,
      :final description,
    ) =>
      ConfigOptionView(
        id: id.value,
        name: name,
        description: description,
        currentValue: currentValue.value,
        values: [
          for (final value in options)
            ConfigOptionValueView(
              value: value.value.value,
              name: value.name,
              description: value.description,
            ),
        ],
      ),
  };
}

/// Значение опции конфигурации.
@freezed
abstract class ConfigOptionValueView with _$ConfigOptionValueView {
  const factory ConfigOptionValueView({
    required String value,
    required String name,
    String? description,
  }) = _ConfigOptionValueView;
}

/// Команда, которую агент объявил в последнем `available_commands_update`.
///
/// В ACP у команды нет отдельного вызова: хост вставляет `/<name> ` в
/// промпт, [hint] — подсказка к аргументам (перенос `_agentCommandsFor`,
/// design D9).
@freezed
abstract class AgentCommandView with _$AgentCommandView {
  const factory AgentCommandView({
    required String name,
    required String description,
    String? hint,
  }) = _AgentCommandView;

  factory AgentCommandView.of(AvailableCommand command) {
    final hint = command.input?.hint;
    return AgentCommandView(
      name: command.name,
      description: command.description,
      hint: hint == null || hint.isEmpty ? null : hint,
    );
  }
}
