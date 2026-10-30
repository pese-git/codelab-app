// Домашний каталог CLI (tasks 2.3; spec codelab-cli «Профили подключения
// CLI»; design.md change `add-codelab-cli`, D4).

import 'dart:io';

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  test('CODELAB_HOME wins over HOME', () {
    final home = CodelabHome.resolve({
      'CODELAB_HOME': '/data/codelab',
      'HOME': '/Users/me',
    });

    expect(home.path, '/data/codelab');
    expect(home.profilesFile, '/data/codelab/profiles.json');
    expect(home.historyFile, '/data/codelab/cli_history');
  });

  test('without CODELAB_HOME the home is ~/.codelab', () {
    expect(
      CodelabHome.resolve({'HOME': '/Users/me'}).path,
      '/Users/me/.codelab',
    );
  });

  test('CODELAB_HOME with ~ or ~/x expands to the home folder', () {
    const env = {'HOME': '/Users/me'};
    expect(
      CodelabHome.resolve({...env, 'CODELAB_HOME': '~'}).path,
      '/Users/me',
    );
    expect(
      CodelabHome.resolve({...env, 'CODELAB_HOME': '~/x'}).path,
      '/Users/me/x',
    );
    expect(
      CodelabHome.resolve({'USERPROFILE': '/u', 'CODELAB_HOME': '~/x'}).path,
      '/u/x',
    );
  });

  test(
    'CODELAB_HOME with ~user/x is a usage error (same text as the agent)',
    () {
      expect(
        () =>
            CodelabHome.resolve({'HOME': '/Users/me', 'CODELAB_HOME': '~u/x'}),
        throwsA(
          isA<UsageError>().having(
            (e) => e.message,
            'message',
            'CODELAB_HOME: ~user is not supported, use an absolute path',
          ),
        ),
      );
    },
  );

  test(r'CODELAB_HOME with ~\x is a usage error', () {
    expect(
      () => CodelabHome.resolve({'HOME': '/Users/me', 'CODELAB_HOME': r'~\x'}),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          contains('~user is not supported'),
        ),
      ),
    );
  });

  test('CODELAB_HOME with ~ and an empty HOME is a usage error', () {
    expect(
      () => CodelabHome.resolve({'CODELAB_HOME': '~/x', 'HOME': ''}),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          'CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use an '
              'absolute path',
        ),
      ),
    );
  });

  test('USERPROFILE is the home folder on Windows', () {
    expect(
      CodelabHome.resolve({'USERPROFILE': r'C:\Users\me'}).path,
      endsWith('.codelab'),
    );
  });

  test('no home folder at all is a usage error', () {
    expect(() => CodelabHome.resolve({}), throwsA(isA<UsageError>()));
  });

  test('ensureExists() creates the folder with mode 0700', () async {
    final tmp = Directory.systemTemp.createTempSync('codelab_home_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final home = CodelabHome.resolve({'CODELAB_HOME': '${tmp.path}/home'});

    await home.ensureExists();

    final stat = Directory(home.path).statSync();
    expect(stat.type, FileSystemEntityType.directory);
    expect(stat.mode & 0x1ff, 0x1c0); // 0700
  }, skip: Platform.isWindows ? 'POSIX permissions only' : false);
}
