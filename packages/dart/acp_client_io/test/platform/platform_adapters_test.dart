// Тесты `dart:io`-адаптеров портов клиента (tasks 5.3; spec acp-client-kit
// «IO-адаптеры клиента»): настоящие файлы и процессы на Dart VM.

import 'dart:io';

import 'package:acp_client_core/acp_client_core.dart';
import 'package:acp_client_io/acp_client_io.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('acp_client_io_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('IoWorkingDirectoryProvider', () {
    test('reports the process working directory', () {
      expect(
        const IoWorkingDirectoryProvider().currentPath,
        Directory.current.path,
      );
    });
  });

  group('IoTextFileIo', () {
    const io = IoTextFileIo();

    test('writes a file in a new directory and reads it back', () async {
      final path = '${tmp.path}/nested/dir/notes.txt';

      await io.writeText(path: path, content: 'one\ntwo\nthree\nfour');

      expect(await io.readText(path: path), 'one\ntwo\nthree\nfour');
    });

    test('reads a line range: line is 1-based, limit counts lines', () async {
      final path = '${tmp.path}/lines.txt';
      await io.writeText(path: path, content: 'one\ntwo\nthree\nfour');

      expect(await io.readText(path: path, line: 2, limit: 2), 'two\nthree');
      expect(await io.readText(path: path, line: 4), 'four');
    });

    test('a missing file is FsNotFoundFailure', () async {
      await expectLater(
        io.readText(path: '${tmp.path}/missing.txt'),
        throwsA(isA<FsNotFoundFailure>()),
      );
    });

    test('an unreadable file is FsIoFailure', () async {
      final path = '${tmp.path}/secret.txt';
      File(path).writeAsStringSync('hidden');
      Process.runSync('chmod', ['000', path]);
      addTearDown(() => Process.runSync('chmod', ['600', path]));

      await expectLater(io.readText(path: path), throwsA(isA<FsIoFailure>()));
    });
  });

  group('IoTerminalProcessRunner', () {
    const runner = IoTerminalProcessRunner();

    test('runs a process and keeps its output and exit code', () async {
      final handle = await runner.start(
        command: '/bin/sh',
        args: ['-c', 'echo hi; echo err >&2; exit 3'],
        env: const {},
        cwd: tmp.path,
      );

      final exited = await handle.waitForExit() as TerminalProcessExited;

      expect(exited.exitCode, 3);
      expect(handle.output, contains('hi'));
      expect(handle.output, contains('err'));
      expect(handle.truncated, isFalse);
    });

    test('keeps only the tail of the output beyond the byte limit', () async {
      final handle = await runner.start(
        command: '/bin/sh',
        args: ['-c', 'printf 0123456789'],
        env: const {},
        cwd: tmp.path,
        outputByteLimit: 4,
      );

      await handle.waitForExit();

      expect(handle.output, '6789');
      expect(handle.truncated, isTrue);
    });

    test('kill() ends a running process with SIGTERM', () async {
      final handle = await runner.start(
        command: '/bin/sh',
        args: ['-c', 'sleep 30'],
        env: const {},
        cwd: tmp.path,
      );

      await handle.kill();
      final exited = await handle.waitForExit() as TerminalProcessExited;

      expect(exited.signal, 'SIGTERM');
    });

    test('a missing command is TerminalStartFailure', () async {
      await expectLater(
        runner.start(
          command: '${tmp.path}/no-such-binary',
          args: const [],
          env: const {},
          cwd: tmp.path,
        ),
        throwsA(isA<TerminalStartFailure>()),
      );
    });
  });
}
