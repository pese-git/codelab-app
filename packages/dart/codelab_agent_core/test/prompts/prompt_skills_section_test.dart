import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:codelab_agent_core/src/prompts/prompts.g.dart';
import 'package:test/test.dart';

import '../skills/skills_support.dart';
import '../support/package_dir.dart';
import 'compose_test.dart' show allTools;

PromptInputs _inputs({
  List<SkillDefinition> skills = const [],
  List<McpServerSummary> servers = const [],
  ProjectContext? context,
  ({String name, String body})? agent,
}) => PromptInputs(
  cwd: '/proj',
  platform: 'linux',
  today: DateTime.utc(2026, 1, 15, 23, 59),
  mode: ModeId.standard,
  profile: HostProfile.of('agent-serve'),
  toolNames: {...allTools, 'skill'},
  mcpServers: servers,
  projectContext: context,
  agentProfile: agent,
  skills: skills,
);

final _skills = parse([
  validSkill('release-notes'),
  validSkill('flutter-golden'),
]).modelVisible;

final _context = assembleProjectContext([
  ContextFile(path: 'AGENTS.md', content: 'Rule A: use tabs.\n'),
  ContextFile(path: 'pkg/AGENTS.md', content: 'Rule B: no tabs.\n'),
], 1 << 16)!;

/// Секция `skills/catalog` и тексты навыков в `prompts/` (agent-prompts
/// «Детерминированная сборка системного промпта», сценарии «Каталог навыков
/// между mcp и контекстом проекта», «База не называет инструментов»; PR-2,
/// PR-3, PR-6; design.md change `add-agent-skills`, D6; §11.5 шаг 9a).
void main() {
  String text(String path) =>
      File(corePath('prompts/$path')).readAsStringSync();

  group('placement (step 9a)', () {
    test('scenario "Каталог навыков между mcp и контекстом проекта"', () {
      final prompt = composeSystemPrompt(
        _inputs(
          skills: _skills,
          servers: const [McpServerSummary(name: 'fake', toolCount: 2)],
          context: _context,
        ),
      );

      final mcp = prompt.indexOf('# MCP servers');
      final skills = prompt.indexOf('## Skills');
      final project = prompt.indexOf('# Project instructions');
      expect(mcp, isNonNegative);
      expect(skills, greaterThan(mcp));
      expect(project, greaterThan(skills));
      expect(
        prompt.indexOf('- flutter-golden:'),
        inInclusiveRange(skills, project),
      );
    });

    test('section ids: mcp, skills.catalog, project_context in this order', () {
      final sections = systemPromptSections(
        _inputs(
          skills: _skills,
          servers: const [McpServerSummary(name: 'fake', toolCount: 2)],
          context: _context,
        ),
      );

      expect(sections.sublist(sections.length - 3), [
        'mcp',
        'skills.catalog',
        'project_context',
      ]);
    });

    test('with an agent profile the profile is still the last section', () {
      final sections = systemPromptSections(
        _inputs(
          skills: _skills,
          context: _context,
          agent: (name: 'reviewer', body: 'Review.'),
        ),
      );

      expect(sections.sublist(sections.length - 3), [
        'skills.catalog',
        'project_context',
        'agent_profile',
      ]);
    });

    test('the section follows the tool sections when there is no mcp', () {
      final sections = systemPromptSections(_inputs(skills: _skills));

      expect(sections.last, 'skills.catalog');
      expect(sections[sections.length - 2], 'tools.tasks');
    });
  });

  group('without skills the prompt is byte-for-byte the old one (PR-3)', () {
    String golden(String name) =>
        File(corePath('test/prompts/golden/$name.txt')).readAsStringSync();

    test('no skills: the golden of the profile', () {
      expect(composeSystemPrompt(_inputs()), golden('agent-serve-standard'));
    });

    test('no skills with project context: the old golden', () {
      expect(
        composeSystemPrompt(_inputs(context: _context)),
        golden('agent-serve-standard-project'),
      );
    });

    test('no skills with mcp: no skills heading, no section id', () {
      final inputs = _inputs(
        servers: const [McpServerSummary(name: 'fake', toolCount: 1)],
      );

      expect(composeSystemPrompt(inputs), isNot(contains('## Skills')));
      expect(systemPromptSections(inputs), isNot(contains('skills.catalog')));
    });
  });

  group('resources in prompts/ (PR-2, PR-6)', () {
    test('the catalog declares tools [skill] and vars [entries]', () {
      expect(Prompts.skillsCatalog.id, 'skills.catalog');
      expect(Prompts.skillsCatalog.tools, {'skill'});
      expect(Prompts.skillsCatalog.vars, {'entries'});
    });

    test('invoked and reattached name no tool and declare none', () {
      expect(Prompts.skillsInvoked.tools, isEmpty);
      expect(Prompts.skillsInvoked.vars, {'name', 'block'});
      expect(Prompts.skillsReattached.tools, isEmpty);
    });

    test('scenario "База не называет инструментов": skills/invoked.md and '
        'skills/reattached.md name no tool', () {
      final forbidden = RegExp(
        r'\b(exec|ls|lsp|update_plan|task_create|web_fetch|web_search|task_status|task_cancel)\b|mcp__',
      );
      for (final path in ['skills/invoked.md', 'skills/reattached.md']) {
        expect(
          forbidden.allMatches(text(path)).map((m) => m[0]),
          isEmpty,
          reason: path,
        );
      }
    });

    test('the catalog text says: when to call skill, paths relative to the '
        'skill directory, no override of safety rules', () {
      final body = text('skills/catalog.md');

      expect(body, contains("skill"));
      expect(body, matches(RegExp(r'relative to', caseSensitive: false)));
      expect(body, matches(RegExp(r'(safety|security)', caseSensitive: false)));
    });

    test('the tool description is a resource of tool_descriptions/', () {
      expect(
        File(corePath('prompts/tool_descriptions/skill.md')).existsSync(),
        isTrue,
      );
      expect(Prompts.toolDescriptionsSkill.render(const {}), isNotEmpty);
    });
  });
}
