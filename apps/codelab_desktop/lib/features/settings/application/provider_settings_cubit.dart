import 'dart:async';

import 'package:codelab_acp_protocol/codelab_acp_protocol.dart' show SessionId;
import 'package:codelab_client_acp/codelab_client_acp.dart' show Logger;
import 'package:codelab_client_core/codelab_client_core.dart'
    show
        ClientWorkspace,
        Connected,
        ConnectionFailed,
        ConnectionLost,
        ConnectionProfile,
        EmbeddedProfile,
        Reconnecting,
        SessionHandle,
        StdioProfile,
        WebSocketProfile,
        WorkspaceState,
        isLocalHost,
        profileOrigin;
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/language/app_language_cubit.dart' show AppStrings;
import '../../../core/platform/home_path_label.dart';
import '../../../l10n/app_localizations.dart';
import 'provider_settings_session.dart';
import 'provider_settings_state.dart';
import 'provider_wizard_cubit.dart';

export 'provider_settings_session.dart';
export 'provider_settings_state.dart';
export 'provider_wizard_cubit.dart' show ProviderWizardCubit;

/// Страница «Providers»: настройки провайдеров агента текущего подключения.
///
/// Почему: один владелец данных страницы — снимок `config.yaml` агента,
/// итоги проверок и запись «Default model» и «Remove» (design.md change
/// `add-provider-setup-ui`, D5, D10, D21). Политику («чьи это настройки»,
/// «можно ли удалить», порядок «конфиг → секрет») решают `resolveSettingsAccess`
/// и `ProviderRemover` моста `codelab_setup`; Cubit только вызывает их и
/// превращает итог в [ProviderSettingsState] (AGENTS.md §7, §10).
///
/// Для чего: собирает состояние из [ProviderSettingsSession] (конфиг, секреты,
/// проверка) и `WorkspaceState` (профиль и соединение окна, опция `model`
/// активной сессии для строки «Active in this session»). Для WebSocket и
/// стороннего агента локальный конфиг НЕ читается (SETUP-2): состояние —
/// [ProviderSettingsReadOnly]. Битый `config.yaml` даёт
/// [ProviderSettingsUnreadable] и запись не предлагает. Значение ключа сюда не
/// попадает: статус считается без чтения значения, а проверку выполняет
/// адаптер сессии, который читает ключ и сразу отдаёт его `ProviderCheck`
/// (D4, SETUP-1). События журнала — D18: только `provider_id` и виды, без
/// имён секретов и переменных, адресов и текстов исключений (только тип).
///
/// Как использовать: composition root создаёт Cubit на каждое открытие
/// страницы, страница зовёт [reload] и закрывает Cubit вместе с собой. [reload]
/// открывает сессию заново (правка `secrets.backend` применяется без
/// перезапуска, D3) и повторно вызывается сам при смене профиля или
/// соединения окна. Поздний снимок отбрасывается номером загрузки, поздний
/// итог Check — номером проверки строки; [close] отменяет ожидание всех
/// проверок (`provider_settings.check_discarded`, D21). Запись одна за раз:
/// пока [ProviderSettingsReady.saving], повторные [setDefaultModel] и
/// [remove] ничего не делают. Конфликт записи показывает баннер, перечитывает
/// снимок и не повторяется (SETUP-6).
class ProviderSettingsCubit extends Cubit<ProviderSettingsState> {
  ProviderSettingsCubit({
    required ClientWorkspace workspace,
    required Future<ConnectionProfile> Function() defaultProfile,
    required ProviderSettingsOpener open,
    required Map<String, String> environment,
    required String? codelabHome,
    required String? Function() projectDirectory,
    Logger? logger,
    DateTime Function()? now,
    Future<void> Function()? retryStart,
    required AppStrings strings,
  }) : _strings = strings,
       _workspace = workspace,
       _retryStart = retryStart,
       _defaultProfile = defaultProfile,
       _open = open,
       _environment = environment,
       _codelabHome = codelabHome,
       _projectDirectory = projectDirectory,
       _logger = logger,
       _now = now ?? DateTime.now,
       super(const ProviderSettingsLoading()) {
    _accessProfile = _connectedProfile(_workspace.current);
    // Одна подписка на язык на весь срок жизни Cubit (D5 п. 3, R3): строки,
    // итоги проверок и InfoBar пересобираются из последних входов, конфиг и
    // агент не затрагиваются; отменяется в `close()`.
    _languageSubscription = strings.changes.listen(_handleLanguage);
    _workspaceSubscription = _workspace.state.listen(_onWorkspace);
    _bindSession(_workspace.current.activeSessionId);
  }

  final AppStrings _strings;
  late final StreamSubscription<AppLocalizations> _languageSubscription;

  /// Причина «только чтение» последнего состояния [ProviderSettingsReadOnly]:
  /// вход проекции, из которого текст пересобирается при смене языка.
  _ReadOnlyCause? _readOnlyCause;

  /// Проблемы последнего [ProviderSettingsUnreadable] как типизированные
  /// входы: проблемы приложения переводятся, проблемы загрузчика — как есть.
  List<_Problem> _problems = const [];

  final ClientWorkspace _workspace;
  final Future<ConnectionProfile> Function() _defaultProfile;
  final ProviderSettingsOpener _open;
  final Map<String, String> _environment;
  final String? _codelabHome;

  /// Папка для слоя `projectLocal`; `null` — проектных слоёв нет и
  /// `projectLocal` не предлагается (require-project-folder/design.md, D8).
  /// До итерации B источник — выбранный проект (tasks A2.5); папка сессии в
  /// фокусе (D8) подключается в итерации B.
  final String? Function() _projectDirectory;
  final Logger? _logger;
  final DateTime Function() _now;

  /// «Retry» баннера после записи и сбоя старта агента: повтор намерения
  /// старта (`ConnectionCubit.retryStart`, D13 п. 4, Q22); `null` — кнопки нет.
  final Future<void> Function()? _retryStart;

  late final StreamSubscription<WorkspaceState> _workspaceSubscription;
  StreamSubscription<Object?>? _viewSubscription;
  SessionId? _boundSession;

  /// Профиль подключения, для которого прочитан доступ; смена — повод
  /// перечитать (D5).
  ConnectionProfile? _accessProfile;

  /// Номер загрузки: снимок, пришедший после более новой загрузки или
  /// [close], отбрасывается (D21).
  var _loadAttempt = 0;

  ProviderSettingsSession? _session;
  EditableSettings? _access;
  AgentConfigSnapshot? _snapshot;
  List<ProviderEntryView> _entries = const [];
  String? _activeModel;

  /// Итоги проверок за жизнь страницы: id → данные итога (D10). Хранятся
  /// данные, а не подписи: подписи строятся на текущем языке (D5, правило 1).
  final _results = <String, ProviderCheckOutcome>{};

  /// Идущие проверки: id → номер и источник отмены. Новая проверка строки и
  /// [close] отменяют прежнюю (токен доходит до `ProviderCheck`, D21).
  final _checks = <String, ({int operation, CancelTokenSource cancel})>{};
  var _checkSeq = 0;

  var _saving = false;
  ProviderBanner? _banner;

  /// Читает доступ и конфиг; вызывается при открытии страницы и после каждой
  /// собственной записи.
  Future<void> reload() async {
    final attempt = ++_loadAttempt;
    _accessProfile = _connectedProfile(_workspace.current);
    final profile = _accessProfile ?? await _defaultProfile();
    if (isClosed || attempt != _loadAttempt) {
      return;
    }
    final access = _accessOf(profile);
    switch (access) {
      case RemoteReadOnly(:final endpoint):
        _setReadOnly(_RemoteCause(profileOrigin(endpoint)), access: 'remote');
      case NotManaged(:final agentName):
        _setReadOnly(_UnmanagedCause(agentName), access: 'not_managed');
      case EditableSettings():
        await _loadEditable(attempt, profile, access);
    }
  }

  SettingsAccess _accessOf(ConnectionProfile profile) {
    final dir = _projectDirectory();
    final cwd = dir == null || dir.isEmpty ? null : dir;
    final home = _codelabHome ?? '';
    return switch (profile) {
      EmbeddedProfile() => resolveSettingsAccess(
        kind: AgentLaunchKind.embedded,
        cwd: cwd,
        defaultCodelabHome: home,
      ),
      StdioProfile(:final command, :final args, :final env) =>
        resolveSettingsAccess(
          kind: AgentLaunchKind.stdio,
          command: command,
          args: args,
          env: env,
          cwd: profile.runInProjectDirectory ? cwd : null,
          defaultCodelabHome: home,
        ),
      WebSocketProfile(:final uri) => resolveSettingsAccess(
        kind: AgentLaunchKind.webSocket,
        endpoint: uri,
        defaultCodelabHome: home,
      ),
    };
  }

  void _setReadOnly(_ReadOnlyCause cause, {required String access}) {
    _session = null;
    _access = null;
    _snapshot = null;
    _entries = const [];
    _readOnlyCause = cause;
    _logger?.debug(
      'provider_settings.loaded',
      context: {'providers': 0, 'access': access},
    );
    _emit(_readOnlyState(cause));
  }

  /// Состояние «только чтение» из причины и текущего языка.
  ProviderSettingsReadOnly _readOnlyState(_ReadOnlyCause cause) {
    final l10n = _strings.current;
    return switch (cause) {
      _RemoteCause(:final origin) => ProviderSettingsReadOnly(
        notice: l10n.providersReadOnlyTitle(origin),
        hint: l10n.settingsRemoteHostHint,
        activeModel: _activeModel,
      ),
      _UnmanagedCause(:final agentName) => ProviderSettingsReadOnly(
        notice: l10n.providersNotManaged(agentName),
        activeModel: _activeModel,
      ),
    };
  }

  Future<void> _loadEditable(
    int attempt,
    ConnectionProfile profile,
    EditableSettings access,
  ) async {
    if (access.paths.codelabHome.isEmpty) {
      _setUnreadable(const [_NoHomeProblem()]);
      return;
    }
    final environment = {
      ..._environment,
      if (profile is StdioProfile) ...profile.env,
    };
    final ProviderSettingsSession session;
    final AgentConfigSnapshot snapshot;
    final List<ProviderEntryView> entries;
    try {
      session = await _open(access, environment);
      snapshot = await session.config.snapshot(
        cwd: access.cwd ?? access.paths.codelabHome,
      );
      entries = await providerEntriesOf(
        snapshot,
        environment: environment,
        isSecretSet: session.isSecretSet,
      );
    } on Object catch (error) {
      if (isClosed || attempt != _loadAttempt) {
        return;
      }
      _logger?.warning(
        'provider_settings.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _setUnreadable(const [_CannotReadSettingsProblem()], log: false);
      return;
    }
    if (isClosed || attempt != _loadAttempt) {
      return;
    }
    if (snapshot.issues.isNotEmpty || !snapshot.isReadable(ConfigLayer.user)) {
      _setUnreadable([
        // Проблемы загрузчика — текст ядра агента, как есть (D7).
        for (final issue in snapshot.issues) _LoaderProblem(issue.toString()),
        if (snapshot.issues.isEmpty) const _UserConfigProblem(),
      ]);
      return;
    }
    _session = session;
    _access = access;
    _snapshot = snapshot;
    _entries = entries;
    // Итоги и идущие проверки исчезнувших провайдеров не переживают
    // перечитывание: поздний итог чужой строки не должен появиться (D21).
    for (final id in _checks.keys.toList()) {
      if (!entries.any((e) => e.id == id)) {
        _cancelCheck(id);
      }
    }
    _results.removeWhere((id, _) => !entries.any((e) => e.id == id));
    _logger?.debug(
      'provider_settings.loaded',
      context: {'providers': entries.length, 'access': 'editable'},
    );
    // `_saving` здесь не трогается: перечитывание посреди записи не должно
    // разрешать вторую запись (D21); сбрасывает его только `_finishWrite`.
    _emit(_buildReady());
  }

  void _setUnreadable(List<_Problem> problems, {bool log = true}) {
    _session = null;
    _access = null;
    _snapshot = null;
    _entries = const [];
    _problems = problems;
    if (log) {
      _logger?.warning(
        'provider_settings.unreadable',
        context: {'error_type': 'ConfigIssue'},
      );
    }
    _emit(_unreadableState());
  }

  /// Состояние «config.yaml не читается» из типизированных проблем и языка.
  ProviderSettingsUnreadable _unreadableState() {
    final l10n = _strings.current;
    return ProviderSettingsUnreadable(
      problems: [
        for (final problem in _problems)
          switch (problem) {
            _NoHomeProblem() => l10n.providersProblemNoHome,
            _CannotReadSettingsProblem() =>
              l10n.providersProblemCannotReadSettings,
            _UserConfigProblem() => l10n.providersProblemUserConfig,
            _LoaderProblem(:final text) => text,
          },
      ],
      activeModel: _activeModel,
    );
  }

  ProviderSettingsReady _buildReady() {
    final snapshot = _snapshot!;
    final models = <String>[];
    for (final entry in _entries) {
      for (final model in entry.models) {
        if (!models.contains(model)) {
          models.add(model);
        }
      }
    }
    final backend = _session!.backend;
    final userLayer = snapshot.layers[ConfigLayer.user]!;
    final home = _homeOf(userLayer.path);
    return ProviderSettingsReady(
      rows: [for (final entry in _entries) _rowOf(entry)],
      models: models,
      defaultModel: snapshot.defaultModel,
      keyStorage: KeyStorageView(
        backendId: backend.id,
        writable: backend.writable,
        unavailableReason: backend.unavailableReason,
        openFilePath: backend.id == 'file'
            ? homePathLabel('$home/secrets.yaml', _environment)
            : null,
      ),
      configPath: homePathLabel(userLayer.path, _environment),
      saving: _saving,
      banner: _banner,
      activeModel: _activeModel,
    );
  }

  /// Каталог пользовательского `config.yaml` — дом агента.
  static String _homeOf(String configPath) {
    final slash = configPath.lastIndexOf('/');
    final back = configPath.lastIndexOf(r'\');
    final cut = slash > back ? slash : back;
    return cut <= 0 ? configPath : configPath.substring(0, cut);
  }

  ProviderRow _rowOf(ProviderEntryView entry) {
    final l10n = _strings.current;
    final editable = entry.editable;
    final onlyOne = _entries.length == 1;
    final editRefusal = editable ? _editRefusal(entry) : null;
    final source = entry.source;
    final definedIn = editable
        ? null
        : switch (source.kind) {
            ConfigSourceKind.environment => l10n.providersDefinedInEnvironment,
            _ => l10n.providersDefinedIn(
              homePathLabel(source.label, _environment),
            ),
          };
    final models = entry.models.length;
    // Подпись строки — перечень независимых частей через « · », а не фраза:
    // каждая часть — своё сообщение каталога (D5, правило 7).
    final keyLabel = keyStatusLabel(l10n, entry.key);
    final subtitle = [
      entry.id,
      _kindLabel(l10n, entry.kind),
      ?entry.displayBaseUrl,
      keyLabel,
      l10n.providersModelCount(models),
      ?definedIn,
    ].join(' · ');
    final detail = keyStatusDetail(l10n, entry.key);
    return ProviderRow(
      id: entry.id,
      subtitle: subtitle,
      keyLabel: keyLabel,
      keyText: detail.text,
      keyMono: detail.mono,
      keyTail: detail.tail,
      source: source.kind == ConfigSourceKind.environment
          ? l10n.providersSourceEnvironment
          : homePathLabel(source.label, _environment),
      isDefault: entry.isDefault,
      editable: editable,
      canEdit: editable && editRefusal == null,
      editHint: editRefusal,
      canRemove: editable && !onlyOne,
      unencryptedHost: _unencryptedHost(entry),
      canCheck:
          entry.key is! KeyLiteralInConfig &&
          (entry.kind == null || supportsProviderCheck(entry.kind!)),
      checkHint: entry.kind != null && !supportsProviderCheck(entry.kind!)
          ? l10n.providersCheckUnavailable(entry.kind!)
          : null,
      keyHint: entry.key is KeyLiteralInConfig
          ? l10n.providersKeyHintLiteral
          : null,
      removeHint: editable && onlyOne ? l10n.providersRemoveLast : null,
      check: ProviderCheckView.of(
        _results[entry.id] ?? const CheckNotRun(),
        l10n,
      ),
    );
  }

  /// Хост `http://` к нелокальному адресу, если у провайдера есть ключ:
  /// ключ уходит открытым текстом (SETUP-10). Правило локальных хостов общее с
  /// `ProfileDraft` (`isLocalHost`). Только хост: путь и query в текст не
  /// входят.
  static String? _unencryptedHost(ProviderEntryView entry) {
    final url = Uri.tryParse(entry.baseUrl ?? '');
    if (url == null ||
        url.scheme != 'http' ||
        url.host.isEmpty ||
        isLocalHost(url.host) ||
        entry.key is KeyNone) {
      return null;
    }
    return url.host;
  }

  /// Подпись вида провайдера: названия продуктов не переводятся (D7), вид,
  /// незнакомый app, — значение провода как есть; «Unknown kind» — текст app.
  static String _kindLabel(AppLocalizations l10n, String? kind) =>
      switch (kind) {
        'openai-compatible' => 'OpenAI-compatible',
        'anthropic' => 'Anthropic',
        'gemini' => 'Gemini',
        final other? => other,
        null => l10n.providersUnknownKind,
      };

  /// Почему «Edit» неактивна: правило моста `providerEditRefusal`, общее с
  /// «Remove» и с проверкой автомата при «Save» (D7, D9); тексты разные для
  /// `notEditable` и `multipleLayers`.
  String? _editRefusal(ProviderEntryView entry) {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return null;
    }
    final refusal = providerEditRefusal(snapshot, entry.id);
    return refusal == null
        ? null
        : providerRefusalText(_strings.current, refusal);
  }

  // --- Мастер провайдера ----------------------------------------------------

  /// Открывает мастер на сессии страницы: добавление или правка [editId].
  ///
  /// Автомат строит сессия composition root (`openWizard`): порт ключей и
  /// значение ключа в Cubit не попадают (SETUP-1, D7). `null` — мастер
  /// недоступен: страница не в состоянии записи, провайдера нет или «Edit» для
  /// него неактивна.
  Future<ProviderWizardCubit?> openWizard({String? editId}) async {
    final session = _session;
    final access = _access;
    final current = state;
    if (current is! ProviderSettingsReady ||
        current.saving ||
        session == null ||
        access == null) {
      return null;
    }
    ProviderEntryView? editing;
    if (editId != null) {
      editing = _entries.where((e) => e.id == editId).firstOrNull;
      if (editing == null ||
          _editRefusal(editing) != null ||
          !editing.editable) {
        return null;
      }
    }
    try {
      final flow = await session.openWizard(editing: editing);
      if (isClosed) {
        await flow.dispose();
        return null;
      }
      return ProviderWizardCubit(
        flow: flow,
        access: access,
        backendId: session.backend.id,
        editingId: editId,
        isAgentConnected: _agentConnected,
        startFailed: _startFailed,
        before: _snapshot,
        logger: _logger,
        strings: _strings,
        readSnapshot: () => session.config.snapshot(
          cwd: access.cwd ?? access.paths.codelabHome,
        ),
      );
    } on Object catch (error) {
      _logger?.warning(
        'provider_settings.unreadable',
        context: {'error_type': error.runtimeType.toString()},
      );
      _banner = const ProviderBanner(
        ProviderBannerKind.error,
        CannotOpenWizardMessage(),
      );
      _publishReady();
      return null;
    }
  }

  /// После `ConfigSaved` мастера: баннер [banner] и перечитывание снимка
  /// (D9, spec app-settings «Мастер провайдера в app»).
  Future<void> wizardSaved(ProviderBanner banner) async {
    _banner = banner;
    await reload();
  }

  /// «Retry» баннера: повторяет намерение старта агента одной попыткой.
  Future<void> retryAgentStart() async {
    final retry = _retryStart;
    if (retry != null) {
      await retry();
    }
  }

  /// Последний старт агента закончился сбоем: баннеру нужен «Retry».
  bool _startFailed() =>
      _workspace.current.connection is ConnectionFailed ||
      _workspace.current.connection is ConnectionLost;

  /// Агент подключён: `WorkspaceState.connection` — `Connected` или
  /// `Reconnecting` (D9).
  bool _agentConnected() => _connectedProfile(_workspace.current) != null;

  // --- «Default model» ----------------------------------------------------

  /// Пишет `agent.default_model` в слой, где ключ определён сейчас, если он
  /// редактируемый, иначе в `user` (D10). Модель вне каталога игнорируется.
  Future<void> setDefaultModel(String model) async {
    final current = state;
    final snapshot = _snapshot;
    final session = _session;
    if (current is! ProviderSettingsReady ||
        current.saving ||
        snapshot == null ||
        session == null ||
        !current.models.contains(model)) {
      return;
    }
    final origin = snapshot.originOf('agent.default_model');
    final layer = origin != null && origin.editable
        ? origin.layer!
        : ConfigLayer.user;
    final base = snapshot.layers[layer] ?? snapshot.layers[ConfigLayer.user]!;
    _beginWrite();
    final outcome = await session.config.apply(base, [
      SetValue('agent.default_model', model),
    ]);
    if (isClosed) {
      return;
    }
    if (outcome is ConfigSaved) {
      _logger?.info(
        'provider_settings.default_model_changed',
        context: {'provider_id': model.split('/').first},
      );
      await _finishWrite(
        banner: const ProviderBanner(
          ProviderBannerKind.saved,
          DefaultModelSaved(),
        ),
      );
    } else {
      await _finishWrite(failed: outcome);
    }
  }

  // --- Check ---------------------------------------------------------------

  /// Проверяет список моделей провайдера [id]. Ключ читает адаптер сессии и
  /// сразу передаёт `ProviderCheck`; здесь значения нет (D4, SETUP-1).
  /// Повторная проверка строки отменяет прежнюю.
  Future<void> check(String id) async {
    final current = state;
    final session = _session;
    final entry = _entries.where((e) => e.id == id).firstOrNull;
    if (current is! ProviderSettingsReady || session == null || entry == null) {
      return;
    }
    final key = entry.key;
    if (key is KeyLiteralInConfig) {
      // Значение литерального ключа app не читает (SETUP-1).
      return;
    }
    if (key is KeySecretMissing || (key is KeyFromEnv && !key.isSet)) {
      // Запрос без ключа дал бы заведомый отказ и ввёл бы в заблуждение.
      _results[id] = const CheckKeyMissing();
      _publishReady();
      return;
    }
    final kind = entry.kind;
    if (kind != null && !supportsProviderCheck(kind)) {
      return;
    }
    // Адрес по умолчанию для вида даёт мост (`defaultProviderBaseUrl`).
    final base = entry.baseUrl;
    final url = kind == null
        ? null
        : base == null
        ? defaultProviderBaseUrl(kind)
        : Uri.tryParse(base);
    final operation = ++_checkSeq;
    // Прежняя проверка строки обрывается: её запрос закрывается, итог
    // отбрасывается.
    _cancelCheck(id);
    final cancel = CancelTokenSource();
    _checks[id] = (operation: operation, cancel: cancel);
    if (kind == null || url == null || !url.hasScheme) {
      _checks.remove(id);
      _results[id] = CheckRejected(
        reason: ProviderCheckFailureKind.badResponse,
        at: _now(),
      );
      _publishReady();
      return;
    }
    final previous = _results[id];
    _results[id] = const CheckInProgress();
    _publishReady();
    final log = _logger?.withCorrelation(operationId: '$operation');
    log?.info(
      'provider_settings.check_started',
      context: {'operation_id': operation, 'provider_id': id},
    );
    final watch = Stopwatch()..start();
    ProviderCheckResult result;
    String? errorType;
    try {
      result = await session.checkProvider(
        kind: kind,
        baseUrl: url,
        key: key,
        cancel: cancel.token,
      );
    } on Object catch (error) {
      errorType = error.runtimeType.toString();
      result = const CheckFailure(
        ProviderCheckFailure(
          kind: ProviderCheckFailureKind.badResponse,
          message: 'the check failed',
        ),
      );
    }
    if (isClosed) {
      // `close()` уже записал `check_discarded` для идущих проверок.
      return;
    }
    if (_checks[id]?.operation != operation) {
      // Проверку отменили (повтор, смена подключения, исчезновение строки):
      // `_cancelCheck` уже записал `check_discarded`, итог молча отбрасывается.
      return;
    }
    if (result is CheckCancelled) {
      // Отмена без нашего `cancel()` не должна оставлять строку в `running`:
      // возвращается прежний итог, запись проверки убирается.
      _cancelCheck(id, outcome: 'cancelled');
      if (previous == null) {
        _results.remove(id);
      } else {
        _results[id] = previous;
      }
      _publishReady();
      return;
    }
    _checks.remove(id);
    final String outcome;
    switch (result) {
      case CheckOk(:final models):
        outcome = 'ok';
        _results[id] = CheckSucceeded(
          models: models.length,
          durationMs: watch.elapsedMilliseconds,
          at: _now(),
        );
      case CheckCancelled():
        // Недостижимо: отменённый итог отброшен выше.
        return;
      case CheckFailure(:final failure):
        outcome = failure.kind.name;
        _results[id] = CheckRejected(
          reason: failure.kind,
          status: failure.statusCode,
          at: _now(),
        );
    }
    log?.info(
      'provider_settings.check_finished',
      context: {
        'operation_id': operation,
        'provider_id': id,
        'outcome': outcome,
        'duration_ms': watch.elapsedMilliseconds,
        'error_type': ?errorType,
      },
    );
    _publishReady();
  }

  // --- Remove --------------------------------------------------------------

  /// Данные диалога `Remove provider <id>?`; `null` — провайдера нет.
  ProviderRemovalPlan? removalPlan(String id) {
    final snapshot = _snapshot;
    if (snapshot == null || !_entries.any((e) => e.id == id)) {
      return null;
    }
    final defaultModel = snapshot.defaultModel;
    return ProviderRemovalPlan(
      providerId: id,
      offersKeyDeletion: ProviderRemover.ownedSecretName(snapshot, id) != null,
      needsNewDefault: defaultModel != null && defaultModel.startsWith('$id/'),
      newDefaultChoices: [
        for (final entry in _entries)
          if (entry.id != id) ...entry.models,
      ],
    );
  }

  /// Удаляет провайдера [id] одной записью; секрет — после `ConfigSaved`
  /// (SETUP-24). `true` — провайдер удалён. Последнего провайдера и
  /// провайдера из нередактируемого слоя не удаляет.
  Future<bool> remove(
    String id, {
    String? newDefaultModel,
    bool deleteStoredKey = false,
  }) async {
    final current = state;
    final snapshot = _snapshot;
    final session = _session;
    final row = current is ProviderSettingsReady
        ? current.rows.where((r) => r.id == id).firstOrNull
        : null;
    if (current is! ProviderSettingsReady ||
        current.saving ||
        snapshot == null ||
        session == null ||
        row == null ||
        !row.canRemove) {
      return false;
    }
    final ownedSecret = ProviderRemover.ownedSecretName(snapshot, id);
    _cancelCheck(id);
    _results.remove(id);
    _beginWrite();
    final outcome =
        await ProviderRemover(
          config: session.config,
          deleteSecret: session.deleteSecret,
        ).remove(
          snapshot,
          providerId: id,
          newDefaultModel: newDefaultModel,
          deleteStoredKey: deleteStoredKey,
        );
    if (isClosed) {
      return outcome is ProviderRemoved;
    }
    switch (outcome) {
      case ProviderRemoved(:final secret):
        _results.remove(id);
        _logger?.info(
          'provider_settings.removed',
          context: {
            'provider_id': id,
            'key_deleted': secret == SecretCleanup.deleted,
          },
        );
        await _finishWrite(
          banner: ProviderBanner(
            secret == SecretCleanup.failed
                ? ProviderBannerKind.error
                : ProviderBannerKind.saved,
            ProviderRemovedMessage(id, secret, ownedSecret),
          ),
        );
        return true;
      case ProviderRemovalNotSaved(:final outcome):
        await _finishWrite(failed: outcome);
        return false;
      case ProviderRemovalRefused(:final reason):
        await _finishWrite(
          banner: ProviderBanner(
            ProviderBannerKind.error,
            ProviderRemovalRefusedMessage(reason),
          ),
        );
        return false;
    }
  }

  // --- Запись --------------------------------------------------------------

  void _beginWrite() {
    _saving = true;
    _banner = null;
    _publishReady();
  }

  /// Итог записи в баннер и перечитывание снимка (после любого исхода: файл
  /// мог измениться, а отказ оставляет страницу прежней).
  ///
  /// [failed] — неуспешный исход записи: баннер по его виду и событие
  /// `provider_settings.save_failed` только с видом исхода, без текстов
  /// проблем (D18). [banner] — готовый баннер успеха или отказа политики.
  Future<void> _finishWrite({
    ConfigSaveOutcome? failed,
    ProviderBanner? banner,
  }) async {
    switch (failed) {
      case ConfigConflict():
        _banner = const ProviderBanner(
          ProviderBannerKind.conflict,
          ConfigConflictMessage(),
        );
        _logSaveFailed('conflict');
      case ConfigRejected(:final issues):
        _banner = ProviderBanner(
          ProviderBannerKind.error,
          // Тексты проверки ядра агента — как есть внутри переведённой рамки.
          ConfigRejectedMessage(configIssuesText(issues)),
        );
        _logSaveFailed('rejected');
      case ConfigInlineSecret(:final key):
        _banner = ProviderBanner(
          ProviderBannerKind.error,
          ConfigInlineSecretMessage(key),
        );
        _logSaveFailed('inline_secret');
      case ConfigSaved():
      case null:
        _banner = banner;
    }
    _saving = false;
    await reload();
  }

  void _logSaveFailed(String outcome) => _logger?.warning(
    'provider_settings.save_failed',
    context: {'outcome': outcome},
  );

  /// Отменяет идущую проверку строки [id]: токен обрывает запрос, итог
  /// отбрасывается, пишется `provider_settings.check_discarded` (D21).
  void _cancelCheck(String id, {String outcome = 'superseded'}) {
    final running = _checks.remove(id);
    if (running == null) {
      return;
    }
    running.cancel.cancel();
    _logger
        ?.withCorrelation(operationId: '${running.operation}')
        .debug(
          'provider_settings.check_discarded',
          context: {
            'operation_id': running.operation,
            'provider_id': id,
            'outcome': outcome,
          },
        );
  }

  // --- Рабочее пространство -------------------------------------------------

  static ConnectionProfile? _connectedProfile(WorkspaceState state) =>
      state.connection is Connected || state.connection is Reconnecting
      ? state.profile
      : null;

  void _onWorkspace(WorkspaceState next) {
    _bindSession(next.activeSessionId);
    final profile = _connectedProfile(next);
    if (profile != _accessProfile) {
      // Смена подключения перечитывает доступ (D5); проверки и итоги прежнего
      // агента относятся к другим настройкам и отбрасываются (D21).
      for (final id in _checks.keys.toList()) {
        _cancelCheck(id);
      }
      _results.clear();
      unawaited(reload());
    }
  }

  /// Подписывается на опции активной сессии ради «Active in this session».
  void _bindSession(SessionId? id) {
    if (id == _boundSession && _viewSubscription != null) {
      return;
    }
    unawaited(_viewSubscription?.cancel());
    _viewSubscription = null;
    _boundSession = id;
    final handle = id == null ? null : _workspace.session(id);
    _setActiveModel(handle);
    if (handle != null) {
      _viewSubscription = handle.view.listen((view) {
        final model = _modelOf(handle);
        if (model != _activeModel) {
          _activeModel = model;
          _republish();
        }
      });
    }
  }

  void _setActiveModel(SessionHandle? handle) {
    _activeModel = handle == null ? null : _modelOf(handle);
    _republish();
  }

  static String? _modelOf(SessionHandle handle) {
    for (final option in handle.current.configOptions) {
      if (option.id == 'model') {
        return option.currentValue;
      }
    }
    return null;
  }

  /// Обновляет `activeModel` в уже опубликованном состоянии.
  void _republish() {
    final current = state;
    if (isClosed) {
      return;
    }
    switch (current) {
      case ProviderSettingsReady():
        emit(current.copyWith(activeModel: () => _activeModel));
      case ProviderSettingsReadOnly(:final notice, :final hint):
        emit(
          ProviderSettingsReadOnly(
            notice: notice,
            hint: hint,
            activeModel: _activeModel,
          ),
        );
      case ProviderSettingsUnreadable(:final problems):
        emit(
          ProviderSettingsUnreadable(
            problems: problems,
            activeModel: _activeModel,
          ),
        );
      case ProviderSettingsLoading():
        break;
    }
  }

  /// Смена языка: пересобирает текст текущего состояния из последних входов
  /// (снимок, итоги проверок данными, причина «только чтение», проблемы).
  /// Конфиг не перечитывается, агент не опрашивается, баннер (типизированный)
  /// остаётся и переводится в presentation. После `close` — игнорируется.
  void _handleLanguage(AppLocalizations _) {
    if (isClosed) {
      return;
    }
    switch (state) {
      case ProviderSettingsReady():
        _publishReady();
      case ProviderSettingsReadOnly():
        final cause = _readOnlyCause;
        if (cause != null) {
          emit(_readOnlyState(cause));
        }
      case ProviderSettingsUnreadable():
        emit(_unreadableState());
      case ProviderSettingsLoading():
        break;
    }
  }

  void _publishReady() {
    if (isClosed || _snapshot == null || _session == null) {
      return;
    }
    emit(_buildReady());
  }

  void _emit(ProviderSettingsState next) {
    if (!isClosed) {
      emit(next);
    }
  }

  @override
  Future<void> close() async {
    await _languageSubscription.cancel();
    // Токен обрывает запрос и закрывает соединение; поздний итог не меняет
    // страницу (D21).
    for (final MapEntry(:key, :value) in _checks.entries) {
      value.cancel.cancel();
      final operation = value.operation;
      _logger
          ?.withCorrelation(operationId: '$operation')
          .debug(
            'provider_settings.check_discarded',
            context: {
              'operation_id': operation,
              'provider_id': key,
              'outcome': 'closed',
            },
          );
    }
    _checks.clear();
    await _viewSubscription?.cancel();
    await _workspaceSubscription.cancel();
    return super.close();
  }
}

/// Причина состояния «только чтение»: вход проекции, из которого текст
/// InfoBar строится на текущем языке (D5, правило 1).
sealed class _ReadOnlyCause {
  const _ReadOnlyCause();
}

/// Агент удалённый: [origin] — `scheme://host:port` без пути и запроса.
final class _RemoteCause extends _ReadOnlyCause {
  const _RemoteCause(this.origin);

  final String origin;
}

/// Агент сторонний: настройками управляет [agentName].
final class _UnmanagedCause extends _ReadOnlyCause {
  const _UnmanagedCause(this.agentName);

  final String agentName;
}

/// Проблема нечитаемой конфигурации. Проблемы приложения переводятся по
/// типу; [_LoaderProblem] — текст загрузчика ядра агента, как есть (D7).
sealed class _Problem {
  const _Problem();
}

final class _NoHomeProblem extends _Problem {
  const _NoHomeProblem();
}

final class _CannotReadSettingsProblem extends _Problem {
  const _CannotReadSettingsProblem();
}

final class _UserConfigProblem extends _Problem {
  const _UserConfigProblem();
}

final class _LoaderProblem extends _Problem {
  const _LoaderProblem(this.text);

  final String text;
}
