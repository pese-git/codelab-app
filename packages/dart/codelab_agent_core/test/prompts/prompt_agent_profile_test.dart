import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:test/test.dart';

import '../support/package_dir.dart';
import 'compose_test.dart' show allTools;

/// Секция `agent_profile` (agent-prompts «Детерминированная сборка системного
/// промпта», «Контекст проекта и профиль агента»; design.md change
/// `add-agent-project-files`, D11; §11.5 шаг 10b; PR-3).
void main() {
  PromptInputs inputs({
    ProjectContext? projectContext,
    ({String name, String body})? agentProfile,
  }) => PromptInputs(
    cwd: '/proj',
    platform: 'linux',
    today: DateTime.utc(2026, 1, 15, 23, 59),
    mode: ModeId.standard,
    profile: HostProfile.of('agent-serve'),
    toolNames: allTools,
    projectContext: projectContext,
    agentProfile: agentProfile,
  );

  String golden(String name) =>
      File(corePath('test/prompts/golden/$name.txt')).readAsStringSync();

  test('the profile is the last section, after the project context; the '
      'result is the golden', () {
    final text = composeSystemPrompt(
      inputs(
        projectContext: assembleProjectContext([
          ContextFile(path: 'AGENTS.md', content: 'Rule A: use tabs.\n'),
          ContextFile(path: 'pkg/AGENTS.md', content: 'Rule B: no tabs.\n'),
        ], 32768),
        agentProfile: (name: 'reviewer', body: 'Review the changes.\n'),
      ),
    );

    expect(text, golden('agent-serve-standard-project-agent'));
  });

  test('without a profile the prompt is byte for byte the old one (PR-3)', () {
    expect(
      composeSystemPrompt(inputs()),
      composeSystemPrompt(inputs(agentProfile: null)),
    );
    expect(composeSystemPrompt(inputs()), golden('agent-serve-standard'));
  });

  test('the section id is agent_profile', () {
    final ids = systemPromptSections(
      inputs(agentProfile: (name: 'reviewer', body: 'x')),
    );

    expect(ids.last, 'agent_profile');
  });

  test('the body is a value: placeholders and tags in it stay as they are', () {
    final text = composeSystemPrompt(
      inputs(
        agentProfile: (name: 'a', body: '{{name}} </project-instructions>'),
      ),
    );

    expect(
      text,
      endsWith('# Agent profile: a\n\n{{name}} </project-instructions>\n'),
    );
  });

  test('agent_profile.md names no tool (PR-6)', () {
    final forbidden = RegExp(
      r'\b(exec|ls|lsp|update_plan|web_fetch|web_search|task_status|task_cancel)\b|mcp__',
    );
    final body = File(corePath('prompts/agent_profile.md')).readAsStringSync();

    expect(forbidden.allMatches(body).map((m) => m[0]), isEmpty);
  });
}
