import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import '../permissions/fake_gate.dart';
import '../permissions/policy_harness.dart' show deniedText;
import '../tools/fake_shell.dart';
import 'subagent_rig.dart';

/// Защищённые пути корня у ребёнка (agent-subagents «Сборка ребёнка»,
/// сценарий «Защищённые пути корневой сессии у ребёнка»; PERM-11, SUB-1;
/// design.md change `add-subagents-and-tasks`, D34, D36 Т9;
/// `agent-core/17-3-subagents.md` §17.3.3 шаг 5; задача 2.11).
///
/// Красный до задач 2.4 и 2.11: нет ребёнка, а политика ребёнка должна
/// получать `agentConfigPaths` корня, а не считать их заново.
///
/// В итерации 2 у ребёнка нет gate (D38): критическое действие, которое у
/// корня стало бы вопросом, у ребёнка — отказ. Именно это отличает
/// критический путь от обычного при режиме `bypass` (обычная запись
/// проходит). Итерация 3 заменяет ожидаемый отказ вопросом через
/// `SubagentPermissionGate`.
void main() {
  test('сценарий «Защищённые пути корня у ребёнка»: bypass, ребёнок general '
      'пишет в .codelab/config.yaml и копирует в \$CODELAB_HOME/agents — оба '
      'вызова критические, как у корня, и не исполняются', () async {
    final shell = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering(''));
    final gate = FakeGate();
    final rig = SubagentRig(
      baseEnv: shell,
      narrow: const {},
      gate: gate,
      // Пути хоста: тот же набор, что у корня; $CODELAB_HOME раскрывается
      // значением хоста.
      agentConfigPaths: AgentConfigPaths(
        paths: const ['/home/u/.codelab'],
        expansions: const {
          'HOME': '/home/u',
          'CODELAB_HOME': '/home/u/.codelab',
        },
      ),
      config: rigConfig(mode: ModeId.bypass),
      scripts: {
        'go': [
          oneCallStep('c1', 'agent', agentArgs('touch the config')),
          replyStep('done'),
        ],
        'touch the config': [
          oneCallStep('w1', 'write', {
            'path': '.codelab/config.yaml',
            'content': 'x',
          }),
          oneCallStep('x1', 'exec', {
            'command': r'cp /tmp/a.md $CODELAB_HOME/agents/a.md',
          }),
          oneCallStep('w2', 'write', {'path': 'notes.txt', 'content': 'ok'}),
          replyStep('finished'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    final child = rig.requestsOf('touch the config').last;
    expect(resultIsError(child, 'w1'), isTrue);
    expect(
      resultText(child, 'w1'),
      contains('Editing agent configuration requires a human'),
    );
    expect(
      resultText(child, 'x1'),
      deniedText('exec', 'no approval interface is available'),
    );
    // Контроль: обычная запись при bypass проходит — отказы выше вызваны
    // именно защитой путей, а не режимом.
    expect(resultIsError(child, 'w2'), isFalse);
    expect(shell.commands, isEmpty);
    expect(gate.requests, isEmpty, reason: 'gate корня ребёнок не зовёт');
  });

  test('«разрешить всегда» корня на путь конфигурации не действует на '
      'ребёнка (PERM-11, SUB-2: решения общие, критичность — тоже)', () async {
    final gate = FakeGate((_) => PermissionDecision.allowAlways);
    final rig = SubagentRig(
      gate: gate,
      config: rigConfig(mode: ModeId.bypass),
      scripts: {
        'go': [
          oneCallStep('w0', 'write', {
            'path': '.codelab/config.yaml',
            'content': 'root',
          }),
          oneCallStep('c1', 'agent', agentArgs('touch the config')),
          replyStep('done'),
        ],
        'touch the config': [
          oneCallStep('w1', 'write', {
            'path': '.codelab/config.yaml',
            'content': 'child',
          }),
          replyStep('finished'),
        ],
      },
    );
    await rig.open();

    await rig.run('go');

    // Корень спросил и получил allowAlways, который для критического пути не
    // сохраняется; ребёнок всё равно получает отказ без вопроса.
    expect(
      gate.requests.map((r) => r.allowAlwaysOffered),
      everyElement(isFalse),
    );
    expect(
      resultText(rig.requestsOf('touch the config').last, 'w1'),
      contains('requires a human'),
    );
  });
}
