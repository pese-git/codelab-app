import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
// Тест читает применённый снимок рантайма: это шов тестов, а не публичный API
// (PKG-5).
import 'package:codelab_agent_core/src/runtime/agent_runtime.dart'
    show AgentRuntimeImpl;
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../config/config_support.dart' show baseValues, layer;
import '../host/core_harness.dart' show inMemoryJournal, noExec, textStep;
import '../support/manual_stream.dart';

/// Встроенные команды `/config` и `/mcp` (agent-slash-commands «Встроенные
/// команды config и mcp», «Список команд сессии»; design.md change
/// `add-config-writer-and-reload`, D10, D11, D12, R0-3, R7-1, R7-2;
/// `agent-core/17-5-agent-setup.md` §17.5.6, §17.5.7).
///
/// Тесты идут через публичный `AgentSession.prompt` и `events`: проверяется
/// то, что видит хост (мост ACP, встроенный агент, `codelab`), а не классы
/// реализации. Коннектор — `_Connector` с состоянием серверов; источник
/// конфига — `_Source` с воротами загрузки.
void main() {
  group('the list of the session commands', () {
    test('config and mcp come first, then the templates '
        '(scenario "Встроенные команды идут первыми")', () async {
      final rig = await _Rig.create(templates: ['review']);
      final session = await rig.session();

      expect(
        [for (final c in session.commands) c.name],
        ['config', 'mcp', 'review'],
      );
      expect(
        [for (final c in session.commands) c.source],
        [
          SlashCommandSource.builtin,
          SlashCommandSource.builtin,
          SlashCommandSource.template,
        ],
      );
    });

    test('the declarations are byte for byte (D12)', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final config = session.commands[0];
      expect(config.name, 'config');
      expect(config.description, 'Reload or check the agent config');
      expect(config.inputHint, 'reload | check');
      final mcp = session.commands[1];
      expect(mcp.name, 'mcp');
      expect(mcp.description, 'List, reload, enable or disable MCP servers');
      expect(
        mcp.inputHint,
        'list | reload [<id>] | enable <id> | disable <id>',
      );
    });

    test('without a ConfigSource there is no config: the prompt goes to the '
        'model as text (scenario "Без источника конфига")', () async {
      final rig = await _Rig.create(withSource: false);
      final session = await rig.session();

      expect([for (final c in session.commands) c.name], ['mcp']);
      await session.prompt(const [TextContent('/config reload')]);

      expect(rig.streamCalls, 1);
      expect(rig.lastUserText, '/config reload');
    });

    test('configCommand: false (serve --ws) hides config, mcp stays; the '
        'prompt goes to the model (scenario "WebSocket без /config", '
        'R0-3)', () async {
      final rig = await _Rig.create(configCommand: false);
      final session = await rig.session();

      expect([for (final c in session.commands) c.name], ['mcp']);
      await session.prompt(const [TextContent('/config check')]);

      expect(rig.streamCalls, 1);
      expect(rig.lastUserText, '/config check');
      expect(rig.source.loads, 0, reason: 'nothing was loaded');
    });

    test('the signal of the watcher still reloads without the command '
        '(scenario "WebSocket без /config")', () async {
      final rig = await _Rig.create(configCommand: false);
      _put(rig.user, 'budget.max_steps', 20);

      rig.source.signal();
      await pumpEventQueue();

      expect(rig.runtime.appliedValues['budget.max_steps'], 20);
    });

    test('with the capability mcp off there is no mcp; the prompt goes to '
        'the model (D12)', () async {
      final rig = await _Rig.create(mcpCapability: false);
      final session = await rig.session();

      expect([for (final c in session.commands) c.name], ['config']);
      await session.prompt(const [TextContent('/mcp list')]);

      expect(rig.streamCalls, 1);
      expect(rig.lastUserText, '/mcp list');
    });

    test(
      'an unknown /x without a template goes to the model as before',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();

        await session.prompt(const [TextContent('/frobnicate now')]);

        expect(rig.streamCalls, 1);
        expect(rig.lastUserText, '/frobnicate now');
      },
    );

    test('a reload does not change the list of a live session '
        '(scenario "Перезагрузка не меняет список")', () async {
      final rig = await _Rig.create(templates: ['review']);
      final session = await rig.session();
      final before = [for (final c in session.commands) c.name];
      _put(rig.user, 'trusted_projects', ['/proj']);

      final reply = await rig.ask(session, '/config reload');

      expect(
        reply.text,
        'Config reloaded: no keys applied now.\n'
        'Restart required: trusted_projects',
      );
      expect([for (final c in session.commands) c.name], before);
    });
  });

  group('the answer is not a turn of the model', () {
    test('events: TurnStarted, one message, TurnEnded(completed); the model '
        'is not asked; the journal is not touched (CFG-18, scenario '
        '"/mcp list без модели")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final journal = rig.store.textOf(session.id);

      final reply = await rig.ask(session, '/mcp list');

      expect(
        [for (final e in reply.events) e.runtimeType],
        [TurnStarted, MessageStarted, MessageDelta, MessageEnded, TurnEnded],
      );
      expect((reply.events.last as TurnEnded).reason, TurnEndReason.completed);
      expect(reply.result.reason, TurnEndReason.completed);
      expect(rig.streamCalls, 0);
      expect(rig.store.textOf(session.id), journal);
    });

    test('the journal stays untouched for every command', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      final journal = rig.store.textOf(session.id);

      for (final text in [
        '/config reload',
        '/config check',
        '/config frob',
        '/mcp',
        '/mcp reload',
        '/mcp reload a',
        '/mcp disable a',
        '/mcp enable a',
        '/mcp reload nope',
        '/mcp frob',
      ]) {
        await rig.ask(session, text);
      }

      expect(rig.store.textOf(session.id), journal);
      expect(rig.streamCalls, 0);
    });

    test('command.builtin has the session, the name and the subcommand, '
        'never the arguments (§16)', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();

      await rig.ask(session, '/mcp reload secret-token-123');
      await rig.ask(session, '/mcp');
      await rig.ask(session, '/config check');
      await rig.ask(session, '/config top-secret-arg');

      final logs = rig.logger.eventsOf('command.builtin');
      expect(
        [for (final l in logs) l.fields],
        [
          {
            'session_id': session.id.value,
            'name': 'mcp',
            'subcommand': 'reload',
          },
          {'session_id': session.id.value, 'name': 'mcp', 'subcommand': 'list'},
          {
            'session_id': session.id.value,
            'name': 'config',
            'subcommand': 'check',
          },
          {
            'session_id': session.id.value,
            'name': 'config',
            'subcommand': 'usage',
          },
        ],
      );
      expect(
        [for (final r in rig.logger.records) r.toString()].join('\n'),
        isNot(contains('secret-token-123')),
      );
    });
  });

  group('/config reload (R7-1, R7-2)', () {
    test('without a difference: Config unchanged.', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final reply = await rig.ask(session, '/config reload');

      expect(reply.text, 'Config unchanged.');
      expect(rig.source.rebases, [true]);
    });

    test('one changed key: the singular (R7-2, scenario "Один изменённый '
        'ключ")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      _put(rig.user, 'budget.max_steps', 20);

      final reply = await rig.ask(session, '/config reload');

      expect(reply.text, 'Config reloaded: 1 key changed.');
    });

    test('two changed keys: the plural', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      _put(rig.user, 'budget.max_steps', 20);
      _put(rig.user, 'budget.max_tokens', 1000);

      final reply = await rig.ask(session, '/config reload');

      expect(reply.text, 'Config reloaded: 2 keys changed.');
    });

    test('applied and deferred keys: the count, then the Restart required '
        'line', () async {
      final rig = await _Rig.create(
        extra: {
          'logging': {'file': '/var/a.log'},
        },
      );
      final session = await rig.session();
      _put(rig.user, 'budget.max_steps', 20);
      _put(rig.user, 'logging.file', '/var/b.log');
      _put(rig.user, 'trusted_projects', ['/proj']);

      final reply = await rig.ask(session, '/config reload');

      expect(
        reply.text,
        'Config reloaded: 1 key changed.\n'
        'Restart required: logging.file, trusted_projects',
      );
    });

    test('only deferred keys: no keys applied now, never 0 keys changed '
        '(R7-1, scenario "Перезагрузка только с отложенными ключами"); the '
        'repeat gives the same answer', () async {
      final rig = await _Rig.create(
        extra: {
          'logging': {'file': '/var/a.log'},
        },
      );
      final session = await rig.session();
      _put(rig.user, 'logging.file', '/var/b.log');
      _put(rig.user, 'trusted_projects', ['/proj']);
      const expected =
          'Config reloaded: no keys applied now.\n'
          'Restart required: logging.file, trusted_projects';

      final first = await rig.ask(session, '/config reload');
      final again = await rig.ask(session, '/config reload');

      expect(first.text, expected);
      expect(again.text, expected, reason: 'scenario "Повторная перезагрузка"');
      expect(first.text, isNot(contains('0 keys')));
      expect(first.text, isNot(contains('unchanged')));
    });

    test('one issue: the singular (R7-2, scenario "Одна проблема при '
        'перезагрузке")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      _put(rig.user, 'compaction.reserve_token', 1);

      final reply = await rig.ask(session, '/config reload');

      expect(
        reply.text,
        'Config reload failed (1 issue). Current settings kept. '
        'Run /config check.',
      );
    });

    test('two issues: the plural', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      _put(rig.user, 'compaction.reserve_token', 1);
      _put(rig.user, 'budget.max_step', 1);

      final reply = await rig.ask(session, '/config reload');

      expect(
        reply.text,
        'Config reload failed (2 issues). Current settings kept. '
        'Run /config check.',
      );
    });
  });

  group('/config check', () {
    test(
      'valid: the first line is exactly Config: valid, then Sources',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();

        final reply = await rig.ask(session, '/config check');

        final sources = (await rig.source.load(rebase: false)).sources;
        expect(sources, isNotEmpty);
        expect(reply.text, 'Config: valid\nSources: ${sources.join(', ')}');
        expect(rig.source.rebases, [
          false,
          false,
        ], reason: 'a check never rebases');
      },
    );

    test('invalid: the count, a line per issue as ConfigIssue.toString(), '
        'the snapshot is not changed (scenario "/config check после ручной '
        'ошибки")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      _put(rig.user, 'compaction.reserve_token', 1);
      final applied = rig.runtime.appliedValues;

      final reply = await rig.ask(session, '/config check');

      final loaded = await rig.source.load(rebase: false);
      expect(loaded.issues, hasLength(1));
      final lines = reply.text.split('\n');
      expect(lines.first, 'Config: invalid (issues: 1)');
      expect(lines[1], '- ${loaded.issues.single}');
      expect(
        lines[1],
        contains(
          'compaction.reserve_token: unknown key (did you mean '
          'reserve_tokens?)',
        ),
      );
      expect(lines[2], 'Sources: ${loaded.sources.join(', ')}');
      expect(rig.runtime.appliedValues, applied);
    });

    test(
      'the plural has no declension: issues: 2 (R7-2 does not touch it)',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();
        _put(rig.user, 'compaction.reserve_token', 1);
        _put(rig.user, 'budget.max_step', 1);

        final reply = await rig.ask(session, '/config check');

        expect(reply.text.split('\n').first, 'Config: invalid (issues: 2)');
      },
    );

    test(
      'deferred keys: the line Restart required, nothing is applied',
      () async {
        final rig = await _Rig.create(
          extra: {
            'logging': {'file': '/var/a.log'},
          },
        );
        final session = await rig.session();
        _put(rig.user, 'logging.file', '/var/b.log');
        _put(rig.user, 'budget.max_steps', 20);

        final reply = await rig.ask(session, '/config check');

        final lines = reply.text.split('\n');
        expect(lines.first, 'Config: valid');
        expect(lines.last, 'Restart required: logging.file');
        expect(rig.runtime.appliedValues['budget.max_steps'], isNull);
      },
    );

    test('Usage for another argument and for none', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      for (final text in ['/config', '/config frob', '/config reload now']) {
        final reply = await rig.ask(session, text);
        expect(
          reply.text,
          'Usage: /config reload | /config check',
          reason: text,
        );
      }
      expect(rig.source.loads, 0);
    });
  });

  group('/mcp list', () {
    test('the table of three servers byte for byte (§17.5.7, scenario '
        '"/mcp list без модели")', () async {
      final rig = await _Rig.create(
        servers: [_http('github'), _stdio('local-db', enabled: false)],
      );
      final session = await rig.session(
        mcp: [const McpStdioServerConfig(name: 'docs', command: 'docs-mcp')],
      );
      rig
          .tools(session)
          .preset(
            const McpServerSummary(
              name: 'github',
              toolCount: 12,
              origin: McpServerOrigin.config,
              transport: 'http',
            ),
          );
      rig
          .tools(session)
          .preset(
            const McpServerSummary(
              name: 'local-db',
              toolCount: 0,
              origin: McpServerOrigin.config,
              state: McpServerState.disabled,
              lastError: 'disabled by /mcp disable',
            ),
          );
      rig
          .tools(session)
          .preset(
            const McpServerSummary(
              name: 'docs',
              toolCount: 4,
              state: McpServerState.failed,
              lastError: 'process exited with code 1',
              retryIn: Duration(seconds: 8),
            ),
          );

      final reply = await rig.ask(session, '/mcp list');

      expect(
        reply.text,
        '```text\n'
        'MCP servers (3)\n'
        'ID        SOURCE   TRANSPORT  STATE      TOOLS  LAST ERROR\n'
        'github    config   http       connected  12     -\n'
        'local-db  config   stdio      disabled   0      disabled by /mcp disable\n'
        'docs      session  stdio      failed     4      process exited with code 1 (retry in 8s)\n'
        '```',
      );
    });

    test('/mcp without an argument is the same as list', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();

      final bare = await rig.ask(session, '/mcp');
      final list = await rig.ask(session, '/mcp list');

      expect(bare.text, list.text);
      expect(bare.text, startsWith('```text\nMCP servers (1)\n'));
    });

    test('no servers: No MCP servers. without a block', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final reply = await rig.ask(session, '/mcp list');

      expect(reply.text, 'No MCP servers.');
    });

    test('the table is the state at the moment of the answer', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      rig
          .tools(session)
          .preset(
            const McpServerSummary(
              name: 'a',
              toolCount: 2,
              origin: McpServerOrigin.config,
              transport: 'http',
              state: McpServerState.failed,
              lastError: 'connection refused',
              retryIn: Duration(seconds: 3),
            ),
          );

      final reply = await rig.ask(session, '/mcp list');

      expect(
        reply.text,
        contains('failed  2      connection refused (retry in 3s)'),
      );
    });

    test('Usage for another argument; the argument is not echoed', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      const usage =
          'Usage: /mcp list | /mcp reload [<id>] | /mcp enable <id> | '
          '/mcp disable <id>';

      for (final text in [
        '/mcp frob',
        '/mcp enable',
        '/mcp disable',
        '/mcp list extra',
      ]) {
        final reply = await rig.ask(session, text);
        expect(reply.text, usage, reason: text);
      }
      final tools = rig.tools(session);
      expect(tools.reconnected, isEmpty);
      expect(tools.enabledCalls, isEmpty);
    });
  });

  group('/mcp reload', () {
    test('reloads the config, wakes only the failed servers, then the '
        'summary line and the table of the moment of the answer', () async {
      final rig = await _Rig.create(servers: [_http('a'), _http('b')]);
      final session = await rig.session();
      rig
          .tools(session)
          .preset(
            const McpServerSummary(
              name: 'b',
              toolCount: 0,
              origin: McpServerOrigin.config,
              transport: 'http',
              state: McpServerState.failed,
              lastError: 'connection refused',
              retryIn: Duration(seconds: 8),
            ),
          );

      final reply = await rig.ask(session, '/mcp reload');

      expect(rig.source.loads, 1);
      expect(rig.tools(session).reconnected, ['b']);
      expect(
        reply.text,
        'Config unchanged.\n'
        '```text\n'
        'MCP servers (2)\n'
        'ID  SOURCE  TRANSPORT  STATE      TOOLS  LAST ERROR\n'
        'a   config  http       connected  0      -\n'
        'b   config  http       connected  0      -\n'
        '```',
        reason: 'the fake connector turns a reconnected server into connected',
      );
    });

    test('the summary line is the one of /config reload, with the singular '
        '(R7-2)', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      _put(rig.user, 'budget.max_steps', 20);

      final reply = await rig.ask(session, '/mcp reload');

      expect(reply.text.split('\n').first, 'Config reloaded: 1 key changed.');
    });

    test('only deferred keys: no keys applied now, Restart required, then the '
        'table without the deferred server (R7-1, scenario "/mcp reload '
        'только с отложенными ключами")', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [_http('a'), _stdio('x')]);

      final reply = await rig.ask(session, '/mcp reload');

      final lines = reply.text.split('\n');
      expect(lines[0], 'Config reloaded: no keys applied now.');
      expect(lines[1], 'Restart required: mcp.servers[x]');
      expect(lines[2], '```text');
      expect(reply.text, contains('MCP servers (1)'));
      expect(reply.text, isNot(contains('\nx ')));
    });

    test('one issue and two issues: MCP servers unchanged, the singular and '
        'the plural (R7-2); no server is woken', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      rig
          .tools(session)
          .preset(
            const McpServerSummary(
              name: 'a',
              toolCount: 0,
              origin: McpServerOrigin.config,
              transport: 'http',
              state: McpServerState.failed,
              lastError: 'connection refused',
              retryIn: Duration(seconds: 8),
            ),
          );
      _put(rig.user, 'compaction.reserve_token', 1);

      final one = await rig.ask(session, '/mcp reload');
      _put(rig.user, 'budget.max_step', 1);
      final two = await rig.ask(session, '/mcp reload');

      expect(
        one.text.split('\n').first,
        'Config reload failed (1 issue); MCP servers unchanged. '
        'Run /config check.',
      );
      expect(
        two.text.split('\n').first,
        'Config reload failed (2 issues); MCP servers unchanged. '
        'Run /config check.',
      );
      expect(one.text, contains('connection refused (retry in 8s)'));
      expect(rig.tools(session).reconnected, isEmpty);
    });

    test('the replacement caused by the command is applied before the '
        'answer; the deferred one of a turn is applied at TurnEnded '
        '(scenario "/mcp reload после отложенной замены")', () async {
      final rig = await _Rig.create(
        servers: [_http('a'), _http('b')],
        hold: true,
      );
      final session = await rig.session();
      final turn = session.prompt(const [TextContent('go')]);
      await pumpEventQueue();
      expect(rig.manual!.calls, 1, reason: 'the turn of the model runs');
      _put(rig.user, 'mcp.servers', [_http('a')]);
      await rig.runtime.reloadConfig();
      expect(rig.tools(session).replaced, isEmpty, reason: 'deferred');
      await session.cancel();
      await turn;
      await pumpEventQueue();
      _put(rig.user, 'mcp.servers', [_http('a'), _http('c')]);

      final reply = await rig.ask(session, '/mcp reload');

      expect(reply.text, contains('MCP servers (2)'));
      expect(reply.text, contains('\na  '));
      expect(reply.text, contains('\nc  '));
      expect(reply.text, isNot(contains('\nb  ')));
    });

    test('the second prompt during the command is rejected as during a turn '
        'of the model, without the ACP bridge; the command answers '
        '(scenario "Параллельный промпт во время /mcp reload")', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      final gate = rig.source.gate = Completer<void>();

      final first = rig.ask(session, '/mcp reload');
      await pumpEventQueue();
      expect(rig.source.loads, 1, reason: 'waits for the load of the config');

      await expectLater(
        session.prompt(const [TextContent('hello')]),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        session.prompt(const [TextContent('/mcp list')]),
        throwsA(isA<StateError>()),
      );
      gate.complete();
      final reply = await first;

      expect(reply.text, startsWith('Config unchanged.\n```text\n'));
      expect(rig.streamCalls, 0);
    });
  });

  group('/mcp reload <id>', () {
    test('reconnects the server without reading the config; the answer is '
        'the table', () async {
      final rig = await _Rig.create(servers: [_http('a'), _http('b')]);
      final session = await rig.session();

      final reply = await rig.ask(session, '/mcp reload b');

      expect(rig.tools(session).reconnected, ['b']);
      expect(rig.source.loads, 0);
      expect(reply.text, startsWith('```text\nMCP servers (2)\n'));
    });

    test('a server of the client is reloaded too', () async {
      final rig = await _Rig.create();
      final session = await rig.session(
        mcp: [const McpStdioServerConfig(name: 'docs', command: 'docs-mcp')],
      );

      await rig.ask(session, '/mcp reload docs');

      expect(rig.tools(session).reconnected, ['docs']);
    });

    test('an unknown id: the text, nothing is reconnected', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();

      final reply = await rig.ask(session, '/mcp reload nope');

      expect(reply.text, 'Unknown MCP server: nope. Run /mcp list.');
      expect(rig.tools(session).reconnected, isEmpty);
    });

    test('a session without servers: an unknown id too', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final reply = await rig.ask(session, '/mcp reload a');

      expect(reply.text, 'Unknown MCP server: a. Run /mcp list.');
    });
  });

  group('/mcp enable and /mcp disable', () {
    test('disable is for this session only: the table shows disabled, the '
        'config and the journal do not change (scenario "/mcp disable '
        'только в сессии")', () async {
      final rig = await _Rig.create(servers: [_http('github')]);
      final session = await rig.session();
      final journal = rig.store.textOf(session.id);
      final configBefore = _snapshotOf(rig.user);

      final reply = await rig.ask(session, '/mcp disable github');

      expect(rig.tools(session).enabledCalls, [('github', false)]);
      expect(reply.text, contains('github  config  http       disabled'));
      expect(reply.text, contains('disabled by /mcp disable'));
      expect(_snapshotOf(rig.user), configBefore);
      expect(rig.store.textOf(session.id), journal);
      expect(rig.source.loads, 0);
    });

    test('enable switches the server back on', () async {
      final rig = await _Rig.create(servers: [_stdio('s', enabled: false)]);
      final session = await rig.session();

      final reply = await rig.ask(session, '/mcp enable s');

      expect(rig.tools(session).enabledCalls, [('s', true)]);
      expect(reply.text, contains('s   config  stdio      connected'));
    });

    test('an unknown id is truncated to 64 runes, the text of the issue '
        'is not (D12)', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      final id = '\u{1F600}' * 100;

      final reply = await rig.ask(session, '/mcp enable $id');

      expect(
        reply.text,
        'Unknown MCP server: ${'\u{1F600}' * 64}. Run /mcp list.',
      );
      expect(rig.tools(session).enabledCalls, isEmpty);
    });

    test('a new server deferred until a restart is unknown; a changed one '
        'is enabled with the previous variant (scenario "enable отложенного '
        'сервера")', () async {
      final rig = await _Rig.create(servers: [_stdio('y', enabled: false)]);
      final session = await rig.session();
      _put(rig.user, 'mcp.servers', [
        _stdio('y', command: 'other-mcp', enabled: false),
        _stdio('x'),
      ]);
      final report = await rig.runtime.reloadConfig();
      expect(report.restartRequiredKeys, ['mcp.servers[x]', 'mcp.servers[y]']);

      final unknown = await rig.ask(session, '/mcp enable x');
      final known = await rig.ask(session, '/mcp enable y');

      expect(unknown.text, 'Unknown MCP server: x. Run /mcp list.');
      expect(known.text, startsWith('```text\n'));
      final tools = rig.tools(session);
      expect(tools.enabledCalls, [('y', true)]);
      // Настоящий коннектор подключает описание, полученное им последним;
      // оно не должно получить `other-mcp`: отложенная правка не доходит до
      // коннектора (R6-1).
      for (final desired in tools.replaced) {
        for (final server in desired.whereType<McpStdioServerConfig>()) {
          expect(server.command, isNot('other-mcp'));
        }
      }
    });

    test('does not overtake a replacement in flight: the command waits for '
        'it and then sees the new list (D10, D11)', () async {
      final rig = await _Rig.create(servers: [_http('a'), _http('b')]);
      final session = await rig.session();
      final gate = rig.tools(session).replaceGate = Completer<void>();
      _put(rig.user, 'mcp.servers', [_http('a')]);
      final reloading = rig.runtime.reloadConfig();
      await pumpEventQueue();
      expect(rig.tools(session).replaced, hasLength(1));

      final reply = rig.ask(session, '/mcp disable b');
      await pumpEventQueue();
      expect(rig.tools(session).enabledCalls, isEmpty, reason: 'waits');
      gate.complete();
      await reloading;

      expect(
        (await reply).text,
        'Unknown MCP server: b. Run /mcp list.',
        reason: 'b was removed by the replacement that was in flight',
      );
      expect(rig.tools(session).enabledCalls, isEmpty);
    });

    test('a replacement caused during the command queues behind it: '
        'the manual action does not run inside a replacement (D11)', () async {
      final rig = await _Rig.create(servers: [_http('a'), _http('b')]);
      final session = await rig.session();
      final gate = rig.tools(session).enableGate = Completer<void>();

      final reply = rig.ask(session, '/mcp disable a');
      await pumpEventQueue();
      expect(rig.tools(session).enabledCalls, [
        ('a', false),
      ], reason: 'the action is in flight');
      _put(rig.user, 'mcp.servers', [_http('a'), _http('b'), _http('c')]);
      final reloading = rig.runtime.reloadConfig();
      await pumpEventQueue();
      expect(rig.tools(session).replaced, isEmpty, reason: 'queued behind');
      gate.complete();
      await reply;
      await reloading;

      expect(rig.tools(session).replaced, hasLength(1));
    });
  });

  group('the slot of the turn and cancel', () {
    test('a command during a turn of the model is rejected like a second '
        'prompt', () async {
      final rig = await _Rig.create(hold: true);
      final session = await rig.session();
      final turn = session.prompt(const [TextContent('go')]);
      await pumpEventQueue();

      await expectLater(
        session.prompt(const [TextContent('/mcp list')]),
        throwsA(isA<StateError>()),
      );

      await session.cancel();
      await turn;
    });

    test('the slot is free after a command', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      await rig.ask(session, '/mcp list');
      final result = await session.prompt(const [TextContent('hello')]);

      expect(result.reason, TurnEndReason.completed);
      expect(rig.streamCalls, 1);
    });

    test('session/cancel during /config reload: cancelled without text, the '
        'slot is free, the reload runs to the end', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final gate = rig.source.gate = Completer<void>();
      _put(rig.user, 'budget.max_steps', 20);

      final reply = rig.ask(session, '/config reload');
      await pumpEventQueue();
      expect(rig.source.loads, 1);
      await session.cancel();
      final cancelled = await reply;

      expect(cancelled.result.reason, TurnEndReason.cancelled);
      expect(
        [for (final e in cancelled.events) e.runtimeType],
        [TurnStarted, TurnEnded],
      );
      expect(cancelled.text, '');
      // Слот свободен.
      final next = await rig.ask(session, '/mcp list');
      expect(next.text, 'No MCP servers.');
      // Перезагрузка рантайма доведена до конца и применила ключ.
      expect(rig.runtime.appliedValues['budget.max_steps'], isNull);
      gate.complete();
      await pumpEventQueue();
      expect(rig.runtime.appliedValues['budget.max_steps'], 20);
    });

    test(
      'the cancel token of the prompt ends the command the same way',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();
        final gate = rig.source.gate = Completer<void>();
        final source = CancelTokenSource();

        final reply = rig.ask(session, '/config check', cancel: source.token);
        await pumpEventQueue();
        source.cancel();
        final cancelled = await reply;

        expect(cancelled.result.reason, TurnEndReason.cancelled);
        expect(cancelled.text, '');
        gate.complete();
        await pumpEventQueue();
      },
    );
  });

  group('review fixes of iteration 7', () {
    test('a command cancelled during /mcp reload does not wake the servers '
        'later nor touch the next turn (D6, D11)', () async {
      final rig = await _Rig.create(servers: [_http('a')], hold: true);
      final session = await rig.session();
      rig
          .tools(session)
          .preset(
            const McpServerSummary(
              name: 'a',
              toolCount: 0,
              origin: McpServerOrigin.config,
              transport: 'http',
              state: McpServerState.failed,
              lastError: 'connection refused',
              retryIn: Duration(seconds: 8),
            ),
          );
      final gate = rig.source.gate = Completer<void>();
      final command = rig.ask(session, '/mcp reload');
      await pumpEventQueue();
      await session.cancel();
      expect((await command).result.reason, TurnEndReason.cancelled);
      expect(rig.logger.eventsOf('command.builtin.cancelled').single.fields, {
        'session_id': session.id.value,
        'name': 'mcp',
        'subcommand': 'reload',
      });

      final turn = session.prompt(const [TextContent('go')]);
      await pumpEventQueue();
      expect(rig.manual!.calls, 1, reason: 'the turn of the model runs');
      gate.complete();
      await pumpEventQueue();

      expect(rig.tools(session).reconnected, isEmpty);
      await session.cancel();
      await turn;
    });

    test('a failure of the command ends the turn as a failed turn of the '
        'model: AgentError, TurnEnded(failed); the log has the class only; '
        'the slot is free', () async {
      final rig = await _Rig.create(servers: [_http('a')]);
      final session = await rig.session();
      rig.tools(session).failServers = StateError('secret-detail');

      final reply = await rig.ask(session, '/mcp list');

      expect(
        [for (final e in reply.events) e.runtimeType],
        [TurnStarted, AgentError, TurnEnded],
      );
      expect(reply.result.reason, TurnEndReason.failed);
      final failure = reply.events.whereType<AgentError>().single;
      expect(failure.retrying, isFalse);
      expect(failure.message, isNot(contains('secret-detail')));
      final log = rig.logger.eventsOf('command.builtin.failed').single;
      expect(log.fields, {
        'session_id': session.id.value,
        'name': 'mcp',
        'subcommand': 'list',
        'error_class': 'StateError',
      });
      expect(
        [for (final r in rig.logger.records) r.toString()].join('\n'),
        isNot(contains('secret-detail')),
      );
      rig.tools(session).failServers = null;
      expect(
        (await rig.ask(session, '/mcp list')).result.reason,
        TurnEndReason.completed,
      );
    });

    test('a throwing load of /config check: the text without the message, '
        'the log config.check.failed with the class', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      rig.source.loadError = StateError('boom-secret');

      final reply = await rig.ask(session, '/config check');

      expect(
        reply.text,
        'Config check failed (StateError). See the agent log.',
      );
      final log = rig.logger.eventsOf('config.check.failed').single;
      expect(log.level, LogLevel.warning);
      expect(log.fields, {
        'session_id': session.id.value,
        'error_class': 'StateError',
      });
      expect(
        [for (final r in rig.logger.records) r.toString()].join('\n'),
        isNot(contains('boom-secret')),
      );
    });

    test('close() during a command ends it as cancelled', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final gate = rig.source.gate = Completer<void>();

      final reply = rig.ask(session, '/config reload');
      await pumpEventQueue();
      await session.close();

      expect((await reply).result.reason, TurnEndReason.cancelled);
      gate.complete();
      await pumpEventQueue();
    });

    test(
      'a failed manual action is logged with the server and the action',
      () async {
        final rig = await _Rig.create(servers: [_http('a')]);
        final session = await rig.session();
        rig.tools(session).failReconnect = StateError('x');

        await rig.ask(session, '/mcp reload a');

        final log = rig.logger.eventsOf('mcp.server.failed').single;
        expect(log.fields['server'], 'a');
        expect(log.fields['transport'], 'http');
        expect(log.fields['action'], 'reconnect');
        expect(log.fields['session_id'], session.id.value);
      },
    );

    test('the cells of the table: - without an error in any state, the retry '
        'only for failed, rounded, at least 1s', () async {
      final rig = await _Rig.create(
        servers: [_http('a'), _http('b'), _http('c')],
      );
      final session = await rig.session();
      McpServerSummary of(String n, McpServerState st, Duration? retry) =>
          McpServerSummary(
            name: n,
            toolCount: 0,
            origin: McpServerOrigin.config,
            transport: 'http',
            state: st,
            retryIn: retry,
          );
      rig.tools(session)
        ..preset(
          of('a', McpServerState.failed, const Duration(milliseconds: 400)),
        )
        ..preset(
          of('b', McpServerState.failed, const Duration(milliseconds: 2500)),
        )
        ..preset(of('c', McpServerState.disabled, const Duration(seconds: 9)));

      final reply = await rig.ask(session, '/mcp list');

      expect(reply.text, contains('failed    0      - (retry in 1s)\n'));
      expect(reply.text, contains('failed    0      - (retry in 3s)\n'));
      expect(reply.text, contains('disabled  0      -\n'));
      expect(reply.text, endsWith('\n```'));
    });

    test('a leading space is not a command, as with the templates '
        '(expand_command.dart)', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      await session.prompt(const [TextContent(' /mcp list')]);

      expect(rig.streamCalls, 1);
    });

    test('after session/load the disabled server follows the config', () async {
      final rig = await _Rig.create(servers: [_http('github')]);
      final session = await rig.session();
      await rig.ask(session, '/mcp disable github');
      expect(rig.tools(session).servers.single.state, McpServerState.disabled);
      await session.close();

      final loaded = await rig.runtime.loadSession(
        session.id,
        const SessionHostPorts(),
      );
      final reply = await rig.ask(loaded, '/mcp list');

      expect(reply.text, contains('github  config  http       connected'));
    });

    test('a new session of the same cwd after a reload has no new project '
        'template either: the trust is pinned (R0-1, scenario "Перезагрузка '
        'не меняет список")', () async {
      final trusted = await _Rig.create(
        templates: ['review'],
        trustedTemplates: ['fix'],
        extra: {
          'trusted_projects': ['/proj'],
        },
      );
      expect(
        [for (final c in (await trusted.session()).commands) c.name],
        contains('fix'),
        reason: 'the control: a trusted project has the template',
      );
      final rig = await _Rig.create(
        templates: ['review'],
        trustedTemplates: ['fix'],
      );
      final live = await rig.session();
      _put(rig.user, 'trusted_projects', ['/proj']);
      await rig.runtime.reloadConfig();

      final fresh = await rig.session();

      expect([for (final c in live.commands) c.name], isNot(contains('fix')));
      expect([for (final c in fresh.commands) c.name], isNot(contains('fix')));
    });
  });
}

// ---------------------------------------------------------------------------

/// Ответ команды: события хода, итог и текст единственного сообщения.
final class _Reply {
  _Reply(this.events, this.result);

  final List<AgentEvent> events;
  final TurnResult result;

  /// Текст завершённого сообщения агента; пусто, если сообщения не было.
  String get text {
    final ended = [
      for (final e in events.whereType<MessageEnded>())
        if (e.message is AssistantMessage) e,
    ];
    if (ended.isEmpty) {
      return '';
    }
    return ended.last.message.content
        .whereType<TextContent>()
        .map((b) => b.text)
        .join();
  }
}

Map<String, Object?> _http(String name, {String? url}) => {
  'name': name,
  'type': 'http',
  'url': url ?? 'https://$name.test/mcp',
};

Map<String, Object?> _stdio(
  String name, {
  String command = 'fake-mcp',
  bool enabled = true,
}) => {
  'name': name,
  'type': 'stdio',
  'command': command,
  if (!enabled) 'enabled': false,
};

void _put(Map<String, Object?> root, String path, Object? value) {
  final names = path.split('.');
  var node = root;
  for (final name in names.take(names.length - 1)) {
    node =
        node.putIfAbsent(name, () => <String, Object?>{})!
            as Map<String, Object?>;
  }
  node[names.last] = _deep(value);
}

Object? _deep(Object? node) => switch (node) {
  final Map<Object?, Object?> map => <String, Object?>{
    for (final entry in map.entries) entry.key! as String: _deep(entry.value),
  },
  final List<Object?> list => <Object?>[for (final item in list) _deep(item)],
  _ => node,
};

/// Снимок карты слоя для сравнения «до и после» (карта правится по месту).
String _snapshotOf(Map<String, Object?> map) => _deep(map).toString();

Map<String, Object?> _user(
  List<Map<String, Object?>> servers,
  Map<String, Object?> extra,
) => {
  ...baseValues(),
  'providers': {
    'a': {
      'kind': 'openai-compatible',
      'base_url': 'https://a.test/v1',
      'models': {'m1': <String, Object?>{}},
    },
  },
  'agent': {'default_model': 'a/m1'},
  'mcp': {'servers': _deep(servers)},
  ...extra,
};

/// Источник конфигурации в памяти: `load()` пересобирает конфиг из слоя
/// пользователя, который тест правит по месту; ворота [gate] держат загрузку.
final class _Source implements ConfigSource {
  _Source(this._build) {
    _initial = _build(null);
    expect(_initial.issues, isEmpty, reason: _initial.issues.join('\n'));
  }

  final ConfigLoadResult Function(List<String>? pinned) _build;
  late final ConfigLoadResult _initial;
  final _changes = StreamController<void>.broadcast(sync: true);

  /// Число вызовов `load` и значения `rebase` каждого.
  var loads = 0;
  final rebases = <bool>[];
  Completer<void>? gate;

  /// Если задано, `load` бросает его (сбой источника).
  Object? loadError;

  void signal() => _changes.add(null);

  Future<void> close() => _changes.close();

  @override
  ConfigLoadResult get initial => _initial;

  @override
  Future<ConfigLoadResult> load({bool rebase = true}) async {
    loads++;
    rebases.add(rebase);
    final held = gate;
    if (held != null) {
      await held.future;
    }
    if (loadError case final error?) {
      throw error;
    }
    return _build(_initial.config!.trustedProjects);
  }

  @override
  Stream<void> get changes => _changes.stream;
}

/// Коннектор с состоянием серверов: `servers` живёт, `reconnect` и
/// `setEnabled` меняют состояние, `replaceServers` приводит список к
/// желаемому. Реальную логику автомата проверяют тесты `codelab_agent_mcp`.
final class _Connector implements McpConnector {
  final sessions = <_Tools>[];
  final requests = <McpConnectRequest>[];

  @override
  Set<String> get transports => const {'stdio', 'http'};

  @override
  Future<McpSessionTools> connect(McpConnectRequest request) async {
    requests.add(request);
    final tools = _Tools(request);
    sessions.add(tools);
    return tools;
  }
}

final class _Tools implements McpSessionTools {
  _Tools(this.request) {
    for (final server in request.servers) {
      _servers.add(_summaryOf(server));
    }
  }

  final McpConnectRequest request;
  final _servers = <McpServerSummary>[];
  final replaced = <List<McpServerConfig>>[];
  final reconnected = <String>[];
  final enabledCalls = <(String, bool)>[];
  Completer<void>? replaceGate;
  Completer<void>? enableGate;

  /// Поток состояний (D12): этим тестам события не нужны, поток пуст.
  @override
  Stream<List<McpServerSummary>> get changes => const Stream.empty();

  /// Если задано, чтение `servers` или `reconnect` бросает его.
  Object? failServers;
  Object? failReconnect;

  static McpServerSummary _summaryOf(McpServerConfig server) =>
      McpServerSummary(
        name: server.name,
        toolCount: 0,
        origin: server.origin,
        transport: server.transport,
        state: server.enabled
            ? McpServerState.connected
            : McpServerState.disabled,
      );

  /// Заменяет сводку сервера: готовит состояние (`failed`, число
  /// инструментов), которое коннектор сообщил бы сам.
  void preset(McpServerSummary summary) {
    final index = _servers.indexWhere((s) => s.name == summary.name);
    expect(index, isNonNegative, reason: 'no server ${summary.name}');
    _servers[index] = summary;
  }

  @override
  List<AgentTool> get tools => const [];

  @override
  List<McpServerSummary> get servers {
    if (failServers case final error?) {
      throw error;
    }
    return List.unmodifiable(_servers);
  }

  @override
  McpToolsUpdate? takeUpdate() => null;

  @override
  Future<void> replaceServers(List<McpServerConfig> desired) async {
    replaced.add(desired);
    await replaceGate?.future;
    final byName = {for (final s in _servers) s.name: s};
    _servers
      ..clear()
      ..addAll([
        for (final server in desired) byName[server.name] ?? _summaryOf(server),
      ]);
  }

  @override
  Future<void> reconnect(String name) async {
    reconnected.add(name);
    if (failReconnect case final error?) {
      throw error;
    }
    final index = _servers.indexWhere((s) => s.name == name);
    if (index >= 0) {
      final old = _servers[index];
      _servers[index] = McpServerSummary(
        name: old.name,
        toolCount: old.toolCount,
        origin: old.origin,
        transport: old.transport,
      );
    }
  }

  @override
  Future<void> setEnabled(String name, bool enabled) async {
    enabledCalls.add((name, enabled));
    await enableGate?.future;
    final index = _servers.indexWhere((s) => s.name == name);
    if (index >= 0) {
      final old = _servers[index];
      _servers[index] = McpServerSummary(
        name: old.name,
        toolCount: enabled ? old.toolCount : 0,
        origin: old.origin,
        transport: old.transport,
        state: enabled ? McpServerState.connected : McpServerState.disabled,
        lastError: enabled ? null : 'disabled by /mcp disable',
      );
    }
  }

  @override
  Future<void> close() async {}
}

/// Память, раскрывающая любой путь в себя: сессия получает раскрытый
/// `realpath` и может быть доверенной (как в `config_reload_test.dart`).
final class _ResolvingEnv implements ExecutionEnv, PathResolver {
  final _inner = MemoryExecutionEnv(cwd: '/proj');

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> realpath(String path) async => Ok(path);

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) => _inner.readText(path, line: line, limit: limit);

  @override
  Future<Result<void, FileError>> writeText(String path, String content) =>
      _inner.writeText(path, content);

  @override
  Future<Result<FileStat, FileError>> stat(String path) => _inner.stat(path);

  @override
  Future<Result<ExecResult, ExecError>> exec(
    String command,
    ExecOptions options,
  ) => _inner.exec(command, options);
}

final class _Port implements ProjectFilesSource {
  _Port(this.names, {this.trustedOnly = const []});

  final List<String> names;

  /// Шаблоны проекта: отдаются только доверенному проекту (D4).
  final List<String> trustedOnly;

  @override
  Future<ProjectFiles> load(ProjectFilesQuery query) async => ProjectFiles(
    templates: [
      for (final name in [...names, if (query.projectTrusted) ...trustedOnly])
        MarkdownFile(
          path: '/home/.codelab/prompts/$name.md',
          scope: ExtensionScope.user,
          body: 'Do $name',
          bodyLine: 1,
        ),
    ],
  );
}

final class _Rig {
  _Rig._(
    this.user,
    this.built,
    this.fake,
    this.source,
    this.logger,
    this.store,
    this.manual,
    this._calls,
    this._contexts,
  );

  static Future<_Rig> create({
    List<Map<String, Object?>> servers = const [],
    Map<String, Object?> extra = const {},
    bool withSource = true,
    bool configCommand = true,
    bool mcpCapability = true,
    bool hold = false,
    List<String> templates = const [],
    List<String> trustedTemplates = const [],
  }) async {
    final user = _user(servers, extra);
    final clock = FakeClock();
    final logger = RecordingLogger(clock: clock);
    final store = MemorySessionStore();
    final manual = hold ? ManualStream(clock) : null;
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': [for (var i = 0; i < 10; i++) textStep('ok')],
    }, clock: clock);
    final calls = <int>[];
    final contexts = <LlmContext>[];
    StreamFunction stream() => (ref, context, {cancel}) {
      calls.add(calls.length);
      contexts.add(context);
      return manual != null
          ? manual.call(ref, context, cancel: cancel)
          : scripted.call(ref, context, cancel: cancel);
    };
    final source = _Source(
      (pinned) => CoreConfig.fromLayers(
        [layer(user)],
        environment: const {},
        projectRoot: '/proj',
        pinnedTrustedProjects: pinned,
      ),
    );
    ModelCatalog catalogOf(CoreConfig config) =>
        StaticModelCatalog(config.providers, logger: logger);
    final fake = _Connector();
    final initial = source.initial.config!;
    final built = buildAgentCore(
      profile: HostProfile.of('agent-serve').narrowed({
        ...inMemoryJournal,
        ...noExec,
        if (!mcpCapability) HostCapability.mcp: const CapabilityOff('test'),
      }),
      services: AgentCoreServices(
        baseEnv: _ResolvingEnv(),
        logger: logger,
        clock: clock,
        ids: SequentialIdGenerator(),
        sessions: store,
        models: catalogOf(initial),
        mcp: fake,
        config: withSource ? source : null,
        projectFiles: templates.isEmpty && trustedTemplates.isEmpty
            ? null
            : _Port(templates, trustedOnly: trustedTemplates),
      ),
      config: initial,
      streamFunction: stream(),
      modelsFor: withSource
          ? (config) => (stream: stream(), catalog: catalogOf(config))
          : null,
      configCommand: configCommand,
    );
    addTearDown(() async {
      await built.runtime.dispose();
      await source.close();
    });
    return _Rig._(
      user,
      built,
      fake,
      source,
      logger,
      store,
      manual,
      calls,
      contexts,
    );
  }

  final Map<String, Object?> user;
  final BuiltAgentCore built;
  final _Connector fake;
  final _Source source;
  final RecordingLogger logger;
  final MemorySessionStore store;
  final ManualStream? manual;
  final List<int> _calls;
  final List<LlmContext> _contexts;

  AgentRuntimeImpl get runtime => built.runtime as AgentRuntimeImpl;

  /// Число запросов к модели.
  int get streamCalls => _calls.length;

  /// Текст последнего сообщения пользователя в последнем запросе модели.
  String get lastUserText => _contexts.last.messages
      .whereType<UserMessage>()
      .last
      .content
      .whereType<TextContent>()
      .map((b) => b.text)
      .join();

  Future<AgentSession> session({List<McpServerConfig> mcp = const []}) =>
      runtime.createSession(SessionSpec(cwd: '/proj', mcpServers: mcp));

  /// Коннектор сессии (по порядку создания: тесты используют одну сессию).
  _Tools tools(AgentSession session) {
    final index = fake.requests.lastIndexWhere(
      (r) => r.sessionId == session.id,
    );
    expect(index, isNonNegative, reason: 'the session has no MCP servers');
    return fake.sessions[index];
  }

  /// Отправляет [text] и собирает события хода.
  Future<_Reply> ask(
    AgentSession session,
    String text, {
    CancelToken? cancel,
  }) async {
    final events = <AgentEvent>[];
    final subscription = session.events.listen(events.add);
    final result = await session.prompt([TextContent(text)], cancel: cancel);
    await pumpEventQueue();
    await subscription.cancel();
    return _Reply(events, result);
  }
}
