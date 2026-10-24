import 'dart:io';

import 'package:test/test.dart';

import '../support/package_dir.dart';

/// HOST-6: only the assembly creates the registry, the agent and the
/// runtime.
void main() {
  test('ToolRegistry(, Agent( and AgentRuntime( only in the assembly', () {
    final allowed = {
      'host/build_agent_core.dart',
      'runtime/agent_runtime.dart',
      'loop/agent.dart',
    };
    final offenders = <String>[];
    final lib = Directory(corePath('lib/src'));
    for (final file in lib.listSync(recursive: true).whereType<File>()) {
      final relative = file.path.substring(lib.path.length + 1);
      if (!file.path.endsWith('.dart') || allowed.contains(relative)) {
        continue;
      }
      for (final (i, line) in file.readAsLinesSync().indexed) {
        if (RegExp(
              r'\b(ToolRegistry|Agent|AgentRuntimeImpl)\(',
            ).hasMatch(line) &&
            !line.trimLeft().startsWith('///')) {
          offenders.add('$relative:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
