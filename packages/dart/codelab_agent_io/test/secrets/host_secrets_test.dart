import 'dart:io';
import 'dart:isolate';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

const value = 'sk-test-0123456789abcdef';

/// Запускает `openHostSecrets` в isolate. Замыкание создаётся в отдельной
/// функции, чтобы в сообщение попала только строка [codelabHome], а не
/// контекст теста (D15: через границу идут только сериализуемые данные).
Future<({bool found, String source, int lookups, bool leaked})>
_resolveInIsolate(String codelabHome) => Isolate.run(() async {
  final logger = RecordingLogger();
  final resolver = openHostSecrets(
    codelabHome: codelabHome,
    environment: {'CODELAB_SECRET_CODELAB_P': value},
    backend: 'env',
    debug: true,
    logger: logger,
  );
  final lookup = await resolver.secret('codelab/p', purpose: 'test');
  return (
    found: lookup is SecretFound,
    source: lookup is SecretFound ? lookup.source : '',
    lookups: logger.eventsOf('secrets.lookup').length,
    leaked: logger.records.join('\n').contains(value),
  );
});

/// Секреты настольных хостов (agent-secrets «Секреты настольных хостов и
/// встроенных профилей», все сценарии; design.md change
/// `add-agent-secret-store`, D15).
void main() {
  late Directory root;
  late String home;

  setUp(() {
    root = Directory.systemTemp.createTempSync('host_secrets_test');
    home = '${root.path}/home';
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('openHostSecrets works inside an isolate from serializable data; only '
      'found/source leave it and the log has no value', () async {
    final result = await _resolveInIsolate(home);

    expect(result.found, isTrue);
    expect(result.source, 'env');
    expect(result.lookups, 1);
    expect(result.leaked, isFalse);
  });

  test('a secret saved by SecretAdmin is found by the resolver on the file '
      'backend', () async {
    final logger = RecordingLogger();
    final admin = SecretAdmin(
      store: FileSecretStore(path: '$home/secrets.yaml'),
      environment: const {},
    );
    expect(await admin.store('codelab/p', value), isA<SecretStored>());

    final resolver = openHostSecrets(
      codelabHome: home,
      environment: const {},
      backend: 'file',
      debug: false,
      logger: logger,
    );
    final lookup = await resolver.secret('codelab/p', purpose: 'test');

    expect(lookup, isA<SecretFound>());
    lookup as SecretFound;
    expect(lookup.value, value);
    expect(lookup.source, 'file');
    expect(logger.eventsOf('secrets.backend.plaintext'), hasLength(1));
  });

  test('a null backend is auto: env, never the file', () async {
    final logger = RecordingLogger();
    await SecretAdmin(
      store: FileSecretStore(path: '$home/secrets.yaml'),
      environment: const {},
    ).store('codelab/p', value);

    final resolver = openHostSecrets(
      codelabHome: home,
      environment: const {},
      backend: null,
      debug: false,
      logger: logger,
    );

    expect(
      await resolver.secret('codelab/p', purpose: 'test'),
      isA<SecretMissing>(),
    );
  });

  test('a replaced secret is seen only by a new resolver', () async {
    final logger = RecordingLogger();
    SecretResolver open() => openHostSecrets(
      codelabHome: home,
      environment: const {},
      backend: 'file',
      debug: false,
      logger: logger,
    );
    SecretAdmin admin() => SecretAdmin(
      store: FileSecretStore(path: '$home/secrets.yaml'),
      environment: const {},
    );
    await admin().store('codelab/p', 'old-value');
    final first = open();
    expect(
      (await first.secret('codelab/p', purpose: 't') as SecretFound).value,
      'old-value',
    );

    await admin().store('codelab/p', 'new-value');

    final cached = await first.secret('codelab/p', purpose: 't') as SecretFound;
    expect(cached.value, 'old-value');
    expect(cached.source, 'cache');
    final fresh = await open().secret('codelab/p', purpose: 't') as SecretFound;
    expect(fresh.value, 'new-value');
    expect(fresh.source, 'file');
  });

  test('debug mode logs lookups without the value', () async {
    final logger = RecordingLogger();
    final resolver = openHostSecrets(
      codelabHome: home,
      environment: {'CODELAB_SECRET_CODELAB_P': value},
      backend: null,
      debug: true,
      logger: logger,
    );

    await resolver.secret('codelab/p', purpose: 'providers.p.api_key_secret');

    final lookup = logger.eventsOf('secrets.lookup').single;
    expect(lookup.fields['name'], 'codelab/p');
    expect(lookup.fields['found'], true);
    expect(logger.records.join('\n'), isNot(contains(value)));
  });
}
