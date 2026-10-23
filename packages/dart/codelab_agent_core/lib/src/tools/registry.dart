import '../llm/stream_function.dart';
import 'agent_tool.dart';

final _namePattern = RegExp(r'^[a-zA-Z0-9_-]{1,64}$');

/// Tools of a session in registration order (`agent-core-architecture`
/// §6.2). The order of [schemas] is stable, which keeps the prompt cache
/// of the provider.
final class ToolRegistry {
  final _tools = <String, AgentTool>{};

  /// A duplicate name replaces the tool in place and reports through
  /// [onDuplicate] (TOOL-4). A name outside `^[a-zA-Z0-9_-]{1,64}$` is a
  /// programmer error.
  void register(AgentTool tool, {void Function(String name)? onDuplicate}) {
    if (!_namePattern.hasMatch(tool.name)) {
      throw ArgumentError.value(
        tool.name,
        'tool.name',
        'must match ${_namePattern.pattern}',
      );
    }
    if (_tools.containsKey(tool.name)) {
      onDuplicate?.call(tool.name);
    }
    _tools[tool.name] = tool;
  }

  bool unregister(String name) => _tools.remove(name) != null;

  AgentTool? lookup(String name) => _tools[name];

  List<AgentTool> get tools => List.unmodifiable(_tools.values);

  List<ToolSchema> get schemas => [for (final t in _tools.values) t.toSchema()];
}
