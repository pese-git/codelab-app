// Widget-тесты панели Agents v1 в доке (задачи 5b.1, 5b.4 change
// `add-subagents-and-tasks`): agent-workbench-ui «Панель Agents v1» (сценарии
// «Панель появляется с первым субагентом», «Сторонний агент», «Ребёнок, внук
// и итог», «Ожидание одобрения и переход к нему», «Дерево шагов выбранного
// потомка», «Переход к строке в ленте», «Пункты списка у субагента»,
// «Загрузка сессии с субагентами», «Работающая строка в незанятой сессии»,
// «Запуск ждёт одобрения в панели», «Только данные v1») и «Tool dock with
// closable pane tabs» («Unavailable pane is hidden but kept in the layout»);
// design.md D33, D49 Т7–Т11, D50 п. 2–3.
//
// Ключи и тексты — из задач 5b.1 и 5b.3 (`agents-row-<toolCallId>`,
// `agents-go-to-approval-<toolCallId>`, `agents-show-in-transcript-<toolCallId>`,
// `transcript-row-<id>`, `CodeLabTranscriptPanel.targetKey` и `highlightKey`).
//
// Данные идут через настоящий граф app: сценарные `session/update` на
// `FakeAcpTransport` проходят kit и Cubit-ы (как в `workbench_shell_test`),
// поэтому тесты не знают, как kit строит строки. Решает «опасно ли» и выбирает
// исход пользователь в ленте (PERM-4): в панели Agents решения нет.
//
// Отдельно проверяются: панель Agents без строк не даёт переключателя и
// остаётся в раскладке; пункта палитры `agents` нет, пока панель недоступна.
// Группа «ревью итерации 5b» — переход к одобрению не решает, разовый запрос
// показа ленты.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:codelab_desktop/features/workbench/presentation/widgets/workbench_agents_pane.dart';
import 'package:codelab_desktop/l10n/app_localizations.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/l10n_app.dart';
import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

// ---------------------------------------------------------------------------
// Кадры агента (по образцу `codelab_client_core/test/session/
// session_subagents_test.dart`: признак субагента — `_meta.codelab.subagent`).
// ---------------------------------------------------------------------------

Map<String, Object?> _meta({
  String? parent,
  Map<String, Object?>? subagent,
  String? outcome,
}) => {
  'codelab': {
    'parentToolCallId': ?parent,
    'subagent': ?subagent,
    'outcome': ?outcome,
  },
};

/// Вызов `agent` (`think`, признак D28); [parent] — родитель на проводе.
Map<String, Object?> _agentCall(
  String id, {
  String? parent,
  String type = 'explore',
  String subagentId = 'sub_a1',
  String status = 'in_progress',
  String description = 'Find auth code',
  String? task,
  Map<String, Object?>? subagentExtra,
  String? outcome,
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': 'Subagent $type: $description',
  'kind': 'think',
  'status': status,
  'rawInput': {'type': type, 'description': description, 'task': ?task},
  '_meta': _meta(
    parent: parent,
    subagent: {'id': subagentId, 'type': type, ...?subagentExtra},
    outcome: outcome,
  ),
};

/// Обычный вызов потомка (или корня, если [parent] не задан).
Map<String, Object?> _call(
  String id, {
  String? parent,
  String kind = 'read',
  String status = 'completed',
  String? title,
  Map<String, Object?>? rawInput,
}) => {
  'sessionUpdate': 'tool_call',
  'toolCallId': id,
  'title': title ?? 'Read ${id.split('/').last}',
  'kind': kind,
  'status': status,
  'rawInput': ?rawInput,
  if (parent != null) '_meta': _meta(parent: parent),
};

/// Итоговое обновление вызова `agent`.
Map<String, Object?> _end(
  String id, {
  String status = 'completed',
  Map<String, Object?>? subagent,
  String? outcome,
}) => {
  'sessionUpdate': 'tool_call_update',
  'toolCallId': id,
  'status': status,
  if (subagent != null || outcome != null)
    '_meta': _meta(subagent: subagent, outcome: outcome),
};

Map<String, Object?> _summary(
  String id, {
  int toolCalls = 2,
  int input = 9000,
  int output = 1200,
  int ms = 19000,
}) => {
  'id': id,
  'summary': {
    'toolCalls': toolCalls,
    'tokens': {'input': input, 'output': output},
    'durationMs': ms,
  },
};

/// `_meta.codelab.subagent` запроса потомка (D8).
Map<String, Object?> _requester({
  required String id,
  required String type,
  required int depth,
  String parent = 'call_1',
}) => {
  'codelab': {
    'subagent': {
      'id': id,
      'type': type,
      'description': 'Find callers',
      'depth': depth,
      'path': const <String>[],
      'parentToolCallId': parent,
    },
  },
};

/// Строки ленты верхнего уровня, не относящиеся к тесту: уводят строку
/// `agent` корня за верхний край ленты, а блок одобрения — из видимой части.
List<Map<String, Object?>> _fillers(int count, {int from = 0}) => [
  for (var i = from; i < from + count; i++)
    _call(
      'filler$i',
      status: 'completed',
      rawInput: {'path': '/work/filler$i.dart'},
    ),
];

/// Ребёнок `review` (`call_1`) с вызовами `read` и внуком `explore`
/// (`call_1/call_2`), у которого один вызов `ls` — сценарий дерева шагов.
List<Map<String, Object?>> _childWithGrandchild() => [
  _agentCall(
    'call_1',
    type: 'review',
    description: 'Review the change',
    subagentId: 'sub_a1',
  ),
  _call('call_1/call_1', parent: 'call_1', rawInput: {'path': '/work/a1.dart'}),
  _call('call_1/call_3', parent: 'call_1', rawInput: {'path': '/work/a2.dart'}),
  _agentCall(
    'call_1/call_2',
    parent: 'call_1',
    type: 'explore',
    description: 'Find callers',
    subagentId: 'sub_b2',
  ),
  _call(
    'call_1/call_2/call_1',
    parent: 'call_1/call_2',
    kind: 'execute',
    rawInput: {'command': 'ls lib'},
    title: 'Run ls lib',
  ),
];

// ---------------------------------------------------------------------------
// Сцена: приложение, агент-двойник и шаги протокола.
// ---------------------------------------------------------------------------

/// Приложение в `testWidgets` и агент-двойник, чьи кадры тест играет сам.
///
/// Почему не `ShellHarness`: он рассчитан на обычные `test()`, а здесь нужны
/// кадры отрисовки; шаги протокола выполняются в `runAsync` (настоящий
/// event loop), а отрисовка — через `pump`, как в `workbench_shell_test`.
///
/// Как использовать: [open] → [newSession] → [startTurn] → [frames]; каждый
/// начатый ход тест завершает сам либо оставляет [close] (он ответит
/// `end_turn`, иначе закрытие графа оборвёт запрос).
final class _Scene {
  _Scene._(this.tester, this.binding, this.agent, this.cubit);

  final WidgetTester tester;
  final CodeLabTestBinding binding;
  final FakeAcpTransport agent;
  final CodeLabShellCubit cubit;

  JsonRpcRequest? _prompt;
  Future<void>? _turnDone;
  var _nextRequestId = 100;

  /// Поднимает приложение и подключает агента. [list] — страница ответа на
  /// `session/list` (агент тогда объявляет `loadSession`); [paneClock] —
  /// вместо всего приложения показывается только панель Agents с этими часами
  /// (тик внедряется в виджет, D49 Т9).
  static Future<_Scene> open(
    WidgetTester tester, {
    ListSessionsResponse? list,
    DateTime Function()? paneClock,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = FakeAcpTransport()
      ..initializeAgentCapabilities = list == null
          ? const AgentCapabilities()
          : const AgentCapabilities(
              loadSession: true,
              sessionCapabilities: SessionCapabilities(
                list: SessionListCapabilities(),
              ),
            );
    final binding = CodeLabTestBinding(
      project: '/work',
      stdioTransportFactory: (_) => agent,
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.pumpWidget(
      binding.bootstrap(
        child: paneClock == null
            ? const CodeLabApp(startOnLaunch: false)
            : FluentApp(
                localizationsDelegates: l10nTestDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: BlocProvider<CodeLabShellCubit>.value(
                  value: cubit,
                  child: ScaffoldPage(
                    padding: EdgeInsets.zero,
                    content: WorkbenchAgentsPane(clock: paneClock),
                  ),
                ),
              ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() async {
      final starting = cubit.startWith();
      if (list != null) {
        final request =
            await agent.sent.firstWhere(
                  (m) => m is JsonRpcRequest && m.method == sessionListMethod,
                )
                as JsonRpcRequest;
        agent.emitInbound(
          JsonRpcMessage.response(id: request.id, result: list.toJson()),
        );
      }
      await starting;
    });
    final scene = _Scene._(tester, binding, agent, cubit);
    await scene.flush();
    return scene;
  }

  /// Даёт доставить кадры и состояния Cubit-ов и перерисовать окно.
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

  /// Начинает ход: сессия становится занятой, пока тест не вызовет [endTurn].
  Future<void> startTurn() async {
    await tester.runAsync(() async {
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionPromptMethod,
      );
      _turnDone = cubit
          .submitPrompt('go')
          .then<void>((_) {}, onError: (Object _) {});
      _prompt = await sent as JsonRpcRequest;
    });
    await flush();
  }

  /// Завершает ход: `end_turn` или, с [failure], ошибка запроса (обрыв).
  Future<void> endTurn({bool failure = false}) async {
    final prompt = _prompt;
    if (prompt == null) {
      return;
    }
    _prompt = null;
    await tester.runAsync(() async {
      agent.emitInbound(
        failure
            ? JsonRpcMessage.response(
                id: prompt.id,
                error: const JsonRpcError(code: -32603, message: 'lost'),
              )
            : JsonRpcMessage.response(
                id: prompt.id,
                result: const {'stopReason': 'end_turn'},
              ),
      );
      await _turnDone;
    });
    await flush();
  }

  /// Кадры `session/update` сессии [sessionId] одним пакетом.
  Future<void> frames(
    Iterable<Map<String, Object?>> updates, {
    String sessionId = 's1',
  }) async {
    for (final update in updates) {
      agent.emitInbound(
        JsonRpcMessage.notification(
          method: sessionUpdateMethod,
          params: {'sessionId': sessionId, 'update': update},
        ),
      );
    }
    await flush();
  }

  /// Запрос разрешения: [meta] — `_meta` вызова (`null` — спрашивает корень).
  Future<void> ask(
    String toolCallId, {
    Map<String, Object?>? meta,
    ToolKind kind = ToolKind.execute,
    String command = 'git diff --stat',
    String sessionId = 's1',
  }) async {
    agent.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(_nextRequestId++),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: SessionId(sessionId),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId(toolCallId),
            title: 'Run $command',
            kind: kind,
            status: ToolCallStatus.pending,
            rawInput: {'command': command},
            meta: meta,
          ),
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow',
              kind: PermissionOptionKind.allowOnce,
            ),
            PermissionOption(
              optionId: PermissionOptionId('reject-once'),
              name: 'Reject',
              kind: PermissionOptionKind.rejectOnce,
            ),
          ],
        ).toJson(),
      ),
    );
    await flush();
  }

  /// Выбор сессии из сайдбара с загрузкой: [replay] проигрывается как реплей.
  Future<void> loadSession(String id, List<Map<String, Object?>> replay) async {
    await tester.runAsync(() async {
      final sent = agent.sent.firstWhere(
        (m) => m is JsonRpcRequest && m.method == sessionLoadMethod,
      );
      cubit.selectSession(id);
      final request = await sent as JsonRpcRequest;
      for (final update in replay) {
        agent.emitInbound(
          JsonRpcMessage.notification(
            method: sessionUpdateMethod,
            params: {'sessionId': id, 'update': update},
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      agent.emitInbound(
        JsonRpcMessage.response(
          id: request.id,
          result: const <String, Object?>{},
        ),
      );
    });
    await flush();
  }

  /// Завершает ход и закрывает граф.
  Future<void> close() async {
    await endTurn();
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }

  // --- Поиск ---

  Finder get toggle => find.byKey(CodeLabAppBar.toggleKey(ToolPane.agents));

  Finder get pane => find.byKey(CodeLabToolDock.paneKey(ToolPane.agents));

  Finder rowOf(String toolCallId) =>
      find.byKey(ValueKey('agents-row-$toolCallId'));

  Finder get anyRow => find.byWidgetPredicate((w) {
    final key = w.key;
    return key is ValueKey<String> && key.value.startsWith('agents-row-');
  });

  Finder showInTranscript(String toolCallId) =>
      find.byKey(ValueKey('agents-show-in-transcript-$toolCallId'));

  Finder goToApproval(String toolCallId) =>
      find.byKey(ValueKey('agents-go-to-approval-$toolCallId'));

  Finder get transcript => find.byType(CodeLabTranscriptPanel);

  /// Весь видимый текст под [scope] одной строкой.
  String textOf(Finder scope) => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(of: scope, matching: find.byType(RichText)),
    ))
      w.text.toPlainText(),
  ].join(' | ');

  /// Цель целиком внутри видимой части ленты (лента ленива: непостроенная
  /// строка не найдена, построенная вне окна — найдена, но вне прямоугольника).
  bool inTranscriptView(Finder target) {
    if (target.evaluate().isEmpty) {
      return false;
    }
    final view = tester.getRect(transcript);
    final rect = tester.getRect(target.first);
    return rect.top >= view.top - 1 && rect.bottom <= view.bottom + 1;
  }

  /// Строки ленты верхнего уровня и вложенные — для id строк маппера.
  List<CodeLabToolCallRow> get toolRows => [
    for (final row in cubit.state.transcriptRows)
      if (row is CodeLabToolCallRow) row,
  ];

  /// Строка `agent` корневого уровня в ленте (первая с признаком субагента).
  CodeLabToolCallRow get rootAgentRow =>
      toolRows.firstWhere((row) => row.subagent != null);

  /// Переключатель Agents в app bar: открывает панель.
  Future<void> openPaneByToggle() async {
    tester.widget<ToggleButton>(toggle).onChanged!(true);
    await flush();
  }

  Future<void> tapKey(Finder finder) async {
    await tester.tap(finder);
    await flush();
  }
}

/// Секунды из текста строки панели (`19s`); `null` — времени в тексте нет.
int? _secondsIn(String text) {
  final match = RegExp(r'(?<![\d.])(\d+)s\b').firstMatch(text);
  return match == null ? null : int.parse(match.group(1)!);
}

void main() {
  group('доступность панели Agents (D49 Т11)', () {
    testWidgets('«Панель появляется с первым субагентом»: до первого кадра '
        'вызова переключателя нет, после него есть, а открытая панель '
        'показывает строку running и «Subagents · 1 running»', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      expect(scene.toggle, findsNothing);

      await scene.frames([_agentCall('call_1')]);

      expect(scene.toggle, findsOneWidget);
      await scene.openPaneByToggle();
      expect(scene.pane, findsOneWidget);
      final row = scene.rowOf('call_1');
      expect(row, findsOneWidget);
      final text = scene.textOf(row);
      expect(text, contains('explore'));
      expect(text, contains('Find auth code'));
      expect(text, contains('running'));
      final heading = scene.textOf(scene.pane);
      expect(heading, contains('Subagents'));
      expect(heading, contains('1 running'));

      await scene.close();
    });

    testWidgets('«Сторонний агент»: вызов think без признака не даёт '
        'переключателя и вкладки, сохранённая панель остаётся в раскладке', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      scene.cubit.openPane(ToolPane.agents);
      await scene.newSession('s1');
      await scene.startTurn();

      await scene.frames([
        {
          'sessionUpdate': 'tool_call',
          'toolCallId': 'call_1',
          'title': 'Subagent explore: Find auth code',
          'kind': 'think',
          'status': 'in_progress',
          'rawInput': {'type': 'explore', 'description': 'Find auth code'},
        },
      ]);

      expect(scene.toggle, findsNothing);
      expect(scene.pane, findsNothing);
      expect(scene.cubit.state.openPanes, contains(ToolPane.agents));
      // Вызов — обычная строка ленты, не строка субагента.
      expect(scene.toolRows.single.subagent, isNull);

      await scene.close();
    });

    testWidgets('сохранённая открытая панель Agents без строк не даёт вкладки '
        'и переключателя и остаётся в раскладке («Unavailable pane is hidden '
        'but kept in the layout»)', (tester) async {
      final scene = await _Scene.open(tester);
      scene.cubit
        ..openPane(ToolPane.agents)
        ..openPane(ToolPane.plan);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.flush();

      expect(scene.toggle, findsNothing);
      expect(scene.pane, findsNothing);
      expect(
        find.byKey(CodeLabToolDock.paneKey(ToolPane.plan)),
        findsOneWidget,
        reason: 'the dock shows only the available panes',
      );
      expect(
        scene.cubit.state.openPanes,
        containsAll([ToolPane.agents, ToolPane.plan]),
      );

      await scene.close();
    });

    testWidgets('сохранённая панель Agents возвращается вместе с первой '
        'строкой субагента', (tester) async {
      final scene = await _Scene.open(tester);
      scene.cubit
        ..openPane(ToolPane.agents)
        ..openPane(ToolPane.plan);
      await scene.newSession('s1');
      await scene.startTurn();
      expect(scene.pane, findsNothing);

      await scene.frames([_agentCall('call_1')]);

      expect(scene.toggle, findsOneWidget);
      scene.cubit.selectPane(ToolPane.agents);
      await scene.flush();
      expect(scene.pane, findsOneWidget);
      expect(scene.rowOf('call_1'), findsOneWidget);

      await scene.close();
    });

    testWidgets('пункта палитры `agents` нет, пока панель недоступна', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();

      expect([
        for (final action in scene.cubit.state.paletteActions) action.id,
      ], isNot(contains('agents')));

      await scene.close();
    });

    testWidgets('пункт палитры `agents` появляется с панелью и открывает её '
        '(D49 Т11)', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();

      await scene.frames([_agentCall('call_1')]);

      expect([
        for (final action in scene.cubit.state.paletteActions) action.id,
      ], contains('agents'));

      scene.cubit.openCommandPalette();
      await scene.flush();
      await tester.enterText(
        find.byKey(CodeLabCommandPaletteSurface.queryFieldKey),
        'agents',
      );
      await scene.flush();
      final item = find.descendant(
        of: find.byKey(CodeLabCommandPaletteSurface.listKey),
        matching: find.text('Agents'),
      );
      expect(item, findsOneWidget);
      await scene.tapKey(item);

      expect(scene.cubit.state.isCommandPaletteOpen, isFalse);
      expect(scene.pane, findsOneWidget);

      await scene.close();
    });
  });

  group('строки панели', () {
    testWidgets('«Ребёнок, внук и итог»: строка внука под строкой ребёнка с '
        'отступом, `done`, «2 tool calls», «10.2k», «19s»; ребёнок — '
        '`running`', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([
        ..._childWithGrandchild(),
        _call(
          'call_1/call_2/call_2',
          parent: 'call_1/call_2',
          rawInput: {'path': '/work/b.dart'},
        ),
        _end('call_1/call_2', subagent: _summary('sub_b2')),
      ]);
      await scene.openPaneByToggle();

      final child = scene.rowOf('call_1');
      final grandchild = scene.rowOf('call_1/call_2');
      expect(child, findsOneWidget);
      expect(grandchild, findsOneWidget);
      expect(
        tester.getTopLeft(grandchild).dy,
        greaterThan(tester.getTopLeft(child).dy),
      );
      final childTextLeft = tester
          .getTopLeft(
            find.descendant(
              of: child,
              matching: find.textContaining('review', findRichText: true),
            ),
          )
          .dx;
      final grandchildTextLeft = tester
          .getTopLeft(
            find.descendant(
              of: grandchild,
              matching: find.textContaining('explore', findRichText: true),
            ),
          )
          .dx;
      expect(grandchildTextLeft, greaterThan(childTextLeft));
      final text = scene.textOf(grandchild);
      expect(text, contains('done'));
      expect(text, contains('2 tool calls'));
      expect(text, contains('10.2k'));
      expect(text, contains('19s'));
      expect(scene.textOf(child), contains('running'));

      await scene.close();
    });

    testWidgets('«Ожидание одобрения и переход к нему»: внук ждёт, «Go to '
        'approval» прокручивает ленту к блоку «explore wants to run», строка '
        'корня остаётся свёрнутой, «Allow» возвращает `running`', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([
        ..._childWithGrandchild(),
        _call(
          'call_1/call_2/call_3',
          parent: 'call_1/call_2',
          kind: 'execute',
          status: 'pending',
          rawInput: {'command': 'git diff --stat'},
        ),
      ]);
      await scene.ask(
        'call_1/call_2/call_3',
        meta: _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );
      // Строки после вопроса уводят блок одобрения из видимой части ленты.
      await scene.frames(_fillers(60));
      await scene.openPaneByToggle();

      final grandchild = scene.rowOf('call_1/call_2');
      expect(scene.textOf(grandchild), contains('waiting for approval'));
      expect(scene.textOf(scene.pane), contains('1 waiting for approval'));
      final block = find.textContaining(
        'explore wants to run',
        findRichText: true,
      );
      expect(scene.inTranscriptView(block), isFalse);

      await scene.tapKey(scene.goToApproval('call_1/call_2'));

      expect(scene.inTranscriptView(block), isTrue);
      // Блок стоит под строкой корня, а сама она не раскрыта пользователем.
      expect(
        scene.cubit.state.transcriptExpansion[scene.rootAgentRow.id],
        isNot(isTrue),
      );

      await scene.tapKey(
        find.descendant(of: scene.transcript, matching: find.text('Allow')),
      );

      expect(scene.textOf(grandchild), contains('running'));
      expect(scene.textOf(grandchild), isNot(contains('waiting')));

      await scene.close();
    });

    testWidgets('«Запуск ждёт одобрения в панели»: корень спрашивает про '
        'запуск `agent`; строка ждёт, «Go to approval» ведёт к строке этого '
        'вызова с панелью решения, после «Allow» — `running`', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([_agentCall('call_1', status: 'pending')]);
      await scene.ask('call_1', kind: ToolKind.think, command: 'agent explore');
      await scene.frames(_fillers(60));
      await scene.openPaneByToggle();

      final row = scene.rowOf('call_1');
      expect(scene.textOf(row), contains('waiting for approval'));
      expect(scene.textOf(scene.pane), contains('1 waiting for approval'));
      final rootRow = find.byKey(
        CodeLabTranscriptPanel.rowKey(scene.rootAgentRow.id),
      );
      expect(scene.inTranscriptView(rootRow), isFalse);

      await scene.tapKey(scene.goToApproval('call_1'));

      expect(scene.inTranscriptView(rootRow), isTrue);
      await scene.tapKey(
        find.descendant(of: scene.transcript, matching: find.text('Allow')),
      );
      expect(scene.textOf(row), contains('running'));
      expect(scene.textOf(row), isNot(contains('waiting')));

      await scene.close();
    });

    testWidgets('«Дерево шагов выбранного потомка»: выбор `review` рисует '
        'вызовы, внука и его `ls`; выбор переживает смену вкладки на Plan и '
        'обратно', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames(_childWithGrandchild());
      await scene.openPaneByToggle();

      // Без выбранной строки дерева нет, заглушек тоже (D49 Т8).
      expect(
        find.descendant(
          of: scene.pane,
          matching: find.textContaining('a1.dart', findRichText: true),
        ),
        findsNothing,
      );

      await scene.tapKey(scene.rowOf('call_1'));

      String tree() => scene.textOf(scene.pane);
      expect(tree(), contains('a1.dart'));
      expect(tree(), contains('a2.dart'));
      expect(tree(), contains('Subagent explore: Find callers'));
      expect(tree(), contains('ls lib'));

      scene.cubit.openPane(ToolPane.plan);
      await scene.flush();
      expect(scene.pane, findsNothing);
      scene.cubit.selectPane(ToolPane.agents);
      await scene.flush();

      expect(tree(), contains('a1.dart'));
      expect(tree(), contains('ls lib'));

      await scene.close();
    });

    testWidgets('«Пункты списка у субагента»: пункт `#2` с владельцем — id '
        'субагента показан меткой с подсказкой «Check callers»', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([
        _agentCall('call_1', subagentId: 'sub_a1'),
        {
          'sessionUpdate': 'plan',
          'entries': [
            for (final (id, content, owner) in const [
              ('1', 'Read the code', 'main'),
              ('2', 'Check callers', 'sub_a1'),
            ])
              {
                'content': content,
                'status': 'pending',
                'priority': 'medium',
                '_meta': {
                  'codelab': {
                    'task': {'id': id, 'owner': owner},
                  },
                },
              },
          ],
        },
      ]);
      await scene.openPaneByToggle();

      final row = scene.rowOf('call_1');
      expect(scene.textOf(row), contains('#2'));
      expect(scene.textOf(row), isNot(contains('#1')));
      expect(
        find.descendant(
          of: row,
          matching: find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == 'Check callers',
          ),
        ),
        findsOneWidget,
      );

      await scene.close();
    });

    testWidgets('«Только данные v1»: у работающего субагента нет шагов, '
        'стоимости, «Stop», «Open transcript», «Message» и «Background '
        'jobs»', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([_agentCall('call_1')]);
      await scene.openPaneByToggle();

      expect(scene.rowOf('call_1'), findsOneWidget);
      final text = scene.textOf(scene.pane);
      for (final absent in const [
        'Stop',
        'Open transcript',
        'Message',
        'Background jobs',
        'cost',
        r'$',
        'steps',
      ]) {
        expect(text, isNot(contains(absent)), reason: absent);
      }

      await scene.close();
    });
  });

  group('переход к ленте (D49 Т7)', () {
    testWidgets('«Переход к строке в ленте»: «Show in transcript» строки '
        'верхнего уровня прокручивает к ней и подсвечивает на время; повтор '
        'после ухода прокручивает снова; новые строки не возвращают ленту '
        'к низу', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([_agentCall('call_1'), ..._fillers(60)]);
      await scene.openPaneByToggle();

      final id = scene.rootAgentRow.id;
      final rowKey = CodeLabTranscriptPanel.rowKey(id);
      expect(scene.inTranscriptView(find.byKey(rowKey)), isFalse);

      await scene.tapKey(scene.showInTranscript('call_1'));
      await tester.pump(const Duration(milliseconds: 300));

      expect(scene.inTranscriptView(find.byKey(rowKey)), isTrue);
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey(id)),
        findsOneWidget,
      );

      // Пришёл новый кадр: лента в режиме чтения истории, к низу не уходит.
      await scene.frames(_fillers(3, from: 100));
      expect(scene.inTranscriptView(find.byKey(rowKey)), isTrue);

      // Подсветка короткая (около 1,5 с).
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(CodeLabTranscriptPanel.highlightKey(id)), findsNothing);

      // Пользователь ушёл вниз; тот же запрос снова приводит к строке.
      await tester.drag(scene.transcript, const Offset(0, -5000));
      await scene.flush();
      await scene.tapKey(scene.showInTranscript('call_1'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scene.inTranscriptView(find.byKey(rowKey)), isTrue);

      await scene.close();
    });

    testWidgets('«Show in transcript» у строки внука раскрывает путь и '
        'прокручивает к его вложенной строке `agent`', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([..._childWithGrandchild(), ..._fillers(60)]);
      await scene.openPaneByToggle();

      final root = scene.rootAgentRow;
      final nested = root.children.whereType<CodeLabToolCallRow>().singleWhere(
        (row) => row.subagent != null,
      );
      final target = find.byKey(CodeLabTranscriptPanel.targetKey(nested.id));
      expect(scene.inTranscriptView(target), isFalse);

      await scene.tapKey(scene.showInTranscript('call_1/call_2'));
      await tester.pump(const Duration(milliseconds: 300));

      // Строка корня раскрыта явным действием пользователя (D33).
      expect(scene.cubit.state.transcriptExpansion[root.id], isTrue);
      expect(scene.inTranscriptView(target), isTrue);

      await scene.close();
    });
  });

  group('сессии и время', () {
    testWidgets('«Загрузка сессии с субагентами»: два вызова — `done` и '
        '`cancelled` — дают две строки с итогом и без растущего времени; '
        'повторный выбор сессии не удваивает строки', (tester) async {
      final scene = await _Scene.open(
        tester,
        list: const ListSessionsResponse(
          sessions: [SessionInfo(sessionId: SessionId('s-old'), cwd: '/work')],
        ),
      );
      expect(scene.toggle, findsNothing);

      await scene.loadSession('s-old', [
        {
          'sessionUpdate': 'user_message_chunk',
          'content': {'type': 'text', 'text': 'explore it'},
        },
        _agentCall(
          'call_1',
          status: 'completed',
          subagentExtra: {
            'summary': {
              'toolCalls': 4,
              'tokens': {'input': 15200, 'output': 3000},
              'durationMs': 48000,
            },
          },
        ),
        _agentCall(
          'call_2',
          status: 'failed',
          outcome: 'cancelled',
          subagentId: 'sub_a2',
          subagentExtra: {
            'summary': {
              'toolCalls': 2,
              'tokens': {'input': 900, 'output': 100},
              'durationMs': 4000,
            },
          },
        ),
      ]);

      expect(scene.cubit.state.activeSessionId, 's-old');
      expect(scene.toggle, findsOneWidget);
      await scene.openPaneByToggle();
      expect(scene.anyRow, findsNWidgets(2));
      expect(scene.textOf(scene.rowOf('call_1')), contains('done'));
      expect(scene.textOf(scene.rowOf('call_1')), contains('4 tool calls'));
      expect(scene.textOf(scene.rowOf('call_1')), contains('48s'));
      expect(scene.textOf(scene.rowOf('call_2')), contains('cancelled'));
      expect(scene.textOf(scene.rowOf('call_2')), contains('4s'));
      final before = scene.textOf(scene.pane);

      // Время завершённых строк — из итога, оно не растёт.
      await tester.pump(const Duration(seconds: 5));
      expect(scene.textOf(scene.pane), before);

      scene.cubit.selectSession('s-old');
      await scene.flush();
      expect(scene.anyRow, findsNWidgets(2));

      await scene.close();
    });

    testWidgets('«Работающая строка в незанятой сессии»: после сбоя хода '
        'строка остаётся `running` без времени и учтена в «1 running»', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([_agentCall('call_1')]);
      await scene.openPaneByToggle();
      await scene.endTurn(failure: true);

      final row = scene.rowOf('call_1');
      expect(row, findsOneWidget);
      expect(scene.textOf(row), contains('running'));
      expect(_secondsIn(scene.textOf(row)), isNull);
      expect(scene.textOf(scene.pane), contains('1 running'));

      await tester.pump(const Duration(seconds: 3));
      expect(_secondsIn(scene.textOf(scene.rowOf('call_1'))), isNull);

      await scene.close();
    });

    testWidgets('тик раз в секунду на внедрённых часах виджета (D49 Т9): '
        'время работающей строки растёт, пока сессия занята, и пропадает '
        'вместе с занятостью', (tester) async {
      // Начало строки kit берёт из `DateTime.now`, а часы виджета тест ведёт
      // сам: [base] снят до запуска, сдвиг [offset] не зависит от скорости
      // прогона, и разность целых секунд до и после тика ровно 3.
      final base = DateTime.now();
      var offset = const Duration(seconds: 10);
      final scene = await _Scene.open(
        tester,
        paneClock: () => base.add(offset),
      );
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([_agentCall('call_1')]);
      scene.cubit.openPane(ToolPane.agents);
      await scene.flush();

      final first = _secondsIn(scene.textOf(scene.rowOf('call_1')));
      expect(first, isNotNull, reason: 'a running row of a busy session');

      offset += const Duration(seconds: 3);
      await tester.pump(const Duration(seconds: 3));

      expect(_secondsIn(scene.textOf(scene.rowOf('call_1'))), first! + 3);

      await scene.endTurn();
      offset += const Duration(seconds: 5);
      await tester.pump(const Duration(seconds: 5));

      final idle = scene.textOf(scene.rowOf('call_1'));
      expect(idle, contains('running'));
      expect(_secondsIn(idle), isNull);

      await scene.close();
    });
  });

  group('ревью итерации 5b', () {
    /// Два внука `explore` и `search` под ребёнком `review`; каждый ждёт
    /// одобрения своего `exec`. Возвращает `approvalId` обоих.
    Future<(String, String)> twoWaiting(_Scene scene) async {
      await scene.frames([
        ..._childWithGrandchild(),
        _agentCall(
          'call_1/call_4',
          parent: 'call_1',
          type: 'search',
          description: 'Find usages',
          subagentId: 'sub_c3',
        ),
        _call(
          'call_1/call_2/call_3',
          parent: 'call_1/call_2',
          kind: 'execute',
          status: 'pending',
          rawInput: {'command': 'git diff --stat'},
        ),
        _call(
          'call_1/call_4/call_5',
          parent: 'call_1/call_4',
          kind: 'execute',
          status: 'pending',
          rawInput: {'command': 'git log'},
        ),
      ]);
      await scene.ask(
        'call_1/call_2/call_3',
        meta: _requester(id: 'sub_b2', type: 'explore', depth: 2),
      );
      await scene.ask(
        'call_1/call_4/call_5',
        command: 'git log',
        meta: _requester(id: 'sub_c3', type: 'search', depth: 2),
      );
      await scene.frames(_fillers(60));
      final explore = scene.cubit.state.agents
          .rowOf('call_1/call_2')
          ?.approvalId
          ?.value;
      final search = scene.cubit.state.agents
          .rowOf('call_1/call_4')
          ?.approvalId
          ?.value;
      return (explore!, search!);
    }

    testWidgets('«Go to approval» не принимает решение: запрос остаётся '
        'ожидающим, ответ на `session/request_permission` не отправлен', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      final (explore, _) = await twoWaiting(scene);
      await scene.openPaneByToggle();
      final focusBefore = FocusManager.instance.primaryFocus;
      int responses() =>
          scene.agent.sentMessages.whereType<JsonRpcResponse>().length;
      final before = responses();

      await scene.tapKey(scene.goToApproval('call_1/call_2'));

      expect(responses(), before);
      expect(
        scene.cubit.state.agents.rowOf('call_1/call_2')?.approvalId?.value,
        explore,
      );
      expect(scene.textOf(scene.rowOf('call_1/call_2')), contains('waiting'));
      expect(scene.textOf(scene.rowOf('call_1/call_4')), contains('waiting'));
      // Фокус остался там, где был: клавиши решения не получили его.
      expect(FocusManager.instance.primaryFocus, same(focusBefore));

      await scene.close();
    });

    testWidgets('кнопка шага «Go to approval» ведёт к блоку одобрения шага', (
      tester,
    ) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      final (explore, _) = await twoWaiting(scene);
      await scene.openPaneByToggle();
      await scene.tapKey(scene.rowOf('call_1'));

      // Id шага — id элемента ленты, которому принадлежит одобрение.
      final stepId = scene.cubit.state.agents.pendingApprovals.entries
          .firstWhere((entry) => entry.value == explore)
          .key;
      expect(
        find.byKey(CodeLabAgentsPane.stepGoToApprovalKey(stepId)),
        findsOneWidget,
      );
      // Ссылка шага в узком доке уходит за край окна, поэтому нажатие
      // вызывает колбэк, который панель отдала организму.
      tester
          .widget<CodeLabAgentsPane>(find.byType(CodeLabAgentsPane))
          .onStepGoToApproval!(stepId);
      await scene.flush();

      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey(explore)),
        findsOneWidget,
      );

      await scene.close();
    });

    testWidgets('два ожидающих одобрения: переход ведёт к блоку своего '
        '`approvalId`', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      final (explore, search) = await twoWaiting(scene);
      await scene.openPaneByToggle();
      expect(explore, isNot(search));

      await scene.tapKey(scene.goToApproval('call_1/call_4'));
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey(search)),
        findsOneWidget,
      );
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey(explore)),
        findsNothing,
      );

      await tester.pump(const Duration(seconds: 3));
      await scene.tapKey(scene.goToApproval('call_1/call_2'));
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey(explore)),
        findsOneWidget,
      );
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey(search)),
        findsNothing,
      );

      await scene.close();
    });

    testWidgets('запрос показа гаснет, когда лента закончила показ: '
        'в состоянии запроса нет', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([_agentCall('call_1'), ..._fillers(60)]);
      await scene.openPaneByToggle();
      final rowKey = CodeLabTranscriptPanel.rowKey(scene.rootAgentRow.id);

      await scene.tapKey(scene.showInTranscript('call_1'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(scene.inTranscriptView(find.byKey(rowKey)), isTrue);
      expect(scene.cubit.state.transcriptShowRequest, isNull);

      // Запроса в состоянии нет: перемонтированная лента (новый `State`)
      // получила бы `showRequest == null` и не прокрутила бы снова.
      expect(
        find.byKey(CodeLabTranscriptPanel.highlightKey(scene.rootAgentRow.id)),
        findsOneWidget,
      );

      await scene.close();
    });

    testWidgets('запрос показа разовый: после ухода в другую сессию и '
        'возврата его в состоянии нет', (tester) async {
      final scene = await _Scene.open(tester);
      await scene.newSession('s1');
      await scene.startTurn();
      await scene.frames([_agentCall('call_1'), ..._fillers(60)]);
      await scene.openPaneByToggle();

      await scene.tapKey(scene.showInTranscript('call_1'));

      await scene.newSession('s2');
      expect(scene.cubit.state.transcriptShowRequest, isNull);

      scene.cubit.selectSession('s1');
      await scene.flush();
      expect(scene.cubit.state.activeSessionId, 's1');
      expect(scene.cubit.state.transcriptShowRequest, isNull);

      await scene.close();
    });
  });
}
