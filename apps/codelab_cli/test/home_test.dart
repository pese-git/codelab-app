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
