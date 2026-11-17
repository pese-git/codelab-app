import 'dart:convert';
import 'dart:io';

import 'package:codelab_acp_testing/codelab_acp_testing.dart';
import 'package:test/test.dart';

import 'support/corpus_invariants.dart';

/// Fixtures of stage 0 (`dart-agent-and-clients/09-05-stage-0-foundation.md`,
/// task 0.7). The list grows only together with the corpus.
const _stage0Fixtures = {
  'acp/initialize-capabilities',
  'acp/session-new-modes-config',
  'acp/prompt-text-end-turn',
  'acp/prompt-cancel-mid-tool',
  'acp/prompt-tool-permission-allow',
  'acp/prompt-tool-permission-reject-continues',
  'acp/tool-status-lifecycle',
  'acp/tool-read-range',
  'acp/tool-exec-terminal-embed',
  'acp/prompt-update-plan',
  'acp/set-config-option-model',
  'acp/errors-unknown-session-update-tolerated',
};

/// Клиентская фикстура change `tolerate-unknown-tool-kind` (D8; acp-golden-
/// fixtures «Фикстура неизвестного вида вызова»): роль только `client`,
/// Dart-агент незнакомых видов не выдаёт.
const _toolKindFixtures = {'acp/tool-kind-unknown-tolerated'};

/// Корпус этапа 4 полностью — 35 фикстур §14.2: 33 агентского прогона в
/// памяти (design.md change `add-dart-agent-acp-server`, D8) и 2
/// транспортные (`add-codelab-agent-binary`, D8); фикстуры выноса — в
/// `add-agent-core-output-spill`.
const _stage4Fixtures = {
  'acp/compaction-long-session-continues',
  'acp/config-effort-option',
  'acp/errors-bad-frame-survives',
  'acp/multi-session-concurrent-prompts',
  'acp/permission-allow-always-scoped',
  'acp/permission-critical-pattern-in-bypass',
  'acp/permission-options-all-four',
  'acp/permission-outcome-cancelled',
  'acp/prompt-anthropic-tool-call',
  'acp/prompt-cancel-during-terminal',
  'acp/prompt-cancel-mid-stream',
  'acp/prompt-failed-provider-auth',
  'acp/prompt-max-turn-requests',
  'acp/prompt-network-drop',
  'acp/prompt-parallel-tool-calls',
  'acp/prompt-provider-error',
  'acp/prompt-streaming-text',
  'acp/prompt-thought-chunk',
  'acp/prompt-turn-budget-exceeded',
  'acp/session-info-title',
  'acp/session-list-cwd-filter',
  'acp/session-load-interrupted-turn',
  'acp/session-load-replay',
  'acp/set-mode-bypass-no-prompt',
  'acp/set-mode-plan-rejects-edit',
  'acp/set-mode-updates-current-mode',
  'acp/tool-edit-ambiguous-match-error',
  'acp/tool-edit-exact-replace',
  'acp/tool-exec-terminal-env-array',
  'acp/tool-invalid-args-error',
  'acp/tool-list-dir',
  'acp/tool-search-content',
  'acp/tool-write-permission-diff',
  'acp/stdio-framing-large-line',
  'acp/ws-auth-bearer-required',
};

/// MCP-фикстуры этапа 8 итерации 2 (design.md change `add-agent-mcp-client`,
/// D15): все с ролью `agent`. `acp/mcp-http-tool-call` проходит через
/// настоящий `StreamableHttpTransport` (итерация 3).
const _stage8McpFixtures = {
  'acp/session-new-with-mcp',
  'acp/mcp-tool-permission',
  'acp/mcp-stdio-tool-call',
  'acp/mcp-result-fenced',
  'acp/set-mode-plan-rejects-mcp-write',
  'acp/mcp-http-tool-call',
};

/// Фикстуры файлов проекта этапа 8 (design.md change
/// `add-agent-project-files`, D15; acp-golden-fixtures «Фикстуры файлов
/// проекта этапа 8»): роль только `agent`, команды публикует агент.
const _stage8ProjectFilesFixtures = {
  'acp/prompt-template-command',
  'acp/available-commands-no-tools',
  'acp/set-config-option-agent',
  // Встроенная команда `/mcp` (design.md change
  // `add-config-writer-and-reload`, D12; задача 7.3).
  'acp/slash-mcp-list',
};

/// Встроенные slash-команды агента, закрывающие строки Must K-02 и R-08
/// (change `switch-default-agent-to-dart`, задачи 2.1 и 2.3): команды
/// исполняет агент, поэтому роль только `agent`.
const _slashCommandFixtures = {
  'acp/slash-compact',
  'acp/slash-help',
  'acp/slash-usage',
  'acp/slash-mode-plan',
};

/// Фикстуры навыков (design.md change `add-agent-skills`, D7, D8; задача 3.1;
/// acp-golden-fixtures «Фикстуры навыков»): роль только `agent`, команды и
/// инструмент `skill` публикует агент.
const _skillFixtures = {
  'acp/skill-command-listed',
  'acp/skill-invoke',
  'acp/skill-tool-load',
  'acp/skill-script-exec',
};

/// Фикстуры change `add-subagents-and-tasks` итераций 1–5 (acp-golden-fixtures
/// «Фикстуры субагентов и списка задач»); фикстуры дерева вызовов потомков —
/// итерация 5, задача 5.1.
const _tasksFixtures = {
  'acp/initialize-codelab-extensions',
  'acp/prompt-task-plan',
  'acp/prompt-subagent-tool-call',
  'acp/prompt-subagent-permission',
  'acp/prompt-subagent-nested-permission',
  'acp/prompt-subagent-tool-tree',
  'acp/session-load-subagent-tool-tree',
  'acp/session-load-legacy-plan',
};

/// Фикстуры change `add-usage-extension`, итерация 1 (задача 1.5;
/// acp-golden-fixtures «Фикстуры расширения usage»; design.md D13): роль
/// только `agent` — клиентскую роль `acp/prompt-usage-steps` добавляет
/// задача 2.7 (D18 Т8), чтобы `conformance:client` не краснел между PR.
const _usageFixtures = {
  'acp/prompt-usage-steps',
  'acp/prompt-usage-unpriced',
  'acp/prompt-usage-cancelled',
  'acp/compact-usage-context',
  'acp/prompt-usage-compaction-off',
};

/// Фикстуры change `add-usage-ledger` (design.md D11; acp-golden-fixtures
/// «Фикстуры журнала usage»): метки `usage` и `usageLedger` (FIX-4), роль
/// `agent` (клиентскую роль `acp/usage-ledger-request` добавляет задача 3.5,
/// чтобы `conformance:client` не краснел между PR), ссылки `spec` на
/// `15-Extensibility.md`. `acp/session-load-usage-full` заменяет
/// `acp/session-load-usage-partial` (D13 change `add-usage-extension`).
const _usageLedgerFixtures = {
  'acp/usage-ledger-request',
  'acp/usage-ledger-rebuild',
  'acp/session-load-usage-full',
  'acp/compact-usage-summary',
};

/// Блок `agentCapabilities._meta.codelab` ответа `initialize` фикстуры.
Map<Object?, Object?> _agentCodelabBlock(AcpFixture fixture) {
  final response = fixture.frames
      .where((f) => f.direction == FrameDirection.a2c)
      .map((f) => f.frame!)
      .singleWhere((f) => f['result'] != null);
  final capabilities =
      ((response['result'] as Map)['agentCapabilities'] as Map);
  return ((capabilities['_meta'] as Map)['codelab'] as Map)
      .cast<Object?, Object?>();
}

void main() {
  final corpus = loadFixtureCorpus();
  final protocolDirectory = protocolSpecDirectory();

  test('the corpus holds exactly the stage 0, stage 4, MCP and project files '
      'fixtures', () {
    expect(_stage4Fixtures, hasLength(35));
    expect(corpus.map((f) => f.id).toSet(), {
      ..._stage0Fixtures,
      ..._stage4Fixtures,
      ..._stage8McpFixtures,
      ..._stage8ProjectFilesFixtures,
      ..._slashCommandFixtures,
      ..._skillFixtures,
      ..._toolKindFixtures,
      ..._tasksFixtures,
      ..._usageFixtures,
      ..._usageLedgerFixtures,
    });
  });

  // acp-golden-fixtures «Фикстуры расширения usage» (D13, D18 Т8): метка
  // `usage` (FIX-4, сценарий «Расширение не объявлено»), роль `agent`
  // (у `acp/prompt-usage-steps` ещё и `client`, задача 2.7), объявление клиента — через
  // `setup.clientCapabilities` с `_meta.codelab.usage`.
  test('the usage fixtures declare the usage extension and its consent', () {
    for (final fixture in corpus.where((f) => _usageFixtures.contains(f.id))) {
      expect(fixture.extensions, contains('usage'), reason: fixture.id);
      // Задача 2.7 (D21 Т7): `acp/prompt-usage-steps` играет и клиентский
      // прогон (подмножество `_meta.codelab`); остальные — только агент.
      expect(
        fixture.roles,
        fixture.id == 'acp/prompt-usage-steps'
            ? {FixtureRole.agent, FixtureRole.client}
            : {FixtureRole.agent},
        reason: fixture.id,
      );
      final caps = fixture.setup.clientCapabilities as Map?;
      final codelab = (caps?['_meta'] as Map?)?['codelab'] as Map?;
      expect(codelab?['usage'], {
        'version': 1,
      }, reason: '${fixture.id}: the client must declare usage');
    }
  });

  // acp-golden-fixtures «Фикстуры журнала usage» (change `add-usage-ledger`,
  // D11): метки `usage` и `usageLedger`, роль только `agent`, ссылка на
  // `15-Extensibility.md`; `acp/slash-usage` — тоже с обеими метками, но без
  // объявления `usage` клиентом (ход без снимков).
  test('the usage ledger fixtures carry both labels, the agent role and an '
      'extensibility spec link', () {
    final ids = {..._usageLedgerFixtures, 'acp/slash-usage'};
    for (final fixture in corpus.where((f) => ids.contains(f.id))) {
      expect(
        fixture.extensions,
        containsAll(['usage', 'usageLedger']),
        reason: fixture.id,
      );
      expect(fixture.roles, {FixtureRole.agent}, reason: fixture.id);
      expect(
        fixture.spec.any((s) => s.startsWith('15-Extensibility.md')),
        isTrue,
        reason: fixture.id,
      );
    }
    for (final fixture in corpus.where(
      (f) => _usageLedgerFixtures.contains(f.id),
    )) {
      final caps = fixture.setup.clientCapabilities as Map?;
      final codelab = (caps?['_meta'] as Map?)?['codelab'] as Map?;
      expect(codelab?['usage'], {
        'version': 1,
      }, reason: '${fixture.id}: the client must declare usage');
    }
    // `acp/session-load-usage-partial` удалена: сумма после загрузки полная.
    expect(
      corpus.map((f) => f.id),
      isNot(contains('acp/session-load-usage-partial')),
    );
  });

  // D18 Т8: `acp/prompt-usage-steps`, `-unpriced` и `-cancelled` идут и во
  // встроенном агенте (`conformance:embedded`, `codelab-agent serve --stdio`),
  // поэтому без `setup.config` и `setup.sessions`; цены задаёт `llm.model.cost`.
  // Отступление от текста задачи 1.5: `acp/compact-usage-context` несёт
  // `setup.config.compaction.keep_recent_tokens: 512`, как `acp/slash-compact`:
  // с порогом по умолчанию (16384 токена хвоста) короткая история не
  // сжимается и `ContextCompacted` не возникает; такая фикстура — только
  // `conformance:agent`.
  test('the usage fixtures for all modes have no setup.config/sessions', () {
    final byId = {for (final f in corpus) f.id: f};
    for (final id in const [
      'acp/prompt-usage-steps',
      'acp/prompt-usage-unpriced',
      'acp/prompt-usage-cancelled',
    ]) {
      expect(byId[id]!.setup.config, isNull, reason: id);
      expect(byId[id]!.setup.sessions, isEmpty, reason: id);
    }
    expect(byId['acp/compact-usage-context']!.setup.config, {
      'compaction': {'keep_recent_tokens': 512},
    });
    expect(
      byId['acp/prompt-usage-compaction-off']!.setup.config,
      containsPair('compaction', {'enabled': false}),
    );
    final priced = byId['acp/prompt-usage-steps']!.llm!.model!;
    expect(priced['cost'], isA<Map>());
    expect(
      byId['acp/prompt-usage-unpriced']!.llm!.model!,
      isNot(contains('cost')),
    );
  });

  // acp-golden-fixtures «Фикстуры субагентов и списка задач»: роли заданы
  // таблицей спецификации, а не умолчанием.
  test('the tasks fixtures have the roles of the specification table', () {
    final roles = {for (final f in corpus) f.id: f.roles};
    expect(roles['acp/initialize-codelab-extensions'], {
      FixtureRole.agent,
      FixtureRole.client,
    });
    expect(roles['acp/prompt-task-plan'], {
      FixtureRole.agent,
      FixtureRole.client,
    });
    expect(roles['acp/session-load-legacy-plan'], {FixtureRole.agent});
    // Итерация 2 (задача 2.1): вызов `agent` проигрывают обе роли — агент
    // проецирует его, kit разбирает `_meta.codelab.subagent`.
    expect(roles['acp/prompt-subagent-tool-call'], {
      FixtureRole.agent,
      FixtureRole.client,
    });
    // Итерация 3 (задача 3.1): запрос ребёнка проигрывают обе роли — агент
    // шлёт `_meta.codelab.subagent`, kit читает его как `SubagentRequester`
    // (D43 п. 1).
    expect(roles['acp/prompt-subagent-permission'], {
      FixtureRole.agent,
      FixtureRole.client,
    });
    // Итерация 4 (задача 4.1): запрос внука проигрывает только агент — kit
    // читает тот же `SubagentRequester`, нового поведения клиента нет
    // (acp-golden-fixtures; design.md D45 Т1).
    expect(roles['acp/prompt-subagent-nested-permission'], {FixtureRole.agent});
    // Итерация 5 (задача 5.1): дерево вызовов потомков и его реплей играют
    // обе роли — агент проецирует кадры, kit строит дерево (D47 Т8).
    for (final id in const [
      'acp/prompt-subagent-tool-tree',
      'acp/session-load-subagent-tool-tree',
    ]) {
      expect(roles[id], {FixtureRole.agent, FixtureRole.client}, reason: id);
    }
  });

  // «acp/initialize-capabilities SHALL остаться вариантом "клиент без _meta"
  // с ролью agent»: блок объявлений ответа зависит от клиента (D9).
  test('initialize-capabilities is the agent-only no-_meta variant', () {
    final fixture = corpus.singleWhere(
      (f) => f.id == 'acp/initialize-capabilities',
    );
    expect(fixture.roles, {FixtureRole.agent});
  });

  // «acp/prompt-update-plan SHALL остаться в корпусе только с ролью client»:
  // у Dart-агента инструмента update_plan больше нет.
  test('prompt-update-plan is played by the client role only', () {
    final fixture = corpus.singleWhere((f) => f.id == 'acp/prompt-update-plan');
    expect(fixture.roles, {FixtureRole.client});
  });

  // FIX-4: расширения объявлены по используемым данным — `task`,
  // `capabilities` (acp-golden-fixtures, вводная таблица).
  test('the tasks fixtures declare the extensions they use', () {
    final byId = {for (final f in corpus) f.id: f};
    expect(byId['acp/prompt-task-plan']!.extensions, contains('task'));
    expect(byId['acp/session-load-legacy-plan']!.extensions, contains('task'));
    expect(
      byId['acp/initialize-codelab-extensions']!.extensions,
      contains('capabilities'),
    );
    expect(
      byId['acp/prompt-subagent-tool-call']!.extensions,
      contains('subagent'),
    );
    expect(
      byId['acp/prompt-subagent-tool-tree']!.extensions,
      containsAll(['capabilities', 'subagent', 'parentToolCallId']),
    );
  });

  // D36 Т12, D45 Т9, D47 Т8: редакция итерации 5 — клиент объявляет и
  // `subagentToolCalls`, агент отвечает тем же ключом рядом с `subagents`
  // (`maxDepth: 3`) и `tasks`.
  test('initialize-codelab-extensions is the iteration 5 edition', () {
    final fixture = corpus.singleWhere(
      (f) => f.id == 'acp/initialize-codelab-extensions',
    );
    // change `add-usage-extension`, задача 1.5: ответ агента несёт `usage`
    // (D3), метка `usage` — в `extensions` (FIX-4). Кадр клиента ниже не
    // меняется до задачи 2.7 (D18 Т8).
    // change `add-usage-ledger`, задача 2.5 (D7): в ответе агента ещё и
    // `usageLedger`, метка `usageLedger` — в `extensions`; кадр клиента не
    // меняется (клиент `usageLedger` не объявляет).
    expect(
      fixture.extensions,
      containsAll(['capabilities', 'usage', 'usageLedger']),
    );
    expect(_agentCodelabBlock(fixture), {
      'subagents': {'version': 1, 'maxDepth': 3},
      'subagentToolCalls': {'version': 1},
      'tasks': {'version': 1},
      'usage': {'version': 1},
      'usageLedger': {'version': 1},
    });
    final request = fixture.frames
        .where((f) => f.direction == FrameDirection.c2a)
        .map((f) => f.frame!)
        .single;
    final partial = ((request['params'] as Map)[r'$partial'] as Map);
    final caps = partial['clientCapabilities'] as Map;
    expect(((caps['_meta'] as Map)['codelab'] as Map), {
      'tasks': {'version': 1},
      'subagents': {'version': 1},
      'subagentToolCalls': {'version': 1},
      'usage': {'version': 1},
    });
  });

  /// `tool_call` и `tool_call_update` кадров [frames] по порядку; обёртка
  /// `$partial` (кадр `in_progress` хука допускает `_meta`) снимается.
  List<Map<Object?, Object?>> toolFrames(Iterable<FixtureFrame> frames) => [
    for (final frame in frames)
      if (frame.direction == FrameDirection.a2c && frame.frame != null)
        if (((frame.frame!['params'] as Map?)?['update']) case final Map raw)
          if ((raw[r'$partial'] as Map? ?? raw) case final Map u)
            if (u['sessionUpdate'] == 'tool_call' ||
                u['sessionUpdate'] == 'tool_call_update')
              u.cast<Object?, Object?>(),
  ];

  // D47 Т8: фикстуры дерева задают согласие `subagentToolCalls` через
  // `setup.clientCapabilities`; без него агент вызовов потомков не пришлёт.
  test('the tool tree fixtures declare the subagentToolCalls consent', () {
    for (final id in const [
      'acp/prompt-subagent-tool-tree',
      'acp/session-load-subagent-tool-tree',
    ]) {
      final fixture = corpus.singleWhere((f) => f.id == id);
      final caps = fixture.setup.clientCapabilities!;
      final codelab = (caps['_meta'] as Map)['codelab'] as Map;
      expect(codelab['subagentToolCalls'], {'version': 1}, reason: id);
      expect(
        fixture.extensions,
        containsAll(['capabilities', 'subagent', 'parentToolCallId']),
        reason: id,
      );
    }
  });

  // agent-acp-server «Вызовы ребёнка и внука», «Статусы вызова потомка», D47
  // Т2, Т3, Q16: цепочка `toolCallId`, `parentToolCallId`, `{id, type}` внука
  // в первом кадре, `summary` в финальном обновлении, `pending → in_progress →
  // итог` вызовов потомков.
  test('prompt-subagent-tool-tree fixes the chain, the parent and the '
      'statuses of the descendants', () {
    final fixture = corpus.singleWhere(
      (f) => f.id == 'acp/prompt-subagent-tool-tree',
    );
    final frames = toolFrames(fixture.frames);
    Map<Object?, Object?> codelab(Map<Object?, Object?> u) =>
        ((u['_meta'] as Map?)?['codelab'] as Map? ?? const {})
            .cast<Object?, Object?>();

    final calls = frames.where((u) => u['sessionUpdate'] == 'tool_call');
    expect(calls.map((u) => u['toolCallId']), [
      'call_1',
      'call_1/call_1',
      'call_1/call_2',
      'call_1/call_2/call_1',
    ]);
    expect(calls.map((u) => codelab(u)['parentToolCallId']), [
      null,
      'call_1',
      'call_1',
      'call_1/call_2',
    ]);
    final nested = calls.singleWhere((u) => u['toolCallId'] == 'call_1/call_2');
    expect((codelab(nested)['subagent'] as Map).keys.toSet(), {'id', 'type'});
    expect((codelab(nested)['subagent'] as Map)['type'], 'explore');

    // Последовательность статусов каждого вызова потомка без строк
    // прогресса (у них `content`).
    for (final id in const [
      'call_1/call_1',
      'call_1/call_2',
      'call_1/call_2/call_1',
    ]) {
      final statuses = [
        for (final u in frames)
          if (u['toolCallId'] == id && u['content'] == null ||
              u['toolCallId'] == id && u['status'] == 'completed')
            u['status'],
      ];
      expect(statuses, ['pending', 'in_progress', 'completed'], reason: id);
    }

    final finalNested = frames.lastWhere(
      (u) => u['toolCallId'] == 'call_1/call_2' && u['status'] == 'completed',
    );
    final summary =
        ((codelab(finalNested)['subagent'] as Map)['summary'] as Map);
    expect(summary['toolCalls'], 1);
    expect(summary['tokens'], {'input': 1600, 'output': 150});
    final finalRoot = frames.lastWhere(
      (u) => u['toolCallId'] == 'call_1' && u['status'] == 'completed',
    );
    expect(codelab(finalRoot)['parentToolCallId'], isNull);
    expect(
      ((codelab(finalRoot)['subagent'] as Map)['summary'] as Map)['toolCalls'],
      3,
    );
  });

  // agent-acp-server «Реплей дерева», D47 Т6, Т7: живой ход, затем
  // `session/load` в том же соединении; вызовы потомков идут сразу после
  // `tool_call` вызова `agent` корня, рекурсивно, с итоговыми статусами.
  test('session-load-subagent-tool-tree replays the descendants right after '
      'the agent call', () {
    final fixture = corpus.singleWhere(
      (f) => f.id == 'acp/session-load-subagent-tool-tree',
    );
    final loadIndex = fixture.frames.indexWhere(
      (f) => f.frame?['method'] == 'session/load',
    );
    expect(loadIndex, isPositive);
    final replayed = toolFrames(fixture.frames.skip(loadIndex));
    expect(replayed.map((u) => u['toolCallId']), [
      'call_1',
      'call_1/call_1',
      'call_1/call_2',
      'call_1/call_2/call_1',
    ]);
    expect(
      replayed.map((u) => u['status']),
      everyElement('completed'),
      reason: 'реплей отдаёт вызов одним кадром с итоговым статусом',
    );
    expect(
      [
        for (final u in replayed)
          ((u['_meta'] as Map?)?['codelab'] as Map?)?['parentToolCallId'],
      ],
      [null, 'call_1', 'call_1', 'call_1/call_2'],
    );
  });

  // D28, D24: первый `tool_call` вызова `agent` несёт `{id, type}`, финальное
  // обновление — `summary`; вызовов ребёнка среди кадров нет.
  test('prompt-subagent-tool-call fixes the subagent _meta and no child '
      'tool calls', () {
    final fixture = corpus.singleWhere(
      (f) => f.id == 'acp/prompt-subagent-tool-call',
    );
    final updates = [
      for (final frame in fixture.frames)
        if (frame.direction == FrameDirection.a2c && frame.frame != null)
          if (((frame.frame!['params'] as Map?)?['update']) case final Map u) u,
    ];
    final calls = updates.where((u) => u['sessionUpdate'] == 'tool_call');
    expect(calls.map((u) => u['toolCallId']), ['call_1']);
    final subagent = ((calls.single['_meta'] as Map)['codelab'] as Map);
    expect((subagent['subagent'] as Map)['type'], 'explore');
    final last = updates.lastWhere(
      (u) => u['sessionUpdate'] == 'tool_call_update' && u['status'] != null,
    );
    expect(last['status'], 'completed');
    final summary =
        ((((last['_meta'] as Map)['codelab'] as Map)['subagent']
                as Map)['summary']
            as Map);
    expect(summary['toolCalls'], 3);
    expect(summary['tokens'], {'input': 6000, 'output': 400});
  });

  test('the unknown tool kind fixture is played by the client role only', () {
    final fixture = corpus.singleWhere((f) => _toolKindFixtures.contains(f.id));
    expect(fixture.roles, {FixtureRole.client});
  });

  test('MCP and project files fixtures are played by the agent role only', () {
    for (final fixture in corpus.where(
      (f) =>
          _stage8McpFixtures.contains(f.id) ||
          _stage8ProjectFilesFixtures.contains(f.id) ||
          _slashCommandFixtures.contains(f.id) ||
          _skillFixtures.contains(f.id),
    )) {
      expect(fixture.roles, {FixtureRole.agent}, reason: fixture.id);
    }
  });

  for (final fixture in corpus) {
    group(fixture.id, () {
      test('FIX-1: spec references exist', () {
        expect(
          specReferenceViolations(
            fixture,
            protocolDirectory: protocolDirectory,
          ),
          isEmpty,
        );
      });

      test('FIX-4: no undeclared extensions', () {
        expect(undeclaredExtensionViolations(fixture), isEmpty);
      });
    });
  }

  // `llm.model.cost` (change `add-usage-extension`, D18 Т8; задача 1.5a):
  // цены модели сценария, доллары за 10^6 токенов, как `ModelCost` ядра.
  // Без поля цены неизвестны — отсюда `noPrice` в фикстуре
  // `acp/prompt-usage-unpriced`. Неизвестный ключ и не число — громкий отказ
  // загрузки с путём (§14.9, шаг 1).
  group('llm.model.cost', () {
    AcpFixture parse(Object? cost) => AcpFixture.fromJson({
      'id': 'acp/cost-model',
      'spec': ['05-Prompt Turn.md#1-user-message'],
      'description': 'Фикстура теста цен модели.',
      'setup': {'cwd': '/work/demo'},
      'llm': {
        'model': {
          'provider': 'scripted',
          'modelId': 'scripted-1',
          'contextWindow': 32768,
          'cost': ?cost,
        },
        'steps': <Object?>[],
      },
      'frames': [
        {
          'dir': 'c2a',
          'frame': {
            'jsonrpc': '2.0',
            'method': 'session/cancel',
            'params': {'sessionId': r'${sessionId}'},
          },
        },
      ],
    }, fileName: 'cost-model.json');

    Matcher failsAt(String path) => throwsA(
      isA<FixtureFormatException>().having((e) => e.path, 'path', path),
    );

    test('input and output are accepted', () {
      final fixture = parse({'input': 3, 'output': 15});

      expect(fixture.llm!.model!['cost'], {'input': 3, 'output': 15});
    });

    test('cacheRead, cacheWrite and fractional prices are accepted', () {
      final fixture = parse({
        'input': 3.5,
        'output': 15,
        'cacheRead': 0.3,
        'cacheWrite': 3.75,
      });

      expect(fixture.llm!.model!['cost'], containsPair('cacheWrite', 3.75));
    });

    test('an unknown key fails with its path', () {
      expect(
        () => parse({'input': 3, 'output': 15, 'reasoning': 1}),
        failsAt(r'$.llm.model.cost.reasoning'),
      );
    });

    test('a non-numeric price fails with its path', () {
      expect(
        () => parse({'input': '3', 'output': 15}),
        failsAt(r'$.llm.model.cost.input'),
      );
      expect(
        () => parse({'input': 3, 'output': 15, 'cacheRead': true}),
        failsAt(r'$.llm.model.cost.cacheRead'),
      );
    });

    test('input and output are required', () {
      expect(() => parse({'input': 3}), failsAt(r'$.llm.model.cost.output'));
      expect(() => parse({'output': 3}), failsAt(r'$.llm.model.cost.input'));
    });

    // Отрицательная или не конечная цена бессмысленна и ломает расчёт
    // стоимости у потребителя: отказ загрузки (D19 п. 6). Отрицательная — с
    // путём ключа; не конечная (JSON её не выражает, `1e999` декодируется в
    // Infinity) — отказом канонизации.
    test('a negative price fails with its path, a non-finite one fails', () {
      expect(
        () => parse({'input': -1, 'output': 15}),
        failsAt(r'$.llm.model.cost.input'),
      );
      // Не конечное число отсекает канонизация фикстуры до разбора ключей.
      expect(
        () => parse({'input': 3, 'output': double.infinity}),
        throwsA(isA<FixtureFormatException>()),
      );
      expect(
        () => parse({'input': 3, 'output': 15, 'cacheRead': double.nan}),
        throwsA(isA<FixtureFormatException>()),
      );
      expect(
        () => parse({'input': 3, 'output': 15, 'cacheWrite': -0.5}),
        failsAt(r'$.llm.model.cost.cacheWrite'),
      );
    });

    test('a zero price is accepted', () {
      expect(parse({'input': 0, 'output': 0}).llm!.model, contains('cost'));
    });

    test('the schema forbids negative prices', () {
      final schema =
          jsonDecode(File('fixtures/acp/_schema.json').readAsStringSync())
              as Map<String, Object?>;
      final props =
          ((schema[r'$defs']! as Map)['llmModelCost']! as Map)['properties']!
              as Map;
      for (final key in ['input', 'output', 'cacheRead', 'cacheWrite']) {
        expect((props[key]! as Map)['minimum'], 0, reason: key);
      }
    });

    test('cost must be an object', () {
      expect(() => parse(3), failsAt(r'$.llm.model.cost'));
    });

    test('a model without cost stays valid', () {
      expect(parse(null).llm!.model, isNot(contains('cost')));
    });
  });

  group('invariant checks on a temporary corpus', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('acp_fixture_invariants_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    AcpFixture write(
      String name, {
      List<String> spec = const ['05-Prompt Turn.md#cancellation'],
      List<String>? extensions,
      Map<String, Object?> frame = const {
        'jsonrpc': '2.0',
        'method': 'session/cancel',
        'params': {'sessionId': r'${sessionId}'},
      },
    }) {
      File('${dir.path}/$name.json').writeAsStringSync(
        jsonEncode({
          'id': 'acp/$name',
          'spec': spec,
          'description': 'Временная фикстура теста инвариантов.',
          'extensions': ?extensions,
          'setup': <String, Object?>{},
          'frames': [
            {'dir': 'c2a', 'frame': frame},
          ],
        }),
      );
      return loadFixtureCorpus(
        directory: dir.path,
      ).singleWhere((f) => f.id == 'acp/$name');
    }

    test('a valid reference passes', () {
      expect(
        specReferenceViolations(
          write('valid'),
          protocolDirectory: protocolDirectory,
        ),
        isEmpty,
      );
    });

    test('a reference to a missing file names the fixture and the link', () {
      expect(
        specReferenceViolations(
          write('missing-file', spec: ['99-Nothing.md#cancellation']),
          protocolDirectory: protocolDirectory,
        ),
        [contains('acp/missing-file: spec "99-Nothing.md#cancellation"')],
      );
    });

    test('a reference to a missing anchor fails', () {
      expect(
        specReferenceViolations(
          write('missing-anchor', spec: ['05-Prompt Turn.md#no-such-part']),
          protocolDirectory: protocolDirectory,
        ),
        [contains('no anchor #no-such-part')],
      );
    });

    test('a reference without an anchor fails', () {
      expect(
        specReferenceViolations(
          write('no-anchor', spec: ['05-Prompt Turn.md']),
          protocolDirectory: protocolDirectory,
        ),
        [contains('no #anchor')],
      );
    });

    test('_meta.codelab without extensions fails', () {
      final frame = {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {
          'stopReason': 'cancelled',
          '_meta': {
            'codelab': {'outcome': 'cancelled'},
          },
        },
      };
      expect(undeclaredExtensionViolations(write('meta', frame: frame)), [
        contains(r'$.frames[0].result._meta.codelab'),
      ]);
      expect(
        undeclaredExtensionViolations(
          write('meta-declared', frame: frame, extensions: ['outcome']),
        ),
        isEmpty,
      );
    });

    test('data.codelab and _codelab/* methods without extensions fail', () {
      expect(
        undeclaredExtensionViolations(
          write(
            'data',
            frame: {
              'jsonrpc': '2.0',
              'id': 1,
              'error': {
                'code': -32603,
                'message': 'failed',
                'data': {
                  'codelab': {'errorClass': 'auth'},
                },
              },
            },
          ),
        ),
        hasLength(1),
      );
      expect(
        undeclaredExtensionViolations(
          write(
            'method',
            frame: {'jsonrpc': '2.0', 'method': '_codelab/session/steer'},
          ),
        ),
        hasLength(1),
      );
    });
  });

  group('markdown anchors', () {
    test('headings become slugs, explicit anchors are kept', () {
      expect(
        markdownAnchors(
          '# Prompt Turn\n'
          '### 5. Tool Invocation and Status Reporting\n'
          '#### <span class="font-mono">WriteTextFileResponse</span>\n'
          '## The `_meta` Field\n'
          '<a id="fs-write_text_file" />\n',
        ),
        {
          'prompt-turn',
          '5-tool-invocation-and-status-reporting',
          'writetextfileresponse',
          'the-_meta-field',
          'fs-write_text_file',
        },
      );
    });
  });
}
