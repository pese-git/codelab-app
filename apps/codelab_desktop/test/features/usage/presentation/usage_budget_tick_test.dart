// Widget-тесты задачи 3.3 change `add-desktop-usage-pane`: тик блока
// `Turn budget` в `WorkbenchUsagePane(clock:)` (agent-workbench-ui «Бюджет
// хода в панели Usage»: «Время идёт между шагами», «Таймер только при
// показанной панели», «Начало нового хода»; design.md, D9, Q11 (а); образец —
// тик панели Agents, D49 Т9).
//
// Тик не виден снаружи сам по себе: его наблюдают по обращениям к часам
// виджета. Построение зовёт `clock` один раз, поэтому счётчик `clockCalls`
// растёт на тик, пока ничего другого панель не перестраивает. Видимый эффект —
// подпись строки Time (`usage-budget-time`), которая считается на момент
// `now` из `receivedAt` снимка.
//
// Часы: kit в графе app берёт `DateTime.now` (внедрить свои часы в рабочее
// пространство через корневой scope пока нельзя), поэтому `receivedAt` берётся
// из состояния фасада, а часы виджета строятся от него: `receivedAt +
// offset`. Так «один источник» достигается без второго поддельного таймера
// в kit. Время Flutter-таймера ведёт `tester.pump(Duration)`.
//
// Задача 2.5 change `fix-usage-pane-live-cards` (agent-workbench-ui «Бюджет
// хода в панели Usage»: «Одобрение не откатывает время», «Одобрение
// субагента», «Отмена хода»; design.md D3–D5, Q2 (б), Q4 (а)): запрос
// одобрения корня останавливает тик, а Time не уменьшается; ответ возобновляет
// тик без прыжка на длину ожидания; одобрение потомка тик не останавливает;
// `cancelling` тикает до снимка `turn`. Метки ожиданий ставит `AcpClientApplication`
// по системным часам, поэтому тесты этой группы работают на настоящем времени
// (`realClock`, короткие реальные паузы через `runAsync`): с условными часами
// виджета метки одобрений и `receivedAt` разошлись бы. Точные секунды и
// объединения интервалов проверяет `usage_budget_test.dart` на собранных
// вручную `SessionView`.
//
// Панель монтируется напрямую (без дока): «показана» значит «смонтирована»
// (D3), а скрытие — размонтирование. Решение «тикать ли» принимает application
// (`UsageBudgetData.ticking`), виджет только следует ему; его проверяют тесты
// `usage_budget_test.dart`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show ApprovalRequestId;
import 'package:codelab_desktop/features/usage/presentation/workbench_usage_pane.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

const _usageOnly = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

Map<String, Object?> _tokens(int input, int output) => {
  'input': input,
  'output': output,
  'cacheRead': 0,
  'cacheWrite': 0,
};

/// Бюджет снимка: `3 / 50`, `92.0k / 200.0k`, `$0.41 / $0.50`, Time `3:00 /
/// 10:00` (`usedMs` — [usedMs]); [duration] `false` — без лимита времени.
Map<String, Object?> _budgetJson({int usedMs = 180000, bool duration = true}) =>
    {
      'steps': {'used': 3, 'limit': 50},
      'tokens': {'used': 92000, 'limit': 200000},
      'cost': {'used': '0.41', 'limit': '0.5'},
      if (duration) 'duration': {'usedMs': usedMs, 'limitMs': 600000},
    };

/// Снимок `_codelab/session/usage` сессии `s1`: [trigger] — `step` или
/// `turn`; `turn` — итог хода (признак `ended`, Q11 (а)).
Map<String, Object?> _snapshot({
  required int seq,
  required String trigger,
  required String turnId,
  required Map<String, Object?> budget,
}) => {
  'sessionId': 's1',
  'seq': seq,
  'trigger': trigger,
  'turnId': turnId,
  'turn': {'steps': 1, 'tokens': _tokens(100, 20), 'cost': '0.5'},
  'session': {
    'turns': 1,
    'steps': 1,
    'tokens': _tokens(100, 20),
    'cost': '0.5',
  },
  'currency': 'USD',
  'budget': budget,
};

/// Приложение без дока: панель Usage в `ScaffoldPage`, агент-двойник, шаги
/// протокола и поддельные часы виджета.
final class _Scene {
  _Scene._(this.tester, this.binding, this.agent, this.cubit, this.shown);

  final WidgetTester tester;
  final CodeLabTestBinding binding;
  final FakeAcpTransport agent;
  final CodeLabShellCubit cubit;

  /// Панель смонтирована (док показывает вкладку) — переключается тестом.
  final ValueNotifier<bool> shown;

  /// Сколько раз панель спрашивала часы: прирост без других причин
  /// перестроения — число тиков.
  int clockCalls = 0;

  /// Момент `receivedAt` последнего снимка: точка отсчёта часов виджета.
  DateTime? _base;

  /// Сдвиг часов виджета от [_base]; тест двигает его вместе с `pump`.
  Duration offset = Duration.zero;

  /// Часы виджета — настоящее время: метки одобрений kit тоже настоящие,
  /// поэтому тесты ожиданий не смешивают условное и системное время.
  bool realClock = false;

  JsonRpcRequest? _prompt;
  Future<void>? _turnDone;

  DateTime _clock() {
    clockCalls++;
    if (realClock) return DateTime.now();
    return (_base ?? DateTime.now()).add(offset);
  }

  static Future<_Scene> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = FakeAcpTransport()..initializeAgentCapabilities = _usageOnly;
    final binding = CodeLabTestBinding(
      project: '/work',
      stdioTransportFactory: (_) => agent,
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    final shown = ValueNotifier<bool>(true);
    late final _Scene scene;
    await tester.pumpWidget(
      binding.bootstrap(
        child: FluentApp(
          home: BlocProvider<CodeLabShellCubit>.value(
            value: cubit,
            child: ScaffoldPage(
              padding: EdgeInsets.zero,
              content: ValueListenableBuilder<bool>(
                valueListenable: shown,
                builder: (context, on, _) => on
                    ? WorkbenchUsagePane(clock: () => scene._clock())
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(() => cubit.startWith());
    scene = _Scene._(tester, binding, agent, cubit, shown);
    await scene.flush();
    await scene.newSession('s1');
    return scene;
  }

  Future<void> flush() async {
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
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

  /// Начинает ход: сессия `running`, пока тест не вызовет [endTurn].
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

  /// Завершает ход ответом `end_turn`.
  Future<void> endTurn() async {
    final prompt = _prompt;
    if (prompt == null) return;
    _prompt = null;
    await tester.runAsync(() async {
      agent.emitInbound(
        JsonRpcMessage.response(
          id: prompt.id,
          result: const {'stopReason': 'end_turn'},
        ),
      );
      await _turnDone;
    });
    await flush();
  }

  /// Присылает снимок usage и берёт его `receivedAt` за начало отсчёта часов
  /// виджета (сдвиг сбрасывается).
  Future<void> snapshot(Map<String, Object?> params) async {
    // Построение при применении снимка идёт до того, как тест узнает его
    // `receivedAt`: часы виджета на этот момент ставятся на настоящее время
    // (часы kit в графе app — `DateTime.now`), иначе сдвиг прошлого снимка
    // дал бы `now − receivedAt` в секунды и подпись «0:08» вместо «0:04».
    _base = DateTime.now();
    offset = Duration.zero;
    agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: params,
      ),
    );
    await flush();
    final received = cubit.state.usage.budget?.time?.receivedAt;
    if (received != null) {
      _base = received;
      offset = Duration.zero;
    }
  }

  /// Запрос разрешения у агента: у сессии появляется ожидающее одобрение;
  /// [meta] — `_meta` вызова (`null` — спрашивает корень, иначе потомок).
  /// Идентификатор одобрения — `permission-<rpcId>`.
  Future<void> ask({int rpcId = 100, Map<String, Object?>? meta}) async {
    agent.emitInbound(
      JsonRpcMessage.request(
        id: JsonRpcId.integer(rpcId),
        method: sessionRequestPermissionMethod,
        params: RequestPermissionRequest(
          sessionId: const SessionId('s1'),
          toolCall: ToolCallUpdate(
            toolCallId: ToolCallId('call-$rpcId'),
            title: 'Run ls',
            kind: ToolKind.execute,
            status: ToolCallStatus.pending,
            rawInput: const {'command': 'ls'},
            meta: meta,
          ),
          options: const [
            PermissionOption(
              optionId: PermissionOptionId('allow-once'),
              name: 'Allow',
              kind: PermissionOptionKind.allowOnce,
            ),
          ],
        ).toJson(),
      ),
    );
    await flush();
  }

  /// Ответ пользователя на одобрение [rpcId]: интервал ожидания закрывается.
  Future<void> respond({int rpcId = 100}) async {
    await tester.runAsync(
      () => cubit.respondToApproval(
        approvalId: ApprovalRequestId('permission-$rpcId'),
        sessionId: const SessionId('s1'),
        optionId: 'allow-once',
      ),
    );
    await flush();
  }

  /// Отмена хода пользователем: сессия `cancelling` до ответа на промпт.
  Future<void> cancel() async {
    await tester.runAsync(cubit.cancelTurn);
    await flush();
  }

  /// Реальная пауза: системные часы идут, а таймеры теста стоят.
  Future<void> realWait(int ms) =>
      tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));

  /// Секунды из подписи Time (`m:ss / …`); `null` — строки Time нет.
  int? get timeSeconds {
    // В `time` перед числами стоит подпись строки (`Time | 3:00 / 10:00`).
    final match = RegExp(r'(\d+(?::\d\d)+) / ').firstMatch(time);
    if (match == null) return null;
    final parts = match.group(1)!.split(':').map(int.parse).toList();
    return parts.length == 2
        ? parts[0] * 60 + parts[1]
        : parts[0] * 3600 + parts[1] * 60 + parts[2];
  }

  /// Проходит [seconds] секунд по одной: часы виджета и таймер двигаются
  /// вместе.
  Future<void> elapse(int seconds) async {
    for (var i = 0; i < seconds; i++) {
      offset += const Duration(seconds: 1);
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Прирост обращений к часам за [seconds] секунд без других событий.
  Future<int> ticksIn(int seconds) async {
    final before = clockCalls;
    await elapse(seconds);
    return clockCalls - before;
  }

  Finder get block => find.byKey(const ValueKey('usage-budget'));

  /// Подпись строки Time одной строкой; пусто, если строки нет.
  String get time => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('usage-budget-time')),
        matching: find.byType(RichText),
      ),
    ))
      w.text.toPlainText(),
  ].join(' | ');

  String get title => [
    for (final w in tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(const ValueKey('usage-budget-title')),
        matching: find.byType(RichText),
      ),
    ))
      w.text.toPlainText(),
  ].join(' | ');

  /// Размонтирует панель, завершает ход и закрывает граф: незакрытый
  /// `Timer` провалил бы тест сообщением «A Timer is still pending».
  Future<void> close() async {
    shown.value = false;
    await tester.pump();
    await endTurn();
    await tester.pumpWidget(const SizedBox.shrink());
    await closeCodeLabRootScopeInTest();
  }
}

void main() {
  testWidgets('«Время идёт между шагами»: running, без одобрений, неитоговый '
      'бюджет с duration — Time обновляется раз в секунду', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(),
      ),
    );

    expect(scene.block, findsOneWidget);
    expect(scene.title, contains('This turn'));
    expect(scene.time, contains('3:00 / 10:00'));

    final ticks = await scene.ticksIn(5);

    expect(ticks, inInclusiveRange(5, 6), reason: 'тик раз в секунду');
    expect(scene.time, contains('3:05 / 10:00'));

    await scene.close();
  });

  testWidgets('Time после тика растёт вместе с часами и не уходит назад при '
      'отрицательной разности', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(),
      ),
    );

    scene.offset = const Duration(seconds: -3);
    await scene.tester.pump(const Duration(seconds: 1));

    expect(scene.time, contains('3:00 / 10:00'));

    await scene.close();
  });

  testWidgets('панель скрыта: часов не спрашивают, таймера нет', (
    tester,
  ) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(),
      ),
    );
    expect(await scene.ticksIn(2), greaterThan(0));

    scene.shown.value = false;
    await tester.pump();
    final after = scene.clockCalls;
    await scene.elapse(5);

    expect(scene.clockCalls, after);
    expect(scene.block, findsNothing);

    await scene.close();
  });

  testWidgets('скрытая панель при показе снова тикает', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(),
      ),
    );
    scene.shown.value = false;
    await tester.pump();
    scene.shown.value = true;
    await tester.pump();

    expect(await scene.ticksIn(3), greaterThanOrEqualTo(3));

    await scene.close();
  });

  testWidgets('«Таймер только при показанной панели»: конец хода отменяет '
      'таймер', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(),
      ),
    );
    expect(await scene.ticksIn(2), greaterThan(0));

    await scene.endTurn();
    await scene.snapshot(
      _snapshot(
        seq: 2,
        trigger: 'turn',
        turnId: 'turn-1',
        budget: _budgetJson(usedMs: 200000),
      ),
    );

    expect(scene.title, contains('Last turn'));
    expect(scene.time, contains('3:20 / 10:00'));
    expect(await scene.ticksIn(5), 0, reason: 'сессия свободна — тика нет');
    expect(scene.time, contains('3:20 / 10:00'));

    await scene.close();
  });

  testWidgets('ожидающее одобрение останавливает тик, Time остаётся '
      '`3:00 / 10:00`', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(),
      ),
    );
    expect(await scene.ticksIn(2), greaterThan(0));

    await scene.ask();

    expect(await scene.ticksIn(5), 0, reason: 'одобрение ждёт пользователя');
    expect(scene.time, contains('3:00 / 10:00'));
    expect(scene.title, contains('This turn'));

    await scene.close();
  });

  testWidgets('без duration в бюджете таймера нет', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(duration: false),
      ),
    );

    expect(scene.block, findsOneWidget);
    expect(find.byKey(const ValueKey('usage-budget-time')), findsNothing);
    expect(await scene.ticksIn(3), 0);

    await scene.close();
  });

  testWidgets('сессия свободна: бюджет прошлого хода без тика, Time — '
      '`usedMs`', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'turn',
        turnId: 'turn-1',
        budget: _budgetJson(usedMs: 90000),
      ),
    );

    expect(scene.title, contains('Last turn'));
    expect(scene.time, contains('1:30 / 10:00'));
    expect(await scene.ticksIn(3), 0);
    expect(scene.time, contains('1:30 / 10:00'));

    await scene.close();
  });

  testWidgets('«Начало нового хода»: до первого `step` нового хода блок '
      '`Last turn` с итогом прошлого и без тика; первый `step` включает '
      '`This turn` и тик', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'turn',
        turnId: 'turn-1',
        budget: _budgetJson(usedMs: 90000),
      ),
    );
    await scene.endTurn();

    // Новый промпт: сессия running, снимков хода 2 ещё нет.
    await scene.startTurn();

    expect(scene.title, contains('Last turn'));
    expect(scene.time, contains('1:30 / 10:00'));
    expect(await scene.ticksIn(5), 0, reason: 'до первого step тика нет');
    expect(scene.time, contains('1:30 / 10:00'));

    await scene.snapshot(
      _snapshot(
        seq: 2,
        trigger: 'step',
        turnId: 'turn-2',
        budget: _budgetJson(usedMs: 4000),
      ),
    );

    expect(scene.title, contains('This turn'));
    expect(scene.time, contains('0:04 / 10:00'));
    expect(await scene.ticksIn(3), greaterThanOrEqualTo(3));
    expect(scene.time, contains('0:07 / 10:00'));

    await scene.close();
  });

  /// Ход идёт, снимок `step` применён: `usedMs` 180000 (`3:00`); часы виджета
  /// — настоящее время.
  Future<_Scene> runningTurn(WidgetTester tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();
    scene.realClock = true;
    await scene.snapshot(
      _snapshot(
        seq: 1,
        trigger: 'step',
        turnId: 'turn-1',
        budget: _budgetJson(),
      ),
    );
    return scene;
  }

  Map<String, Object?> subagentMeta() => {
    'codelab': {
      'subagent': {
        'id': 'sub_aaaaaaaa',
        'type': 'explore',
        'description': 'Find callers',
        'depth': 1,
        'path': const <String>[],
        'parentToolCallId': 'call_1',
      },
    },
  };

  testWidgets('«Одобрение не откатывает время»: запрос одобрения корня '
      'останавливает тик, а Time не уменьшается (SMK-43)', (tester) async {
    final scene = await runningTurn(tester);
    await scene.realWait(2200);
    await scene.tester.pump(const Duration(seconds: 1));
    final before = scene.timeSeconds!;
    expect(before, greaterThanOrEqualTo(182), reason: 'Time шёл к 3:02');

    await scene.ask();

    expect(await scene.ticksIn(5), 0, reason: 'одобрение ждёт пользователя');
    expect(
      scene.timeSeconds,
      greaterThanOrEqualTo(before),
      reason: 'Time не возвращается к usedMs снимка (3:00)',
    );
    expect(scene.title, contains('This turn'));

    await scene.close();
  });

  testWidgets('«Одобрение не откатывает время»: ответ возобновляет тик без '
      'прыжка на длину ожидания', (tester) async {
    final scene = await runningTurn(tester);
    await scene.ask();
    expect(await scene.ticksIn(2), 0);
    final frozen = scene.timeSeconds!;

    // Пользователь думает 2,5 с: время ожидания в Time попадать не должно.
    await scene.realWait(2500);
    await scene.respond();

    expect(
      scene.timeSeconds,
      lessThanOrEqualTo(frozen + 1),
      reason: 'без вычитания ожидания Time прыгнул бы на 2–3 с',
    );
    expect(
      await scene.ticksIn(3),
      greaterThanOrEqualTo(3),
      reason: 'после ответа тик возобновляется',
    );

    // После ответа время снова идёт.
    final resumed = scene.timeSeconds!;
    await scene.realWait(1200);
    await scene.tester.pump(const Duration(seconds: 1));
    expect(scene.timeSeconds, greaterThan(resumed));

    await scene.close();
  });

  testWidgets('«Одобрение субагента»: ожидающее одобрение потомка тик не '
      'останавливает, Time идёт', (tester) async {
    final scene = await runningTurn(tester);
    await scene.ask(meta: subagentMeta());
    final start = scene.timeSeconds!;

    expect(
      await scene.ticksIn(3),
      greaterThanOrEqualTo(3),
      reason: 'цикл корня время потомка считает',
    );
    await scene.realWait(1200);
    await scene.tester.pump(const Duration(seconds: 1));

    expect(scene.timeSeconds, greaterThan(start));

    await scene.close();
  });

  testWidgets('«Одобрение субагента» при ожидании корня: тик стоит, пока '
      'ждёт корень, и возвращается после его ответа', (tester) async {
    final scene = await runningTurn(tester);
    await scene.ask(rpcId: 101, meta: subagentMeta());
    await scene.ask(rpcId: 102);

    expect(await scene.ticksIn(3), 0);

    await scene.respond(rpcId: 102);

    expect(await scene.ticksIn(3), greaterThanOrEqualTo(3));

    await scene.close();
  });

  testWidgets('«Отмена хода»: cancelling тикает до снимка `turn`, Time '
      'идёт, а не стоит на `3:00`', (tester) async {
    final scene = await runningTurn(tester);
    await scene.cancel();

    expect(scene.title, contains('This turn'));
    expect(await scene.ticksIn(3), greaterThanOrEqualTo(3));
    await scene.realWait(1200);
    await scene.tester.pump(const Duration(seconds: 1));
    expect(scene.timeSeconds, greaterThanOrEqualTo(181));

    await scene.endTurn();
    await scene.snapshot(
      _snapshot(
        seq: 2,
        trigger: 'turn',
        turnId: 'turn-1',
        budget: _budgetJson(usedMs: 187000),
      ),
    );

    expect(scene.title, contains('Last turn'));
    expect(scene.time, contains('3:07 / 10:00'));
    expect(await scene.ticksIn(3), 0, reason: 'после `turn` тика нет');

    await scene.close();
  });

  testWidgets('без бюджета блока и таймера нет', (tester) async {
    final scene = await _Scene.open(tester);
    await scene.startTurn();

    expect(scene.block, findsNothing);
    expect(await scene.ticksIn(3), 0);

    await scene.close();
  });
}
