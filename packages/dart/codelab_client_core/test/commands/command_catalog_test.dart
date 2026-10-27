// Тесты каталога команд палитры (tasks 2.1 change
// `add-command-palette-agent-commands`; design D2–D4; spec acp-client-kit
// «Каталог команд палитры»).

import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:test/test.dart';

HostCommand _host(String name, {bool isAvailable = true}) => HostCommand(
  id: name,
  name: name,
  label: 'Host $name',
  description: 'Host command $name.',
  isAvailable: isAvailable,
);

AgentCommandView _agent(String name, {String description = 'Agent.'}) =>
    AgentCommandView(name: name, description: description);

/// Источник и имя команды — короткая форма для сравнения списков.
List<String> _names(List<CatalogCommand> commands) => [
  for (final command in commands)
    switch (command) {
      HostCatalogCommand(:final command) => 'host:${command.name}',
      AgentCatalogCommand(:final command) => 'agent:${command.name}',
    },
];

void main() {
  group('commands', () {
    test('host commands in host order, then agent commands in agent '
        'order', () {
      final catalog = CommandCatalog(
        host: [_host('new'), _host('logs')],
        agent: [_agent('review'), _agent('compact')],
      );

      expect(_names(catalog.commands), [
        'host:new',
        'host:logs',
        'agent:review',
        'agent:compact',
      ]);
    });

    test('an unavailable host command gives way to the agent command of '
        'the same name; an available one stays next to it', () {
      final catalog = CommandCatalog(
        host: [_host('new'), _host('compact', isAvailable: false)],
        agent: [_agent('compact'), _agent('new')],
      );

      expect(_names(catalog.commands), [
        'host:new',
        'agent:compact',
        'agent:new',
      ]);
    });

    test('names are compared case-sensitively, as the agent sends them', () {
      final catalog = CommandCatalog(
        host: [_host('compact', isAvailable: false)],
        agent: [_agent('Compact')],
      );

      expect(_names(catalog.commands), ['host:compact', 'agent:Compact']);
    });

    test('a repeated agent name is one command, the first one', () {
      final catalog = CommandCatalog(
        host: const [],
        agent: [
          _agent('plan', description: 'First.'),
          _agent('plan', description: 'Second.'),
        ],
      );

      expect(catalog.commands, [
        CatalogCommand.agent(_agent('plan', description: 'First.')),
      ]);
    });

    test('the stub comes back once the agent no longer declares the '
        'name', () {
      final host = [_host('compact', isAvailable: false)];

      final withAgent = CommandCatalog(host: host, agent: [_agent('compact')]);
      final without = CommandCatalog(host: host, agent: const []);

      expect(_names(withAgent.commands), ['agent:compact']);
      expect(_names(without.commands), ['host:compact']);
    });
  });

  group('search', () {
    final catalog = CommandCatalog(
      host: [_host('new'), _host('logs')],
      agent: [
        _agent('review', description: 'Review the plan'),
        _agent('plan'),
        _agent('compact', description: 'Compact the conversation'),
      ],
    );

    test('an empty query, with or without the slash, is every command', () {
      expect(catalog.search(''), catalog.commands);
      expect(catalog.search(' / '), catalog.commands);
    });

    test('a name prefix ranks above a description match', () {
      expect(_names(catalog.search('pl')), ['agent:plan', 'agent:review']);
    });

    test('the leading slash and the case are ignored', () {
      expect(_names(catalog.search('/PL')), ['agent:plan', 'agent:review']);
    });

    test('a subsequence of the name matches', () {
      expect(_names(catalog.search('/cpt')), ['agent:compact']);
    });

    test('rules rank prefix, substring, subsequence, then label or '
        'description; within a rule — catalog order', () {
      final ranked = CommandCatalog(
        host: const [],
        agent: [
          _agent('review', description: 'Review code'),
          _agent('clone'),
          _agent('deco'),
          _agent('compact'),
        ],
      );

      expect(_names(ranked.search('co')), [
        'agent:compact',
        'agent:deco',
        'agent:clone',
        'agent:review',
      ]);
    });

    test('a host command matches by its label', () {
      expect(_names(catalog.search('host lo')), ['host:logs']);
    });

    test('nothing matches', () {
      expect(catalog.search('zzz'), isEmpty);
    });
  });
}
