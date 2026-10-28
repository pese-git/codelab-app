// Сужение `ReplContext`: `thoughts`, `showPlan` и `pick` вместо рендера
// (tasks 5.1 change `add-cli-tui`; spec codelab-cli «Slash-меню и
// клиентские команды»; design.md change `add-cli-tui`, D10).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

import '../../support/fake_agent.dart';

const _model = {
  'type': 'select',
  'id': 'model',
  'name': 'Model',
  'category': 'model',
  'currentValue': 'b',
  'options': [
    {'value': 'a', 'name': 'Model A'},
    {'value': 'b', 'name': 'Model B'},
  ],
};

/// Контекст команд без терминала: записывает, что команда попросила.
final class _Context implements ReplContext {
  _Context(this.session, this.workspace);

  @override
  final SessionHandle session;

  @override
  final ClientWorkspace workspace;

  final said = <String>[];
  final picked = <PickerSpec>[];
  final plans = <List<PlanEntryView>>[];
  ThoughtsMode? shownThoughts;

  @override
  String get cwd => '/w';

  @override
  List<SessionSummaryView> listedSessions = const [];

  @override
  void say(String text) => said.add(text);

  @override
  void pick(PickerSpec spec) => picked.add(spec);

  @override
  void showPlan(List<PlanEntryView> plan) => plans.add(plan);

  @override
  set thoughts(ThoughtsMode mode) => shownThoughts = mode;

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ReplCommand _command(String name) =>
    mvpReplCommands.singleWhere((c) => c.name == name);

void main() {
  late FakeAgent agent;
  late _Context context;

  setUp(() async {
    agent = FakeAgent();
    await agent.workspace.connect(FakeAgent.profile, projectDirectory: '/w');
    final opening = agent.workspace.newSession(cwd: '/w');
    await agent.acceptNewSession('s1', configOptions: [_model]);
    context = _Context(await opening, agent.workspace);
  });
  tearDown(() => agent.dispose());

  test('/model without a value asks to pick, the current one marked', () async {
    await _command('model').run(context, const []);

    final spec = context.picked.single;
    expect(spec.title, 'Model (model):');
    expect([for (final i in spec.items) i.label], ['a  Model A', 'b  Model B']);
    expect([for (final i in spec.items) i.line], ['/model a', '/model b']);
    expect(spec.current, 1);
    expect(spec.action, PickerAction.run);
  });

  test('/config <id> picks a value of that option', () async {
    await _command('config').run(context, const ['model']);

    expect(
      [for (final i in context.picked.single.items) i.line],
      ['/config model a', '/config model b'],
    );
  });

  test('/thoughts sets the mode through the context', () async {
    await _command('thoughts').run(context, const ['collapsed']);

    expect(context.shownThoughts, ThoughtsMode.collapsed);
    expect(context.said, ['thoughts: collapsed']);
  });

  test('/plan without a plan says so and shows nothing', () async {
    await _command('plan').run(context, const []);

    expect(context.plans, isEmpty);
    expect(context.said, ['No plan yet.']);
  });
}
