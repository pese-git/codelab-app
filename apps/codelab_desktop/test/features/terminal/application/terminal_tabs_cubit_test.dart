// `TerminalTabsCubit` и фабрика модели терминала (задачи 2.1–2.2 change
// `add-integrated-terminal`; спецификация `integrated-terminal`: «Вкладки
// терминала принадлежат сессии», «Панель Terminal в доке инструментов»
// (сценарий «Нет активной сессии»), «Рабочая папка вкладки терминала»,
// «Жизненный цикл процессов терминала», «Содержимое терминала не покидает
// экран»; design.md D3–D5, D9; решения Q4 (пересмотрено), Q8, Q13, Q17–Q19).
//
// Красный тест: Cubit, его состояние и фабрика `terminalModel` ещё не
// написаны (задача 2.2). Ожидаемый публичный API фиксируют эти тесты:
//
// * `TerminalOwner(String profileId, SessionId sessionId)` — ключ владельца
//   вкладок, значение с `==` (D5);
// * `TerminalTabsCubit({workspace, launcher, directoryExists, logger,
//   modelFactory = terminalModel, hangUpGrace = 2 с, closeAllGrace = 3 с,
//   writeChunkSize = 4096})`:
//   `Future<void> newTab()`, `void selectTab(id)`, `void closeTab(id)`,
//   `Future<void> closeAll()`, `void acknowledgeDisclosure()`,
//   `Terminal? terminalOf(id)`, `bool get hasPendingOutput`,
//   `int flushOutput({bool Function()? canContinue})` — записывает в модели
//   накопленный вывод частями не больше `writeChunkSize` и возвращает число
//   частей; `canContinue` вызывается перед каждой частью (бюджет кадра
//   объекта сброса, 2.7–2.8), `close()` — отписка без сигналов процессам;
// * `TerminalTabsState({owner, tabs, activeTabId, hasSession,
//   disclosureShown})`; `TerminalTab({id, title, status})`;
// * закрытая иерархия `TerminalTabStatus`: `TerminalTabStarting |
//   TerminalTabRunning | TerminalTabExited(exitCode) | TerminalTabFailed(
//   reason)`;
// * `terminalModel({required onOutput, onResize})` — единственная фабрика
//   `Terminal` с политикой буфера обмена Q13.
//
// Время — fake: `testWidgets` и `tester.pump(Duration)`; `fake_async` не
// подключается. Процесс и рабочее пространство — двойники
// (`fake_user_shell_launcher.dart`, `fake_client_workspace.dart`).
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/core/platform/user_shell_launcher.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_model.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_owner.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tab.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm2_core/xterm2_core.dart';

import '../../../support/fake_client_workspace.dart';
import '../../../support/fake_external_link_opener.dart';
import '../../../support/fake_user_shell_launcher.dart';
import '../../../support/recording_logger.dart';

const _p1 = ConnectionProfile.stdio(id: 'p1', label: 'One', command: 'a');
const _p2 = ConnectionProfile.stdio(id: 'p2', label: 'Two', command: 'b');

final _s1 = SessionId('s1');
final _s2 = SessionId('s2');

/// Модель, записывающая каждый `write` (проверка порций, D3).
final class _RecordingTerminal extends Terminal {
  _RecordingTerminal({super.onOutput, super.onResize, this.parse = true})
    : super(maxLines: 10000);

  final List<String> written = [];

  /// `false` — только запись в журнал, без разбора эмулятором (мегабайты
  /// вывода в тесте предела буфера).
  final bool parse;

  @override
  void write(String data) {
    written.add(data);
    if (parse) super.write(data);
  }
}

void main() {
  late FakeClientWorkspace workspace;
  late FakeUserShellLauncher launcher;
  late RecordingLogger logger;
  late Set<String> existingDirectories;
  late List<_RecordingTerminal> terminals;
  late TerminalTabsCubit cubit;
  late FakeExternalLinkOpener linkOpener;

  TerminalTabsCubit build({
    int writeChunkSize = 4096,
    int maxPendingOutput = terminalMaxPendingOutput,
    bool parse = true,
  }) => TerminalTabsCubit(
    workspace: workspace,
    launcher: launcher,
    directoryExists: (path) async => existingDirectories.contains(path),
    logger: logger,
    externalLinkOpener: linkOpener,
    modelFactory: ({required onOutput, onResize}) {
      final terminal = _RecordingTerminal(
        onOutput: onOutput,
        onResize: onResize == null ? null : (w, h, _, _) => onResize(w, h),
        parse: parse,
      );
      terminals.add(terminal);
      return terminal;
    },
    writeChunkSize: writeChunkSize,
    maxPendingOutput: maxPendingOutput,
  );

  setUp(() {
    workspace = FakeClientWorkspace();
    launcher = FakeUserShellLauncher();
    logger = RecordingLogger();
    linkOpener = FakeExternalLinkOpener();
    existingDirectories = {'/work/a', '/work/b'};
    terminals = [];
    cubit = build();
  });

  tearDown(() async {
    await cubit.close();
    await workspace.close();
  });

  /// Открывает вкладку в активной сессии и возвращает её процесс.
  Future<FakeUserShell> openTab() async {
    await cubit.newTab();
    return launcher.shells.last;
  }

  List<Map<String, Object?>> events(String name) => [
    for (final e in logger.entries)
      if (e['event'] == name) e,
  ];

  TerminalTabStatus status([int index = 0]) => cubit.state.tabs[index].status;

  /// Скармливает порции Cubit до опустошения буфера.
  int flushAll() {
    var total = 0;
    while (cubit.hasPendingOutput) {
      final written = cubit.flushOutput();
      if (written == 0) break;
      total += written;
    }
    return total;
  }

  group('вкладки принадлежат сессии (D5, Q4 пересмотрено)', () {
    testWidgets('владелец — профиль и сессия на момент активации; смена '
        'сессии показывает её вкладки и не трогает процессы', (tester) async {
      workspace.openSession(_p1, _s1);
      final shellA = await openTab();
      expect(cubit.state.owner, TerminalOwner('p1', _s1));
      final tabA = cubit.state.tabs.single.id;

      workspace.openSession(_p1, _s2, cwd: '/work/b');
      expect(cubit.state.owner, TerminalOwner('p1', _s2));
      expect(cubit.state.tabs, isEmpty);
      expect(cubit.state.hasSession, isTrue);

      final shellB = await openTab();
      expect(cubit.state.tabs, hasLength(1));
      expect(cubit.state.tabs.single.id, isNot(tabA));

      workspace.openSession(_p1, _s1);
      expect(cubit.state.tabs.single.id, tabA);
      expect(shellA.hangUps + shellA.kills, 0);
      expect(shellB.hangUps + shellB.kills, 0);
      expect(status(), isA<TerminalTabRunning>());
    });

    testWidgets('одинаковый sessionId у двух профилей — разные владельцы', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      await openTab();
      // Чтобы сессия `s1` профиля p2 стала активной, активная сессия должна
      // смениться: при том же `activeSessionId` владелец не пересобирается.
      workspace.openSession(_p2, _s2, cwd: '/work/b');
      workspace.openSession(_p2, _s1);

      expect(cubit.state.owner, TerminalOwner('p2', _s1));
      expect(cubit.state.tabs, isEmpty);

      workspace.openSession(_p1, _s2);
      workspace.openSession(_p1, _s1);
      expect(cubit.state.owner, TerminalOwner('p1', _s1));
      expect(cubit.state.tabs, hasLength(1));
    });

    testWidgets('тот же sessionId у другого профиля без промежуточной '
        'сессии: новый handle — новый владелец (D5)', (tester) async {
      workspace.openSession(_p1, _s1);
      await openTab();
      final tabX = cubit.state.tabs.single.id;

      // `newSession` агента Y вернул тот же id: `activeSessionId` не
      // менялся, зато `SessionHandle` другой.
      workspace.openSession(_p2, _s1);

      expect(cubit.state.owner, TerminalOwner('p2', _s1));
      expect(cubit.state.tabs, isEmpty);

      workspace.openSession(_p1, _s2, cwd: '/work/b');
      workspace.openSession(_p1, _s1);
      expect(cubit.state.owner, TerminalOwner('p1', _s1));
      expect(cubit.state.tabs.single.id, tabX);
    });

    testWidgets('reconnect с тем же handle не меняет владельца (D5)', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final tab = cubit.state.tabs.single.id;

      workspace.emit(
        workspace.current.copyWith(
          connection: const ConnectionView.disconnected(),
        ),
      );
      workspace.emit(
        workspace.current.copyWith(
          profile: _p2,
          connection: const ConnectionView.connected(),
        ),
      );

      expect(cubit.state.owner, TerminalOwner('p1', _s1));
      expect(cubit.state.tabs.single.id, tab);
      expect(shell.hangUps + shell.kills, 0);
    });

    testWidgets('вкладки переживают смену проекта, профиля и разрыв '
        'соединения; возврат сессии показывает живой процесс (Q18)', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final tab = cubit.state.tabs.single.id;

      workspace.emit(workspace.current.copyWith(projectDirectory: '/other'));
      expect(cubit.state.tabs.single.id, tab);

      workspace.emit(
        workspace.current.copyWith(
          profile: const ConnectionProfile.stdio(
            id: 'p1',
            label: 'Renamed',
            command: 'a2',
          ),
        ),
      );
      expect(cubit.state.tabs.single.id, tab);

      workspace.emit(
        workspace.current.copyWith(
          connection: const ConnectionView.disconnected(),
        ),
      );
      workspace.emit(
        workspace.current.copyWith(
          connection: const ConnectionView.connected(),
        ),
      );
      expect(cubit.state.tabs.single.id, tab);

      workspace.openSession(_p1, _s2, cwd: '/work/b');
      workspace.openSession(_p1, _s1);
      expect(cubit.state.tabs.single.id, tab);
      expect(status(), isA<TerminalTabRunning>());
      expect(shell.hangUps + shell.kills, 0);
    });

    testWidgets('после подключения к другому профилю без выбора сессии '
        'показываются вкладки прежней сессии', (tester) async {
      workspace.openSession(_p1, _s1);
      await openTab();
      final tab = cubit.state.tabs.single.id;

      // ClientWorkspace не сбрасывает activeSessionId (D5).
      workspace.emit(workspace.current.copyWith(profile: _p2));

      expect(cubit.state.owner, TerminalOwner('p1', _s1));
      expect(cubit.state.tabs.single.id, tab);
      expect(cubit.state.hasSession, isTrue);
    });
  });

  group('нет активной сессии (Q17)', () {
    testWidgets('без activeSessionId состояние «нет сессии», новая вкладка '
        'не стартует', (tester) async {
      expect(cubit.state.hasSession, isFalse);
      expect(cubit.state.owner, isNull);

      await cubit.newTab();

      expect(cubit.state.tabs, isEmpty);
      expect(launcher.starts, isEmpty);
      expect(launcher.resolveShellCalls, 0);
    });

    testWidgets('у активной сессии нет SessionHandle — то же самое', (
      tester,
    ) async {
      workspace.emit(
        workspace.current.copyWith(profile: _p1, activeSessionId: _s1),
      );

      expect(cubit.state.hasSession, isFalse);
      await cubit.newTab();

      expect(cubit.state.tabs, isEmpty);
      expect(launcher.starts, isEmpty);
    });
  });

  group('запуск вкладки (D5, Q19)', () {
    testWidgets('снимок cwd: вкладка стартует в папке сессии на момент '
        'создания', (tester) async {
      workspace.openSession(_p1, _s1);
      await openTab();
      // Папка сессии позже сменилась: первая вкладка её не видит.
      workspace.addSession(_s1, '/work/b');
      await openTab();

      expect(launcher.starts.map((s) => s.workingDirectory), [
        '/work/a',
        '/work/b',
      ]);
      // `WorkingDirectoryProvider` Cubit не принимает: запасного пути нет.
    });

    testWidgets('несуществующая папка — failed(folderNotFound) без start', (
      tester,
    ) async {
      existingDirectories.clear();
      workspace.openSession(_p1, _s1);

      await cubit.newTab();

      expect(
        status(),
        isA<TerminalTabFailed>().having(
          (s) => s.reason,
          'reason',
          UserShellStartFailure.folderNotFound,
        ),
      );
      expect(launcher.starts, isEmpty);
    });

    testWidgets('shell берётся у порта: команда уходит в start', (
      tester,
    ) async {
      launcher.shell = (executable: '/opt/bin/fish', arguments: ['-l']);
      workspace.openSession(_p1, _s1);

      await cubit.newTab();

      expect(launcher.starts.single.executable, '/opt/bin/fish');
      expect(launcher.starts.single.arguments, ['-l']);
      expect(launcher.starts.single.columns, greaterThan(0));
      expect(launcher.starts.single.rows, greaterThan(0));
    });

    testWidgets('resolveShell() == null — failed(shellNotFound) без start', (
      tester,
    ) async {
      launcher.shell = null;
      workspace.openSession(_p1, _s1);

      await cubit.newTab();

      expect(
        status(),
        isA<TerminalTabFailed>().having(
          (s) => s.reason,
          'reason',
          UserShellStartFailure.shellNotFound,
        ),
      );
      expect(launcher.starts, isEmpty);
    });

    testWidgets('новая вкладка активна; 12 вкладок подряд без отказа (Q8)', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);

      for (var i = 0; i < 12; i++) {
        await cubit.newTab();
        expect(cubit.state.activeTabId, cubit.state.tabs.last.id);
      }

      expect(cubit.state.tabs, hasLength(12));
      expect(launcher.starts, hasLength(12));
      expect(cubit.state.tabs.map((t) => t.id).toSet(), hasLength(12));
      expect(
        cubit.state.tabs,
        everyElement(
          isA<TerminalTab>().having(
            (t) => t.status,
            'status',
            isA<TerminalTabRunning>(),
          ),
        ),
      );
    });

    testWidgets('selectTab делает вкладку активной', (tester) async {
      workspace.openSession(_p1, _s1);
      await cubit.newTab();
      await cubit.newTab();
      final first = cubit.state.tabs.first.id;

      cubit.selectTab(first);

      expect(cubit.state.activeTabId, first);
    });
  });

  group('старт в полёте (D4)', () {
    testWidgets('закрытие вкладки до конца start: поздний UserShell получает '
        'kill и в реестр не попадает', (tester) async {
      launcher.deferStarts = true;
      workspace.openSession(_p1, _s1);

      final pendingTab = cubit.newTab();
      await tester.pump();
      expect(status(), isA<TerminalTabStarting>());
      cubit.closeTab(cubit.state.tabs.single.id);
      expect(cubit.state.tabs, isEmpty);

      final shell = launcher.pending.single.complete();
      await pendingTab;

      expect(shell.kills, 1);
      expect(shell.hangUps, 0);
      expect(cubit.state.tabs, isEmpty);
      expect(shell.hasOutputListener, isFalse);
    });

    testWidgets('closeAll() во время start: то же самое, новые вкладки не '
        'создаются', (tester) async {
      launcher.deferStarts = true;
      workspace.openSession(_p1, _s1);

      final pendingTab = cubit.newTab();
      await tester.pump();
      final closing = cubit.closeAll();
      final shell = launcher.pending.single.complete();
      await pendingTab;
      await tester.pump(const Duration(seconds: 3));
      await closing;

      expect(shell.kills, 1);
      expect(cubit.state.tabs, isEmpty);
    });

    testWidgets('ошибка start у закрытой вкладки: только событие, состояние '
        'не меняется', (tester) async {
      launcher.deferStarts = true;
      workspace.openSession(_p1, _s1);

      final pendingTab = cubit.newTab();
      await tester.pump();
      cubit.closeTab(cubit.state.tabs.single.id);
      final before = cubit.state;
      launcher.pending.single.fail(UserShellStartFailure.ptyUnavailable);
      await pendingTab;

      expect(cubit.state, before);
      expect(events('terminal.start_failed'), hasLength(1));
    });

    testWidgets('поздний UserShell закрытой вкладки с ошибкой exitCode: '
        'событие exit_wait_failed без необработанной ошибки', (tester) async {
      launcher.deferStarts = true;
      workspace.openSession(_p1, _s1);
      final shell = FakeUserShell()..failExit(StateError('boom'));

      final pendingTab = cubit.newTab();
      await tester.pump();
      final tabId = cubit.state.tabs.single.id;
      cubit.closeTab(tabId);
      final before = cubit.state;
      launcher.pending.single.complete(shell);
      await pendingTab;
      await tester.pump();

      expect(cubit.state, before);
      expect(shell.kills, 1);
      expect(
        events('terminal.exit_wait_failed').single,
        allOf(
          containsPair('tab_id', tabId),
          containsPair('error_type', 'StateError'),
        ),
      );
    });
  });

  group('ошибки старта (D4, D9)', () {
    testWidgets('UserShellStartFailure.ptyUnavailable — failed и событие', (
      tester,
    ) async {
      launcher.startError = UserShellStartFailure.ptyUnavailable;
      workspace.openSession(_p1, _s1);

      await cubit.newTab();

      expect(
        status(),
        isA<TerminalTabFailed>().having(
          (s) => s.reason,
          'reason',
          UserShellStartFailure.ptyUnavailable,
        ),
      );
      expect(
        events('terminal.start_failed').single,
        containsPair('reason', 'ptyUnavailable'),
      );
    });

    testWidgets('дефект адаптера (ArgumentError): failed(ptyUnavailable), '
        'error_type без текста и путей, исключение не выходит', (tester) async {
      launcher.startError = ArgumentError(
        'native library not found: /Users/x/lib.dylib',
      );
      workspace.openSession(_p1, _s1);

      await cubit.newTab();

      expect(
        status(),
        isA<TerminalTabFailed>().having(
          (s) => s.reason,
          'reason',
          UserShellStartFailure.ptyUnavailable,
        ),
      );
      final event = events('terminal.start_failed').single;
      expect(event, containsPair('reason', 'ptyUnavailable'));
      expect(event, containsPair('error_type', 'ArgumentError'));
      expect(logger.entries.toString(), isNot(contains('/Users')));
      expect(logger.entries.toString(), isNot(contains('dylib')));
    });
  });

  group('завершение процесса (D4)', () {
    testWidgets('exit 3 — exited(3), строка в эмуляторе, ввод игнорируется', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      shell.exit(3);
      await tester.pump();

      expect(
        status(),
        isA<TerminalTabExited>().having((s) => s.exitCode, 'exitCode', 3),
      );
      flushAll();
      expect(
        terminals.single.written.join(),
        contains('[Process exited with code 3]'),
      );
      expect(
        events('terminal.tab_exited').single,
        containsPair('exit_code', 3),
      );

      terminals.single.textInput('ls\n');
      expect(shell.written, isEmpty);
    });

    testWidgets('код null — exited(null), строка без кода, событие без '
        'exit_code', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      shell.exit(null);
      await tester.pump();

      expect(
        status(),
        isA<TerminalTabExited>().having((s) => s.exitCode, 'exitCode', isNull),
      );
      flushAll();
      final text = terminals.single.written.join();
      expect(text, contains('[Process exited]'));
      expect(text, isNot(contains('with code')));
      expect(
        events('terminal.tab_exited').single.containsKey('exit_code'),
        isFalse,
      );
    });

    testWidgets('после exited Cubit отписан от output и не шлёт сигналов ни '
        'при закрытии, ни в closeAll()', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final other = await openTab();

      shell.exit(0);
      await tester.pump();
      expect(shell.hasOutputListener, isFalse);

      cubit.closeTab(cubit.state.tabs.first.id);
      final closing = cubit.closeAll();
      await tester.pump(const Duration(seconds: 3));
      await closing;

      expect(shell.hangUps + shell.kills, 0);
      expect(other.hangUps, 1);
    });

    testWidgets('exitCode завершился ошибкой — exited(null), '
        'exit_wait_failed, без сигналов и отписка от output', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final tabId = cubit.state.tabs.single.id;

      shell.failExit(StateError('boom /secret/path'));
      await tester.pump();

      expect(
        status(),
        isA<TerminalTabExited>().having((s) => s.exitCode, 'exitCode', isNull),
      );
      expect(
        events('terminal.exit_wait_failed').single,
        containsPair('tab_id', tabId),
      );
      expect(
        events('terminal.exit_wait_failed').single,
        containsPair('error_type', 'StateError'),
      );
      expect(logger.entries.toString(), isNot(contains('boom')));
      expect(logger.entries.toString(), isNot(contains('/secret')));
      expect(shell.hangUps + shell.kills, 0);
      expect(shell.hasOutputListener, isFalse);
    });
  });

  group('предел непрочитанного буфера вывода (Q20, D3)', () {
    const marker = '\r\n[output truncated]\r\n';

    String text() => terminals.last.written.join();

    testWidgets('20 МБ в фоновую вкладку без сброса: буфер не больше предела, '
        'пометка одна, хвост и порядок сохранены', (tester) async {
      await cubit.close();
      cubit = build(writeChunkSize: 1 << 20, parse: false);
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      final sent = StringBuffer();
      for (var i = 0; i < 20; i++) {
        final chunk = String.fromCharCode(0x41 + i) * (1 << 20);
        sent.write(chunk);
        shell.emit(chunk);
        await tester.idle();
      }
      flushAll();

      final written = text();
      expect(marker.allMatches(written), hasLength(1));
      expect(written, startsWith(marker));
      final kept = written.substring(marker.length);
      expect(kept.length, terminalMaxPendingOutput);
      // Хвост вывода и порядок: оставшееся — суффикс всего отправленного.
      expect(sent.toString().endsWith(kept), isTrue);
    });

    testWidgets('пометка раз на эпизод: до сброса — одна, после сброса новое '
        'переполнение даёт новую', (tester) async {
      await cubit.close();
      cubit = build(maxPendingOutput: 100);
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      for (final c in ['a' * 60, 'b' * 60, 'c' * 60]) {
        shell.emit(c);
        await tester.idle();
      }
      flushAll();
      expect(marker.allMatches(text()), hasLength(1));
      expect(text(), '$marker${'b' * 40}${'c' * 60}');

      shell.emit('d' * 150);
      await tester.idle();
      flushAll();
      expect(marker.allMatches(text()), hasLength(2));
      expect(text().endsWith('d' * 100), isTrue);
    });

    testWidgets('граница обрезки внутри суррогатной пары: после пометки нет '
        'одиночных суррогатов', (tester) async {
      await cubit.close();
      // Нечётный предел: обрезка 200 единиц (100 эмодзи) попадает внутрь пары.
      cubit = build(maxPendingOutput: 101);
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      shell.emit('\u{1F600}' * 100);
      await tester.idle();
      flushAll();

      final kept = text().substring(marker.length);
      expect(text(), startsWith(marker));
      expect(kept, isNotEmpty);
      // Строка корректна: `runes` даёт ровно столько точек, сколько пар.
      expect(kept.runes.every((r) => r == 0x1F600), isTrue);
      expect(kept.length, 100);
    });

    testWidgets('вывод в пределах не трогается, пометки нет', (tester) async {
      await cubit.close();
      cubit = build(maxPendingOutput: 100);
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      shell.emit('a' * 100);
      await tester.idle();
      flushAll();

      expect(text(), 'a' * 100);
    });
  });

  group('закрытие (D4)', () {
    testWidgets('hangUp, через 2 с kill; вкладка исчезает сразу, forced в '
        'событии', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final tabId = cubit.state.tabs.single.id;

      cubit.closeTab(tabId);

      expect(cubit.state.tabs, isEmpty);
      expect(shell.hangUps, 1);
      expect(shell.kills, 0);
      await tester.pump(const Duration(milliseconds: 1999));
      expect(shell.kills, 0);
      await tester.pump(const Duration(milliseconds: 1));
      expect(shell.kills, 1);
      expect(
        events('terminal.tab_closed').single,
        containsPair('forced', true),
      );
      expect(
        events('terminal.tab_closed').single,
        containsPair('tab_id', tabId),
      );
    });

    testWidgets('shell вышел на hangUp — kill не нужен, forced == false', (
      tester,
    ) async {
      launcher.shellsExitOnHangUp = true;
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      cubit.closeTab(cubit.state.tabs.single.id);
      await tester.pump(const Duration(seconds: 3));

      expect(shell.hangUps, 1);
      expect(shell.kills, 0);
      expect(
        events('terminal.tab_closed').single,
        containsPair('forced', false),
      );
    });

    testWidgets('повторное закрытие — без ошибок и лишних сигналов', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final tabId = cubit.state.tabs.single.id;

      cubit.closeTab(tabId);
      cubit.closeTab(tabId);
      await tester.pump(const Duration(seconds: 3));

      expect(shell.hangUps, 1);
      expect(shell.kills, 1);
    });

    testWidgets('поздний вывод закрытой вкладки не меняет состояние', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      cubit.closeTab(cubit.state.tabs.single.id);
      final before = cubit.state;

      shell.emit('late output');
      await tester.pump();

      expect(cubit.state, before);
      expect(cubit.hasPendingOutput, isFalse);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('closeAll(): hangUp всем, через 3 с kill, затем новые '
        'вкладки не создаются, повторный вызов без действий', (tester) async {
      workspace.openSession(_p1, _s1);
      final a = await openTab();
      final b = await openTab();

      final closing = cubit.closeAll();
      expect(a.hangUps + b.hangUps, 2);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(a.kills + b.kills, 0);
      await tester.pump(const Duration(milliseconds: 1));
      await closing;

      expect(a.kills, 1);
      expect(b.kills, 1);
      expect(events('terminal.close_all').single, containsPair('count', 2));
      expect(events('terminal.close_all').single, containsPair('forced', true));

      await cubit.newTab();
      expect(launcher.starts, hasLength(2));
      expect(cubit.state.tabs, isEmpty);

      await cubit.closeAll();
      expect(a.hangUps + b.hangUps, 2);
      expect(events('terminal.close_all'), hasLength(1));
    });
  });

  group('closeAll(): forced в tab_closed (D4, D9)', () {
    testWidgets('убитая по таймауту вкладка пишет tab_closed с forced: true, '
        'вышедшая сама — с forced: false', (tester) async {
      workspace.openSession(_p1, _s1);
      final stubborn = await openTab();
      final stubbornId = cubit.state.tabs.single.id;
      final polite = await openTab();
      final politeId = cubit.state.tabs.last.id;

      final closing = cubit.closeAll();
      polite.exit(0);
      await tester.pump(const Duration(seconds: 3));
      await closing;

      expect(stubborn.kills, 1);
      expect(polite.kills, 0);
      final closed = {
        for (final e in events('terminal.tab_closed')) e['tab_id']: e['forced'],
      };
      expect(closed, {stubbornId: true, politeId: false});
    });

    testWidgets('вкладка из closeTab, у которой closeAll отменил killTimer, '
        'тоже помечается forced', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final tabId = cubit.state.tabs.single.id;
      cubit.closeTab(tabId);

      final closing = cubit.closeAll();
      await tester.pump(const Duration(seconds: 3));
      await closing;

      expect(shell.kills, 1);
      expect(
        events('terminal.tab_closed').single,
        containsPair('forced', true),
      );
    });
  });

  group('запись в эмулятор порциями (D3, D4)', () {
    String payload(int length) => String.fromCharCodes([
      for (var i = 0; i < length; i++) 0x20 + (i * 7 + i ~/ 5) % 90,
    ]);

    testWidgets('400 КБ одним чанком уходят в Terminal.write частями не '
        'больше 4 КБ, без потери и перестановки', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final data = payload(400 * 1024);

      shell.emit(data);
      await tester.pump();

      expect(cubit.hasPendingOutput, isTrue);
      expect(terminals.single.written, isEmpty);
      final chunks = flushAll();

      expect(chunks, greaterThanOrEqualTo(100));
      expect(
        terminals.single.written.map((c) => c.length),
        everyElement(lessThanOrEqualTo(4096)),
      );
      expect(terminals.single.written.join(), data);
      expect(cubit.hasPendingOutput, isFalse);
    });

    testWidgets('canContinue ограничивает число частей за вызов; остаток '
        'переносится', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      shell.emit(payload(20 * 1024));
      await tester.pump();

      var allowed = 2;
      final written = cubit.flushOutput(canContinue: () => allowed-- > 0);

      expect(written, 2);
      expect(cubit.hasPendingOutput, isTrue);
    });

    testWidgets('закрытие вкладки отбрасывает незаписанный остаток', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      shell.emit(payload(40 * 1024));
      await tester.pump();
      var allowed = 1;
      cubit.flushOutput(canContinue: () => allowed-- > 0);
      expect(cubit.hasPendingOutput, isTrue);

      cubit.closeTab(cubit.state.tabs.single.id);

      expect(cubit.hasPendingOutput, isFalse);
      expect(cubit.flushOutput(), 0);
      // Дать истечь 2 с до kill: иначе в конце теста остаётся Timer.
      await tester.pump(const Duration(seconds: 2));
      expect(terminals.single.written, hasLength(1));
    });

    testWidgets('ввод пользователя и ответы эмулятора уходят процессу', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();

      terminals.single.textInput('ls\n');

      expect(shell.written.join(), 'ls\n');
    });
  });

  // Вторая линия защиты ссылок OSC 8 (D3, D11): даже если виджет по ошибке
  // вызвал `openLink` для запрещённой схемы, порт не получает адрес.
  group('ссылки OSC 8: openLink (D3, D9)', () {
    for (final (uri, scheme) in [
      ('file:///etc/passwd', 'file'),
      ('javascript:alert(1)', 'javascript'),
    ]) {
      test('$scheme: порт не вызывается, событие только со схемой', () async {
        await cubit.openLink(uri);

        expect(linkOpener.opened, isEmpty);
        final refused = logger.entries.where(
          (e) => e['event'] == 'terminal.link_refused',
        );
        expect(refused, hasLength(1));
        expect(refused.single['scheme'], scheme);
        expect(logger.entries.toString(), isNot(contains(uri)));
      });
    }

    test(
      'https: порт получает адрес, событие link_opened только со схемой',
      () async {
        await cubit.openLink('https://example.com/a?token=x');

        expect(linkOpener.opened, [Uri.parse('https://example.com/a?token=x')]);
        final opened = logger.entries.where(
          (e) => e['event'] == 'terminal.link_opened',
        );
        expect(opened.single['scheme'], 'https');
        expect(logger.entries.toString(), isNot(contains('token=x')));
      },
    );
  });

  group('жизненный цикл Cubit и журнал (D9)', () {
    testWidgets('после close() событий нет и ошибок нет', (tester) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      await cubit.close();
      final count = logger.entries.length;

      shell.emit('x');
      shell.exit(0);
      workspace.openSession(_p1, _s2, cwd: '/work/b');
      await tester.pump();

      expect(logger.entries, hasLength(count));
      expect(workspace.hasStateListeners, isFalse);
    });

    testWidgets('предупреждение показывается один раз за жизнь Cubit', (
      tester,
    ) async {
      expect(cubit.state.disclosureShown, isFalse);

      cubit.acknowledgeDisclosure();
      expect(cubit.state.disclosureShown, isTrue);

      workspace.openSession(_p1, _s1);
      await cubit.newTab();
      cubit.acknowledgeDisclosure();
      expect(cubit.state.disclosureShown, isTrue);
    });

    testWidgets('события D9 без путей, окружения, ввода и вывода', (
      tester,
    ) async {
      workspace.openSession(_p1, _s1);
      final shell = await openTab();
      final tabId = cubit.state.tabs.single.id;

      shell.emit('OUTPUT-MARKER-1');
      terminals.single.textInput('INPUT-MARKER-2');
      await tester.pump();
      flushAll();
      shell.exit(0);
      await tester.pump();

      final opened = events('terminal.tab_opened').single;
      expect(opened, containsPair('tab_id', tabId));
      expect(opened, containsPair('session_id', 's1'));
      expect(opened, containsPair('shell', 'zsh'));
      expect(opened, containsPair('columns', launcher.starts.single.columns));
      expect(opened, containsPair('rows', launcher.starts.single.rows));
      // profileId в события не пишется (D9).
      expect(opened.keys, isNot(contains('profile_id')));
      final dump = logger.entries.toString();
      for (final forbidden in ['/work/a', '/bin/zsh', 'MARKER', 'p1', 'PATH']) {
        expect(dump, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('terminalModel — политика буфера обмена (Q13, D3)', () {
    test('каждое поле политики выставлено, обработчики не null', () {
      final terminal = terminalModel(onOutput: (_) {});

      expect(terminal.maxLines, 10000);
      expect(terminal.clipboardDecoder, isNotNull);
      expect(terminal.clipboardDecoder!('c', 'aGVsbG8='), isNull);
      expect(terminal.allowITerm2ClipboardCapture, isFalse);
      expect(terminal.allowKittyClipboard, isFalse);
      expect(terminal.onClipboardStore, isNotNull);
      expect(() => terminal.onClipboardStore!('c', 'text'), returnsNormally);
      expect(terminal.onClipboardQuery, isNotNull);
      expect(terminal.onClipboardQuery!('c'), isNull);
      // Адрес открывается только через onHyperlinkTap и диалог (Q14, 2.10).
      expect(terminal.onOpenUrl, isNull);
    });

    test('onOutput несёт ввод и ответы эмулятора, onResize — размер', () {
      final output = <String>[];
      final sizes = <(int, int)>[];
      final terminal = terminalModel(
        onOutput: output.add,
        onResize: (columns, rows) => sizes.add((columns, rows)),
      );

      terminal.textInput('a');
      terminal.resize(100, 30);

      expect(output.join(), 'a');
      expect(sizes, [(100, 30)]);
    });
  });
}
