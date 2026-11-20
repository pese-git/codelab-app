// Адаптер `OnboardingProbe` composition root (задача 2.3 change
// `add-app-onboarding`; design.md D6, D7, D9; spec app-onboarding «Пропуск
// шага выбора модели», «Шаг «Permissions»»).
//
// Красный по причине компиляции: `lib/app/onboarding_probe.dart` появляется в
// задаче 2.4.
//
// Только временная папка (образец — `provider_setup_probe_test.dart`):
// настоящий `~/.codelab` и хранилище секретов разработчика не читаются.
//
// Контракт сверх design.md (принят при реализации 2.4):
// `SetupOnboardingProbe({resolveProfile, codelabHome, logDirectory,
// environment, logger, keysOf})`; `resolveProfile` — шов над
// `DefaultProfileResolver.resolve`, `keysOf` — шов над `providerKeysOf`
// (двойник без `read`: значения ключей не читаются).

import 'dart:io';

import 'package:codelab_client_core/codelab_client_core.dart'
    show ConnectionProfile;
import 'package:codelab_desktop/app/embedded_logger.dart';
import 'package:codelab_desktop/app/onboarding_probe.dart';
import 'package:codelab_desktop/features/onboarding/application/onboarding_probe.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_setup/io.dart' as setup;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Порт ключей поверх настоящего хранилища, но без права читать значения.
final class _NoReadKeys implements ProviderKeys {
  _NoReadKeys(this._inner);

  final ProviderKeys _inner;
  var readCalls = 0;

  @override
  SecretBackendInfo get backend => _inner.backend;

  @override
  String? get readOnlyHint => _inner.readOnlyHint;

  @override
  Future<bool> stored(String name) => _inner.stored(name);

  @override
  Future<SecretValue?> read(String name) async {
    readCalls++;
    throw StateError('значение ключа читать нельзя');
  }

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) =>
      throw StateError('onboarding-зонд не пишет ключи');

  @override
  Future<SecretDeletion> delete(String name) =>
      throw StateError('onboarding-зонд не удаляет ключи');
}

void main() {
  late Directory root;
  late String home;
  late String logs;
  late Map<String, String> environment;
  late _NoReadKeys keys;
  var keysOpened = 0;

  setUp(() {
    root = Directory.systemTemp.createTempSync('codelab-onboarding-probe-');
    addTearDown(() => root.deleteSync(recursive: true));
    home = p.join(root.path, '.codelab');
    Directory(home).createSync();
    logs = p.join(root.path, 'Library', 'logs');
    // HOME нужен подписям путей: `homePathLabel` сокращает по нему до `~`.
    environment = {'HOME': root.path, 'CODELAB_HOME': home};
    keysOpened = 0;
  });

  void config(String yaml) =>
      File(p.join(home, 'config.yaml')).writeAsStringSync(yaml);

  Future<OnboardingFacts> read({
    ConnectionProfile profile = embeddedConnectionProfile,
  }) {
    final probe = SetupOnboardingProbe(
      resolveProfile: () async => profile,
      codelabHome: home,
      logDirectory: logs,
      environment: environment,
      logger: CodeLabEmbeddedLogger(),
      keysOf: (access, {required String home}) {
        keysOpened++;
        return keys = _NoReadKeys(setup.providerKeysOf(access, home: home));
      },
    );
    return probe.read();
  }

  const provider = '''
agent:
  default_model: gw/m
providers:
  gw:
    kind: openai-compatible
    base_url: https://gw.example/v1
    %KEY%
    models:
      m:
        context_window: 8000
''';

  test(
    'пустой дом: NoProviderConfigured, режим standard, бэкенд env',
    () async {
      final facts = await read();

      expect(facts.isExternal, isFalse);
      expect(facts.readiness, isA<NoProviderConfigured>());
      expect(facts.mode, 'standard');
      expect(facts.backendId, 'env');
      expect(facts.backendWritable, isFalse);
    },
  );

  test('api_key_env и заданная переменная: ProviderReady', () async {
    config(provider.replaceFirst('%KEY%', 'api_key_env: GW_KEY'));
    environment['GW_KEY'] = 'value-not-read';

    final facts = await read();

    expect(facts.readiness, isA<ProviderReady>());
    expect((facts.readiness as ProviderReady).model, 'gw/m');
  });

  test('api_key_secret без секрета при backend: file: ProviderKeyMissing, '
      'бэкенд file', () async {
    config(
      'secrets:\n  backend: file\n${provider.replaceFirst('%KEY%', 'api_key_secret: codelab/gw')}',
    );

    final facts = await read();

    final missing = facts.readiness as ProviderKeyMissing;
    expect(missing.providerId, 'gw');
    expect(missing.reference, 'secret codelab/gw');
    expect(facts.backendId, 'file');
    expect(facts.backendWritable, isTrue);
  });

  test('budget.max_steps: 0 — ConfigBroken', () async {
    config(
      '${provider.replaceFirst('%KEY%', 'api_key_env: GW_KEY')}'
      'budget:\n  max_steps: 0\n',
    );

    final facts = await read();

    expect(facts.readiness, isA<ConfigBroken>());
  });

  test(
    'permissions.mode: bypass из общего с CLI конфига — режим bypass',
    () async {
      // Режим читается из разобранного конфига, а он без провайдера не
      // разбирается (тогда действует умолчание standard): нужен годный конфиг.
      config(
        '${provider.replaceFirst('%KEY%', 'api_key_env: GW_KEY')}'
        'permissions:\n  mode: bypass\n',
      );

      final facts = await read();

      expect(facts.mode, 'bypass');
    },
  );

  test(
    'WebSocket-профиль по умолчанию: external, конфиг не читается',
    () async {
      // Битый конфиг: если бы адаптер его читал, он бы сообщил о проблеме или
      // бросил; внешний профиль до конфига не доходит (D6, п. 1).
      config('secrets: [x\n');

      final facts = await read(
        profile: ConnectionProfile.webSocket(
          id: 'remote',
          label: 'Remote',
          uri: Uri.parse('ws://127.0.0.1:8765'),
        ),
      );

      expect(facts.isExternal, isTrue);
      expect(facts.readiness, isNull);
      expect(keysOpened, 0, reason: 'хранилище секретов не открывается');
      expect(facts.logsLabel, isNotEmpty);
    },
  );

  test('подписи путей: дом и каталог логов с ~', () async {
    final facts = await read();

    expect(facts.homeLabel, p.join('~', '.codelab'));
    expect(facts.logsLabel, p.join('~', 'Library', 'logs'));
    expect(facts.homeLabel, isNot(contains(root.path)));
  });

  test('значения ключей не читаются: двойник без read не вызывался', () async {
    config(
      'secrets:\n  backend: file\n${provider.replaceFirst('%KEY%', 'api_key_secret: codelab/gw')}',
    );
    // Секрет кладётся настоящим хранилищем `file`: формат файла не
    // дублируется в тесте. Проверка наличия значения не требует.
    final access = await setup.ClientSecretAccess.open(
      codelabHome: home,
      environment: environment,
      logger: CodeLabEmbeddedLogger(),
    );
    await setup
        .providerKeysOf(access, home: home)
        .write('codelab/gw', SecretValue('sk-test-leak-0123456789'));

    final facts = await read();

    expect(keys.readCalls, 0);
    expect(facts.readiness, isA<ProviderReady>());
    expect(facts.toString(), isNot(contains('sk-test-leak')));
  });

  // Раздел 5 change (ревью 2026-11-21, пп. 2, 3; design.md D6, D8; задача 5.3).
  // Контракт: `OnboardingFacts.access` — `EditableSettings`, по которому
  // прочитан снимок; снимок берётся с `cwd: access.paths.codelabHome`, поэтому
  // проектного слоя папки процесса в нём нет.
  group('один доступ и только user-слой (пп. 2, 3)', () {
    test('конфиг папки процесса не учитывается: .codelab/config.yaml рядом с '
        'процессом не пропускает шаг модели', () async {
      final processDir = Directory.systemTemp.createTempSync(
        'codelab-onboarding-cwd-',
      );
      final previous = Directory.current;
      addTearDown(() {
        Directory.current = previous;
        processDir.deleteSync(recursive: true);
      });
      Directory(p.join(processDir.path, '.codelab')).createSync();
      File(
        p.join(processDir.path, '.codelab', 'config.yaml'),
      ).writeAsStringSync(
        provider.replaceFirst('%KEY%', 'api_key_env: GW_KEY'),
      );
      environment['GW_KEY'] = 'value-not-read';
      Directory.current = processDir;

      final facts = await read();

      expect(facts.readiness, isA<NoProviderConfigured>());
    });

    test('факты несут EditableSettings доступа с домом профиля', () async {
      final facts = await read();

      final access = facts.access!;
      expect(access.paths.codelabHome, home);
    });

    test(
      'stdio-профиль codelab-agent с CODELAB_HOME в env: доступ и готовность '
      'берутся из дома агента, а не из встроенного',
      () async {
        final agentHome = Directory.systemTemp.createTempSync(
          'codelab-onboarding-agent-home-',
        );
        addTearDown(() => agentHome.deleteSync(recursive: true));
        File(p.join(agentHome.path, 'config.yaml')).writeAsStringSync(
          provider.replaceFirst('%KEY%', 'api_key_env: GW_KEY'),
        );
        environment['GW_KEY'] = 'value-not-read';

        final facts = await read(
          profile: ConnectionProfile.stdio(
            id: 'agent',
            label: 'Agent',
            command: 'codelab-agent',
            env: {'CODELAB_HOME': agentHome.path},
          ),
        );

        expect(facts.access!.paths.codelabHome, agentHome.path);
        expect(facts.readiness, isA<ProviderReady>());
        expect(facts.isExternal, isFalse);
      },
    );

    test('у внешнего профиля доступа нет', () async {
      final facts = await read(
        profile: ConnectionProfile.webSocket(
          id: 'remote',
          label: 'Remote',
          uri: Uri.parse('ws://127.0.0.1:8765'),
        ),
      );

      expect(facts.access, isNull);
    });
  });
}
