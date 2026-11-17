import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show ClientCapabilities, FileSystemCapabilities;
import 'package:codelab_agent_acp/src/acp_permission_gate.dart';
import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'support/client_channel.dart';

/// `AcpPermissionGate`: запрос потомка (задача 3.1 `[protocol]` change
/// `add-subagents-and-tasks`, итерация 3; agent-acp-server «Запрос
/// разрешения ребёнка»; design.md D8, D42 Т5, D43 п. 1).
///
/// Почему отдельный файл: файл `acp_permission_gate_test.dart` описывает
/// запросы корня; здесь всё, что зависит от поля
/// `PermissionRequest.subagent` (`SubagentRequestRef`, D42 Т4): `_meta.codelab`
/// запроса потомка несёт `subagent`, а ожидание объявления берёт цепочку
/// `toolCallId`.
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

  // D42 Т5: клиенту без `subagentToolCalls` цепочка потомка не проецируется
  // (SUB-12), поэтому ждать `announced(chain)` значило бы ждать вечно; ждём
  // вызов `agent` корня. Клиенту с согласием — цепочку (группа ниже, 5.1).
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

  // Ревью безопасности (LOW): отмена в окне ожидания объявления не оставляет
  // висящего ожидания и не отправляет запрос на провод.
  test(
    'cancel while waiting for announced: cancelled, nothing on the wire',
    () async {
      final cancel = CancelTokenSource();
      final never = Completer<void>();
      final gate = AcpPermissionGate(
        ch.link,
        logger: ch.logger,
        announced: (_) => never.future,
      );

      final decision = gate.request(childExec(), cancel.token);
      await pumpEventQueue();
      cancel.cancel();

      expect(await decision, PermissionDecision.cancelled);
      await pumpEventQueue();
      expect(ch.client.requests, isEmpty);
    },
  );

  // D45 Т3, agent-acp-server «Запрос разрешения внука»: `parentToolCallId`
  // корня приходит отдельным значением, а не разбором цепочки. Id вызова
  // провайдера может содержать `/` (`call/1`): разбор по первому сегменту дал
  // бы `call`, и gate ждал бы объявления несуществующего вызова.
  test('a grandchild request waits for the root call id that contains a '
      'slash', () async {
    rejectOnce();
    final asked = <String>[];
    final announcedRoot = Completer<void>();
    final gate = AcpPermissionGate(
      ch.link,
      logger: ch.logger,
      announced: (toolCallId) {
        asked.add(toolCallId);
        return toolCallId == 'call/1'
            ? announcedRoot.future
            : Completer<void>().future;
      },
    );

    final decision = gate.request(
      PermissionRequest(
        toolCallId: 'call/1/call_2/call_3',
        tool: 'exec',
        kind: ToolKind.execute,
        tier: ToolTier.exec,
        title: '[review: Check the diff] Run git diff --stat',
        rawInput: const {'command': 'git diff --stat'},
        allowAlwaysOffered: true,
        subagent: const SubagentRequestRef(
          id: 'sub_g1',
          type: 'review',
          description: 'Check the diff',
          depth: 2,
          path: ['sub_c1'],
          parentToolCallId: 'call/1',
        ),
      ),
      CancelToken.none,
    );
    await pumpEventQueue();

    expect(asked, ['call/1']);
    expect(
      ch.client.requests,
      isEmpty,
      reason: 'запрос не опережает tool_call',
    );

    announcedRoot.complete();
    expect(await decision, PermissionDecision.rejectOnce);
    final toolCall = sentToolCall();
    expect(toolCall['toolCallId'], 'call/1/call_2/call_3');
    final subagent =
        ((toolCall['_meta']! as Map)['codelab']! as Map)['subagent'] as Map;
    expect(subagent['depth'], 2);
    expect(subagent['path'], ['sub_c1']);
    expect(subagent['parentToolCallId'], 'call/1');
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

  // Итерация 5 (задача 5.1; agent-acp-server «Запрос разрешения в строке
  // своего вызова»; D42 Т5, D47 Т3): клиенту с согласием `subagentToolCalls`
  // цепочка потомка проецируется `tool_call`, поэтому запрос ждёт
  // объявления самой цепочки, а не вызова `agent` корня, и встаёт в строку
  // своего вызова. Согласие читается из `ClientLink.capabilities` в момент
  // запроса. Без согласия gate ждёт вызов `agent` корня.
  group('with the subagentToolCalls consent', () {
    Future<ClientChannel> consenting(Object? version) => ClientChannel.open(
      capabilities: ClientCapabilities(
        fs: const FileSystemCapabilities(
          readTextFile: true,
          writeTextFile: true,
        ),
        terminal: true,
        meta: {
          'codelab': {
            'subagentToolCalls': {'version': version},
          },
        },
      ),
    );

    test('a child request waits for announced(chain)', () async {
      final consented = await consenting(1);
      consented.client.handlers['session/request_permission'] = (_) => {
        'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
      };
      final asked = <String>[];
      final announcedChain = Completer<void>();
      final gate = AcpPermissionGate(
        consented.link,
        logger: consented.logger,
        announced: (toolCallId) {
          asked.add(toolCallId);
          return toolCallId == 'call_1/call_1'
              ? announcedChain.future
              : Completer<void>().future;
        },
      );

      final decision = gate.request(childExec(), CancelToken.none);
      await pumpEventQueue();

      expect(asked, ['call_1/call_1']);
      expect(
        consented.client.requests,
        isEmpty,
        reason: 'запрос не опережает tool_call своего вызова',
      );

      announcedChain.complete();
      expect(await decision, PermissionDecision.rejectOnce);
      expect(
        (consented.client.requests.single.params! as Map)['toolCall'],
        containsPair('toolCallId', 'call_1/call_1'),
      );
    });

    // Внук: ждём всю цепочку из трёх сегментов, id с `/` не разбирается.
    test('a grandchild request waits for its whole chain', () async {
      final consented = await consenting(1);
      consented.client.handlers['session/request_permission'] = (_) => {
        'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
      };
      final asked = <String>[];
      final gate = AcpPermissionGate(
        consented.link,
        logger: consented.logger,
        announced: (toolCallId) async => asked.add(toolCallId),
      );

      await gate.request(
        PermissionRequest(
          toolCallId: 'call/1/call_2/call_3',
          tool: 'exec',
          kind: ToolKind.execute,
          tier: ToolTier.exec,
          title: '[review: Check the diff] Run git diff --stat',
          rawInput: const {'command': 'git diff --stat'},
          allowAlwaysOffered: true,
          subagent: const SubagentRequestRef(
            id: 'sub_g1',
            type: 'review',
            description: 'Check the diff',
            depth: 2,
            path: ['sub_c1'],
            parentToolCallId: 'call/1',
          ),
        ),
        CancelToken.none,
      );

      expect(asked, ['call/1/call_2/call_3']);
    });

    // Согласие — целое `version: 1` (D9): другое значение — согласия нет,
    // запрос ждёт вызов `agent` корня, как раньше.
    test('a version other than the integer 1 is no consent', () async {
      for (final version in <Object?>[2, '1', 1.5, null]) {
        final other = await consenting(version);
        other.client.handlers['session/request_permission'] = (_) => {
          'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
        };
        final asked = <String>[];
        final gate = AcpPermissionGate(
          other.link,
          logger: other.logger,
          announced: (toolCallId) async => asked.add(toolCallId),
        );

        await gate.request(childExec(), CancelToken.none);

        expect(asked, ['call_1'], reason: 'version: $version');
      }
    });

    // D47 Т3: после переподключения действует объявление нового соединения —
    // `ClientLink.capabilities` меняется, gate читает его при запросе, а не
    // при создании.
    test('the consent is read from the link at the moment of the '
        'request', () async {
      final plain = await ClientChannel.open();
      plain.client.handlers['session/request_permission'] = (_) => {
        'outcome': {'outcome': 'selected', 'optionId': 'reject_once'},
      };
      final asked = <String>[];
      final gate = AcpPermissionGate(
        plain.link,
        logger: plain.logger,
        announced: (toolCallId) async => asked.add(toolCallId),
      );
      plain.link.capabilities = ClientCapabilities(
        terminal: true,
        meta: {
          'codelab': {
            'subagentToolCalls': {'version': 1},
          },
        },
      );

      await gate.request(childExec(), CancelToken.none);

      expect(asked, ['call_1/call_1']);
    });
  });
}
