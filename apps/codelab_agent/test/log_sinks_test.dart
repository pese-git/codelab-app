import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent/codelab_agent.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Логи бинаря (задача 4.6; agent-binary «Логи бинаря»; документ ядра
/// §12.3.1; design.md change `add-codelab-agent-binary`, D5).
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('codelab_agent_log_');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  final at = DateTime.utc(2026, 10, 25, 12);

  test('stderr sink: one line per record', () async {
    final lines = <String>[];
    final controller = StreamController<List<int>>();
    final done = controller.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(lines.add);
    final sink = StderrLogSink(IOSink(controller.sink));

    sink.write(
      LogRecord(
        time: at,
        level: LogLevel.info,
        event: 'turn.end',
        fields: {'session_id': 's1'},
      ),
    );
    sink.write(LogRecord(time: at, level: LogLevel.warning, event: 'x.y'));
    await sink.close();
    await done;

    expect(lines, hasLength(2));
    expect(lines.first, allOf(contains('info'), contains('turn.end')));
    expect(lines.first, contains('session_id'));
  });

  test('file sink: JSON Lines with ts, level, event first', () async {
    final path = '${temp.path}/logs/agent.log';
    final sink = FileLogSink.open(path);
    sink.write(
      LogRecord(
        time: at,
        level: LogLevel.error,
        event: 'llm.request.end',
        fields: {'model': 'gpt-5'},
        error: 'boom',
      ),
    );
    await sink.close();

    final line = File(path).readAsLinesSync().single;
    final record = jsonDecode(line) as Map<String, Object?>;
    expect(record.keys.take(3), ['ts', 'level', 'event']);
    expect(record['ts'], '2026-10-25T12:00:00.000Z');
    expect(record['level'], 'error');
    expect(record['model'], 'gpt-5');
    expect(record['error'], 'boom');
    expect(record.containsKey('stack'), isFalse);
  });

  test('file sink appends and does not truncate', () async {
    final path = '${temp.path}/agent.log';
    File(path).writeAsStringSync('{"old":true}\n');
    final sink = FileLogSink.open(path)
      ..write(LogRecord(time: at, level: LogLevel.info, event: 'a.b'));
    await sink.close();

    expect(File(path).readAsLinesSync(), hasLength(2));
  });

  test('file sink: directory 0700, file 0600', () async {
    final path = '${temp.path}/new/dir/agent.log';
    final sink = FileLogSink.open(path);
    await sink.close();

    expect(File(path).statSync().modeString(), 'rw-------');
    expect(
      Directory('${temp.path}/new/dir').statSync().modeString(),
      'rwx------',
    );
  }, skip: Platform.isWindows ? 'POSIX permissions' : null);

  test('a path to stdout is a usage error', () {
    for (final path in ['-', '/dev/stdout', '/dev/fd/1', '/proc/self/fd/1']) {
      expect(
        () => FileLogSink.open(path),
        throwsA(
          isA<UsageError>().having(
            (e) => e.message,
            'message',
            '--log-file cannot point to stdout: stdout carries the ACP protocol',
          ),
        ),
        reason: path,
      );
    }
  });

  test('a path that cannot be opened is a usage error', () {
    File('${temp.path}/file').writeAsStringSync('');
    expect(
      () => FileLogSink.open('${temp.path}/file/agent.log'),
      throwsA(
        isA<UsageError>().having(
          (e) => e.message,
          'message',
          startsWith('cannot open log file ${temp.path}/file/agent.log: '),
        ),
      ),
    );
  });

  test('host logger: level filter and every sink gets the record', () {
    final a = _MemorySink();
    final b = _MemorySink();
    final logger = HostLogger(level: LogLevel.info, sinks: [a, b]);

    logger.log(LogLevel.debug, 'hidden.event');
    logger.log(LogLevel.info, 'shown.event', fields: {'n': 1});

    expect(logger.isEnabled(LogLevel.debug), isFalse);
    expect(a.records.map((r) => r.event), ['shown.event']);
    expect(b.records.map((r) => r.event), ['shown.event']);
  });

  test('a failing file sink is disabled after one note', () {
    final primary = _MemorySink();
    final failing = _MemorySink(failing: true);
    final logger = HostLogger(level: LogLevel.info, sinks: [primary, failing]);

    logger.log(LogLevel.info, 'first');
    logger.log(LogLevel.info, 'second');

    expect(primary.records.map((r) => r.event), [
      'first',
      'log.file.write_failed',
      'second',
    ]);
  });
}

final class _MemorySink implements LogSink {
  _MemorySink({this.failing = false});

  final bool failing;
  final records = <LogRecord>[];

  @override
  void write(LogRecord record) {
    if (failing) {
      throw const FileSystemException('disk full');
    }
    records.add(record);
  }

  @override
  Future<void> close() async {}
}
