import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:codelab_agent_core/src/config/key_path.dart' show samePath;
import 'package:test/test.dart';

import 'config_support.dart';

/// Доверие к проектному конфигу (agent-configuration «Доверие к проектному
/// конфигу»; `agent-core-architecture` §15.3; CFG-3; design.md change
/// `add-agent-configuration`, D7).
void main() {
  ConfigTree project(Map<String, Object?> values) =>
      layer(values, kind: ConfigLayerKind.project);

  const server = {'name': 'gh', 'type': 'http', 'url': 'https://gh.test/mcp'};

  Map<String, Object?> projectValues() => {
    'mcp': {
      'servers': [server],
    },
    'permissions': {
      'tools': {'exec': 'allow', 'read': 'ask', 'write': 'deny'},
    },
  };

  group('an untrusted project', () {
    test('loses mcp.servers and allow rules, with one warning each', () {
      final result = load([
        layer(baseValues()),
        project(projectValues()),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final config = result.config!;
      expect(config.mcpServers, isEmpty);
      expect(config.permissions.rules.toolPolicies, {
        'read': ToolPolicy.ask,
        'write': ToolPolicy.deny,
      });
      final warnings = warningsOf(result, 'config.project.untrusted_key');
      expect(
        [for (final w in warnings) w.key],
        ['mcp.servers', 'permissions.tools.exec'],
      );
      expect(warnings.first.fields, {
        'key': 'mcp.servers',
        'source': '/proj/.codelab/config.yaml',
      });
    });

    test('loses providers and model_catalog', () {
      final result = load([
        layer(baseValues()),
        project({
          'providers': {
            'evil': {
              'kind': 'openai-compatible',
              'base_url': 'https://evil.test/v1',
            },
          },
        }),
      ], projectRoot: '/proj');

      expect([for (final p in result.config!.providers) p.config.name], ['p']);
      expect(
        [
          for (final w in warningsOf(result, 'config.project.untrusted_key'))
            w.key,
        ],
        ['providers'],
      );
    });

    test('keeps ask/deny rules, agent.default_model and compaction', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'providers': {
              'p': {
                'models': {'m2': <String, Object?>{}},
              },
            },
          }),
        ),
        project({
          'agent': {'default_model': 'p/m2', 'effort': 'low'},
          'compaction': {'reserve_tokens': 123},
          'permissions': {
            'deny': ['exec:git push'],
          },
        }),
      ], projectRoot: '/proj');

      final config = result.config!;
      expect(config.defaultModel.id, 'm2');
      expect(config.effort, ReasoningEffort.low);
      expect(config.compaction.reserveTokens, 123);
      expect(config.permissions.rules.denyPatterns, {
        const PermissionKey('exec', 'git push'),
      });
      expect(result.warnings, isEmpty);
    });
  });

  group('a trusted project', () {
    test('keeps mcp.servers, allow rules and providers', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
          }),
        ),
        project(projectValues()),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      final config = result.config!;
      expect([for (final s in config.mcpServers) s.name], ['gh']);
      expect(config.permissions.rules.toolPolicies['exec'], ToolPolicy.allow);
      expect(result.warnings, isEmpty);
    });

    test('the path is compared by components after normalization', () {
      for (final listed in ['/proj/', '/a/../proj', '/proj/./']) {
        final result = load([
          layer(
            withValues(baseValues(), {
              'trusted_projects': [listed],
            }),
          ),
          project(projectValues()),
        ], projectRoot: '/proj');

        expect(result.config!.mcpServers, hasLength(1), reason: listed);
      }
      final other = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj-other'],
          }),
        ),
        project(projectValues()),
      ], projectRoot: '/proj');
      expect(other.config!.mcpServers, isEmpty);
    });

    test('sessions, logging and exec are dropped even with trust', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
          }),
        ),
        project({
          'sessions': {'dir': '/evil'},
          'logging': {'level': 'trace'},
          'exec': {'shell': '/bin/evil'},
        }),
      ], projectRoot: '/proj');

      expect(result.host!.sessionsDir, isNull);
      expect(result.host!.logLevel, isNull);
      expect(
        [
          for (final w in warningsOf(result, 'config.project.untrusted_key'))
            w.key,
        ],
        ['sessions', 'logging', 'exec'],
      );
      expect(
        warningsOf(result, 'config.key.not_applied'),
        isEmpty,
        reason: 'a dropped key is not also reported as not applied',
      );
    });
  });

  group('permissions.mode only narrows', () {
    ModeId? modeOf(String? lower, String upper) {
      final result = load([
        layer(
          withValues(baseValues(), {
            if (lower != null) 'permissions': {'mode': lower},
          }),
        ),
        project({
          'permissions': {'mode': upper},
        }),
      ], projectRoot: '/proj');
      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      return result.config!.permissions.mode;
    }

    test('bypass below, ask in the project: ask', () {
      expect(modeOf('bypass', 'ask'), ModeId.ask);
    });

    test('ask below, bypass in the project: ask stays', () {
      expect(modeOf('ask', 'bypass'), ModeId.ask);
    });

    test('nothing below: the project cannot go softer than the profile '
        'default, but can tighten', () {
      expect(modeOf(null, 'bypass'), isNull);
      expect(modeOf(null, 'accept-edits'), isNull);
      expect(modeOf(null, 'ask'), ModeId.ask);
    });

    test('plan wins over every softer mode', () {
      expect(modeOf('bypass', 'plan'), ModeId.plan);
      expect(modeOf('plan', 'bypass'), ModeId.plan);
      expect(modeOf('standard', 'plan'), ModeId.plan);
    });

    Set<ToolTier> extraOf(String? lower, String upper) {
      final result = load([
        layer(
          withValues(baseValues(), {
            if (lower != null) 'permissions': {'mode': lower},
          }),
        ),
        project({
          'permissions': {'mode': upper},
        }),
      ], projectRoot: '/proj');
      return result.config!.permissions.extraDeniedTiers;
    }

    test('ask below and plan in the project: ask with write and exec '
        'denied (§15.3)', () {
      expect(modeOf('ask', 'plan'), ModeId.ask);
      expect(extraOf('ask', 'plan'), {ToolTier.write, ToolTier.exec});
    });

    test('plan below and ask in the project: both restrictions stay', () {
      expect(modeOf('plan', 'ask'), ModeId.ask);
      expect(extraOf('plan', 'ask'), {ToolTier.write, ToolTier.exec});
    });

    test('other combinations add no extra denied tiers', () {
      expect(extraOf('standard', 'plan'), isEmpty);
      expect(extraOf('bypass', 'ask'), isEmpty);
      expect(extraOf(null, 'ask'), isEmpty);
    });
  });

  group('budget only decreases', () {
    int steps(int? lower, int upper, {List<ConfigIssue>? warnings}) {
      final result = load([
        layer(
          withValues(baseValues(), {
            if (lower != null) 'budget': {'max_steps': lower},
          }),
        ),
        project({
          'budget': {'max_steps': upper},
        }),
      ], projectRoot: '/proj');
      warnings?.addAll(warningsOf(result, 'config.project.untrusted_key'));
      return result.config!.budget.maxSteps;
    }

    test('an increase is dropped with one warning', () {
      final warnings = <ConfigIssue>[];

      expect(steps(30, 100, warnings: warnings), 30);
      expect(warnings.single.key, 'budget.max_steps');
    });

    test('a decrease is applied', () {
      final warnings = <ConfigIssue>[];

      expect(steps(30, 10, warnings: warnings), 10);
      expect(warnings, isEmpty);
    });

    test('with nothing below, the built-in limit 50 is the ceiling', () {
      expect(steps(null, 100), 50);
      expect(steps(null, 20), 20);
    });

    test(
      'a limit that was unlimited below accepts any finite project value',
      () {
        final result = load([
          layer(baseValues()),
          project({
            'budget': {'max_tokens': 5000, 'max_duration': '5m'},
          }),
        ], projectRoot: '/proj');

        expect(result.config!.budget.maxTokens, 5000);
        expect(result.config!.budget.maxDuration, const Duration(minutes: 5));
      },
    );
  });

  group('trusted_projects', () {
    test('in a project layer is dropped with a warning, not an error '
        '(CFG-3)', () {
      for (final kind in [
        ConfigLayerKind.project,
        ConfigLayerKind.projectLocal,
      ]) {
        final result = load([
          layer(baseValues()),
          layer({
            'trusted_projects': ['/proj'],
          }, kind: kind),
        ], projectRoot: '/proj');

        expect(result.issues, isEmpty, reason: kind.name);
        expect(
          [
            for (final w in warningsOf(result, 'config.project.untrusted_key'))
              w.key,
          ],
          ['trusted_projects'],
          reason: kind.name,
        );
        expect(result.config!.mcpServers, isEmpty);
      }
    });

    test('in the --config layer is a problem', () {
      final result = load([
        layer(baseValues()),
        layer({
          'trusted_projects': ['/proj'],
        }, kind: ConfigLayerKind.extra),
      ]);

      final issue = issuesAt(result, 'trusted_projects').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(
        issue.message,
        'trusted_projects is read only from the global config',
      );
    });

    test('a relative path is a problem with its index', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/ok', 'proj'],
          }),
        ),
      ]);

      final issue = issuesAt(result, 'trusted_projects[1]').single;
      expect(issue.kind, ConfigIssueKind.value);
      expect(issue.message, contains('absolute'));
    });

    test('~ is expanded before the absolute check', () {
      final result = load(
        [
          layer(
            withValues(baseValues(), {
              'trusted_projects': ['~/work/proj'],
            }),
          ),
          project(projectValues()),
        ],
        projectRoot: '/home/u/work/proj',
        environment: {'HOME': '/home/u'},
      );

      expect(result.issues, isEmpty);
      expect(result.config!.mcpServers, hasLength(1));
    });

    test('samePath tells an absolute path from a relative one', () {
      expect(samePath('/proj', '/proj/'), isTrue);
      expect(samePath('proj', '/proj'), isFalse);
      expect(samePath('/a/../proj', '/proj'), isTrue);
    });
  });

  test('project layers without projectRoot are a programmer error', () {
    for (final kind in [
      ConfigLayerKind.project,
      ConfigLayerKind.projectLocal,
    ]) {
      expect(
        () => load([layer(baseValues()), layer({}, kind: kind)]),
        throwsArgumentError,
        reason: kind.name,
      );
    }
  });

  group('rules of permissions in an untrusted project', () {
    ConfigLoadResult run(
      Map<String, Object?> user,
      Map<String, Object?> proj, {
      bool trusted = false,
      ConfigLayerKind kind = ConfigLayerKind.project,
    }) => load([
      layer(
        withValues(withValues(baseValues(), user), {
          if (trusted) 'trusted_projects': ['/proj'],
        }),
      ),
      layer(proj, kind: kind),
    ], projectRoot: '/proj');

    test('deny of the project is united with the global list, an empty list '
        'does not clear it', () {
      final cleared = run(
        {
          'permissions': {
            'deny': ['exec:rm -rf'],
          },
        },
        {
          'permissions': {'deny': <String>[]},
        },
      );
      final united = run(
        {
          'permissions': {
            'deny': ['exec:rm -rf'],
          },
        },
        {
          'permissions': {
            'deny': ['write:.env'],
          },
        },
      );

      expect(cleared.config!.permissions.rules.denyPatterns, {
        const PermissionKey('exec', 'rm -rf'),
      });
      expect(united.config!.permissions.rules.denyPatterns, {
        const PermissionKey('exec', 'rm -rf'),
        const PermissionKey('write', '.env'),
      });
    });

    test('a trusted project replaces the list as any global layer', () {
      final result = run(
        {
          'permissions': {
            'deny': ['exec:rm -rf'],
          },
        },
        {
          'permissions': {'deny': <String>[]},
        },
        trusted: true,
      );

      expect(result.config!.permissions.rules.denyPatterns, isEmpty);
    });

    test('a tool rule of the project applies only when it is stricter '
        '(deny > ask > allow)', () {
      final softer = run(
        {
          'permissions': {
            'tools': {'exec': 'deny', 'write': 'ask'},
          },
        },
        {
          'permissions': {
            'tools': {'exec': 'ask', 'write': 'deny', 'read': 'ask'},
          },
        },
      );

      expect(softer.config!.permissions.rules.toolPolicies, {
        'exec': ToolPolicy.deny,
        'write': ToolPolicy.deny,
        'read': ToolPolicy.ask,
      });
      expect(
        [
          for (final w in warningsOf(softer, 'config.project.untrusted_key'))
            w.key,
        ],
        ['permissions.tools.exec'],
      );
    });

    test('a trusted project may soften a tool rule', () {
      final result = run(
        {
          'permissions': {
            'tools': {'exec': 'deny'},
          },
        },
        {
          'permissions': {
            'tools': {'exec': 'ask'},
          },
        },
        trusted: true,
      );

      expect(
        result.config!.permissions.rules.toolPolicies['exec'],
        ToolPolicy.ask,
      );
    });
  });

  group('config.local.yaml follows the trust rules until the project is '
      'trusted', () {
    final local = {
      'mcp': {
        'servers': [server],
      },
      'permissions': {
        'tools': {'exec': 'allow'},
        'mode': 'bypass',
      },
      'budget': {'max_steps': 500},
    };

    test('untrusted: servers, allow, a softer mode and a bigger budget are '
        'dropped', () {
      final result = load([
        layer(baseValues()),
        layer(local, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      final config = result.config!;
      expect(config.mcpServers, isEmpty);
      expect(config.permissions.rules.toolPolicies, isEmpty);
      expect(config.permissions.mode, isNull);
      expect(config.budget.maxSteps, 50);
      expect(
        [
          for (final w in warningsOf(result, 'config.project.untrusted_key'))
            w.key,
        ],
        containsAll([
          'mcp.servers',
          'permissions.tools.exec',
          'permissions.mode',
          'budget.max_steps',
        ]),
      );
    });

    test('trusted: nothing is dropped', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
          }),
        ),
        layer(local, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      final config = result.config!;
      expect(config.mcpServers, hasLength(1));
      expect(config.permissions.rules.toolPolicies['exec'], ToolPolicy.allow);
      expect(config.permissions.mode, ModeId.bypass);
      expect(config.budget.maxSteps, 500);
      expect(warningsOf(result, 'config.project.untrusted_key'), isEmpty);
    });

    test('untrusted: sessions, logging and exec are dropped; trusted: only '
        'config.local.yaml may set them', () {
      final values = {
        'sessions': {'dir': '/data'},
        'logging': {'level': 'debug'},
        'exec': {'shell': '/bin/zsh'},
      };
      final untrusted = load([
        layer(baseValues()),
        layer(values, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');
      final trusted = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
          }),
        ),
        layer(values, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      expect(untrusted.host!.sessionsDir, isNull);
      expect(
        [
          for (final w in warningsOf(untrusted, 'config.project.untrusted_key'))
            w.key,
        ],
        ['sessions', 'logging', 'exec'],
      );
      expect(trusted.host!.sessionsDir, '/data');
      expect(trusted.host!.logLevel, LogLevel.debug);
      expect(warningsOf(trusted, 'config.project.untrusted_key'), isEmpty);
    });

    test('the project layer below counts as "lower" for the local one', () {
      final result = load([
        layer(baseValues()),
        project({
          'permissions': {'mode': 'ask'},
        }),
        layer({
          'permissions': {'mode': 'bypass'},
        }, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      expect(result.config!.permissions.mode, ModeId.ask);
    });
  });

  group('sections that need trust beyond MVP keys', () {
    final sections = {
      'prompts': {'system_text': 'x'},
      'hooks': {'enabled': true},
      'plugins': {'enabled': <String>[]},
      'a2a': {
        'client': {'poll_interval': '1s'},
      },
      'lsp': {'enabled': true},
    };

    test('are dropped from an untrusted project, kept with trust', () {
      final untrusted = load([
        layer(baseValues()),
        project(sections),
      ], projectRoot: '/proj');
      final trusted = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
          }),
        ),
        project(sections),
      ], projectRoot: '/proj');

      expect(
        [
          for (final w in warningsOf(untrusted, 'config.project.untrusted_key'))
            w.key,
        ],
        ['prompts', 'hooks', 'plugins', 'a2a', 'lsp'],
      );
      expect(warningsOf(untrusted, 'config.key.not_applied'), isEmpty);
      expect(warningsOf(trusted, 'config.project.untrusted_key'), isEmpty);
      expect(warningsOf(trusted, 'config.key.not_applied'), isNotEmpty);
    });

    test('secrets are read only from the global config, even with trust', () {
      for (final kind in [
        ConfigLayerKind.project,
        ConfigLayerKind.projectLocal,
      ]) {
        final result = load([
          layer(
            withValues(baseValues(), {
              'trusted_projects': ['/proj'],
            }),
          ),
          layer({
            'secrets': {'backend': 'file'},
          }, kind: kind),
        ], projectRoot: '/proj');

        expect(
          [
            for (final w in warningsOf(result, 'config.project.untrusted_key'))
              w.key,
          ],
          ['secrets'],
          reason: kind.name,
        );
      }
    });
  });

  group('layers without trust rules', () {
    test('--config, environment and flags are not restricted', () {
      for (final kind in [
        ConfigLayerKind.extra,
        ConfigLayerKind.environment,
        ConfigLayerKind.flags,
      ]) {
        final result = load([
          layer(baseValues()),
          layer(projectValues(), kind: kind),
        ], projectRoot: '/proj');

        expect(result.config!.mcpServers, hasLength(1), reason: kind.name);
        expect(
          result.config!.permissions.rules.toolPolicies['exec'],
          ToolPolicy.allow,
          reason: kind.name,
        );
        expect(warningsOf(result, 'config.project.untrusted_key'), isEmpty);
      }
    });
  });

  // D9: снимок без проектных слоёв для сессий вне корня запуска.
  group('the snapshot without the project layers (D9)', () {
    test('holds the keys of layers 1, 2, 4a-6 only', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
            'budget': {'max_steps': 40},
          }),
        ),
        project(projectValues()),
        layer({
          'budget': {'max_steps': 10},
        }, kind: ConfigLayerKind.projectLocal),
      ], projectRoot: '/proj');

      final config = result.config!;
      expect(config.projectRoot, '/proj');
      expect(config.mcpServers, hasLength(1));
      expect(config.budget.maxSteps, 10);
      final bare = config.withoutProject!;
      expect(bare.mcpServers, isEmpty);
      expect(bare.budget.maxSteps, 40);
      expect(bare.permissions.rules.toolPolicies, isEmpty);
      expect(bare.withoutProject, isNull);
      expect(config.forSessionCwd('/proj'), same(config));
      expect(config.forSessionCwd('/proj/sub'), same(bare));
      expect(config.forSessionCwd('/other'), same(bare));
    });

    test('a default model set only by the project falls back to the model '
        'of the full snapshot', () {
      final values = baseValues()..remove('agent');
      final result = load([
        layer(values),
        project({
          'agent': {'default_model': 'p/m'},
        }),
      ], projectRoot: '/proj');

      expect(result.issues, isEmpty, reason: result.issues.join('\n'));
      expect(result.config!.withoutProject!.defaultModel.id, 'm');
    });

    test('a problem that exists only without the project is reported', () {
      final result = load([
        layer(
          withValues(baseValues(), {
            'trusted_projects': ['/proj'],
            'providers': {
              'p': {'idle_timeout': '700s'},
            },
          }),
        ),
        project({
          'providers': {
            'p': {'idle_timeout_reasoning': '900s'},
          },
        }),
      ], projectRoot: '/proj');

      expect(result.config, isNull);
      expect(issuesAt(result, 'providers.p.idle_timeout'), hasLength(1));
    });

    test('without project layers there is no second snapshot', () {
      final result = load([layer(baseValues())], projectRoot: '/proj');

      expect(result.config!.projectRoot, '/proj');
      expect(result.config!.withoutProject, isNull);
    });

    test('without projectRoot the config has no root', () {
      final result = load([layer(baseValues())]);

      expect(result.config!.projectRoot, isNull);
      expect(result.config!.forSessionCwd('/any'), same(result.config));
    });
  });
}
