// Тесты разбора полей профиля (tasks 5.1; перенос `_splitShellWords` и
// `_parseEnv` из `CodeLabShellCubit`, design D8; кавычки — tasks 2.1 change
// `add-codelab-cli`, spec acp-client-kit «Профили и резолверы транспорта»).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseShellWords', () {
    test('splits on any whitespace and drops empty words', () {
      expect(parseShellWords('  serve   --stdio\t--log x\n'), [
        'serve',
        '--stdio',
        '--log',
        'x',
      ]);
    });

    test('an empty or blank line gives no words', () {
      expect(parseShellWords(''), isEmpty);
      expect(parseShellWords('   '), isEmpty);
    });

    test('quotes and escapes follow POSIX shell without expansions', () {
      expect(
        parseShellWords('python -m "codelab agent" --name \'a b\' x\\ y'),
        ['python', '-m', 'codelab agent', '--name', 'a b', 'x y'],
      );
    });

    test('single quotes keep the text literally', () {
      expect(parseShellWords(r"""'a "b" \n $HOME'"""), [r'a "b" \n $HOME']);
    });

    test(r'double quotes unescape only \" and \\', () {
      expect(parseShellWords(r'"say \"hi\" \\ \n"'), [r'say "hi" \ \n']);
    });

    test('quoted parts join with adjacent text into one word', () {
      expect(parseShellWords('--opt="a b"c'), ['--opt=a bc']);
    });

    test('empty quotes give an empty word', () {
      expect(parseShellWords('run "" \'\''), ['run', '', '']);
    });

    test('an unterminated quote is a FormatException', () {
      expect(() => parseShellWords('run "oops'), throwsFormatException);
      expect(() => parseShellWords("run 'oops"), throwsFormatException);
    });

    test('a trailing backslash is a FormatException', () {
      expect(() => parseShellWords(r'run \'), throwsFormatException);
    });
  });

  group('parseEnvLines', () {
    test('reads KEY=VALUE lines and trims both sides', () {
      expect(parseEnvLines(' CODELAB_LOG_LEVEL = DEBUG \nEXTRA=value'), {
        'CODELAB_LOG_LEVEL': 'DEBUG',
        'EXTRA': 'value',
      });
    });

    test('the value keeps further equals signs', () {
      expect(parseEnvLines('URL=http://h/?a=b'), {'URL': 'http://h/?a=b'});
    });

    test('blank lines and lines without a key are skipped', () {
      expect(parseEnvLines('\n=nokey\nnoequals\nA=1\n'), {'A': '1'});
    });
  });
}
