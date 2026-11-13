import 'package:test/test.dart';

import 'support/layered_config_source.dart';
import 'support/server_harness.dart';

/// Геттер `AgentRuntime.subagents`, из которого адаптер строит блок
/// `initialize` (design.md change `add-subagents-and-tasks` D37; задачи 2.4,
/// 2.8a): `null` при `subagents.enabled: false`, иначе значение с `maxDepth`
/// из применённого конфига; живая перезагрузка меняет его без перезапуска.
///
/// Почему в пакете адаптера, а не в ядре: тест проверяет именно тот рантайм,
/// который получает `AcpAgentServer`, и ту же перезагрузку, что в
/// `initialize_subagents_test.dart`. Двойники рантайма (`_SpyRuntime`)
/// дополняет задача 2.4 `[agent]`, поэтому файл красный до неё по
/// компиляции: геттера `subagents` в `AgentRuntime` ещё нет.
void main() {
  ServerHarness? h;

  tearDown(() async => h?.dispose());

  test('the getter reflects the applied config and a live reload', () async {
    final source = LayeredConfigSource(
      extra: {
        'subagents': {'max_depth': 2},
      },
    );
    h = await ServerHarness.start(configSource: source);

    expect(h!.core.runtime.subagents, isNotNull);
    expect(h!.core.runtime.subagents!.maxDepth, 2);

    source.put('subagents.enabled', false);
    await h!.core.runtime.reloadConfig();

    expect(h!.core.runtime.subagents, isNull);
  });
}
