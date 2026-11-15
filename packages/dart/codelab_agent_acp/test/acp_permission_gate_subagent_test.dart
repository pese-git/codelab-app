import 'dart:async';

import 'package:codelab_agent_acp/src/acp_permission_gate.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';

/// `AcpPermissionGate`: запрос потомка (задача 3.1 `[protocol]` change
/// `add-subagents-and-tasks`, итерация 3; agent-acp-server «Запрос
/// разрешения ребёнка»; design.md D8, D42 Т5, D43 п. 1).
///
/// Почему отдельный файл: файл `acp_permission_gate_test.dart` описывает
/// запросы корня и остаётся зелёным; здесь всё, что зависит от поля
/// `PermissionRequest.subagent` (`SubagentRequestRef`, D42 Т4). Пока ядро
/// его не вводит (задача 3.2), файл не компилируется, а после заглушки ядра
/// остаётся красным до `AcpPermissionGate` (задача 3.3): `_meta.codelab`
/// без `subagent`, а ожидание объявления берёт цепочку `toolCallId`.
void main() {
  late ClientChannel ch;

  setUp(() async {
    ch = await ClientChannel.open();
  });

  /// Запрос ребёнка `review` глубины 1: `toolCallId` — цепочка от вызова
  /// `agent` корня (SUB-3), `title` с префиксом (§17.3.3).
  PermissionRequest childExec({String? criticalLabel}) => PermissionRequest(
    toolCallId: 'call_1/call_1',
    tool: 'exec',
    kind: ToolKind.execute,
    tier: ToolTier.exec,
    title: '[review: Check the diff] Run git diff --stat',
    rawInput: const {'command': 'git diff --stat'},
    pattern: 'git diff --stat',
    criticalLabel: criticalLabel,
    allowAlwaysOffered: criticalLabel == null,
    subagent: const SubagentRequestRef(
      id: 'sub_p2r7t9w1',
      type: 'review',
      description: 'Check the diff',
      depth: 1,
      path: [],
      parentToolCallId: 'call_1',
    ),
  );

  Map<Object?, Object?> sentToolCall() =>
      (ch.client.requests.single.params! as Map)['toolCall']! as Map;

  void rejectOnce() =>
      ch.client.handlers['session/request_permission'] = (_) => {
        'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
      };

  // agent-acp-server «Запрос разрешения ребёнка»: смысл ключа в запросе —
  // «спрашивает потомок» (D43 п. 1); поля — по §17.3.7.
  test('toolCall._meta.codelab.subagent describes the asking child', () async {
    rejectOnce();
    final gate = AcpPermissionGate(ch.link, logger: ch.logger);

    await gate.request(childExec(), CancelToken.none);

    final toolCall = sentToolCall();
    expect(toolCall['toolCallId'], 'call_1/call_1');
    expect(toolCall['title'], '[review: Check the diff] Run git diff --stat');
    expect(toolCall['_meta'], {
      'codelab': {
        'subagent': {
          'id': 'sub_p2r7t9w1',
          'type': 'review',
          'description': 'Check the diff',
          'depth': 1,
          'path': <Object?>[],
          'parentToolCallId': 'call_1',
        },
      },
    });
  });

  // D42 Т5: `_meta.codelab` — один объект, `critical`/`label` и `subagent`
  // не затирают друг друга.
  test('critical and subagent share one _meta.codelab object', () async {
    rejectOnce();
    final gate = AcpPermissionGate(ch.link, logger: ch.logger);

    await gate.request(
      childExec(criticalLabel: 'recursive delete'),
      CancelToken.none,
    );

    final codelab = (sentToolCall()['_meta']! as Map)['codelab']! as Map;
    expect(codelab['critical'], isTrue);
    expect(codelab['label'], 'recursive delete');
    expect((codelab['subagent']! as Map)['parentToolCallId'], 'call_1');
  });

  // Запрос корня не получает ключа `subagent` (agent-acp-server «Запрос без
  // сведений о субагенте» на стороне агента: поле `null` — ключа нет).
  test('a root request has no subagent key', () async {
    rejectOnce();
    final gate = AcpPermissionGate(ch.link, logger: ch.logger);

    await gate.request(
      PermissionRequest(
        toolCallId: 'call_2',
        tool: 'exec',
        kind: ToolKind.execute,
        tier: ToolTier.exec,
        title: 'Run ls',
        rawInput: {'command': 'ls'},
        allowAlwaysOffered: true,
      ),
      CancelToken.none,
    );

    expect(sentToolCall().containsKey('_meta'), isFalse);
  });

  // D42 Т5: цепочка потомка не проецируется (SUB-12), поэтому ждать
  // `announced(chain)` значило бы ждать вечно; ждём вызов `agent` корня.
  test('a child request waits for announced(parentToolCallId), not for the '
      'chain', () async {
    rejectOnce();
    final asked = <String>[];
    final announcedRoot = Completer<void>();
    final gate = AcpPermissionGate(
      ch.link,
      logger: ch.logger,
      announced: (toolCallId) {
        asked.add(toolCallId);
        // Цепочку «никто не объявит»: ждать её нельзя.
        return toolCallId == 'call_1'
            ? announcedRoot.future
            : Completer<void>().future;
      },
    );

    final decision = gate.request(childExec(), CancelToken.none);
    await pumpEventQueue();

    expect(asked, ['call_1']);
    expect(
      ch.client.requests,
      isEmpty,
      reason: 'запрос не опережает tool_call',
    );

    announcedRoot.complete();
    expect(await decision, PermissionDecision.rejectOnce);
    expect(ch.client.requests, hasLength(1));
  });

  // Запрос корня по-прежнему ждёт собственный `toolCallId` (§13.7).
  test('a root request still waits for its own toolCallId', () async {
    rejectOnce();
    final asked = <String>[];
    final gate = AcpPermissionGate(
      ch.link,
      logger: ch.logger,
      announced: (toolCallId) async => asked.add(toolCallId),
    );

    await gate.request(
      PermissionRequest(
        toolCallId: 'call_2',
        tool: 'exec',
        kind: ToolKind.execute,
        tier: ToolTier.exec,
        title: 'Run ls',
        rawInput: {'command': 'ls'},
        allowAlwaysOffered: true,
      ),
      CancelToken.none,
    );

    expect(asked, ['call_2']);
  });
}
