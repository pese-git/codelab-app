// Одобрение ребёнка в REPL и TUI (задача 3.1 `[client]` change
// `add-subagents-and-tasks`; spec codelab-cli «Одобрение ребёнка» и строка
// исхода без строки вызова потомка; codelab-tui «Одобрение ребёнка в TUI»;
// design.md, D27 п. 4, D43 п. 2).
//
// Красные тесты: у `PendingApprovalView` нет поля `subagent`, а у
// `SubagentRequester` — типа (задача 3.4 kit) — файл не компилируется.
// Решения, которые фиксируют тесты (spec формат не задаёт, предложение
// задачи):
//  - блок начинается строкой `<путь> wants to run`, следом `  task: <description>`,
//    затем прежние строки `Permission: …` (заголовок вызова, риск, команда);
//  - у `ToolCallItem.childApprovals` корня после решения REPL печатает одну
//    строку исхода `  <путь>: <метка решения>`; строки вызова потомка
//    (`call_1/call_1`) нет (D43 п. 2).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

const _allowOnce = PermissionOption(
  optionId: PermissionOptionId('allow-once'),
  name: 'Allow once',
  kind: PermissionOptionKind.allowOnce,
);
const _rejectOnce = PermissionOption(
  optionId: PermissionOptionId('reject-once'),
  name: 'Reject',
  kind: PermissionOptionKind.rejectOnce,
);

const _review = SubagentRequester(
  id: 'sub_a1',
  type: 'review',
  description: 'Check the diff',
  depth: 1,
  parentToolCallId: 'call_1',
);

PendingApprovalView _childApproval({SubagentRequester subagent = _review}) =>
    PendingApprovalView(
      approvalId: const ApprovalRequestId('a1'),
      sessionId: const SessionId('s1'),
      risk: ApprovalRiskLevel.shell,
      command: 'git diff --stat',
      rawInput: const {'command': 'git diff --stat'},
      options: const [_allowOnce, _rejectOnce],
      focused: true,
      subagent: subagent,
    );

ToolCallItem _agentRow({List<ApprovalStateView> childApprovals = const []}) =>
    ToolCallItem(
      id: 'call-1',
      toolCallId: const ToolCallId('call_1'),
      title: 'Subagent review: Check the diff',
      details: const ToolCallView(
        kind: ToolKind.think,
        status: ToolCallStatusView.running,
        rawInput: {'type': 'review', 'description': 'Check the diff'},
        subagentCall: SubagentCallView(id: 'sub_a1', type: 'review'),
      ),
      childApprovals: childApprovals,
    );

void main() {
  group('REPL: «Одобрение ребёнка»', () {
    test('the Permission line shows the title of the child call', () {
      final child = PendingApprovalView(
        approvalId: const ApprovalRequestId('a1'),
        sessionId: const SessionId('s1'),
        risk: ApprovalRiskLevel.localWrite,
        options: const [_allowOnce, _rejectOnce],
        focused: true,
        subagent: _review,
        toolTitle: '[review: Check the diff] Write f1.txt',
      );
      final prompt = ApprovalPrompt.first(
        SessionView(
          revision: 1,
          status: SessionStatusView.running,
          transcript: [
            _agentRow(childApprovals: [child]),
          ],
          pendingApprovals: [child],
        ),
        cwd: '/work',
      )!;

      expect(
        prompt.block,
        contains(
          startsWith('Permission: [review: Check the diff] Write f1.txt'),
        ),
      );
    });

    test('the block starts with `review wants to run` and the task title; '
        'n gives reject_once of this request', () {
      final prompt = ApprovalPrompt(
        _childApproval(),
        title: 'Run git diff --stat',
        cwd: '/work',
      );

      expect(prompt.block.first, 'review wants to run');
      expect(prompt.block[1], '  task: Check the diff');
      expect(prompt.block, contains('  command: git diff --stat'));
      expect(prompt.optionFor('n'), const PermissionOptionId('reject-once'));
    });

    test('a grandchild shows the whole path', () {
      final prompt = ApprovalPrompt(
        _childApproval(
          subagent: const SubagentRequester(
            id: 'sub_b2',
            type: 'explore',
            description: 'Find usages',
            depth: 2,
            parentToolCallId: 'call_1',
            // Тип вызова корня уже разрешён проекцией kit (D43 п. 4).
            rootType: 'review',
          ),
        ),
        title: 'Run ls',
        cwd: '/work',
      );

      expect(prompt.block.first, 'review › explore wants to run');
    });

    test('a grandchild without a known root type shows `…`', () {
      final prompt = ApprovalPrompt(
        _childApproval(
          subagent: const SubagentRequester(
            id: 'sub_b2',
            type: 'explore',
            description: 'Find usages',
            depth: 2,
            parentToolCallId: 'call_1',
          ),
        ),
        title: 'Run ls',
        cwd: '/work',
      );

      expect(prompt.block.first, '… › explore wants to run');
    });

    test('a request of the root has no path line', () {
      final prompt = ApprovalPrompt(
        _childApproval().copyWith(subagent: null),
        title: 'Run dart test',
        cwd: '/work',
      );

      expect(prompt.block.first, startsWith('Permission: '));
    });

    test('after the decision one outcome line is printed, without a call '
        'line of the child', () {
      final out = StringBuffer();
      final r = TerminalRenderer(
        surface: OutputSurface.plain,
        out: out,
        err: StringBuffer(),
        clock: () => DateTime(2026, 11, 15, 12),
      );
      r.render(
        SessionView(
          revision: 1,
          status: SessionStatusView.running,
          transcript: [
            _agentRow(
              childApprovals: const [
                ResolvedApprovalView(
                  label: 'Reject',
                  outcome: ApprovalOutcomeView.rejected,
                ),
              ],
            ),
          ],
        ),
      );

      final text = out.toString();
      expect(text, contains('  review: Reject'));
      expect(text, isNot(contains('call_1/call_1')));
    });
  });

  group('TUI: «Одобрение ребёнка в TUI»', () {
    test('the approval zone has the path line, the task title and the '
        'command; the choice goes to this request', () {
      var model = TuiModel.initial(
        profile: 'default',
        size: const TerminalSize(columns: 100, rows: 30),
        cwd: '/work',
        commands: mvpReplCommands,
      );
      final t0 = DateTime.utc(2026, 11, 15, 12);
      model = reduce(
        model,
        SessionViewMsg(
          SessionView(
            revision: 1,
            status: SessionStatusView.running,
            pendingApprovals: [_childApproval()],
            transcript: [_agentRow()],
          ),
          at: t0,
        ),
      ).$1;

      final lines = [
        for (final line in render(model, TuiChrome(hints: '', now: t0)).lines)
          line.replaceAll(RegExp('\x1b\\[[0-9;]*m'), ''),
      ];
      expect(lines.any((l) => l.contains('review wants to run')), isTrue);
      expect(lines.any((l) => l.contains('Check the diff')), isTrue);
      expect(lines.any((l) => l.contains('git diff --stat')), isTrue);

      final (_, cmds) = reduce(model, KeyMsg(const TextKey('n'), at: t0));
      expect(cmds, [
        const RespondCmd(
          ApprovalRequestId('a1'),
          PermissionOptionId('reject-once'),
        ),
      ]);
    });
  });
}
