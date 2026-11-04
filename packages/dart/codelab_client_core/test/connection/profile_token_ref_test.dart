// Ссылка на токен профиля и общий источник секретов app и CLI (tasks 2.1
// change `add-app-settings-shell`; spec acp-client-kit «Ссылка на токен
// профиля»; design.md, D15).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

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
}
