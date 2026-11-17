import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show JsonRpcNotification;
import 'package:codelab_agent_acp/src/usage_accounting.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/server_harness.dart';

/// Проекция бюджета хода в `_codelab/session/usage` (agent-acp-server
/// «Бюджет хода в уведомлении `_codelab/session/usage`»; design.md change
/// `add-desktop-usage-pane`, D7, Q5; задача 2.3).
///
/// Почему отдельный файл: поле `budget` — надстройка над usage v1 со своими
/// правилами «когда есть» (только при `max_tokens`, `max_cost` или
/// `max_duration`), а `usage_projection_test.dart` проверяет остальной снимок.
///
/// Тесты «поля нет» (в том числе у снимков `compaction`, `compactionDiscarded`
/// и `load`) — защита от лишнего ключа у существующих фикстур и поводов уровня
/// сессии (D7).
///
/// Числа — как в фикстуре `acp/prompt-usage-budget` и
/// `acp/prompt-usage-steps` (цены 3 / 15 / 0.3 / 3.75 доллара за 10^6
/// токенов): стоимость шагов 0.0111 и 0.0171 микродолларами целая.
void main() {
  late ServerHarness h;

  tearDown(() => h.dispose());

  const usageClient = <String, Object?>{
    'fs': {'readTextFile': true, 'writeTextFile': true},
    'terminal': true,
    '_meta': {
      'codelab': {
        'usage': {'version': 1},
      },
    },
  };

  ModelRef model({ModelCost? cost}) => ModelRef(
    provider: 'scripted',
    id: 'scripted-1',
    api: ProviderApi.openaiChat,
    baseUrl: Uri.parse('http://localhost:8080/v1'),
    contextWindow: 32768,
    maxOutputTokens: 4096,
    cost: cost,
  );

  final priced = model(
    cost: const ModelCost(
      input: 3,
      output: 15,
      cacheRead: 0.3,
      cacheWrite: 3.75,
    ),
  );

  Map<String, Object?> taskStep(Map<String, Object?> usage) => {
    'reply': [
      {
        'toolCall': {
          'id': 'call_1',
          'name': 'task_create',
          'arguments': {'subject': 'Прочитать тесты', 'priority': 'high'},
        },
      },
    ],
    'usage': usage,
  };

  Map<String, Object?> textStep(String text, Map<String, Object?>? usage) => {
    'reply': [
      {'text': text},
    ],
    'usage': ?usage,
  };

  const step0 = {'input': 1200, 'output': 300, 'cacheRead': 10000};
  const step1 = {
    'input': 1500,
    'output': 400,
    'cacheRead': 12000,
    'cacheWrite': 800,
  };

  /// Сервер с лимитами [budget] и сессия; клиент объявил `usage`.
  Future<String> ready({
    required TurnBudget budget,
    required ModelRef defaultModel,
    required List<Map<String, Object?>> steps,
    CompactionOverrides compaction = const CompactionOverrides(),
  }) async {
    h = await ServerHarness.start(
      steps: steps,
      defaultModel: defaultModel,
      budget: budget,
      compaction: compaction,
    );
    await h.initialize(clientCapabilities: usageClient);
    return h.newSession();
  }

  List<Map<String, Object?>> usageOf(TestClient client) => [
    for (final frame in client.received)
      if (frame case JsonRpcNotification(
        method: '_codelab/session/usage',
        :final params,
      ))
        (params! as Map).cast<String, Object?>(),
  ];

  Map<String, Object?> asMap(Object? value) =>
      (value! as Map).cast<String, Object?>();

  List<Map<String, Object?>> twoSteps() => [
    taskStep(step0),
    textStep('Список готов.', step1),
  ];

  // «Бюджет в снимках хода» (фикстура `acp/prompt-usage-budget`): форма и
  // числа поля; `steps.used` — 1, 2, 2; токены — `input + output` без
  // кэша; `duration` нет, потому что `max_duration` не задан.
  test(
    'max_tokens and max_cost: step and turn snapshots carry budget',
    () async {
      final sessionId = await ready(
        budget: const TurnBudget(maxTokens: 200000, maxCost: 0.5),
        defaultModel: priced,
        steps: twoSteps(),
      );

      await h.prompt(sessionId, 'Составь список задач');

      final frames = usageOf(h.client);
      expect(frames.map((f) => f['trigger']), ['step', 'step', 'turn']);
      const expected = [
        (steps: 1, tokens: 1500, cost: '0.0111'),
        (steps: 2, tokens: 3400, cost: '0.0282'),
        (steps: 2, tokens: 3400, cost: '0.0282'),
      ];
      for (final (i, frame) in frames.indexed) {
        expect(frame, contains('budget'), reason: 'снимок ${i + 1}');
        expect(frame['budget'], {
          'steps': {'used': expected[i].steps, 'limit': 50},
          'tokens': {'used': expected[i].tokens, 'limit': 200000},
          'cost': {'used': expected[i].cost, 'limit': '0.5'},
        }, reason: 'снимок ${i + 1}');
      }
    },
  );

  // Состав: `steps` — всегда, остальное — только заданные лимиты.
  test('only max_tokens: steps and tokens, no cost and no duration', () async {
    final sessionId = await ready(
      budget: const TurnBudget(maxTokens: 10000),
      defaultModel: priced,
      steps: twoSteps(),
    );

    await h.prompt(sessionId, 'Составь список задач');

    for (final frame in usageOf(h.client)) {
      expect(asMap(frame['budget']).keys.toSet(), {'steps', 'tokens'});
    }
  });

  test('only max_duration: steps and duration in milliseconds', () async {
    final sessionId = await ready(
      budget: const TurnBudget(maxDuration: Duration(minutes: 10)),
      defaultModel: priced,
      steps: twoSteps(),
    );

    await h.prompt(sessionId, 'Составь список задач');

    final frames = usageOf(h.client);
    expect(frames.map((f) => f['trigger']), ['step', 'step', 'turn']);
    for (final frame in frames) {
      final budget = asMap(frame['budget']);
      expect(budget.keys.toSet(), {'steps', 'duration'});
      final duration = asMap(budget['duration']);
      expect(duration['limitMs'], 600000);
      expect(duration['usedMs'], isA<int>());
      expect(duration['usedMs'], greaterThanOrEqualTo(0));
    }
  });

  // `cost.limit` — `round(max_cost × 10^6)` микродолларов десятичной
  // строкой (D9 change `add-usage-extension`): 0.1234567 → `0.123457`.
  test('cost.limit is max_cost rounded to microdollars', () async {
    final sessionId = await ready(
      budget: const TurnBudget(maxCost: 0.1234567),
      defaultModel: priced,
      steps: twoSteps(),
    );

    await h.prompt(sessionId, 'Составь список задач');

    for (final frame in usageOf(h.client)) {
      expect(asMap(asMap(frame['budget'])['cost'])['limit'], '0.123457');
    }
  });

  // Модель без цен: цикл лимит стоимости не проверяет, `cost.used` нет, но
  // `currency` обязателен, как только есть `budget.cost` (D7).
  test('max_cost on an unpriced model: cost has only limit and currency '
      'is USD', () async {
    final sessionId = await ready(
      budget: const TurnBudget(maxCost: 0.5),
      defaultModel: model(),
      steps: [
        textStep('Привет', const {'input': 100, 'output': 20}),
      ],
    );

    await h.prompt(sessionId, 'Привет');

    final frames = usageOf(h.client);
    expect(frames.map((f) => f['trigger']), ['step', 'turn']);
    for (final frame in frames) {
      expect(asMap(frame['budget'])['cost'], {'limit': '0.5'});
      expect(frame['currency'], 'USD');
    }
  });

  // Невалидный `max_cost` (NaN, ±inf, отрицательный, больше предела
  // микродолларов) показать нельзя: подполя `cost` нет, остальной бюджет
  // остаётся, проекция не бросает (D7, D9).
  for (final (name, maxCost) in [
    ('NaN', double.nan),
    ('+inf', double.infinity),
    ('huge', 1e300),
  ]) {
    test('$name max_cost with max_tokens: budget without cost', () async {
      final sessionId = await ready(
        budget: TurnBudget(maxTokens: 200000, maxCost: maxCost),
        defaultModel: priced,
        steps: twoSteps(),
      );

      await h.prompt(sessionId, 'Составь список задач');

      final frames = usageOf(h.client);
      expect(frames.map((f) => f['trigger']), ['step', 'step', 'turn']);
      for (final frame in frames) {
        final budget = asMap(frame['budget']);
        expect(budget, isNot(contains('cost')));
        expect(budget['steps'], isNotNull);
        expect(asMap(budget['tokens'])['limit'], 200000);
      }
    });

    test('$name max_cost alone: no budget', () async {
      final sessionId = await ready(
        budget: TurnBudget(maxCost: maxCost),
        defaultModel: priced,
        steps: twoSteps(),
      );

      await h.prompt(sessionId, 'Составь список задач');

      final frames = usageOf(h.client);
      expect(frames.map((f) => f['trigger']), ['step', 'step', 'turn']);
      for (final frame in frames) {
        expect(frame, isNot(contains('budget')));
      }
    });
  }

  // Отрицательный и -inf лимиты цикл исчерпывает сразу (до первого шага), так
  // что снимков не будет; проекцию проверяем напрямую.
  for (final (name, maxCost) in [
    ('-inf', double.negativeInfinity),
    ('negative', -1.0),
    ('NaN', double.nan),
    ('huge', 1e300),
  ]) {
    test('budgetJson with $name max_cost does not throw', () {
      BudgetProgress progress(TurnBudget limits) => BudgetProgress(
        limits: limits,
        steps: 1,
        tokens: 10,
        cost: 0.01,
        active: Duration.zero,
      );

      final withTokens = budgetJson(
        progress(TurnBudget(maxTokens: 1000, maxCost: maxCost)),
      );
      expect(withTokens, isNotNull);
      expect(withTokens, isNot(contains('cost')));
      expect(withTokens, contains('steps'));
      expect(withTokens, contains('tokens'));
      expect(budgetJson(progress(TurnBudget(maxCost: maxCost))), isNull);
    });
  }

  // Без лимитов, кроме шагов, поля нет: иначе все существующие usage-фикстуры
  // получили бы лишний ключ (D7; фикстура `acp/prompt-usage-steps`).
  for (final (name, budget) in [
    ('defaults', const TurnBudget()),
    ('only max_steps', const TurnBudget(maxSteps: 10)),
  ]) {
    test('$name: no budget in step and turn snapshots', () async {
      final sessionId = await ready(
        budget: budget,
        defaultModel: priced,
        steps: twoSteps(),
      );

      await h.prompt(sessionId, 'Составь список задач');

      final frames = usageOf(h.client);
      expect(frames.map((f) => f['trigger']), ['step', 'step', 'turn']);
      for (final frame in frames) {
        expect(frame, isNot(contains('budget')));
      }
    });
  }

  // Совместимость v1: клиент без `usage` уведомлений не получает вовсе,
  // поле budget ничего не меняет в объявлении (`usage: {"version": 1}`).
  test('a client without usage still receives no usage frames', () async {
    h = await ServerHarness.start(
      steps: twoSteps(),
      defaultModel: priced,
      budget: const TurnBudget(maxTokens: 200000),
    );
    await h.initialize();
    final sessionId = await h.newSession();

    await h.prompt(sessionId, 'Составь список задач');

    expect(usageOf(h.client), isEmpty);
  });

  // Снимок `compaction` бюджета не несёт (D7: поле только у `step`/`turn`).
  test('the compaction snapshot has no budget', () async {
    final longReply = 'Ответ подробно. ' * 150;
    final sessionId = await ready(
      budget: const TurnBudget(maxTokens: 200000),
      defaultModel: priced,
      compaction: const CompactionOverrides(keepRecentTokens: 512),
      steps: [
        textStep(longReply, const {'input': 100, 'output': 20}),
        textStep(longReply, const {'input': 20000, 'output': 20}),
        textStep('Пользователь задал два вопроса.', null),
      ],
    );
    await h.prompt(sessionId, 'Первый вопрос');
    await h.prompt(sessionId, 'Второй вопрос');
    // Ход «/compact» не доходит до шага модели, поэтому до него убеждаемся,
    // что у снимков ходов поле есть: иначе тест прошёл бы зря.
    final turnFrames = usageOf(h.client);
    expect(turnFrames, isNotEmpty);
    expect(turnFrames.first, contains('budget'));

    await h.prompt(sessionId, '/compact обработка ошибок');

    final frames = usageOf(h.client);
    expect(frames.last['trigger'], 'compaction');
    expect(frames.last, isNot(contains('budget')));
  });

  // Снимок `load` бюджета не несёт: ход не идёт, лимитов хода нет.
  test('the load snapshot has no budget', () async {
    const budget = TurnBudget(maxTokens: 200000);
    final sessionId = await ready(
      budget: budget,
      defaultModel: priced,
      steps: [
        textStep('Здравствуйте.', const {'input': 10, 'output': 5}),
      ],
    );
    await h.prompt(sessionId, 'Привет');
    expect(usageOf(h.client).first, contains('budget'));
    final store = h.store;
    await h.dispose();

    h = await ServerHarness.start(
      sessions: store,
      defaultModel: priced,
      budget: budget,
      steps: const [],
    );
    await h.initialize(clientCapabilities: usageClient);
    final load = await h.client.request('session/load', {
      'sessionId': sessionId,
      'cwd': '/work/demo',
      'mcpServers': <Object?>[],
    });
    expect(load.error, isNull);
    await pumpEventQueue();

    final frames = usageOf(h.client);
    expect(frames.single['trigger'], 'load');
    expect(frames.single, isNot(contains('budget')));
  });

  // Снимок `compactionDiscarded` (change `fix-discarded-compaction-usage`,
  // CMP-13) бюджета не несёт: он идёт вне хода, лимиты хода к нему не
  // относятся (agent-acp-server «Снимок сжатия»; D7, задача 3.1a).
  //
  // Сторожевой тест: зелёный сразу, потому что `_sessionSnapshot` поле не
  // передаёт. Строим сводку напрямую, без сервера: ход с заданными лимитами
  // нужен лишь затем, чтобы у сводки был `budget` последнего шага и итога
  // хода, который снимок обязан НЕ унаследовать.
  test('the compactionDiscarded snapshot has no budget even with limits '
      'set and a budget on the last step and turn', () {
    const limits = TurnBudget(maxTokens: 200000, maxCost: 0.5);
    const root = SessionId('sess_discarded');
    final spent = Usage(
      input: 1200,
      output: 300,
      cost: const UsageCost(input: 0.0036, output: 0.0045),
    );
    final progress = BudgetProgress(
      limits: limits,
      steps: 1,
      tokens: 1500,
      cost: 0.0081,
      active: Duration.zero,
    );
    final accounting = UsageAccounting()
      ..turnStarted(const TurnId('turn_1'))
      ..stepEnded(
        StepEnded(
          root,
          result: StepResult(
            stepIndex: 0,
            response: AssistantMessage(
              content: const [],
              model: priced,
              usage: spent,
              stopReason: StopReason.stop,
              timestamp: DateTime.utc(2026),
            ),
            results: const [],
            usage: spent,
          ),
          context: const ContextFill(
            used: 120,
            window: 32768,
            compactAt: 24576,
          ),
          budget: progress,
        ),
      )
      ..turnEnded(
        TurnEnded(
          root,
          reason: TurnEndReason.completed,
          usage: spent,
          budget: progress,
        ),
      );
    // Контроль: у снимков хода поле при тех же лимитах есть, иначе тест
    // прошёл бы зря.
    expect(accounting.turnSnapshot(root.value), contains('budget'));

    accounting.summarizerEnded(
      const Usage(input: 900, output: 120),
      priced: true,
    );
    final frame = accounting.compactionDiscardedSnapshot(root.value, 120);

    expect(frame['trigger'], 'compactionDiscarded');
    expect(frame, isNot(contains('budget')));
  });
}
