import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../permissions/policy_harness.dart' show deniedText;
import 'subagent_rig.dart';

/// Режим ребёнка сужается по цепочке предков при каждом решении
/// (agent-subagents «Сборка ребёнка», «Смена режима родителя посреди работы
/// ребёнка»; agent-permissions «Разрешения потомка через gate корневой
/// сессии», последний абзац; SUB-2; design.md change
/// `add-subagents-and-tasks`, D36 Т3; `agent-core/17-3-subagents.md`
/// §17.3.3, шаг 4).
///
/// Красные до задачи 2.4: нет `narrow` в `permissions/modes.dart` и режима
/// ребёнка, вычисляемого на каждое решение.
///
/// Фиксируемый API: `narrow(parent, typeMode)` — `parent` и результат —
/// пара `({PermissionMode mode, Set<ToolTier> deniedTiers})`, `typeMode` —
/// `ModeId?` определения типа (`null` — режим родителя как есть).
void main() {
  ({PermissionMode mode, Set<ToolTier> deniedTiers}) pair(ModeId id) =>
      (mode: id.permissionMode, deniedTiers: id.deniedTiers);

  group('narrow: примеры §17.3.3', () {
    void expectNarrow(
      ModeId parent,
      ModeId? type,
      PermissionMode mode,
      Set<ToolTier> denied,
    ) {
      final result = narrow(pair(parent), type);

      expect(result.mode, mode, reason: '$parent + $type');
      expect(result.deniedTiers, denied, reason: '$parent + $type');
    }

    const changes = {ToolTier.write, ToolTier.exec};

    test('родитель standard + тип plan → write с запретом write и exec', () {
      expectNarrow(ModeId.standard, ModeId.plan, PermissionMode.write, changes);
    });

    test('родитель ask + тип plan → alwaysAsk с тем же запретом', () {
      expectNarrow(ModeId.ask, ModeId.plan, PermissionMode.alwaysAsk, changes);
    });

    test('родитель plan + тип без режима → запрет родителя', () {
      expectNarrow(ModeId.plan, null, PermissionMode.write, changes);
    });

    test('родитель bypass + тип standard → write без запретов', () {
      expectNarrow(ModeId.bypass, ModeId.standard, PermissionMode.write, {});
    });

    test('родитель accept-edits + тип standard → write', () {
      expectNarrow(
        ModeId.acceptEdits,
        ModeId.standard,
        PermissionMode.write,
        {},
      );
    });

    test('тип без режима берёт режим родителя как есть', () {
      expectNarrow(ModeId.bypass, null, PermissionMode.yolo, {});
      expectNarrow(ModeId.acceptEdits, null, PermissionMode.acceptEdits, {});
    });

    test('результат не мягче ни родителя, ни типа (SUB-2)', () {
      for (final parent in ModeId.values) {
        for (final type in [...ModeId.values, null]) {
          final result = narrow(pair(parent), type);
          final p = pair(parent);

          expect(
            result.mode.index,
            lessThanOrEqualTo(p.mode.index),
            reason: '$parent + $type',
          );
          expect(result.deniedTiers, containsAll(p.deniedTiers));
          if (type != null) {
            expect(
              result.mode.index,
              lessThanOrEqualTo(type.permissionMode.index),
            );
            expect(result.deniedTiers, containsAll(type.deniedTiers));
          }
        }
      }
    });
  });

  test('сценарий «Смена режима родителя посреди работы ребёнка»: write '
      'ребёнка после перехода корня в plan отклонён причиной режима без '
      'вопроса', () async {
    final gate = FakeGate();
    final env = MemoryExecutionEnv(cwd: '/proj');
    final rig = SubagentRig(
      baseEnv: env,
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('edit the file')),
          replyStep('done'),
        ],
        // Первый ответ ребёнка ждёт часы: корень успевает сменить режим.
        'edit the file': [
          oneCallStep('w1', 'write', {
            'path': 'a.txt',
            'content': 'x',
          }, delayMs: 10),
          replyStep('could not write'),
        ],
      },
      gate: gate,
      config: rigConfig(mode: ModeId.bypass),
    );
    await rig.open();

    final turn = rig.run('go');
    await pumpUntil(
      () => rig.clock.pendingTimers > 0,
      reason: 'the child never reached its first model request',
    );
    await rig.session.setMode(ModeId.plan);
    await rig.clock.elapse(const Duration(milliseconds: 10));
    await turn;

    final second = rig.requestsOf('edit the file')[1];
    expect(
      resultText(second, 'w1'),
      deniedText('write', 'plan mode: changes are not allowed'),
    );
    expect(gate.requests, isEmpty, reason: 'режим отказал без вопроса');
    expect(await env.stat('/proj/a.txt'), isA<Err<FileStat, FileError>>());
  });

  test('тип с режимом standard под корнем в bypass не получает права '
      'корня: write ребёнка — вопрос, а вопроса без gate нет (D38)', () async {
    final gate = FakeGate();
    final env = MemoryExecutionEnv(cwd: '/proj');
    final rig = SubagentRig(
      baseEnv: env,
      projectFiles: AgentsPort([
        agentFile('careful', scope: 'subagent', extra: {'mode': 'standard'}),
      ]),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('careful job', type: 'careful')),
          oneCallStep('c2', 'agent', agentArgs('free job')),
          replyStep('done'),
        ],
        'careful job': [
          oneCallStep('w1', 'write', {'path': 'careful.txt', 'content': 'x'}),
          replyStep('stopped'),
        ],
        'free job': [
          oneCallStep('w2', 'write', {'path': 'free.txt', 'content': 'y'}),
          replyStep('written'),
        ],
      },
      gate: gate,
      config: rigConfig(mode: ModeId.bypass),
    );
    await rig.open();

    await rig.run('go');

    expect(
      resultText(rig.requestsOf('careful job')[1], 'w1'),
      deniedText('write', 'no approval interface is available'),
    );
    expect(resultIsError(rig.requestsOf('free job')[1], 'w2'), isFalse);
    expect(
      await env.stat('/proj/careful.txt'),
      isA<Err<FileStat, FileError>>(),
    );
    expect(await env.stat('/proj/free.txt'), isA<Ok<FileStat, FileError>>());
    expect(gate.requests, isEmpty);
  });
}
