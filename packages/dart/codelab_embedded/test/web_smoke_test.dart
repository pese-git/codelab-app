import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:test/test.dart';

import 'web_smoke/main.dart';

/// Тот же код, что `melos run web-compile` собирает в JS и Wasm, на Dart VM:
/// основной барель встроенного агента собирает ядро на `MemoryExecutionEnv` и
/// закрывается (embedded-agent «Основной барель собирается для web»; design.md
/// change `add-embedded-agent-mode`, D3).
void main() {
  test('the main barrel assembles and disposes an agent over memory', () async {
    final report = await runEmbeddedWebSmoke();

    expect(report.profile, 'embedded-cli');
    expect(report.toolNames, containsAll(['read', 'write', 'edit']));
    expect(report.toolNames, isNot(contains('exec')));
    expect(report.transportState, AcpTransportState.idle);
  });
}
