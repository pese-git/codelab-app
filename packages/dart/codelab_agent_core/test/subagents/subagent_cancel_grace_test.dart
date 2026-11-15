import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../support/models.dart';
import 'subagent_rig.dart';

/// `cancel_grace` (agent-subagents «Жизненный цикл и отмена»; D5;
/// `agent-core/17-3-subagents.md` §17.3.4, шаг 8): ребёнок, переживший
/// отмену, не держит вызов дольше grace, но слот освобождается только после
/// его реальной остановки.
void main() {
  test('после отмены и истечения grace: один SubagentFinished(cancelled), '
      'agent получает cancelled, событий ребёнка после итога нет, слот '
      'освобождается после реальной остановки', () async {
    final hang = Completer<Result<String, FileError>>();
    final env = _HangingEnv(hang.future);
    final rig = SubagentRig(
      baseEnv: env,
      config: CoreConfig(
        defaultModel: subagentTestModel,
        subagents: const SubagentsConfig(cancelGrace: Duration(seconds: 5)),
      ),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('stuck child')),
          replyStep('never requested'),
        ],
        'stuck child': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          replyStep('never requested'),
        ],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(() => env.reading, reason: 'the child never started read');
    await rig.session.cancel();
    await pumpEventQueue(times: 30);
    expect(rig.eventsOf<SubagentFinished>(), isEmpty, reason: 'grace идёт');
    await rig.clock.elapse(const Duration(seconds: 5));
    final result = await turn;

    expect(result.reason, TurnEndReason.cancelled);
    final finished = rig.eventsOf<SubagentFinished>().single;
    expect(finished.status, SubagentState.cancelled);
    expect(
      rig.eventsOf<ToolCallFinished>().single.outcome,
      ToolOutcome.cancelled,
    );
    final events = rig.events;
    final at = events.indexOf(finished);
    expect(events.skip(at + 1).whereType<SubagentActivity>(), isEmpty);
    expect(rig.logger.eventsOf('subagent.cancel_grace_exceeded'), hasLength(1));
    // Ребёнок ещё занят `read`: слот не освобождён.
    expect(rig.logger.eventsOf('subagent.slot.release'), isEmpty);

    hang.complete(Err(FileError(FileErrorCode.notFound, 'a.txt')));
    await pumpUntil(
      () => rig.logger.eventsOf('subagent.slot.release').isNotEmpty,
      reason: 'the slot is released after the child really stops',
    );
    expect(rig.eventsOf<SubagentFinished>(), hasLength(1));
    expect(
      rig.events.skip(at + 1).whereType<SubagentActivity>(),
      isEmpty,
      reason: 'поздние события ребёнка не переизлучаются',
    );
  });

  test('внук застрял в инструменте: после grace ребёнок и внук — по одному '
      'SubagentFinished(cancelled), ход завершается, менеджер внука '
      'закрывается вместе с сессией ребёнка (D5, D45 Т2)', () async {
    final hang = Completer<Result<String, FileError>>();
    final env = _HangingEnv(hang.future);
    final rig = SubagentRig(
      baseEnv: env,
      config: CoreConfig(
        defaultModel: subagentTestModel,
        subagents: const SubagentsConfig(cancelGrace: Duration(seconds: 5)),
      ),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('kid job')),
          replyStep('never requested'),
        ],
        'kid job': [
          oneCallStep('g1', 'agent', agentArgs('stuck grand')),
          replyStep('never requested'),
        ],
        'stuck grand': [
          oneCallStep('r1', 'read', {'path': 'a.txt'}),
          replyStep('never requested'),
        ],
      },
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(() => env.reading, reason: 'the grandchild never read');
    await rig.session.cancel();
    await pumpEventQueue(times: 30);
    await rig.clock.elapse(const Duration(seconds: 5));
    final result = await turn;

    expect(result.reason, TurnEndReason.cancelled);
    // Ребёнок объявлен отменённым по grace раньше, чем завершились его
    // потомки: события внука после итога ребёнка до клиента не доходят.
    final kid = rig.eventsOf<SubagentFinished>().single;
    expect(kid.status, SubagentState.cancelled);
    final at = rig.events.indexOf(kid);
    expect(rig.events.skip(at + 1).whereType<SubagentActivity>(), isEmpty);

    hang.complete(Err(FileError(FileErrorCode.notFound, 'a.txt')));
    await pumpUntil(
      () => rig.logger.eventsOf('subagent.slot.release').length == 2,
      reason: 'both slots are released after the real stop',
    );
    // Менеджер внука довёл его до итога в журнале ребёнка (SUB-4, SUB-6).
    final kidJournal = rig.store.textOf(kid.childSessionId!)!;
    expect(kidJournal, contains('"status":"cancelled"'));
    expect(rig.eventsOf<SubagentFinished>(), hasLength(1));
  });

  test('таймер grace не создаётся после завершения вызова', () async {
    final rig = SubagentRig(
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('quick child')),
          replyStep('done'),
        ],
        'quick child': [replyStep('ok')],
      },
    );
    await rig.open();

    await rig.run('go');
    await pumpEventQueue(times: 30);
    await rig.session.cancel();
    await pumpEventQueue(times: 30);

    expect(rig.clock.pendingTimers, 0);
  });
}

/// Env, чей `readText` не отвечает, пока тест не разрешит: ребёнок «застревает»
/// в инструменте и не реагирует на отмену.
final class _HangingEnv implements ExecutionEnv {
  _HangingEnv(this._read);

  final Future<Result<String, FileError>> _read;
  final _inner = MemoryExecutionEnv(cwd: '/proj');
  var reading = false;

  @override
  String get cwd => _inner.cwd;

  @override
  Future<Result<String, FileError>> readText(
    String path, {
    int? line,
    int? limit,
  }) {
    reading = true;
    return _read;
  }

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
