// Контекст команд TUI: вывод — сообщениями ядра, сессия — у контекста
// (tasks 5.3 change `add-cli-tui`; spec codelab-tui «Команды и пикеры TUI»;
// design.md, D10).

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../support/fake_agent.dart';

void main() {
  late FakeAgent agent;
  late List<TuiMsg> sent;
  late List<int> exits;
  late TuiCommandContext context;

  Future<SessionHandle> open(String id) async {
    final opening = agent.workspace.newSession(cwd: '/w');
    await agent.acceptNewSession(id);
    return opening;
  }

  setUp(() async {
    agent = FakeAgent();
    sent = [];
    exits = [];
    await agent.workspace.connect(FakeAgent.profile, projectDirectory: '/w');
    context = TuiCommandContext(
      workspace: agent.workspace,
      profile: FakeAgent.profile,
      cwd: '/w',
      send: sent.add,
      onExit: exits.add,
    )..attach(await open('s1'));
  });
  tearDown(() async {
    await context.close();
    await agent.dispose();
  });

  test('attaching a session sends its current view', () {
    expect(
      sent.whereType<SessionAttachedMsg>().last.view,
      context.session.current,
    );
    expect(context.session.id.value, 's1');
  });

  test('say is a note, clearScreen drops the notes', () {
    context
      ..say('hello \x07there')
      ..clearScreen();

    expect(sent.whereType<NoteMsg>().single.text, 'hello there');
    expect(sent.last, isA<ClearNotesMsg>());
  });

  test('pick opens a picker, thoughts change the mode', () {
    const spec = PickerSpec(
      items: [PickerItem(label: 'x', line: '/model x')],
    );
    context
      ..pick(spec)
      ..thoughts = ThoughtsMode.hidden;

    expect(sent.whereType<OpenPickerMsg>().single.spec, spec);
    expect(sent.whereType<ThoughtsMsg>().single.mode, ThoughtsMode.hidden);
  });

  test('the plan is shown as a note', () {
    context.showPlan(const [
      PlanEntryView(
        content: 'Edit',
        status: PlanEntryStatus.pending,
        priority: PlanEntryPriority.low,
      ),
    ]);

    final note = sent.whereType<NoteMsg>().single.text;
    expect(note, startsWith(planHeader));
    expect(note, contains('[ ] Edit'));
  });

  test('openSession switches the session and its views', () async {
    final second = await open('s2');
    sent.clear();

    await context.openSession(second, replay: true);

    expect(context.session, second);
    expect(sent.whereType<SessionAttachedMsg>().single.view, second.current);
    expect(agent.workspace.current.activeSessionId, second.id);
  });

  test('exit and the keys of the full-screen mode', () {
    context.exit(0);

    expect(exits, [0]);
    expect(context.keys, same(KeyBindings.tui));
  });

  // Тот же текст отказа по токену, что при старте (spec codelab-cli «Отказ
  // подключения из-за токена»).
  group('a handshake rejected because of the token', () {
    Future<TuiCommandContext> wsContext(WebSocketProfile profile) async {
      // Новый «процесс» агента: транспорт setUp уже запущен.
      agent.restartAgent();
      await agent.workspace.connect(profile, projectDirectory: '/w');
      return TuiCommandContext(
        workspace: agent.workspace,
        profile: profile,
        tokenSource: fakeTokenSource,
        cwd: '/w',
        send: sent.add,
        onExit: exits.add,
      );
    }

    String lastNote() => sent.whereType<NoteMsg>().last.text;

    test('switchProfile says the agent rejected the token', () async {
      final ws = wsProfile();
      final ctx = await wsContext(ws);
      agent.openError = handshakeRejected(401);

      await ctx.switchProfile(ws);

      expect(
        lastNote(),
        'codelab: cannot connect to ws://127.0.0.1:9: '
        'the agent rejected the token (HTTP 401).',
      );
      expect(lastNote(), isNot(contains(fakeTokenMarker)));
      for (final leak in fakeUrlLeaks) {
        expect(lastNote(), isNot(contains(leak)));
      }
    });

    test('reconnect says the agent requires a token when none was '
        'sent', () async {
      final ctx = await wsContext(wsProfile(withToken: false));
      agent.openError = handshakeRejected(403);

      await ctx.reconnect();

      expect(
        lastNote(),
        'codelab: cannot reconnect: the agent requires a token (HTTP 403).',
      );
    });

    test('other failures keep the previous text', () async {
      final ctx = await wsContext(wsProfile());
      agent.openError = handshakeRejected(500);

      await ctx.reconnect();

      expect(lastNote(), contains('Failed to connect ACP transport.'));
    });
  });
}
