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

  // Второй реализации SSE нет: MCP-клиент читает потоки тем же декодером
  // (change `add-agent-mcp-client`, D10; §2.6).
  test('the barrel exports the SSE decoder for the MCP transport', () {
    expect(barrel, contains("export 'src/llm/sse.dart'"));
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
      'src/tools/path_lock.dart',
      'src/tools/validator.dart',
      'src/tools/builtin/',
      // Механизмы журнала и сжатия — внутренние (design.md этапа 3, D1).
      'src/session/session_writer.dart',
      'src/session/projections.dart',
      'src/compaction/',
    ]) {
      expect(barrel, isNot(contains("export '$internal")), reason: internal);
    }
  });

  // Граница рабочей папки нужна не только инструментам ядра: загрузчик
  // файлов проекта хоста читает через `BoundedEnv` корень своей области
  // (change `add-agent-project-files`, D2). Экспортируется один тип, без
  // внутренностей декоратора; инструменты по-прежнему получают только
  // окружение за границей (ENV-2).
  test('the barrel exports only BoundedEnv of the boundary decorator', () {
    expect(
      barrel,
      contains("export 'src/env/bounded_env.dart' show BoundedEnv;"),
    );
  });

  // Конфигурация: хост видит типы входа и результата, а схема, обход слоя,
  // доверие и слияние — внутренности проверки (change
  // `add-agent-configuration`, D3; CFG-5).
  test('the barrel exports the configuration contract, not its internals', () {
    for (final public in [
      'src/config/config_tree.dart',
      'src/config/config_issue.dart',
      'src/config/core_config.dart',
      'src/config/host_settings.dart',
      'src/config/redact_settings.dart',
    ]) {
      expect(barrel, contains("export '$public"), reason: public);
    }
    for (final internal in [
      'src/config/schema.dart',
      'src/config/validate.dart',
      'src/config/trust.dart',
      'src/config/merge.dart',
      'src/config/interpolate.dart',
      'src/config/resolve.dart',
    ]) {
      expect(barrel, isNot(contains("export '$internal")), reason: internal);
    }
  });

  test('the barrel exports the runtime and the assembly', () {
    expect(barrel, contains("export 'src/runtime/agent_runtime.dart'"));
    expect(barrel, contains("export 'src/runtime/agent_session.dart'"));
    expect(barrel, contains("export 'src/host/build_agent_core.dart'"));
  });

  // Формат журнала и порт хранилища нужны JsonlSessionStore другого пакета
  // (design.md этапа 3, D1).
  test('the barrel exports the journal format and the store port', () {
    for (final file in [
      'src/session/records.dart',
      'src/session/parse.dart',
      'src/session/session_store.dart',
      'src/session/memory_session_store.dart',
      'src/session/slug.dart',
    ]) {
      expect(barrel, contains("export '$file'"), reason: file);
    }
  });
}
