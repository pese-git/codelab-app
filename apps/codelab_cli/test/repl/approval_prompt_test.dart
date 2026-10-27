// Одобрение в REPL (tasks 7.1; spec codelab-cli «Одобрение в REPL»; U-02;
// design.md change `add-codelab-cli`, D8).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/repl_harness.dart';

const _allowOnce = PermissionOption(
  optionId: PermissionOptionId('allow-once'),
  name: 'Allow once',
  kind: PermissionOptionKind.allowOnce,
);
const _allowAlways = PermissionOption(
  optionId: PermissionOptionId('allow-always'),
  name: 'Always allow',
  kind: PermissionOptionKind.allowAlways,
);
const _rejectOnce = PermissionOption(
  optionId: PermissionOptionId('reject-once'),
  name: 'Reject',
  kind: PermissionOptionKind.rejectOnce,
);
const _rejectAlways = PermissionOption(
  optionId: PermissionOptionId('reject-always'),
  name: 'Always reject',
  kind: PermissionOptionKind.rejectAlways,
);

PendingApprovalView _approval({
  List<PermissionOption> options = const [_allowOnce, _rejectOnce],
  String? command = 'dart test',
  Map<String, Object?>? rawInput = const {'command': 'dart test'},
  bool critical = false,
}) => PendingApprovalView(
  approvalId: const ApprovalRequestId('a1'),
  sessionId: const SessionId('s1'),
  risk: ApprovalRiskLevel.shell,
  command: command,
  rawInput: rawInput,
  options: options,
  focused: true,
  critical: critical,
);

void main() {
  group('ApprovalPrompt', () {
    test('the block has the title, risk, command, folder and only the '
        'offered keys', () {
      final prompt = ApprovalPrompt(
        _approval(),
        title: 'Run dart test',
        cwd: '/work',
      );

      expect(prompt.block, [
        'Permission: Run dart test (shell)',
        '  command: dart test',
        '  cwd: /work',
        '  [y] allow once  [n] reject once  [?] details  [Esc] cancel',
      ]);
    });

    test('all four kinds give four keys', () {
      final prompt = ApprovalPrompt(
        _approval(
          options: const [_allowOnce, _allowAlways, _rejectOnce, _rejectAlways],
        ),
        title: 'Run',
        cwd: '/work',
      );

      expect(
        prompt.block.last,
        '  [y] allow once  [a] allow always  [n] reject once  '
        '[N] reject always  [?] details  [Esc] cancel',
      );
    });

    test('a critical request says so in the title', () {
      final prompt = ApprovalPrompt(
        _approval(critical: true),
        title: 'Run rm -rf build',
        cwd: '/work',
      );

      expect(
        prompt.block.first,
        'Permission: Run rm -rf build (shell, critical)',
      );
    });

    test('without a command the first string of rawInput is shown, not the '
        'object', () {
      final prompt = ApprovalPrompt(
        _approval(
          command: null,
          rawInput: const {
            'path': 'lib/main.dart',
            'options': {'force': true},
          },
        ),
        title: 'Edit',
        cwd: '/work',
      );

      expect(prompt.block[1], '  command: lib/main.dart');
      expect(prompt.block.join('\n'), isNot(contains('{')));
    });

    test('keys choose the option of their kind, the first of several', () {
      final prompt = ApprovalPrompt(
        _approval(
          options: const [
            _allowOnce,
            _allowAlways,
            _rejectOnce,
            _rejectAlways,
            PermissionOption(
              optionId: PermissionOptionId('allow-once-2'),
              name: 'Allow once again',
              kind: PermissionOptionKind.allowOnce,
            ),
          ],
        ),
        title: 'Run',
        cwd: '/work',
      );

      expect(prompt.optionFor('y'), _allowOnce.optionId);
      expect(prompt.optionFor('a'), _allowAlways.optionId);
      expect(prompt.optionFor('n'), _rejectOnce.optionId);
      expect(prompt.optionFor('N'), _rejectAlways.optionId);
      expect(prompt.optionFor('x'), isNull);
    });

    test('a key of an option the agent did not offer chooses nothing', () {
      final prompt = ApprovalPrompt(_approval(), title: 'Run', cwd: '/work');

      expect(prompt.optionFor('a'), isNull);
      expect(prompt.optionFor('N'), isNull);
    });

    test('details are the whole rawInput, redacted', () {
      final prompt = ApprovalPrompt(
        _approval(rawInput: const {'command': 'curl', 'api_key': 'sk-secret'}),
        title: 'Run',
        cwd: '/work',
      );

      expect(prompt.details, contains('"command": "curl"'));
      expect(prompt.details, isNot(contains('sk-secret')));
    });
  });

  group('in the REPL', () {
    late ReplHarness repl;

    setUp(() async {
      repl = ReplHarness();
      await repl.start();
    });
    tearDown(() => repl.dispose());

    Future<JsonRpcRequest> askPermission({
      int id = 7,
      String call = 'call_1',
      List<PermissionOption> options = const [_allowOnce, _rejectOnce],
    }) async {
      repl.line('go');
      final prompt = await repl.agent.next(sessionPromptMethod);
      repl.agent.requestPermission(
        id: id,
        sessionId: 's1',
        toolCallId: call,
        options: options,
      );
      await repl.waitText('Permission: Run $call');
      return prompt;
    }

    Future<String?> optionSent(int id) async {
      final response = await repl.agent.responseTo(id);
      final outcome =
          (response.result! as Map<String, Object?>)['outcome']!
              as Map<String, Object?>;
      return outcome['optionId'] as String?;
    }

    test('y answers allow_once and the turn goes on', () async {
      final prompt = await askPermission();

      repl.type('y');

      expect(await optionSent(7), 'allow-once');
      // Настоящий агент отвечает не раньше следующего события: kit успевает
      // отметить одобрение решённым.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repl.agent
        ..chunk('s1', 'done')
        ..respond(prompt, {'stopReason': 'end_turn'});
      await repl.waitText('done');
      expect(await repl.exit(), 0);
    });

    test('n answers reject_once', () async {
      await askPermission();

      repl.type('n');

      expect(await optionSent(7), 'reject-once');
    });

    test('a key of an option not offered and Enter send nothing', () async {
      await askPermission();

      repl
        ..type('a')
        ..press(const [0x0d])
        ..type('N');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        repl.agent.transport.sentMessages.whereType<JsonRpcResponse>(),
        isEmpty,
      );
      repl.type('y');
      expect(await optionSent(7), 'allow-once');
    });

    test('? prints rawInput and asks again', () async {
      await askPermission();

      repl.type('?');

      await repl.waitText('"command": "dart test"');
      await repl.waitText('[y] allow once');
      repl.type('n');
      expect(await optionSent(7), 'reject-once');
    });

    test('Esc cancels the turn and the request is cancelled', () async {
      await askPermission();

      repl.press(const [0x1b]);

      await repl.agent.nextNotification(sessionCancelMethod);
      final response = await repl.agent.responseTo(7);
      expect((response.result! as Map<String, Object?>)['outcome'], {
        'outcome': 'cancelled',
      });
    });

    test('two requests are asked one at a time in order', () async {
      await askPermission();
      repl.agent.requestPermission(
        id: 8,
        sessionId: 's1',
        toolCallId: 'call_2',
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(repl.output, isNot(contains('Permission: Run call_2')));

      repl.type('y');
      expect(await optionSent(7), 'allow-once');
      await repl.waitText('Permission: Run call_2');

      repl.type('n');
      expect(await optionSent(8), 'reject-once');
    });

    test('typing during the question does not reach the prompt', () async {
      final prompt = await askPermission();

      repl.type('hello');
      repl.type('y');
      expect(await optionSent(7), 'allow-once');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      repl.agent.respond(prompt, {'stopReason': 'end_turn'});
      await Future<void>.delayed(const Duration(milliseconds: 20));

      repl.line('next');
      expect(promptTextOf(await repl.agent.next(sessionPromptMethod)), 'next');
    });
  });
}
