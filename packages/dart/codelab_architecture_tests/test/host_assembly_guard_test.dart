import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/host_assembly.dart';
import 'support/repo_root.dart';

/// HOST-6 (документ ядра §10): хосты собирают ядро только через
/// `buildAgentCore` — ни `ToolRegistry(`, ни `Agent(`, ни `AgentRuntime(` в
/// коде хоста (workspace-architecture «Автоматический сторож границ
/// пакетов»; design.md change `add-codelab-agent-binary`, D11).
void main() {
  final root = repoRoot();

  test('apps/codelab_agent builds the core only through buildAgentCore', () {
    final violations = [
      for (final dir in ['lib', 'bin'])
        ...scanHostAssembly(p.join(root, 'apps', 'codelab_agent', dir)),
    ];

    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('reports a manual core assembly with file and line', () {
    final tmp = Directory.systemTemp.createTempSync('guard_host_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File(p.join(tmp.path, 'lib', 'src', 'host.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '/// AgentRuntime( in a comment is fine.\n'
        'final server = AcpAgentServer(core: core);\n'
        'final runtime = AgentRuntime(services);\n'
        'final registry = ToolRegistry();\n',
      );

    final violations = scanHostAssembly(p.join(tmp.path, 'lib'));

    expect(violations, hasLength(2));
    expect(violations.first, endsWith('lib/src/host.dart:3 -> AgentRuntime('));
    expect(violations.last, endsWith('lib/src/host.dart:4 -> ToolRegistry('));
  });
}
