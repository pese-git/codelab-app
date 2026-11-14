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

/// Фикстуры change `add-subagents-and-tasks` итераций 1–2 (acp-golden-fixtures
/// «Фикстуры субагентов и списка задач»). Остальные фикстуры change
/// (`acp/prompt-subagent-permission`, `-nested-permission`, `-tool-tree`,
/// `acp/session-load-subagent-tool-tree`) приходят с итерациями 3–5 и
/// добавляются сюда вместе с ними.
const _tasksFixtures = {
  'acp/initialize-codelab-extensions',
  'acp/prompt-task-plan',
  'acp/prompt-subagent-tool-call',
  'acp/session-load-legacy-plan',
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
    });
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
  });

  // D36 Т12: редакция итерации 2 не объявляет `subagentToolCalls` — агент ещё
  // не проецирует вызовы потомков; ключ придёт с задачей 5.2.
  test('initialize-codelab-extensions is the iteration 2 edition', () {
    final fixture = corpus.singleWhere(
      (f) => f.id == 'acp/initialize-codelab-extensions',
    );
    final block = _agentCodelabBlock(fixture);
    expect(block, {
      'subagents': {'version': 1, 'maxDepth': 1},
      'tasks': {'version': 1},
    });
    expect(block, isNot(contains('subagentToolCalls')));
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
