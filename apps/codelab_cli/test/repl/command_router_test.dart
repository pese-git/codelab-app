// Маршрутизатор slash-команд и Tab-дополнение (tasks 7.3; spec codelab-cli
// «Slash-меню и клиентские команды»; U-03; design.md change
// `add-codelab-cli`, D7).

import 'package:codelab_cli/codelab_cli.dart';
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

final class _Command implements ReplCommand {
  const _Command(this.name, [this.description = 'client command']);

  @override
  final String name;

  @override
  final String description;

  @override
  String get usage => '/$name';

  @override
  Future<void> run(ReplContext context, List<String> args) async {}
}

const _agent = [
  AgentCommandView(name: 'compact', description: 'Compact the conversation'),
  AgentCommandView(name: 'plan', description: 'Create a plan', hint: 'what'),
];

void main() {
  final router = CommandRouter(const [
    _Command('help'),
    _Command('plan', 'Show the plan'),
    _Command('profile'),
    _Command('queue'),
    _Command('quit'),
  ]);

  CommandRoute route(String line) => router.route(line, agentCommands: _agent);

  group('route', () {
    test('a line without a slash is a prompt', () {
      expect(route('hello /plan'), const PromptRoute('hello /plan'));
    });

    test('a client command wins over the agent command of the same '
        'name', () {
      final result = route('/plan') as ClientCommandRoute;

      expect(result.command.name, 'plan');
      expect(result.args, isEmpty);
    });

    test('arguments are split by spaces', () {
      final result = route('/queue  drop 2') as ClientCommandRoute;

      expect(result.command.name, 'queue');
      expect(result.args, ['drop', '2']);
    });

    test('/agent:<name> sends the agent command as a prompt', () {
      expect(
        route('/agent:plan fix tests'),
        const AgentPromptRoute('/plan fix tests'),
      );
    });

    test('a name only the agent knows is a prompt as is', () {
      expect(route('/compact now'), const AgentPromptRoute('/compact now'));
    });

    test('an unknown command is reported without a request', () {
      expect(route('/nope x'), const UnknownCommandRoute('nope'));
      expect(route('/agent:nope'), const UnknownCommandRoute('agent:nope'));
    });

    test('a new agent catalog changes the routing at once', () {
      expect(route('/review'), const UnknownCommandRoute('review'));

      expect(
        router.route(
          '/review',
          agentCommands: const [
            AgentCommandView(name: 'review', description: 'Review'),
          ],
        ),
        const AgentPromptRoute('/review'),
      );
    });
  });

  group('complete', () {
    Completion complete(String line) =>
        router.complete(line, agentCommands: _agent);

    test('one candidate is put into the line', () {
      expect(complete('/he').replacement, '/help ');
      expect(complete('/com').replacement, '/compact ');
    });

    test('several candidates are listed, agent ones marked', () {
      final result = complete('/');

      expect(result.replacement, isNull);
      final labels = [
        for (final c in result.candidates) (c.label, c.fromAgent),
      ];
      expect(
        labels,
        containsAll([
          ('/help', false),
          ('/plan', false),
          ('/compact', true),
          ('/agent:plan', true),
        ]),
      );
    });

    test('the common prefix of several candidates is put into the line', () {
      final result = complete('/q');

      expect(result.replacement, '/qu');
      expect(result.candidates.map((c) => c.label), ['/queue', '/quit']);
    });

    test('without a longer common prefix the line stays', () {
      final result = complete('/p');

      expect(result.replacement, isNull);
      expect(result.candidates.map((c) => c.label), [
        '/plan',
        '/profile',
        '/agent:plan',
      ]);
    });

    test('a line with arguments or without a slash does not complete', () {
      expect(complete('/plan x').candidates, isEmpty);
      expect(complete('plan').candidates, isEmpty);
    });
  });
}
