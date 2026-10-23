import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/tools/registry.dart';
import 'package:test/test.dart';

import 'fake_tools.dart';

final class _DefaultTierTool extends AgentTool {
  @override
  String get name => 'plain';

  @override
  String get description => 'Plain.';

  @override
  Map<String, Object?> get parameters => const {'type': 'object'};

  @override
  Future<ToolExecutionResult> execute(
    Map<String, Object?> args,
    ToolContext ctx,
  ) async => const ToolExecutionResult([]);
}

void main() {
  test('schemas keep the registration order and are stable', () {
    final registry = ToolRegistry()
      ..register(FakeTool('read'))
      ..register(FakeTool('edit'))
      ..register(FakeTool('exec'));

    final first = [for (final s in registry.schemas) s.name];
    final second = [for (final s in registry.schemas) s.name];

    expect(first, ['read', 'edit', 'exec']);
    expect(second, first);
    expect([for (final t in registry.tools) t.name], first);
  });

  test('a duplicate replaces the tool and reports it', () {
    final duplicates = <String>[];
    final replacement = FakeTool('read');
    final registry = ToolRegistry()
      ..register(FakeTool('read'))
      ..register(FakeTool('edit'))
      ..register(replacement, onDuplicate: duplicates.add);

    expect(duplicates, ['read']);
    expect(registry.lookup('read'), same(replacement));
    expect([for (final t in registry.tools) t.name], ['read', 'edit']);
  });

  test('a name outside [a-zA-Z0-9_-]{1,64} is an ArgumentError', () {
    final registry = ToolRegistry();

    expect(() => registry.register(FakeTool('read file')), throwsArgumentError);
    expect(() => registry.register(FakeTool('')), throwsArgumentError);
    expect(() => registry.register(FakeTool('a' * 65)), throwsArgumentError);
    registry.register(FakeTool('mcp__docs-1__fetch_${'a' * 40}'));
  });

  test('unregister removes the tool', () {
    final registry = ToolRegistry()..register(FakeTool('read'));

    expect(registry.unregister('read'), isTrue);
    expect(registry.unregister('read'), isFalse);
    expect(registry.lookup('read'), isNull);
  });

  test('a tool without an explicit tier is exec (TOOL-5)', () {
    final tool = _DefaultTierTool();

    expect(tool.tier, ToolTier.exec);
    expect(tool.tierOf(const {}), ToolTier.exec);
    expect(tool.kindOf(const {}), ToolKind.other);
    expect(tool.offersAllowAlways(const {}), isTrue);
    expect(tool.toSchema().name, 'plain');
  });
}
