// `McpSettingsCubit` (задача 5.4 change `add-provider-setup-ui`; spec
// app-settings «Страница «MCP servers»», «Панель «Agent status» страницы MCP
// servers», «События журнала Providers и MCP servers без секретов»;
// design.md D11, D12, D18, D21, D24, решения Q24–Q27).
//
// Красный тест: Cubit, его состояния и порт `EmbeddedMcpStatusSource` ещё не
// написаны (задача 5.10). Ожидаемый публичный API (имена выбраны здесь и
// фиксируют контракт для реализации):
//
// * `McpSettingsCubit({workspace, defaultProfile, open, environment,
//   codelabHome, projectDirectory, statusSource, logger?, now?})`;
//   `reload()`, `openNewServer()`, `cancelNewServer()`, `draftFor(name)`,
//   `save(draft, {target, replaceSecrets})`, `dismissReplaceQuestion()`,
//   `setEnabled(name, {enabled})`, `disableHere(name)`, `enableHere(name)`,
//   `removalPlan(name)`, `remove(name)`, `refresh()`, `reconnectServer(name)`,
//   `reloadAll()`, статический `secretNameFor(server, key)`;
// * состояния `McpSettingsLoading | McpSettingsReadOnly | McpSettingsUnreadable
//   | McpSettingsReady` (общий предок `McpSettingsLoaded` с `agentStatus`);
// * `McpAgentStatusUnavailable | McpAgentStatusLive(rows, updatedAt) |
//   McpAgentStatusText(text, sending, canSend, notice)`.
//
// Конфиг, секреты и порт MCP — двойники (`fake_provider_settings.dart`,
// `fake_mcp_status.dart`): порядок «секрет → конфиг → откат» проверяет мост
// `codelab_setup` (5.3), здесь — что страница вызывает и показывает. Маркер
// `sk-test-leak-…` лежит только в «хранилище» двойника и в ответах агента:
// состояние и журнал его видеть не должны (SETUP-1, D18).

import 'dart:async';
import 'dart:io';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show
        AgentMessageChunk,
        AgentThoughtChunk,
        SessionId,
        SessionUpdate,
        TextContent;
import 'package:codelab_client_acp/codelab_client_acp.dart' show SecretRedactor;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/embedded_profile.dart';
import 'package:codelab_desktop/features/settings/application/mcp_settings_cubit.dart';
import 'package:codelab_embedded/codelab_embedded.dart' show McpServerState;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_mcp_status.dart';
import '../../../support/fake_provider_settings.dart';
import '../../../support/real_config_session.dart';
import '../../../support/recording_logger.dart';

const _home = '/home/u/.codelab';
const _authorization = 'codelab/mcp/github/authorization';
const _listFailed = '/mcp list did not complete. Try Refresh again.';
const _unsetVariable = 'config.variable.unset';

final _s1 = SessionId('s1');
final _s2 = SessionId('s2');

final _ownAgent = ConnectionProfile.stdio(
  id: 'dev',
  label: 'Dev',
  command: '/opt/bin/codelab-agent',
  args: const ['serve', '--stdio'],
  env: const {'CODELAB_HOME': '/srv/codelab'},
);

final _remote = ConnectionProfile.webSocket(
  id: 'devbox',
  label: 'Devbox',
  uri: Uri.parse('wss://devbox:7420/acp?t=$leakMarker'),
);

const _foreign = ConnectionProfile.stdio(
  id: 'other',
  label: 'Other',
  command: 'python',
  args: ['-m', 'other_agent'],
);

/// Слой с серверами: изменяемая карта, как требует двойник конфига.
Map<String, Object?> _layer(List<Map<String, Object?>> servers) => {
  'mcp': {'servers': servers},
};

Map<String, Object?> _github({Map<String, Object?>? headers}) => {
  'name': 'github',
  'type': 'http',
  'url': 'https://api.example.test/mcp/',
  'headers': headers ?? {'Authorization': '\${secret:$_authorization}'},
  // Ключ, которого форма не знает: правка и переключатель его не теряют.
  'call_timeout': 30,
};

Map<String, Object?> _postgres() => {
  'name': 'postgres',
  'type': 'stdio',
  'command': 'uvx',
  'args': ['postgres-mcp'],
  'env': {'DATABASE_URL': r'${PG_URL}'},
};

Map<String, Object?> _playwright() => {
  'name': 'playwright',
  'type': 'stdio',
  'command': 'npx',
  'args': ['@playwright/mcp'],
};

McpServerDraft _newGithub({
  String name = 'github',
  Map<String, McpValueDraft>? headers,
}) => McpServerDraft(
  name: name,
  kind: McpTransportKind.http,
  url: 'https://api.example.test/mcp/',
  headers:
      headers ??
      {
        'Authorization': McpValueDraft.secret(
          SecretValue('Bearer $leakMarker'),
        ),
      },
);

SessionUpdate _msg(String text) =>
    AgentMessageChunk(content: TextContent(text: text));
SessionUpdate _thought(String text) =>
    AgentThoughtChunk(content: TextContent(text: text));

ConfigIssue _rejectedIssue({
  ConfigIssueKind kind = ConfigIssueKind.value,
  String key = 'mcp.servers[postgres].env.DATABASE_URL',
}) => ConfigIssue(
  kind: kind,
  key: key,
  source: FakeAgentConfigStore.userPath,
  message: 'variable PG_URL is not set',
  // Так загрузчик помечает незаданную `${VAR}`: без этого признака проблема
  // выглядела бы как «ключа нет» и ушла бы в `startProblems`.
  event: kind == ConfigIssueKind.value ? _unsetVariable : null,
  fields: const {'variable': 'PG_URL'},
);

void main() {
  late FakeAgentConfigStore store;
  late FakeProviderSettingsSession session;
  late FakeWorkspace workspace;
  late FakeEmbeddedMcpStatusSource source;
  late RecordingLogger logger;
  late List<McpSettingsCubit> cubits;
  late List<({EditableSettings access, Map<String, String> env})> opened;
  FutureOr<void> Function()? onOpen;
  Object? defaultProfileError;
  var projectDir = '/work/app';
  var clock = DateTime(2026, 11, 8, 14, 2);

  McpSettingsCubit make({String? home = _home}) {
    final cubit = McpSettingsCubit(
      workspace: workspace,
      defaultProfile: () async {
        if (defaultProfileError case final error?) {
          throw error;
        }
        return embeddedConnectionProfile;
      },
      open: (access, env) async {
        opened.add((access: access, env: env));
        await onOpen?.call();
        return session;
      },
      environment: const {'HOME': '/home/u'},
      codelabHome: home,
      projectDirectory: () => projectDir,
      statusSource: source,
      logger: logger,
      now: () => clock,
    );
    cubits.add(cubit);
    return cubit;
  }

  setUp(() {
    store = FakeAgentConfigStore(user: _layer([_github(), _postgres()]));
    session = FakeProviderSettingsSession(
      store,
      secrets: {_authorization: leakMarker},
    );
    workspace = FakeWorkspace();
    source = FakeEmbeddedMcpStatusSource();
    logger = RecordingLogger();
    cubits = [];
    opened = [];
    onOpen = null;
    defaultProfileError = null;
    projectDir = '/work/app';
    clock = DateTime(2026, 11, 8, 14, 2);
  });

  tearDown(() async {
    for (final cubit in cubits) {
      await cubit.close();
    }
  });

  Future<McpSettingsReady> ready(McpSettingsCubit cubit) async {
    await cubit.reload();
    return cubit.state as McpSettingsReady;
  }

  McpSettingsReady current(McpSettingsCubit cubit) =>
      cubit.state as McpSettingsReady;

  McpServerRow row(McpSettingsReady state, String name) =>
      state.rows.firstWhere((r) => r.name == name);

  McpAgentStatus status(McpSettingsCubit cubit) =>
      (cubit.state as McpSettingsLoaded).agentStatus;

  Map<String, Object?> event(String name) =>
      logger.entries.lastWhere((e) => e['event'] == name);

  Iterable<Object?> events() => logger.entries.map((e) => e['event']);

  /// Подключённое окно: профиль [profile], активная сессия [active].
  void connect(ConnectionProfile profile, {SessionId? active}) {
    workspace.emit(
      WorkspaceState(
        connection: const ConnectionView.connected(),
        profile: profile,
        activeSessionId: active,
      ),
    );
  }

  /// Сессия агента вне процесса, которая объявила `/mcp`.
  FakeSessionHandle externalSession({
    SessionId? id,
    SessionStatusView sessionStatus = SessionStatusView.idle,
    List<QueuedPrompt> queue = const [],
    bool announcesMcp = true,
  }) {
    final handle = FakeSessionHandle(
      SessionView(
        revision: 1,
        status: sessionStatus,
        queue: queue,
        agentCommands: [
          if (announcesMcp)
            const AgentCommandView(name: 'mcp', description: 'MCP servers'),
        ],
      ),
      id: id,
    );
    workspace.handles[handle.id] = handle;
    return handle;
  }

  group('page state and access (Q26, D5)', () {
    test('lists the servers of the layers in merge order with their source '
        'and kind, masked, and logs mcp_settings.loaded', () async {
      store.project = _layer([_playwright()]);
      store.projectLocal = _layer([
        {
          'name': 'docs-fs',
          'type': 'stdio',
          'command': 'npx',
          'args': ['--token', leakMarker],
          'env': {'LOG_LEVEL': 'debug'},
        },
      ]);

      final state = await ready(make());

      expect(state.rows.map((r) => r.name), [
        'github',
        'postgres',
        'playwright',
        'docs-fs',
      ]);
      expect(row(state, 'github').entry.kind, McpTransportKind.http);
      expect(row(state, 'github').sourceLabel, 'user');
      expect(row(state, 'docs-fs').sourceLabel, 'this project');
      expect(
        row(state, 'playwright').sourceLabel,
        'defined in ${FakeAgentConfigStore.projectPath}',
      );
      // «флаг значение»: значение после `--token` закрыто правилом ядра.
      expect(row(state, 'docs-fs').entry.args, isNot(contains(leakMarker)));
      expect(row(state, 'docs-fs').entry.masked, isTrue);
      expect(state.toString(), isNot(contains(leakMarker)));
      expect(opened.single.access.paths.codelabHome, _home);
      expect(event('mcp_settings.loaded'), {
        'servers': 4,
        'access': 'editable',
        'event': 'mcp_settings.loaded',
        'level': 'debug',
      });
    });

    test('an empty config is Ready with no rows and no card', () async {
      store.user = {};

      final state = await ready(make());

      expect(state.rows, isEmpty);
      expect(state.newServerOpen, isFalse);
      expect(state.rejected, isNull);
    });

    test('the secret backend and the project target are part of the '
        'state', () async {
      store.backend = const SecretBackendInfo(
        id: 'env',
        writable: false,
        unavailableReason: 'OS key stores are not available yet',
      );

      final state = await ready(make());

      expect(state.secretStorage.backendId, 'env');
      expect(state.secretStorage.writable, isFalse);
      expect(
        state.secretStorage.unavailableReason,
        'OS key stores are not available yet',
      );
      expect(state.canSaveToProject, isTrue);

      projectDir = '';
      expect((await ready(make())).canSaveToProject, isFalse);
    });

    test('a WebSocket agent is ReadOnly with only the panel, and the local '
        'config is not read', () async {
      connect(_remote, active: _s1);
      externalSession(id: _s1);

      final cubit = make();
      await cubit.reload();

      final state = cubit.state as McpSettingsReadOnly;
      expect(state.notice, 'Read-only: this agent runs on wss://devbox:7420.');
      expect(state.hint, contains('codelab mcp add'));
      expect(state.agentStatus, isA<McpAgentStatusText>());
      expect(opened, isEmpty);
      expect(store.snapshots, 0);
      expect(state.toString(), isNot(contains(leakMarker)));
    });

    test('a third-party stdio agent is ReadOnly', () async {
      connect(_foreign);

      final cubit = make();
      await cubit.reload();

      final state = cubit.state as McpSettingsReadOnly;
      expect(state.notice, 'Provider settings are managed by python.');
      expect(opened, isEmpty);
    });

    test('a user layer that cannot be read is Unreadable and is never '
        'written', () async {
      store.omitUserLayer = true;

      final cubit = make();
      await cubit.reload();

      expect(cubit.state, isA<McpSettingsUnreadable>());
      expect(events(), contains('mcp_settings.unreadable'));
      expect(await cubit.save(_newGithub()), isFalse);
      expect(store.applied, isEmpty);
      expect(session.mcpKeys.journal, isEmpty);
    });

    for (final kind in [
      ConfigIssueKind.syntax,
      ConfigIssueKind.profile,
      ConfigIssueKind.unknownKey,
      ConfigIssueKind.type,
    ]) {
      test('a ${kind.name} problem makes the page Unreadable with the loader '
          'problem and no write', () async {
        store.issues = [
          ConfigIssue(
            kind: kind,
            key: 'mcp.servers',
            source: FakeAgentConfigStore.userPath,
            message: 'the file does not follow the schema',
          ),
        ];

        final cubit = make();
        await cubit.reload();

        final state = cubit.state as McpSettingsUnreadable;
        expect(state.problems.single, contains('mcp.servers'));
        expect(await cubit.save(_newGithub()), isFalse);
        expect(store.applied, isEmpty);
      });
    }

    for (final kind in [
      ConfigIssueKind.value,
      ConfigIssueKind.semantic,
      ConfigIssueKind.inlineSecret,
    ]) {
      test('a ${kind.name} problem keeps the page Ready with the '
          'mcp-rejected content and the write available (scenario "page '
          'opened with a rejected config")', () async {
        store.issues = [_rejectedIssue(kind: kind)];

        final state = await ready(make());

        final rejected = state.rejected!;
        expect(rejected.title, 'The agent rejects the current config');
        expect(
          rejected.problems.single,
          contains('mcp.servers[postgres].env.DATABASE_URL'),
        );
        expect(rejected.editServer, 'postgres');
        expect(state.saving, isFalse);
        expect(state.rows, isNotEmpty);
        expect(store.applied, isEmpty);
      });
    }

    test('a missing key (start problem) neither blocks the page nor enters '
        'the rejected content', () async {
      store.user = {};
      store.issues = const [
        ConfigIssue(
          kind: ConfigIssueKind.value,
          key: 'agent.default_model',
          source: 'config',
          message:
              'no model is configured; add a provider with at least one model',
          // Rejections моста исключают `config.model.none` (Q29): это забота
          // страницы Providers.
          event: 'config.model.none',
        ),
      ];

      final state = await ready(make());

      expect(state.rejected, isNull);
    });

    test(
      'a snapshot that arrives after a newer load is dropped (D21)',
      () async {
        connect(embeddedConnectionProfile);
        final gate = Completer<void>();
        var opens = 0;
        onOpen = () => ++opens == 1 ? gate.future : null;
        final cubit = make();

        final first = cubit.reload();
        await cubit.reload();
        final states = <McpSettingsState>[];
        final subscription = cubit.stream.listen(states.add);
        final after = cubit.state;
        gate.complete();
        await first;
        await pumpEventQueue();

        expect(states, isEmpty);
        expect(cubit.state, same(after));
        await subscription.cancel();
      },
    );

    test('a snapshot that arrives after close() is dropped', () async {
      connect(embeddedConnectionProfile);
      final gate = Completer<void>();
      onOpen = () => gate.future;
      final cubit = make();

      final load = cubit.reload();
      await cubit.close();
      gate.complete();
      await load;

      expect(cubit.isClosed, isTrue);
    });
  });

  group('saving a server (D11, D21)', () {
    test('scenario "a server with a secret header": the value goes to the '
        'store before the config, the file gets only the reference and '
        'the log has no marker', () async {
      store.user = {};
      session.secrets.clear();
      store.onApply = () => session.mcpKeys.journal.add('apply');
      final cubit = make();
      await cubit.reload();
      cubit.openNewServer();

      final saved = await cubit.save(_newGithub());

      expect(saved, isTrue);
      // `stored` дважды: проверка занятости до записи и перепроверка в
      // `commit` (одно правило, `occupiedSecrets`).
      expect(session.mcpKeys.journal, [
        'stored $_authorization',
        'stored $_authorization',
        'write $_authorization',
        'apply',
      ]);
      expect(session.secrets[_authorization], 'Bearer $leakMarker');
      final apply = store.applied.single;
      expect(apply.base.path, FakeAgentConfigStore.userPath);
      final upsert = apply.edits.single as UpsertMcpServer;
      expect(upsert.server['headers'], {
        'Authorization': '\${secret:$_authorization}',
      });
      expect(upsert.toString(), isNot(contains(leakMarker)));
      final state = current(cubit);
      expect(state.newServerOpen, isFalse);
      expect(state.banner?.kind, McpBannerKind.saved);
      expect(state.rows.map((r) => r.name), ['github']);
      expect(event('mcp_settings.saved'), {
        'server': 'github',
        'type': 'http',
        'target': 'user',
        'stored_refs': 1,
        'replaced': 0,
        'cleanup_deleted': 0,
        'cleanup_kept': 0,
        'cleanup_failed': 0,
        'restart_required': false,
        'event': 'mcp_settings.saved',
        'level': 'info',
      });
      final text = logger.entries.toString();
      expect(text, isNot(contains(leakMarker)));
      expect(text, isNot(contains(_authorization)));
      expect(text, isNot(contains('api.example.test')));
      expect(state.toString(), isNot(contains(leakMarker)));
    });

    test('a new server can be written to the local project file', () async {
      store.projectLocal = {};
      final cubit = make();
      await cubit.reload();

      await cubit.save(
        _newGithub(name: 'fresh', headers: const {}),
        target: ConfigLayer.projectLocal,
      );

      expect(
        store.applied.single.base.path,
        FakeAgentConfigStore.projectLocalPath,
      );
      expect(event('mcp_settings.saved')['target'], 'local');
    });

    test('a save to the project layer without a project folder writes '
        'nothing', () async {
      projectDir = '';
      final cubit = make();
      await cubit.reload();

      final saved = await cubit.save(
        _newGithub(name: 'fresh', headers: const {}),
        target: ConfigLayer.projectLocal,
      );

      expect(saved, isFalse);
      expect(store.applied, isEmpty);
      expect(current(cubit).banner?.kind, McpBannerKind.error);
      // Причина — именно нет папки проекта, а не нечитаемый слой (SETUP-3).
      expect(event('mcp_settings.save_failed')['refusal'], 'noProjectTarget');
    });

    test('a taken name is a draft problem before commit: nothing is written, '
        'not even the secret (validate with existingNames)', () async {
      final cubit = make();
      await cubit.reload();
      cubit.openNewServer();

      final saved = await cubit.save(_newGithub(name: 'postgres'));

      expect(saved, isFalse);
      final issues = current(cubit).draftIssues!;
      expect(issues.server, isNull);
      expect(
        issues.problems.single.message,
        'A server with this name already exists.',
      );
      expect(store.applied, isEmpty);
      expect(session.mcpKeys.journal, isEmpty);
      expect(current(cubit).newServerOpen, isTrue);
    });

    test(
      'an invalid draft is reported as problems and is not committed',
      () async {
        final cubit = make();
        await cubit.reload();

        final saved = await cubit.save(
          McpServerDraft(name: 'bad name', kind: McpTransportKind.stdio),
        );

        expect(saved, isFalse);
        expect(
          current(cubit).draftIssues!.problems.map((p) => p.message),
          contains('Use a name without spaces, [, ] or ".'),
        );
        expect(store.applied, isEmpty);
      },
    );

    test('an existing secret asks "Replace it" with its name before any '
        'write; the chosen name goes to replaceSecrets', () async {
      final cubit = make();
      await cubit.reload();
      // Сервер `GitHub` даёт то же имя секрета, что и `github`.
      final draft = _newGithub(name: 'GitHub');

      final first = await cubit.save(draft);

      expect(first, isFalse);
      expect(session.mcpKeys.journal, ['stored $_authorization']);
      expect(current(cubit).replaceQuestion!.names, [_authorization]);
      expect(current(cubit).replaceQuestion!.server, isNull);
      expect(store.applied, isEmpty);
      expect(session.mcpKeys.journal, isNot(contains('write $_authorization')));
      expect(session.secrets[_authorization], leakMarker);

      final second = await cubit.save(draft, replaceSecrets: {_authorization});

      expect(second, isTrue);
      expect(session.secrets[_authorization], 'Bearer $leakMarker');
      expect(current(cubit).replaceQuestion, isNull);
      expect(event('mcp_settings.saved')['replaced'], 1);
      expect(logger.entries.toString(), isNot(contains(_authorization)));
    });

    test('the question can be dismissed without a write', () async {
      final cubit = make();
      await cubit.reload();
      await cubit.save(_newGithub(name: 'GitHub'));

      cubit.dismissReplaceQuestion();

      expect(current(cubit).replaceQuestion, isNull);
      expect(store.applied, isEmpty);
    });

    test('a secret that appears after the question (McpSecretAppeared) '
        'asks the same question and writes nothing', () async {
      session.secrets[_authorization] = 'created-elsewhere';
      session.mcpKeys.hideFirstStored.add(_authorization);
      final cubit = make();
      await cubit.reload();

      final saved = await cubit.save(_newGithub(name: 'GitHub'));

      expect(saved, isFalse);
      expect(current(cubit).replaceQuestion!.names, [_authorization]);
      expect(store.applied, isEmpty);
      expect(session.secrets[_authorization], 'created-elsewhere');
    });

    test(
      'a refused secret write shows an error and writes no config',
      () async {
        session.mcpKeys.refusal = 'the store is read-only';
        final cubit = make();
        await cubit.reload();

        final saved = await cubit.save(_newGithub(name: 'fresh'));

        expect(saved, isFalse);
        expect(current(cubit).banner?.kind, McpBannerKind.error);
        expect(store.applied, isEmpty);
        expect(event('mcp_settings.save_failed')['outcome'], 'secret_failed');
      },
    );

    test('a conflict shows the banner, rolls back the new secret, re-reads '
        'and does not retry (SETUP-6)', () async {
      store.user = {};
      session.secrets.clear();
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final cubit = make();
      await cubit.reload();
      cubit.openNewServer();
      final before = store.snapshots;

      final saved = await cubit.save(_newGithub());

      expect(saved, isFalse);
      expect(store.applied, hasLength(1));
      expect(store.snapshots, greaterThan(before));
      expect(session.secrets, isNot(contains(_authorization)));
      final state = current(cubit);
      expect(state.banner?.kind, McpBannerKind.conflict);
      expect(state.saving, isFalse);
      // Форма остаётся открытой: пользователь повторит запись сам.
      expect(state.newServerOpen, isTrue);
      expect(event('mcp_settings.save_failed'), {
        'server': 'github',
        'operation': 'save',
        'outcome': 'conflict',
        'rollback': 'deleted',
        'event': 'mcp_settings.save_failed',
        'level': 'warning',
      });
    });

    test('rejected and inline-secret outcomes are error banners with the '
        'outcome kind in the log, without texts', () async {
      final cubit = make();
      await cubit.reload();
      final outcomes = <ConfigSaveOutcome, String>{
        ConfigRejected([
          ConfigIssue(
            kind: ConfigIssueKind.value,
            key: 'mcp.servers',
            source: 'x',
            message: 'bad $leakMarker',
          ),
        ]): 'rejected',
        const ConfigInlineSecret(
          key: 'mcp.servers[x].env.TOKEN',
          suggestedSecretName: 'codelab/mcp/x/token',
        ): 'inline_secret',
      };
      for (final MapEntry(:key, :value) in outcomes.entries) {
        store.nextOutcome = key;

        await cubit.save(_newGithub(name: 'x', headers: const {}));

        expect(current(cubit).banner?.kind, McpBannerKind.error);
        expect(event('mcp_settings.save_failed')['outcome'], value);
      }
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
    });

    test('an exception of the writer is logged as its type only', () async {
      store.onApply = () => throw StateError('boom $leakMarker');
      final cubit = make();
      await cubit.reload();

      await cubit.save(_newGithub(name: 'x', headers: const {}));

      final failed = event('mcp_settings.save_failed');
      expect(failed['outcome'], 'error');
      expect(failed['error_type'], 'StateError');
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
      expect(current(cubit).toString(), isNot(contains(leakMarker)));
    });

    test(
      'a second save during the write is ignored, the first completes',
      () async {
        final gate = Completer<void>();
        store.onApply = () => gate.future;
        final cubit = make();
        await cubit.reload();

        final first = cubit.save(_newGithub(name: 'x', headers: const {}));
        await pumpEventQueue();
        expect(current(cubit).saving, isTrue);
        final second = await cubit.save(
          _newGithub(name: 'y', headers: const {}),
        );
        gate.complete();

        expect(second, isFalse);
        expect(await first, isTrue);
        expect(store.applied, hasLength(1));
        expect(current(cubit).saving, isFalse);
      },
    );

    test('scenario "a config rejected by the agent": the file is written, '
        'the mcp-rejected content names the key path and the server, no '
        'prompt goes to the session', () async {
      final handle = externalSession(id: _s1);
      connect(embeddedConnectionProfile, active: _s1);
      store.onApply = () => store.issues = [_rejectedIssue()];
      final cubit = make();
      await cubit.reload();

      final saved = await cubit.save(
        McpServerDraft(
          name: 'postgres2',
          kind: McpTransportKind.stdio,
          command: 'uvx',
          env: {'DATABASE_URL': McpValueDraft.text(r'${PG_URL}')},
        ),
      );

      expect(saved, isTrue);
      final rejected = current(cubit).rejected!;
      expect(rejected.title, 'Saved, but the agent rejected the new config');
      expect(
        rejected.problems.single,
        contains('mcp.servers[postgres].env.DATABASE_URL'),
      );
      expect(rejected.editServer, 'postgres');
      expect(handle.sent, isEmpty);
      expect(event('mcp_settings.rejected_after_save'), {
        'server': 'postgres2',
        'issues': 1,
        'event': 'mcp_settings.rejected_after_save',
        'level': 'warning',
      });
    });

    test('warnings of ConfigSaved are shown in the saved banner', () async {
      store.nextOutcome = ConfigSaved(
        fingerprint: 'fp',
        warnings: [_rejectedIssue()],
        restartRequiredKeys: const [],
      );
      final cubit = make();
      await cubit.reload();

      await cubit.save(_newGithub(name: 'x', headers: const {}));

      final banner = current(cubit).banner!;
      expect(banner.kind, McpBannerKind.saved);
      expect(banner.lines.join('\n'), contains('variable PG_URL is not set'));
    });

    test('editing writes the whole raw element of its own layer: unknown '
        'keys stay, the stored secret is not touched, "Save to" is ignored '
        '(Q27)', () async {
      store.projectLocal = {};
      final cubit = make();
      await cubit.reload();
      final draft = cubit.draftFor('github')!;
      expect(draft.headers['Authorization'], isA<McpStoredSecret>());

      final saved = await cubit.save(
        draft.copyWith(url: 'https://other.example.test/mcp/'),
        target: ConfigLayer.projectLocal,
      );

      expect(saved, isTrue);
      expect(store.applied.single.base.path, FakeAgentConfigStore.userPath);
      final element =
          (store.applied.single.edits.single as UpsertMcpServer).server;
      expect(element['url'], 'https://other.example.test/mcp/');
      expect(element['call_timeout'], 30);
      expect(element['headers'], {
        'Authorization': '\${secret:$_authorization}',
      });
      expect(session.isSetCalls, isEmpty);
      expect(session.mcpKeys.journal, isEmpty);
    });

    test('a changed name is a draft problem and nothing is written', () async {
      final cubit = make();
      await cubit.reload();

      final saved = await cubit.save(
        cubit.draftFor('github')!.copyWith(name: 'github2'),
      );

      expect(saved, isFalse);
      final issues = current(cubit).draftIssues!;
      expect(issues.server, 'github');
      expect(
        issues.problems.single.message,
        'Remove the server and add it again to rename it.',
      );
      expect(store.applied, isEmpty);
    });

    test('a project-layer server has no draft to edit', () async {
      store.project = _layer([_playwright()]);
      final cubit = make();
      await cubit.reload();

      final state = current(cubit);
      expect(row(state, 'playwright').canEdit, isFalse);
      expect(
        await cubit.save(McpServerDraft.fromElement(_playwright())),
        isFalse,
      );
      expect(store.applied, isEmpty);
    });

    test(
      'Add server opens one card; a second call changes nothing; Cancel '
      'closes it without a write (scenario "new server and cancel")',
      () async {
        final cubit = make();
        await cubit.reload();
        final states = <McpSettingsState>[];
        final subscription = cubit.stream.listen(states.add);

        cubit.openNewServer();
        cubit.openNewServer();
        await pumpEventQueue();

        expect(current(cubit).newServerOpen, isTrue);
        expect(states, hasLength(1));

        cubit.cancelNewServer();
        await pumpEventQueue();

        expect(current(cubit).newServerOpen, isFalse);
        expect(store.applied, isEmpty);
        await subscription.cancel();
      },
    );
  });

  group('toggle, "Disable here" and "Enable here" (Q21)', () {
    test('toggle writes the whole raw element of the server layer with the '
        'changed enabled', () async {
      final cubit = make();
      await cubit.reload();

      final done = await cubit.setEnabled('github', enabled: false);

      expect(done, isTrue);
      final apply = store.applied.single;
      expect(apply.base.path, FakeAgentConfigStore.userPath);
      expect((apply.edits.single as UpsertMcpServer).server, {
        ..._github(),
        'enabled': false,
      });
      expect(row(current(cubit), 'github').enabled, isFalse);
      expect(event('mcp_settings.toggled'), {
        'server': 'github',
        'action': 'disable',
        'target': 'user',
        'event': 'mcp_settings.toggled',
        'level': 'info',
      });
    });

    test('a project-layer server cannot be toggled or removed', () async {
      store.project = _layer([_playwright()]);
      store.projectLocal = {};
      final cubit = make();
      final state = await ready(cubit);

      final playwright = row(state, 'playwright');
      expect(playwright.canToggle, isFalse);
      expect(playwright.canRemove, isFalse);
      expect(playwright.canDisableHere, isTrue);
      expect(await cubit.setEnabled('playwright', enabled: false), isFalse);
      expect(await cubit.remove('playwright'), isFalse);
      expect(store.applied, isEmpty);
      expect(
        playwright.note,
        'playwright comes from the project file: it can\'t be edited or '
        'removed here; "Disable here" writes enabled: false to '
        '.codelab/config.local.yaml.',
      );
    });

    test('scenario "project layer server": Disable here writes only '
        '{name, enabled: false} to the local file; the row shows disabled '
        'here', () async {
      store.project = _layer([_playwright()]);
      store.projectLocal = {};
      final cubit = make();
      await cubit.reload();

      final done = await cubit.disableHere('playwright');

      expect(done, isTrue);
      final apply = store.applied.single;
      expect(apply.base.path, FakeAgentConfigStore.projectLocalPath);
      expect((apply.edits.single as UpsertMcpServer).server, {
        'name': 'playwright',
        'enabled': false,
      });
      final playwright = row(current(cubit), 'playwright');
      expect(playwright.entry.disabledHere, isTrue);
      expect(playwright.canEnableHere, isTrue);
      expect(playwright.canDisableHere, isFalse);
      expect(playwright.canRemove, isFalse);
      expect(
        playwright.note,
        'playwright is disabled in .codelab/config.local.yaml. "Enable here" '
        'removes this override.',
      );
      expect(event('mcp_settings.toggled')['action'], 'disable_here');
      expect(event('mcp_settings.toggled')['target'], 'local');
    });

    test('scenario "Enable here": the override is removed from the local '
        'file, the project file is untouched', () async {
      store.project = _layer([_playwright()]);
      store.projectLocal = _layer([
        {'name': 'playwright', 'enabled': false},
      ]);
      final cubit = make();
      final state = await ready(cubit);
      expect(row(state, 'playwright').canEnableHere, isTrue);

      final done = await cubit.enableHere('playwright');

      expect(done, isTrue);
      final apply = store.applied.single;
      expect(apply.base.path, FakeAgentConfigStore.projectLocalPath);
      expect(apply.edits.single, const RemoveMcpServer('playwright'));
      final playwright = row(current(cubit), 'playwright');
      expect(playwright.entry.disabledHere, isFalse);
      expect(playwright.enabled, isTrue);
      expect(event('mcp_settings.toggled')['action'], 'enable_here');
    });

    test('Disable here without a project folder is a banner and no write '
        '(McpServerRefused noProjectTarget)', () async {
      store.project = _layer([_playwright()]);
      store.projectLocal = {};
      projectDir = '';
      final cubit = make();
      await cubit.reload();

      final done = await cubit.disableHere('playwright');

      expect(done, isFalse);
      expect(current(cubit).banner?.kind, McpBannerKind.error);
      expect(store.applied, isEmpty);
      final failed = event('mcp_settings.save_failed');
      expect(failed['operation'], 'toggle');
      expect(failed['outcome'], 'refused');
      expect(failed['refusal'], 'noProjectTarget');
    });

    test('Disable here with an unreadable local file is a banner and no '
        'write (layerUnreadable)', () async {
      store.project = _layer([_playwright()]);
      // Слоя `projectLocal` нет в снимке: файл не разобрался.
      store.omitProjectLocalLayer = true;
      final cubit = make();
      await cubit.reload();

      final done = await cubit.disableHere('playwright');

      expect(done, isFalse);
      expect(current(cubit).banner?.kind, McpBannerKind.error);
      expect(store.applied, isEmpty);
      expect(event('mcp_settings.save_failed')['refusal'], 'layerUnreadable');
    });
  });

  group('removal (Q22, Q25 (3), (4))', () {
    setUp(() {
      store.user = _layer([
        _github(),
        // Секрет `codelab/mcp/github/token` принадлежит другому серверу.
        {
          'name': 'GitHub',
          'type': 'http',
          'url': 'https://other.example.test/mcp/',
          'headers': {'X-Token': r'${secret:codelab/mcp/github/token}'},
        },
        {
          'name': 'docs',
          'type': 'stdio',
          'command': 'docs-mcp',
          'env': {'TOKEN': r'${secret:team/docs-token}'},
        },
      ]);
      session.secrets
        ..['codelab/mcp/github/token'] = 'other'
        ..['team/docs-token'] = 'manual';
    });

    test('scenario "removal confirmation": the plan names only the page '
        'secrets and nothing is written until Remove', () async {
      final cubit = make();
      await cubit.reload();

      final plan = cubit.removalPlan('github')!;

      expect(plan.server, 'github');
      expect(plan.secrets, [_authorization]);
      expect(cubit.removalPlan('docs')!.secrets, isEmpty);
      expect(cubit.removalPlan('unknown'), isNull);
      expect(store.applied, isEmpty);
      expect(session.mcpKeys.journal, isEmpty);
      expect(session.secrets, hasLength(3));
    });

    test('a project-layer server has no removal plan', () async {
      store.project = _layer([_playwright()]);
      final cubit = make();
      await cubit.reload();

      expect(cubit.removalPlan('playwright'), isNull);
    });

    test('scenario "removal with secrets": the element goes first, then only '
        'the page secret nobody references; the log has counts only', () async {
      store.onApply = () => session.mcpKeys.journal.add('apply');
      final cubit = make();
      await cubit.reload();

      final done = await cubit.remove('github');

      expect(done, isTrue);
      expect(
        store.applied.single.edits.single,
        const RemoveMcpServer('github'),
      );
      expect(session.mcpKeys.journal, ['apply', 'delete $_authorization']);
      expect(session.secrets, isNot(contains(_authorization)));
      expect(session.secrets, contains('codelab/mcp/github/token'));
      final state = current(cubit);
      expect(state.banner?.kind, McpBannerKind.saved);
      expect(state.banner?.lines, ['Server github removed.']);
      expect(state.rows.map((r) => r.name), ['GitHub', 'docs']);
      expect(event('mcp_settings.removed'), {
        'server': 'github',
        'cleanup_deleted': 1,
        'cleanup_kept': 0,
        'cleanup_failed': 0,
        'event': 'mcp_settings.removed',
        'level': 'info',
      });
      expect(logger.entries.toString(), isNot(contains(_authorization)));
    });

    test('scenario "a manual secret stays": kept with its name in the '
        'banner, counted, not logged', () async {
      final cubit = make();
      await cubit.reload();

      await cubit.remove('docs');

      expect(session.secrets, contains('team/docs-token'));
      expect(current(cubit).banner?.kind, McpBannerKind.saved);
      expect(current(cubit).banner?.lines, [
        'Server docs removed.',
        'team/docs-token is kept: it was not created by this page.',
      ]);
      expect(event('mcp_settings.removed')['cleanup_kept'], 1);
      expect(logger.entries.toString(), isNot(contains('team/docs-token')));
    });

    test(
      'a secret still referenced elsewhere is kept with its own line',
      () async {
        store.user = _layer([
          _github(),
          {
            'name': 'mirror',
            'type': 'http',
            'url': 'https://mirror.example.test/mcp/',
            'headers': {'Authorization': '\${secret:$_authorization}'},
          },
        ]);
        final cubit = make();
        await cubit.reload();

        await cubit.remove('github');

        expect(session.secrets, contains(_authorization));
        expect(current(cubit).banner?.kind, McpBannerKind.saved);
        expect(current(cubit).banner?.lines, [
          'Server github removed.',
          '$_authorization is kept because other settings still use it.',
        ]);
        expect(event('mcp_settings.removed')['cleanup_kept'], 1);
      },
    );

    test('a secret that cannot be deleted makes an error banner with the '
        'command to delete it by hand', () async {
      session.mcpKeys.deletion = SecretDeletion.failed;
      final cubit = make();
      await cubit.reload();

      final done = await cubit.remove('github');

      expect(done, isTrue);
      final banner = current(cubit).banner!;
      expect(banner.kind, McpBannerKind.error);
      expect(banner.lines, [
        'Server github removed.',
        '$_authorization could not be deleted. Delete it with: '
            'codelab secret delete $_authorization',
      ]);
      expect(event('mcp_settings.removed')['cleanup_failed'], 1);
    });

    test('a refused write keeps the server and every secret', () async {
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final cubit = make();
      await cubit.reload();

      final done = await cubit.remove('github');

      expect(done, isFalse);
      expect(session.mcpKeys.journal, isEmpty);
      expect(session.secrets, hasLength(3));
      expect(current(cubit).banner?.kind, McpBannerKind.conflict);
      expect(current(cubit).rows.map((r) => r.name), contains('github'));
      final failed = event('mcp_settings.save_failed');
      expect(failed['operation'], 'remove');
      expect(failed['outcome'], 'conflict');
    });
  });

  group('review 5b fixes', () {
    test('an exception of the secret store during Save is an error banner, '
        'a log event with the type only, and Save works again', () async {
      session.mcpKeys.storedError = StateError('boom $leakMarker');
      final cubit = make();
      await cubit.reload();

      final saved = await cubit.save(_newGithub(name: 'fresh'));

      expect(saved, isFalse);
      final state = current(cubit);
      expect(state.banner?.kind, McpBannerKind.error);
      expect(state.saving, isFalse);
      expect(store.applied, isEmpty);
      final failed = event('mcp_settings.save_failed');
      expect(failed['outcome'], 'error');
      expect(failed['operation'], 'save');
      expect(failed['error_type'], 'StateError');
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
      expect(state.toString(), isNot(contains(leakMarker)));
      expect(state.banner.toString(), isNot(contains('boom')));

      session.mcpKeys.storedError = null;
      session.secrets.clear();
      expect(await cubit.save(_newGithub(name: 'fresh')), isTrue);
    });

    test(
      'an exception while the default profile is read is not lost',
      () async {
        defaultProfileError = StateError('boom $leakMarker');
        final cubit = make();

        await cubit.reload();

        expect(cubit.state, isA<McpSettingsUnreadable>());
        final unreadable = event('mcp_settings.unreadable');
        expect(unreadable['error_type'], 'StateError');
        expect(logger.entries.toString(), isNot(contains(leakMarker)));
      },
    );

    test('a draft problem and a secret that appeared are logged as '
        'save_failed with their outcome', () async {
      final cubit = make();
      await cubit.reload();

      await cubit.save(_newGithub(name: 'postgres'));

      expect(event('mcp_settings.save_failed'), {
        'server': 'postgres',
        'operation': 'save',
        'outcome': 'invalid',
        'event': 'mcp_settings.save_failed',
        'level': 'warning',
      });

      session.secrets[_authorization] = 'created-elsewhere';
      session.mcpKeys.hideFirstStored.add(_authorization);
      await cubit.save(_newGithub(name: 'GitHub'));

      expect(event('mcp_settings.save_failed')['outcome'], 'secret_appeared');
      expect(event('mcp_settings.save_failed')['operation'], 'save');
    });

    test('a connection that changed during Save stops the write with a '
        'banner', () async {
      final gate = Completer<void>();
      session.mcpKeys.onStored = () => gate.future;
      final cubit = make();
      await cubit.reload();

      final saving = cubit.save(_newGithub(name: 'fresh'));
      await pumpEventQueue();
      session.mcpKeys.onStored = null;
      await cubit.reload();
      gate.complete();
      final saved = await saving;

      expect(saved, isFalse);
      expect(store.applied, isEmpty);
      expect(
        session.mcpKeys.journal.where((e) => e.startsWith('write')),
        isEmpty,
      );
      expect(current(cubit).banner?.kind, McpBannerKind.error);
      expect(current(cubit).saving, isFalse);
    });

    test('a secret orphaned by an edit is deleted after the write and the '
        'banner names the ones that stay or fail (LOW-2)', () async {
      final cubit = make();
      await cubit.reload();
      final plain = cubit
          .draftFor('github')!
          .copyWith(headers: {'Authorization': McpValueDraft.text('plain')});

      final saved = await cubit.save(plain);

      expect(saved, isTrue);
      expect(session.secrets, isNot(contains(_authorization)));
      expect(current(cubit).banner?.kind, McpBannerKind.saved);
      expect(current(cubit).banner?.lines, ['Server github saved.']);
      expect(event('mcp_settings.saved')['cleanup_deleted'], 1);
      expect(logger.entries.toString(), isNot(contains(_authorization)));
    });

    test('an orphaned secret that cannot be deleted is an error banner with '
        'the command', () async {
      session.mcpKeys.deletion = SecretDeletion.failed;
      final cubit = make();
      await cubit.reload();
      final plain = cubit
          .draftFor('github')!
          .copyWith(headers: {'Authorization': McpValueDraft.text('plain')});

      await cubit.save(plain);

      expect(current(cubit).banner?.kind, McpBannerKind.error);
      expect(
        current(cubit).banner?.lines,
        contains(
          '$_authorization could not be deleted. Delete it with: '
          'codelab secret delete $_authorization',
        ),
      );
      expect(event('mcp_settings.saved')['cleanup_failed'], 1);
    });

    test('a refused write whose rollback failed names the leftover secret; a '
        'replaced secret is reported too (D9)', () async {
      store.user = {};
      session.secrets.clear();
      session.mcpKeys.deletion = SecretDeletion.failed;
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      final cubit = make();
      await cubit.reload();

      await cubit.save(_newGithub());

      final lines = current(cubit).banner!.lines.join('\n');
      expect(lines, contains('codelab secret delete $_authorization'));
      expect(lines, isNot(contains(leakMarker)));

      session.secrets[_authorization] = 'old';
      store.nextOutcome = const ConfigConflict(FakeAgentConfigStore.userPath);
      await cubit.save(_newGithub(), replaceSecrets: {_authorization});

      expect(
        current(cubit).banner!.lines.join('\n'),
        contains('$_authorization was already replaced'),
      );
    });

    test(
      'an exception AFTER the write began resets saving, shows an error '
      'banner and the next write works (toggle, remove, Enable here)',
      () async {
        final cubit = make();
        await cubit.reload();
        session.portError = StateError('boom $leakMarker');

        for (final (operation, run) in <(String, Future<bool> Function())>[
          ('toggle', () => cubit.setEnabled('github', enabled: false)),
          ('remove', () => cubit.remove('github')),
          ('toggle', () => cubit.enableHere('github')),
        ]) {
          expect(await run(), isFalse, reason: operation);

          final state = current(cubit);
          expect(state.saving, isFalse, reason: operation);
          expect(state.banner?.kind, McpBannerKind.error, reason: operation);
          final failed = event('mcp_settings.save_failed');
          expect(failed['operation'], operation);
          expect(failed['outcome'], 'error');
          expect(failed['error_type'], 'StateError');
          expect(state.banner.toString(), isNot(contains('boom')));
          expect(logger.entries.toString(), isNot(contains(leakMarker)));
        }

        session.portError = null;
        expect(await cubit.setEnabled('github', enabled: false), isTrue);
        expect(store.applied, hasLength(1));
      },
    );

    test('a queued /mcp prompt is removed from the queue even when the page '
        'was closed or the session changed meanwhile (L-2)', () async {
      final handle = externalSession(id: _s1);
      connect(_ownAgent, active: _s1);
      final cubit = make();
      await cubit.reload();
      final reply = Completer<PromptOutcome>();
      handle.onSend = (_) => reply.future;

      final pending = cubit.refresh();
      await pumpEventQueue();
      externalSession(id: _s2);
      connect(_ownAgent, active: _s2);
      reply.complete(
        PromptQueued(_s1, const QueuedPrompt(id: 'q1', text: '/mcp list')),
      );
      await pending;
      expect(handle.removedFromQueue, ['q1']);

      final second = externalSession(id: _s1);
      connect(_ownAgent, active: _s1);
      final closing = Completer<PromptOutcome>();
      second.onSend = (_) => closing.future;
      final late = cubit.refresh();
      await pumpEventQueue();
      await cubit.close();
      closing.complete(
        PromptQueued(_s1, const QueuedPrompt(id: 'q2', text: '/mcp list')),
      );
      await late;

      expect(second.removedFromQueue, ['q2']);
    });

    test('a connection that changed during Save is logged as a stale save '
        '(LOW-4)', () async {
      final gate = Completer<void>();
      session.mcpKeys.onStored = () => gate.future;
      final cubit = make();
      await cubit.reload();

      final saving = cubit.save(_newGithub(name: 'fresh'));
      await pumpEventQueue();
      session.mcpKeys.onStored = null;
      await cubit.reload();
      gate.complete();
      await saving;

      final failed = event('mcp_settings.save_failed');
      expect(failed['operation'], 'save');
      expect(failed['outcome'], 'stale');
      expect(failed['server'], 'fresh');
    });

    test('the editor reports a rejected draft through the Cubit: the problem '
        'is in the state and the event is save_failed invalid', () async {
      final cubit = make();
      await cubit.reload();
      cubit.openNewServer();

      cubit.rejectDraft(
        server: null,
        name: 'fresh',
        problems: const [
          McpDraftProblem(McpDraftField.headers, 'Two values are named X.'),
        ],
      );

      final issues = current(cubit).draftIssues!;
      expect(issues.server, isNull);
      expect(issues.problems.single.message, 'Two values are named X.');
      expect(event('mcp_settings.save_failed'), {
        'server': 'fresh',
        'operation': 'save',
        'outcome': 'invalid',
        'event': 'mcp_settings.save_failed',
        'level': 'warning',
      });
      expect(store.applied, isEmpty);
    });

    test('a queued prompt that already left the queue is logged as '
        'already_sent', () async {
      final handle = externalSession(id: _s1);
      connect(_ownAgent, active: _s1);
      handle.queueKeepsItem = false;
      handle.onSend = (_) async =>
          PromptQueued(_s1, const QueuedPrompt(id: 'q9', text: '/mcp list'));
      final cubit = make();
      await cubit.reload();

      await cubit.refresh();

      expect(handle.removedFromQueue, ['q9']);
      expect(event('mcp_settings.command_discarded'), {
        'command': 'list',
        'reason': 'already_sent',
        'session_id': 's1',
        'event': 'mcp_settings.command_discarded',
        'level': 'debug',
      });
      expect((status(cubit) as McpAgentStatusText).notice, _listFailed);
    });

    test('a refused second secret rolls back the first; when the rollback '
        'fails the banner names exactly the leftover (L-4)', () async {
      store.user = {};
      session.secrets.clear();
      session.mcpKeys
        ..refusal = 'the store is read-only'
        ..refuseOnly = 'codelab/mcp/fresh/b'
        ..deletion = SecretDeletion.failed;
      final cubit = make();
      await cubit.reload();

      await cubit.save(
        McpServerDraft(
          name: 'fresh',
          kind: McpTransportKind.http,
          url: 'https://api.example.test/mcp/',
          headers: {
            'A': McpValueDraft.secret(SecretValue('one')),
            'B': McpValueDraft.secret(SecretValue('two')),
          },
        ),
      );

      final lines = current(cubit).banner!.lines;
      expect(current(cubit).banner?.kind, McpBannerKind.error);
      expect(
        lines,
        contains(
          'codelab/mcp/fresh/a could not be deleted. Delete it with: '
          'codelab secret delete codelab/mcp/fresh/a',
        ),
      );
      expect(lines.join('\n'), isNot(contains('fresh/b could not')));
      final failed = event('mcp_settings.save_failed');
      expect(failed['outcome'], 'secret_failed');
      expect(failed['rollback'], 'failed');
      expect(store.applied, isEmpty);
    });

    test('no mcp_settings event field is masked by the log redactor, so the '
        'counters stay numbers (smoke 5b)', () async {
      final cubit = make();
      await cubit.reload();
      final plain = cubit
          .draftFor('github')!
          .copyWith(headers: {'Authorization': McpValueDraft.text('plain')});
      await cubit.save(plain);
      await cubit.save(_newGithub(name: 'fresh'));
      await cubit.remove('postgres');

      final events = [
        for (final e in logger.entries)
          if ('${e['event']}'.startsWith('mcp_settings.')) e,
      ];
      expect(events, isNotEmpty);
      for (final entry in events) {
        expect(
          const SecretRedactor().redactMap(Map.of(entry)),
          entry,
          reason: '${entry['event']}',
        );
      }
      final saved = event('mcp_settings.saved');
      expect(saved['cleanup_deleted'], isA<int>());
      expect(saved['stored_refs'], isA<int>());
    });

    test('the reload after a passed write failed: the saved event is still '
        'written, restart_required false (review 6a)', () async {
      store.user = {};
      session.secrets.clear();
      store.onApply = () => store.snapshotError = StateError('boom');
      final cubit = make();
      await cubit.reload();
      store.onApply = () => store.snapshotError = StateError('boom');

      await cubit.save(_newGithub(name: 'fresh', headers: const {}));

      expect(event('mcp_settings.saved')['restart_required'], isFalse);
      expect(events().where((e) => e == 'mcp_settings.save_failed'), isEmpty);
    });

    test('an exception after a passed write reaches _exclusive: the write '
        'stays saved — one saved event, no save_failed, no error banner '
        '(review 6a)', () async {
      store.user = {};
      session.secrets.clear();
      final cubit = make();
      await cubit.reload();
      // Сборка состояния после записи бросает один раз (после `commit`).
      store.onApply = () => session.backendErrorOnce = StateError('boom');

      final saved = await cubit.save(
        _newGithub(name: 'fresh', headers: const {}),
      );

      expect(saved, isTrue);
      final state = current(cubit);
      expect(state.banner?.kind, McpBannerKind.saved);
      expect(state.banner?.lines.first, 'Server fresh saved.');
      expect(state.saving, isFalse);
      expect(
        logger.entries.where((e) => e['event'] == 'mcp_settings.saved'),
        hasLength(1),
      );
      expect(
        logger.entries.where((e) => e['event'] == 'mcp_settings.save_failed'),
        isEmpty,
      );
    });

    test('an exception after a passed switch or Remove keeps the write: no '
        'error banner, no save_failed (review 6a)', () async {
      final cubit = make();
      await cubit.reload();
      // Сборка состояния бросает один раз — после записи, внутри `apply`.
      store.onApply = () =>
          session.backendErrorOnce = StateError('boom $leakMarker');

      expect(await cubit.setEnabled('github', enabled: false), isTrue);

      expect(current(cubit).banner?.kind, isNot(McpBannerKind.error));
      expect(current(cubit).saving, isFalse);

      await cubit.reload();
      store.onApply = () =>
          session.backendErrorOnce = StateError('boom $leakMarker');

      expect(await cubit.remove('postgres'), isTrue);

      expect(current(cubit).banner?.lines.first, 'Server postgres removed.');
      expect(
        logger.entries.where((e) => e['event'] == 'mcp_settings.save_failed'),
        isEmpty,
      );
      // Позднее исключение после успешной записи не теряется: предупреждение
      // с типом исключения, без текста (ревью 6a).
      final hint = logger.entries.where(
        (e) => e['event'] == 'mcp_settings.restart_hint_failed',
      );
      expect(hint, hasLength(2));
      expect(hint.every((e) => e['error_type'] == 'StateError'), isTrue);
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
    });

    test(
      'a row carries its ready draft (the page does not build it)',
      () async {
        final state = await ready(make());

        expect(row(state, 'github').draft?.name, 'github');
        expect(
          row(state, 'github').draft?.headers['Authorization'],
          isA<McpStoredSecret>(),
        );
      },
    );

    test('the state of the session is re-read before /mcp is sent', () async {
      final handle = externalSession(id: _s1);
      connect(_ownAgent, active: _s1);
      final cubit = make();
      await cubit.reload();

      // Ход начался, а событие `view` ещё не пришло.
      handle.current = const SessionView(
        revision: 2,
        status: SessionStatusView.running,
        agentCommands: [AgentCommandView(name: 'mcp', description: 'MCP')],
      );
      await cubit.refresh();

      expect(handle.sent, isEmpty);
    });
  });

  // Задача 6.1b-2 change `add-provider-setup-ui` (Q31; design.md D11
  // «Итерация 6: сервер, отложенный до перезапуска»): признак даёт настоящая
  // функция моста `restartRequiredServers(before, after)` по снимкам
  // настоящего `FileAgentConfigStore` (правило ядра `planConfigReload`), а не
  // мок. Красные до реализации в `McpSettingsCubit` и до функции моста
  // (задача 6.1b-1).
  group('a server that starts only after Restart agent (6.1b-2, Q31)', () {
    late Directory root;
    late RealConfigSession real;

    const restartSaved =
        'Server fresh saved. It starts after Restart agent '
        '(Settings › Connection).';

    setUp(() async {
      root = Directory.systemTemp.createTempSync('codelab_mcp_restart_');
      addTearDown(() => root.deleteSync(recursive: true));
      Directory('${root.path}/home').createSync();
      Directory('${root.path}/project').createSync();
    });

    Future<McpSettingsCubit> openReal({
      String config = realHomeConfig,
      bool agentConnected = true,
    }) async {
      real = await RealConfigSession.open(
        home: '${root.path}/home',
        project: '${root.path}/project',
        config: config,
      );
      if (agentConnected) {
        connect(embeddedConnectionProfile);
      }
      final cubit = McpSettingsCubit(
        workspace: workspace,
        defaultProfile: () async => embeddedConnectionProfile,
        open: (access, env) async => real,
        environment: {'HOME': '${root.path}/home'},
        codelabHome: '${root.path}/home',
        projectDirectory: () => '${root.path}/project',
        statusSource: source,
        logger: logger,
        now: () => clock,
      );
      cubits.add(cubit);
      await cubit.reload();
      return cubit;
    }

    McpServerDraft stdio(String name) => McpServerDraft(
      name: name,
      kind: McpTransportKind.stdio,
      command: 'npx',
    );

    test(
      'a new stdio server names Restart agent and the event says so',
      () async {
        final cubit = await openReal();

        expect(await cubit.save(stdio('fresh')), isTrue);

        expect(current(cubit).banner?.kind, McpBannerKind.saved);
        expect(current(cubit).banner?.lines.first, restartSaved);
        expect(event('mcp_settings.saved')['restart_required'], isTrue);
      },
    );

    test(
      'a new http server with a secret header names Restart agent',
      () async {
        final cubit = await openReal();

        await cubit.save(
          McpServerDraft(
            name: 'fresh',
            kind: McpTransportKind.http,
            url: 'https://mcp.example.test/mcp/',
            headers: {'Authorization': McpValueDraft.secret(SecretValue('x'))},
          ),
        );

        expect(current(cubit).banner?.lines.first, restartSaved);
        expect(event('mcp_settings.saved')['restart_required'], isTrue);
      },
    );

    test('a new http server without substitutions is plain saved', () async {
      final cubit = await openReal();

      await cubit.save(
        McpServerDraft(
          name: 'fresh',
          kind: McpTransportKind.http,
          url: 'https://mcp.example.test/mcp/',
        ),
      );

      expect(current(cubit).banner?.lines.first, 'Server fresh saved.');
      expect(event('mcp_settings.saved')['restart_required'], isFalse);
    });

    test(
      'a key outside the connection of an enabled server is plain saved',
      () async {
        final cubit = await openReal(
          config:
              '''
$realHomeConfig
mcp:
  servers:
    - name: web
      type: http
      url: https://mcp.example.test/mcp/
''',
        );

        final draft = cubit.draftFor('web')!;
        await cubit.save(draft.copyWith(enabled: true));

        expect(current(cubit).banner?.lines.first, 'Server web saved.');
        expect(event('mcp_settings.saved')['restart_required'], isFalse);
      },
    );

    test(
      'changed arguments of an enabled stdio server name Restart agent',
      () async {
        final cubit = await openReal(
          config:
              '''
$realHomeConfig
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-mcp
      args: [--root, /tmp]
''',
        );

        await cubit.save(
          cubit.draftFor('docs')!.copyWith(args: ['--root', '/x']),
        );

        expect(
          current(cubit).banner?.lines.first,
          'Server docs saved. It starts after Restart agent '
          '(Settings › Connection).',
        );
      },
    );

    test(
      'enabling with the switch names Restart agent in its own words',
      () async {
        final cubit = await openReal(
          config:
              '''
$realHomeConfig
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-mcp
      enabled: false
''',
        );

        expect(await cubit.setEnabled('docs', enabled: true), isTrue);

        expect(
          current(cubit).banner?.lines.first,
          'Server docs enabled. It starts after Restart agent '
          '(Settings › Connection).',
        );
      },
    );

    test('Enable here names Restart agent when the bridge lists the server '
        '(review 6a)', () async {
      final project = '${root.path}/project';
      Directory('$project/.codelab').createSync();
      File('$project/.codelab/config.yaml').writeAsStringSync('''
mcp:
  servers:
    - name: playwright
      type: stdio
      command: npx
''');
      File('$project/.codelab/config.local.yaml').writeAsStringSync('''
mcp:
  servers:
    - name: playwright
      enabled: false
''');
      final cubit = await openReal(
        config: '$realHomeConfig\ntrusted_projects:\n  - $project\n',
      );
      expect(row(current(cubit), 'playwright').canEnableHere, isTrue);

      expect(await cubit.enableHere('playwright'), isTrue);

      expect(
        current(cubit).banner?.lines.first,
        'Server playwright enabled. It starts after Restart agent '
        '(Settings › Connection).',
      );
    });

    test('Enable here without a restart has no banner', () async {
      final project = '${root.path}/project';
      Directory('$project/.codelab').createSync();
      File('$project/.codelab/config.yaml').writeAsStringSync('''
mcp:
  servers:
    - name: web
      type: http
      url: https://mcp.example.test/mcp/
''');
      File('$project/.codelab/config.local.yaml').writeAsStringSync('''
mcp:
  servers:
    - name: web
      enabled: false
''');
      final cubit = await openReal(
        config: '$realHomeConfig\ntrusted_projects:\n  - $project\n',
      );

      expect(await cubit.enableHere('web'), isTrue);

      expect(current(cubit).banner, isNull);
    });

    test('a deferred write, then a plain one: the state of the first does '
        'not leak into the second (review 6a)', () async {
      final cubit = await openReal();
      await cubit.save(stdio('fresh'));
      expect(event('mcp_settings.saved')['restart_required'], isTrue);

      await cubit.save(
        McpServerDraft(
          name: 'web',
          kind: McpTransportKind.http,
          url: 'https://mcp.example.test/mcp/',
        ),
      );

      expect(current(cubit).banner?.lines.first, 'Server web saved.');
      expect(event('mcp_settings.saved')['restart_required'], isFalse);
      expect(
        logger.entries.where((e) => e['event'] == 'mcp_settings.saved'),
        hasLength(2),
      );
    });

    test('a throwing switch does not leak "enabled" into the next write '
        '(review 6a)', () async {
      final cubit = await openReal(
        config:
            '''
$realHomeConfig
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-mcp
      enabled: false
    - name: extra
      type: stdio
      command: extra-mcp
''',
      );
      real.portError = StateError('boom $leakMarker');
      expect(await cubit.setEnabled('docs', enabled: true), isFalse);
      real.portError = null;

      expect(await cubit.remove('extra'), isTrue);

      expect(current(cubit).banner?.lines.first, 'Server extra removed.');
    });

    test('the write passed but the page was closed during the commit: the '
        'saved event is still written with restart_required false '
        '(review 6a)', () async {
      final gate = Completer<void>();
      final cubit = await openReal();
      real.mcpKeys.onWrite = () => gate.future;

      final saving = cubit.save(
        McpServerDraft(
          name: 'fresh',
          kind: McpTransportKind.http,
          url: 'https://mcp.example.test/mcp/',
          headers: {'Authorization': McpValueDraft.secret(SecretValue('x'))},
        ),
      );
      await pumpEventQueue();
      await cubit.close();
      gate.complete();
      await saving;

      expect(event('mcp_settings.saved')['restart_required'], isFalse);
    });

    test(
      'the connection changed during the write: no hint (review 6a)',
      () async {
        final gate = Completer<void>();
        final cubit = await openReal();
        real.mcpKeys.onWrite = () => gate.future;

        final saving = cubit.save(
          McpServerDraft(
            name: 'fresh',
            kind: McpTransportKind.http,
            url: 'https://mcp.example.test/mcp/',
            headers: {'Authorization': McpValueDraft.secret(SecretValue('x'))},
          ),
        );
        await pumpEventQueue();
        connect(_ownAgent);
        gate.complete();
        await saving;
        await pumpEventQueue();

        expect(
          logger.entries.where((e) => e['event'] == 'mcp_settings.saved'),
          hasLength(1),
        );
        expect(event('mcp_settings.saved')['restart_required'], isFalse);
      },
    );

    test('a failing restart rule keeps the write saved without a hint and '
        'logs restart_hint_failed with the error type (review 6a)', () async {
      final cubit = await openReal();
      real.breakRestartRule = true;

      expect(await cubit.save(stdio('fresh')), isTrue);

      expect(current(cubit).banner?.lines.first, 'Server fresh saved.');
      final failed = logger.entries.singleWhere(
        (e) => e['event'] == 'mcp_settings.restart_hint_failed',
      );
      expect(failed['error_type'], 'StateError');
      expect(event('mcp_settings.saved')['restart_required'], isFalse);
      expect(
        logger.entries.where((e) => e['event'] == 'mcp_settings.save_failed'),
        isEmpty,
      );
    });

    test('disabling with the switch needs no restart: no banner', () async {
      final cubit = await openReal(
        config:
            '''
$realHomeConfig
mcp:
  servers:
    - name: docs
      type: stdio
      command: docs-mcp
''',
      );

      await cubit.setEnabled('docs', enabled: false);

      expect(current(cubit).banner, isNull);
    });

    test('without a connected agent the banner is plain saved', () async {
      final cubit = await openReal(agentConnected: false);

      await cubit.save(stdio('fresh'));

      expect(current(cubit).banner?.lines.first, 'Server fresh saved.');
    });
  });

  // Задача 6.1e change `add-provider-setup-ui` (Q34 (б); design.md D11
  // «Итерация 6: ограждение ответа `/mcp list`»): ядро ставит markdown-
  // ограждение для ленты чата; панель снимает ОДНО внешнее, только если весь
  // ответ — один огороженный блок. Красные до реализации склейки ответа.
  group('the fence of the /mcp reply (6.1e, Q34)', () {
    late FakeSessionHandle handle;

    setUp(() {
      handle = externalSession(id: _s1);
      connect(_ownAgent, active: _s1);
    });

    Future<String?> replyText(
      List<String> chunks, {
      bool reload = false,
    }) async {
      handle.onSend = (_) async =>
          completedTurn(_s1, [for (final c in chunks) _msg(c)]);
      final cubit = make();
      await cubit.reload();
      if (reload) {
        await cubit.reloadAll();
      } else {
        await cubit.refresh();
      }
      return (status(cubit) as McpAgentStatusText).text;
    }

    const table = 'MCP servers (1)\ngithub connected 3';

    test('one fenced block with a language loses its fence lines', () async {
      expect(await replyText(['```text\n$table\n```']), table);
    });

    test(
      'a fence without a language is removed too, also over chunks',
      () async {
        expect(
          await replyText([
            '```\nMCP servers (1)\n',
            'github connected 3\n```',
          ]),
          table,
        );
      },
    );

    test('blank lines around the block do not matter', () async {
      expect(await replyText(['\n\n```text\n$table\n```\n\n']), table);
    });

    test('text before or after the block stays as it is', () async {
      const before = 'Servers:\n```text\n$table\n```';
      const after = '```text\n$table\n```\nDone.';
      expect(await replyText([before]), before);
      expect(await replyText([after]), after);
    });

    test('two blocks stay as they are', () async {
      const two = '```\nA\n```\n```\nB\n```';
      expect(await replyText([two]), two);
    });

    test('a block with an inner fence line stays as it is', () async {
      const inner = '```text\nA\n```\nB\n```';
      expect(await replyText([inner]), inner);
    });

    test('an opening fence alone stays as it is', () async {
      const open = '```text\n$table';
      expect(await replyText([open]), open);
    });

    test('a reply to /mcp reload without a fence stays as it is', () async {
      const reload = 'Reloaded github: connected';
      expect(await replyText([reload], reload: true), reload);
    });
  });

  group('secretNameFor', () {
    test('is the bridge rule: lower case, one name for GitHub and github', () {
      expect(
        McpSettingsCubit.secretNameFor('GitHub', 'Authorization'),
        _authorization,
      );
    });
  });

  group('Agent status: the embedded agent (D12, Q24)', () {
    late FakeMcpStatusPort port;

    setUp(() {
      port = FakeMcpStatusPort(
        'p1',
        servers: [
          mcpSummary('github', tools: 42),
          mcpSummary(
            'postgres',
            state: McpServerState.failed,
            lastError: 'ECONNREFUSED 127.0.0.1:5432',
            retryIn: const Duration(seconds: 24),
          ),
          mcpSummary('playwright', state: McpServerState.disabled),
        ],
      );
      source.ports[_s1] = port;
      connect(embeddedConnectionProfile, active: _s1);
    });

    test('the snapshot is shown at once with the artboard cells', () async {
      final cubit = make();
      await cubit.reload();

      final live = status(cubit) as McpAgentStatusLive;
      expect(live.updatedAt, clock);
      expect(
        live.rows.map((r) => (r.name, r.stateLabel, r.tools, r.lastError)),
        [
          ('github', 'connected', '42', '—'),
          (
            'postgres',
            'failed · retry in 24 s',
            '0',
            'ECONNREFUSED 127.0.0.1:5432',
          ),
          ('playwright', 'disabled', '—', '—'),
        ],
      );
      expect(live.rows.map((r) => r.canReconnect), [true, true, false]);
      expect(port.listeners, 1);
    });

    test('a change replaces the rows and the time; there is one '
        'subscription however often the page reloads', () async {
      final cubit = make();
      await cubit.reload();
      await cubit.reload();
      clock = DateTime(2026, 11, 8, 14, 5);

      port.emit([mcpSummary('github', tools: 43)]);

      final live = status(cubit) as McpAgentStatusLive;
      expect(live.rows.single.tools, '43');
      expect(live.updatedAt, clock);
      expect(port.listeners, 1);
      expect(events(), contains('mcp_settings.status_subscribed'));
    });

    test('an embedded agent shows the table without the mcp command '
        'being announced, even when it has no servers (Q24)', () async {
      port.servers = [];
      externalSession(id: _s1, announcesMcp: false);
      final cubit = make();
      await cubit.reload();

      final live = status(cubit) as McpAgentStatusLive;
      expect(live.rows, isEmpty);
    });

    test('no session, no Connected or a null port is Unavailable', () async {
      connect(embeddedConnectionProfile);
      final cubit = make();
      await cubit.reload();
      expect(status(cubit), isA<McpAgentStatusUnavailable>());
      expect(source.calls, isEmpty);

      source.ports.remove(_s1);
      connect(embeddedConnectionProfile, active: _s1);
      expect(status(cubit), isA<McpAgentStatusUnavailable>());
      expect(source.calls, [_s1]);

      source.ports[_s1] = port;
      workspace.emit(
        WorkspaceState(
          connection: const ConnectionView.disconnected(),
          profile: embeddedConnectionProfile,
          activeSessionId: _s1,
        ),
      );
      expect(status(cubit), isA<McpAgentStatusUnavailable>());
    });

    test('a switch of the active session cancels the old subscription '
        'before the new one', () async {
      final second = FakeMcpStatusPort(
        'p2',
        servers: [mcpSummary('docs', tools: 3)],
        journal: port.journal,
      );
      source.ports[_s2] = second;
      final cubit = make();
      await cubit.reload();

      connect(embeddedConnectionProfile, active: _s2);

      expect(port.journal, ['listen p1', 'cancel p1', 'listen p2']);
      expect(port.listeners, 0);
      expect(second.listeners, 1);
      expect((status(cubit) as McpAgentStatusLive).rows.single.name, 'docs');
      port.emit([mcpSummary('stale')]);
      expect((status(cubit) as McpAgentStatusLive).rows.single.name, 'docs');
      expect(events(), contains('mcp_settings.status_unsubscribed'));
    });

    test('a new Connected rebinds to the new port even for the same '
        'session id (reconnect)', () async {
      final fresh = FakeMcpStatusPort(
        'p2',
        servers: [mcpSummary('github', tools: 7)],
        journal: port.journal,
      );
      final cubit = make();
      await cubit.reload();

      workspace.emit(
        WorkspaceState(
          connection: const ConnectionView.disconnected(),
          profile: embeddedConnectionProfile,
          activeSessionId: _s1,
        ),
      );
      expect(port.listeners, 0);
      source.ports[_s1] = fresh;
      connect(embeddedConnectionProfile, active: _s1);

      expect(port.journal, ['listen p1', 'cancel p1', 'listen p2']);
      expect((status(cubit) as McpAgentStatusLive).rows.single.tools, '7');
    });

    test('a change of the profile cancels the subscription', () async {
      final cubit = make();
      await cubit.reload();

      connect(_ownAgent, active: _s1);

      expect(port.listeners, 0);
      expect(status(cubit), isNot(isA<McpAgentStatusLive>()));
    });

    test('the end of the stream makes the panel Unavailable until the next '
        'Connected', () async {
      final cubit = make();
      await cubit.reload();

      port.close();

      expect(status(cubit), isA<McpAgentStatusUnavailable>());
      expect(port.listeners, 0);
    });

    test(
      'close() cancels the subscription and later events do nothing',
      () async {
        final cubit = make();
        await cubit.reload();

        await cubit.close();
        port.emit([mcpSummary('late')]);

        expect(port.listeners, 0);
        expect(port.journal, ['listen p1', 'cancel p1']);
      },
    );

    test(
      'Reconnect calls the port with the server and sends no prompt',
      () async {
        final handle = externalSession(id: _s1);
        final cubit = make();
        await cubit.reload();

        await cubit.reconnectServer('postgres');

        expect(port.reconnected, ['postgres']);
        expect(handle.sent, isEmpty);
        expect(event('mcp_settings.status_reconnect'), {
          'server': 'postgres',
          'scope': 'one',
          'session_id': 's1',
          'event': 'mcp_settings.status_reconnect',
          'level': 'info',
        });
      },
    );

    test('Reload all reconnects the servers one by one without the '
        'disabled ones', () async {
      port.servers = [
        mcpSummary('github'),
        mcpSummary('playwright', state: McpServerState.disabled),
        mcpSummary('postgres', state: McpServerState.failed),
      ];
      final gate = port.gate = Completer<void>();
      final cubit = make();
      await cubit.reload();

      final all = cubit.reloadAll();
      await pumpEventQueue();
      expect(port.reconnected, ['github']);
      gate.complete();
      await all;

      expect(port.reconnected, ['github', 'postgres']);
      expect(event('mcp_settings.status_reconnect')['scope'], 'all');
    });

    test('Refresh does nothing for an embedded agent', () async {
      final handle = externalSession(id: _s1);
      final cubit = make();
      await cubit.reload();

      await cubit.refresh();

      expect(handle.sent, isEmpty);
    });
  });

  group('Agent status: /mcp list outside the process (D12, Q25 (6))', () {
    late FakeSessionHandle handle;

    setUp(() {
      handle = externalSession(id: _s1);
      connect(_ownAgent, active: _s1);
    });

    test('nothing is sent by itself; the panel offers the buttons', () async {
      final cubit = make();
      await cubit.reload();
      handle.emit(handle.current.copyWith(revision: 2));

      final text = status(cubit) as McpAgentStatusText;
      expect(text.text, isNull);
      expect(text.canSend, isTrue);
      expect(text.sending, isFalse);
      expect(handle.sent, isEmpty);
    });

    test('Refresh sends /mcp list and shows the message chunks of this turn '
        'joined, without thoughts and without parsing', () async {
      handle.onSend = (_) async => completedTurn(_s1, [
        _msg('github   connected\n'),
        _thought('hidden reasoning'),
        _msg('postgres failed'),
      ]);
      final cubit = make();
      await cubit.reload();

      await cubit.refresh();

      expect(handle.sent, ['/mcp list']);
      final text = status(cubit) as McpAgentStatusText;
      expect(text.text, 'github   connected\npostgres failed');
      expect(text.sending, isFalse);
      expect(text.notice, isNull);
      expect(event('mcp_settings.command_sent'), {
        'command': 'list',
        'session_id': 's1',
        'event': 'mcp_settings.command_sent',
        'level': 'info',
      });
    });

    test('Reconnect and Reload all send exactly one /mcp reload prompt each '
        'and show the reply as is; /mcp list is not sent (Q29)', () async {
      handle.onSend = (text) async =>
          completedTurn(_s1, [_msg('reply to $text')]);
      final cubit = make();
      await cubit.reload();

      await cubit.reconnectServer('github');

      expect(handle.sent, ['/mcp reload github']);
      expect(
        (status(cubit) as McpAgentStatusText).text,
        'reply to /mcp reload github',
      );

      await cubit.reloadAll();

      expect(handle.sent, ['/mcp reload github', '/mcp reload']);
      expect(
        (status(cubit) as McpAgentStatusText).text,
        'reply to /mcp reload',
      );
      final sent = logger.entries
          .where((e) => e['event'] == 'mcp_settings.command_sent')
          .toList();
      expect(sent.first['command'], 'reload');
      expect(sent.first['server'], 'github');
      expect(sent.last['command'], 'reload');
    });

    test('a ReadOnly WebSocket page offers the same buttons', () async {
      connect(_remote, active: _s1);
      handle.onSend = (_) async => completedTurn(_s1, [_msg('remote list')]);
      final cubit = make();
      await cubit.reload();

      await cubit.refresh();

      expect((status(cubit) as McpAgentStatusText).text, 'remote list');
    });

    final blocked = <String, SessionView>{
      'a running turn': const SessionView(
        revision: 2,
        status: SessionStatusView.running,
        agentCommands: [AgentCommandView(name: 'mcp', description: 'MCP')],
      ),
      'a cancelling turn': const SessionView(
        revision: 2,
        status: SessionStatusView.cancelling,
        agentCommands: [AgentCommandView(name: 'mcp', description: 'MCP')],
      ),
      'a detached session': const SessionView(
        revision: 2,
        status: SessionStatusView.detached,
        agentCommands: [AgentCommandView(name: 'mcp', description: 'MCP')],
      ),
      'a non-empty queue': const SessionView(
        revision: 2,
        status: SessionStatusView.idle,
        queue: [QueuedPrompt(id: 'q1', text: 'later')],
        agentCommands: [AgentCommandView(name: 'mcp', description: 'MCP')],
      ),
    };
    for (final MapEntry(:key, :value) in blocked.entries) {
      test(
        '$key makes the buttons inactive and sends no /mcp prompt',
        () async {
          final cubit = make();
          await cubit.reload();

          handle.emit(value);

          expect((status(cubit) as McpAgentStatusText).canSend, isFalse);
          await cubit.refresh();
          await cubit.reconnectServer('github');
          await cubit.reloadAll();
          expect(handle.sent, isEmpty);

          handle.emit(
            const SessionView(
              revision: 3,
              status: SessionStatusView.idle,
              agentCommands: [
                AgentCommandView(name: 'mcp', description: 'MCP'),
              ],
            ),
          );
          expect((status(cubit) as McpAgentStatusText).canSend, isTrue);
        },
      );
    }

    test(
      'a connection that is not Connected makes the buttons inactive',
      () async {
        final cubit = make();
        await cubit.reload();

        workspace.emit(
          WorkspaceState(
            connection: const ConnectionView.reconnecting(attempt: 1),
            profile: _ownAgent,
            activeSessionId: _s1,
          ),
        );

        expect((status(cubit) as McpAgentStatusText).canSend, isFalse);
        await cubit.refresh();
        expect(handle.sent, isEmpty);
      },
    );

    test('without the mcp command the panel is Unavailable and nothing is '
        'sent', () async {
      handle = externalSession(id: _s1, announcesMcp: false);
      connect(_ownAgent, active: _s1);
      final cubit = make();
      await cubit.reload();

      expect(status(cubit), isA<McpAgentStatusUnavailable>());
      await cubit.refresh();
      expect(handle.sent, isEmpty);
    });

    test('without a session the panel is Unavailable', () async {
      connect(_ownAgent);
      final cubit = make();
      await cubit.reload();

      expect(status(cubit), isA<McpAgentStatusUnavailable>());
    });

    test('Refresh is inactive while the request is in flight', () async {
      final reply = Completer<PromptOutcome>();
      handle.onSend = (_) => reply.future;
      final cubit = make();
      await cubit.reload();

      final first = cubit.refresh();
      await pumpEventQueue();
      final during = status(cubit) as McpAgentStatusText;
      expect(during.sending, isTrue);
      expect(during.canSend, isFalse);
      await cubit.refresh();
      reply.complete(completedTurn(_s1, [_msg('done')]));
      await first;

      expect(handle.sent, ['/mcp list']);
      expect((status(cubit) as McpAgentStatusText).text, 'done');
    });

    test('a late reply after a switch of the session is dropped', () async {
      final reply = Completer<PromptOutcome>();
      handle.onSend = (_) => reply.future;
      final cubit = make();
      await cubit.reload();

      final pending = cubit.refresh();
      await pumpEventQueue();
      externalSession(id: _s2);
      connect(_ownAgent, active: _s2);
      reply.complete(completedTurn(_s1, [_msg('stale $leakMarker')]));
      await pending;

      final text = status(cubit) as McpAgentStatusText;
      expect(text.text, isNull);
      expect(text.sending, isFalse);
      expect(event('mcp_settings.command_discarded'), {
        'command': 'list',
        'reason': 'session_changed',
        'session_id': 's1',
        'event': 'mcp_settings.command_discarded',
        'level': 'debug',
      });
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
    });

    test('a late reply after close() is dropped', () async {
      final reply = Completer<PromptOutcome>();
      handle.onSend = (_) => reply.future;
      final cubit = make();
      await cubit.reload();

      final pending = cubit.refresh();
      await pumpEventQueue();
      await cubit.close();
      reply.complete(completedTurn(_s1, [_msg('late')]));
      await pending;

      expect(event('mcp_settings.command_discarded')['reason'], 'closed');
    });

    test('scenario "/mcp list failed": a queued or failed prompt shows the '
        'line above the old text, with no exception text', () async {
      handle.onSend = (_) async => completedTurn(_s1, [_msg('old text')]);
      final cubit = make();
      await cubit.reload();
      await cubit.refresh();

      final outcomes = <String, PromptOutcome>{
        'queued': PromptQueued(
          _s1,
          const QueuedPrompt(id: 'q', text: '/mcp list'),
        ),
        'failed': PromptFailed(_s1, StateError('boom $leakMarker')),
      };
      for (final MapEntry(:key, :value) in outcomes.entries) {
        handle.onSend = (_) async => value;

        await cubit.refresh();

        final text = status(cubit) as McpAgentStatusText;
        expect(text.notice, _listFailed, reason: key);
        expect(text.text, 'old text', reason: key);
        expect(text.toString(), isNot(contains('boom')));
        expect(event('mcp_settings.command_discarded')['reason'], key);
      }
      // Встав в очередь, `/mcp list` не должен уйти позже сам (ревью 5b).
      expect(handle.removedFromQueue, ['q']);

      handle.onSend = (_) async => completedTurn(_s1, [_msg('new text')]);
      await cubit.refresh();
      final text = status(cubit) as McpAgentStatusText;
      expect(text.text, 'new text');
      expect(text.notice, isNull);
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
      expect(logger.entries.toString(), isNot(contains('old text')));
    });

    test('a send that throws is the same failure line', () async {
      handle.onSend = (_) => throw StateError('boom $leakMarker');
      final cubit = make();
      await cubit.reload();

      await cubit.refresh();

      expect((status(cubit) as McpAgentStatusText).notice, _listFailed);
      expect(event('mcp_settings.command_discarded')['reason'], 'failed');
      expect(logger.entries.toString(), isNot(contains(leakMarker)));
    });
  });
}
