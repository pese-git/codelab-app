import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:codelab_agent_core/src/tools/builtin/ls.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/builtin/search.dart';
import 'package:codelab_agent_core/src/tools/builtin/write.dart';
import 'package:codelab_agent_core/src/tools/tasks/task_tools.dart';
import 'package:test/test.dart';

import '../subagents/subagent_rig.dart'
    show SubagentRig, agentArgs, oneCallStep, replyStep, schemaOf;
import '../support/package_dir.dart';
import 'compose_test.dart' show allTools, inputs;

void main() {
  // PR-6: секция инструментов входит в промпт, только если включены все её
  // инструменты.
  test('without ls there is no tools/listing', () {
    final sections = systemPromptSections(
      inputs(tools: allTools.difference({'ls'})),
    );

    expect(sections, isNot(contains('tools.listing')));
  });

  test('without write and edit tools/read stays and tools/edit goes', () {
    final sections = systemPromptSections(
      inputs(tools: allTools.difference({'write', 'edit'})),
    );

    expect(sections, contains('tools.read'));
    expect(sections, isNot(contains('tools.edit')));
  });

  // Секция списка задач зависит только от якоря task_create (PR-6, D32).
  test(
    'without task_create there is no tools/tasks and no task_* in the prompt',
    () {
      final tools = allTools.difference({'task_create'});

      final sections = systemPromptSections(inputs(tools: tools));
      final text = composeSystemPrompt(inputs(tools: tools));

      expect(sections, isNot(contains('tools.tasks')));
      expect(text, isNot(contains('task_create')));
      expect(text, isNot(contains('update_plan')));
    },
  );

  test('with task_create the section tools/tasks is in the prompt', () {
    expect(systemPromptSections(inputs()), contains('tools.tasks'));
    expect(Prompts.all['tools.tasks']!.tools, {
      'task_create',
    }, reason: 'frontmatter: tools: [task_create]');
  });

  // Сценарий «База не называет инструментов» (agent-prompts): на файлы без
  // `tools` распространяется запрет имён инструментов; subagent/system.md
  // появляется в итерации 2 и проверяется там.
  test('the base and the untrusted rule name no tool', () {
    final forbidden = RegExp(
      r'\b(exec|ls|lsp|update_plan|task_create|web_fetch|web_search|task_status|task_cancel)\b|mcp__',
    );
    for (final path in [
      'system/base.md',
      'system/untrusted.md',
      'project_context.md',
      'project_context_file.md',
      'agent_profile.md',
    ]) {
      final body = File(corePath('prompts/$path')).readAsStringSync();
      expect(
        forbidden.allMatches(body).map((m) => m[0]),
        isEmpty,
        reason: path,
      );
    }
  });

  // Сценарий «Секция списка задач называет только якорь» (agent-prompts, D32).
  test('tools/tasks.md names only task_create; the compaction rule is in '
      'the task_list description', () {
    final section = File(corePath('prompts/tools/tasks.md')).readAsStringSync();
    final listDescription = File(
      corePath('prompts/tool_descriptions/task_list.md'),
    ).readAsStringSync();

    expect(section, contains('tools: [task_create]'));
    expect(section, contains('task_create'));
    for (final other in ['task_update', 'task_list', 'task_get']) {
      expect(section, isNot(contains(other)), reason: other);
    }
    expect(section, isNot(contains('update_plan')));
    expect(
      listDescription,
      matches(RegExp(r'compact|compress|context', caseSensitive: false)),
      reason: 'правило «после сжатия контекста вызови task_list»',
    );
  });

  test('the files of update_plan are gone (D13)', () {
    expect(File(corePath('prompts/tools/plan.md')).existsSync(), isFalse);
    expect(
      File(corePath('prompts/tool_descriptions/update_plan.md')).existsSync(),
      isFalse,
    );
  });

  test('a tools/ file without tools is rejected by the generator', () {
    // Проверяется в gen_prompts_test.dart; здесь — что все секции tools/
    // в репозитории объявляют свои инструменты.
    final dir = Directory(corePath('prompts/tools'));
    for (final file in dir.listSync().whereType<File>()) {
      expect(
        file.readAsStringSync(),
        matches(RegExp(r'^tools: \[.+\]$', multiLine: true)),
        reason: file.path,
      );
    }
  });

  // Сценарий «Описание детского task_update» (agent-prompts; design.md change
  // `add-subagents-and-tasks`, D46, п. 4). Красные до задачи 4.5: у ребёнка то
  // же описание `task_update`, что у корня, и дети отмечали чужие пункты
  // (ручной прогон: `task.rejected reason=owner`).
  group('описание детского task_update (D46, п. 4)', () {
    const childDescription =
        'Change the status of a task list item assigned to you: in_progress '
        'when you start it, completed when done.\n'
        'You cannot change other fields or items assigned to someone else. '
        'Your assigned item, if any, is named in your instructions.';

    test('файл prompts/tool_descriptions/task_update_subagent.md есть и без '
        'переменных', () {
      final file = File(
        corePath('prompts/tool_descriptions/task_update_subagent.md'),
      );

      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), contains('vars: []'));
      expect(file.readAsStringSync(), contains(childDescription));
    });

    test('схемы шага: у ребёнка general своё описание, у корня прежнее, '
        'параметры обеих схем совпадают', () async {
      final rig = SubagentRig(
        scripts: {
          'go': [
            oneCallStep('c1', 'agent', agentArgs('kid job')),
            replyStep('done'),
          ],
          'kid job': [replyStep('kid report')],
        },
      );
      await rig.open();

      await rig.run('go');

      final root = schemaOf(rig.requestsOf('go').first, 'task_update');
      final child = schemaOf(rig.requestsOf('kid job').single, 'task_update');
      expect(child.description, childDescription);
      expect(root.description, contains('Keep exactly one item in_progress.'));
      expect(root.description, isNot(contains('assigned to you')));
      expect(child.parameters, root.parameters);
    });
  });

  test('CorePlan.promptSections lists the sections of the default mode', () {
    final memory = MemoryExecutionEnv(cwd: '/proj');
    final core = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed(const {
        HostCapability.shellExec: CapabilityOff('test'),
        HostCapability.sessionPersistence: CapabilityOff('test'),
      }),
      services: AgentCoreServices(
        baseEnv: memory,
        logger: _NoLogger(),
        clock: const SystemClock(),
        ids: _Ids(),
        sessions: MemorySessionStore(),
      ),
      config: CoreConfig(
        defaultModel: ModelRef(
          provider: 'test',
          id: 'm',
          api: ProviderApi.openaiChat,
          baseUrl: Uri.parse('http://localhost'),
          contextWindow: 1000,
          maxOutputTokens: 100,
        ),
      ),
      streamFunction: (model, context, {cancel}) => throw UnimplementedError(),
    );

    expect(core.plan.promptSections, [
      'system.base',
      'system.untrusted',
      'tools.read',
      'tools.edit',
      'tools.listing',
      'tools.tasks',
    ]);
  });

  test('built-in tools take their description from prompts', () {
    final descriptions = {
      for (final tool in [
        ReadTool(),
        WriteTool(),
        EditTool(),
        LsTool(),
        SearchTool(),
        ExecTool(),
        TaskCreateTool(),
        TaskUpdateTool(),
        TaskListTool(),
        TaskGetTool(),
      ])
        tool.name: tool.description,
    };

    expect(
      descriptions['read'],
      Prompts.toolDescriptionsRead.render({'maxLines': '2000', 'maxKb': '50'}),
    );
    for (final MapEntry(key: name, value: text) in descriptions.entries) {
      final template = Prompts.all['tool_descriptions.$name']!;
      expect(text, isNotEmpty, reason: name);
      if (template.vars.isEmpty) {
        expect(text, template.render({}), reason: name);
      }
    }
  });
}

final class _NoLogger implements Logger {
  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

final class _Ids implements IdGenerator {
  var _n = 0;

  @override
  String nextId() => 'id-${_n++}';

  @override
  String nextChars(int count, String alphabet) =>
      '${_n++}'.padLeft(count, alphabet[0]);
}
