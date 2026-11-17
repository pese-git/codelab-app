// Красные widget-тесты задачи 1.6 change `add-desktop-usage-pane`: панель
// Usage в доке и связанное поведение app (agent-workbench-ui «Панель Usage»:
// «Панель с журналом», «Rebuild from log», «Сбой загрузки журнала», «Агент
// без журнала», «Агент без usage»; «Строка статуса сессии под композером»:
// «Клик открывает панель Usage», «Строка без данных некликабельна»; «Экспорт
// usage в CSV»: «Отказ в диалоге»; design.md, D1, D3, D5, D6, D10, D11).
//
// Данные идут через настоящий граф app, как в `agents_pane_test.dart`:
// сценарные кадры `_codelab/session/usage` и ответы журнала на
// `FakeAcpTransport` проходят kit и Cubit-ы. Тест не знает, как kit строит
// `usageLedger` и как app собирает `UsagePaneData`; проверяются запросы на
// провод и видимое поведение по ключам A17: `usage-rebuild`, `usage-export`,
// `usage-ledger-status`, `usage-card-*`, `usage-turn-*`, `usage-note`,
// `usage-retry`, `palette-item` — по `CodeLabShellState.paletteActions`.
//
// Доступность панели решает application (D10): виджет её не определяет.
// Экспорт идёт через двойник порта `FakeUsageCsvSaver` (D5); файл не пишется.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/core/platform/usage_csv_saver.dart';
import 'package:codelab_desktop/features/usage/presentation/workbench_usage_pane.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_usage_csv_saver.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

const _ledgerMethod = '_codelab/session/usage/ledger';

const _usageOnly = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

const _usageAndLedger = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
      'usageLedger': {'version': 1},
    },
  },
);

Map<String, Object?> _tokens(int input, int output) => {
  'input': input,
  'output': output,
  'cacheRead': 0,
  'cacheWrite': 0,
};

/// Снимок `_codelab/session/usage` версии 1 сессии `s1`.
Map<String, Object?> _snapshot({int seq = 1}) => {
  'sessionId': 's1',
  'seq': seq,
  'trigger': 'turn',
  'turnId': 'turn-$seq',
  'turn': {'steps': 1, 'tokens': _tokens(100, 20), 'cost': '0.5'},
  'session': {
    'turns': 1,
    'steps': 1,
    'tokens': _tokens(100, 20),
    'cost': '0.5',
  },
  'currency': 'USD',
};

/// Ответ журнала D6: один ход с одним шагом.
Map<String, Object?> _ledger({
  int seq = 1,
  String status = 'upToDate',
  String? reason,
}) => {
  'sessionId': 's1',
  'seq': seq,
  'currency': 'USD',
  'total': {'turns': 1, 'steps': 1, 'tokens': _tokens(100, 20), 'cost': '0.5'},
  'ledger': {'status': status, 'reason': ?reason, 'records': 3},
  'turns': [
    {
      'index': 1,
      'total': {'steps': 1, 'tokens': _tokens(100, 20), 'cost': '0.5'},
      'steps': [
        {'index': 0, 'tokens': _tokens(100, 20), 'toolCallIds': <String>[]},
      ],
    },
  ],
};

/// Приложение в `testWidgets`, агент-двойник и шаги протокола.
final class _Scene {
  _Scene._(this.tester, this.binding, this.agent, this.cubit, this.saver);

  final WidgetTester tester;
  final CodeLabTestBinding binding;
  final FakeAcpTransport agent;
  final CodeLabShellCubit cubit;
  final FakeUsageCsvSaver saver;
  final Set<Object> _answered = {};

  static Future<_Scene> open(
    WidgetTester tester, {
    AgentCapabilities capabilities = _usageAndLedger,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = FakeAcpTransport()
      ..initializeAgentCapabilities = capabilities;
    final saver = FakeUsageCsvSaver();
    final binding = CodeLabTestBinding(
      project: '/work',
      stdioTransportFactory: (_) => agent,
      usageCsvSaver: saver,
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.runAsync(() => cubit.startWith());
    final scene = _Scene._(tester, binding, agent, cubit, saver);
    await scene.flush();
    return scene;
  }

  Future<void> flush() async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    // Кнопки Fluent отпускают нажатие по таймеру 100 мс.
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> newSession(String id) async {
    await tester.runAsync(() async {
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionNewMethod,
      );
      final creating = cubit.createSession();
      final request = await sent as JsonRpcRequest;
      agent.emitInbound(
        JsonRpcMessage.response(id: request.id, result: {'sessionId': id}),
      );
      await creating;
    });
    await flush();
  }

  /// Присылает снимок usage; строка статуса получает сегмент и размер.
  Future<void> snapshot({int seq = 1}) async {
    agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: seq),
      ),
    );
    await flush();
  }

  /// Команды агента: имена без слэша.
  Future<void> agentCommands(List<String> names) async {
    agent.emitInbound(
      JsonRpcMessage.notification(
        method: sessionUpdateMethod,
        params: {
          'sessionId': 's1',
          'update': {
            'sessionUpdate': 'available_commands_update',
            'availableCommands': [
              for (final name in names)
                {'name': name, 'description': 'Agent command $name'},
            ],
          },
        },
      ),
    );
    await flush();
  }

  /// Все запросы журнала, ушедшие агенту.
  List<JsonRpcRequest> get ledgerRequests => [
    for (final m in agent.sentMessages)
      if (m is JsonRpcRequest && m.method == _ledgerMethod) m,
  ];

  /// Отвечает на ещё не отвеченные запросы журнала.
  Future<void> answerLedger(Map<String, Object?> result) async {
    for (final request in ledgerRequests) {
      if (_answered.add(request.id)) {
        agent.emitInbound(
          JsonRpcMessage.response(id: request.id, result: result),
        );
      }
    }
    await flush();
  }

  /// Отвечает на ещё не отвеченные запросы журнала ошибкой агента.
  Future<void> failLedger({int code = -32603}) async {
    for (final request in ledgerRequests) {
      if (_answered.add(request.id)) {
        agent.emitInbound(
          JsonRpcMessage.response(
            id: request.id,
            error: JsonRpcError(code: code, message: 'ledger failed'),
          ),
        );
      }
    }
    await flush();
  }

  Finder get toggle => find.byKey(CodeLabAppBar.toggleKey(ToolPane.usage));
  Finder get pane => find.byKey(CodeLabToolDock.paneKey(ToolPane.usage));
  Finder get statusBar => find.byType(CodeLabSessionStatusBar);

  /// Сегмент токенов строки статуса: надёжная точка клика (центр самой строки
  /// может попасть в промежуток между сегментами).
  Finder get statusBarSegment => find.descendant(
    of: statusBar,
    matching: find.byKey(const ValueKey('status-bar-usage')),
  );

  Finder key(String value) => find.byKey(ValueKey(value));

  Future<void> openByToggle() async {
    tester.widget<ToggleButton>(toggle).onChanged!(true);
    await flush();
  }

  Future<void> tapKey(String value) async {
    await tester.tap(key(value));
    await flush();
  }

  /// Видимый текст под [scope] одной строкой.
  String textOf(Finder scope) => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(of: scope, matching: find.byType(RichText)),
    ))
      w.text.toPlainText(),
  ].join(' | ');

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }
}

void main() {
  group('доступность и клик по строке статуса (D6, D10)', () {
    testWidgets('«Агент без usage»: переключателя, вкладки и пункта палитры '
        'нет, сохранённая раскладка не меняется', (tester) async {
      final scene = await _Scene.open(
        tester,
        capabilities: const AgentCapabilities(),
      );
      scene.cubit.openPane(ToolPane.usage);
      await scene.newSession('s1');

      expect(scene.toggle, findsNothing);
      expect(scene.pane, findsNothing);
      expect(scene.cubit.state.openPanes, contains(ToolPane.usage));
      expect(scene.cubit.state.usageAvailable, isFalse);
      expect(
        scene.cubit.state.paletteActions.map((a) => a.id),
        isNot(contains('usage-pane')),
      );
      expect(scene.ledgerRequests, isEmpty);

      await scene.close();
    });

    testWidgets('«Строка без данных некликабельна»: клик по строке ничего '
        'не открывает', (tester) async {
      final scene = await _Scene.open(
        tester,
        capabilities: const AgentCapabilities(),
      );
      await scene.newSession('s1');
      expect(scene.statusBar, findsOneWidget);
      expect(scene.textOf(scene.statusBar), contains('usage: —'));

      await scene.tester.tap(scene.statusBar.first, warnIfMissed: false);
      await scene.flush();

      expect(scene.cubit.state.openPanes, isNot(contains(ToolPane.usage)));
      expect(scene.pane, findsNothing);

      await scene.close();
    });

    testWidgets('«Клик открывает панель Usage»: док показывает вкладку '
        'активной, повторный клик её не закрывает', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.snapshot();
      expect(scene.pane, findsNothing);

      await scene.tester.tap(scene.statusBarSegment);
      await scene.flush();

      expect(scene.pane, findsOneWidget);
      expect(scene.cubit.state.activePane, ToolPane.usage);

      await scene.tester.tap(scene.statusBarSegment);
      await scene.flush();

      expect(scene.pane, findsOneWidget);
      expect(scene.cubit.state.openPanes, contains(ToolPane.usage));
      expect(scene.cubit.state.activePane, ToolPane.usage);

      await scene.close();
    });

    testWidgets('пункт палитры Usage (/usage-pane) стоит рядом с командой '
        'агента /usage и открывает панель', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.agentCommands(['usage']);

      final actions = scene.cubit.state.paletteActions;
      final host = actions.singleWhere((a) => a.id == 'usage-pane');

      expect(host.slashCommand, '/usage-pane');
      expect(host.label, 'Usage');
      expect(
        actions.where((a) => a.slashCommand == '/usage'),
        hasLength(1),
        reason: 'команда агента /usage остаётся своей',
      );

      scene.cubit.selectCommand(host);
      await scene.flush();

      expect(scene.pane, findsOneWidget);
      expect(scene.cubit.state.activePane, ToolPane.usage);

      await scene.close();
    });

    testWidgets('панель только с usage без журнала доступна и в палитре '
        'есть', (tester) async {
      final scene = await _Scene.open(tester, capabilities: _usageOnly);
      await scene.newSession('s1');
      await scene.snapshot();

      expect(scene.cubit.state.usageAvailable, isTrue);
      expect(scene.toggle, findsOneWidget);
      expect(
        scene.cubit.state.paletteActions.map((a) => a.id),
        contains('usage-pane'),
      );

      await scene.close();
    });
  });

  group('слот дока (D1, D3)', () {
    testWidgets('«Панель с журналом»: открытие даёт один запрос журнала без '
        'rebuild, после ответа видны карточки и ход', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.snapshot();
      expect(scene.ledgerRequests, isEmpty);

      await scene.openByToggle();

      expect(scene.pane, findsOneWidget);
      expect(scene.ledgerRequests, hasLength(1));
      expect(
        (scene.ledgerRequests.single.params as Map?)?['rebuild'],
        isNull,
        reason: 'автоматический запрос уходит без rebuild',
      );

      await scene.answerLedger(_ledger());

      expect(scene.key('usage-card-input'), findsOneWidget);
      expect(scene.key('usage-card-cost'), findsOneWidget);
      expect(scene.key('usage-turn-1'), findsOneWidget);
      expect(
        scene.textOf(scene.key('usage-ledger-status')),
        'Ledger: up to date · 3 records',
      );
      expect(scene.ledgerRequests, hasLength(1));

      await scene.close();
    });

    testWidgets('«Rebuild from log»: запрос с rebuild: true, строка '
        'состояния обновляется', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.snapshot();
      await scene.openByToggle();
      await scene.answerLedger(_ledger());

      await scene.tapKey('usage-rebuild');

      expect(scene.ledgerRequests, hasLength(2));
      expect((scene.ledgerRequests.last.params as Map)['rebuild'], isTrue);

      await scene.answerLedger(_ledger(status: 'rebuilt', reason: 'explicit'));

      expect(
        scene.textOf(scene.key('usage-ledger-status')),
        'rebuilt from journal (explicit) · 3 records',
      );

      await scene.close();
    });

    testWidgets('«Сбой загрузки журнала»: заметка и Retry, повторного '
        'запроса без действия пользователя нет, Retry шлёт один', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.snapshot();
      await scene.openByToggle();

      await scene.failLedger();

      expect(
        scene.textOf(scene.key('usage-note')),
        contains("Couldn't load usage history."),
      );
      expect(scene.key('usage-retry'), findsOneWidget);
      expect(scene.ledgerRequests, hasLength(1));

      await scene.snapshot(seq: 2);
      expect(
        scene.ledgerRequests,
        hasLength(1),
        reason: 'failed не повторяется',
      );

      await scene.tapKey('usage-retry');

      expect(scene.ledgerRequests, hasLength(2));
      expect((scene.ledgerRequests.last.params as Map?)?['rebuild'], isNull);

      await scene.close();
    });

    testWidgets('«Агент без журнала»: карточки из снимка, заметка, ни '
        'Export CSV, ни Rebuild, ни запросов журнала', (tester) async {
      final scene = await _Scene.open(tester, capabilities: _usageOnly);
      await scene.newSession('s1');
      await scene.snapshot();

      await scene.openByToggle();

      expect(scene.pane, findsOneWidget);
      expect(scene.key('usage-card-cost'), findsOneWidget);
      expect(
        scene.textOf(scene.key('usage-note')),
        contains('This agent does not provide usage history.'),
      );
      expect(scene.key('usage-export'), findsNothing);
      expect(scene.key('usage-rebuild'), findsNothing);
      expect(scene.key('usage-turn-1'), findsNothing);
      expect(scene.ledgerRequests, isEmpty);

      await scene.close();
    });

    testWidgets('закрытая панель журнал не запрашивает', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.snapshot();
      await scene.snapshot(seq: 2);

      expect(scene.ledgerRequests, isEmpty);

      await scene.close();
    });
  });

  group('экспорт CSV (D5; «Отказ в диалоге»)', () {
    Future<_Scene> opened(WidgetTester tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.snapshot();
      await scene.openByToggle();
      await scene.answerLedger(_ledger());
      return scene;
    }

    testWidgets('сохранено: порт получил CSV с заголовком и предложенное имя '
        'codelab-usage-<sessionId>-<дата>.csv, заметки нет', (tester) async {
      final scene = await opened(tester);

      await scene.tapKey('usage-export');

      expect(scene.saver.saved, hasLength(1));
      final saved = scene.saver.saved.single;
      expect(
        saved.suggestedName,
        matches(r'^codelab-usage-s1-\d{8}-\d{4}\.csv$'),
      );
      expect(
        saved.csv,
        startsWith(
          'kind,turn,step,title,model,input,output,cache_read,cache_write,'
          'reasoning,cost,currency,partial\r\n',
        ),
      );
      expect(scene.key('usage-note'), findsNothing);

      await scene.close();
    });

    testWidgets('отказ в диалоге: ни файла, ни заметки', (tester) async {
      final scene = await opened(tester);
      scene.saver.result = const UsageCsvCancelled();

      await scene.tapKey('usage-export');

      expect(scene.saver.saved, hasLength(1));
      expect(find.text("Couldn't save the file."), findsNothing);
      expect(scene.key('usage-note'), findsNothing);

      await scene.close();
    });

    testWidgets('сбой записи: заметка Couldn\'t save the file.', (
      tester,
    ) async {
      final scene = await opened(tester);
      scene.saver.result = const UsageCsvFailed('FileSystemException');

      await scene.tapKey('usage-export');

      expect(find.text("Couldn't save the file."), findsOneWidget);

      await scene.close();
    });

    testWidgets('заметка о сбое записи сбрасывается при смене сессии в '
        'фокусе (D5)', (tester) async {
      final scene = await opened(tester);
      scene.saver.result = const UsageCsvFailed('FileSystemException');
      await scene.tapKey('usage-export');
      expect(find.text("Couldn't save the file."), findsOneWidget);

      await scene.newSession('s2');

      expect(scene.cubit.state.activeSessionId, 's2');
      expect(find.text("Couldn't save the file."), findsNothing);

      await scene.close();
    });
  });

  group('счётчик экземпляров панели (D3)', () {
    testWidgets('два экземпляра, старый размонтирован: автообновление после '
        'хода всё ещё уходит', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.snapshot();
      final showFirst = ValueNotifier<bool>(true);
      addTearDown(showFirst.dispose);
      await tester.pumpWidget(
        scene.binding.bootstrap(
          child: FluentApp(
            home: BlocProvider<CodeLabShellCubit>.value(
              value: scene.cubit,
              child: ValueListenableBuilder<bool>(
                valueListenable: showFirst,
                builder: (context, first, _) => Column(
                  children: [
                    if (first)
                      const Expanded(
                        child: WorkbenchUsagePane(key: ValueKey('first')),
                      ),
                    const Expanded(
                      child: WorkbenchUsagePane(key: ValueKey('second')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await scene.flush();
      await scene.answerLedger(_ledger());
      expect(scene.ledgerRequests, hasLength(1));

      showFirst.value = false;
      await scene.flush();
      await scene.snapshot(seq: 2);
      expect(scene.ledgerRequests, hasLength(2));

      await scene.close();
    });
  });
}
