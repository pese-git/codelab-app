// Ссылка на токен профиля и общий источник секретов app и CLI (tasks 2.1
// change `add-app-settings-shell`; spec acp-client-kit «Ссылка на токен
// профиля»; design.md, D15). Форма `secret:<имя>` и порт `stored` — task 1.2
// change `add-provider-setup-ui` (spec acp-client-kit «Ссылка на токен
// профиля»; design.md, D13).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/profile_fakes.dart';

void main() {
  const environment = {
    'CODELAB_AGENT_TOKEN': 't1',
    'DEVBOX_TOKEN': 't2',
    'EMPTY': '',
  };

  group('ProfileSecretSource', () {
    const secrets = ProfileSecretSource(environment);

    test('reads env:<NAME> for CODELAB_AGENT_TOKEN and any other '
        'variable', () async {
      expect(await secrets.read('env:CODELAB_AGENT_TOKEN'), 't1');
      expect(await secrets.read('env:DEVBOX_TOKEN'), 't2');
    });

    test('an empty or a missing variable is no token', () async {
      expect(await secrets.read('env:EMPTY'), isNull);
      expect(await secrets.read('env:MISSING'), isNull);
    });

    test('a secret name is an unsupported reference: no token', () async {
      expect(await secrets.read('codelab/profiles/dev/token'), isNull);
    });

    test('an invalid variable name is no token even if the variable '
        'exists', () async {
      const odd = ProfileSecretSource({'1BAD': 'x', 'A-B': 'y', '': 'z'});

      expect(await odd.read('env:1BAD'), isNull);
      expect(await odd.read('env:A-B'), isNull);
      expect(await odd.read('env:'), isNull);
    });
  });

  group('ProfileTokenRef.parse', () {
    test('env:<NAME> is an environment variable reference', () {
      expect(
        ProfileTokenRef.parse('env:CODELAB_AGENT_TOKEN'),
        const EnvTokenRef('CODELAB_AGENT_TOKEN'),
      );
      expect(
        ProfileTokenRef.parse('env:DEVBOX_TOKEN'),
        const EnvTokenRef('DEVBOX_TOKEN'),
      );
      expect(ProfileTokenRef.parse('env:_x1'), const EnvTokenRef('_x1'));
    });

    test('a secret name is unsupported in this version', () {
      expect(
        ProfileTokenRef.parse('codelab/profiles/dev/token'),
        const UnsupportedTokenRef('codelab/profiles/dev/token'),
      );
    });

    test('an invalid variable name is unsupported', () {
      for (final ref in ['env:1BAD', 'env:A-B', 'env:', 'env:A B', 'ENV:X']) {
        expect(
          ProfileTokenRef.parse(ref),
          UnsupportedTokenRef(ref),
          reason: ref,
        );
      }
    });
  });

  test('toString of an unsupported reference hides the value (it may be a '
      'secret written into the wrong field)', () {
    const ref = UnsupportedTokenRef('sk-test-leak-123');

    expect('$ref', isNot(contains('sk-test-leak-123')));
    expect('$ref', 'UnsupportedTokenRef(<redacted>)');
  });

  group('secret: references (add-provider-setup-ui, D13)', () {
    const env = {
      'CODELAB_AGENT_TOKEN': 't1',
      'DEVBOX_TOKEN': 't2',
      'EMPTY': '',
    };

    test('forms of a reference: env, secret, empty, missing and a bare '
        'secret name', () async {
      final stored = FakeProfileSecrets(
        values: {'codelab/profiles/dev/token': 't3'},
      );
      final secrets = ProfileSecretSource(env, stored: stored);

      expect(await secrets.read('env:CODELAB_AGENT_TOKEN'), 't1');
      expect(await secrets.read('env:DEVBOX_TOKEN'), 't2');
      expect(await secrets.read('env:EMPTY'), isNull);
      expect(await secrets.read('env:MISSING'), isNull);
      expect(await secrets.read('secret:codelab/profiles/dev/token'), 't3');
      expect(await secrets.read('secret:codelab/missing'), isNull);
      // Голое имя без префикса — возможный вписанный токен: не читается.
      expect(await secrets.read('codelab/profiles/dev/token'), isNull);
    });

    test('parse: secret:<name> is a SecretTokenRef with a canonical ref', () {
      final parsed = ProfileTokenRef.parse('secret:codelab/profiles/dev/token');

      expect(parsed, const SecretTokenRef('codelab/profiles/dev/token'));
      expect(
        (parsed as SecretTokenRef).ref,
        'secret:codelab/profiles/dev/token',
      );
      expect(parsed.name, 'codelab/profiles/dev/token');
    });

    test('unsupported: a bare name and invalid secret names', () {
      for (final ref in [
        'codelab/profiles/dev/token',
        'secret:Bad Name',
        'secret:a/../b',
        'secret:a..b',
        'secret:a//b',
        'secret:a/',
        'secret:',
        'secret:/a',
        'secret:${'a' * 129}',
        'SECRET:abc',
      ]) {
        expect(
          ProfileTokenRef.parse(ref),
          UnsupportedTokenRef(ref),
          reason: ref,
        );
      }
      expect(
        ProfileTokenRef.parse('secret:${'a' * 128}'),
        isA<SecretTokenRef>(),
      );
    });

    test('an unsupported secret: reference is no token and its toString is '
        'masked', () async {
      final stored = FakeProfileSecrets(values: {'Bad Name': 'leak'});
      final secrets = ProfileSecretSource(env, stored: stored);

      expect(await secrets.read('secret:Bad Name'), isNull);
      final parsed = ProfileTokenRef.parse('secret:sk-test-leak-0123456789 x');
      expect(parsed, isA<UnsupportedTokenRef>());
      expect('$parsed', isNot(contains('sk-test-leak')));
    });

    test('without the stored port a secret: reference is null, no '
        'exception', () async {
      const secrets = ProfileSecretSource(env);

      expect(await secrets.read('secret:codelab/profiles/dev/token'), isNull);
    });

    test('an empty stored value is no token', () async {
      final secrets = ProfileSecretSource(
        env,
        stored: FakeProfileSecrets(values: {'codelab/ws': ''}),
      );

      expect(await secrets.read('secret:codelab/ws'), isNull);
    });

    test('a replaced secret is seen on the next read (no cache)', () async {
      final stored = FakeProfileSecrets(values: {'codelab/ws': 'a'});
      final secrets = ProfileSecretSource(env, stored: stored);

      expect(await secrets.read('secret:codelab/ws'), 'a');
      // Другой процесс заменил значение, пока транспорт был закрыт.
      stored.values['codelab/ws'] = 'b';
      expect(await secrets.read('secret:codelab/ws'), 'b');
    });
  });

  group('missing token secret (add-provider-setup-ui, D13)', () {
    WebSocketProfile ws(String? ref) => WebSocketProfile(
      id: 'devbox',
      label: 'Devbox',
      uri: Uri.parse('wss://devbox:7420'),
      tokenRef: ref,
    );

    test('isSecretMissing is true only for a secret: reference without a '
        'value', () async {
      final secrets = ProfileSecretSource(const {
        'DEVBOX_TOKEN': 'x',
      }, stored: FakeProfileSecrets(values: {'codelab/ws': 'v'}));

      expect(await secrets.isSecretMissing(ws('secret:codelab/ws')), isFalse);
      expect(await secrets.isSecretMissing(ws('secret:codelab/none')), isTrue);
      // Другие виды ссылок и профили не про секрет — предупреждения нет.
      expect(await secrets.isSecretMissing(ws(null)), isFalse);
      expect(await secrets.isSecretMissing(ws('env:NOPE')), isFalse);
      expect(await secrets.isSecretMissing(ws('whatever')), isFalse);
      expect(
        await secrets.isSecretMissing(
          const StdioProfile(id: 's', label: 's', command: 'c'),
        ),
        isFalse,
      );
    });

    test('without the stored port or with a failing store the secret is '
        'missing, no exception', () async {
      expect(
        await const ProfileSecretSource({}).isSecretMissing(ws('secret:a/b')),
        isTrue,
      );
      expect(
        await ProfileSecretSource(
          const {},
          stored: _ThrowingSecrets(),
        ).isSecretMissing(ws('secret:a/b')),
        isTrue,
      );
    });

    test('isSecretMissing asks isSet and never reads the value', () async {
      final stored = FakeProfileSecrets(values: {'codelab/ws': 'v'});
      final secrets = ProfileSecretSource(const {}, stored: stored);

      expect(await secrets.isSecretMissing(ws('secret:codelab/ws')), isFalse);
      expect(await secrets.isSecretMissing(ws('secret:codelab/no')), isTrue);

      expect(stored.isSetCalls, 2);
      expect(stored.readCalls, 0);
    });

    test('the warning text names only the profile id', () {
      expect(
        secretMissingWarning('devbox'),
        'Profile devbox has no stored secret value; connecting without '
        'a token.',
      );
    });
  });
}

final class _ThrowingSecrets extends FakeProfileSecrets {
  @override
  Future<bool> isSet(String name) => throw StateError('store down');
}
