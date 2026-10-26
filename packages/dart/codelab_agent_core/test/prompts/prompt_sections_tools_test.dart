import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:codelab_agent_core/src/tools/builtin/edit.dart';
import 'package:codelab_agent_core/src/tools/builtin/exec.dart';
import 'package:codelab_agent_core/src/tools/builtin/ls.dart';
import 'package:codelab_agent_core/src/tools/builtin/read.dart';
import 'package:codelab_agent_core/src/tools/builtin/search.dart';
import 'package:codelab_agent_core/src/tools/builtin/update_plan.dart';
import 'package:codelab_agent_core/src/tools/builtin/write.dart';
import 'package:test/test.dart';

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

  test('without update_plan the prompt does not mention it', () {
    final text = composeSystemPrompt(
      inputs(tools: allTools.difference({'update_plan'})),
    );

    expect(text, isNot(contains('update_plan')));
  });

  test('the base and the untrusted rule name no tool', () {
    final forbidden = RegExp(
      r'\b(exec|ls|lsp|update_plan|web_fetch|web_search|task_status|task_cancel)\b|mcp__',
    );
    for (final path in ['system/base.md', 'system/untrusted.md']) {
      final body = File(corePath('prompts/$path')).readAsStringSync();
      expect(
        forbidden.allMatches(body).map((m) => m[0]),
        isEmpty,
        reason: path,
      );
    }
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
      'tools.plan',
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
        UpdatePlanTool(),
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
