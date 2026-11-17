import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codelab_agent_io/codelab_agent_io.dart';
import 'package:test/test.dart';

/// `StdinSecretInput` над фейковым `Stdin` (design.md change
/// `add-agent-secret-store`, D8): скрытый ввод побайтово, без канонического
/// режима. Настоящий терминал в тесте недоступен, поэтому фейк записывает
/// каждое изменение `echoMode`/`lineMode`.
void main() {
  const maxValueBytes = 64 * 1024; // предел значения (D14)
  const prompt = 'Secret value for codelab/x: ';

  late _FakeStdin fake;
  late _CapturedSink sink;

  /// Ввод над фейком: окно «тишины» нулевое, кроме тестов, где оно нужно.
  StdinSecretInput inputOver({
    Duration drainWindow = Duration.zero,
    void Function(int)? onExit,
  }) => StdinSecretInput(
    input: fake,
    prompts: sink.sink,
    drainWindow: drainWindow,
    exitProcess: onExit,
  );

  setUp(() {
    fake = _FakeStdin();
    sink = _CapturedSink();
  });

  tearDown(() => fake.close());

  List<int> bytes(String text) => utf8.encode(text);

  group('readHidden', () {
    test(
      'Enter завершает ввод; режимы выключены и затем восстановлены',
      () async {
        final future = inputOver().readHidden(prompt);
        fake.add(bytes('sk-test-abc\n'));

        expect(await future, 'sk-test-abc');
        expect(fake.modeChanges, [
          'echoMode=false',
          'lineMode=false',
          'lineMode=true',
          'echoMode=true',
        ]);
        expect(sink.text, startsWith(prompt));
        expect(sink.text, isNot(contains('sk-test')));
      },
    );

    test('режимы восстанавливаются сначала как были: исходный lineMode=false '
        'остаётся false', () async {
      fake.lineModeValue = false;
      fake.echoModeValue = false;
      final future = inputOver().readHidden(prompt);
      fake.add(bytes('v\n'));
      await future;

      expect(fake.echoModeValue, isFalse);
      expect(fake.lineModeValue, isFalse);
    });

    test(
      '\\r завершает ввод, следующий за ним \\n входит в терминатор',
      () async {
        final future = inputOver().readHidden(prompt);
        fake.add(bytes('abc\r\n'));

        expect(await future, 'abc');
      },
    );

    test(
      'Backspace (0x7f и 0x08) убирает последний символ по кодовой точке',
      () async {
        final future = inputOver().readHidden(prompt);
        fake.add([...bytes('ab'), ...bytes('é'), 0x7f, 0x08, ...bytes('cd\n')]);

        expect(await future, 'acd');
      },
    );

    test('Backspace на пустом вводе ничего не ломает', () async {
      final future = inputOver().readHidden(prompt);
      fake.add([0x7f, ...bytes('x\n')]);

      expect(await future, 'x');
    });

    test('Ctrl+D на пустом вводе: null (EOF), режимы восстановлены', () async {
      final future = inputOver().readHidden(prompt);
      fake.add([0x04]);

      expect(await future, isNull);
      expect(fake.echoModeValue, isTrue);
      expect(fake.lineModeValue, isTrue);
    });

    test('Ctrl+D после символов игнорируется', () async {
      final future = inputOver().readHidden(prompt);
      fake.add([...bytes('ab'), 0x04, ...bytes('c\n')]);

      expect(await future, 'abc');
    });

    test('конец потока без символов: null; режимы восстановлены', () async {
      final future = inputOver().readHidden(prompt);
      await fake.close();

      expect(await future, isNull);
      expect(fake.echoModeValue, isTrue);
      expect(fake.lineModeValue, isTrue);
    });

    test('пустая строка (Enter сразу): пустое значение, не EOF', () async {
      final future = inputOver().readHidden(prompt);
      fake.add(bytes('\n'));

      expect(await future, '');
    });

    test('недопустимый UTF-8: FormatException, режимы восстановлены', () async {
      final future = inputOver().readHidden(prompt);
      fake.add([0xff, 0xfe, 0x0a]);

      await expectLater(future, throwsFormatException);
      expect(fake.echoModeValue, isTrue);
      expect(fake.lineModeValue, isTrue);
    });

    test('байты после перевода строки в том же куске: многострочный ввод, '
        'значение не возвращается', () async {
      final future = inputOver().readHidden(prompt);
      fake.add(bytes('first\nsecond\n'));

      await expectLater(future, throwsA(isA<MultilineSecretException>()));
      expect(fake.echoModeValue, isTrue);
      expect(fake.lineModeValue, isTrue);
      expect(sink.text, isNot(contains('first')));
      expect(sink.text, isNot(contains('second')));
    });

    test('байты в окне после Enter (отдельным куском): тоже многострочный '
        'ввод; поток дренируется до восстановления режимов', () async {
      final future = inputOver(
        drainWindow: const Duration(seconds: 30),
      ).readHidden(prompt);
      fake.add(bytes('first\n'));
      await pumpEventQueue();
      expect(fake.modeChanges.last, 'lineMode=false', reason: 'окно открыто');
      fake.add(bytes('second\n'));
      await pumpEventQueue();
      fake.add(bytes('third\n'));
      await fake.close();

      await expectLater(future, throwsA(isA<MultilineSecretException>()));
      expect(fake.modeChanges.last, 'echoMode=true');
    });

    test('один терминатор без продолжения: не многострочный', () async {
      final future = inputOver().readHidden(prompt);
      fake.add(bytes('only\n'));

      expect(await future, 'only');
    });

    test('предел чтения: бесконечный ввод не копится, результат длиннее '
        'maxValueBytes', () async {
      final future = inputOver().readHidden(prompt);
      fake.add(List.filled(maxValueBytes + 500, 0x61));

      final result = (await future)!;
      expect(result.length, greaterThan(maxValueBytes));
      expect(result.length, lessThanOrEqualTo(maxValueBytes + 4));
      expect(fake.echoModeValue, isTrue);
    });

    test('Ctrl+C (0x03): режимы восстановлены, выход с кодом 130', () async {
      final exits = <int>[];
      final future = inputOver(onExit: exits.add).readHidden(prompt);
      fake.add([...bytes('abc'), 0x03]);
      // Тестовый `exitProcess` не завершает процесс: ввод закрываем сами.
      await fake.close();
      await future;

      expect(exits, [130]);
      expect(fake.echoModeValue, isTrue);
      expect(fake.lineModeValue, isTrue);
      expect(sink.text, isNot(contains('abc')));
    });
  });

  group('readAll', () {
    test('читает весь поток', () async {
      fake.add(bytes('line1\nline2\n'));
      final future = inputOver().readAll();
      await fake.close();

      expect(await future, 'line1\nline2\n');
    });

    test('недопустимый UTF-8: FormatException', () async {
      fake.add([0xff, 0xfe]);
      final expectation = expectLater(
        inputOver().readAll(),
        throwsFormatException,
      );
      await fake.close();

      await expectation;
    });
  });
}

/// Фейковый `Stdin`: события пишет тест, режимы журналируются.
///
/// Остальные члены `Stdin` (синхронное чтение и т. п.) ядру не нужны:
/// обращение к ним — ошибка теста, `noSuchMethod` её покажет.
final class _FakeStdin extends Stream<List<int>> implements Stdin {
  /// Как настоящий `Stdin`: отмена подписки закрывает дескриптор 0, и
  /// дальнейшая смена режимов — `StdinException` (EBADF), а не изменение.
  late final StreamController<List<int>>
  _controller = StreamController<List<int>>(
    onCancel: () {
      // Конец потока (EOF) дескриптор не закрывает — только отмена подписки.
      if (!_controller.isClosed) {
        fdClosed = true;
      }
    },
  );
  bool fdClosed = false;
  final modeChanges = <String>[];

  bool echoModeValue = true;
  bool lineModeValue = true;

  void add(List<int> chunk) => _controller.add(chunk);

  Future<void> close() async {
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _controller.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  bool get hasTerminal => true;

  @override
  bool get echoMode => echoModeValue;

  @override
  set echoMode(bool value) {
    _checkFd();
    echoModeValue = value;
    modeChanges.add('echoMode=$value');
  }

  @override
  bool get lineMode => lineModeValue;

  @override
  set lineMode(bool value) {
    _checkFd();
    lineModeValue = value;
    modeChanges.add('lineMode=$value');
  }

  void _checkFd() {
    if (fdClosed) {
      throw const StdinException('Bad file descriptor', OSError('EBADF', 9));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// `IOSink` в память: что бы ни писал ввод в stderr, тест видит текст.
final class _CapturedSink {
  _CapturedSink() {
    _controller.stream.listen((chunk) => _buffer.write(utf8.decode(chunk)));
    sink = IOSink(_controller.sink);
  }

  final _controller = StreamController<List<int>>();
  final _buffer = StringBuffer();
  late final IOSink sink;

  String get text => _buffer.toString();
}
