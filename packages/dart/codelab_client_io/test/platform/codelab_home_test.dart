// Общее правило `CODELAB_HOME` (design.md change `add-app-settings-shell`,
// D7): CLI и app обязаны видеть один `profiles.json`.

import 'package:codelab_client_io/codelab_client_io.dart';
import 'package:test/test.dart';

void main() {
  test('CODELAB_HOME wins over HOME', () {
    expect(
      resolveCodelabHome({
        'CODELAB_HOME': '/data/codelab',
        'HOME': '/Users/me',
      }),
      '/data/codelab',
    );
  });

  test('without CODELAB_HOME the home is ~/.codelab', () {
    expect(resolveCodelabHome({'HOME': '/Users/me'}), '/Users/me/.codelab');
  });

  test('USERPROFILE is used when HOME is absent or empty', () {
    expect(
      resolveCodelabHome({'HOME': '', 'USERPROFILE': '/u'}),
      '/u/.codelab',
    );
  });

  test('~ and ~/x expand through HOME, then USERPROFILE', () {
    const env = {'HOME': '/Users/me'};
    expect(resolveCodelabHome({...env, 'CODELAB_HOME': '~'}), '/Users/me');
    expect(resolveCodelabHome({...env, 'CODELAB_HOME': '~/x'}), '/Users/me/x');
    expect(
      resolveCodelabHome({'USERPROFILE': '/u', 'CODELAB_HOME': '~/x'}),
      '/u/x',
    );
  });

  test('~user/x is an error with the CLI text', () {
    for (final value in ['~bob/x', '~bob', r'~\x']) {
      expect(
        () => resolveCodelabHome({'HOME': '/h', 'CODELAB_HOME': value}),
        throwsA(
          isA<CodelabHomeException>().having(
            (e) => e.message,
            'message',
            'CODELAB_HOME: ~user is not supported, use an absolute path',
          ),
        ),
        reason: value,
      );
    }
  });

  test('~ without HOME and USERPROFILE is an error with the CLI text', () {
    for (final env in [
      {'CODELAB_HOME': '~/x'},
      {'CODELAB_HOME': '~', 'HOME': ''},
    ]) {
      expect(
        () => resolveCodelabHome(env),
        throwsA(
          isA<CodelabHomeException>().having(
            (e) => e.message,
            'message',
            'CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an '
                'absolute path',
          ),
        ),
      );
    }
  });

  test('no home folder at all is an error', () {
    expect(
      () => resolveCodelabHome({}),
      throwsA(
        isA<CodelabHomeException>().having(
          (e) => e.message,
          'message',
          'Cannot find the home folder: set CODELAB_HOME or HOME.',
        ),
      ),
    );
  });
}
