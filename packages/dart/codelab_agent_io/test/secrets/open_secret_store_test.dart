import 'dart:io';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

import '../support/fake_secret_process_runner.dart';

/// Выбор бэкенда `secrets.backend` (agent-secrets «Выбор бэкенда
/// secrets.backend», сценарии «auto — env на всех ОС», «auto не выбирает
/// file»; design.md change `add-agent-secret-store`, D7).
void main() {
  late Directory root;
  late String home;
  late RecordingLogger logger;
  late FakeSecretProcessRunner runner;

  DescribedSecretStore open(
    String? choice, {
    String platform = 'linux',
    Map<String, String> environment = const {},
  }) => openSecretStore(
    choice: choice,
    environment: environment,
    home: home,
    runner: runner,
    platform: platform,
    logger: logger,
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('open_secret_store_test');
    home = '${root.path}/home';
    logger = RecordingLogger();
    runner = FakeSecretProcessRunner();
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('auto is env on every OS', () {
    for (final platform in ['macos', 'linux', 'windows']) {
      for (final choice in [null, 'auto']) {
        test('$platform with choice $choice', () {
          final store = open(choice, platform: platform);

          expect(store, isA<EnvSecretStore>());
          expect(store.backend.id, 'env');
          expect(store.backend.writable, isFalse);
          final reason = platform == 'windows'
              ? equals(
                  'OS keychain backends are not available in this version; '
                  'set CODELAB_SECRET_* variables',
                )
              : equals(
                  'OS keychain backends are not available in this version; '
                  'set secrets.backend: file or CODELAB_SECRET_* variables',
                );
          expect(store.backend.unavailableReason, reason);
          if (platform == 'windows') {
            expect(
              store.backend.unavailableReason,
              isNot(contains('secrets.backend: file')),
            );
          }
          expect(runner.calls, isEmpty);
          final selected = logger.eventsOf('secrets.backend.selected');
          expect(selected, hasLength(1));
          expect(selected.single.level, LogLevel.info);
          expect(selected.single.fields['backend'], 'env');
          expect(selected.single.fields['path'], isNull);
          expect(selected.single.fields['reason'], reason);
        });
      }
    }

    test('reads CODELAB_SECRET_* from the given environment', () async {
      final store = open(
        'auto',
        environment: {'CODELAB_SECRET_CODELAB_A': 'v'},
      );

      expect(await store.read('codelab/a'), 'v');
    });
  });

  test('auto never selects file even if secrets.yaml exists', () async {
    File('$home/secrets.yaml')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('"codelab/openai": "sk-test-0123456789abcdef"\n');
    Process.runSync('/bin/chmod', ['600', '$home/secrets.yaml']);
    final store = open('auto');
    final resolver = SecretResolver(
      store: store,
      environment: const {},
      logger: logger,
    );

    final lookup = await resolver.secret('codelab/openai', purpose: 'test');

    expect(store.backend.id, 'env');
    expect(lookup, isA<SecretMissing>().having((m) => m.backend, 'b', 'env'));
    expect(logger.eventsOf('secrets.file.refused'), isEmpty);
    expect(logger.eventsOf('secrets.backend.plaintext'), isEmpty);
  });

  test('env is explicit and has no unavailable reason', () {
    final store = open('env');

    expect(store, isA<EnvSecretStore>());
    expect(store.backend.unavailableReason, isNull);
    final selected = logger.eventsOf('secrets.backend.selected').single;
    expect(selected.fields['backend'], 'env');
    expect(selected.fields['path'], isNull);
  });

  test('explicit env and file log the configured reason, never values', () {
    final environment = {'CODELAB_SECRET_CODELAB_A': 'topvalue-env'};
    open('env', environment: environment);
    open('file', environment: environment);

    final selected = logger.eventsOf('secrets.backend.selected');
    expect(selected.map((e) => e.fields['reason']), [
      'configured: secrets.backend: env',
      'configured: secrets.backend: file',
    ]);
    expect(logger.records.join('\n'), isNot(contains('topvalue-env')));
  });

  test('file is FileSecretStore over <home>/secrets.yaml and warns about '
      'plaintext once; the file is not created', () {
    final store = open('file');

    expect(store, isA<FileSecretStore>());
    expect(store.backend.id, 'file');
    expect(store.backend.writable, isTrue);
    final selected = logger.eventsOf('secrets.backend.selected');
    expect(selected, hasLength(1));
    expect(selected.single.fields['backend'], 'file');
    expect(selected.single.fields['path'], '$home/secrets.yaml');
    final plaintext = logger.eventsOf('secrets.backend.plaintext');
    expect(plaintext, hasLength(1));
    expect(plaintext.single.level, LogLevel.warning);
    expect(plaintext.single.fields, {'path': '$home/secrets.yaml'});
    expect(File('$home/secrets.yaml').existsSync(), isFalse);
    expect(Directory(home).existsSync(), isFalse);
  });

  test('file on Windows is a typed failure with the ConfigLoader text, not '
      'UnsupportedError', () {
    expect(
      () => open('file', platform: 'windows'),
      throwsA(
        isA<SecretStoreUnavailableException>()
            .having((e) => e.backend, 'backend', 'file')
            .having(
              (e) => e.reason,
              'reason',
              'file backend is not supported on Windows; use env with '
                  'CODELAB_SECRET_* variables',
            ),
      ),
    );
    expect(logger.eventsOf('secrets.backend.selected'), isEmpty);
  });

  test('keychain and unknown choices are typed failures with spec texts', () {
    final texts = {
      'keychain': 'keychain is not supported yet (supported: auto, env, file)',
      'vault': 'expected one of: auto, keychain, env, file',
      'sk-secret-looking-value': 'expected one of: auto, keychain, env, file',
    };
    for (final entry in texts.entries) {
      expect(
        () => open(entry.key),
        throwsA(
          isA<SecretStoreUnavailableException>().having(
            (e) => e.reason,
            'reason',
            allOf(equals(entry.value), isNot(contains('sk-secret'))),
          ),
        ),
        reason: entry.key,
      );
    }
    expect(logger.eventsOf('secrets.backend.selected'), isEmpty);
  });

  group('secretsBackendProblem is the single check', () {
    test('valid choices have no problem', () {
      for (final platform in ['macos', 'linux', 'windows']) {
        for (final choice in [null, 'auto', 'env']) {
          expect(secretsBackendProblem(choice, platform), isNull);
        }
      }
      expect(secretsBackendProblem('file', 'macos'), isNull);
      expect(secretsBackendProblem('file', 'linux'), isNull);
    });

    test('problems carry the spec texts', () {
      expect(
        secretsBackendProblem('file', 'windows')!.message,
        'file backend is not supported on Windows; use env with '
        'CODELAB_SECRET_* variables',
      );
      expect(
        secretsBackendProblem('keychain', 'linux')!.message,
        'keychain is not supported yet (supported: auto, env, file)',
      );
      expect(
        secretsBackendProblem('x', 'linux')!.message,
        'expected one of: auto, keychain, env, file',
      );
    });
  });

  test('no backend of this version starts a process', () {
    for (final choice in [null, 'auto', 'env', 'file']) {
      open(choice);
    }

    expect(runner.calls, isEmpty);
  });
}
