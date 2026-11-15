import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/subagents/subagent_permission_gate.dart';
import 'package:test/test.dart';

import 'subagent_rig.dart' show pumpUntil;

/// Отмена ждущего в очереди запроса не пускает следующего к gate параллельно
/// с открытым вопросом (ревью итерации 3, MAJOR; design.md change
/// `add-subagents-and-tasks`, D8, D42 Т3; PERM-7).
///
/// Очередь проверяется напрямую: отмена одного потомка — это отмена токена
/// его запроса, остальные запросы дерева живы.
void main() {
  PermissionRequest req(String id) => PermissionRequest(
    toolCallId: id,
    tool: 'write',
    kind: ToolKind.edit,
    tier: ToolTier.write,
    title: id,
    rawInput: const {},
  );

  test('отмена среднего из трёх: у gate один открытый запрос, третий идёт '
      'после ответа первому (D8)', () async {
    final gate = _HoldingGate();
    final queue = SubagentQuestionQueue(gate);
    final a = CancelTokenSource(), b = CancelTokenSource();
    final c = CancelTokenSource();
    final first = queue.request(req('a'), a.token);
    final second = queue.request(req('b'), b.token);
    final third = queue.request(req('c'), c.token);
    await pumpUntil(() => gate.requests.isNotEmpty, reason: 'a not sent');

    b.cancel(const UserCancel());
    expect(await second, PermissionDecision.cancelled);
    await pumpUntil(() => queue.pending == 2, reason: 'b not removed');

    expect(gate.requests.map((r) => r.toolCallId), ['a']);
    gate.answer(0, PermissionDecision.allowOnce);
    expect(await first, PermissionDecision.allowOnce);
    await pumpUntil(() => gate.requests.length == 2, reason: 'c not sent');
    expect(gate.requests.map((r) => r.toolCallId), ['a', 'c']);
    gate.answer(1, PermissionDecision.allowOnce);
    expect(await third, PermissionDecision.allowOnce);
  });

  test('отмена единственного ждущего не освобождает очередь: новый вопрос '
      'ждёт ответа первому', () async {
    final gate = _HoldingGate();
    final queue = SubagentQuestionQueue(gate);
    final a = CancelTokenSource(), b = CancelTokenSource();
    final c = CancelTokenSource();
    final first = queue.request(req('a'), a.token);
    final second = queue.request(req('b'), b.token);
    await pumpUntil(() => gate.requests.isNotEmpty, reason: 'a not sent');
    b.cancel(const UserCancel());
    expect(await second, PermissionDecision.cancelled);
    await pumpUntil(() => queue.pending == 1, reason: 'b not removed');

    final third = queue.request(req('c'), c.token);
    await pumpUntil(() => queue.pending == 2, reason: 'c not queued');
    expect(gate.requests.map((r) => r.toolCallId), ['a']);

    gate.answer(0, PermissionDecision.allowOnce);
    await first;
    await pumpUntil(() => gate.requests.length == 2, reason: 'c not sent');
    gate.answer(1, PermissionDecision.allowOnce);
    await third;
  });

  // PERM-7: gate корня может не уважать отмену (клиент не снимает диалог, пока
  // пользователь не ответит). Очередь обязана сама вернуть `cancelled` и
  // передать право следующему, не дожидаясь gate; иначе отмена потомка
  // зависает на чужом диалоге. Ловит снятие `raceCancel` вокруг `root.request`.
  test('gate корня игнорирует отмену: отменённый получает cancelled сразу, '
      'право передаётся ждущему (PERM-7)', () async {
    final gate = _HoldingGate();
    final queue = SubagentQuestionQueue(gate);
    final a = CancelTokenSource(), b = CancelTokenSource();
    final first = queue.request(req('a'), a.token);
    final second = queue.request(req('b'), b.token);
    await pumpUntil(() => gate.requests.isNotEmpty, reason: 'a not sent');

    a.cancel(const UserCancel());
    // Gate ничего не отвечал: результат приходит только от самой очереди.
    expect(await first, PermissionDecision.cancelled);

    await pumpUntil(() => gate.requests.length == 2, reason: 'b not sent');
    expect(gate.requests.map((r) => r.toolCallId), ['a', 'b']);
    gate.answer(1, PermissionDecision.allowOnce);
    expect(await second, PermissionDecision.allowOnce);
    gate.answer(0, PermissionDecision.allowOnce);
  });
}

final class _HoldingGate implements PermissionGate {
  final requests = <PermissionRequest>[];
  final _answers = <Completer<PermissionDecision>>[];

  @override
  Future<PermissionDecision> request(
    PermissionRequest req,
    CancelToken cancel,
  ) {
    requests.add(req);
    final completer = Completer<PermissionDecision>();
    _answers.add(completer);
    return completer.future;
  }

  void answer(int index, PermissionDecision decision) =>
      _answers[index].complete(decision);
}
