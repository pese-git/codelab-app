import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/testing.dart';
import 'package:test/test.dart';

import '../host/core_harness.dart' show inMemoryJournal, noExec, textStep;
import '../support/manual_stream.dart';

/// Встроенные команды MVP `/compact`, `/mode`, `/model` в `AgentSession.prompt`
/// (agent-slash-commands «Встроенные команды MVP»; design.md change
/// `add-agent-builtin-slash-commands`, D1, D5, D6, D12; K-02, R-08;
/// `agent-core-architecture` §13.6, §13.7, §9.5, §9.8).
///
/// Тесты идут через публичные `AgentSession.prompt` и `events`, как у хостов
/// (мост ACP, встроенный агент, `codelab`). Списки команд, `/status`, `/help`
/// и неизвестная команда — в `test/commands/builtin_commands_test.dart`, там
/// же есть источник конфигурации.
///
/// Окно модели — 32000 токенов, хвост сжатия — 2048 токенов: два хода по
/// `'a' * 8000` и `'b' * 16000` символов дают регион для среза, но до порога
/// `afterTurn` (24000) не доходят; ход с `'b' * 100000` порог превышает.
void main() {
  group('/compact', () {
    test('with a focus: the summary request has the <focus> block, the '
        'journal gets one compaction record and no record of the command; '
        'the answer is Compacted: X → Y tokens. (scenario "/compact с '
        'указанием", K-02, D5)', () async {
      final rig = await _Rig.create(steps: _twoTurns());
      final session = await rig.session();
      await rig.history(session);
      final before = await rig.records(session);

      final reply = await rig.ask(session, '/compact API changes');

      final compacted = reply.events.whereType<ContextCompacted>().single;
      expect(compacted.tokensBefore, greaterThan(compacted.tokensAfter));
      expect(
        reply.text,
        'Compacted: ${compacted.tokensBefore} → ${compacted.tokensAfter} '
        'tokens.',
      );
      expect(reply.result.reason, TurnEndReason.completed);
      final summary = rig.summaryRequests.single;
      expect(_text(summary), contains('<focus>'));
      expect(_text(summary), contains('API changes'));
      final after = await rig.records(session);
      expect(
        [for (final r in after.skip(before.length)) r.runtimeType],
        [CompactionRecord],
        reason: 'neither the prompt /compact nor the answer is written',
      );
      expect(_userTexts(after), isNot(contains('/compact API changes')));
    });

    test('the events: TurnStarted, ContextCompacted, one message, '
        'TurnEnded(completed)', () async {
      final rig = await _Rig.create(steps: _twoTurns());
      final session = await rig.session();
      await rig.history(session);

      final reply = await rig.ask(session, '/compact');

      expect(
        [for (final e in reply.events) e.runtimeType],
        [
          TurnStarted,
          ContextCompacted,
          MessageStarted,
          MessageDelta,
          MessageEnded,
          TurnEnded,
        ],
      );
    });

    test('without a focus: no <focus> block in the summary request', () async {
      final rig = await _Rig.create(steps: _twoTurns());
      final session = await rig.session();
      await rig.history(session);

      final reply = await rig.ask(session, '/compact');

      expect(reply.text, startsWith('Compacted: '));
      expect(_text(rig.summaryRequests.single), isNot(contains('<focus>')));
    });

    test('the log: command.builtin run without the focus; compaction.done '
        'with trigger manual (D12)', () async {
      final rig = await _Rig.create(steps: _twoTurns());
      final session = await rig.session();
      await rig.history(session);

      await rig.ask(session, '/compact secret-focus-123');

      expect(rig.logger.eventsOf('command.builtin').single.fields, {
        'session_id': session.id.value,
        'name': 'compact',
        'subcommand': 'run',
      });
      expect(
        rig.logger.eventsOf('compaction.done').single.fields['trigger'],
        'manual',
      );
      expect(
        [for (final r in rig.logger.records) r.toString()].join('\n'),
        isNot(contains('secret-focus-123')),
      );
    });

    test('nothing to compact: the text, no summary request, no new records '
        '(scenario "Нечего сжимать")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final before = await rig.records(session);

      final reply = await rig.ask(session, '/compact');

      expect(reply.text, 'Nothing to compact.');
      expect(reply.result.reason, TurnEndReason.completed);
      expect(rig.streamCalls, 0);
      expect((await rig.records(session)).length, before.length);
    });

    test('a running background afterTurn is awaited first: no two '
        'compactions of one branch at once (D5, §9.5)', () async {
      final rig = await _Rig.create(
        steps: [
          textStep('a' * 8000),
          // Выше порога afterTurn (24000 токенов): фоновое сжатие стартует.
          textStep('b' * 100000),
          // Запросы суммаризатора после удержанного первого.
          textStep('## Summary\n- manual'),
          textStep('## Summary\n- manual 2'),
          textStep('## Summary\n- manual 3'),
        ],
        holdSummary: 0,
      );
      final session = await rig.session();
      await rig.history(session, background: true);

      var done = false;
      final command = rig.ask(session, '/compact').whenComplete(() {
        done = true;
      });
      await pumpEventQueue();

      expect(done, isFalse, reason: 'waits for the background compaction');
      expect(rig.summaryCalls, 1, reason: 'no concurrent summary request');
      rig.finishHeld('## Summary\n- background');
      final reply = await command;

      expect(reply.result.reason, TurnEndReason.completed);
      expect(
        reply.text,
        anyOf(startsWith('Compacted: '), 'Nothing to compact.'),
      );
      expect(
        reply.events.whereType<ContextCompacted>(),
        isNotEmpty,
        reason: 'the background compaction did end during the wait',
      );
      expect(
        reply.events.indexWhere((e) => e is ContextCompacted),
        lessThan(reply.events.indexWhere((e) => e is TurnStarted)),
        reason: 'the background compaction ended before the command began',
      );
    });

    test('session/cancel during the summary: cancelled without a message, '
        'no compaction record, the slot is free (scenario "Отмена '
        '/compact", CMP-4)', () async {
      final rig = await _Rig.create(
        steps: [..._twoTurns(), textStep('hello')],
        holdSummary: 0,
      );
      final session = await rig.session();
      await rig.history(session);
      final before = await rig.records(session);

      final command = rig.ask(session, '/compact');
      await pumpEventQueue();
      expect(rig.summaryCalls, 1);
      await session.cancel();
      final reply = await command;

      expect(reply.result.reason, TurnEndReason.cancelled);
      expect(
        [for (final e in reply.events) e.runtimeType],
        [TurnStarted, TurnEnded],
      );
      expect(reply.text, '');
      expect((await rig.records(session)).length, before.length);
      expect(rig.logger.eventsOf('command.builtin.cancelled').single.fields, {
        'session_id': session.id.value,
        'name': 'compact',
        'subcommand': 'run',
      });
      final next = await session.prompt(const [TextContent('go on')]);
      expect(next.reason, TurnEndReason.completed);
    });

    test(
      'the cancel token of the prompt ends the command the same way',
      () async {
        final rig = await _Rig.create(steps: _twoTurns(), holdSummary: 0);
        final session = await rig.session();
        await rig.history(session);
        final source = CancelTokenSource();

        final command = rig.ask(session, '/compact', cancel: source.token);
        await pumpEventQueue();
        source.cancel();
        final reply = await command;

        expect(reply.result.reason, TurnEndReason.cancelled);
        expect(
          (await rig.records(session)).whereType<CompactionRecord>(),
          isEmpty,
        );
      },
    );

    test('a second prompt during /compact is rejected like during a turn '
        'of the model (slot of the turn, D12)', () async {
      final rig = await _Rig.create(steps: _twoTurns(), holdSummary: 0);
      final session = await rig.session();
      await rig.history(session);
      final command = rig.ask(session, '/compact');
      await pumpEventQueue();

      await expectLater(
        session.prompt(const [TextContent('hello')]),
        throwsA(isA<StateError>()),
      );

      await session.cancel();
      await command;
    });

    test('a failed summary: AgentError(compaction) without retrying, '
        'TurnEnded(failed), no message, the journal is unchanged '
        '(CompactionFailed, Q9, CMP-3)', () async {
      final rig = await _Rig.create(
        steps: [
          ..._twoTurns().take(2),
          {
            'error': {'class': 'rateLimited', 'message': 'slow down'},
          },
          textStep('hello'),
        ],
      );
      final session = await rig.session();
      await rig.history(session);
      final before = await rig.records(session);

      final reply = await rig.ask(session, '/compact');

      expect(
        [for (final e in reply.events) e.runtimeType],
        [TurnStarted, AgentError, TurnEnded],
      );
      final error = reply.events.whereType<AgentError>().single;
      expect(error.cls, AgentErrorClass.compaction);
      expect(error.retrying, isFalse);
      expect(reply.result.reason, TurnEndReason.failed);
      expect(reply.text, '');
      expect((await rig.records(session)).length, before.length);
      final next = await session.prompt(const [TextContent('go on')]);
      expect(next.reason, TurnEndReason.completed, reason: 'the slot is free');
    });

    test('without the capability compaction the command is not declared '
        'and is unknown (Q10)', () async {
      final rig = await _Rig.create(compaction: false);
      final session = await rig.session();

      final reply = await rig.ask(session, '/compact');

      expect([
        for (final c in session.commands) c.name,
      ], isNot(contains('compact')));
      expect(
        reply.text,
        'Unknown command: /compact. Run /help to list commands.',
      );
      expect(rig.streamCalls, 0);
    });
  });

  group('/mode (scenario "/mode plan", D6, Q3)', () {
    test('the events: TurnStarted, ModeChanged, the message, TurnEnded; the '
        'model is not asked', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final reply = await rig.ask(session, '/mode plan');

      expect(
        [for (final e in reply.events) e.runtimeType],
        [
          TurnStarted,
          ModeChanged,
          MessageStarted,
          MessageDelta,
          MessageEnded,
          TurnEnded,
        ],
      );
      expect(reply.events.whereType<ModeChanged>().single.mode, ModeId.plan);
      expect(reply.text, 'Mode: plan.');
      expect(reply.result.reason, TurnEndReason.completed);
      expect(session.mode, ModeId.plan);
      expect(rig.streamCalls, 0);
    });

    test('the journal gets mode_change and no record of the prompt or the '
        'answer', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final before = await rig.records(session);

      await rig.ask(session, '/mode plan');

      final added = (await rig.records(session)).skip(before.length).toList();
      expect([for (final r in added) r.runtimeType], [ModeChangeRecord]);
      expect((added.single as ModeChangeRecord).modeId, 'plan');
    });

    test('the way is setMode: the change id of the event is the one of the '
        'session counter', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final first = await rig.ask(session, '/mode plan');
      final second = await rig.ask(session, '/mode ask');

      final a = first.events.whereType<ModeChanged>().single.changeId;
      final b = second.events.whereType<ModeChanged>().single.changeId;
      expect(a, isNotNull);
      expect(b, greaterThan(a!));
    });

    test('an old synonym is normalized, the answer has the main id', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final architect = await rig.ask(session, '/mode architect');
      expect(architect.text, 'Mode: plan.');
      expect(session.mode, ModeId.plan);
      final code = await rig.ask(session, '/mode code');
      expect(code.text, 'Mode: bypass.');
      expect(session.mode, ModeId.bypass);
      expect((await rig.ask(session, '/mode debug')).text, 'Mode: standard.');
      expect(
        (await rig.ask(session, '/mode acceptEdits')).text,
        'Mode: accept-edits.',
      );
    });

    test(
      'without an argument: the current mode and the list, no change',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();
        final before = await rig.records(session);

        final reply = await rig.ask(session, '/mode');

        expect(
          reply.text,
          'Mode: standard. Available: plan, ask, standard, accept-edits, '
          'bypass.',
        );
        expect(reply.events.whereType<ModeChanged>(), isEmpty);
        expect((await rig.records(session)).length, before.length);
      },
    );

    test(
      'autopilot and an unknown id: Unknown mode, the mode and the '
      'journal are unchanged (scenario "Неизвестный режим", §10.5)',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();
        final before = await rig.records(session);

        final autopilot = await rig.ask(session, '/mode autopilot');
        final turbo = await rig.ask(session, '/mode turbo');

        const available =
            'Available: plan, ask, standard, accept-edits, bypass.';
        expect(autopilot.text, 'Unknown mode: autopilot. $available');
        expect(turbo.text, 'Unknown mode: turbo. $available');
        expect(session.mode, ModeId.standard);
        expect(
          [...autopilot.events, ...turbo.events].whereType<ModeChanged>(),
          isEmpty,
        );
        expect((await rig.records(session)).length, before.length);
      },
    );

    test('an unknown id is cut to 64 runes', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final reply = await rig.ask(session, '/mode ${'x' * 100}');

      expect(
        reply.text,
        'Unknown mode: ${'x' * 64}. Available: plan, ask, standard, '
        'accept-edits, bypass.',
      );
    });

    test('the log: set, show, unknown; never the argument (D12)', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      await rig.ask(session, '/mode plan');
      await rig.ask(session, '/mode');
      await rig.ask(session, '/mode secret-token-123');

      expect(
        [for (final l in rig.logger.eventsOf('command.builtin')) l.fields],
        [
          for (final sub in ['set', 'show', 'unknown'])
            {'session_id': session.id.value, 'name': 'mode', 'subcommand': sub},
        ],
      );
      expect(
        [for (final r in rig.logger.records) r.toString()].join('\n'),
        isNot(contains('secret-token-123')),
      );
    });
  });

  group('/model (D6, Q3)', () {
    test('a model of the catalog: model_change, the next step uses it, the '
        'answer is Model: <provider/model>.', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final before = await rig.records(session);

      final reply = await rig.ask(session, '/model a/m2');

      expect(reply.text, 'Model: a/m2.');
      expect(reply.result.reason, TurnEndReason.completed);
      expect(
        [for (final e in reply.events) e.runtimeType],
        [
          TurnStarted,
          ModelOptionsChanged,
          MessageStarted,
          MessageDelta,
          MessageEnded,
          TurnEnded,
        ],
      );
      expect(session.model.id, 'm2');
      final added = (await rig.records(session)).skip(before.length).toList();
      expect([for (final r in added) r.runtimeType], [ModelChangeRecord]);
      expect((added.single as ModelChangeRecord).modelId, 'm2');
      expect(rig.streamCalls, 0);
      await session.prompt(const [TextContent('next')]);
      expect(rig.requestedModels.single.id, 'm2');
    });

    test('an unknown model: the text, the model and the journal are '
        'unchanged (scenario "Неизвестная модель")', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final before = await rig.records(session);

      final reply = await rig.ask(session, '/model x/y');

      expect(
        reply.text,
        'Unknown model: x/y. Run /status to see the current model.',
      );
      expect(session.model.id, 'm1');
      expect((await rig.records(session)).length, before.length);
    });

    test(
      '--role is after the MVP: the same answer with the argument',
      () async {
        final rig = await _Rig.create();
        final session = await rig.session();

        final reply = await rig.ask(session, '/model --role fast');

        expect(
          reply.text,
          'Unknown model: --role fast. Run /status to see the current model.',
        );
        expect(session.model.id, 'm1');
      },
    );

    test('without an argument: the current model and the hint', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      final reply = await rig.ask(session, '/model');

      expect(reply.text, 'Model: a/m1. Run /model <provider/model> to switch.');
      expect(session.model.id, 'm1');
    });

    test('the log: set, show, unknown; never the model name (D12)', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      await rig.ask(session, '/model a/m2');
      await rig.ask(session, '/model');
      await rig.ask(session, '/model secret/model-xyz');

      expect(
        [for (final l in rig.logger.eventsOf('command.builtin')) l.fields],
        [
          for (final sub in ['set', 'show', 'unknown'])
            {
              'session_id': session.id.value,
              'name': 'model',
              'subcommand': sub,
            },
        ],
      );
      expect(
        [for (final r in rig.logger.records) r.toString()].join('\n'),
        isNot(contains('secret/model-xyz')),
      );
    });
  });

  group('state-changing commands always wait for their work (D14)', () {
    test('/mode: cancel during the held journal write — the change is '
        'applied, the answer is by fact, no event after TurnEnded', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      rig.gate.arm((r) => r is ModeChangeRecord);

      final command = rig.ask(session, '/mode plan');
      await rig.gate.reached;
      await session.cancel();
      await pumpEventQueue();
      rig.gate.release();
      final reply = await command;

      expect(reply.result.reason, TurnEndReason.completed);
      expect(reply.text, 'Mode: plan.');
      expect(session.mode, ModeId.plan);
      expect(reply.events.last, isA<TurnEnded>());
      expect(
        reply.events.indexWhere((e) => e is ModeChanged),
        lessThan(reply.events.indexWhere((e) => e is TurnEnded)),
      );
      expect(reply.events.whereType<TurnEnded>(), hasLength(1));
    });

    test('/mode: cancelled before the change — cancelled, no record, no '
        'ModeChanged', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final before = await rig.records(session);
      final source = CancelTokenSource()..cancel();

      final reply = await rig.ask(session, '/mode plan', cancel: source.token);

      expect(reply.result.reason, TurnEndReason.cancelled);
      expect(reply.events.whereType<ModeChanged>(), isEmpty);
      expect(reply.text, '');
      expect(session.mode, ModeId.standard);
      expect((await rig.records(session)).length, before.length);
    });

    test('/model: cancelled before the change — cancelled, the model and '
        'the journal are unchanged', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      final before = await rig.records(session);
      final source = CancelTokenSource()..cancel();

      final reply = await rig.ask(session, '/model a/m2', cancel: source.token);

      expect(reply.result.reason, TurnEndReason.cancelled);
      expect(reply.events.whereType<ModelOptionsChanged>(), isEmpty);
      expect(session.model.id, 'm1');
      expect((await rig.records(session)).length, before.length);
    });

    test('/compact: cancel after the check, during the held compaction '
        'record — applied: the text, ContextCompacted before TurnEnded, '
        'end_turn', () async {
      final rig = await _Rig.create(steps: _twoTurns());
      final session = await rig.session();
      await rig.history(session);
      rig.gate.arm((r) => r is CompactionRecord);

      final command = rig.ask(session, '/compact');
      await rig.gate.reached;
      await session.cancel();
      await pumpEventQueue();
      rig.gate.release();
      final reply = await command;

      expect(reply.result.reason, TurnEndReason.completed);
      expect(reply.text, startsWith('Compacted: '));
      expect(reply.events.last, isA<TurnEnded>());
      expect(
        reply.events.indexWhere((e) => e is ContextCompacted),
        lessThan(reply.events.indexWhere((e) => e is TurnEnded)),
      );
      expect(
        (await rig.records(session)).whereType<CompactionRecord>(),
        hasLength(1),
      );
    });

    test('close() while /mode waits in the queue of changes behind a held '
        'client setMode: cancelled, no AgentError, no failed warning, no '
        'records after the close', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      rig.gate.arm((r) => r is ModeChangeRecord);
      final client = session.setMode(ModeId.ask);
      await rig.gate.reached;
      final before = await rig.records(session);

      final command = rig.ask(session, '/mode plan');
      await pumpEventQueue();
      final closing = session.close();
      await pumpEventQueue();
      rig.gate.release();
      await client;
      await closing;
      final reply = await command;

      expect(reply.result.reason, TurnEndReason.cancelled);
      expect(reply.events.whereType<AgentError>(), isEmpty);
      expect(rig.logger.eventsOf('command.builtin.failed'), isEmpty);
      expect(rig.logger.eventsOf('command.builtin.cancelled'), hasLength(1));
      expect(session.mode, ModeId.ask, reason: 'only the client change');
      final after = await rig.records(session);
      expect(
        [for (final r in after.skip(before.length)) r.runtimeType],
        [ModeChangeRecord],
        reason: 'the held client record only; nothing of /mode plan',
      );
    });

    test('close() during /compact waits for the work: no record is written '
        'after the close (summary answers after the cancel)', () async {
      final rig = await _Rig.create(
        steps: _twoTurns(),
        holdSummary: 0,
        holdIgnoresCancel: true,
      );
      final session = await rig.session();
      await rig.history(session);
      final before = await rig.records(session);
      final command = rig.ask(session, '/compact');
      await pumpEventQueue();
      expect(rig.summaryCalls, 1);

      var closed = false;
      final closing = session.close().whenComplete(() => closed = true);
      await pumpEventQueue();
      expect(closed, isFalse, reason: 'close waits for the running command');
      rig.finishHeld('## Summary\n- late');
      await closing;
      final reply = await command;

      expect(reply.result.reason, TurnEndReason.cancelled);
      expect((await rig.records(session)).length, before.length);
    });
  });

  group('only the first text block is a command (D3)', () {
    test('a command in the second block or inside a resource wrapper does '
        'not change the mode', () async {
      final rig = await _Rig.create();
      final session = await rig.session();

      await session.prompt(const [
        TextContent('hello'),
        TextContent('/mode bypass'),
      ]);
      await session.prompt(const [
        TextContent('<resource uri="file:///a">/mode bypass</resource>'),
      ]);

      expect(session.mode, ModeId.standard);
      expect(rig.streamCalls, 2, reason: 'both prompts went to the model');
    });
  });

  group('session/load', () {
    test('restores the mode and the model chosen by commands; the replay '
        'has no texts of the commands (scenario "Состояние mode и model '
        'переживает session/load", D6)', () async {
      final rig = await _Rig.create();
      final session = await rig.session();
      await rig.ask(session, '/mode plan');
      await rig.ask(session, '/model a/m2');
      await session.close();

      final loaded = await rig.runtime.loadSession(
        session.id,
        const SessionHostPorts(),
      );

      expect(loaded.mode, ModeId.plan);
      expect(loaded.model.id, 'm2');
      final replayed = _eventTexts(loaded.replay());
      expect(replayed, isNot(contains('/mode plan')));
      expect(replayed, isNot(contains('/model a/m2')));
      expect(replayed, isNot(contains('Mode: plan.')));
    });
  });
}

/// Два хода без срабатывания `afterTurn` и ответ суммаризатора третьим
/// шагом; сам журнал — `rig.history`.
List<Map<String, Object?>> _twoTurns() => [
  textStep('a' * 8000),
  textStep('b' * 16000),
  textStep('## Summary\n- done'),
];

/// Текст единственного сообщения запроса к модели.
String _text(LlmContext context) => (context.messages.single as UserMessage)
    .content
    .whereType<TextContent>()
    .map((b) => b.text)
    .join();

/// Тексты сообщений пользователя журнала.
List<String> _userTexts(List<SessionRecord> records) => [
  for (final r in records)
    if (r is MessageRecord && r.message is UserMessage)
      r.message.content.whereType<TextContent>().map((b) => b.text).join(),
];

/// Все тексты событий: ввод хода, сообщения и дельты.
List<String> _eventTexts(Iterable<AgentEvent> events) {
  String of(Message m) =>
      m.content.whereType<TextContent>().map((b) => b.text).join();
  return [
    for (final e in events)
      ...switch (e) {
        TurnStarted(:final input) => [for (final m in input) of(m)],
        MessageStarted(:final message) => [of(message)],
        MessageEnded(:final message) => [of(message)],
        MessageDelta(:final delta) => [delta],
        _ => const <String>[],
      },
  ];
}

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

final class _Rig {
  _Rig._(
    this.built,
    this.logger,
    this.store,
    this._manual,
    this._requests,
    this.requestedModels,
    this.gate,
  );

  /// [steps] — ответы scripted-модели по порядку запросов (ходы и запросы
  /// суммаризатора). [holdSummary] — номер запроса суммаризатора (с 0),
  /// ответ на который пишет тест сам (`finishHeld`): так сжатие стоит на
  /// месте, пока тест не отпустит его или не отменит.
  static Future<_Rig> create({
    List<Map<String, Object?>> steps = const [],
    bool compaction = true,
    int? holdSummary,
    bool holdIgnoresCancel = false,
  }) async {
    final user = <String, Object?>{
      'providers': {
        'a': {
          'kind': 'openai-compatible',
          'base_url': 'https://a.test/v1',
          'models': {
            'm1': {'context_window': 32000},
            'm2': {'context_window': 32000},
          },
        },
      },
      'agent': {'default_model': 'a/m1'},
      'compaction': {'keep_recent_tokens': 2048, 'enabled': compaction},
    };
    final loaded = CoreConfig.fromLayers(
      [
        ConfigTree(
          kind: ConfigLayerKind.user,
          source: '/home/u/.codelab/config.yaml',
          values: user,
          positions: const {},
        ),
      ],
      environment: const {},
      projectRoot: '/proj',
    );
    expect(loaded.issues, isEmpty, reason: loaded.issues.join('\n'));
    final config = loaded.config!;
    final clock = FakeClock();
    final logger = RecordingLogger(clock: clock);
    final scripted = ScriptedStreamFunction.fromJson({
      'steps': [...steps, for (var i = 0; i < 10; i++) textStep('ok')],
    }, clock: clock);
    final store = MemorySessionStore();
    final gate = _GateStore(store);
    final manual = ManualStream(clock);
    final requests = <LlmContext>[];
    final models = <ModelRef>[];
    var summaries = 0;
    final rig = _Rig._(
      buildAgentCore(
        profile: HostProfile.of(
          'agent-serve',
        ).narrowed({...inMemoryJournal, ...noExec}),
        services: AgentCoreServices(
          baseEnv: MemoryExecutionEnv(cwd: '/proj'),
          logger: logger,
          clock: clock,
          ids: SequentialIdGenerator(),
          sessions: gate,
          models: StaticModelCatalog(config.providers, logger: logger),
        ),
        config: config,
        streamFunction: (ref, context, {cancel}) {
          requests.add(context);
          models.add(ref);
          // Запрос суммаризатора узнаётся по ключу кэша (`<сессия>:summary`).
          if (context.cacheKey?.endsWith(':summary') ?? false) {
            if (summaries++ == holdSummary) {
              // Поставщик, не реагирующий на отмену: проверяет, что `close()`
              // ждёт работу команды, а не полагается на быстрый выход (D14).
              return manual.call(
                ref,
                context,
                cancel: holdIgnoresCancel ? null : cancel,
              );
            }
          }
          return scripted.call(ref, context, cancel: cancel);
        },
      ),
      logger,
      store,
      manual,
      requests,
      models,
      gate,
    );
    addTearDown(rig.built.runtime.dispose);
    return rig;
  }

  final BuiltAgentCore built;
  final RecordingLogger logger;
  final MemorySessionStore store;
  final ManualStream _manual;
  final List<LlmContext> _requests;

  /// Модель каждого запроса в порядке запросов.
  final List<ModelRef> requestedModels;

  /// Ворота записи журнала: держат запись выбранного вида до `release()`.
  final _GateStore gate;

  AgentRuntime get runtime => built.runtime;

  /// Число запросов к модели, включая запросы суммаризатора.
  int get streamCalls => _requests.length;

  /// Запросы суммаризатора (ход модели ключа `:summary` не имеет).
  List<LlmContext> get summaryRequests => [
    for (final r in _requests)
      if (r.cacheKey?.endsWith(':summary') ?? false) r,
  ];

  int get summaryCalls => summaryRequests.length;

  Future<AgentSession> session() =>
      runtime.createSession(SessionSpec(cwd: '/proj', mode: ModeId.standard));

  /// Два хода пользователя (`_twoTurns`), чтобы у журнала был регион сжатия.
  ///
  /// Предусловие теста: фоновое сжатие `afterTurn` не стартовало
  /// ([background] `false`) либо стартовало ([background] `true`); иначе
  /// размеры ходов разошлись с окном модели и тест проверял бы не то.
  Future<void> history(AgentSession session, {bool background = false}) async {
    await session.prompt(const [TextContent('first task')]);
    await session.prompt(const [TextContent('second task')]);
    expect(
      summaryCalls,
      background ? 1 : 0,
      reason: 'afterTurn precondition of the history',
    );
  }

  Future<List<SessionRecord>> records(AgentSession session) async =>
      (await store.open(session.id)).records;

  /// Отпускает удержанный запрос суммаризатора готовым ответом [text].
  void finishHeld(String text) {
    final state = _manual.state..start();
    final block = state.openBlock(BlockKind.text);
    state
      ..append(block, text)
      ..finish(StopReason.stop);
    _manual.end();
  }

  /// Отправляет [text] и собирает события хода.
  Future<_Reply> ask(
    AgentSession session,
    String text, {
    CancelToken? cancel,
  }) async {
    final events = <AgentEvent>[];
    final subscription = session.events.listen(events.add);
    // Поздний подписчик получает события предыдущего хода из буфера сессии
    // (`AgentSession.events`): ответ команды — только то, что пришло после.
    await pumpEventQueue();
    events.clear();
    final result = await session.prompt([TextContent(text)], cancel: cancel);
    await pumpEventQueue();
    await subscription.cancel();
    return _Reply(events, result);
  }
}

/// Хранилище, которое держит запись журнала выбранного вида, пока тест не
/// отпустит её: так «команда уже начала смену, а запись ещё идёт» становится
/// детерминированным состоянием без пауз по времени.
final class _GateStore implements SessionStore {
  _GateStore(this.inner);

  final MemorySessionStore inner;
  bool Function(SessionRecord record)? _holds;
  Completer<void>? _gate;
  final _reached = Completer<void>();

  /// Следующая запись, для которой [holds] истинно, ждёт [release].
  void arm(bool Function(SessionRecord record) holds) {
    _holds = holds;
    _gate = Completer<void>();
  }

  /// Запись дошла до ворот и ждёт.
  Future<void> get reached => _reached.future;

  void release() => _gate!.complete();

  @override
  Future<void> create(SessionHeader header) => inner.create(header);

  @override
  Future<String> createChild(SessionHeader header) => inner.createChild(header);

  @override
  Future<void> append(
    SessionId id,
    SessionRecord record, {
    bool durable = false,
  }) async {
    final gate = _gate;
    if (gate != null && (_holds?.call(record) ?? false)) {
      if (!_reached.isCompleted) {
        _reached.complete();
      }
      await gate.future;
    }
    await inner.append(id, record, durable: durable);
  }

  @override
  Future<void> flush(SessionId id) => inner.flush(id);

  @override
  Future<SessionSnapshot> open(SessionId id) => inner.open(id);

  @override
  Future<SessionPage> list({String? cwd, String? cursor, int pageSize = 50}) =>
      inner.list(cwd: cwd, cursor: cursor, pageSize: pageSize);

  @override
  Future<void> close(SessionId id) => inner.close(id);
}
