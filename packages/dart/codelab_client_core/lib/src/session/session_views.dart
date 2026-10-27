import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
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

    /// Категория опции из ACP (`mode`, `model`, `thought_level`): по ней хост
    /// находит, например, режим для шапки сессии (change
    /// `redesign-workbench-shell`, D7). Незнакомая категория — как есть.
    String? category,
  }) = _ConfigOptionView;

  /// Представление опции вида `select` — единственного вида в ACP.
  factory ConfigOptionView.of(SessionConfigOption option) => switch (option) {
    SessionConfigSelect(
      :final id,
      :final name,
      :final currentValue,
      :final options,
      :final description,
      :final category,
    ) =>
      ConfigOptionView(
        id: id.value,
        name: name,
        description: description,
        category: category,
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

/// Запись плана сессии из последнего `SessionUpdate.plan`.
///
/// Почему: план показывают и app, и CLI, а правило «последнее обновление
/// заменяет план целиком» должно быть одним (design.md change
/// `add-codelab-cli`, D14; прежде — `currentPlanOf` app).
///
/// Для чего: элемент `SessionView.plan`; статус и приоритет — значения ACP
/// как есть.
@freezed
abstract class PlanEntryView with _$PlanEntryView {
  const factory PlanEntryView({
    required String content,
    required PlanEntryStatus status,
    required PlanEntryPriority priority,
  }) = _PlanEntryView;

  factory PlanEntryView.of(PlanEntry entry) => PlanEntryView(
    content: entry.content,
    status: entry.status,
    priority: entry.priority,
  );
}

/// План сессии — записи последнего `SessionUpdate.plan` по всем её ходам.
///
/// План раннего хода остаётся текущим и в следующем ходе, который своего не
/// прислал (add-plan-progress-checklist/design.md, Decisions); до первого
/// обновления — пустой список.
List<PlanEntryView> planOf(AcpSession session) {
  List<PlanEntry>? latest;
  for (final turn in session.turns) {
    for (final update in turn.updates) {
      if (update case PlanUpdate(:final entries)) {
        latest = entries;
      }
    }
  }
  return List.unmodifiable([
    for (final entry in latest ?? const <PlanEntry>[]) PlanEntryView.of(entry),
  ]);
}
