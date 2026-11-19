// Красные тесты задачи 3.3 change `add-desktop-localization`: панель Usage на
// русском (spec app-settings «Локализация интерфейса app»; agent-workbench-ui
// «Панель Usage», «Бюджет хода в панели Usage»; design.md D5 п. 4, D7, D8).
//
// `features/usage/application` остаётся без Flutter: оттуда выходят
// типизированные значения (заголовок `This turn`/`Last turn`, вид строки
// бюджета, вид заметки), а текст собирает presentation по каталогу (D5 п. 4).
// Тесты проверяют конечный текст на экране, а не форму типов, поэтому не
// предписывают имена значений application.
//
// Числа — формат ядра клиента, общий с CLI и CSV: точка, `k`, без пробелов
// между разрядами (D8, Q2 (а)); они не меняются при `ru`. Данные идут через
// настоящий граф app, как в `usage_pane_test.dart`.
//
// Русские строки панели — вне глоссария, кроме «Ввод», «Вывод», «Стоимость»,
// «Шаги», «Токены», «Время», «Этот ход», «Прошлый ход» (глоссарий,
// «Бюджет хода», «Панель «Расход»»); весь список — в отчёте задачи 3.3.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_desktop/core/platform/usage_csv_saver.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_usage_csv_saver.dart';
import '../../../support/live_scene.dart';

const _ledgerMethod = '_codelab/session/usage/ledger';

const _usageAndLedger = AgentCapabilities(
  meta: {
    'codelab': {
      'usage': {'version': 1},
      'usageLedger': {'version': 1},
    },
  },
);

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

Map<String, Object?> _snapshot({
  required int seq,
  required String trigger,
  String turnId = 'turn-1',
}) => {
  'sessionId': 's1',
  'seq': seq,
  'trigger': trigger,
  'turnId': turnId,
  'turn': {'steps': 3, 'tokens': _tokens(100, 20), 'cost': '0.41'},
  'session': {
    'turns': 1,
    'steps': 3,
    'tokens': _tokens(100, 20),
    'cost': '0.41',
  },
  'currency': 'USD',
  'budget': {
    'steps': {'used': 3, 'limit': 50},
    'tokens': {'used': 92000, 'limit': 200000},
    'cost': {'used': '0.41', 'limit': '0.5'},
    'duration': {'usedMs': 180000, 'limitMs': 600000},
  },
};

Map<String, Object?> _ledger() => {
  'sessionId': 's1',
  'seq': 2,
  'currency': 'USD',
  'total': {'turns': 1, 'steps': 3, 'tokens': _tokens(100, 20), 'cost': '0.41'},
  'ledger': {'status': 'upToDate', 'records': 3},
  'turns': [
    {
      'index': 1,
      'total': {'steps': 3, 'tokens': _tokens(100, 20), 'cost': '0.41'},
      'steps': [
        {'index': 0, 'tokens': _tokens(100, 20), 'toolCallIds': <String>[]},
      ],
    },
  ],
};

Finder _pane() => find.byKey(CodeLabToolDock.paneKey(ToolPane.usage));

/// Отвечает на запросы журнала, которых агент ещё не получил ответа.
Future<void> _answerLedger(LiveScene scene, Set<Object> answered) async {
  for (final message in scene.agent.sentMessages) {
    if (message is JsonRpcRequest &&
        message.method == _ledgerMethod &&
        answered.add(message.id)) {
      scene.agent.emitInbound(
        JsonRpcMessage.response(id: message.id, result: _ledger()),
      );
    }
  }
  await scene.flush();
}

void main() {
  testWidgets('идущий ход: заголовок «Этот ход», строки бюджета и числа '
      'ядра', (tester) async {
    final scene = await LiveScene.open(
      tester,
      locale: const Locale('ru'),
      capabilities: _usageAndLedger,
    );
    await scene.newSession('s1');
    await scene.prompt('go');
    scene.agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: 1, trigger: 'step'),
      ),
    );
    await scene.flush();
    scene.cubit.openPane(ToolPane.usage);
    await scene.flush();

    final budget = scene.textOf(find.byKey(const ValueKey('usage-budget')));
    expect(budget, contains('Этот ход'));
    for (final label in const ['Шаги', 'Токены', 'Стоимость', 'Время']) {
      expect(budget, contains(label));
    }
    // Формат ядра на любом языке (D8).
    expect(budget, contains('3 / 50'));
    expect(budget, contains('92.0k / 200.0k'));
    expect(budget, contains(r'$0.41 / $0.50'));
    expect(budget, contains('3:00 / 10:00'));
    // Пояснение под блоком — вне глоссария.
    expect(
      scene.textOf(find.byKey(const ValueKey('usage-budget-note'))),
      contains(
        'При достижении лимита ход останавливается на границе '
        'следующего шага.',
      ),
    );

    await scene.close();
  });

  testWidgets('завершённый ход: заголовок «Прошлый ход»', (tester) async {
    final scene = await LiveScene.open(
      tester,
      locale: const Locale('ru'),
      capabilities: _usageAndLedger,
    );
    await scene.newSession('s1');
    final turn = await scene.prompt('go');
    scene.agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: 1, trigger: 'step'),
      ),
    );
    await scene.flush();
    scene.cubit.openPane(ToolPane.usage);
    await scene.flush();
    await scene.endTurn(turn);
    scene.agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: 2, trigger: 'turn'),
      ),
    );
    await scene.flush();

    expect(
      scene.textOf(find.byKey(const ValueKey('usage-budget-title'))),
      contains('Прошлый ход'),
    );

    await scene.close();
  });

  testWidgets('карточки, заголовок панели и строка журнала на русском', (
    tester,
  ) async {
    final scene = await LiveScene.open(
      tester,
      locale: const Locale('ru'),
      capabilities: _usageAndLedger,
    );
    await scene.newSession('s1');
    scene.agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: 1, trigger: 'turn'),
      ),
    );
    await scene.flush();
    scene.cubit.openPane(ToolPane.usage);
    await scene.flush();
    await _answerLedger(scene, {});

    final pane = scene.textOf(_pane());
    expect(pane, contains('Эта сессия'));
    for (final title in const ['Ввод', 'Вывод', 'Стоимость', 'Ходы · шаги']) {
      expect(pane, contains(title));
    }
    // Число записей склоняется (D8): 3 записи.
    expect(pane, contains('История расхода: актуальна · 3 записи'));
    // Кит: подписи кнопок панели.
    expect(pane, contains('Пересобрать из журнала'));
    expect(pane, contains('Экспорт в CSV'));

    await scene.close();
  });

  testWidgets('агент без журнала: заметка на русском', (tester) async {
    final scene = await LiveScene.open(
      tester,
      locale: const Locale('ru'),
      capabilities: _usageOnly,
    );
    await scene.newSession('s1');
    scene.agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: 1, trigger: 'turn'),
      ),
    );
    await scene.flush();
    scene.cubit.openPane(ToolPane.usage);
    await scene.flush();

    expect(
      scene.textOf(find.byKey(const ValueKey('usage-note'))),
      contains('Этот агент не предоставляет историю расхода.'),
    );

    await scene.close();
  });

  testWidgets('сбой записи CSV: заметка «Не удалось сохранить файл.»', (
    tester,
  ) async {
    final saver = FakeUsageCsvSaver()
      ..result = const UsageCsvFailed('FileSystemException');
    final scene = await LiveScene.open(
      tester,
      locale: const Locale('ru'),
      capabilities: _usageAndLedger,
      usageCsvSaver: saver,
    );
    await scene.newSession('s1');
    scene.agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: 1, trigger: 'turn'),
      ),
    );
    await scene.flush();
    scene.cubit.openPane(ToolPane.usage);
    await scene.flush();
    await _answerLedger(scene, {});

    await tester.tap(find.byKey(const ValueKey('usage-export')));
    await scene.flush();

    expect(saver.saved, hasLength(1));
    expect(find.text('Не удалось сохранить файл.'), findsOneWidget);
    expect(find.text("Couldn't save the file."), findsNothing);

    await scene.close();
  });

  testWidgets('отказ журнала: заметка и «Повторить» на русском', (
    tester,
  ) async {
    final scene = await LiveScene.open(
      tester,
      locale: const Locale('ru'),
      capabilities: _usageAndLedger,
    );
    await scene.newSession('s1');
    scene.agent.emitInbound(
      JsonRpcMessage.notification(
        method: '_codelab/session/usage',
        params: _snapshot(seq: 1, trigger: 'turn'),
      ),
    );
    await scene.flush();
    scene.cubit.openPane(ToolPane.usage);
    await scene.flush();
    for (final message in scene.agent.sentMessages) {
      if (message is JsonRpcRequest && message.method == _ledgerMethod) {
        scene.agent.emitInbound(
          JsonRpcMessage.response(
            id: message.id,
            error: const JsonRpcError(code: -32603, message: 'ledger failed'),
          ),
        );
      }
    }
    await scene.flush();

    final note = scene.textOf(find.byKey(const ValueKey('usage-note')));
    expect(note, contains('Не удалось загрузить историю расхода.'));
    expect(note, contains('Повторить'));

    await scene.close();
  });
}
