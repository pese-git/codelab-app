// Автомат флаговой формы на фейках портов (ревью 4a, п. 1; design.md change
// `add-provider-setup-ui`, D9, D15).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import '../support/fake_terminal.dart';
import '../support/setup_fakes.dart';

void main() {
  test(
    'секрет появился между шагом ключа и записью (ProviderKeyAppeared): '
    'код 1 «provider add failed», запись не идёт, автомат не виснет',
    () async {
      final check = FakeProviderCheck();
      // Шаг ключа видит «нет», перепроверка перед записью — «есть» (SETUP-5).
      final keys = FakeProviderKeys()..storedAnswers.addAll([false, true]);
      final config = FakeConfigStore(snapshotValue: snapshotOf());
      final flow = buildWizardFlow(
        check: check,
        keys: keys,
        config: config,
        entry: ProviderWizardEntry.flags,
      );
      final result = runProviderAddByFlags(
        flags: const ProviderAddFlags(
          id: 'gw',
          preset: 'custom-openai',
          baseUrl: 'https://gw.example/v1',
          model: 'm1',
          contextWindow: '8000',
          apiKeyStdin: true,
          yes: true,
        ),
        openKit: () async => ProviderAddKit(
          flow: flow,
          backend: 'file',
          pathOf: (_) => '/h/config.yaml',
        ),
        readKey: () async => leakMarker,
        interactive: false,
        terminal: FakeTerminal(),
        cwd: '/work',
      );
      await eventually(() => check.calls.isNotEmpty);
      check.respond(modelsOk(['m1']));

      final done = await result.timeout(const Duration(seconds: 5));

      expect(done.exitCode, 1);
      expect(done.stdout, isEmpty);
      expect(done.stderr.single, startsWith('codelab: provider add failed: '));
      expect(done.stderr.single, isNot(contains(leakMarker)));
      expect(config.applied, isEmpty);
      expect(keys.written, isEmpty);
    },
  );

  test('автомат отменён во время проверки: код 1 с внятной строкой, без '
      'исключения', () async {
    final check = FakeProviderCheck();
    final keys = FakeProviderKeys();
    final config = FakeConfigStore(snapshotValue: snapshotOf());
    final flow = buildWizardFlow(
      check: check,
      keys: keys,
      config: config,
      entry: ProviderWizardEntry.flags,
    );
    final result = runProviderAddByFlags(
      flags: const ProviderAddFlags(
        id: 'gw',
        preset: 'custom-openai',
        baseUrl: 'https://gw.example/v1',
        model: 'm1',
        contextWindow: '8000',
        yes: true,
      ),
      openKit: () async =>
          ProviderAddKit(flow: flow, backend: 'file', pathOf: (_) => ''),
      readKey: () async => null,
      interactive: false,
      terminal: FakeTerminal(),
      cwd: '/work',
    );
    await eventually(() => check.calls.isNotEmpty);

    flow.dispatch(const Cancel());

    final done = await result.timeout(const Duration(seconds: 5));
    expect(done.exitCode, 1);
    expect(
      done.stderr.single,
      'codelab: provider add failed: the setup was cancelled',
    );
    expect(config.applied, isEmpty);
  });
}
