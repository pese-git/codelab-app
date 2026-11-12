// Обработчик выхода из app: `closeAll()` терминала до завершения процесса
// (`add-integrated-terminal`, задача 2.14; спецификация `integrated-terminal`
// «Жизненный цикл процессов терминала», сценарий «Выход из приложения»;
// design.md D4 «Выход из app», D15 п. 9).
//
// Время — fake: `testWidgets` и `tester.pump(Duration)`, как в
// `terminal_tabs_cubit_test.dart`. Настоящего PTY нет: процессы — двойники.
import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/app/app_exit_handler.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_client_workspace.dart';
import '../support/fake_external_link_opener.dart';
import '../support/fake_user_shell_launcher.dart';
import '../support/recording_logger.dart';

const _p1 = ConnectionProfile.stdio(id: 'p1', label: 'One', command: 'a');
final _s1 = SessionId('s1');

/// Cubit, у которого закрытие падает: проверка ветки сбоя обработчика.
final class _FailingCloseCubit extends TerminalTabsCubit {
  _FailingCloseCubit({
    required super.workspace,
    required super.launcher,
    required super.directoryExists,
    required super.logger,
    required super.externalLinkOpener,
  });

  @override
  Future<void> closeAll() => Future<void>.error(
    StateError('secret /home/user/path'),
    StackTrace.current,
  );
}

/// Журнал, который бросает на любой записи: выход не должен от этого зависеть.
final class _ThrowingLogger implements Logger {
  @override
  Object? noSuchMethod(Invocation invocation) => throw StateError('log');
}

void main() {
  late FakeClientWorkspace workspace;
  late FakeUserShellLauncher launcher;
  late RecordingLogger logger;
  late TerminalTabsCubit cubit;
  late AppExitHandler handler;
  // Двойник сброса журнала: тест решает, когда он завершится.
  late Future<void> Function() flushLogs;
  var flushCalls = 0;

  setUp(() {
    workspace = FakeClientWorkspace()..openSession(_p1, _s1);
    launcher = FakeUserShellLauncher();
    logger = RecordingLogger();
    cubit = TerminalTabsCubit(
      workspace: workspace,
      launcher: launcher,
      directoryExists: (_) async => true,
      logger: logger,
      externalLinkOpener: FakeExternalLinkOpener(),
    );
    flushCalls = 0;
    flushLogs = () async => flushCalls++;
    handler = AppExitHandler(
      terminalTabs: cubit,
      logger: logger,
      flushLogs: () => flushLogs(),
    );
  });

  tearDown(() async {
    await cubit.close();
    await workspace.close();
  });

  Future<FakeUserShell> openTab() async {
    await cubit.newTab();
    return launcher.shells.last;
  }

  testWidgets('зависший shell: kill и exit не позже чем через 3 с', (
    tester,
  ) async {
    final shell = await openTab();

    AppExitResponse? response;
    final exiting = handler.onExitRequested().then((r) => response = r);
    await tester.pump(const Duration(seconds: 2, milliseconds: 999));
    expect(response, isNull);
    expect(shell.hangUps, 1);
    expect(shell.kills, 0);

    await tester.pump(const Duration(milliseconds: 1));
    await exiting;

    expect(response, AppExitResponse.exit);
    expect(shell.kills, 1);
    expect(
      logger.entries.singleWhere((e) => e['event'] == 'terminal.close_all'),
      containsPair('forced', true),
    );
  });

  testWidgets('все вышли по hangUp: exit без ожидания 3 с', (tester) async {
    launcher.shellsExitOnHangUp = true;
    final a = await openTab();
    final b = await openTab();

    final response = await handler.onExitRequested();

    expect(response, AppExitResponse.exit);
    expect([a.hangUps, b.hangUps], [1, 1]);
    expect([a.kills, b.kills], [0, 0]);
  });

  testWidgets('без вкладок: exit сразу, start не вызывается', (tester) async {
    final response = await handler.onExitRequested();

    expect(response, AppExitResponse.exit);
    expect(launcher.starts, isEmpty);
  });

  testWidgets('закрытие scope после обработчика: без start, без сигналов, '
      'без исключений', (tester) async {
    launcher.shellsExitOnHangUp = true;
    final shell = await openTab();
    await handler.onExitRequested();

    // `CodeLabRootLifecycle.dispose` зовёт `closeAll()` и закрывает Cubit.
    await cubit.closeAll();
    await cubit.close();
    await expectLater(cubit.newTab(), completes);

    expect(launcher.starts, hasLength(1));
    expect(shell.hangUps, 1);
    expect(shell.kills, 0);
  });

  testWidgets('повторный запрос во время closeAll(): второго прохода нет', (
    tester,
  ) async {
    final shell = await openTab();

    final first = handler.onExitRequested();
    final second = handler.onExitRequested();
    await tester.pump(const Duration(seconds: 3));

    expect(await first, AppExitResponse.exit);
    expect(await second, AppExitResponse.exit);
    expect(shell.hangUps, 1);
    expect(shell.kills, 1);
    expect(
      logger.entries.where((e) => e['event'] == 'terminal.close_all'),
      hasLength(1),
    );
  });

  testWidgets('ошибка closeAll(): exit и app.exit_close_failed только с '
      'error_type, без текста ошибки', (tester) async {
    final failing = _FailingCloseCubit(
      workspace: workspace,
      launcher: launcher,
      directoryExists: (_) async => true,
      logger: logger,
      externalLinkOpener: FakeExternalLinkOpener(),
    );
    addTearDown(failing.close);

    final response = await AppExitHandler(
      terminalTabs: failing,
      logger: logger,
      flushLogs: () async {},
    ).onExitRequested();

    expect(response, AppExitResponse.exit);
    final event = logger.entries.singleWhere(
      (e) => e['event'] == 'app.exit_close_failed',
    );
    expect(event['error_type'], 'StateError');
    expect(event.toString(), isNot(contains('secret')));
    expect(event.keys.toSet(), {'event', 'level', 'error_type'});
  });

  testWidgets('app.exit_requested пишется до closeAll()', (tester) async {
    launcher.shellsExitOnHangUp = true;
    await openTab();

    await handler.onExitRequested();

    final events = [for (final e in logger.entries) e['event']];
    expect(events, contains('app.exit_requested'));
    expect(
      events.indexOf('app.exit_requested'),
      lessThan(events.indexOf('terminal.close_all')),
    );
  });

  testWidgets('зависший shell: terminal.tab_closed forced до возврата exit', (
    tester,
  ) async {
    launcher.deferStarts = true;
    final opening = cubit.newTab();
    await tester.pump();
    final shell = launcher.pending.single.complete(
      FakeUserShell(exitsOnKill: false),
    );
    await opening;

    final exiting = handler.onExitRequested();
    await tester.pump(const Duration(seconds: 3));
    await exiting;

    expect(shell.kills, 1);
    expect(
      logger.entries.singleWhere((e) => e['event'] == 'terminal.tab_closed'),
      containsPair('forced', true),
    );
  });

  testWidgets('сбой hangUp()/kill() одной вкладки не оставляет другие живыми', (
    tester,
  ) async {
    launcher.deferStarts = true;
    final shells = <FakeUserShell>[];
    for (var i = 0; i < 3; i++) {
      final opening = cubit.newTab();
      await tester.pump();
      shells.add(launcher.pending.last.complete());
      await opening;
    }
    shells[0].hangUpError = StateError('hangup');
    shells[1].killError = StateError('kill');

    final exiting = handler.onExitRequested();
    await tester.pump(const Duration(seconds: 3));
    expect(await exiting, AppExitResponse.exit);

    expect([for (final s in shells) s.hangUps], [1, 1, 1]);
    expect([for (final s in shells) s.kills], [1, 1, 1]);
    // `kill` второй вкладки бросил: процесс мог остаться жив, поэтому
    // `tab_closed` пишется только для двух других, а для неё — `signal_failed`.
    final closed = [
      for (final e in logger.entries)
        if (e['event'] == 'terminal.tab_closed') e['tab_id'],
    ];
    final failed = [
      for (final e in logger.entries)
        if (e['event'] == 'terminal.signal_failed') e['signal'],
    ];
    expect(closed, hasLength(2));
    expect(failed, unorderedEquals(['hangup', 'kill']));
  });

  testWidgets('сбой журнала при app.exit_requested не мешает выходу', (
    tester,
  ) async {
    final throwing = AppExitHandler(
      terminalTabs: cubit,
      logger: _ThrowingLogger(),
      flushLogs: () => flushLogs(),
    );

    expect(await throwing.onExitRequested(), AppExitResponse.exit);
  });

  testWidgets('обработчик ждёт сброс журнала', (tester) async {
    final flush = Completer<void>();
    flushLogs = () {
      flushCalls++;
      return flush.future;
    };

    AppExitResponse? response;
    final exiting = handler.onExitRequested().then((r) => response = r);
    await tester.pump(const Duration(milliseconds: 100));
    expect(flushCalls, 1);
    expect(response, isNull);

    flush.complete();
    await exiting;
    expect(response, AppExitResponse.exit);
  });

  testWidgets('зависший сброс журнала не держит выход дольше 500 мс', (
    tester,
  ) async {
    flushLogs = () {
      flushCalls++;
      return Completer<void>().future;
    };

    AppExitResponse? response;
    final exiting = handler.onExitRequested().then((r) => response = r);
    await tester.pump(const Duration(milliseconds: 499));
    expect(response, isNull);
    await tester.pump(const Duration(milliseconds: 1));
    await exiting;

    expect(response, AppExitResponse.exit);
  });

  testWidgets('сбой сброса журнала не мешает выходу', (tester) async {
    flushLogs = () => Future<void>.error(StateError('disk'));

    expect(await handler.onExitRequested(), AppExitResponse.exit);
  });
}
