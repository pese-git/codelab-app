// Точка входа web-smoke: `melos run web-compile` компилирует её в JS и Wasm и
// так доказывает, что основной барель моста настроек остаётся web-безопасным
// (без dart:io, dart:isolate, package:codelab_agent_io и
// package:http/io_client.dart). На Dart VM тот же код проверяет
// `web_smoke_test.dart` (design.md change `add-provider-setup-ui`, D20).
import 'dart:async';
import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        ConfigLayerKind,
        ConfigTree,
        ContextFile,
        CoreConfig,
        LogLevel,
        Logger,
        ModelRef,
        PhaseLoaded,
        ProjectExtensions,
        ProjectFiles,
        ProviderApi,
        SkillFile,
        SkillFiles,
        SkillRootInfo;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:http/http.dart' as http;

/// Итог web-smoke: что построил основной барель без файлов и сети.
final class SetupWebSmokeReport {
  const SetupWebSmokeReport({
    required this.access,
    required this.models,
    required this.entries,
    required this.removal,
    required this.wizard,
    required this.settings,
    required this.mcp,
    required this.extensions,
    required this.codes,
    required this.draftCodes,
    required this.skillFields,
  });

  final String access;
  final List<String> models;
  final List<String> entries;
  final String removal;

  /// Правки плана мастера, прошедшего от пресета до обзора.
  final List<String> wizard;

  /// Строки `/settings` снимка: `ключ:источник` для заданных ключей и число
  /// строк реестра `shared`; проверяет реэкспорт `SettingsRegistry` и др.
  final List<String> settings;

  /// Черновик MCP-сервера, его правка и строка страницы по снимку: проверяет,
  /// что `McpServerDraft`, `McpServerEntryView` и реэкспорт `UpsertMcpServer`
  /// в основном бареле собираются без `dart:io` (D11, D20).
  final List<String> mcp;

  /// Вид страницы навыков на фейковых данных: проверяет, что `AgentExtensionsView`
  /// и `agentExtensionsOf` собираются без `dart:io` (`add-app-skills-page`,
  /// D4, задача 1.4).
  final List<String> extensions;

  /// Типизированные поля мастера (`errorCode`, `literalKeyInConfig`,
  /// `notVerified`) на шагах с ошибкой: проверяет, что они читаются без
  /// `dart:io` и без зависимости от локали (`add-desktop-localization`, D6,
  /// задача 4.1a).
  final List<String> codes;

  /// Коды проблем черновика MCP (`McpDraftProblem.code`, `argument`, фабрика
  /// `McpDraftProblem.of`): читаются без `dart:io` и локали
  /// (`add-desktop-localization`, D6, задача 5.1a).
  final List<String> draftCodes;

  /// Поля вида навыков `SkillEntryView.overridesScope` и
  /// `SkillRootView.extraEntry` на фейковых данных (задача 5.1a).
  final List<String> skillFields;
}

/// Клиент, который отвечает списком моделей без сети.
final class _FakeModelsClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(
          utf8.encode('{"data":[{"id":"m","context_length":4096}]}'),
        ),
        200,
      );
}

/// Хранилище конфига в памяти: записывает правки и отвечает `ConfigSaved`.
final class _MemoryStore implements AgentConfigStore {
  final applied = <List<ConfigEdit>>[];

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    applied.add(edits);
    return const ConfigSaved(
      fingerprint: 'fp',
      warnings: [],
      restartRequiredKeys: [],
    );
  }

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) =>
      throw UnimplementedError('smoke работает по готовому снимку');
}

/// Журнал, который молчит: smoke не проверяет записи.
final class _SilentLogger implements Logger {
  const _SilentLogger();

  @override
  bool isEnabled(LogLevel level) => false;

  @override
  void log(
    LogLevel level,
    String event, {
    Map<String, Object?> fields = const {},
    Object? error,
    StackTrace? stack,
  }) {}
}

/// Порт ключей в памяти: бэкенд только для чтения, секретов нет.
final class _NoKeys implements ProviderKeys {
  @override
  SecretBackendInfo get backend =>
      const SecretBackendInfo(id: 'env', writable: false);

  @override
  String? get readOnlyHint => 'read-only';

  @override
  Future<bool> stored(String name) async => false;

  @override
  Future<SecretValue?> read(String name) async => null;

  @override
  Future<ProviderKeyWrite> write(String name, SecretValue value) async =>
      const ProviderKeyRefused('read-only');

  @override
  Future<SecretDeletion> delete(String name) async => SecretDeletion.notSet;
}

/// Прогоняет мастер провайдера от пресета до обзора на портах в памяти.
Future<List<String>> _runWizard(AgentConfigSnapshot snapshot) async {
  final keys = _NoKeys();
  final store = _MemoryStore();
  final flow = ProviderSetupFlow(
    check: HttpProviderCheck(_FakeModelsClient.new),
    committer: ProviderSetupCommitter(config: store, keys: keys),
    keys: keys,
    snapshot: snapshot,
    access: const EditableSettings(ConfigPaths(codelabHome: '/home')),
    environment: const {},
    isLocalHost: (host) => host == 'localhost',
    logger: const _SilentLogger(),
    entry: ProviderWizardEntry.app,
  );
  // Подписка раньше, чем автомат дойдёт до нужного состояния.
  flow
    ..dispatch(const PresetChosen('openrouter'))
    ..dispatch(const BaseUrlSubmitted('https://openrouter.ai/api/v1'));
  await flow.states.firstWhere((s) => s is ChoosingKey && s.ready);
  flow.dispatch(const KeySubmitted(NoKey()));
  await flow.states.firstWhere((s) => s is ChoosingModel);
  flow.dispatch(const ModelChosen('m'));
  final edits = [
    for (final edit in (flow.current as Reviewing).plan.toEdits())
      edit.toString(),
  ];
  await flow.dispose();
  return edits;
}

/// Доводит мастер до ошибок шагов и читает новые типизированные поля.
///
/// Бэкенд [_NoKeys] только для чтения: `StoreSecret` даёт
/// `secretStoreReadOnly`. Порядок строк: код ошибки адреса, код ошибки ключа,
/// `literalKeyInConfig` шага ключа, `notVerified` обзора.
Future<List<String>> _wizardCodes(AgentConfigSnapshot snapshot) async {
  final keys = _NoKeys();
  final flow = ProviderSetupFlow(
    check: HttpProviderCheck(_FakeModelsClient.new),
    committer: ProviderSetupCommitter(config: _MemoryStore(), keys: keys),
    keys: keys,
    snapshot: snapshot,
    access: const EditableSettings(ConfigPaths(codelabHome: '/home')),
    environment: const {},
    isLocalHost: (host) => host == 'localhost',
    logger: const _SilentLogger(),
    entry: ProviderWizardEntry.app,
  );
  // Поток broadcast доставляет состояния позже `dispatch`, а опоздавший
  // подписчик их не получает: ожидания регистрируются один раз и
  // дополняются уже накопленными состояниями.
  final seen = <ProviderSetupState>[];
  final waiters =
      <(bool Function(ProviderSetupState), Completer<ProviderSetupState>)>[];
  final sub = flow.states.listen((state) {
    seen.add(state);
    for (final (test, done) in [...waiters]) {
      if (!done.isCompleted && test(state)) {
        done.complete(state);
      }
    }
  });
  Future<ProviderSetupState> until(bool Function(ProviderSetupState) test) {
    final done = Completer<ProviderSetupState>();
    waiters.add((test, done));
    return done.future;
  }

  final addressWait = until((s) => s is EnteringBaseUrl && s.error != null);
  flow
    ..dispatch(const PresetChosen('openrouter'))
    ..dispatch(const BaseUrlSubmitted('ftp://smoke.invalid'));
  final address = await addressWait;
  final keyReady = until((s) => s is ChoosingKey && s.ready);
  flow.dispatch(const BaseUrlSubmitted('https://openrouter.ai/api/v1'));
  await keyReady;
  final keyFailed = until((s) => s is ChoosingKey && s.error != null);
  flow.dispatch(KeySubmitted(StoreSecret(SecretValue('smoke'))));
  final key = await keyFailed;
  final modelStep = until((s) => s is ChoosingModel);
  flow.dispatch(const KeySubmitted(NoKey()));
  await modelStep;
  flow.dispatch(const ModelChosen('m'));
  final review = flow.current as Reviewing;
  await sub.cancel();
  await flow.dispose();
  return [
    'address:${(address as EnteringBaseUrl).errorCode?.name}',
    'key:${(key as ChoosingKey).errorCode?.name}',
    'literal:${key.literalKeyInConfig}',
    'notVerified:${review.notVerified}',
  ];
}

/// Строки `/settings` и символы реестра, реэкспортированные мостом.
List<String> _settingRows(AgentConfigSnapshot snapshot) {
  final rows = settingFieldsOf(snapshot);
  final kind = SettingsRegistry.lookup('providers.a.kind')!;
  Object? parsed;
  try {
    SettingsRegistry.parseCliValue(
      SettingsRegistry.lookup('budget.max_steps')!,
      'x',
    );
  } on ConfigValueException catch (e) {
    parsed = e.expected;
  }
  return [
    for (final r in rows)
      if (r.source != null) '${r.key}:${r.sourceName}',
    'type:${kind.type == SettingType.enumeration}',
    'scope:${kind.scope == SettingScope.shared}',
    'bad:${parsed != null}',
    // Правила правки строк (change `add-app-general-page`, D6).
    'refusal:${settingKeyEditRefusalOf('trusted_projects') is TrustBoundarySetting}',
    'rows:${rows.where((r) => settingEditRefusalOf(r) == null).isNotEmpty}',
  ];
}

/// Вид расширений агента на фейковых данных: цепочка, навык и шаблон.
List<String> _extensionsSmoke() {
  final config = CoreConfig(
    defaultModel: ModelRef(
      provider: 'smoke',
      id: 'm',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('https://smoke.invalid/v1'),
      contextWindow: 8000,
      maxOutputTokens: 1000,
    ),
  );
  final snapshot = AgentConfigSnapshot.fromLayers(
    cwd: '/web',
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/home/config.yaml',
        fingerprint: 'f',
        values: const {},
      ),
    },
    loaded: ConfigLoadResult(config: config),
    secrets: const SecretBackendInfo(id: 'env', writable: false),
  );
  final view = agentExtensionsOf(
    snapshot,
    ProjectExtensions(
      cwd: '/web',
      trusted: true,
      contextRoot: '/web',
      codelabHome: '/home',
      projectFiles: PhaseLoaded(
        ProjectFiles(
          context: [ContextFile(path: 'AGENTS.md', content: 'rules')],
        ),
      ),
      skills: PhaseLoaded(
        SkillFiles(
          skills: [
            SkillFile(
              dir: '/web/.codelab/skills/smoke',
              scope: ExtensionScope.project,
              rootIndex: 0,
              frontmatter: const ConfigTree(
                kind: ConfigLayerKind.user,
                source: '/web/.codelab/skills/smoke/SKILL.md',
                values: {'name': 'smoke', 'description': 'Smoke skill'},
              ),
              body: 'Body',
              bodyLine: 4,
            ),
          ],
        ),
      ),
      skillRoots: const [
        SkillRootInfo(
          scope: ExtensionScope.project,
          path: '/web/.codelab/skills',
        ),
      ],
    ),
    userHome: '/home',
  );
  return [
    'context:${view.context.files.map((f) => f.path).join(',')}',
    'skill:${view.skills.entries.map((e) => '${e.name}:${e.root.label}').join(',')}',
    'trusted:${view.trusted}',
  ];
}

/// Проблемы черновика с кодами и страничная проблема фабрикой моста.
List<String> _draftCodesSmoke() {
  final problems = [
    ...McpServerDraft(
      name: 'a b',
      kind: McpTransportKind.http,
      url: 'https://u:p@h/mcp',
    ).validate(),
    ...McpServerDraft(
      name: 'docs',
      kind: McpTransportKind.stdio,
      command: 'srv',
      env: {'TOKEN': McpValueDraft.secret(SecretValue(''))},
    ).validate(),
    McpDraftProblem.of(
      McpDraftProblemCode.keyDuplicate,
      McpDraftField.headers,
      argument: 'Authorization',
    ),
  ];
  return [
    for (final p in problems) '${p.code?.name}:${p.argument}:${p.message}',
  ];
}

/// Вид навыков: проект перекрыл пользователя, навык из дополнительной папки.
List<String> _skillFieldsSmoke() {
  const roots = [
    SkillRootInfo(scope: ExtensionScope.project, path: '/web/.codelab/skills'),
    SkillRootInfo(scope: ExtensionScope.user, path: '/home/skills'),
    SkillRootInfo(
      scope: ExtensionScope.extra,
      path: '/home/.claude/skills',
      extraRoot: '~/.claude/skills',
    ),
  ];
  SkillFile skill(String name, int root) => SkillFile(
    dir: '${roots[root].path}/$name',
    scope: roots[root].scope,
    rootIndex: root,
    frontmatter: ConfigTree(
      kind: ConfigLayerKind.user,
      source: '${roots[root].path}/$name/SKILL.md',
      values: {'name': name, 'description': 'Smoke skill'},
    ),
    body: 'Body',
    bodyLine: 4,
  );
  final config = CoreConfig(
    defaultModel: ModelRef(
      provider: 'smoke',
      id: 'm',
      api: ProviderApi.openaiChat,
      baseUrl: Uri.parse('https://smoke.invalid/v1'),
      contextWindow: 8000,
      maxOutputTokens: 1000,
    ),
  );
  final snapshot = AgentConfigSnapshot.fromLayers(
    cwd: '/web',
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/home/config.yaml',
        fingerprint: 'f',
        values: const {},
      ),
    },
    loaded: ConfigLoadResult(config: config),
    secrets: const SecretBackendInfo(id: 'env', writable: false),
  );
  final view = agentExtensionsOf(
    snapshot,
    ProjectExtensions(
      cwd: '/web',
      trusted: true,
      contextRoot: '/web',
      codelabHome: '/home',
      projectFiles: PhaseLoaded(ProjectFiles.empty),
      skills: PhaseLoaded(
        SkillFiles(
          skills: [skill('review', 0), skill('review', 1), skill('delta', 2)],
        ),
      ),
      skillRoots: roots,
    ),
    userHome: '/home',
  );
  return [
    for (final e in view.skills.entries)
      '${e.name}:${e.overridesScope?.name}:${e.root.extraEntry}',
  ];
}

/// Черновик MCP-сервера с секретным заголовком и строка страницы по снимку.
List<String> _mcpSmoke() {
  final draft = McpServerDraft(
    name: 'docs',
    kind: McpTransportKind.http,
    url: 'https://docs.invalid/mcp',
    headers: {'Authorization': McpValueDraft.secret(SecretValue('smoke'))},
  );
  final snapshot = AgentConfigSnapshot.fromLayers(
    cwd: '/web',
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/home/config.yaml',
        fingerprint: 'f',
        values: {
          'mcp': {
            'servers': [
              {
                'name': 'docs',
                'type': 'http',
                'url': 'https://docs.invalid/mcp',
                'headers': {'Authorization': 'Bearer smoke-literal-token'},
              },
            ],
          },
        },
      ),
    },
    loaded: const ConfigLoadResult(),
    secrets: const SecretBackendInfo(id: 'env', writable: false),
  );
  final entry = mcpServerEntriesOf(snapshot).single;
  return [
    for (final edit in draft.toEdits())
      edit is UpsertMcpServer ? 'upsert:${edit.server['name']}' : '?',
    for (final name in draft.secretsToWrite().keys) 'secret:$name',
    'entry:${entry.name}:${entry.source.kind.name}:${entry.masked}',
    'valid:${isValidMcpServerName('docs')}',
  ];
}

/// Прогоняет доступ, проверку `/models`, список провайдеров и удаление.
Future<SetupWebSmokeReport> runSetupWebSmoke() async {
  final access = resolveSettingsAccess(
    kind: AgentLaunchKind.embedded,
    cwd: '/web',
    defaultCodelabHome: '/home',
  );
  final check = HttpProviderCheck(_FakeModelsClient.new);
  final result = await check.listModels(
    'openai-compatible',
    Uri.parse('https://smoke.invalid/v1'),
    SecretValue('smoke'),
  );
  final snapshot = AgentConfigSnapshot.fromLayers(
    cwd: '/web',
    layers: {
      ConfigLayer.user: ConfigSnapshot(
        target: const ConfigTarget.user(),
        path: '/home/config.yaml',
        fingerprint: 'f',
        values: {
          'providers': {
            'a': {'kind': 'openai-compatible', 'api_key_env': 'SMOKE_KEY'},
            'b': {'kind': 'anthropic'},
          },
        },
      ),
    },
    loaded: const ConfigLoadResult(),
    secrets: const SecretBackendInfo(id: 'env', writable: false),
  );
  final entries = await providerEntriesOf(
    snapshot,
    environment: const {},
    isSecretSet: (_) async => false,
  );
  final store = _MemoryStore();
  final removal = await ProviderRemover(
    config: store,
    deleteSecret: (_) async => SecretDeletion.notSet,
  ).remove(snapshot, providerId: 'b');
  return SetupWebSmokeReport(
    access: access.runtimeType.toString(),
    models: [
      if (result case CheckOk(:final models)) ...models.map((m) => m.id),
    ],
    entries: [for (final entry in entries) '${entry.id}:${entry.key.label}'],
    removal: removal.runtimeType.toString(),
    wizard: await _runWizard(snapshot),
    settings: _settingRows(snapshot),
    mcp: _mcpSmoke(),
    extensions: _extensionsSmoke(),
    codes: await _wizardCodes(snapshot),
    draftCodes: _draftCodesSmoke(),
    skillFields: _skillFieldsSmoke(),
  );
}

Future<void> main() async {
  final report = await runSetupWebSmoke();
  // ignore: avoid_print
  print(
    'setup web smoke: ${report.access} ${report.models} ${report.entries} '
    '${report.removal}',
  );
}
