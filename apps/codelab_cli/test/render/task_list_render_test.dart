// Список задач и тихая строка операций в REPL (задача 1.1, «CLI» change
// `add-subagents-and-tasks`; spec codelab-cli «Субагенты и список задач в
// REPL»; design.md, D27).
//
// Красные тесты: у `PlanEntryView` нет `taskId`/`ownerLabel`/`openBlockers`, а
// `TaskOpsItem` не существует (задачи 1.6, 1.6a); рендер плана и тихая строка
// — задача 1.7. Формат пункта: `#<id> [<status>] <subject>`, затем
// ` (<метка владельца>)` и ` (blocked by #<id>, …)`.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _dim = '\x1b[2m';
const _reset = '\x1b[0m';

var _revision = 0;

SessionView _view(
  List<TranscriptItem> transcript, {
  List<PlanEntryView> plan = const [],
}) => SessionView(
  revision: ++_revision,
  status: SessionStatusView.running,
  transcript: transcript,
  plan: plan,
);

void main() {
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    out = StringBuffer();
    err = StringBuffer();
  });

  TerminalRenderer renderer({OutputSurface surface = OutputSurface.ansi}) =>
      TerminalRenderer(
        surface: surface,
        out: out,
        err: err,
        thoughts: ThoughtsMode.dim,
        clock: () => DateTime(2026, 11, 12, 12),
      );

  group('plan with tasks', () {
    // #1 завершён, #2 идёт у субагента explore и по блокеру #1 уже свободен.
    const first = PlanEntryView(
      content: 'Map callers',
      status: PlanEntryStatus.completed,
      priority: PlanEntryPriority.medium,
      taskId: '1',
    );
    const second = PlanEntryView(
      content: 'Write tests',
      status: PlanEntryStatus.inProgress,
      priority: PlanEntryPriority.medium,
      taskId: '2',
      owner: 'sub_a1',
      blockedBy: ['1'],
      ownerLabel: 'explore',
    );

    test('entries with an id are printed as #id [status] subject; an owner '
        'subagent label is a suffix, a completed blocker is not marked', () {
      final r = renderer();
      r.render(_view(const [], plan: const [first, second]));

      final text = out.toString();
      expect(text, contains('#1 [completed] Map callers\n'));
      expect(text, contains('#2 [in_progress] Write tests (explore)\n'));
      expect(text, isNot(contains('blocked by')));
    });

    test('open blockers are listed after the owner label', () {
      final r = renderer();
      r.render(
        _view(
          const [],
          plan: const [
            PlanEntryView(
              content: 'Ship',
              status: PlanEntryStatus.pending,
              priority: PlanEntryPriority.medium,
              taskId: '4',
              owner: 'sub_a1',
              blockedBy: ['2', '3'],
              openBlockers: ['2', '3'],
              ownerLabel: 'review',
            ),
          ],
        ),
      );

      expect(
        out.toString(),
        contains('#4 [pending] Ship (review) (blocked by #2, #3)\n'),
      );
    });

    test('an entry without taskId is printed as before', () {
      final r = renderer();
      r.render(
        _view(
          const [],
          plan: const [
            PlanEntryView(
              content: 'Edit',
              status: PlanEntryStatus.inProgress,
              priority: PlanEntryPriority.medium,
            ),
          ],
        ),
      );

      expect(out.toString(), 'Plan:\n  [~] Edit\n');
    });

    test('text from the session passes the control-character cleanup', () {
      final r = renderer();
      r.render(
        _view(
          const [],
          plan: const [
            PlanEntryView(
              content: 'Do\x1b[31m it',
              status: PlanEntryStatus.pending,
              priority: PlanEntryPriority.medium,
              taskId: '1',
              owner: 'sub_a1',
              ownerLabel: 'ex\x1bplore',
            ),
          ],
        ),
      );

      expect(out.toString(), isNot(contains('\x1b')));
    });
  });

  group('quiet task operations line', () {
    const ops = TaskOpsItem(id: 'ops-1', added: ['1', '2', '3', '4']);

    test('on ansi it is one dim line without a status icon and a time', () {
      final r = renderer();
      r.render(_view(const [ops]));
      // Последнюю операцию может дополнить следующая, поэтому строка
      // печатается, когда за ней пришло другое или кончился ход.
      r.finishTurn();

      expect(out.toString(), '${_dim}Tasks #1–#4 added to the plan$_reset\n');
    });

    test('on plain it is the text without escape sequences', () {
      final r = renderer(surface: OutputSurface.plain);
      r.render(_view(const [ops]));
      r.finishTurn();

      expect(out.toString(), 'Tasks #1–#4 added to the plan\n');
    });

    test('it is printed once for repeated revisions', () {
      final r = renderer();
      r.render(_view(const [ops]));
      r.render(_view(const [ops]));
      r.finishTurn();

      expect('Tasks #1–#4'.allMatches(out.toString()), hasLength(1));
    });
  });
}
