import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/config/merge.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Слияние слоёв (agent-configuration «Слои конфигурации и их порядок»;
/// `agent-core-architecture` §15.2; design.md change
/// `add-agent-configuration`, D4).
void main() {
  test('a project layer overrides the global one', () {
    final result = load([
      layer(
        withValues(baseValues(), {
          'budget': {'max_steps': 50},
        }),
      ),
      layer({
        'budget': {'max_steps': 20},
      }, kind: ConfigLayerKind.projectLocal),
    ], projectRoot: '/proj');

    expect(result.config!.budget.maxSteps, 20);
  });

  test('a flag beats a variable and the files; sources keep the layer '
      'order', () {
    final result = load([
      layer({}, kind: ConfigLayerKind.defaults, source: 'defaults'),
      layer(baseValues(), source: '/h/config.yaml'),
      layer(
        {
          'budget': {'max_steps': 30},
        },
        kind: ConfigLayerKind.projectLocal,
        source: '/p/config.local.yaml',
      ),
      layer(
        {
          'budget': {'max_steps': 40},
        },
        kind: ConfigLayerKind.environment,
        source: 'env',
      ),
      layer(
        {
          'budget': {'max_steps': 10},
        },
        kind: ConfigLayerKind.flags,
        source: 'flags',
      ),
    ], projectRoot: '/proj');

    expect(result.config!.budget.maxSteps, 10);
    expect(result.sources, [
      'defaults',
      '/h/config.yaml',
      '/p/config.local.yaml',
      'env',
      'flags',
    ]);
  });

  test('mappings merge by key, scalars and lists are replaced whole', () {
    final merged = mergeLayers([
      layer({
        'budget': {'max_steps': 5, 'max_tokens': 100},
        'permissions': {
          'deny': ['exec:a', 'exec:b'],
        },
      }),
      layer({
        'budget': {'max_steps': 7},
        'permissions': {
          'deny': ['exec:c'],
        },
      }, kind: ConfigLayerKind.projectLocal),
    ]);

    expect(merged['budget'], {'max_steps': 7, 'max_tokens': 100});
    expect((merged['permissions']! as Map)['deny'], [
      'exec:c',
    ], reason: 'a list is replaced, not appended');
  });

  test('mcp.servers merge by name: a new name is appended, the same name '
      'is replaced whole, enabled: false switches a server off', () {
    final merged = mergeLayers([
      layer({
        'mcp': {
          'servers': [
            {'name': 'github', 'type': 'http', 'url': 'https://a.test/mcp'},
            {'name': 'files', 'type': 'stdio', 'command': 'files-mcp'},
          ],
        },
      }),
      layer({
        'mcp': {
          'servers': [
            {'name': 'github', 'type': 'http', 'url': 'https://b.test/mcp'},
            {'name': 'files', 'enabled': false},
            {'name': 'extra', 'type': 'stdio', 'command': 'extra-mcp'},
          ],
        },
      }, kind: ConfigLayerKind.projectLocal),
    ]);

    final servers = (merged['mcp']! as Map)['servers']! as List;
    expect(
      [for (final s in servers) (s as Map)['name']],
      ['github', 'files', 'extra'],
    );
    expect((servers[0] as Map)['url'], 'https://b.test/mcp');
    expect(servers[1], {'name': 'files', 'enabled': false});
  });

  test(
    'tools.disabled of layers 2-4 is united; a later layer kind replaces',
    () {
      final merged = mergeLayers([
        layer({
          'tools': {
            'disabled': ['exec', 'mcp__*'],
          },
        }),
        layer({
          'tools': {
            'disabled': ['exec', 'write'],
          },
        }, kind: ConfigLayerKind.project),
        layer({
          'tools': {
            'disabled': ['edit'],
          },
        }, kind: ConfigLayerKind.projectLocal),
      ]);
      final replaced = mergeLayers([
        layer({
          'tools': {
            'disabled': ['exec'],
          },
        }),
        layer({
          'tools': {
            'disabled': ['edit'],
          },
        }, kind: ConfigLayerKind.flags),
      ]);

      expect((merged['tools']! as Map)['disabled'], [
        'exec',
        'mcp__*',
        'write',
        'edit',
      ]);
      expect((replaced['tools']! as Map)['disabled'], ['edit']);
    },
  );

  test('the input layers are not modified', () {
    final base = layer({
      'budget': {'max_steps': 5},
    });
    final merged = mergeLayers([
      base,
      layer({
        'budget': {'max_steps': 6},
      }, kind: ConfigLayerKind.projectLocal),
    ]);
    (merged['budget']! as Map)['max_steps'] = 99;

    expect(base.values['budget'], {'max_steps': 5});
  });
}
