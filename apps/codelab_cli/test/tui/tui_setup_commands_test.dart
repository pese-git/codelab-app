// В итерации 4a `/provider` и `/settings` в `--ui tui` не исполняются и не
// показываются в slash-меню (задача 4.3 change `add-provider-setup-ui`;
// design.md D17, «Сверка с кодом»): TUI берёт список `mvpReplCommands`, а
// построчный мастер внутри кадра TUI невозможен. Команды появятся в TUI в 4b
// вместе с оверлеями (4.15).
//
// Здесь же — `TuiCommandContext` пробрасывает порт `SetupCommands`
// (`TuiCommandContext(setup:)`, `ReplContext.setup`), без оверлеев 4a.
//
// Это отдельный файл, а не добавление в `tui_command_context_test.dart`:
// новый параметр `setup:` ещё не собирается, и существующие тесты контекста
// не должны краснеть по компиляции.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/setup_fakes.dart';
import '../support/setup_repl_harness.dart';

void main() {
  group('список команд TUI', () {
    final names = [for (final c in mvpReplCommands) c.name];

    test('/provider и /settings в нём нет', () {
      expect(names, isNot(contains('provider')));
      expect(names, isNot(contains('settings')));
    });

    test('команды не исполняются: маршрут неизвестной команды', () {
      final router = CommandRouter(mvpReplCommands);

      for (final line in [
        '/provider add',
        '/provider list',
        '/settings',
        '/settings agent.effort high',
      ]) {
        expect(
          router.route(line, agentCommands: const []),
          isA<UnknownCommandRoute>(),
          reason: line,
        );
      }
    });

    test('slash-меню не предлагает их по префиксу', () {
      final router = CommandRouter(mvpReplCommands);

      final provider = router.complete('/prov', agentCommands: const []);
      final settings = router.complete('/set', agentCommands: const []);

      expect(
        provider.candidates.map((c) => c.label),
        isNot(contains('/provider')),
      );
      expect(settings.candidates, isEmpty);
      expect(settings.replacement, isNull);
    });

    test('/help не называет их', () {
      expect([
        for (final c in mvpReplCommands) c.usage,
      ], isNot(anyElement(contains('/provider'))));
      expect([
        for (final c in mvpReplCommands) c.usage,
      ], isNot(anyElement(contains('/settings'))));
    });
  });

  test('TuiCommandContext пробрасывает порт setup без оверлеев', () async {
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
    expect(setup.flowRequests, 0);
    expect(sent, isEmpty);
  });
}
