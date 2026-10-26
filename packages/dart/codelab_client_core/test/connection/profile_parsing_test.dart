// Тесты разбора полей профиля (tasks 5.1; перенос `_splitShellWords` и
// `_parseEnv` из `CodeLabShellCubit`, design D8).

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

    test('quotes are not interpreted, as in the app form before', () {
      expect(parseShellWords('"a b"'), ['"a', 'b"']);
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
