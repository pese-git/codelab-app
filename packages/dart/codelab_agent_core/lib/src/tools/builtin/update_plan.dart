import '../../llm/messages.dart';
import '../../loop/agent_events.dart';
import '../../prompts/prompts.g.dart';
import '../agent_tool.dart';

/// `update_plan` — заменить план работы целиком (`agent-core-architecture`
/// §6.4, C-05).
///
/// Почему инструмент: план — это намерение модели, и только она знает,
/// когда его менять. Клиент показывает его пользователю (ACP `plan`), а
/// заменяет список целиком — поэтому и инструмент принимает весь план, а не
/// разницу.
///
/// Как использовать: модель передаёт `entries`; инструмент кладёт план в
/// `ToolServices.plan` и ждёт публикации `PlanUpdated`, поэтому событие
/// приходит до `ToolCallFinished` этого вызова. Несколько записей
/// `in_progress` допустимы, но модель получает заметку.
final class UpdatePlanTool extends AgentTool {
  @override
  String get name => 'update_plan';

  @override
  String get description => Prompts.toolDescriptionsUpdatePlan.render(const {});

  @override
  Map<String, Object?> get parameters => const {
    'type': 'object',
    'properties': {
      'entries': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'content': {'type': 'string'},
            'priority': {
              'type': 'string',
              'enum': ['high', 'medium', 'low'],
            },
            'status': {
              'type': 'string',
              'enum': ['pending', 'in_progress', 'completed'],
            },
          },
          'required': ['content', 'priority', 'status'],
        },
      },
    },
    'required': ['entries'],
  };

  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.think;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.trusted;

  /// План не касается файлов: «разрешить всегда» действует на любой план
  /// (§7.5).
  @override
  String permissionPattern(Map<String, Object?> args, String cwd) => '*';

  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => const ToolPresentation(title: 'Update plan');

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final entries = [
      for (final raw in args['entries']! as List<Object?>)
        if (raw case final Map<String, Object?> e)
          PlanEntry(
            content: e['content']! as String,
            priority: PlanPriority.values.byName(e['priority']! as String),
            status: switch (e['status']) {
              'in_progress' => PlanStatus.inProgress,
              'completed' => PlanStatus.completed,
              _ => PlanStatus.pending,
            },
          ),
    ];
    await ctx.services.plan.replace(entries);
    int count(PlanStatus status) =>
        entries.where((e) => e.status == status).length;
    final inProgress = count(PlanStatus.inProgress);
    return ToolExecutionResult([
      TextContent(
        [
          'Plan updated: ${entries.length} entries '
              '(${count(PlanStatus.completed)} completed, $inProgress in '
              'progress, ${count(PlanStatus.pending)} pending).',
          if (inProgress > 1) '[Note: more than one entry is in_progress.]',
        ].join('\n'),
      ),
    ]);
  }
}
