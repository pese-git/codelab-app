// Логгер ядра клиента в CLI (tasks 3.4; spec cli-headless «Вывод headless»;
// design.md change `add-codelab-cli`, D9): stdout headless несёт только
// ответ, поэтому лог ядра клиента — только stderr и только с `--verbose`.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:test/test.dart';

void main() {
  test('a silent logger writes nothing', () {
    final sink = StringBuffer();
    final logger = CliLogger.silent();

    logger
      ..info('session_created', context: {'session_id': 's1'})
      ..error('send_failed');

    expect(sink.toString(), isEmpty);
  });

  test('a verbose logger writes one line per entry from info up', () {
    final sink = StringBuffer();
    final logger = CliLogger(sink);

    logger
      ..debug('frame')
      ..info('session_created', context: {'session_id': 's1'})
      ..warning('slow');

    expect(sink.toString().trimRight().split('\n'), [
      '[info] session_created session_id=s1',
      '[warning] slow',
    ]);
  });

  test('bound and correlation context reach every line', () {
    final sink = StringBuffer();
    final logger = CliLogger(
      sink,
    ).bind({'component': 'client'}).withCorrelation(sessionId: 's1');

    logger.info('prompt_sent');

    expect(sink.toString(), contains('component=client'));
    expect(sink.toString(), contains('s1'));
  });

  test('secrets in the context are redacted', () {
    final sink = StringBuffer();

    CliLogger(sink).info(
      'connect',
      context: {'token': 'super-secret', 'note': 'Bearer abcdefghijklmnop'},
    );

    expect(sink.toString(), isNot(contains('super-secret')));
    expect(sink.toString(), isNot(contains('abcdefghijklmnop')));
  });
}
