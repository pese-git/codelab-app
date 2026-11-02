// `CliEmbeddedLogger` (spec codelab-cli «Встроенный агент в CLI», «Логи
// встроенного агента», «Отладка секретов»; design.md change
// `add-embedded-agent-mode`, D5, D6; AGENTS.md §16): лог встроенного агента
// не раскрывает секреты и не засоряет stdout/терминал.

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_embedded/codelab_embedded.dart' as embedded;
import 'package:test/test.dart';

void main() {
  late StringBuffer sink;

  setUp(() => sink = StringBuffer());

  test('a sensitive key is masked, the value never reaches the sink', () {
    CliEmbeddedLogger(sink).log(
      embedded.LogLevel.info,
      'llm.request',
      fields: {
        'api_key': 'sk-very-secret-value',
        'token': 'tok-very-secret-value',
        'model': 'p/m',
      },
    );

    expect(sink.toString(), isNot(contains('very-secret-value')));
    expect(sink.toString(), contains('model=p/m'));
  });

  test('a Bearer credential inside a value is masked', () {
    CliEmbeddedLogger(sink).log(
      embedded.LogLevel.warning,
      'llm.retry',
      fields: {'header': 'Authorization: Bearer abcdef0123456789'},
    );

    expect(sink.toString(), isNot(contains('abcdef0123456789')));
  });

  test('an error is logged by its type only, never by its text', () {
    CliEmbeddedLogger(sink).log(
      embedded.LogLevel.error,
      'embedded.agent.failed',
      error: StateError('provider said: sk-leaked-in-error-text'),
    );

    expect(sink.toString(), contains('error_class=StateError'));
    expect(sink.toString(), isNot(contains('sk-leaked-in-error-text')));
  });

  test('terminal control characters of the values are removed', () {
    CliEmbeddedLogger(sink).log(
      embedded.LogLevel.info,
      'tool.end',
      fields: {'title': 'evil\x1b[31m\x07text'},
    );

    expect(sink.toString(), isNot(contains('\x1b')));
    expect(sink.toString(), isNot(contains('\x07')));
  });

  test('the silent logger writes nothing and reports nothing enabled', () {
    const logger = CliEmbeddedLogger.silent();

    logger.log(embedded.LogLevel.error, 'embedded.agent.failed');

    expect(logger.isEnabled(embedded.LogLevel.error), isFalse);
    expect(sink.toString(), isEmpty);
  });

  test('debug-only mode (--debug-secrets without --verbose) writes the '
      'secret lookups and nothing else', () {
    final logger = CliEmbeddedLogger.secretLookupsOnly(sink);

    logger
      ..log(embedded.LogLevel.info, 'host.plan', fields: {'tools': 'read'})
      ..log(embedded.LogLevel.error, 'embedded.agent.failed')
      ..log(
        embedded.LogLevel.info,
        'secrets.lookup',
        fields: {
          'name': 'codelab/p',
          'purpose': 'api_key',
          'source': 'env',
          'found': true,
        },
      );

    final text = sink.toString();
    expect(text, contains('secrets.lookup'));
    expect(text, contains('name=codelab/p'));
    expect(text, contains('source=env'));
    expect(text, contains('found=true'));
    expect(text, isNot(contains('host.plan')));
    expect(text, isNot(contains('embedded.agent.failed')));
  });
}
