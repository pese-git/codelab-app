// Модульные тесты алиаса `codelab serve` без процессов (change
// `retire-python-agent`, задачи 1.3 и 1.5; design.md D7, D9; spec codelab-cli
// «Алиас codelab serve»).

import 'package:codelab_cli/src/serve_alias.dart';
import 'package:test/test.dart';

void main() {
  group('locateAgentExecutable', () {
    /// Поиск над виртуальной файловой системой: [files] — исполняемые файлы,
    /// [links] — канонические пути ссылок (по умолчанию путь канонический).
    String? locate({
      String codelab = '/opt/codelab/bin/codelab',
      String? path,
      Set<String> files = const {},
      Map<String, String> links = const {},
      bool isWindows = false,
    }) => locateAgentExecutable(
      codelabExecutable: codelab,
      path: path,
      pathSeparator: isWindows ? ';' : ':',
      isWindows: isWindows,
      isExecutableFile: files.contains,
      canonicalize: (file) => links[file] ?? file,
    );

    test('the binary next to codelab wins over PATH', () {
      expect(
        locate(
          path: '/usr/local/bin',
          files: {
            '/opt/codelab/bin/codelab-agent',
            '/usr/local/bin/codelab-agent',
          },
        ),
        '/opt/codelab/bin/codelab-agent',
      );
    });

    test('PATH entries are searched in order', () {
      expect(
        locate(
          path: '/a:/b:/c',
          files: {'/c/codelab-agent', '/b/codelab-agent'},
        ),
        '/b/codelab-agent',
      );
    });

    test('empty and relative PATH entries are skipped (no current dir)', () {
      expect(
        locate(
          path: ':.:bin:/real',
          files: {
            'codelab-agent',
            './codelab-agent',
            'bin/codelab-agent',
            '/real/codelab-agent',
          },
        ),
        '/real/codelab-agent',
      );
      expect(
        locate(path: ':.:bin', files: {'codelab-agent', './codelab-agent'}),
        isNull,
      );
    });

    test('on Windows the name is codelab-agent.exe and ; separates PATH', () {
      expect(
        locate(
          codelab: r'C:\codelab\codelab.exe',
          path: r'C:\x;D:\tools',
          files: {r'D:\tools\codelab-agent.exe', r'D:\tools\codelab-agent'},
          isWindows: true,
        ),
        r'D:\tools\codelab-agent.exe',
      );
    });

    test('a candidate whose canonical path is codelab itself is dropped, the '
        'search goes on', () {
      expect(
        locate(
          path: '/loop:/real',
          files: {'/loop/codelab-agent', '/real/codelab-agent'},
          links: {'/loop/codelab-agent': '/opt/codelab/bin/codelab'},
        ),
        '/real/codelab-agent',
      );
    });

    test('the only candidate being a link to codelab means not found', () {
      expect(
        locate(
          path: '/loop',
          files: {'/loop/codelab-agent'},
          links: {'/loop/codelab-agent': '/opt/codelab/bin/codelab'},
        ),
        isNull,
      );
    });

    test('codelab itself is compared by its canonical path too', () {
      expect(
        locate(
          codelab: '/link/codelab',
          path: '/bin',
          files: {'/bin/codelab-agent'},
          links: {
            '/link/codelab': '/real/codelab',
            '/bin/codelab-agent': '/real/codelab',
          },
        ),
        isNull,
      );
    });

    test('nothing found and a missing PATH give null', () {
      expect(locate(path: '/a:/b'), isNull);
      expect(locate(path: null), isNull);
      expect(locate(path: ''), isNull);
    });
  });

  group('serveAliasExitCode', () {
    test('a normal code of the agent is passed as is', () {
      for (final code in [0, 1, 64, 143]) {
        expect(serveAliasExitCode(code), code);
      }
    });

    test('a negative code is a signal N and becomes 128 + N', () {
      expect(serveAliasExitCode(-15), 143);
      expect(serveAliasExitCode(-2), 130);
      expect(serveAliasExitCode(-9), 137);
    });
  });

  group('texts', () {
    test('the warning is one line with the replacement command', () {
      expect(
        serveAliasWarning,
        'codelab: "codelab serve" is deprecated and will be removed in a '
        'future release; use "codelab-agent serve" instead.',
      );
      expect(serveAliasWarning, isNot(contains('\n')));
    });

    test('not found names both places and prints no PATH', () {
      expect(
        serveAliasNotFound,
        'codelab: codelab-agent was not found next to codelab or in PATH; '
        'install it or run "codelab-agent serve" directly',
      );
    });

    test('a start failure carries only the OS message', () {
      expect(
        serveAliasStartFailure('Permission denied'),
        'codelab: cannot start codelab-agent: Permission denied',
      );
    });
  });
}
