import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

/// `BoundLogger` (design.md change `add-agent-mcp-client`, D13): код, который
/// не знает сессии (транспорт MCP), пишет записи с её `session_id`.
void main() {
  test('bound fields are added to every record; the call wins on a clash', () {
    final sink = RecordingLogger();
    final logger = BoundLogger(sink, {'session_id': 's1', 'server': 'x'});

    logger.log(LogLevel.info, 'e', fields: {'server': 'y', 'k': 1});

    expect(sink.records.single.fields, {
      'session_id': 's1',
      'server': 'y',
      'k': 1,
    });
  });

  test('level, error and stack pass through; isEnabled is the sink one', () {
    final sink = RecordingLogger(minLevel: LogLevel.info);
    final logger = BoundLogger(sink, const {'a': 1});
    final stack = StackTrace.current;

    logger.log(LogLevel.debug, 'dropped');
    logger.log(LogLevel.warning, 'kept', error: 'boom', stack: stack);

    expect(logger.isEnabled(LogLevel.debug), isFalse);
    expect(logger.isEnabled(LogLevel.info), isTrue);
    final record = sink.records.single;
    expect(record.level, LogLevel.warning);
    expect(record.error, 'boom');
    expect(record.stack, isNotNull);
  });
}
