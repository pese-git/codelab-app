import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// `ConfigLoadResult.values` — плоская карта листьев итогового дерева — и
/// закреплённый список доверия `pinnedTrustedProjects` (design.md change
/// `add-config-writer-and-reload`, D8, «ConfigLoadResult.values и прежние
/// HostSettings», «Пересборка снимка с отложенными ключами»; agent-runtime
/// «Живая перезагрузка конфигурации»).
void main() {
  group('values', () {
    test('are the leaves of the merged tree: maps are descended, a list is '
        'one leaf, the later layer wins', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'budget': {'max_steps': 10},
            'permissions': {
              'deny': ['exec:rm *'],
              'tools': {'exec': 'ask'},
            },
          }),
        ),
        layer({
          'budget': {'max_steps': 20},
        }, kind: ConfigLayerKind.extra),
      ]);

      expect(result.issues, isEmpty);
      expect(result.values['budget.max_steps'], 20);
      expect(result.values['permissions.deny'], ['exec:rm *']);
      expect(result.values['permissions.tools.exec'], 'ask');
      expect(result.values['agent.default_model'], 'p/m');
      expect(result.values['providers.p.base_url'], 'https://llm.test/v1');
      expect(result.values, isNot(contains('permissions')));
      expect(result.values, isNot(contains('budget')));
    });

    test('a segment with a dot or a colon is quoted as in KeyPath', () {
      final result = load([
        layer({
          'providers': {
            'p': {
              'kind': 'openai-compatible',
              'base_url': 'https://llm.test/v1',
              'models': {
                'llama3.1:70b': {'context_window': 8000},
              },
            },
          },
          'agent': {'default_model': 'p/llama3.1:70b'},
        }),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(
        result.values['providers.p.models."llama3.1:70b".context_window'],
        8000,
      );
    });

    test('an mcp server is one entry by name with the raw element, '
        'placeholders unexpanded', () {
      final result = load(
        [
          layer(
            withValues(baseValues(), {
              'mcp': {
                'servers': [
                  {
                    'name': 'gh',
                    'type': 'http',
                    'url': 'https://gh.test/mcp',
                    'headers': {'Authorization': r'Bearer ${GH_TOKEN}'},
                  },
                ],
              },
            }),
          ),
        ],
        environment: {'GH_TOKEN': 'ghp-fake-value'},
      );

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.values, contains('mcp.servers[gh]'));
      final element = result.values['mcp.servers[gh]']! as Map<String, Object?>;
      expect(element['url'], 'https://gh.test/mcp');
      expect(
        (element['headers']! as Map<String, Object?>)['Authorization'],
        r'Bearer ${GH_TOKEN}',
      );
      expect(result.values.toString(), isNot(contains('ghp-fake-value')));
    });

    test('a disabled server is in values with enabled: false, like in the '
        'config (D10, change `add-config-writer-and-reload`); an element that '
        'cannot be launched is in neither', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'mcp': {
              'servers': [
                {
                  'name': 'off',
                  'type': 'stdio',
                  'command': 'x',
                  'enabled': false,
                },
                {'name': 'on', 'type': 'stdio', 'command': 'x'},
                {'name': 'bare', 'enabled': false},
              ],
            },
          }),
        ),
      ]);

      expect(result.values.keys.where((k) => k.startsWith('mcp.servers')), [
        'mcp.servers[off]',
        'mcp.servers[on]',
      ]);
      expect(result.values['mcp.servers[off]'], containsPair('enabled', false));
      expect(result.config!.mcpServers.map((s) => s.name), ['off', 'on']);
    });

    test('keys dropped by the trust rules of an untrusted project are not in '
        'values, and trusted_projects shows the file', () {
      final result = load([
        layer({
          ...baseValues(),
          'trusted_projects': ['/other'],
        }),
        layer({
          'providers': {
            'pp': {
              'kind': 'openai-compatible',
              'base_url': 'https://pp.test/v1',
              'models': {'m': <String, Object?>{}},
            },
          },
          'budget': {'max_steps': 3},
        }, kind: ConfigLayerKind.project),
      ], projectRoot: '/proj');

      expect(
        result.values.keys.any((k) => k.startsWith('providers.pp')),
        isFalse,
      );
      expect(result.values['budget.max_steps'], 3);
      expect(result.values['trusted_projects'], ['/other']);
    });

    test('are empty for a failed load', () {
      final result = load([
        layer({
          ...baseValues(),
          'budget': {'max_steps': 0},
        }),
      ]);

      expect(result.config, isNull);
      expect(result.values, isEmpty);
    });
  });

  group('pinnedTrustedProjects', () {
    Map<String, Object?> project() => {
      'providers': {
        'pp': {
          'kind': 'openai-compatible',
          'base_url': 'https://pp.test/v1',
          'models': {'ppm': <String, Object?>{}},
        },
      },
    };

    ConfigLoadResult run(List<String> trusted, {List<String>? pinned}) =>
        CoreConfig.fromLayers(
          [
            layer({...baseValues(), 'trusted_projects': trusted}),
            layer(project(), kind: ConfigLayerKind.project),
          ],
          environment: const {},
          projectRoot: '/proj',
          pinnedTrustedProjects: pinned,
        );

    test('without it the user layer decides, as before', () {
      final result = run(['/proj']);

      expect(result.config!.trustedProjects, ['/proj']);
      expect(
        result.config!.providers.map((p) => p.config.name),
        contains('pp'),
      );
    });

    test('a pinned empty list keeps the project untrusted although the '
        'file trusts it; the new value is only in values', () {
      final result = run(['/proj'], pinned: const []);

      expect(result.config!.trustedProjects, isEmpty);
      expect(result.config!.withoutProject!.trustedProjects, isEmpty);
      expect(
        result.config!.providers.map((p) => p.config.name),
        isNot(contains('pp')),
      );
      expect(result.values['trusted_projects'], ['/proj']);
      expect(
        result.warnings.map((w) => w.event),
        contains('config.project.untrusted_key'),
      );
    });

    test('a pinned list keeps the project trusted although the file '
        'dropped it', () {
      final result = run(const [], pinned: ['/proj']);

      expect(result.config!.trustedProjects, ['/proj']);
      expect(result.config!.withoutProject!.trustedProjects, ['/proj']);
      expect(
        result.config!.providers.map((p) => p.config.name),
        contains('pp'),
      );
      expect(result.values['trusted_projects'], isEmpty);
    });

    test('a project outside the pinned list stays untrusted', () {
      final result = run(['/proj'], pinned: ['/elsewhere']);

      expect(result.config!.trustedProjects, ['/elsewhere']);
      expect(
        result.config!.providers.map((p) => p.config.name),
        isNot(contains('pp')),
      );
    });
  });
}
