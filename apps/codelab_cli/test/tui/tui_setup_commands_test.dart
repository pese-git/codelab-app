// В итерации 4b `/provider` и `/settings` исполняются и в `--ui tui` (задача
// 4.15 change `add-provider-setup-ui`; design.md D17): TUI переходит с
// `mvpReplCommands` на `replCommands`, а мастер и экран настроек — модальные
// оверлеи. До 4b (итерация 4a) команд в TUI не было, и этот файл проверял
// обратное; ожидание заменено по tasks.md 4.15.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/setup_fakes.dart';
import '../support/setup_repl_harness.dart';

void main() {
  group('список команд TUI', () {
    final names = [for (final c in replCommands) c.name];

    test('/provider и /settings в нём есть', () {
      expect(names, containsAll(['provider', 'settings']));
    });

    test('команды исполняются: маршрут клиентской команды', () {
      final router = CommandRouter(replCommands);

      for (final line in ['/provider add', '/provider list', '/settings']) {
        expect(
          router.route(line, agentCommands: const []),
          isA<ClientCommandRoute>(),
          reason: line,
        );
      }
    });

    test('slash-меню предлагает их по префиксу', () {
      final router = CommandRouter(replCommands);

      expect(
        router
            .complete('/pro', agentCommands: const [])
            .candidates
            .map((c) => c.label),
        contains('/provider'),
      );
      expect(
        router.complete('/set', agentCommands: const []).replacement,
        '/settings ',
      );
    });

    test('/help (usage команд) называет их', () {
      final usage = [for (final c in replCommands) c.usage].join('\n');

      expect(usage, contains('/provider'));
      expect(usage, contains('/settings'));
    });
  });

  test('TuiCommandContext: список команд по умолчанию — replCommands, порт '
      'setup пробрасывается', () async {
    final agent = FakeAgent();
    addTearDown(agent.dispose);
    await agent.workspace.connect(FakeAgent.profile, projectDirectory: '/w');
    final setup = FakeSetupCommands(
      configStore: FakeConfigStore(snapshotValue: snapshotOf(cwd: '/w')),
      check: FakeProviderCheck(),
      keys: FakeProviderKeys(),
    );
    final sent = <TuiMsg>[];
    final context = TuiCommandContext(
      workspace: agent.workspace,
      profile: FakeAgent.profile,
      cwd: '/w',
      send: sent.add,
      onExit: (_) {},
      setup: setup,
    );
    addTearDown(context.close);

    final ReplContext asContext = context;

    expect(asContext.setup, same(setup));
    expect(
      asContext.commands.map((c) => c.name),
      containsAll(['provider', 'settings']),
    );
    expect(sent, isEmpty);
  });
}
