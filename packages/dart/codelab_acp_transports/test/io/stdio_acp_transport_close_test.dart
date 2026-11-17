@TestOn('!windows')
library;

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_transports/codelab_acp_transports.dart';
import 'package:codelab_acp_transports/io.dart';
import 'package:test/test.dart';

/// Закрытие stdio-транспорта ограничено по времени (agent-transports
/// «Stdio transport», сценарии «Агент выходит по закрытию stdin» и «Агент
/// игнорирует EOF и SIGTERM»; design.md change
/// `add-client-process-shutdown-on-exit`, D3).
///
/// Почему реальный процесс: эскалацию `SIGTERM` -> `SIGKILL` нельзя проверить
/// фейком. Тест POSIX-only: опирается на `sh`, `trap` и `kill -0`.
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stdio_close_test_');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  /// Ждёт появления файла-маркера: процесс записал его после установки `trap`.
  Future<String> readWhenAppears(File file) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (file.existsSync()) {
        final text = file.readAsStringSync().trim();
        if (text.isNotEmpty) return text;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('Маркер ${file.path} не появился');
  }

  bool isAlive(String pid) =>
      Process.runSync('kill', ['-0', pid]).exitCode == 0;

  test(
    'агент, игнорирующий EOF и SIGTERM, убивается SIGKILL, close не виснет',
    () async {
      final pidFile = File('${tmp.path}/pid');
      final transport = StdioAcpTransport(
        StdioAcpTransportConfig(
          command: 'sh',
          args: [
            '-c',
            "trap '' TERM; echo \$\$ > '${pidFile.path}'; "
                'while :; do sleep 1; done',
          ],
        ),
      );
      final events = <AcpTransportEvent>[];
      final subscription = transport.events.listen(events.add);
      addTearDown(subscription.cancel);

      await transport.start();
      final pid = await readWhenAppears(pidFile);
      expect(isAlive(pid), isTrue);

      final stopwatch = Stopwatch()..start();
      await transport
          .close(timeout: const Duration(milliseconds: 200))
          .timeout(const Duration(seconds: 3));
      stopwatch.stop();

      // 200 мс на EOF + 2 с после SIGTERM + накладные расходы.
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
      expect(transport.state, AcpTransportState.closed);
      expect(
        events.whereType<AcpTransportFailure>(),
        isEmpty,
        reason: 'закрытие не сбой транспорта',
      );

      // Процесс завершён к моменту возврата close (SIGKILL доставляется
      // ядром асинхронно, поэтому короткий опрос, а не одна проверка).
      final deadline = DateTime.now().add(const Duration(seconds: 1));
      while (isAlive(pid) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(isAlive(pid), isFalse);
    },
  );

  test(
    'агент, выходящий по EOF, не получает сигналов; повторный close - no-op',
    () async {
      final signalFile = File('${tmp.path}/got_term');
      final readyFile = File('${tmp.path}/ready');
      final transport = StdioAcpTransport(
        StdioAcpTransportConfig(
          command: 'sh',
          args: [
            '-c',
            "trap 'touch \"${signalFile.path}\"' TERM; "
                "echo ok > '${readyFile.path}'; cat > /dev/null",
          ],
        ),
      );
      final events = <AcpTransportEvent>[];
      final subscription = transport.events.listen(events.add);
      addTearDown(subscription.cancel);

      await transport.start();
      await readWhenAppears(readyFile);

      await transport.close(timeout: const Duration(seconds: 2));
      await transport.close(); // повторный вызов ничего не делает

      expect(signalFile.existsSync(), isFalse);
      expect(transport.state, AcpTransportState.closed);
      expect(events.whereType<AcpTransportFailure>(), isEmpty);
    },
  );

  // --- Исправления по ревью, D13 (задача 5.1) ---

  /// Агент, игнорирующий EOF и SIGTERM; `ready` в stderr сообщает, что `trap`
  /// уже установлен (иначе SIGTERM мог бы прийти до него).
  StdioAcpTransport ignoringAgent() => StdioAcpTransport(
    StdioAcpTransportConfig(
      command: 'sh',
      args: ['-c', "trap '' TERM; echo ready >&2; while :; do sleep 1; done"],
    ),
  );

  /// Запускает транспорт и ждёт `ready` в событиях stderr с дедлайном.
  Future<void> startAndWaitReady(StdioAcpTransport transport) async {
    final ready = Completer<void>();
    final subscription = transport.events.listen((event) {
      if (event is AcpTransportDiagnostic &&
          event.message == 'ready' &&
          !ready.isCompleted) {
        ready.complete();
      }
    });
    addTearDown(subscription.cancel);
    await transport.start();
    await ready.future.timeout(const Duration(seconds: 5));
  }

  test('повторный close с меньшим пределом сокращает ожидание EOF и ждёт '
      'идущее закрытие', () async {
    final transport = ignoringAgent();
    await startAndWaitReady(transport);

    final stopwatch = Stopwatch()..start();
    final completions = <String>[];
    final first = transport
        .close(timeout: const Duration(seconds: 5))
        .then((_) => completions.add('first'));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final second = transport
        .close(timeout: const Duration(milliseconds: 200))
        .then((_) => completions.add('second'));

    await Future.wait([first, second]).timeout(const Duration(seconds: 6));
    stopwatch.stop();

    // 300 мс до SIGTERM + 2 с до SIGKILL, а не 5 + 2 с.
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    // Второй вызов не возвращается раньше первого (мемоизация).
    expect(completions.first, 'first');
    expect(transport.state, AcpTransportState.closed);

    // Повторный вызов после завершения возвращается сразу.
    final again = Stopwatch()..start();
    await transport.close(timeout: const Duration(seconds: 5));
    expect(again.elapsed, lessThan(const Duration(milliseconds: 200)));
  });

  test('более поздний предел не продлевает идущее закрытие', () async {
    final transport = ignoringAgent();
    await startAndWaitReady(transport);

    final stopwatch = Stopwatch()..start();
    final first = transport.close(timeout: const Duration(milliseconds: 200));
    final second = transport.close(timeout: const Duration(seconds: 10));
    await Future.wait([first, second]).timeout(const Duration(seconds: 4));
    stopwatch.stop();

    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 3)));
    expect(transport.state, AcpTransportState.closed);
  });

  test('close во время start дожидается запуска, процесс завершён, '
      'start бросает closed', () async {
    final pidFile = File('${tmp.path}/pid');
    // Страховка от сирот, если реализация не закроет запущенный процесс.
    addTearDown(() {
      if (pidFile.existsSync()) {
        Process.runSync('kill', ['-9', pidFile.readAsStringSync().trim()]);
      }
    });
    final transport = StdioAcpTransport(
      StdioAcpTransportConfig(
        command: 'sh',
        args: [
          '-c',
          "echo \$\$ > '${pidFile.path}'; trap '' TERM; "
              'while :; do sleep 1; done',
        ],
      ),
    );
    final events = <AcpTransportEvent>[];
    final subscription = transport.events.listen(events.add);
    addTearDown(subscription.cancel);

    // start без await: Process.start в полёте, когда приходит close.
    final started = transport.start();
    final startOutcome = expectLater(
      started,
      throwsA(
        isA<AcpTransportException>().having(
          (e) => e.code,
          'code',
          AcpTransportErrorCode.closed,
        ),
      ),
    );
    await transport
        .close(timeout: const Duration(milliseconds: 200))
        .timeout(const Duration(seconds: 5));
    await startOutcome;

    final pid = await readWhenAppears(pidFile);
    final deadline = DateTime.now().add(const Duration(seconds: 1));
    while (isAlive(pid) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(isAlive(pid), isFalse);
    expect(
      events.whereType<AcpTransportStateChanged>().map((e) => e.state),
      isNot(contains(AcpTransportState.connected)),
    );
  });
}
