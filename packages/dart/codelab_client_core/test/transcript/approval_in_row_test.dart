// Одобрение в элементе вызова транскрипта (spec acp-client-kit, требование
// «Одобрение в элементе вызова транскрипта»; change `fix-approval-focus`,
// D13, задача 3.3).
//
// Почему: агент вправе спросить разрешение на тот же `toolCallId` повторно,
// а проекция брала первое одобрение вызова, даже решённое, — ожидающий
// второй запрос не был виден в строке вызова. Правило D13: самое раннее
// ожидающее, иначе последнее по порядку прихода.

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_client_core/src/transcript/transcript_projector.dart';
import 'package:test/test.dart';

const _sessionId = SessionId('s-1');
const _turnId = PromptTurnId('turn-1');
const _c1 = ToolCallId('c1');
const _c2 = ToolCallId('c2');
const _allow = PermissionOptionId('allow');
const _reject = PermissionOptionId('reject');
const _options = [
  PermissionOption(
    optionId: _allow,
    name: 'Allow once',
    kind: PermissionOptionKind.allowOnce,
  ),
  PermissionOption(
    optionId: _reject,
    name: 'Reject once',
    kind: PermissionOptionKind.rejectOnce,
  ),
];

ApprovalRequest _approval(
  String id,
  ToolCallId call, {
  ApprovalStatus status = ApprovalStatus.pending,
  PermissionOptionId? selected,
  DateTime? requestedAt,
}) => ApprovalRequest(
  id: ApprovalRequestId(id),
  sessionId: _sessionId,
  turnId: _turnId,
  toolCall: ToolCallRecord(id: call, title: 'Run ${call.value}'),
  options: _options,
  status: status,
  selectedOptionId: selected,
  requestedAt: requestedAt,
);

/// Проекция хода с одобрениями в порядке прихода [approvals]; [announced] —
/// вызовы, объявленные кадром `tool_call`.
List<TranscriptItem> _project(
  List<ApprovalRequest> approvals, {
  Set<ToolCallId> announced = const {},
}) {
  final turn = PromptTurn(
    id: _turnId,
    sessionId: _sessionId,
    prompt: const [ContentBlock.text(text: 'go')],
    status: PromptTurnStatus.running,
    toolCalls: {for (final a in approvals) a.toolCall.id: a.toolCall},
    approvals: {for (final a in approvals) a.id: a},
    updates: [
      for (final id in announced)
        SessionUpdate.toolCall(
          toolCall: ToolCall(toolCallId: id, title: 'Run ${id.value}'),
        ),
    ],
  );
  final projector = TranscriptProjector()
    ..apply(AcpSession(id: _sessionId, cwd: '/work', turns: [turn]));
  return projector.items;
}

ToolCallItem _row(List<TranscriptItem> items, ToolCallId call) =>
    items.whereType<ToolCallItem>().singleWhere((i) => i.toolCallId == call);

void main() {
  group('Одобрение в элементе вызова', () {
    test('повторный запрос после ответа: в строке — ожидающий второй', () {
      final items = _project(
        [
          _approval(
            'p1',
            _c1,
            status: ApprovalStatus.selected,
            selected: _allow,
          ),
          _approval('p2', _c1),
        ],
        announced: {_c1},
      );

      final approval = _row(items, _c1).approval;
      expect(approval, isA<PendingApprovalView>());
      final pending = approval! as PendingApprovalView;
      expect(pending.approvalId, const ApprovalRequestId('p2'));
      expect(pending.focused, isTrue);
    });

    test('после ответа на повторный: в строке — исход второго', () {
      final items = _project(
        [
          _approval(
            'p1',
            _c1,
            status: ApprovalStatus.selected,
            selected: _allow,
          ),
          _approval(
            'p2',
            _c1,
            status: ApprovalStatus.selected,
            selected: _reject,
          ),
        ],
        announced: {_c1},
      );

      final approval = _row(items, _c1).approval;
      expect(approval, isA<ResolvedApprovalView>());
      expect(
        (approval! as ResolvedApprovalView).outcome,
        ApprovalOutcomeView.rejected,
      );
    });

    test('повторный запрос вызова без tool_call: один элемент, ожидающий', () {
      final items = _project([
        _approval('p1', _c2, status: ApprovalStatus.selected, selected: _allow),
        _approval('p2', _c2),
      ]);

      expect(
        items.whereType<ToolCallItem>().where((i) => i.toolCallId == _c2),
        hasLength(1),
      );
      final approval = _row(items, _c2).approval;
      expect(approval, isA<PendingApprovalView>());
      expect(
        (approval! as PendingApprovalView).approvalId,
        const ApprovalRequestId('p2'),
      );
    });

    test(
      'повторный запрос без tool_call после ответа на оба: исход второго',
      () {
        final items = _project([
          _approval(
            'p1',
            _c2,
            status: ApprovalStatus.selected,
            selected: _allow,
          ),
          _approval(
            'p2',
            _c2,
            status: ApprovalStatus.selected,
            selected: _reject,
          ),
        ]);

        final approval = _row(items, _c2).approval;
        expect(approval, isA<ResolvedApprovalView>());
        expect(
          (approval! as ResolvedApprovalView).outcome,
          ApprovalOutcomeView.rejected,
        );
      },
    );

    group('два ожидающих запроса одного вызова', () {
      final early = DateTime.utc(2026, 11, 20, 10);
      final late = DateTime.utc(2026, 11, 20, 11);

      test('в строке — самое раннее по requestedAt, с focused', () {
        // `p2` пришёл первым по порядку карты, но запрошен позже: выбор идёт
        // по `requestedAt`, как у `_earliestPendingApprovalId`.
        final items = _project(
          [
            _approval('p2', _c1, requestedAt: late),
            _approval('p1', _c1, requestedAt: early),
          ],
          announced: {_c1},
        );

        final pending = _row(items, _c1).approval! as PendingApprovalView;
        expect(pending.approvalId, const ApprovalRequestId('p1'));
        expect(pending.focused, isTrue);
      });

      test(
        'часть запросов без requestedAt: строка и focused — один запрос',
        () {
          // Порядок D13 транзитивен: запросы со временем раньше запросов без
          // него, поэтому A(t2), B(null), C(t1) дают C и в строке, и в focused.
          final items = _project(
            [
              _approval('a', _c1, requestedAt: late),
              _approval('b', _c1),
              _approval('c', _c1, requestedAt: early),
            ],
            announced: {_c1},
          );

          final pending = _row(items, _c1).approval! as PendingApprovalView;
          expect(pending.approvalId, const ApprovalRequestId('c'));
          expect(pending.focused, isTrue);
        },
      );

      test('после ответа на p1 в строке — p2', () {
        final items = _project(
          [
            _approval(
              'p1',
              _c1,
              status: ApprovalStatus.selected,
              selected: _allow,
              requestedAt: early,
            ),
            _approval('p2', _c1, requestedAt: late),
          ],
          announced: {_c1},
        );

        final pending = _row(items, _c1).approval! as PendingApprovalView;
        expect(pending.approvalId, const ApprovalRequestId('p2'));
        expect(pending.focused, isTrue);
      });
    });

    group('один запрос — без изменений', () {
      test('ожидающий остаётся ожидающим', () {
        final items = _project([_approval('p1', _c1)], announced: {_c1});

        final pending = _row(items, _c1).approval! as PendingApprovalView;
        expect(pending.approvalId, const ApprovalRequestId('p1'));
        expect(pending.focused, isTrue);
      });

      test('после ответа — исход', () {
        final items = _project(
          [
            _approval(
              'p1',
              _c1,
              status: ApprovalStatus.selected,
              selected: _allow,
            ),
          ],
          announced: {_c1},
        );

        final approval = _row(items, _c1).approval! as ResolvedApprovalView;
        expect(approval.outcome, ApprovalOutcomeView.allowed);
      });
    });
  });
}
