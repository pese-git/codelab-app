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
}
