import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Журнал сессий хоста по настройкам конфигурации (change
/// `add-embedded-agent-mode`, задача 2.8): `codelab-agent` и встроенный агент
/// строят `JsonlSessionStore` одним кодом.
void main() {
  JsonlSessionStore open(HostSettings settings) => openHostSessions(
    codelabHome: '/h',
    settings: settings,
    clock: FakeClock(),
    logger: RecordingLogger(),
  );

  test('defaults: \$CODELAB_HOME/sessions and fsync checkpoints', () {
    final store = open(const HostSettings());

    expect(store.root, '/h/sessions');
    expect(store.fsync, FsyncPolicy.checkpoints);
  });

  test('sessions.dir and sessions.fsync from the config', () {
    final store = open(const HostSettings(sessionsDir: '/s', fsync: 'always'));

    expect(store.root, '/s');
    expect(store.fsync, FsyncPolicy.always);
  });
}
