import 'dart:collection';
import 'dart:io';

import 'package:codelab_agent/codelab_agent.dart';
import 'package:test/test.dart';

/// Окружение, которое падает при первом чтении: имитация неожиданного
/// исключения внутри `config check` (agent-binary «Подкоманда config
/// бинаря»; design.md change `add-agent-configuration`, D13).
final class _ThrowingEnvironment extends MapBase<String, String> {
  @override
  String? operator [](Object? key) => throw StateError('boom');

  @override
  void operator []=(String key, String value) {}

  @override
  void clear() {}

  @override
  Iterable<String> get keys => throw StateError('boom');

  @override
  String? remove(Object? key) => null;
}

/// В процессе теста: путь `config` в `runCodelabAgent` не должен пропускать
/// неожиданное исключение (код Dart для необработанного — `255` и трасса), как
/// и путь `serve` (`serve.failed`, код `1`).
void main() {
  test('an unexpected exception in config check: failureExit, no stack trace '
      'on stdout', () async {
    final out = <String>[];
    final code = await IOOverrides.runZoned(
      () => runCodelabAgent([
        'config',
        'check',
      ], environment: _ThrowingEnvironment()),
      stdout: () => _CapturingStdout(out),
    );

    expect(code, 1);
    expect(out.join(), isEmpty);
  });
}

final class _CapturingStdout implements Stdout {
  _CapturingStdout(this.sink);

  final List<String> sink;

  @override
  void write(Object? object) => sink.add('$object');

  @override
  void writeln([Object? object = '']) => sink.add('$object\n');

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
