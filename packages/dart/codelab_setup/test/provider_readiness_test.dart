import 'package:codelab_setup/codelab_setup.dart';
import 'package:test/test.dart';

import 'support/provider_setup_fakes.dart';
import 'support/real_home.dart';

/// Готовность провайдера (client-agent-setup «Готовность провайдера»; design.md
/// change `add-provider-setup-ui`, D26). Снимки — из настоящего
/// `FileAgentConfigStore` на временном `CODELAB_HOME`: тексты и виды проблем
/// загрузчика не строятся руками.
void main() {
  late RealHome home;

  setUp(() => home = RealHome.create('provider_readiness_test'));
  tearDown(() => home.dispose());

  group('checkProviderReadiness', () {
    late FakeProviderKeys keys;

    setUp(() => keys = FakeProviderKeys());

    Future<ProviderReadiness> check(
      AgentConfigSnapshot snapshot, [
      Map<String, String> env = const {},
    ]) => checkProviderReadiness(snapshot, keys, env);

    test('пустой дом — NoProviderConfigured, тем же признаком', () async {
      expect(await check(await home.load()), isA<NoProviderConfigured>());
    });

    test('budget.max_steps: 0 — ConfigBroken', () async {
      home.writeConfig('budget:\n  max_steps: 0\n');
      final result = await check(await home.load());
      expect(result, isA<ConfigBroken>());
      expect((result as ConfigBroken).issues, isNotEmpty);
    });

    test('api_key_secret без секрета — ProviderKeyMissing(secret …)', () async {
      home.writeConfig(
        '${gatewayProvider.replaceFirst('    models:', '    api_key_secret: codelab/p\n    models:')}'
        'agent:\n  default_model: gw/m\n',
      );
      final result = await check(await home.load());
      final missing = result as ProviderKeyMissing;
      expect(missing.providerId, 'gw');
      expect(missing.reference, 'secret codelab/p');
      expect(missing.backend.id, 'file');
    });

    test(
      'секрет есть в хранилище или в CODELAB_SECRET_* — ProviderReady',
      () async {
        home.writeConfig(
          '${gatewayProvider.replaceFirst('    models:', '    api_key_secret: codelab/p\n    models:')}'
          'agent:\n  default_model: gw/m\n',
        );
        final snapshot = await home.load();

        keys.storedNames.add('codelab/p');
        expect(await check(snapshot), isA<ProviderReady>());

        keys.storedNames.clear();
        expect(
          await check(snapshot, {'CODELAB_SECRET_CODELAB_P': 'x'}),
          isA<ProviderReady>(),
        );
        // Значения не читаются.
        expect(keys.journal.where((j) => j.startsWith('read')), isEmpty);
      },
    );

    test('api_key_env не задана — ProviderKeyMissing(env K)', () async {
      home.writeConfig(
        '${gatewayProvider.replaceFirst('    models:', '    api_key_env: K\n    models:')}'
        'agent:\n  default_model: gw/m\n',
      );
      final snapshot = await home.load();

      final result = await check(snapshot);
      expect((result as ProviderKeyMissing).reference, 'env K');
      expect(await check(snapshot, {'K': 'v'}), isA<ProviderReady>());
    });

    test('полный конфиг без ключа — ProviderReady(model)', () async {
      home.writeConfig('${gatewayProvider}agent:\n  default_model: gw/m\n');
      final result = await check(await home.load());
      expect((result as ProviderReady).model, 'gw/m');
    });
  });
}
