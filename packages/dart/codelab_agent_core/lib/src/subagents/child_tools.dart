import '../agents/agent_definition.dart';
import '../compaction/estimate.dart';
import '../compaction/settings.dart';
import '../llm/model_ref.dart';
import '../skills/skill_catalog.dart';
import '../tools/agent_tool.dart';

/// Окно модели позволяет показать `agent` (D40): эффективное окно с учётом
/// `compaction.context_window_cap` ([cap]) не меньше порога. Одно правило и
/// для схем шага сессии, и для набора ребёнка (D45 Т10).
bool subagentWindowOk(ModelRef model, int? cap) =>
    effectiveContextWindow(model, cap: cap) >=
    CompactionSettings.minSubagentContextWindow;

/// Набор инструментов ребёнка из схем текущего шага родителя
/// (`agent-core/17-3-subagents.md` §17.3.3, шаг 3; SUB-1, SUB-24; design.md
/// change `add-subagents-and-tasks`, D34, D36 Т7, Т9).
///
/// Почему отдельная чистая функция: правило набора — главный рубеж «потомок
/// не шире предка», и его надо проверять без сессии, в том числе поддельным
/// инструментом `skill`.
///
/// Для чего: `base` — [parentTools]; результат — `base ∩ type.tools`
/// (`tools == null` — все) в порядке родителя, а затем:
/// - `agent` входит, только если [depth] меньше [maxDepth] (запуск глубже
///   лимита невозможен по построению);
/// - `agent` не входит и при малом окне модели ребёнка ([agentVisible] —
///   `false`, D40, D45 Т10);
/// - `task_create` ребёнку не даётся, остальные `task_*` — детский вариант
///   (его создаёт `SubagentTaskList`) на любой глубине и независимо от
///   списка типа;
/// - `skill` входит, только если ребёнку передан снимок каталога [skills]:
///   без снимка инструмент с этим именем убирается (инвариант «нет снимка —
///   нет `skill`»), поэтому окна «`skill` без каталога и без границы» нет.
///
/// Как использовать: фабрика дочерней сессии вызывает её один раз при
/// запуске ребёнка; [depth] — глубина ребёнка (корень — 0). Инструмент типа,
/// которого нет у родителя, не добавляется.
List<AgentTool> selectChildTools({
  required List<AgentTool> parentTools,
  required AgentDefinition type,
  required int depth,
  required int maxDepth,
  SkillCatalog? skills,
  bool agentVisible = true,
}) {
  const childTaskTools = {'task_update', 'task_list', 'task_get'};
  return [
    for (final tool in parentTools)
      if (switch (tool.name) {
        'task_create' => false,
        'agent' => agentVisible && depth < maxDepth && type.allowsTool('agent'),
        'skill' => skills != null && type.allowsTool('skill'),
        final name when childTaskTools.contains(name) => true,
        final name => type.allowsTool(name),
      })
        tool,
  ];
}
