import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

/// Типы правок конфига (agent-configuration «Запись конфига ConfigWriter»;
/// `agent-core-architecture` §17.5.2; design.md change
/// `add-config-writer-and-reload`, D5). Это чистые значения ядра: писатель
/// `codelab_agent_io` и клиенты через реэкспорт `codelab_setup` строят и
/// сравнивают их, не видя `dart:io`.
void main() {
  group('ConfigLayer', () {
    test('lists only the writable layers 2, 3 and 4 in priority order', () {
      expect(ConfigLayer.values, [
        ConfigLayer.user,
        ConfigLayer.project,
        ConfigLayer.projectLocal,
      ]);
    });
  });

  group('ConfigTarget', () {
    test('user has no cwd', () {
      const target = ConfigTarget.user();

      expect(target.layer, ConfigLayer.user);
      expect(target.cwd, isNull);
    });

    test('project and projectLocal carry the cwd', () {
      const project = ConfigTarget.project('/work/app');
      const local = ConfigTarget.projectLocal('/work/app');

      expect((project.layer, project.cwd), (ConfigLayer.project, '/work/app'));
      expect((local.layer, local.cwd), (ConfigLayer.projectLocal, '/work/app'));
    });

    test('targets are equal by layer and cwd', () {
      expect(
        const ConfigTarget.project('/a'),
        const ConfigTarget.project('/a'),
      );
      expect(
        const ConfigTarget.project('/a').hashCode,
        const ConfigTarget.project('/a').hashCode,
      );
      expect(const ConfigTarget.user(), const ConfigTarget.user());
      expect(
        const ConfigTarget.project('/a'),
        isNot(const ConfigTarget.project('/b')),
      );
      expect(
        const ConfigTarget.project('/a'),
        isNot(const ConfigTarget.projectLocal('/a')),
      );
    });
  });

  group('ConfigSnapshot.get', () {
    final snapshot = ConfigSnapshot(
      target: const ConfigTarget.user(),
      path: '/home/u/.codelab/config.yaml',
      fingerprint: 'abc',
      values: {
        'agent': {'default_model': 'p/m'},
        'providers': {
          'openai': {'base_url': 'https://api.test/v1'},
          'local': {
            'models': {
              'qwen2.5-coder-32b': {'context_window': 32768},
              'llama3.1:70b': {'context_window': 8192},
            },
          },
        },
        'mcp': {
          'servers': [
            {'name': 'github', 'url': 'https://mcp.test', 'enabled': true},
            {'name': 'files', 'command': 'srv'},
          ],
        },
      },
    );

    test('reads a nested value by a dotted path', () {
      expect(snapshot.get('agent.default_model'), 'p/m');
      expect(snapshot.get('providers.openai.base_url'), 'https://api.test/v1');
    });

    test('returns a whole subtree for a section path', () {
      expect(snapshot.get('agent'), {'default_model': 'p/m'});
    });

    test('selects an mcp.servers element by name', () {
      expect(snapshot.get('mcp.servers[github].url'), 'https://mcp.test');
      expect(snapshot.get('mcp.servers[files].command'), 'srv');
      expect(snapshot.get('mcp.servers[files]'), {
        'name': 'files',
        'command': 'srv',
      });
    });

    test('selects a list element by index', () {
      expect(snapshot.get('mcp.servers[1].name'), 'files');
    });

    test('reads a quoted segment as one key even with a dot or a colon', () {
      expect(
        snapshot.get(
          'providers.local.models."qwen2.5-coder-32b".context_window',
        ),
        32768,
      );
      expect(
        snapshot.get('providers.local.models."llama3.1:70b".context_window'),
        8192,
      );
    });

    test('returns null for a missing key, server or index', () {
      expect(snapshot.get('agent.fallback'), isNull);
      expect(snapshot.get('budget.max_steps'), isNull);
      expect(snapshot.get('mcp.servers[absent].url'), isNull);
      expect(snapshot.get('mcp.servers[7].url'), isNull);
      expect(snapshot.get('agent.default_model.deeper'), isNull);
    });

    test('an element is chosen by name first, a number is an index only '
        'when no element has that name', () {
      final named = ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/c.yaml',
        fingerprint: null,
        values: {
          'mcp': {
            'servers': [
              {'name': 'a', 'url': 'u0'},
              {'name': '0', 'url': 'u1'},
            ],
          },
        },
      );

      expect(named.get('mcp.servers[0].url'), 'u1');
      expect(named.get('mcp.servers[1].url'), 'u1');
      expect(named.get('mcp.servers[a].url'), 'u0');
    });

    test('malformed paths find nothing', () {
      for (final key in [
        'agent..default_model',
        'agent.default_model.',
        'agent."default_model',
        'mcp.servers[github',
        '',
      ]) {
        expect(snapshot.get(key), isNull, reason: key);
      }
    });

    test('a missing file is a snapshot without fingerprint and values', () {
      const empty = ConfigSnapshot(
        target: ConfigTarget.project('/p'),
        path: '/p/.codelab/config.yaml',
        fingerprint: null,
        values: {},
      );

      expect(empty.fingerprint, isNull);
      expect(empty.get('agent.default_model'), isNull);
    });
  });

  group('ConfigEdit equality', () {
    test('SetValue compares key and value deeply', () {
      expect(const SetValue('a.b', 1), const SetValue('a.b', 1));
      expect(
        const SetValue('a.b', 1).hashCode,
        const SetValue('a.b', 1).hashCode,
      );
      expect(const SetValue('a.b', 1), isNot(const SetValue('a.b', 2)));
      expect(const SetValue('a.b', 1), isNot(const SetValue('a.c', 1)));
      expect(
        SetValue('permissions.deny', ['x', 'y']),
        SetValue('permissions.deny', ['x', 'y']),
      );
      expect(
        SetValue('permissions.deny', ['x', 'y']).hashCode,
        SetValue('permissions.deny', ['x', 'y']).hashCode,
      );
      expect(
        SetValue('permissions.deny', ['x', 'y']),
        isNot(SetValue('permissions.deny', ['y', 'x'])),
      );
      expect(
        SetValue('providers.p.headers', {'A': '1'}),
        SetValue('providers.p.headers', {'A': '1'}),
      );
    });

    test(
      'UnsetValue, RemoveTable and RemoveMcpServer compare by key or name',
      () {
        expect(const UnsetValue('k'), const UnsetValue('k'));
        expect(const UnsetValue('k').hashCode, const UnsetValue('k').hashCode);
        expect(const UnsetValue('k'), isNot(const UnsetValue('j')));
        expect(
          const RemoveTable('providers.x'),
          const RemoveTable('providers.x'),
        );
        expect(
          const RemoveTable('providers.x').hashCode,
          const RemoveTable('providers.x').hashCode,
        );
        expect(const RemoveMcpServer('gh'), const RemoveMcpServer('gh'));
        expect(const RemoveMcpServer('gh'), isNot(const RemoveMcpServer('x')));
      },
    );

    test('UpsertMcpServer compares the server map deeply', () {
      expect(
        UpsertMcpServer({
          'name': 'gh',
          'args': ['-y', 'srv'],
        }),
        UpsertMcpServer({
          'name': 'gh',
          'args': ['-y', 'srv'],
        }),
      );
      expect(
        UpsertMcpServer({'name': 'gh'}).hashCode,
        UpsertMcpServer({'name': 'gh'}).hashCode,
      );
      expect(
        UpsertMcpServer({'name': 'gh'}),
        isNot(UpsertMcpServer({'name': 'other'})),
      );
    });

    test('toString never prints a value, an env or a header', () {
      const secret = 'not-a-real-key-x';

      expect(
        const SetValue('providers.p.headers', secret).toString(),
        isNot(contains(secret)),
      );
      expect(
        UpsertMcpServer({
          'name': 'gh',
          'env': {'GITHUB_TOKEN': secret},
          'headers': {'Authorization': secret},
        }).toString(),
        allOf(isNot(contains(secret)), isNot(contains('GITHUB_TOKEN'))),
      );
    });

    test('edits of different kinds are never equal', () {
      expect(const UnsetValue('k'), isNot(const RemoveTable('k')));
      expect(const RemoveMcpServer('k'), isNot(const RemoveTable('k')));
      expect(const SetValue('k', 'k'), isNot(const UnsetValue('k')));
    });

    test('the hierarchy is sealed: a switch over it is exhaustive', () {
      String kind(ConfigEdit edit) => switch (edit) {
        SetValue() => 'set',
        UnsetValue() => 'unset',
        UpsertMcpServer() => 'upsert',
        RemoveMcpServer() => 'removeServer',
        RemoveTable() => 'removeTable',
      };

      expect(kind(const SetValue('k', 1)), 'set');
      expect(kind(const RemoveTable('k')), 'removeTable');
    });
  });

  group('ConfigConflictException', () {
    test('names the file and is a plain Exception, not a ConfigException', () {
      const error = ConfigConflictException('/home/u/.codelab/config.yaml');

      expect(error, isA<Exception>());
      expect(error, isNot(isA<ConfigException>()));
      expect(error.path, '/home/u/.codelab/config.yaml');
      expect(error.toString(), contains('/home/u/.codelab/config.yaml'));
    });
  });
}
