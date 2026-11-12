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
/// `add-codelab-cli`, D14; прежде — `currentPlanOf` app). Список задач
/// CodeLab приходит тем же `plan`, а его id, владелец и блокеры — в
/// `_meta.codelab.task` пункта (change `add-subagents-and-tasks`, D15).
///
/// Для чего: элемент `SessionView.plan`; статус и приоритет — значения ACP
/// как есть. Поля задачи пусты у плана стороннего агента без `_meta`:
/// [taskId] — `null`, [blockedBy] и [openBlockers] — пустые.
///
/// Как использовать: хост печатает `#<taskId> [<status>] <content>`, а
/// [ownerLabel] и [openBlockers] — суффиксами; [blockedBy] — сырой список
/// из `_meta`, [openBlockers] — его часть, чьи пункты в текущем плане не
/// `completed`. Метка владельца пока — id субагента (тип по `SubagentRequester`
/// добавит итерация 2); для `owner: main` и без `owner` метки нет.
@freezed
abstract class PlanEntryView with _$PlanEntryView {
  const factory PlanEntryView({
    required String content,
    required PlanEntryStatus status,
    required PlanEntryPriority priority,

    /// `_meta.codelab.task.id`.
    String? taskId,

    /// `_meta.codelab.task.owner`: `main` или id субагента.
    String? owner,

    /// `_meta.codelab.task.blockedBy` как пришёл (только строки).
    @Default(<String>[]) List<String> blockedBy,

    /// Незавершённые блокеры: id из [blockedBy], пункты которых есть в
    /// текущем плане и не `completed`.
    @Default(<String>[]) List<String> openBlockers,

    /// Метка владельца-субагента; `null` для `main` и без владельца.
    String? ownerLabel,
  }) = _PlanEntryView;

  /// Представление без знания остального плана: блокеры не вычисляются.
  /// Для плана целиком — [planViewsOf].
  factory PlanEntryView.of(PlanEntry entry) {
    final task = taskMetaOf(entry);
    final owner = task?['owner'];
    return PlanEntryView(
      content: entry.content,
      status: entry.status,
      priority: entry.priority,
      taskId: _stringOf(task?['id']),
      owner: _stringOf(owner),
      blockedBy: _stringsOf(task?['blockedBy']),
      ownerLabel: owner is String && owner != 'main' ? owner : null,
    );
  }
}

/// `_meta.codelab.task` пункта плана; `null` при любой неверной форме
/// (терпимый разбор: отказа обработки обновления нет).
Map<String, Object?>? taskMetaOf(PlanEntry entry) {
  final codelab = entry.meta?['codelab'];
  if (codelab is! Map) {
    return null;
  }
  final task = codelab['task'];
  return task is Map ? task.cast<String, Object?>() : null;
}

String? _stringOf(Object? value) => value is String ? value : null;

List<String> _stringsOf(Object? value) =>
    value is List ? [for (final v in value) ?_stringOf(v)] : const [];

/// Представления пунктов плана [entries] с вычисленными незавершёнными
/// блокерами (по статусам пунктов этого же плана).
List<PlanEntryView> planViewsOf(List<PlanEntry> entries) {
  final status = <String, PlanEntryStatus>{
    for (final entry in entries)
      ?_stringOf(taskMetaOf(entry)?['id']): entry.status,
  };
  return List.unmodifiable([
    for (final entry in entries) _withBlockers(PlanEntryView.of(entry), status),
  ]);
}

PlanEntryView _withBlockers(
  PlanEntryView view,
  Map<String, PlanEntryStatus> status,
) => view.copyWith(
  openBlockers: [
    for (final id in view.blockedBy)
      if (status[id] case final s? when s != PlanEntryStatus.completed) id,
  ],
);

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
  return planViewsOf(latest ?? const <PlanEntry>[]);
}
