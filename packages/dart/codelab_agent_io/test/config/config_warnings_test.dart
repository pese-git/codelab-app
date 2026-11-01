import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// Общая запись предупреждений загрузки конфигурации (change
/// `add-embedded-agent-mode`, задача 2.8; D16 change `add-agent-configuration`):
/// `codelab-agent` и встроенный агент пишут одни и те же события.
void main() {
  test('every warning is a log record with its event, fields and message; a '
      'warning without an event is config.warning', () {
    final logger = RecordingLogger();
    final loaded = ConfigLoadResult(
      warnings: [
        ConfigIssue(
          kind: ConfigIssueKind.unknownKey,
          key: '',
          source: 'env',
          message: 'unknown environment variable CODELAB_X',
          event: 'config.env.unknown',
          fields: const {'name': 'CODELAB_X'},
        ),
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'a',
          source: 'f',
          message: 'plain',
          level: LogLevel.info,
        ),
      ],
    );

    logConfigWarnings(logger, loaded);

    final unknown = logger.eventsOf('config.env.unknown').single;
    expect(unknown.level, LogLevel.warning);
    expect(unknown.fields, {
      'name': 'CODELAB_X',
      'message': 'unknown environment variable CODELAB_X',
    });
    final plain = logger.eventsOf('config.warning').single;
    expect(plain.level, LogLevel.info);
    expect(plain.fields['message'], 'plain');
  });
}
