import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/prompts/compose.dart';
import 'package:test/test.dart';

import 'compose_test.dart' show allTools;

PromptInputs _inputs(List<McpServerSummary> servers, {HostProfile? profile}) =>
    PromptInputs(
      cwd: '/proj',
      platform: 'linux',
      today: DateTime.utc(2026, 1, 15),
      mode: ModeId.standard,
      profile: profile ?? HostProfile.of('agent-serve'),
      toolNames: allTools,
      mcpServers: servers,
    );

/// Секция `mcp` (agent-prompts «Секция mcp»; design.md change
/// `add-agent-mcp-client`, D12; PR-6, §11.5 шаг 9).
void main() {
  test('a server with tools gets a line with its prefix', () {
    final text = composeSystemPrompt(
      _inputs(const [McpServerSummary(name: 'fake', toolCount: 2)]),
    );

    expect(text, contains('# MCP servers'));
    expect(text, contains('- fake: 2 tools, prefix mcp__fake__'));
  });

  test('the prefix uses the sanitized name of the server', () {
    final text = composeSystemPrompt(
      _inputs(const [McpServerSummary(name: 'my.srv', toolCount: 1)]),
    );

    expect(text, contains('- my.srv: 1 tools, prefix mcp__my_srv__'));
  });

  test('lines keep the order of registration', () {
    final text = composeSystemPrompt(
      _inputs(const [
        McpServerSummary(name: 'b', toolCount: 1),
        McpServerSummary(name: 'a', toolCount: 3),
      ]),
    );

    expect(
      text.indexOf('- b: 1 tools'),
      lessThan(text.indexOf('- a: 3 tools')),
    );
  });

  test('a server without enabled tools is not in the section (PR-6)', () {
    final text = composeSystemPrompt(
      _inputs(const [
        McpServerSummary(name: 'empty', toolCount: 0),
        McpServerSummary(name: 'fake', toolCount: 2),
      ]),
    );

    expect(text, isNot(contains('empty')));
    expect(text, contains('- fake: 2 tools'));
  });

  test('without servers there is neither the section nor mcp__', () {
    for (final servers in [
      const <McpServerSummary>[],
      const [McpServerSummary(name: 'empty', toolCount: 0)],
    ]) {
      final inputs = _inputs(servers);

      expect(systemPromptSections(inputs), isNot(contains('mcp')));
      expect(composeSystemPrompt(inputs), isNot(contains('mcp__')));
      expect(composeSystemPrompt(inputs), isNot(contains('# MCP servers')));
    }
  });

  test('the section follows the tool sections and is named mcp', () {
    final sections = systemPromptSections(
      _inputs(const [McpServerSummary(name: 'fake', toolCount: 1)]),
    );

    expect(sections.last, 'mcp');
    expect(sections[sections.length - 2], 'tools.plan');
  });

  test('a capability that is off leaves no section even with servers', () {
    final profile = HostProfile.of(
      'agent-serve',
    ).narrowed(const {HostCapability.mcp: CapabilityOff('test')});

    final inputs = _inputs(const [
      McpServerSummary(name: 'fake', toolCount: 1),
    ], profile: profile);

    expect(systemPromptSections(inputs), isNot(contains('mcp')));
    expect(composeSystemPrompt(inputs), isNot(contains('mcp__')));
  });

  test('the same inputs give the same bytes (PR-3)', () {
    const servers = [McpServerSummary(name: 'fake', toolCount: 2)];

    expect(
      composeSystemPrompt(_inputs(servers)),
      composeSystemPrompt(_inputs(servers)),
    );
  });
}
