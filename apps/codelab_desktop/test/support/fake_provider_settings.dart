// Двойники страницы «Providers» (design.md change `add-provider-setup-ui`,
// D10, D21): снимок конфига, сессия настроек и рабочее пространство в памяти.
//
// Почему двойники, а не настоящие файлы: запись и чтение `config.yaml`
// проверяет мост `codelab_setup` (задачи 2.2, 2.5); страница отвечает только
// за то, что показать и что вызвать. Маркер `sk-test-leak-…` лежит ТОЛЬКО в
// «хранилище» двойника: если он окажется в состоянии или журнале, значит
// Cubit прочитал значение (SETUP-1).

import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart'
    show SessionId, SessionUpdate;
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show PromptTurn, PromptTurnId;
import 'package:codelab_client_core/codelab_client_core.dart';
import 'package:codelab_desktop/features/settings/application/provider_settings_session.dart';
import 'package:codelab_setup/codelab_setup.dart';

import 'fake_provider_wizard.dart';
import 'recording_logger.dart';

/// Значение ключа, которое не должно выйти за пределы двойника.
const leakMarker = 'sk-test-leak-0123456789';

/// Конфиг в памяти: слои задаются картами значений.
final class FakeAgentConfigStore implements AgentConfigStore {
  FakeAgentConfigStore({
    this.user = const {},
    this.project,
    this.projectLocal,
    this.issues = const [],
    this.backend = const SecretBackendInfo(id: 'file', writable: true),
  });

  Map<String, Object?> user;
  Map<String, Object?>? project;
  Map<String, Object?>? projectLocal;
  List<ConfigIssue> issues;

  /// Слой `user` не разобрался: его нет в карте снимка.
  bool omitUserLayer = false;
  SecretBackendInfo backend;

  /// Пути слоёв для проверки `defined in <file>`.
  static const userPath = '/home/u/.codelab/config.yaml';
  static const projectPath = '/work/app/.codelab/config.yaml';
  static const projectLocalPath = '/work/app/.codelab/config.local.yaml';

  final applied = <({ConfigSnapshot base, List<ConfigEdit> edits})>[];

  /// Исход следующего `apply`; по умолчанию `ConfigSaved`.
  ConfigSaveOutcome? nextOutcome;

  /// Исход только первого `apply`, затем `nextOutcome`/`ConfigSaved`
  /// (конфликт один раз: «Save again» после перечитывания, D9).
  ConfigSaveOutcome? firstOutcome;

  /// Действие внутри `apply` (журнал порядка вызовов, ожидание, правка
  /// слоёв после сохранения).
  FutureOr<void> Function()? onApply;

  var snapshots = 0;

  @override
  Future<AgentConfigSnapshot> snapshot({required String cwd}) async {
    snapshots++;
    return AgentConfigSnapshot.fromLayers(
      cwd: cwd,
      layers: {
        if (!omitUserLayer)
          ConfigLayer.user: ConfigSnapshot(
            target: const ConfigTarget.user(),
            path: userPath,
            fingerprint: 'fp-user-$snapshots',
            values: user,
          ),
        if (project case final values?)
          ConfigLayer.project: ConfigSnapshot(
            target: ConfigTarget.project('/work/app'),
            path: projectPath,
            fingerprint: 'fp-project',
            values: values,
          ),
        if (projectLocal case final values?)
          ConfigLayer.projectLocal: ConfigSnapshot(
            target: const ConfigTarget.projectLocal('/work/app'),
            path: projectLocalPath,
            fingerprint: 'fp-local',
            values: values,
          ),
      },
      loaded: ConfigLoadResult(issues: issues),
      secrets: backend,
    );
  }

  @override
  Future<ConfigSaveOutcome> apply(
    ConfigSnapshot base,
    List<ConfigEdit> edits,
  ) async {
    applied.add((base: base, edits: edits));
    await onApply?.call();
    final first = firstOutcome;
    firstOutcome = null;
    final outcome =
        first ??
        nextOutcome ??
        const ConfigSaved(
          fingerprint: 'fp-new',
          warnings: [],
          restartRequiredKeys: [],
        );
    if (outcome is ConfigSaved) {
      // Сохранённые правки видны следующему снимку: мост после записи
      // перечитывает конфиг, чтобы не удалять всё ещё используемый секрет.
      final layer = switch (base.path) {
        userPath => user,
        projectPath => project,
        _ => projectLocal,
      };
      if (layer != null) {
        for (final edit in edits) {
          switch (edit) {
            case RemoveTable(:final key):
              _remove(layer, key.split('.'));
            case SetValue(:final key, :final value):
              _set(layer, key.split('.'), value);
            case UpsertMcpServer(:final server):
              // Страница «MCP servers» (задача 5.4): элемент `mcp.servers`
              // заменяется по `name` целиком, как в настоящем писателе.
              _editServers(layer, (servers) {
                final index = servers.indexWhere(
                  (s) => s is Map && s['name'] == server['name'],
                );
                if (index >= 0) {
                  servers[index] = {...server};
                } else {
                  servers.add({...server});
                }
              });
            case RemoveMcpServer(:final name):
              _editServers(
                layer,
                (servers) =>
                    servers.removeWhere((s) => s is Map && s['name'] == name),
              );
            default:
              break;
          }
        }
      }
    }
    return outcome;
  }

  /// Правит список `mcp.servers` слоя; слой должен быть изменяемой картой.
  static void _editServers(
    Map<String, Object?> layer,
    void Function(List<Object?> servers) edit,
  ) {
    final mcp = layer['mcp'];
    final servers = mcp is Map && mcp['servers'] is List
        ? [...(mcp['servers'] as List<Object?>)]
        : <Object?>[];
    edit(servers);
    layer['mcp'] = <String, Object?>{
      if (mcp is Map)
        for (final e in mcp.entries) '${e.key}': e.value,
      'servers': servers,
    };
  }

  static void _remove(Map<String, Object?> map, List<String> path) {
    if (path.length == 1) {
      map.remove(path.single);
    } else if (map[path.first] case final Map<String, Object?> child) {
      _remove(child, path.sublist(1));
    }
  }

  static void _set(Map<String, Object?> map, List<String> path, Object? v) {
    if (path.length == 1) {
      map[path.single] = v;
    } else {
      final child = map[path.first];
      _set(
        child is Map<String, Object?>
            ? child
            : (map[path.first] = <String, Object?>{}),
        path.sublist(1),
        v,
      );
    }
  }
}

/// Провайдер для карты слоя.
Map<String, Object?> providerMap({
  String kind = 'openai-compatible',
  String? baseUrl = 'https://h.example/v1',
  String? secret,
  String? env,
  List<String> models = const ['m'],
}) => {
  'kind': kind,
  'base_url': ?baseUrl,
  'api_key_secret': ?secret,
  'api_key_env': ?env,
  'models': {
    for (final model in models) model: {'context_window': 32000},
  },
};

/// Сессия настроек в памяти: секреты — карта, чтение значений считается.
final class FakeProviderSettingsSession implements ProviderSettingsSession {
  FakeProviderSettingsSession(this.store, {Map<String, String>? secrets})
    : secrets = {...?secrets};

  final FakeAgentConfigStore store;

  /// Хранилище секретов двойника: значения видны только адаптеру Check.
  final Map<String, String> secrets;

  /// Имена, для которых вызывали `isSecretSet`.
  final isSetCalls = <String>[];

  /// Ключи, переданные проверке: имя секрета или `-` (без ключа).
  final checks = <({String kind, Uri baseUrl, KeyStatusView key})>[];

  /// Токены отмены, переданные проверкам, в порядке вызовов.
  final cancels = <CancelToken?>[];

  /// Исход проверки; по умолчанию успех с одной моделью.
  Future<ProviderCheckResult> Function() checkResult = () async =>
      const CheckOk([RemoteModel('m')]);

  /// Проверка мастера: ответы даёт тест.
  final wizardCheck = FakeWizardCheck();

  /// Подсказка read-only бэкенда для мастера (`ProviderKeys.readOnlyHint`).
  String? readOnlyHint;

  /// Порт ключей последнего открытого мастера (журнал вызовов).
  FakeWizardKeys? lastKeys;

  /// Журнал автомата мастера (события `provider_wizard.*` моста).
  final wizardLog = RecordingLogger();

  /// Доступ, с которым открывается мастер; по умолчанию — пользователь и
  /// папка проекта `/work/app`.
  EditableSettings access = const EditableSettings(
    ConfigPaths(codelabHome: '/home/u/.codelab', projectDir: '/work/app'),
  );

  /// Окружение агента для `UseEnvVar` и `api_key_env` мастера.
  Map<String, String> wizardEnvironment = const {};

  final wizards =
      <
        ({
          ProviderEntryView? editing,
          bool forceDefault,
          ProviderWizardEntry entry,
        })
      >[];

  final deleted = <String>[];
  SecretDeletion deletion = SecretDeletion.deleted;
  FutureOr<void> Function(String name)? onDelete;

  /// Порт ключей страницы «MCP servers» (задача 5.4): те же секреты, что у
  /// [isSecretSet], но через `ProviderKeys`, как собирает composition root
  /// (`providerKeysOf` того же хранилища, задача 5.10). `journal` показывает
  /// порядок «секрет → конфиг → откат».
  late final FakeWizardKeys mcpKeys = FakeWizardKeys(
    secrets,
    backend: store.backend,
  );

  /// Имена, которые [isSecretSet] скрывает, хотя секрет уже есть: гонка
  /// «секрет появился после вопроса» (`McpSecretAppeared`).
  final hiddenFromIsSet = <String>{};

  /// Запись MCP-сервера страницы: настоящий `McpServerCommitter` моста на
  /// двойниках. Станет `@override` вместе с методом интерфейса
  /// `ProviderSettingsSession` (задача 5.10); до этого — обычный метод.
  McpServerCommitter mcpCommitter() =>
      McpServerCommitter(config: store, keys: mcpKeys);

  /// Удаление MCP-сервера страницы: настоящий `McpServerRemover` моста.
  /// Станет `@override` вместе с интерфейсом (задача 5.10).
  McpServerRemover mcpRemover() =>
      McpServerRemover(config: store, keys: mcpKeys);

  @override
  AgentConfigStore get config => store;

  @override
  SecretBackendInfo get backend => store.backend;

  @override
  Future<bool> isSecretSet(String name) async {
    isSetCalls.add(name);
    return secrets.containsKey(name) && !hiddenFromIsSet.contains(name);
  }

  @override
  Future<SecretDeletion> deleteSecret(String name) async {
    await onDelete?.call(name);
    deleted.add(name);
    secrets.remove(name);
    return deletion;
  }

  @override
  Future<ProviderSetupFlow> openWizard({
    ProviderEntryView? editing,
    bool forceDefault = false,
    ProviderWizardEntry entry = ProviderWizardEntry.app,
  }) {
    wizards.add((editing: editing, forceDefault: forceDefault, entry: entry));
    final keys = lastKeys = FakeWizardKeys(
      secrets,
      backend: store.backend,
      readOnlyHint: readOnlyHint,
    );
    return buildWizardFlow(
      store: store,
      keys: keys,
      check: wizardCheck,
      access: access,
      log: wizardLog,
      environment: wizardEnvironment,
      editing: editing,
      forceDefault: forceDefault,
      entry: entry,
    );
  }

  @override
  Future<ProviderCheckResult> checkProvider({
    required String kind,
    required Uri baseUrl,
    required KeyStatusView key,
    CancelToken? cancel,
  }) {
    cancels.add(cancel);
    checks.add((kind: kind, baseUrl: baseUrl, key: key));
    return checkResult();
  }
}

/// Рабочее пространство для Cubit-а страницы: профиль, соединение и
/// активная сессия; остальное страница не использует.
final class FakeWorkspace implements ClientWorkspace {
  FakeWorkspace([WorkspaceState? initial])
    : _current = initial ?? const WorkspaceState();

  WorkspaceState _current;
  final _states = StreamController<WorkspaceState>.broadcast(sync: true);
  final handles = <SessionId, FakeSessionHandle>{};

  @override
  WorkspaceState get current => _current;

  @override
  Stream<WorkspaceState> get state => _states.stream;

  void emit(WorkspaceState next) {
    _current = next;
    _states.add(next);
  }

  @override
  SessionHandle? session(SessionId id) => handles[id];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Сессия с опциями конфигурации.
///
/// Для панели «Agent status» (задача 5.4) умеет `send`: тексты промптов
/// складываются в [sent], исход задаёт [onSend] (по умолчанию — пустой ход).
final class FakeSessionHandle implements SessionHandle {
  FakeSessionHandle(this.current, {SessionId? id}) : id = id ?? SessionId('s1');

  @override
  final SessionId id;

  @override
  SessionView current;

  /// Промпты, отправленные через `send`, по порядку.
  final sent = <String>[];

  /// Исход `send`; `null` — ход без ответа.
  Future<PromptOutcome> Function(String text)? onSend;

  @override
  Future<PromptOutcome> send(String text) {
    sent.add(text);
    final handler = onSend;
    return handler != null
        ? handler(text)
        : Future.value(PromptCompleted(id, _emptyTurn(id)));
  }

  final views = StreamController<SessionView>.broadcast(sync: true);

  @override
  Stream<SessionView> get view => views.stream;

  void emit(SessionView next) {
    current = next;
    views.add(next);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

PromptTurn _emptyTurn(SessionId id, {List<SessionUpdate> updates = const []}) =>
    PromptTurn(
      id: PromptTurnId('turn'),
      sessionId: id,
      prompt: const [],
      updates: updates,
    );

/// Исход хода с ответом агента [chunks] (`AgentMessageChunk`/
/// `AgentThoughtChunk`), как его отдаёт `SessionHandle.send`.
PromptCompleted completedTurn(SessionId id, List<SessionUpdate> chunks) =>
    PromptCompleted(id, _emptyTurn(id, updates: chunks));
