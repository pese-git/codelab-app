import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Журнал usage сессии: свёртка записей (agent-sessions «Журнал usage
/// сессии»; design.md change `add-usage-ledger`, D1, D2, Q4, Q9; критерий
/// `core/usage-ledger-rebuild-deterministic`, OBS-10). Задача 1.1.
///
/// Снимки собраны вручную из записей: свёртка — чистая функция
/// `SessionSnapshot`, ни хранилища, ни модели, ни часов в тесте нет (PKG-6).
void main() {
  final at = DateTime.utc(2026, 11, 17);
  final gpt = _model('openai', 'gpt-4o');
  final claude = _model('anthropic', 'claude-sonnet-4');

  group('turns and steps (D1 пп. 1, 3, 4)', () {
    test('two turns: steps per turn, toolCallIds, the total is their sum', () {
      final b = _Journal(at)
        ..user('first task')
        ..assistant(
          gpt,
          _u(input: 100, output: 10, cost: 0.002),
          calls: const ['call_1'],
        )
        ..toolResult('call_1')
        ..assistant(gpt, _u(input: 150, output: 20, cost: 0.003))
        ..user('second task')
        ..assistant(gpt, _u(input: 70, output: 5, cost: 0.001));

      final ledger = buildUsageLedger(b.snapshot());

      expect(ledger.turns, hasLength(2));
      expect(ledger.turns[0].steps.map((s) => s.recordId), [
        b.ids[1],
        b.ids[3],
      ]);
      expect(ledger.turns[0].steps.map((s) => s.toolCallIds), [
        ['call_1'],
        <String>[],
      ]);
      expect(ledger.turns[0].recordId, b.ids[0]);
      expect(ledger.turns[1].steps.single.recordId, b.ids[5]);
      expect(ledger.steps, 3);
      expect(ledger.total.input, 320);
      expect(ledger.total.output, 35);
      expect(ledger.total.cost.total, closeTo(0.006, 1e-9));
      expect(ledger.turns[0].usage.input, 250);
      expect(ledger.turns[1].usage.input, 70);
      expect(ledger.records, b.records.length);
      expect(ledger.lastRecordId, b.ids.last);
      expect(ledger.sessionId, _sid.value);
    });

    test('steer does not open a turn; loop_note is not a step', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 10))
        ..user('also check the tests', origin: 'steer')
        ..assistant(gpt, _u(input: 20))
        ..assistant(gpt, _u(input: 999), origin: 'loop_note');

      final ledger = buildUsageLedger(b.snapshot());

      expect(ledger.turns, hasLength(1));
      expect(ledger.turns.single.steps, hasLength(2));
      expect(ledger.steps, 2);
      expect(ledger.total.input, 30);
      expect(ledger.byModel.single.steps, 2);
    });

    test('service user records stay in their turn and open no new one', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 10))
        ..user('subagent finished', origin: 'subagent_notice')
        ..assistant(gpt, _u(input: 20));

      final ledger = buildUsageLedger(b.snapshot());

      expect(ledger.turns, hasLength(1));
      expect(ledger.turns.single.steps, hasLength(2));
    });

    test('a turn without steps is not listed', () {
      final b = _Journal(at)
        ..user('never answered')
        ..user('answered')
        ..assistant(gpt, _u(input: 5));

      final ledger = buildUsageLedger(b.snapshot());

      expect(ledger.turns.map((t) => t.recordId), [b.ids[1]]);
    });

    test(
      'the title is the first 64 runes; a command shows its source text',
      () {
        // Эмодзи — две кодовые единицы UTF-16, но одна руна: обрезка по рунам.
        final long = '😀${'я' * 100}';
        final b = _Journal(at)
          ..user(long)
          ..assistant(gpt, _u(input: 1))
          ..user(
            'Review the file lib/a.dart carefully and report',
            command: const CommandRef(
              source: 'template',
              name: 'review',
              args: 'lib/a.dart',
            ),
          )
          ..assistant(gpt, _u(input: 1));

        final ledger = buildUsageLedger(b.snapshot());

        expect(ledger.turns[0].title.runes.length, 64);
        expect(
          ledger.turns[0].title,
          String.fromCharCodes(long.runes.take(64)),
        );
        expect(ledger.turns[1].title, '/review lib/a.dart');
      },
    );
  });

  group('the turn title follows S-16 (D1 п. 3)', () {
    String titleOf(String text, {CommandRef? command}) {
      final b = _Journal(at)
        ..user(text, command: command)
        ..assistant(gpt, _u(input: 1));
      return buildUsageLedger(b.snapshot()).turns.single.title;
    }

    test('trimmed, whitespace and line breaks collapsed to one space', () {
      expect(titleOf('  fix\n\n the   test\t\tnow \r\n'), 'fix the test now');
    });

    test('the limit of 64 runes counts after the collapse', () {
      final text = '${'я' * 30}\n\n\n${'ы' * 60}';

      final title = titleOf(text);

      expect(title.runes.length, 64);
      expect(title, '${'я' * 30} ${'ы' * 33}');
    });

    test('a command text is normalized the same way', () {
      final title = titleOf(
        'expanded body',
        command: const CommandRef(
          source: 'template',
          name: 'review',
          args: 'a.dart   b.dart\n',
        ),
      );

      expect(title, '/review a.dart b.dart');
    });
  });

  group('noUsage (D1 п. 2)', () {
    test('set for an answer without usage, not for error or cache-only', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, const Usage())
        ..assistant(gpt, const Usage(), stop: StopReason.error)
        ..assistant(gpt, const Usage(cacheRead: 500))
        // Только запись в кэш — тоже usage провайдера (D1 п. 2).
        ..assistant(gpt, const Usage(cacheWrite: 300))
        ..assistant(gpt, const Usage(input: 1));

      final steps = buildUsageLedger(b.snapshot()).turns.single.steps;

      expect(steps.map((s) => s.noUsage), [true, false, false, false, false]);
    });
  });

  group('subagents and summaries (D1 пп. 5, 6, 7)', () {
    test('a completed subagent counts in its turn and the session, not in '
        'the models; running and not-last records do not', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 100))
        // s1: running, затем completed — считается один раз.
        ..subagent('s1', 'running')
        ..subagent('s1', 'completed', usage: _u(input: 40, cost: 0.004))
        // s2: running без usage — не считается.
        ..subagent('s2', 'running')
        // s3: completed, но последняя запись — running: не считается.
        ..subagent('s3', 'completed', usage: _u(input: 7000))
        ..subagent('s3', 'running');

      final ledger = buildUsageLedger(b.snapshot());

      expect(ledger.subagents!.count, 1);
      expect(ledger.subagents!.usage.input, 40);
      expect(ledger.turns.single.subagents!.count, 1);
      expect(ledger.turns.single.usage.input, 140);
      expect(ledger.turns.single.steps, hasLength(1));
      expect(ledger.steps, 1);
      expect(ledger.total.input, 140);
      expect(ledger.byModel.single.usage.input, 100);
    });

    test('a turn keeps the usage of each of its subagent runs apart '
        '(price per run, D2)', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 100))
        ..subagent('s1', 'completed', usage: _u(input: 40, cost: 0.004))
        ..subagent('s2', 'completed', usage: _u(input: 60));

      final ledger = buildUsageLedger(b.snapshot());

      final runs = ledger.turns.single.subagentRuns;
      expect(runs.map((r) => r.input), [40, 60]);
      expect(runs.map((r) => r.cost.total), [closeTo(0.004, 1e-9), 0]);
      expect(ledger.turns.single.subagents!.count, 2);
    });

    test('a compaction with details.usage goes to summaries and the total, '
        'not to a turn or the models; one without it does not count', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 100))
        ..compaction(usage: _u(input: 900, output: 120, cost: 0.01))
        ..compaction();

      final ledger = buildUsageLedger(b.snapshot());

      expect(ledger.summaries!.count, 1);
      expect(ledger.summaries!.usage.input, 900);
      expect(ledger.total.input, 1000);
      expect(ledger.turns.single.usage.input, 100);
      expect(ledger.byModel.single.model, 'openai/gpt-4o');
      expect(ledger.byModel.single.usage.input, 100);
    });

    test('summaries.models: the distinct summaryModel values, sorted '
        '(D1 п. 6)', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 1))
        ..compaction(usage: _u(input: 10), model: 'openai/gpt-4o-mini')
        ..compaction(usage: _u(input: 20), model: 'anthropic/claude-haiku')
        ..compaction(usage: _u(input: 30), model: 'openai/gpt-4o-mini')
        // Без details.usage запись не считается, её модель в список не входит.
        ..compaction(model: 'local/never-counted');

      final summaries = buildUsageLedger(b.snapshot()).summaries!;

      expect(summaries.count, 3);
      expect(summaries.models, [
        'anthropic/claude-haiku',
        'openai/gpt-4o-mini',
      ]);
    });

    test('the models are in alphabetical order whatever the journal order', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 1))
        ..assistant(claude, _u(input: 2))
        ..assistant(gpt, _u(input: 3));

      final models = buildUsageLedger(b.snapshot()).byModel;

      expect(models.map((m) => m.model), [
        'anthropic/claude-sonnet-4',
        'openai/gpt-4o',
      ]);
      expect(models.map((m) => m.steps), [1, 2]);
      expect(models.map((m) => m.usage.input), [2, 4]);
    });
  });

  group('serialization (D3, OBS-10)', () {
    _Journal full() => _Journal(at)
      ..user('first task')
      ..assistant(
        gpt,
        _u(input: 100, output: 10, cost: 0.0021),
        calls: const ['call_1'],
      )
      ..toolResult('call_1')
      ..assistant(claude, _u(input: 150, cacheRead: 30, cost: 0.003))
      ..user('steer', origin: 'steer')
      ..assistant(gpt, const Usage(), origin: 'loop_note')
      ..subagent('s1', 'completed', usage: _u(input: 40, cost: 0.004))
      ..compaction(usage: _u(input: 900, cost: 0.01))
      ..user('second task')
      ..assistant(gpt, _u(input: 70, cost: 0.001));

    test('built twice from the same records: byte-for-byte equal '
        '(core/usage-ledger-rebuild-deterministic)', () {
      final first = buildUsageLedger(full().snapshot()).serialize();
      final second = buildUsageLedger(full().snapshot()).serialize();

      expect(second, first);
      expect(buildUsageLedger(full().snapshot()).serialize(), first);
    });

    test('the format v1: keys in order, no spaces outside strings, a '
        'trailing newline, no build time', () {
      final text = buildUsageLedger(full().snapshot()).serialize();

      expect(text, endsWith('}\n'));
      expect(text.indexOf('\n'), text.length - 1);
      expect(
        text,
        startsWith('{"version":1,"sessionId":"${_sid.value}","source":{'),
      );
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json.keys.toList(), [
        'version',
        'sessionId',
        'source',
        'steps',
        'total',
        'byModel',
        'turns',
        'subagents',
        'summaries',
      ]);
      expect(json['source'], {
        'records': full().records.length,
        'lastRecordId': full().ids.last,
      });
      final turn = (json['turns']! as List).first as Map<String, Object?>;
      expect(turn.keys, containsAll(['recordId', 'title', 'usage', 'steps']));
      final step = (turn['steps']! as List).first as Map<String, Object?>;
      expect(step['toolCallIds'], ['call_1']);
      expect((json['subagents']! as Map)['runs'], 1);
      expect((json['summaries']! as Map)['count'], 1);
      expect((json['summaries']! as Map).keys, ['count', 'usage', 'models']);
      expect((json['summaries']! as Map)['models'], ['openai/gpt-4o-mini']);
    });

    test('costs are rounded to 10^-6', () {
      final b = _Journal(at)
        ..user('task')
        ..assistant(gpt, _u(input: 1, cost: 0.1234567891));

      final json =
          jsonDecode(buildUsageLedger(b.snapshot()).serialize())!
              as Map<String, Object?>;

      final cost = (json['total']! as Map)['cost']! as Map;
      expect(cost['input'], 0.123457);
    });

    test('no message texts, tool arguments or results, except the turn '
        'title', () {
      final b = _Journal(at)
        ..user('visible title')
        ..assistant(
          gpt,
          _u(input: 1),
          text: 'SECRET-ANSWER-TEXT',
          calls: const ['call_1'],
          args: const {'path': 'SECRET-ARGUMENT'},
        )
        ..toolResult('call_1', text: 'SECRET-TOOL-RESULT');

      final text = buildUsageLedger(b.snapshot()).serialize();

      expect(text, contains('visible title'));
      expect(text, isNot(contains('SECRET')));
    });

    test('a journal without steps: no turns, no models, zero total, empty '
        'blocks omitted', () {
      final b = _Journal(at)..user('hello');

      final ledger = buildUsageLedger(b.snapshot());
      final json = jsonDecode(ledger.serialize()) as Map<String, Object?>;

      expect(ledger.steps, 0);
      expect(ledger.turns, isEmpty);
      expect(ledger.byModel, isEmpty);
      expect(ledger.total.total, 0);
      for (final key in ['turns', 'byModel', 'subagents', 'summaries']) {
        expect(json.containsKey(key), isFalse, reason: key);
      }
      expect(json['steps'], 0);
    });

    test('an empty journal has no lastRecordId', () {
      final ledger = buildUsageLedger(SessionSnapshot.empty(_header(at)));

      expect(ledger.records, 0);
      expect(ledger.lastRecordId, isNull);
      expect(ledger.steps, 0);
    });
  });

  group('the models without a price (D2, Q4, Q9)', () {
    ModelRef priced(ModelRef m) => ModelRef(
      provider: m.provider,
      id: m.id,
      api: m.api,
      baseUrl: m.baseUrl,
      contextWindow: m.contextWindow,
      maxOutputTokens: m.maxOutputTokens,
      cost: const ModelCost(input: 2.5, output: 10),
    );

    UsageLedger ledgerOf(List<ModelRef> models) {
      final b = _Journal(at)..user('task');
      for (final m in models) {
        b.assistant(m, _u(input: 10));
      }
      return buildUsageLedger(b.snapshot());
    }

    test('a model with no prices and a model absent from the catalog are '
        'listed; a priced one is not', () {
      final ghost = _model('local', 'removed-from-config');
      final ledger = ledgerOf([gpt, claude, ghost]);
      final catalog = FixedModelCatalog([priced(gpt), claude]);

      expect(modelsWithoutPrice(ledger, catalog), {
        'anthropic/claude-sonnet-4',
        'local/removed-from-config',
      });
    });

    test('the ledger itself does not depend on the catalog', () {
      final ledger = ledgerOf([gpt, claude]);
      final before = ledger.serialize();

      modelsWithoutPrice(ledger, FixedModelCatalog([gpt]));

      expect(ledger.serialize(), before);
      expect(before, isNot(contains('noPrice')));
    });
  });
}

final _sid = SessionId('01JB8Q2W6R9T3M5K7N1P4X8Z0C');

ModelRef _model(String provider, String id) => ModelRef(
  provider: provider,
  id: id,
  api: ProviderApi.openaiChat,
  baseUrl: Uri.parse('http://localhost:8080/v1'),
  contextWindow: 32000,
  maxOutputTokens: 4096,
);

Usage _u({int input = 0, int output = 0, int cacheRead = 0, double cost = 0}) =>
    Usage(
      input: input,
      output: output,
      cacheRead: cacheRead,
      cost: UsageCost(input: cost),
    );

SessionHeader _header(DateTime at) => SessionHeader(
  id: _sid,
  cwd: '/proj',
  created: at,
  agent: const AgentInfo(name: 'test', version: '0'),
);

/// Цепочка записей журнала: каждая запись — потомок предыдущей.
final class _Journal {
  _Journal(this.at);

  final DateTime at;
  final records = <SessionRecord>[];

  List<String> get ids => [for (final r in records) r.id];

  String _id() => 'r${records.length.toString().padLeft(7, '0')}';

  String? get _parent => records.isEmpty ? null : records.last.id;

  void _message(Message message, {String? origin, CommandRef? command}) =>
      records.add(
        MessageRecord(
          id: _id(),
          parentId: _parent,
          timestamp: at,
          message: message,
          origin: origin,
          command: command,
        ),
      );

  void user(String text, {String? origin, CommandRef? command}) => _message(
    UserMessage([TextContent(text)], timestamp: at),
    origin: origin,
    command: command,
  );

  void assistant(
    ModelRef model,
    Usage usage, {
    StopReason stop = StopReason.stop,
    List<String> calls = const [],
    Map<String, Object?> args = const {'path': 'a.txt'},
    String text = 'ok',
    String? origin,
  }) => _message(
    AssistantMessage(
      content: [
        TextContent(text),
        for (final id in calls) ToolCall(id: id, name: 'read', arguments: args),
      ],
      model: model,
      usage: usage,
      stopReason: calls.isEmpty ? stop : StopReason.toolUse,
      timestamp: at,
    ),
    origin: origin,
  );

  void toolResult(String callId, {String text = 'result'}) => _message(
    ToolResultMessage(
      toolCallId: callId,
      toolName: 'read',
      content: [TextContent(text)],
      isError: false,
      timestamp: at,
    ),
  );

  void subagent(String subagentId, String status, {Usage? usage}) =>
      records.add(
        SubagentRecord(
          id: _id(),
          parentId: _parent,
          timestamp: at,
          subagentId: subagentId,
          toolCallId: 'call_$subagentId',
          agent: 'explore',
          description: 'look around',
          status: status,
          usage: usage,
        ),
      );

  void compaction({Usage? usage, String model = 'openai/gpt-4o-mini'}) =>
      records.add(
        CompactionRecord(
          id: _id(),
          parentId: _parent,
          timestamp: at,
          summary: 'summary',
          firstKeptId: records.first.id,
          tokensBefore: 1000,
          tokensAfter: 100,
          details: {
            'splitTurn': false,
            'summaryModel': model,
            'usage': ?usage?.toJson(),
          },
        ),
      );

  SessionSnapshot snapshot() => SessionSnapshot(
    header: _header(at),
    records: records,
    leafId: records.isEmpty ? null : records.last.id,
  );
}
