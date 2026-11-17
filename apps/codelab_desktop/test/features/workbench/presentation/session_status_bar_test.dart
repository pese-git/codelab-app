// Красные widget-тесты задачи 3.3 change `add-usage-extension`: строка
// статуса под композером активной сессии (agent-workbench-ui «Строка статуса
// сессии под композером»: «Агент без расширения», «Два хода», «Контекст
// близко к пределу»; design.md D11, D23 Т1).
//
// Данные идут через настоящий граф app (как `agents_pane_test.dart`):
// объявление агента — `FakeAcpTransport.initializeAgentCapabilities` с
// `_meta.codelab.usage`, снимки — уведомления `_codelab/session/usage` на
// транспорте. Тест не знает, как kit свёртывает снимки.
//
// Главный случай — «снимок без следующего `session/update`»: снимок меняет
// только `SessionView` (`revision + 1` без нового `AcpSession`, D21 Т4),
// поэтому строка обновляется подпиской `ActiveSessionCubit` на
// `SessionHandle.view` (D23 Т1). Без подписки строка ждала бы следующего
// обновления ленты или конца хода.
//
// Отсутствующий пока (задача 3.10): ключи `status-bar-usage`,
// `status-bar-cost`, `status-bar-context` в `main_pane.dart` и сама строка;
// тест компилируется и падает на `findsOneWidget`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:codelab_desktop/app/codelab_app_widget.dart';
import 'package:codelab_desktop/features/workbench/application/shell_cubit.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/start_agent.dart';
import '../../../support/test_app_scope.dart';

const _usageKey = ValueKey('status-bar-usage');
const _costKey = ValueKey('status-bar-cost');
const _contextKey = ValueKey('status-bar-context');

const _usageCapabilities = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
    },
  },
);

/// Параметры `_codelab/session/usage` (D2, D9): ход с токенами 120 → 30,
/// стоимость хода `0.0041`, сессии `1.2`, контекст [used] из 200 000.
Map<String, Object?> _snapshot({
  required int seq,
  String trigger = 'step',
  int used = 100000,
  int input = 120,
}) => {
  'sessionId': 's1',
  'seq': seq,
  'trigger': trigger,
  'turnId': 'turn-1',
  'turn': {
    'steps': 1,
    'tokens': {'input': input, 'output': 30, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '0.0041',
  },
  'session': {
    'turns': 1,
    'steps': 1,
    'tokens': {'input': input, 'output': 30, 'cacheRead': 0, 'cacheWrite': 0},
    'cost': '1.2',
  },
  'currency': 'USD',
  'context': {'used': used, 'size': 200000},
};

final class _Scene {
  _Scene._(this.tester, this.agent, this.cubit);

  final WidgetTester tester;
  final FakeAcpTransport agent;
  final CodeLabShellCubit cubit;

  static Future<_Scene> open(
    WidgetTester tester, {
    AgentCapabilities capabilities = const AgentCapabilities(),
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final agent = FakeAcpTransport()
      ..initializeAgentCapabilities = capabilities;
    final binding = CodeLabTestBinding(
      project: '/work',
      stdioTransportFactory: (_) => agent,
    );
    final cubit = binding.scope.resolve<CodeLabShellCubit>();
    await tester.pumpWidget(
      binding.bootstrap(child: const CodeLabApp(startOnLaunch: false)),
    );
    await tester.pump();
    await tester.runAsync(cubit.startWith);
    final scene = _Scene._(tester, agent, cubit);
    await scene.flush();
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

  /// Снимок usage — только уведомление `_codelab/session/usage`, без
  /// `session/update`.
  Future<void> usage(Map<String, Object?> params) async {
    agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: params,
      ),
    );
    await flush();
  }
}

Finder _in(ValueKey<String> key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

void main() {
  testWidgets('no shown session: no status bar', (tester) async {
    await _Scene.open(tester, capabilities: _usageCapabilities);

    expect(find.byKey(_usageKey), findsNothing);
    expect(find.byKey(_costKey), findsNothing);
    expect(find.byKey(_contextKey), findsNothing);
  });

  testWidgets('«Агент без расширения»: «usage: —», no cost, no context, no 0', (
    tester,
  ) async {
    final scene = await _Scene.open(tester);
    await scene.newSession('s1');

    expect(_in(_usageKey, find.text('usage: —')), findsOneWidget);
    expect(find.byKey(_costKey), findsNothing);
    expect(find.byKey(_contextKey), findsNothing);
  });

  testWidgets('declared usage before the first snapshot: no segments', (
    tester,
  ) async {
    final scene = await _Scene.open(tester, capabilities: _usageCapabilities);
    await scene.newSession('s1');

    // Состояние `awaiting`: не «usage: —» и не нули.
    expect(find.byKey(_usageKey), findsNothing);
    expect(find.byKey(_costKey), findsNothing);
    expect(find.byKey(_contextKey), findsNothing);
    expect(find.text('usage: —'), findsNothing);
  });

  testWidgets('a snapshot without the next session/update refreshes the row '
      '(subscription to SessionHandle.view, D23 T1)', (tester) async {
    final scene = await _Scene.open(tester, capabilities: _usageCapabilities);
    await scene.newSession('s1');

    await scene.usage(_snapshot(seq: 1));

    expect(_in(_usageKey, find.text('120 → 30')), findsOneWidget);
    expect(
      _in(_costKey, find.text(r'$0.0041 · session $1.20')),
      findsOneWidget,
    );
    expect(_in(_contextKey, find.textContaining('50%')), findsOneWidget);

    // Второй снимок — снова без `session/update`: строка идёт за ревизиями.
    await scene.usage(_snapshot(seq: 2, used: 170000, input: 450));

    expect(_in(_usageKey, find.text('450 → 30')), findsOneWidget);
    expect(_in(_contextKey, find.textContaining('85%')), findsOneWidget);
    expect(_in(_contextKey, find.textContaining('50%')), findsNothing);
  });

  testWidgets('a duplicate or stale snapshot does not change the row', (
    tester,
  ) async {
    final scene = await _Scene.open(tester, capabilities: _usageCapabilities);
    await scene.newSession('s1');
    await scene.usage(_snapshot(seq: 2, input: 450));

    await scene.usage(_snapshot(seq: 1, input: 120));

    expect(_in(_usageKey, find.text('450 → 30')), findsOneWidget);
  });
}
