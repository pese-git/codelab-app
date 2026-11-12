// Панель Terminal в доке инструментов собранного приложения (задача 2.5
// change `add-integrated-terminal`; spec `integrated-terminal` «Панель Terminal
// в доке инструментов», «Вкладки терминала принадлежат сессии», «Терминал вне
// одобрений агента», «Восстановление дока не запускает shell», «Терминал
// только там, где есть PTY», «Содержимое терминала не покидает экран»; D1, D3,
// D5, D7, D12; Q13, Q17–Q19).
//
// Тест красный до задачи 2.6: в `createCodeLabRootScope` нет шва
// `userShellLauncher:`, в `CodeLabShell` нет ветки `ToolPane.terminal`, а
// `TerminalTabsCubit` не собран в root scope. После 2.6 шов появится и в
// `CodeLabTestBinding` (`test_app_scope.dart`), и локальная сборка `_Env`
// заменится его параметром `userShellLauncher:`.

import 'dart:convert';

import 'package:cherrypick/cherrypick.dart' show Scope;
import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_core/codelab_client_core.dart'
    show ClientWorkspace;
import 'package:codelab_desktop/app/app_scope.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_model.dart';
import 'package:codelab_desktop/features/terminal/application/terminal_tabs_cubit.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:codelab_desktop/features/terminal/presentation/terminal_output_flusher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:structured_log_flutter/structured_log_flutter.dart'
    show LogBuffer;
import 'package:xterm2/ui.dart' show TerminalController, TerminalView;
import 'package:xterm2_core/xterm2_core.dart' show Terminal;

import '../../../support/fake_user_shell_launcher.dart';
import '../../../support/test_app_scope.dart';
import '../../../support/start_agent.dart';

/// Приложение с fake-портом терминала и сценарным агентом.
///
/// Почему локально: параметр `userShellLauncher:` у `CodeLabTestBinding`
/// появится вместе со швом в 2.6; до тех пор файл не должен ломать остальные
/// тесты app. Для чего: один граф cherrypick с `FakeUserShellLauncher`,
/// `FakeAcpTransport` для подключения и сессий и переподключением на второй
/// транспорт. Как использовать: `_Env(tester, ...)` в начале теста, затем
/// `pumpApp`, `openSession`, `reconnect`.
final class _Env {
  _Env({
    FakeUserShellLauncher? launcher,
    Map<String, Object> preferences = const {},
  }) : launcher =
           launcher ?? (FakeUserShellLauncher()..shellsExitOnHangUp = true) {
    final transports = [agent, second];
    binding = CodeLabTestBinding(
      stdioTransportFactory: (_) => transports.removeAt(0),
      preferences: preferences,
      userShellLauncher: this.launcher,
    );
    scope = binding.scope;
    second.initializeAgentCapabilities = const AgentCapabilities(
      loadSession: true,
    );
  }

  final FakeUserShellLauncher launcher;
  final FakeAcpTransport agent = FakeAcpTransport();
  final FakeAcpTransport second = FakeAcpTransport();
  late final CodeLabTestBinding binding;
  late final Scope scope;

  CodeLabShellCubit get shell => scope.resolve<CodeLabShellCubit>();
  TerminalTabsCubit get terminals => scope.resolve<TerminalTabsCubit>();
  ClientWorkspace get workspace => scope.resolve<ClientWorkspace>();

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      CodeLabBootstrap(
        scope: scope,
        child: const CodeLabApp(startOnLaunch: false),
      ),
    );
    await tester.pump();
  }

  /// Подключается (первый раз) и создаёт сессию [id] в папке [cwd].
  Future<void> openSession(
    WidgetTester tester,
    String id, {
    String cwd = '/work/a',
  }) async {
    await tester.runAsync(() async {
      await shell.selectProject(cwd);
      if (shell.state.connectionStatus != CodeLabConnectionStatus.connected) {
        await shell.startWith();
      }
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionNewMethod,
      );
      final created = shell.createSession();
      final request = await sent as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
      );
      await created;
    });
    await tester.pump();
    await tester.pump();
  }

  /// Переподключение на второй транспорт и `session/load` открытых сессий.
  Future<void> reconnect(WidgetTester tester) async {
    await tester.runAsync(() async {
      final loads = <String>[];
      final sub = second.sent.listen((m) {
        if (m is JsonRpcRequest && m.method == sessionLoadMethod) {
          loads.add('${m.id}');
          second.emitInbound(
            JsonRpcMessage.response(
              id: m.id,
              result: const <String, Object?>{},
            ),
          );
        }
      });
      await shell.restartAgent();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
    });
    await tester.pump();
    await tester.pump();
  }
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 50));
}

/// Нажатие переключателя через обработчик: в шрифте Ahem подписи шире
/// реальных и попадание по координате ненадёжно (как в `workbench_shell_test`).
void _toggle(WidgetTester tester, ToolPane pane) => tester
    .widget<ToggleButton>(find.byKey(CodeLabAppBar.toggleKey(pane)))
    .onChanged!(true);

/// Двойник планировщика: запоминает заказанные обратные вызовы и кадры.
final class _CountingScheduler extends Fake implements SchedulerBinding {
  final List<FrameCallback> callbacks = [];
  int frameRequests = 0;

  @override
  int scheduleFrameCallback(
    FrameCallback callback, {
    bool rescheduling = false,
    bool scheduleNewFrame = true,
  }) {
    callbacks.add(callback);
    return callbacks.length;
  }

  @override
  void scheduleFrame() => frameRequests++;

  @override
  void cancelFrameCallbackWithId(int id) {}
}

final _terminalToggle = find.byKey(CodeLabAppBar.toggleKey(ToolPane.terminal));
final _terminalPane = find.byKey(CodeLabToolDock.paneKey(ToolPane.terminal));
final _newTab = find.byKey(CodeLabTerminalPane.newTabKey);
const _hint = 'Open a session to use the terminal';

void main() {
  group('панель Terminal в доке', () {
    testWidgets('переключатель открывает панель с одной вкладкой, терминал '
        'вне одобрений агента', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');

      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      expect(_terminalPane, findsOneWidget);
      expect(find.byKey(CodeLabTerminalPane.tabKey('t1')), findsOneWidget);
      expect(env.launcher.starts, hasLength(1));
      // Рабочая папка вкладки — снимок `SessionHandle.cwd` (Q19).
      expect(env.launcher.starts.single.workingDirectory, '/work/a');
      // D7: запуск shell пользователя не порождает ни запросов агенту, ни
      // одобрений; в ACP не уходит ничего, кроме `initialize` и `session/new`.
      final methods = [
        for (final m in env.agent.sentMessages)
          if (m is JsonRpcRequest) m.method,
      ];
      expect(methods, [initializeMethod, sessionNewMethod]);
      expect(env.shell.sessionIdsWithPendingApproval, isEmpty);
    });

    testWidgets('закрытие панели крестиком дока и повторное открытие '
        'сохраняют вкладку и процесс', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      await tester.tap(find.byKey(CodeLabToolDock.closeKey(ToolPane.terminal)));
      await _frames(tester);
      expect(_terminalPane, findsNothing);

      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      expect(_terminalPane, findsOneWidget);
      expect(find.byKey(CodeLabTerminalPane.tabKey('t1')), findsOneWidget);
      expect(find.byKey(CodeLabTerminalPane.tabKey('t2')), findsNothing);
      expect(env.launcher.starts, hasLength(1));
      final process = env.launcher.shells.single;
      expect(process.hangUps + process.kills, 0);
    });

    testWidgets('выбор сессии B показывает её вкладки, возврат к A — вкладку '
        'A с живым процессом (D5, Q4)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);
      final processA = env.launcher.shells.single;

      await env.openSession(tester, 'session-b', cwd: '/work/b');
      await _frames(tester);
      // У сессии B своих вкладок нет: вкладка A не показана, панель
      // предлагает «New terminal» (Q4).
      expect(find.byKey(CodeLabTerminalPane.tabKey('t1')), findsNothing);
      expect(find.text('New terminal'), findsOneWidget);
      await tester.tap(_newTab);
      await _frames(tester);
      expect(find.byKey(CodeLabTerminalPane.tabKey('t2')), findsOneWidget);
      expect(env.launcher.starts.last.workingDirectory, '/work/b');

      env.shell.selectSession('session-a');
      await _frames(tester);

      expect(find.byKey(CodeLabTerminalPane.tabKey('t1')), findsOneWidget);
      expect(find.byKey(CodeLabTerminalPane.tabKey('t2')), findsNothing);
      // Процесс A жив: сигналов не получал, вывод по-прежнему подписан.
      expect(processA.hangUps + processA.kills, 0);
      expect(processA.hasOutputListener, isTrue);
    });

    testWidgets('без активной сессии панель открывается с подсказкой, без '
        '`terminal-new-tab` и без запуска shell (Q17)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);

      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      expect(_terminalPane, findsOneWidget);
      expect(find.text(_hint), findsOneWidget);
      expect(_newTab, findsNothing);
      expect(find.text('New terminal'), findsNothing);
      expect(env.launcher.starts, isEmpty);
    });

    testWidgets('выбор другого проекта и переподключение с `session/load` '
        'не закрывают вкладку сессии (Q18)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);
      final process = env.launcher.shells.single;

      await tester.runAsync(() => env.shell.selectProject('/work/other'));
      await _frames(tester);
      expect(find.byKey(CodeLabTerminalPane.tabKey('t1')), findsOneWidget);

      await env.reconnect(tester);
      await _frames(tester);

      expect(env.second.state, AcpTransportState.connected);
      expect(env.shell.state.activeSessionId, 'session-a');
      expect(find.byKey(CodeLabTerminalPane.tabKey('t1')), findsOneWidget);
      expect(process.hangUps + process.kills, 0);
      expect(env.launcher.starts, hasLength(1));
    });

    testWidgets('восстановленный док показывает пустое состояние и не '
        'запускает shell (D1, «Восстановление дока»)', (tester) async {
      final env = _Env(
        preferences: {
          'codelab.dock.open_panes': ['terminal'],
          'codelab.dock.active_pane': 'terminal',
        },
      );
      await env.pumpApp(tester);
      await _frames(tester);

      expect(_terminalPane, findsOneWidget);
      expect(find.text(_hint), findsOneWidget);
      expect(env.launcher.starts, isEmpty);

      // Сессия появилась, а пользователь вкладку не просил: «New terminal»,
      // по-прежнему без запуска.
      await env.openSession(tester, 'session-a');
      await _frames(tester);
      expect(find.text('New terminal'), findsOneWidget);
      expect(env.launcher.starts, isEmpty);
    });

    testWidgets('без PTY (`isSupported: false`) переключателя Terminal нет '
        '(D12)', (tester) async {
      final env = _Env(launcher: FakeUserShellLauncher(isSupported: false));
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      await _frames(tester);

      expect(_terminalToggle, findsNothing);
      expect(env.launcher.starts, isEmpty);
    });
  });

  group('предупреждение и содержимое', () {
    testWidgets('предупреждение при первом открытии и его нет после '
        'закрытия (Q7)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');

      _toggle(tester, ToolPane.terminal);
      await _frames(tester);
      expect(find.byKey(CodeLabTerminalPane.disclosureKey), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byKey(CodeLabTerminalPane.disclosureKey),
          matching: find.byType(IconButton),
        ),
      );
      await _frames(tester);
      expect(find.byKey(CodeLabTerminalPane.disclosureKey), findsNothing);

      await tester.tap(find.byKey(CodeLabToolDock.closeKey(ToolPane.terminal)));
      await _frames(tester);
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);
      expect(_terminalPane, findsOneWidget);
      expect(find.byKey(CodeLabTerminalPane.disclosureKey), findsNothing);
    });

    testWidgets('маркер вывода shell не попадает в `LogBuffer` (D9)', (
      tester,
    ) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      const marker = 'OUTPUT_MARKER_5f3a9c_secret';
      env.launcher.shells.single.emit('$marker\r\n');
      await _frames(tester);

      final logged = [
        for (final entry in env.scope.resolve<LogBuffer>().entries.value)
          jsonEncode(entry, toEncodable: (o) => '$o'),
      ];
      expect(logged.where((line) => line.contains(marker)), isEmpty);
      // Путь папки сессии законно попадает в журнал выбора проекта и
      // `session/new`; D9 требует его отсутствия только в событиях терминала.
      final terminalEvents = logged.where(
        (line) => line.contains('"logger":"codelab_desktop.terminal"'),
      );
      expect(terminalEvents, isNotEmpty);
      expect(terminalEvents.where((line) => line.contains('/work/a')), isEmpty);
    });
  });

  group('жизненный цикл и вывод в собранном приложении', () {
    testWidgets('закрытие панели переключателем не запускает shell, даже если '
        'вкладок нет (D1)', (tester) async {
      final env = _Env(
        preferences: {
          'codelab.dock.open_panes': ['terminal'],
          'codelab.dock.active_pane': 'terminal',
        },
      );
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      await _frames(tester);
      expect(_terminalPane, findsOneWidget);

      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      expect(_terminalPane, findsNothing);
      expect(env.launcher.starts, isEmpty);
      expect(env.terminals.state.tabs, isEmpty);
    });

    testWidgets('вывод shell доходит до модели вкладки на кадре (D3)', (
      tester,
    ) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      env.launcher.shells.single.emit('visible-marker-42\r\n');
      await _frames(tester);

      final model = env.terminals.terminalOf('t1')!;
      expect(model.buffer.getText(), contains('visible-marker-42'));
      expect(env.terminals.hasPendingOutput, isFalse);
    });

    testWidgets('объект сброса сам заказывает кадр при выводе и записывает его '
        'в модель на этом кадре (D3)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);
      // Рабочий кадр пустого окна всегда заказан курсором терминала, поэтому
      // `hasScheduledFrame` ничего не доказывает: считаем вызовы у двойника.
      final scheduler = _CountingScheduler();
      final flusher = TerminalOutputFlusher(
        cubit: env.terminals,
        binding: scheduler,
      );
      addTearDown(flusher.dispose);

      env.launcher.shells.single.emit('flush-marker-7');
      await tester.idle();

      expect(env.terminals.hasPendingOutput, isTrue);
      expect(scheduler.callbacks, hasLength(1));
      expect(scheduler.frameRequests, 1);
      // Второй кусок до кадра не заказывает ещё один обратный вызов.
      env.launcher.shells.single.emit('more');
      await tester.idle();
      expect(scheduler.callbacks, hasLength(1));

      scheduler.callbacks.single(Duration.zero);

      expect(env.terminals.hasPendingOutput, isFalse);
      expect(
        env.terminals.terminalOf('t1')!.buffer.getText(),
        contains('flush-marker-7more'),
      );
    });

    testWidgets('текст терминала не прижат к краям панели: у `TerminalView` '
        'есть внутренний отступ (ручная проверка итерации 2)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      final view = tester.widget<TerminalView>(find.byType(TerminalView));

      final padding = view.padding;
      expect(padding, isNotNull);
      expect(padding!.left, greaterThan(0));
      expect(padding.right, greaterThan(0));
      expect(padding.top, greaterThan(0));
      expect(padding.bottom, greaterThan(0));
    });

    testWidgets('TerminalView использует моноширинный шрифт кита codelab_ui '
        '(ручная проверка итерации 2)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);

      final finder = find.byType(TerminalView);
      final view = tester.widget<TerminalView>(finder);
      final kit = CodeLabText.styleOf(
        tester.element(finder),
        CodeLabTextRole.mono,
      )!;

      expect(view.textStyle.fontFamily, kit.fontFamily);
      expect(view.textStyle.fontFamilyFallback, kit.fontFamilyFallback);
      expect(view.textStyle.fontSize, kit.fontSize);
    });

    testWidgets('закрытие root scope шлёт hangUp живым shell (D4)', (
      tester,
    ) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);
      final process = env.launcher.shells.single;
      expect(process.hangUps, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      // Процесс запущен в fake-зоне теста: ожидание его выхода идёт
      // микрозадачами этой зоны, поэтому закрываем с проворачиванием кадров.
      await closeCodeLabRootScopeInTest();

      expect(process.hangUps, 1);
    });

    testWidgets('закрытие root scope снимает крючок сброса вывода и не '
        'оставляет заказанного кадра (cherrypick зовёт dispose только у '
        'Disposable)', (tester) async {
      final env = _Env();
      await env.pumpApp(tester);
      await env.openSession(tester, 'session-a');
      _toggle(tester, ToolPane.terminal);
      await _frames(tester);
      final cubit = env.terminals;
      expect(cubit.onPendingOutput, isNotNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await closeCodeLabRootScopeInTest();

      expect(cubit.onPendingOutput, isNull);
    });
  });

  group('буфер обмена (Q13, D3)', () {
    /// Вызовы канала буфера обмена платформы.
    late List<MethodCall> clipboardCalls;

    setUp(() {
      clipboardCalls = [];
    });

    Future<void> mockClipboard(WidgetTester tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method.startsWith('Clipboard.')) {
            clipboardCalls.add(call);
            if (call.method == 'Clipboard.getData') {
              return <String, Object?>{'text': 'from-system-clipboard'};
            }
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    Future<void> pumpView(
      WidgetTester tester,
      Terminal terminal, {
      TerminalController? controller,
    }) async {
      await tester.pumpWidget(
        FluentApp(
          home: SizedBox(
            width: 600,
            height: 300,
            child: TerminalView(
              terminal,
              controller: controller,
              autofocus: true,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    /// Выводы OSC 52 (запись `c` и `p`, запрос), OSC 1337 и OSC 5522.
    final writes = <String>[
      '\x1b]52;c;${base64.encode(utf8.encode('stolen-c'))}\x07',
      '\x1b]52;p;${base64.encode(utf8.encode('stolen-p'))}\x07',
      '\x1b]52;c;?\x07',
      '\x1b]1337;CopyToClipboard=general\x07stolen-iterm\n'
          '\x1b]1337;EndCopy\x07',
      '\x1b]5522;type=write;${base64.encode(utf8.encode('stolen-kitty'))}\x07',
    ];

    testWidgets('OSC 52, 1337 и 5522 в выводе не трогают системный буфер, а '
        'shell не получает ответа', (tester) async {
      await mockClipboard(tester);
      final shell = FakeUserShell();
      final terminal = terminalModel(onOutput: shell.write);
      await pumpView(tester, terminal);

      for (final sequence in writes) {
        terminal.write(sequence);
        await tester.pump();
      }

      expect(
        clipboardCalls.where(
          (c) =>
              c.method == 'Clipboard.setData' ||
              c.method == 'Clipboard.getData',
        ),
        isEmpty,
      );
      expect(shell.written, isEmpty);
    });

    testWidgets('контроль: модель без политики под тем же TerminalView '
        'вызывает `Clipboard.setData` (ловит подмену `??=`)', (tester) async {
      await mockClipboard(tester);
      final terminal = Terminal(maxLines: 100);
      await pumpView(tester, terminal);

      terminal.write(writes.first);
      await tester.pump();

      expect(
        clipboardCalls.where((c) => c.method == 'Clipboard.setData'),
        isNotEmpty,
      );
    });

    testWidgets('выделение и копирование пользователем вызывают '
        '`Clipboard.setData` с выделенным текстом', (tester) async {
      await mockClipboard(tester);
      final terminal = terminalModel(onOutput: (_) {});
      final controller = TerminalController();
      addTearDown(controller.dispose);
      await pumpView(tester, terminal, controller: controller);
      terminal.write('hello world');
      await tester.pump();

      controller.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(5, 0),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      final sets = clipboardCalls.where((c) => c.method == 'Clipboard.setData');
      expect(sets, hasLength(1));
      expect((sets.single.arguments as Map)['text'], 'hello');
    });
  });
}
