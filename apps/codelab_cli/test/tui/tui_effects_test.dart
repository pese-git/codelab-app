// Исполнение команд ядра экрана (tasks 3.1 change `add-cli-tui`; spec
// codelab-tui «Граница ядра экрана и адаптера»; design.md, D7).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:dart_tui/dart_tui.dart' as tea;
import 'package:test/test.dart';

import '../support/fake_agent.dart';
import '../support/fake_terminal.dart' show eventually;

final class _History implements HistoryStore {
  List<String>? saved;
  Object? error;

  @override
  Future<List<String>> load() async => const [];

  @override
  Future<void> save(List<String> entries) async {
    if (error case final error?) {
      throw error;
    }
    saved = entries;
  }
}

void main() {
  late FakeAgent agent;
  late SessionHandle handle;
  late _History history;
  late List<int> quits;
  late List<String> commands;
  late TuiEffects effects;

  setUp(() async {
    agent = FakeAgent();
    await agent.workspace.connect(FakeAgent.profile, projectDirectory: '/w');
    final opening = agent.workspace.newSession(cwd: '/w');
    await agent.acceptNewSession('s1');
    handle = await opening;
    history = _History();
    quits = [];
    commands = [];
    effects = TuiEffects(
      session: () => handle,
      history: history,
      onQuit: quits.add,
      runCommand: (line) async => commands.add(line),
    );
  });

  tearDown(() => agent.dispose());

  Future<tea.Msg?> run(TuiCmd cmd) async => effects.toDartTuiCmd([cmd])!();

  test('SubmitCmd sends the prompt through the session', () async {
    final done = run(const SubmitCmd('hi'));

    final prompt = await agent.next(sessionPromptMethod);
    expect(
      ((prompt.params! as Map)['prompt'] as List).single,
      containsPair('text', 'hi'),
    );
    agent.respond(prompt, {'stopReason': 'end_turn'});
    expect(await done, isNull);
  });

  test('CancelTurnCmd sends session/cancel', () async {
    final turn = handle.send('slow');
    await agent.next(sessionPromptMethod);

    await run(const CancelTurnCmd());

    await agent.nextNotification(sessionCancelMethod);
    turn.ignore();
  });

  test('RespondCmd answers the permission request (D9)', () async {
    final turn = handle.send('go');
    final prompt = await agent.next(sessionPromptMethod);
    agent.requestPermission(id: 7, sessionId: 's1', toolCallId: 'call_1');
    await eventually(() => handle.current.pendingApprovals.isNotEmpty);
    final approval = handle.current.pendingApprovals.single;

    expect(
      await run(
        RespondCmd(approval.approvalId, const PermissionOptionId('allow-once')),
      ),
      isNull,
    );

    final response = await agent.responseTo(7);
    expect(
      (response.result! as Map<String, Object?>)['outcome'],
      containsPair('optionId', 'allow-once'),
    );
    agent.respond(prompt, {'stopReason': 'end_turn'});
    await turn;
  });

  test('RunCommandCmd runs the command line', () async {
    await run(const RunCommandCmd('/mode plan'));

    expect(commands, ['/mode plan']);
  });

  test('SaveHistoryCmd writes the history', () async {
    await run(const SaveHistoryCmd(['a', 'b']));

    expect(history.saved, ['a', 'b']);
  });

  test('QuitCmd records the code and quits the program', () async {
    expect(await run(const QuitCmd(143)), isA<tea.QuitMsg>());
    expect(quits, [143]);
  });

  test('a failing effect comes back as a message, not an exception', () async {
    history.error = StateError('disk full');

    final msg = await run(const SaveHistoryCmd(['a']));

    expect(
      msg,
      isA<DomainMsg>().having((m) => m.msg, 'msg', isA<EffectFailedMsg>()),
    );
  });

  test('several commands become one batch', () {
    final cmd = effects.toDartTuiCmd(const [
      SaveHistoryCmd(['a']),
      SubmitCmd('a'),
    ]);

    expect(cmd!(), isA<tea.BatchMsg>());
    expect(effects.toDartTuiCmd(const []), isNull);
  });
}
