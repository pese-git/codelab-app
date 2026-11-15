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
/// Итерация 3 (задача 3.1, D42 Т6): критическое действие, которое у корня
/// стало бы вопросом, у ребёнка — вопрос к gate корня с цепочкой `toolCallId`
/// и `allowAlwaysOffered: false`; запись в конфигурацию агента — отказ без
/// вопроса, как у корня. Обычная запись при `bypass` проходит без вопроса:
/// именно это отличает критический путь от обычного. Прежние ожидания отказа
/// D38 заменены; красные до задачи 3.2.
void main() {
  test('сценарий «Защищённые пути корня у ребёнка»: bypass, ребёнок general '
      'пишет в .codelab/config.yaml и копирует в \$CODELAB_HOME/agents — оба '
      'вызова критические, как у корня; запись отказана без вопроса, exec — '
      'вопрос к gate корня и не исполняется до решения', () async {
    final shell = FakeShellEnv(MemoryExecutionEnv(cwd: '/proj'), answering(''));
    final gate = FakeGate((_) => PermissionDecision.rejectOnce);
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
    expect(resultText(child, 'x1'), deniedText('exec', 'rejected by the user'));
    // Контроль: обычная запись при bypass проходит — отказы выше вызваны
    // именно защитой путей, а не режимом.
    expect(resultIsError(child, 'w2'), isFalse);
    expect(shell.commands, isEmpty);
    // Спросили только критический exec: запись в конфигурацию отказана без
    // вопроса, обычная запись при bypass — без вопроса.
    final request = gate.requests.single;
    expect(request.toolCallId, 'c1/x1');
    expect(request.allowAlwaysOffered, isFalse);
    expect(request.criticalLabel, isNotNull);
    expect(request.title, startsWith('[general: Do the work] '));
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
    // С gate у ребёнка (итерация 3) запись в конфигурацию всё равно не
    // доходит до вопроса: спросил только корень (`w0`).
    expect([for (final r in gate.requests) r.toolCallId], ['w0']);
    expect(
      resultText(rig.requestsOf('touch the config').last, 'w1'),
      contains('requires a human'),
    );
  });
}
