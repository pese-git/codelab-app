import 'dart:async';

import '../agents/agent_definition.dart';
import '../cancel/cancel_token.dart';
import '../llm/messages.dart';
import '../loop/agent_events.dart';
import '../prompts/prompts.g.dart';
import '../tools/agent_tool.dart';
import '../util/clock.dart';
import '../util/ids.dart';
import '../util/logger.dart';
import 'subagent_manager.dart';
import 'subagent_model.dart';
import 'subagent_report.dart';
import 'subagents_config.dart';

/// Ошибка проверки вызова `agent` (описание, `prompt`, тип, пункт, лимит).
///
/// Почему исключение: единая точка исполнения превращает его в результат-ошибку
/// `failed` без ограды `untrusted-content` — текст составлен инструментом, а
/// лазейки в ограде для результатов инструментов нет (TOOL-10). Ребёнок при
/// этом не создаётся.
final class SubagentCallError implements Exception {
  const SubagentCallError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Инструмент `agent`: запускает дочернего агента с отдельным контекстом и
/// возвращает один итоговый отчёт (`agent-core/17-3-subagents.md` §17.3.2,
/// §17.3.3; design.md change `add-subagents-and-tasks`, D1, D24, D28).
///
/// Почему инструмент, а не особая ветка цикла: ни цикл, ни политика, ни
/// единая точка исполнения не знают о детях; `agent` — обычный инструмент
/// tier `read` с `permissionPattern` — именем типа («разрешить всегда» на
/// `explore` не разрешает `general`).
///
/// Для чего: проверки аргументов, запуск через [SubagentManager], строка
/// прогресса и «сердцебиение» через `onUpdate`, обёртка отчёта. Несколько
/// вызовов в одном ответе исполняются параллельно: `executionMode` не задан.
///
/// Как использовать: рантайм регистрирует по одному на сессию при
/// `subagents.enabled` конфигурации сессии (D37); [types] — снимок типов на
/// момент создания сессии; [depth] — глубина вызывающего (корень — 0).
final class SubagentTool extends AgentTool {
  SubagentTool({
    required this.manager,
    required List<AgentDefinition> types,
    required this.ids,
    required this.limits,
    required this.clock,
    required this.logger,
    required this.parentSessionId,
    this.depth = 0,
    required int maxDepth,
    required int maxConcurrent,
  }) : types = List.unmodifiable(types),
       _maxDepth = maxDepth,
       _maxConcurrent = maxConcurrent;

  final SubagentManager manager;

  /// Снимок типов: `scope` `subagent` и `both`, по имени.
  final List<AgentDefinition> types;
  final IdGenerator ids;

  /// Лимиты читаются при каждом вызове (D17).
  final SubagentsConfig Function() limits;
  final Clock clock;
  final Logger logger;
  final SessionId parentSessionId;
  final int depth;
  final int _maxDepth, _maxConcurrent;

  static const _alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';

  @override
  String get name => 'agent';

  @override
  String get description => Prompts.toolDescriptionsAgent.render({
    'maxConcurrent': '$_maxConcurrent',
    'nesting': depth + 1 < _maxDepth
        ? 'A subagent may start its own subagents, up to '
              '${_maxDepth - depth - 1} more level(s) below it.'
        : 'Subagents you start cannot start other subagents.',
    'background': '',
    'agentList': [
      for (final type in types) '- ${type.name}: ${type.description}',
    ].join('\n'),
  });

  @override
  Map<String, Object?> get parameters => {
    'type': 'object',
    'properties': {
      'description': {
        'type': 'string',
        'description':
            'Short title of the work, 3-60 characters. Shown to the user.',
      },
      'prompt': {
        'type': 'string',
        'description':
            'Complete instructions for the subagent: the goal, relevant '
            'paths, constraints and the expected shape of the report. The '
            'subagent does not see this conversation.',
      },
      'type': {
        'type': 'string',
        'enum': [for (final type in types) type.name],
        'default': 'general',
        'description': 'Subagent type. See the tool description for the list.',
      },
      // Пункт списка задач назначается ребёнку только корнем (§17.16.4).
      if (depth == 0)
        'task': {
          'type': 'string',
          'description':
              'Optional id of a task list item that the subagent works on.',
        },
    },
    'required': ['description', 'prompt'],
  };

  @override
  ToolTier get tier => ToolTier.read;

  @override
  ToolKind get kind => ToolKind.think;

  @override
  ContentTrust outputTrust(Map<String, Object?> args) => ContentTrust.untrusted;

  @override
  String permissionPattern(Map<String, Object?> args, String cwd) =>
      _typeOf(args);

  /// Заголовок вызова без резерва id: им пользуется лечение журнала, чтобы
  /// последовательность id не зависела от него (D36 Т6).
  String titleOf(Map<String, Object?> args) {
    final description = args['description'];
    return 'Subagent ${_typeOf(args)}: '
        '${description is String ? description.trim() : ''}';
  }

  String _typeOf(Map<String, Object?> args) =>
      args['type'] is String ? args['type']! as String : 'general';

  /// Резервирует id ребёнка до `ToolCallStarted` (D28): клиент опознаёт вызов
  /// `agent` с первого кадра. Отклонённый проверкой вызов ребёнка не создаёт,
  /// а id остаётся только в этом кадре.
  @override
  Future<ToolPresentation> present(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => ToolPresentation(
    title: titleOf(args),
    subagent: SubagentCallRef(
      id: 'sub_${ids.nextChars(8, _alphabet)}',
      type: _typeOf(args),
    ),
  );

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async {
    final description = (args['description'] as String? ?? '').trim();
    if (description.length < 3 || description.length > 60) {
      throw SubagentCallError(
        'Invalid agent call: description must be 3-60 characters.',
      );
    }
    final prompt = args['prompt'] as String? ?? '';
    if (prompt.isEmpty || prompt.length > 32768) {
      throw SubagentCallError(
        'Invalid agent call: prompt must be 1-32768 characters.',
      );
    }
    final typeName = _typeOf(args);
    final type = types.where((t) => t.name == typeName).firstOrNull;
    if (type == null) {
      // Защитная ветка: провайдер может не соблюсти `enum` схемы.
      throw SubagentCallError(
        'Unknown agent type "$typeName". Available: '
        '${types.map((t) => t.name).join(', ')}.',
      );
    }
    final taskId = depth == 0 ? args['task'] as String? : null;
    if (taskId != null) {
      final items = ctx.services.tasks.items;
      if (!items.any((item) => item.id == taskId)) {
        throw SubagentCallError(
          items.isEmpty
              ? 'Unknown task #$taskId. The task list is empty.'
              : 'Unknown task #$taskId. Known: '
                    '${items.map((i) => '#${i.id}').join(', ')}.',
        );
      }
    }
    final id =
        ctx.presentation?.subagent?.id ?? 'sub_${ids.nextChars(8, _alphabet)}';
    final SubagentHandle handle;
    try {
      handle = manager.spawn(
        SubagentSpec(
          id: id,
          parentSessionId: parentSessionId,
          parentToolCallId: ctx.toolCallId,
          depth: depth + 1,
          type: type,
          description: description,
          prompt: prompt,
          taskId: taskId,
        ),
        ctx.cancel,
      );
    } on SubagentLimitException catch (limit) {
      throw SubagentCallError(
        'Subagent limit reached: at most ${limit.limit} subagents per turn. '
        'Combine the remaining work into fewer tasks or do it yourself.',
      );
    }
    final report = await _await(handle, ctx);
    if (report.status == SubagentState.cancelled) {
      throw CancelledException(ctx.cancel.reason);
    }
    return ToolExecutionResult([
      TextContent(wrapSubagentReport(report)),
    ], isError: report.status != SubagentState.completed);
  }

  /// Ждёт отчёт, пока идут строки прогресса и «сердцебиение»; после отмены
  /// ждёт остановки ребёнка не дольше `cancel_grace` (§17.3.4, шаг 8).
  Future<SubagentReport> _await(SubagentHandle handle, ToolContext ctx) async {
    var snapshot = handle.snapshot;
    ClockTimer? heartbeat;
    void line() {
      ctx.onUpdate(ToolExecutionResult([TextContent(progressLine(snapshot))]));
      heartbeat?.cancel();
      heartbeat = clock.timer(limits().heartbeatInterval, () {
        // Свежий снимок: за время тишины мог смениться счётчик токенов.
        snapshot = handle.snapshot;
        line();
      });
    }

    final subscription = handle.progress.listen((s) {
      snapshot = s;
      line();
    });
    ClockTimer? grace;
    var finished = false;
    unawaited(
      ctx.cancel.onCancel.then((_) {
        // Вызов уже закончился: таймер grace не нужен.
        if (finished) {
          return;
        }
        grace = clock.timer(limits().cancelGrace, () {
          unawaited(manager.forceCancelled(handle.id));
        });
      }),
    );
    try {
      return await handle.report;
    } finally {
      finished = true;
      heartbeat?.cancel();
      grace?.cancel();
      await subscription.cancel();
    }
  }

  /// Строка прогресса фиксированного вида: тип, состояние, шаги, вызовы,
  /// токены (`12.3k`), число активных потомков и последняя активность
  /// (§17.3.4, шаг 4).
  static String progressLine(SubagentSnapshot s) {
    final tokens = s.usage.input + s.usage.output;
    final shown = tokens < 1000
        ? '$tokens'
        : '${(tokens / 1000).toStringAsFixed(1)}k';
    final activity = s.lastActivity;
    return [
      s.agent,
      s.state.name,
      '${s.steps} steps',
      '${s.toolCalls} tool calls',
      '$shown tokens',
      if (s.activeChildren > 0) '${s.activeChildren} subagents',
      if (activity != null)
        activity.length > 60 ? activity.substring(0, 60) : activity,
    ].join(' · ');
  }
}
