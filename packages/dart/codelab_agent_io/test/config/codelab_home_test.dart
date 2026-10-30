import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// `codelabHomeOf` раскрывает `~` и `~/…` в `CODELAB_HOME` (решение
/// пользователя 2026-10-30; `agent-core-architecture` §15.6): `env` в
/// оболочке не раскрывает тильду внутри кавычек, а относительный `~/x`
/// молча указывал бы на каталог `./~`. `~user/…` и `~` без домашнего каталога —
/// `ConfigUsageException` (D17).
void main() {
  test('plain CODELAB_HOME is returned as is', () {
    expect(codelabHomeOf({'CODELAB_HOME': '/srv/cl', 'HOME': '/h'}), '/srv/cl');
  });

  test('~ and ~/x expand to HOME', () {
    expect(codelabHomeOf({'CODELAB_HOME': '~', 'HOME': '/h'}), '/h');
    expect(codelabHomeOf({'CODELAB_HOME': '~/x', 'HOME': '/h'}), '/h/x');
  });

  test('USERPROFILE is used when HOME is absent or empty', () {
    expect(
      codelabHomeOf({'CODELAB_HOME': '~/x', 'USERPROFILE': r'C:\u'}),
      r'C:\u/x',
    );
    expect(
      codelabHomeOf({'CODELAB_HOME': '~/x', 'HOME': '', 'USERPROFILE': '/u'}),
      '/u/x',
    );
  });

  test('~user/x is a usage error with the fixed text', () {
    expect(
      () => codelabHomeOf({'CODELAB_HOME': '~bob/x', 'HOME': '/h'}),
      throwsA(
        isA<ConfigUsageException>().having(
          (e) => e.message,
          'message',
          'CODELAB_HOME: ~user is not supported, use an absolute path',
        ),
      ),
    );
  });

  test(r'~\x is a usage error too', () {
    expect(
      () => codelabHomeOf({'CODELAB_HOME': r'~\x', 'HOME': '/h'}),
      throwsA(isA<ConfigUsageException>()),
    );
  });

  test('~ without a home folder (absent or empty) is a usage error', () {
    for (final env in [
      {'CODELAB_HOME': '~/x', 'HOME': ''},
      {'CODELAB_HOME': '~'},
    ]) {
      expect(
        () => codelabHomeOf(env),
        throwsA(
          isA<ConfigUsageException>().having(
            (e) => e.message,
            'message',
            'CODELAB_HOME: cannot expand ~ without HOME or USERPROFILE, use '
                'an absolute path',
          ),
        ),
      );
    }
  });

  test('a scripted load does not check CODELAB_HOME', () {
    final root = Directory.systemTemp.createTempSync('home_scripted_test');
    addTearDown(() => root.deleteSync(recursive: true));
    expect(
      () => ConfigLoader().load(
        cwd: root.path,
        environment: {'CODELAB_HOME': '~bob/cl'},
        scripted: true,
      ),
      returnsNormally,
    );
    expect(Directory('${root.path}/~bob').existsSync(), isFalse);
  });

  test('default is HOME/.codelab', () {
    expect(codelabHomeOf({'HOME': '/h'}), '/h/.codelab');
  });

  test('trusted_projects use the same expansion', () {
    final root = Directory.systemTemp.createTempSync('home_trust_test');
    addTearDown(() => root.deleteSync(recursive: true));
    final home = root.resolveSymbolicLinksSync();
    Directory('$home/proj').createSync();
    Directory('$home/cwd').createSync();
    File('$home/h/config.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
providers:
  p:
    kind: openai-compatible
    base_url: https://llm.test/v1
    models:
      m: {}
agent:
  default_model: p/m
trusted_projects:
  - ~/proj
''');
    final result = ConfigLoader().load(
      cwd: '$home/cwd',
      environment: {'CODELAB_HOME': '$home/h', 'HOME': home},
    );
    expect(result.config?.trustedProjects, ['$home/proj']);
  });
}
