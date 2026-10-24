import 'dart:io';

import 'package:test/test.dart';

import 'support/package_dir.dart';

/// PKG-5 (`agent-core-architecture` §1.5, §1.7): the public barrel does not
/// expose provider adapters; hosts get them through `createStreamFunction`.
void main() {
  final barrel = File(
    corePath('lib/codelab_agent_core.dart'),
  ).readAsStringSync();

  test('the barrel does not export src/llm/providers/', () {
    expect(barrel, isNot(contains("export 'src/llm/providers/")));
  });

  test('the barrel does not export the test support of testing.dart', () {
    expect(barrel, isNot(contains("export 'src/testing/")));
  });

  test('the barrel exports the factory and its configuration', () {
    expect(barrel, contains("export 'src/llm/provider_factory.dart'"));
    expect(barrel, contains("export 'src/llm/provider_config.dart'"));
  });

  // Внутренние классы цикла не входят в публичный API (PKG-5, design.md
  // D1): хост работает через AgentRuntime и AgentSession.
  test('the barrel does not export the loop internals', () {
    for (final internal in [
      'src/loop/agent_loop.dart',
      'src/loop/agent.dart',
      'src/tools/executor.dart',
      'src/tools/registry.dart',
      'src/env/bounded_env.dart',
      'src/tools/path_lock.dart',
      'src/tools/validator.dart',
      'src/tools/builtin/',
    ]) {
      expect(barrel, isNot(contains("export '$internal")), reason: internal);
    }
  });

  test('the barrel exports the runtime and the assembly', () {
    expect(barrel, contains("export 'src/runtime/agent_runtime.dart'"));
    expect(barrel, contains("export 'src/runtime/agent_session.dart'"));
    expect(barrel, contains("export 'src/host/build_agent_core.dart'"));
  });
}
