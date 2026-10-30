import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:test/test.dart';

import 'config_support.dart';

/// Схема и строгая проверка (agent-configuration «Схема и строгая
/// проверка»; CFG-1, CFG-4, `agent-core-architecture` §15.4–§15.5).
void main() {
  group('unknown keys', () {
    test('a typo gets the nearest key as a hint, with file position', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'compaction': {'reserve_token': 1000},
          }),
          source: 'config.yaml',
          positions: {'compaction.reserve_token': const ConfigPosition(12, 3)},
        ),
      ]);

      final issue = issuesAt(result, 'compaction.reserve_token').single;
      expect(issue.kind, ConfigIssueKind.unknownKey);
      expect(issue.message, 'unknown key (did you mean reserve_tokens?)');
      expect((issue.line, issue.column), (12, 3));
      expect(
        issue.toString(),
        'config.yaml:12:3: compaction.reserve_token: '
        'unknown key (did you mean reserve_tokens?)',
      );
      expect(result.config, isNull);
      expect(result.host, isNull);
    });

    test('a key far from every known key has no hint', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'compaction': {'zzzzzzzz': 1},
          }),
        ),
      ]);

      expect(
        issuesAt(result, 'compaction.zzzzzzzz').single.message,
        'unknown key',
      );
    });

    test('a key with a dot suggests the nested form', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'tools': {'output.max_lines': 2000},
          }),
        ),
      ]);

      final issue = issuesAt(result, 'tools.output.max_lines').single;
      expect(issue.kind, ConfigIssueKind.unknownKey);
      expect(issue.message, contains('output:'));
      expect(issue.message, contains('max_lines:'));
    });

    test('an unknown top-level section is an error, not a warning', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'foo': {'bar': 1},
          }),
        ),
      ]);

      expect(issuesAt(result, 'foo').single.kind, ConfigIssueKind.unknownKey);
    });

    test('agents.definitions in YAML points to the Markdown file '
        '(core/config-rejects-yaml-agent-definitions, DF-12)', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'agents': {
              'definitions': {
                'reviewer': {'prompt': 'x'},
              },
            },
          }),
        ),
      ]);

      final issue = issuesAt(result, 'agents.definitions.reviewer').single;
      expect(issue.message, contains('.codelab/agents/reviewer.md'));
      expect(result.config, isNull);
    });
  });

  group('types', () {
    test('a wrong type names the expected one', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'budget': {'max_steps': 'x'},
          }),
        ),
      ]);

      final issue = issuesAt(result, 'budget.max_steps').single;
      expect(issue.kind, ConfigIssueKind.type);
      expect(issue.message, contains('expected int'));
    });

    test('yes/on/off for bool is an error with a hint, but off in '
        'profile.* is a plain string', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'compaction': {'enabled': 'yes'},
            'profile': {
              'agent-serve': {'shell_exec': 'off'},
            },
          }),
        ),
      ]);

      final issue = issuesAt(result, 'compaction.enabled').single;
      expect(issue.kind, ConfigIssueKind.type);
      expect(issue.message, contains('use true or false'));
      expect(result.issues.where((i) => i.key.startsWith('profile')), isEmpty);
    });

    test('null at a schema key is an error, an empty container is not', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'budget': {'max_steps': null},
            'exec': null,
          }),
        ),
      ]);

      final issue = issuesAt(result, 'budget.max_steps').single;
      expect(issue.kind, ConfigIssueKind.type);
      expect(issue.message, contains('null'));
      expect(issuesAt(result, 'exec'), isEmpty);
    });

    test('int does not accept 2.0, float accepts 2', () {
      final bad = load([
        layer(
          withValues(baseValues(), {
            'budget': {'max_steps': 2.0},
          }),
        ),
      ]);
      final good = load([
        layer(
          withValues(baseValues(), {
            'budget': {'max_cost': 2},
          }),
        ),
      ]);

      expect(
        issuesAt(bad, 'budget.max_steps').single.kind,
        ConfigIssueKind.type,
      );
      expect(good.issues, isEmpty, reason: good.issues.join('\n'));
      expect(good.config!.budget.maxCost, 2.0);
    });

    test('a duration is a string like 30s; a bare number is an error', () {
      ConfigLoadResult withTimeout(Object value) => load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {'connect_timeout': value},
            },
          }),
        ),
      ]);

      expect(withTimeout('30s').issues, isEmpty);
      expect(
        issuesAt(withTimeout(30), 'providers.p.connect_timeout').single.kind,
        ConfigIssueKind.type,
      );
      expect(
        issuesAt(withTimeout('soon'), 'providers.p.connect_timeout'),
        hasLength(1),
      );
    });

    test('exec.secrets as a string is an error', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'exec': {'secrets': 'GITHUB_TOKEN'},
          }),
        ),
      ]);

      expect(
        issuesAt(result, 'exec.secrets').single.kind,
        ConfigIssueKind.type,
      );
    });

    test('a non-string element of a string list names its index', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'permissions': {
              'deny': ['exec:git push', 5],
            },
          }),
        ),
      ]);

      expect(
        issuesAt(result, 'permissions.deny[1]').single.kind,
        ConfigIssueKind.type,
      );
    });
  });

  group('permissions.mode', () {
    test('autopilot in a file layer is an error (CFG-4)', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'permissions': {'mode': 'autopilot'},
          }),
        ),
      ]);

      final issue = issuesAt(result, 'permissions.mode').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, contains('launch flag'));
    });

    test('autopilot from the flags layer of the same run is accepted', () {
      final result = load([
        layer(baseValues()),
        layer({
          'permissions': {'mode': 'autopilot'},
        }, kind: ConfigLayerKind.flags),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config!.permissions.modeOverride, PermissionMode.autopilot);
    });

    test('a mode of the table and its synonyms are accepted', () {
      for (final (name, expected) in [
        ('plan', ModeId.plan),
        ('accept-edits', ModeId.acceptEdits),
        ('acceptEdits', ModeId.acceptEdits),
        ('yolo', ModeId.bypass),
        ('alwaysAsk', ModeId.ask),
        ('write', ModeId.standard),
      ]) {
        final result = load([
          layer(
            withValues(baseValues(), {
              'permissions': {'mode': name},
            }),
          ),
        ]);
        expect(result.config?.permissions.mode, expected, reason: name);
      }
    });

    test('a legacy ACP synonym is not accepted', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'permissions': {'mode': 'architect'},
          }),
        ),
      ]);

      expect(issuesAt(result, 'permissions.mode'), hasLength(1));
    });
  });

  group('semantics (§15.5, step 8)', () {
    test('agent.default_model is required', () {
      final result = load([
        layer({'providers': baseValues()['providers']}),
      ]);

      final issue = issuesAt(result, 'agent.default_model').single;
      expect(issue.message, 'required');
    });

    test('agent.default_model must be in the provider catalog', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'agent': {'default_model': 'q/m'},
          }),
        ),
      ]);

      expect(
        issuesAt(result, 'agent.default_model').single.message,
        contains('q/m'),
      );
    });

    test('an unknown provider kind lists the known ones '
        '(core/config-unknown-provider-error, DF-15)', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'foo': {'kind': 'mock'},
            },
          }),
        ),
      ]);

      final issue = issuesAt(result, 'providers.foo.kind').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, contains('openai-compatible'));
      expect(issue.message, contains('anthropic'));
      expect(issue.message, contains('gemini'));
      expect(result.config, isNull);
    });

    test('openai-compatible needs base_url', () {
      final values = baseValues();
      ((values['providers']! as Map)['p']! as Map).remove('base_url');
      final result = load([layer(values)]);

      expect(issuesAt(result, 'providers.p.base_url'), hasLength(1));
    });

    test('anthropic and gemini have a default base_url', () {
      final result = load([
        layer({
          'providers': {
            'a': {
              'kind': 'anthropic',
              'models': {'c': <String, Object?>{}},
            },
            'g': {
              'kind': 'gemini',
              'models': {'x': <String, Object?>{}},
            },
          },
          'agent': {'default_model': 'a/c'},
        }),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(
        result.config!.providers
            .map((p) => p.config.baseUrl.toString())
            .toList(),
        [
          'https://api.anthropic.com',
          'https://generativelanguage.googleapis.com',
        ],
      );
    });

    test('a deny entry without <tool>:<pattern> names its index', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'permissions': {
              'deny': ['exec:git push', 'bad'],
            },
          }),
        ),
      ]);

      expect(issuesAt(result, 'permissions.deny[1]'), hasLength(1));
    });

    test('numeric limits are checked with the key path', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'budget': {'max_steps': 0},
            'compaction': {'reserve_tokens': 0, 'keep_recent_tokens': -1},
            'providers': {
              'p': {'idle_timeout': '60s', 'idle_timeout_reasoning': '30s'},
            },
          }),
        ),
      ]);

      expect(issuesAt(result, 'budget.max_steps'), hasLength(1));
      expect(issuesAt(result, 'compaction.reserve_tokens'), hasLength(1));
      expect(issuesAt(result, 'compaction.keep_recent_tokens'), hasLength(1));
      expect(
        issuesAt(result, 'providers.p.idle_timeout_reasoning'),
        hasLength(1),
      );
    });

    test('a valid config builds CoreConfig and HostSettings', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'agent': {'effort': 'high'},
            'budget': {'max_steps': 20, 'max_duration': '5m'},
            'compaction': {'reserve_tokens': 4000, 'enabled': false},
            'sessions': {'dir': '/data/s', 'fsync': 'always'},
            'logging': {'level': 'debug', 'file': '/data/agent.log'},
          }),
        ),
      ]);

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final config = result.config!;
      expect(config.defaultModel.provider, 'p');
      expect(config.defaultModel.id, 'm');
      expect(config.effort, ReasoningEffort.high);
      expect(config.budget.maxSteps, 20);
      expect(config.budget.maxDuration, const Duration(minutes: 5));
      expect(config.compaction.reserveTokens, 4000);
      expect(config.compaction.enabled, isFalse);
      final host = result.host!;
      expect(host.sessionsDir, '/data/s');
      expect(host.fsync, 'always');
      expect(host.logLevel, LogLevel.debug);
      expect(host.logFile, '/data/agent.log');
    });

    test('the profile section narrows; widening is an error with the key '
        'path', () {
      final narrowed = load([
        layer(
          withValues(baseValues(), {
            'profile': {
              'agent-serve': {
                'shell_exec': 'off',
                'mcp': ['http'],
              },
            },
          }),
        ),
      ]);
      final widened = load([
        layer(
          withValues(baseValues(), {
            'profile': {
              'agent-serve': {
                'mcp': ['http', 'websocket'],
              },
            },
          }),
        ),
      ]);

      expect(narrowed.issues, isEmpty, reason: narrowed.issues.join('\n'));
      final narrowing = narrowed.host!.profileNarrowing['agent-serve']!;
      expect(narrowing[HostCapability.shellExec], isA<CapabilityOff>());
      expect(
        (narrowing[HostCapability.mcp]! as CapabilityTransport).transports,
        {'http'},
      );
      expect(issuesAt(widened, 'profile.agent-serve.mcp'), hasLength(1));
    });

    test('the result lists the sources in layer order', () {
      final result = load([
        layer({}, kind: ConfigLayerKind.defaults, source: 'defaults'),
        layer(baseValues(), source: '/h/config.yaml'),
        layer({}, kind: ConfigLayerKind.flags, source: 'flags'),
      ]);

      expect(result.sources, ['defaults', '/h/config.yaml', 'flags']);
    });
  });

  group('exceptions', () {
    test('orThrow returns the config or throws ConfigException', () {
      final good = load([layer(baseValues())]);
      final bad = load([
        layer(
          withValues(baseValues(), {
            'budget': {'max_steps': 0},
          }),
        ),
      ]);

      expect(good.orThrow(), same(good.config));
      expect(bad.orThrow, throwsA(isA<ConfigException>()));
    });
  });
}
