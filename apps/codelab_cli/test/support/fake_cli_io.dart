import 'dart:async';
import 'dart:convert';

import 'package:codelab_cli/codelab_cli.dart';

/// Потоки процесса в памяти для модульных тестов `runCodelab`.
///
/// Почему: модульные тесты проверяют stdout, stderr и коды выхода без
/// процесса (design.md change `add-codelab-cli`, D2); процессные тесты — в
/// `test/e2e/`.
///
/// Как использовать: `FakeCliIo(stdin: 'hello')`, затем
/// `runCodelab(args, environment: env, io: io)` и [stdoutText],
/// [stderrText].
final class FakeCliIo implements CliIo {
  FakeCliIo({String? stdin, this.stdinIsTerminal = false})
    : _stdin = stdin == null
          ? const Stream<List<int>>.empty()
          : Stream.value(utf8.encode(stdin));

  final Stream<List<int>> _stdin;
  final _stdout = StringBuffer();
  final _stderr = StringBuffer();

  @override
  final bool stdinIsTerminal;

  @override
  Stream<List<int>> get stdin => _stdin;

  @override
  StringSink get stdout => _stdout;

  @override
  StringSink get stderr => _stderr;

  @override
  Future<void> flush() async {}

  String get stdoutText => _stdout.toString();

  String get stderrText => _stderr.toString();
}
