/// Автомат мастера провайдера (`dart-agent-and-clients` §12.4.4; design.md
/// change `add-provider-setup-ui`, D7, D8, D21).
library;

import 'dart:async';

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show
        CancelTokenSource,
        ConfigLayer,
        ConfigTarget,
        LogLevel,
        Logger,
        builtinModelInfo,
        safeDefaultContextWindow;
import 'package:meta/meta.dart';

import '../access/settings_access.dart';
import '../config/agent_config_store.dart';
import '../config/config_source_view.dart';
import '../secret/secret_value.dart';
import '../views/key_status_view.dart';
import '../views/provider_entry_view.dart';
import 'provider_check.dart';
import 'provider_keys.dart';
import 'provider_presets.dart';
import 'provider_remover.dart';
import 'provider_setup_committer.dart';
import 'provider_setup_plan.dart';
import 'provider_setup_state.dart';

export 'provider_setup_state.dart';

/// Текст ошибки шага адреса с userinfo (D7, Q11).
const _userinfoError = 'Remove the user name and password from the address.';

/// Мастер добавления и правки провайдера: один автомат на CLI и app (SETUP-8).
///
/// Почему автомат: шаги, отказы проверки, поздние результаты и запись имеют
/// невозможные сочетания, которые набор флагов не запретит (`AGENTS.md` §8).
/// Побочные эффекты — только через порты: [ProviderCheck], [ProviderKeys] и
/// [ProviderSetupCommitter]; сам автомат — чистый Dart без `dart:io`.
///
/// Для чего: клиенты лишь посылают события ([dispatch]) и показывают
/// [current] / [states]; тексты шагов и порядок записи они не знают.
///
/// Как использовать: composition root строит автомат с портами, `isLocalHost`
/// kit (правило «локальный хост» одно, D8) и снимком конфига; по
/// [Done]/[Cancelled] клиент вызывает [dispose]. Правка —
/// параметр [editing]. [forceDefault] — «Make default» нельзя снять (первый
/// запуск CLI, баннер D26).
///
/// Конкурентность (D21): проверка имеет номер попытки; «Retry», «Back»,
/// «Cancel» и [dispose] делают её устаревшей и отменяют `CancelToken`, а её
/// поздний результат отбрасывается с `provider_wizard.check_discarded`.
final class ProviderSetupFlow {
  ProviderSetupFlow({
    required ProviderCheck check,
    required ProviderSetupCommitter committer,
    required ProviderKeys keys,
    required AgentConfigSnapshot snapshot,
    required EditableSettings access,
    required Map<String, String> environment,
    required bool Function(String host) isLocalHost,
    required Logger logger,
    List<ProviderPreset> presets = ProviderPresets.all,
    ProviderEntryView? editing,
    bool forceDefault = false,
    Duration checkTimeout = defaultProviderCheckTimeout,
    Stopwatch Function() newStopwatch = Stopwatch.new,
    required ProviderWizardEntry entry,
  }) : _check = check,
       _committer = committer,
       _keys = keys,
       _snapshot = snapshot,
       _access = access,
       _environment = environment,
       _isLocalHost = isLocalHost,
       _logger = logger,
       _presets = presets,
       _editing = editing,
       _forceDefault = forceDefault,
       _checkTimeout = checkTimeout,
       _newStopwatch = newStopwatch {
    if (editing case final view?) {
      var base =
          view.baseUrl ?? defaultProviderBaseUrl(view.kind ?? '')?.toString();
      String? initialError;
      // В конфиге мог остаться адрес с userinfo (запись вне мастера): в
      // черновик и поле он не попадает, query сохраняется, а шаг просит
      // убрать имя и пароль (Q11, SETUP-1).
      final parsed = base == null ? null : Uri.tryParse(base);
      if (parsed != null && parsed.userInfo.isNotEmpty) {
        base = parsed.replace(userInfo: '').toString();
        initialError = _userinfoError;
      }
      _draft = ProviderDraft(
        providerId: view.id,
        kind: view.kind ?? 'openai-compatible',
        baseUrl: base,
      );
      _state = EnteringBaseUrl(_draft!, error: initialError);
    } else {
      _state = ChoosingPreset(List.unmodifiable(presets));
    }
    _logger.log(
      LogLevel.info,
      'provider_wizard.started',
      fields: {'mode': editing != null ? 'edit' : 'add', 'entry': entry.wire},
    );
  }

  final ProviderCheck _check;
  final ProviderSetupCommitter _committer;
  final ProviderKeys _keys;
  AgentConfigSnapshot _snapshot;
  final EditableSettings _access;
  final Map<String, String> _environment;
  final bool Function(String host) _isLocalHost;
  final Logger _logger;
  final List<ProviderPreset> _presets;
  ProviderEntryView? _editing;
  final bool _forceDefault;
  final Duration _checkTimeout;
  final Stopwatch Function() _newStopwatch;

  final _controller = StreamController<ProviderSetupState>.broadcast();
  late ProviderSetupState _state;
  ProviderDraft? _draft;
  var _disposed = false;

  // Номер текущей проверки и её отмена (D7, D21).
  var _attempt = 0;
  CancelTokenSource? _cancelSource;

  // Попытка в полёте: её устаревание пишет `check_discarded` один раз.
  ({int attempt, ProviderDraft draft})? _flight;

  // Счётчик шага: устаревает ответ порта, пришедший после смены состояния.
  var _epoch = 0;

  List<RemoteModel> _models = const [];
  var _checked = true;
  bool? _makeDefaultChoice;
  ConfigTarget? _targetChoice;

  /// Текущее состояние.
  ProviderSetupState get current => _state;

  /// Состояния по мере смены (broadcast, без повторной выдачи прежних).
  Stream<ProviderSetupState> get states => _controller.stream;

  /// Держит ли автомат значение ключа (проверка тестом «сброс ссылки», D7).
  @visibleForTesting
  bool get holdsSecret => _draft?.key is StoreSecret;

  /// Принимает событие; не к месту — игнор и запись `debug`.
  void dispatch(ProviderSetupEvent event) {
    if (_disposed) {
      return;
    }
    final state = _state;
    switch ((state, event)) {
      case (ChoosingPreset(), final PresetChosen e):
        _onPreset(e);
      case (final EnteringBaseUrl s, final BaseUrlSubmitted e):
        _onBaseUrl(s, e.text);
      case (final EnteringBaseUrl s, final InsecureAddressConfirmed e)
          when s.insecureHost != null:
        _onInsecureConfirmed(s, e.text);
      case (final ChoosingKey s, final KeySubmitted e) when s.ready:
        _onKey(s, e);
      case (CheckFailed(), RetryCheck()):
        _startCheck(_draft!);
      case (final CheckFailed s, final SkipCheck e):
        _onSkip(s, e.confirmed);
      case (final CheckFailed s, UseV1Address()) when s.canUseV1:
        _onUseV1(s);
      case (final ChoosingModel s, final ModelChosen e):
        _onModelChosen(s, e.modelId);
      case (ChoosingModel(), final ModelEnteredManually e):
        _onManual(e.modelId);
      case (final CheckFailed s, final ModelEnteredManually e):
        _onManualAfterNotFound(s, e.modelId);
      case (final EnteringModelDetails s, final ModelDetailsSubmitted e):
        _onDetails(s, e);
      case (final Reviewing s, final ReviewEdited e):
        _onReviewEdited(s, e);
      case (final Reviewing s, ConfirmSave()):
        _onConfirmSave(s);
      case (_, Back()):
        _onBack(state);
      case (_, Cancel()):
        _onCancel(state);
      default:
        _ignore(event);
    }
  }

  /// Отменяет проверку, сбрасывает ссылку на значение ключа и закрывает поток.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _invalidateCheck();
    _epoch++;
    _draft = null;
    await _controller.close();
  }

  // --- шаги ---

  void _onPreset(PresetChosen event) {
    final preset = _presets.where((p) => p.id == event.presetId).firstOrNull;
    if (preset == null) {
      _ignore(event);
      return;
    }
    _draft = ProviderDraft(
      preset: preset,
      providerId: preset.isCustom ? '' : _uniqueId(preset.id),
      kind: preset.kind,
      baseUrl: preset.baseUrl,
    );
    _emit(EnteringBaseUrl(_draft!));
  }

  void _onBaseUrl(EnteringBaseUrl state, String text) {
    final draft = _draft!;
    final parsed = _parseAddress(text);
    if (parsed.error case final error?) {
      _logger.log(
        LogLevel.info,
        'provider_wizard.address_rejected',
        fields: {'reason': parsed.reason},
      );
      _emit(EnteringBaseUrl(draft, error: error));
      return;
    }
    final uri = parsed.uri!;
    final url = parsed.normalized!;
    if (uri.scheme == 'http' &&
        draft.confirmedInsecureUrl != url &&
        !_isLocalHost(uri.host)) {
      _draft = draft.copyWith(baseUrl: url);
      _logger.log(
        LogLevel.info,
        'provider_wizard.insecure_address',
        fields: {'origin': _origin(uri)},
      );
      _emit(EnteringBaseUrl(_draft!, insecureHost: uri.host));
      return;
    }
    _acceptAddress(draft, url, uri);
  }

  /// Подтверждение действует только на адрес, который сейчас в поле: иначе
  /// текст разбирается как `BaseUrlSubmitted` и подтверждение не переносится на
  /// прежний адрес.
  void _onInsecureConfirmed(EnteringBaseUrl state, String text) {
    final draft = _draft!;
    final parsed = _parseAddress(text);
    if (parsed.normalized == null || parsed.normalized != draft.baseUrl) {
      _onBaseUrl(state, text);
      return;
    }
    final url = parsed.normalized!;
    _acceptAddress(draft.copyWith(confirmedInsecureUrl: url), url, parsed.uri!);
  }

  void _acceptAddress(ProviderDraft draft, String url, Uri uri) {
    var next = draft.copyWith(baseUrl: url);
    if (_editing == null && (draft.preset?.isCustom ?? false)) {
      next = next.copyWith(providerId: _uniqueId(_idFromHost(uri)));
    }
    _draft = next;
    _enterKey(next);
  }

  /// Шаг ключа: до ответа порта `stored` шаг не принимает `KeySubmitted`.
  void _enterKey(ProviderDraft draft, {String? error}) {
    _draft = draft.copyWith(clearKey: true);
    final base = _draft!;
    final name = _secretNameOf(base.providerId);
    final epoch = ++_epoch;
    _emit(_keyState(base, ready: false, existing: null, error: error));
    unawaited(() async {
      bool exists;
      try {
        exists = await _keys.stored(name);
      } on Object catch (error) {
        _logger.log(
          LogLevel.warning,
          'provider_wizard.keys_unavailable',
          fields: {'error_type': error.runtimeType.toString()},
        );
        exists = false;
      }
      if (_disposed || epoch != _epoch) {
        return;
      }
      _emit(
        _keyState(
          base,
          ready: true,
          existing: exists ? name : null,
          error: error,
        ),
      );
    }());
  }

  ChoosingKey _keyState(
    ProviderDraft draft, {
    required bool ready,
    required String? existing,
    String? error,
  }) {
    final editing = _editing;
    final literal = editing?.key is KeyLiteralInConfig;
    final keepable = editing != null
        ? editing.key is! KeyLiteralInConfig && editing.key is! KeyNone
        : existing != null;
    return ChoosingKey(
      draft,
      backend: _keys.backend,
      ready: ready,
      canStoreSecret: _keys.backend.writable,
      canKeepStored: ready && keepable,
      readOnlyHint: _keys.backend.writable ? null : _keys.readOnlyHint,
      existingSecret: existing,
      error: error,
      notice: literal
          ? 'The key is written in config.yaml. Choose where to keep it instead.'
          : null,
      suggestedEnvVar: draft.preset?.suggestedEnvVar,
    );
  }

  void _onKey(ChoosingKey state, KeySubmitted event) {
    final draft = state.draft;
    final choice = event.choice;
    final name = _secretNameOf(draft.providerId);
    String? error;
    switch (choice) {
      case StoreSecret(:final value):
        if (!state.canStoreSecret) {
          error =
              state.readOnlyHint ??
              state.backend.unavailableReason ??
              'The secret store is read-only.';
        } else if (value.isEmpty) {
          error = 'Enter the API key.';
        } else if (state.existingSecret != null && !event.replaceExisting) {
          error =
              'A stored key ${state.existingSecret} already exists in '
              '${state.backend.id}.';
        }
      case KeepStoredSecret():
        if (!state.canKeepStored) {
          error = 'There is no stored key to keep.';
        }
      case UseEnvVar(:final name):
        if (name.trim().isEmpty) {
          error = 'Enter the environment variable name.';
        }
      case NoKey():
        break;
    }
    if (error != null) {
      _emit(
        _keyState(
          draft,
          ready: true,
          existing: state.existingSecret,
          error: error,
        ),
      );
      return;
    }
    _draft = draft.copyWith(
      key: choice,
      secretName: switch (choice) {
        StoreSecret() => name,
        KeepStoredSecret() => _editing == null ? name : null,
        _ => null,
      },
      replaceSecret:
          choice is StoreSecret &&
          event.replaceExisting &&
          state.existingSecret != null,
      clearNotVerified: true,
    );
    _startCheck(_draft!);
  }

  // --- проверка ---

  void _startCheck(ProviderDraft draft) {
    _invalidateCheck();
    _draft = draft.copyWith(clearNotVerified: true);
    final attempt = _attempt;
    _flight = (attempt: attempt, draft: _draft!);
    final source = _cancelSource = CancelTokenSource();
    final probe = _probeUrl(_draft!);
    final stopwatch = _newStopwatch()..start();
    _emit(Checking(_draft!, probe, attempt));
    unawaited(_runCheck(attempt, source, _draft!, probe, stopwatch));
  }

  Future<void> _runCheck(
    int attempt,
    CancelTokenSource source,
    ProviderDraft draft,
    Uri probe,
    Stopwatch stopwatch,
  ) async {
    SecretValue? key;
    try {
      key = await _checkKey(draft);
    } on Object catch (error) {
      // Хранилище не прочиталось: запрос без ключа покажет отказ провайдера.
      _logger.log(
        LogLevel.warning,
        'provider_wizard.keys_unavailable',
        fields: {'error_type': error.runtimeType.toString()},
      );
    }
    if (_disposed || attempt != _attempt) {
      return;
    }
    final result = await _check.listModels(
      draft.kind,
      Uri.parse(draft.baseUrl!),
      key,
      timeout: _checkTimeout,
      cancel: source.token,
    );
    stopwatch.stop();
    if (_disposed || attempt != _attempt) {
      // Попытка устарела: `check_discarded` уже записан в `_invalidateCheck`
      // (один источник), поздний результат молча отбрасывается (D21).
      return;
    }
    _flight = null;
    if (result is CheckCancelled) {
      // Отмена — решение владельца, состояние не меняет (D21).
      return;
    }
    switch (result) {
      case CheckOk(:final models):
        _models = List.unmodifiable(models);
        _checked = true;
        _logger.log(
          LogLevel.info,
          'provider_wizard.check_finished',
          fields: _checkFields(attempt, draft, 'ok'),
        );
        _emit(_modelState(_draft!, checked: true));
      case CheckFailure(:final failure):
        _logger.log(
          LogLevel.info,
          'provider_wizard.check_finished',
          fields: _checkFields(
            attempt,
            draft,
            failure.kind.name,
            status: failure.statusCode,
          ),
        );
        _emit(
          CheckFailed(
            _draft!,
            failure,
            probe,
            stopwatch.elapsed,
            canSkip:
                failure.kind == ProviderCheckFailureKind.unreachable ||
                failure.kind == ProviderCheckFailureKind.timeout,
            canUseV1: _canUseV1(failure, _draft!),
          ),
        );
      case CheckCancelled():
        break;
    }
  }

  /// Ключ запроса проверки (D7): значение черновика, переменная окружения
  /// агента или секрет по ссылке редактируемого провайдера.
  Future<SecretValue?> _checkKey(ProviderDraft draft) async {
    switch (draft.key) {
      case StoreSecret(:final value):
        return value;
      case UseEnvVar(:final name):
        return _fromEnv(name);
      case KeepStoredSecret():
        final editing = _editing;
        if (editing == null) {
          return _keys.read(_secretNameOf(draft.providerId));
        }
        return switch (editing.key) {
          KeyInSecretStore(:final name) ||
          KeySecretMissing(:final name) => await _keys.read(name),
          KeyFromEnv(:final name) => _fromEnv(name),
          _ => null,
        };
      case NoKey() || null:
        return null;
    }
  }

  SecretValue? _fromEnv(String name) {
    final value = _environment[name];
    return value == null || value.isEmpty ? null : SecretValue(value);
  }

  bool _canUseV1(ProviderCheckFailure failure, ProviderDraft draft) {
    if (failure.kind != ProviderCheckFailureKind.notFound ||
        draft.kind != 'openai-compatible') {
      return false;
    }
    final path = Uri.parse(draft.baseUrl!).path;
    return !path.endsWith('/v1');
  }

  void _onUseV1(CheckFailed state) {
    final uri = Uri.parse(state.draft.baseUrl!);
    final next = uri.replace(path: '${uri.path}/v1').toString();
    _startCheck(state.draft.copyWith(baseUrl: next));
  }

  void _onSkip(CheckFailed state, bool confirmed) {
    if (!confirmed || !state.canSkip) {
      _ignore(const SkipCheck(confirmed: false));
      return;
    }
    _draft = state.draft.copyWith(notVerified: state.failure.kind.name);
    _models = const [];
    _checked = false;
    _emit(_modelState(_draft!, checked: false));
  }

  // --- модель ---

  void _onModelChosen(ChoosingModel state, String id) {
    final remote = state.models.where((m) => m.id == id).firstOrNull;
    if (remote == null) {
      _ignore(ModelChosen(id));
      return;
    }
    final window = remote.contextWindow ?? builtinModelInfo(id)?.contextWindow;
    if (window == null) {
      _emit(EnteringModelDetails(state.draft, id, safeDefaultContextWindow));
      return;
    }
    _toReview(
      state.draft.copyWith(
        model: PlannedModel(id: id, contextWindow: window),
      ),
    );
  }

  void _onManual(String id) {
    final draft = _draft!;
    final trimmed = id.trim();
    if (trimmed.isEmpty) {
      _ignore(ModelEnteredManually(id));
      return;
    }
    _emit(
      EnteringModelDetails(
        draft,
        trimmed,
        builtinModelInfo(trimmed)?.contextWindow ?? safeDefaultContextWindow,
      ),
    );
  }

  void _onManualAfterNotFound(CheckFailed state, String id) {
    if (state.failure.kind != ProviderCheckFailureKind.notFound) {
      _ignore(ModelEnteredManually(id));
      return;
    }
    // Сервер не умеет список моделей, но адрес жив: ручной ввод без пропуска.
    _models = const [];
    _checked = true;
    _onManual(id);
  }

  void _onDetails(EnteringModelDetails state, ModelDetailsSubmitted event) {
    String? error;
    if (event.contextWindow <= 0) {
      error = 'Context window must be a positive number.';
    } else if (event.maxOutputTokens != null && event.maxOutputTokens! <= 0) {
      error = 'Max output tokens must be a positive number.';
    }
    if (error != null) {
      _emit(
        EnteringModelDetails(
          state.draft,
          state.modelId,
          state.suggestedContextWindow,
          error: error,
        ),
      );
      return;
    }
    _toReview(
      state.draft.copyWith(
        model: PlannedModel(
          id: state.modelId,
          contextWindow: event.contextWindow,
          maxOutputTokens: event.maxOutputTokens,
        ),
      ),
    );
  }

  ChoosingModel _modelState(ProviderDraft draft, {required bool checked}) =>
      ChoosingModel(
        draft,
        _models,
        checked: checked,
        currentModel: _currentModel(),
      );

  /// Текущая модель правимого провайдера: модель по умолчанию, если она его,
  /// иначе первая объявленная; клиент выделяет её в списке.
  String? _currentModel() {
    final id = _editing?.id;
    if (id == null) {
      return null;
    }
    final models = modelsOf(_snapshot, id);
    final current = _snapshot.defaultModel;
    final prefix = '$id/';
    if (current != null && current.startsWith(prefix)) {
      return current.substring(prefix.length);
    }
    return models.isEmpty ? null : models.first.substring(prefix.length);
  }

  // --- обзор и запись ---

  void _toReview(ProviderDraft draft) {
    _draft = draft;
    _emit(_reviewing(_buildPlan(draft), draft));
  }

  Reviewing _reviewing(
    ProviderSetupPlan plan,
    ProviderDraft draft, {
    String? error,
  }) => Reviewing(plan, [
    if (draft.notVerified case final kind?) 'Not verified: $kind',
  ], error: error);

  ProviderSetupPlan _buildPlan(ProviderDraft draft) {
    final editing = _editing;
    final key = draft.key ?? const NoKey();
    final unset = <String>[];
    if (editing != null) {
      final prefix = 'providers.${draft.providerId}';
      final status = editing.key;
      final hasSecret =
          status is KeyInSecretStore || status is KeySecretMissing;
      final hasEnv = status is KeyFromEnv;
      final hasLiteral = status is KeyLiteralInConfig;
      if (key is StoreSecret) {
        if (hasEnv) unset.add('$prefix.api_key_env');
      } else if (key is UseEnvVar) {
        if (hasSecret) unset.add('$prefix.api_key_secret');
      } else if (key is NoKey) {
        if (hasSecret) unset.add('$prefix.api_key_secret');
        if (hasEnv) unset.add('$prefix.api_key_env');
      }
      // Литерал убирается любым новым источником (R4-4); «оставить» его нельзя.
      if (hasLiteral && key is! KeepStoredSecret) {
        unset.add('$prefix.api_key');
      }
    }
    return ProviderSetupPlan(
      providerId: draft.providerId,
      kind: draft.kind,
      baseUrl: draft.baseUrl,
      key: key,
      secretName: draft.secretName,
      replaceSecret: draft.replaceSecret,
      model: draft.model!,
      makeDefault: _forceDefault
          ? true
          : _makeDefaultChoice ??
                (_snapshot.defaultModel == null ||
                    (_editing?.isDefault ?? false)),
      target: _targetOf(),
      unsetKeys: unset,
    );
  }

  ConfigTarget _targetOf() {
    final editing = _editing;
    if (editing != null) {
      // Слой записи — слой, где лежит провайдер; переключателя нет.
      return editing.source.kind == ConfigSourceKind.projectLocal
          ? ConfigTarget.projectLocal(_access.cwd ?? _snapshot.cwd)
          : const ConfigTarget.user();
    }
    return _targetChoice ?? const ConfigTarget.user();
  }

  void _onReviewEdited(Reviewing state, ReviewEdited event) {
    var plan = state.plan;
    String? error;
    if (event.providerId case final id? when _editing == null) {
      if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(id) ||
          providerIdsOf(_snapshot).contains(id) ||
          plan.key is KeepStoredSecret) {
        error = 'Provider id must be unused and match [a-z0-9_-]+.';
      } else {
        // «Replace it» относился к прежнему имени секрета: на новом имени он не
        // выбирался, и существующий секрет не должен перезаписаться молча
        // (SETUP-5); committer заново спросит `stored` и вернёт на шаг ключа.
        plan = plan.copyWith(
          providerId: id,
          secretName: plan.secretName == null ? null : _secretNameOf(id),
          replaceSecret: false,
        );
        _draft = _draft!.copyWith(
          providerId: id,
          secretName: _draft!.secretName == null ? null : _secretNameOf(id),
          replaceSecret: false,
        );
      }
    }
    if (event.makeDefault case final value? when !_forceDefault) {
      _makeDefaultChoice = value;
      plan = plan.copyWith(makeDefault: value);
    }
    if (event.target case final target? when _editing == null) {
      if (_access.targets.contains(target)) {
        _targetChoice = target;
        plan = plan.copyWith(target: target);
      } else {
        error = 'This target is not available.';
      }
    }
    _emit(_reviewing(plan, _draft!, error: error));
  }

  void _onConfirmSave(Reviewing state) {
    final plan = state.plan;
    final base = _snapshot.layers[plan.target.layer];
    final exists = providerIdsOf(_snapshot).contains(plan.providerId);
    final editRefusal = _editing == null
        ? null
        : providerEditRefusal(_snapshot, plan.providerId);
    final refusal = editRefusal != null
        ? switch (editRefusal) {
            ProviderRemovalRefusal.unknownProvider =>
              PlanRefusal.providerMissing,
            ProviderRemovalRefusal.notEditable => PlanRefusal.notEditable,
            ProviderRemovalRefusal.multipleLayers => PlanRefusal.multipleLayers,
            _ => PlanRefusal.layerUnreadable,
          }
        : base == null
        ? PlanRefusal.layerUnreadable
        : _editing == null && exists
        ? PlanRefusal.providerExists
        : null;
    if (refusal != null || base == null) {
      _emit(
        Reviewing(
          plan,
          state.warnings,
          error: switch (refusal) {
            PlanRefusal.providerExists =>
              'A provider with this id already exists.',
            PlanRefusal.providerMissing =>
              'The provider is no longer in the config.',
            PlanRefusal.notEditable => 'This provider cannot be edited here.',
            PlanRefusal.multipleLayers =>
              'This provider is defined in several config files.',
            _ => 'The config file cannot be read.',
          },
          refusal: refusal,
        ),
      );
      return;
    }
    final epoch = ++_epoch;
    _emit(Saving(plan));
    unawaited(() async {
      ProviderCommitOutcome outcome;
      try {
        outcome = await _committer.commit(plan, base);
      } on Object catch (error) {
        // Порт ключей или конфига бросил: исход — неудачная запись без текста.
        outcome = ProviderConfigNotSaved(
          outcome: null,
          errorType: error.runtimeType.toString(),
          keyReplaced: false,
          rollback: KeyRollback.none,
        );
      }
      if (outcome case ProviderConfigNotSaved(outcome: ConfigConflict())) {
        // Файл изменился после чтения (SETUP-6): повторный «Save» должен идти
        // от свежего отпечатка, иначе конфликт повторится вечно (D9, D21).
        // Черновик и введённый ключ остаются в плане; автоповтора нет.
        try {
          _snapshot = await _committer.reload(cwd: _snapshot.cwd);
        } on Object catch (error) {
          _logger.log(
            LogLevel.warning,
            'provider_wizard.reload_failed',
            fields: {'error_type': error.runtimeType.toString()},
          );
        }
      }
      var next = plan;
      if (outcome case ProviderConfigNotSaved(outcome: ConfigConflict())) {
        next = await _rebuildPlan(plan);
      }
      if (_disposed || epoch != _epoch) {
        return;
      }
      _onCommitted(next, outcome);
    }());
  }

  /// План по свежему снимку после конфликта: «Make default» не перезаписывает
  /// внешнюю правку, `unsetKeys` и слой правки строятся по свежему провайдеру.
  Future<ProviderSetupPlan> _rebuildPlan(ProviderSetupPlan plan) async {
    final draft = _draft;
    if (draft == null) {
      return plan;
    }
    if (_editing case final editing?) {
      try {
        final views = await providerEntriesOf(
          _snapshot,
          environment: _environment,
          isSecretSet: _keys.stored,
        );
        _editing =
            views.where((v) => v.id == editing.id).firstOrNull ?? editing;
      } on Object catch (error) {
        _logger.log(
          LogLevel.warning,
          'provider_wizard.reload_failed',
          fields: {'error_type': error.runtimeType.toString()},
        );
      }
    }
    return _buildPlan(draft);
  }

  void _onCommitted(ProviderSetupPlan plan, ProviderCommitOutcome outcome) {
    switch (outcome) {
      case ProviderCommitted():
        _logger.log(
          LogLevel.info,
          'provider_wizard.saved',
          fields: {
            'provider_id': plan.providerId,
            'key': _keyKind(plan),
            'target': plan.target.layer == ConfigLayer.projectLocal
                ? 'local'
                : 'user',
            'make_default': plan.makeDefault,
            'skipped_check': _draft?.notVerified != null,
          },
        );
        _draft = null;
        _emit(Done(plan.withoutSecretValue(), outcome));
      case ProviderKeyAppeared():
        _logSaveFailed(plan, 'secret_appeared');
        final name = plan.secretName!;
        _draft = _draft!.copyWith(clearKey: true);
        _epoch++;
        _emit(
          _keyState(
            _draft!,
            ready: true,
            existing: name,
            error: 'A stored key $name already exists in ${_keys.backend.id}.',
          ),
        );
      case ProviderKeyNotStored(:final reason):
        _logSaveFailed(plan, 'secret_failed');
        _draft = _draft!.copyWith(clearKey: true);
        _epoch++;
        _emit(_keyState(_draft!, ready: true, existing: null, error: reason));
      case ProviderConfigNotSaved():
        _logSaveFailed(
          plan,
          switch (outcome.outcome) {
            ConfigConflict() => 'conflict',
            ConfigRejected() => 'rejected',
            ConfigInlineSecret() => 'inline_secret',
            _ => 'error',
          },
          rollback: outcome.rollback,
          errorType: outcome.outcome == null ? outcome.errorType : null,
        );
        _emit(SaveFailed(plan, outcome));
    }
  }

  /// `provider_wizard.save_failed` по D18: вид исхода, без текстов и значений.
  void _logSaveFailed(
    ProviderSetupPlan plan,
    String outcome, {
    KeyRollback rollback = KeyRollback.none,
    String? errorType,
  }) => _logger.log(
    LogLevel.warning,
    'provider_wizard.save_failed',
    fields: {
      'provider_id': plan.providerId,
      'outcome': outcome,
      'rollback': rollback.name,
      'error_type': ?errorType,
    },
  );

  /// Поля `check_finished`/`check_discarded` по D18: адрес — только
  /// `scheme://host:port`, без пути, query и имён переменных.
  Map<String, Object?> _checkFields(
    int attempt,
    ProviderDraft draft,
    String outcome, {
    int? status,
  }) => {
    'operation_id': attempt,
    'preset': draft.preset?.id ?? 'edit',
    'endpoint': _origin(Uri.parse(draft.baseUrl!)),
    'outcome': outcome,
    'status': ?status,
  };

  /// `none | env | secret` для события `saved`: источник ключа без имён.
  String _keyKind(ProviderSetupPlan plan) => switch (plan.key) {
    StoreSecret() => 'secret',
    UseEnvVar() => 'env',
    NoKey() => 'none',
    KeepStoredSecret() =>
      plan.secretName != null || _editing?.key is! KeyFromEnv
          ? 'secret'
          : 'env',
  };

  // --- навигация ---

  void _onBack(ProviderSetupState state) {
    switch (state) {
      case EnteringBaseUrl():
        if (_editing != null) {
          _ignore(const Back());
        } else {
          _draft = null;
          _emit(ChoosingPreset(List.unmodifiable(_presets)));
        }
      case ChoosingKey():
        _epoch++;
        _emit(EnteringBaseUrl(_draft!.copyWith(clearKey: true)));
      case Checking(:final draft):
        _invalidateCheck();
        _enterKey(draft);
      case CheckFailed(:final draft, :final failure):
        _invalidateCheck();
        if (failure.kind == ProviderCheckFailureKind.unauthorized) {
          _enterKey(draft);
        } else {
          _emit(EnteringBaseUrl(draft.copyWith(clearKey: true)));
        }
      case ChoosingModel(:final draft):
        _enterKey(draft);
      case EnteringModelDetails(:final draft):
        _emit(_modelState(draft, checked: _checked));
      case Reviewing(:final plan):
        _emit(_modelState(_draft!, checked: _checked));
        assert(plan.providerId.isNotEmpty);
      case SaveFailed(:final plan):
        _emit(_reviewing(plan, _draft!));
      case ChoosingPreset() || Saving() || Done() || Cancelled():
        _ignore(const Back());
    }
  }

  void _onCancel(ProviderSetupState state) {
    if (state is Saving || state is Done || state is Cancelled) {
      _ignore(const Cancel());
      return;
    }
    _invalidateCheck();
    _epoch++;
    _draft = null;
    _logger.log(
      LogLevel.debug,
      'provider_wizard.cancelled',
      fields: {'state': state.runtimeType.toString()},
    );
    _emit(const Cancelled());
  }

  // --- вспомогательное ---

  /// Делает прежнюю попытку устаревшей и отменяет её запрос (мост закрывает
  /// соединение, D8).
  void _invalidateCheck() {
    if (_flight case final flight?) {
      _logger.log(
        LogLevel.debug,
        'provider_wizard.check_discarded',
        fields: _checkFields(flight.attempt, flight.draft, 'discarded'),
      );
      _flight = null;
    }
    _attempt++;
    _cancelSource?.cancel();
    _cancelSource = null;
  }

  void _emit(ProviderSetupState state) {
    _state = state;
    if (!_controller.isClosed) {
      _controller.add(state);
    }
  }

  void _ignore(ProviderSetupEvent event) {
    _logger.log(
      LogLevel.debug,
      'provider_wizard.event_ignored',
      fields: {
        'state': _state.runtimeType.toString(),
        'event': event.runtimeType.toString(),
      },
    );
  }

  String _secretNameOf(String id) => 'codelab/$id';

  /// Адрес для показа проверки: без query, fragment и userinfo (SETUP-1).
  Uri _probeUrl(ProviderDraft draft) {
    final uri = Uri.parse(draft.baseUrl!);
    final suffix = draft.kind == 'anthropic' ? '/v1/models' : '/models';
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: '${uri.path}$suffix',
    );
  }

  /// `scheme://host:port` для журнала: ни пути, ни query, ни userinfo.
  String _origin(Uri uri) =>
      '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';

  String _uniqueId(String base) {
    final taken = providerIdsOf(_snapshot).toSet();
    if (!taken.contains(base)) {
      return base;
    }
    for (var n = 2; ; n++) {
      if (!taken.contains('$base-$n')) {
        return '$base-$n';
      }
    }
  }

  /// `localhost:1234` → `local-1234`; имя приводится к `[a-z0-9_-]+`.
  String _idFromHost(Uri uri) {
    var name = uri.host.toLowerCase();
    // Любой локальный хост (по правилу kit) — `local`: адрес не должен попадать
    // в id провайдера (`127-0-0-1-18765`).
    if (name == 'localhost' || _isLocalHost(uri.host)) {
      name = 'local';
    }
    name = name
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (uri.hasPort) {
      name = name.isEmpty ? '${uri.port}' : '$name-${uri.port}';
    }
    return name.isEmpty ? 'custom' : name;
  }

  /// Разбор адреса шага: `http`/`https`, хост обязателен, userinfo отклоняется
  /// (валидатор ядра секреты в `base_url` не проверяет — Q11), завершающий `/`
  /// убирается; query и fragment допустимы.
  ({Uri? uri, String? normalized, String? error, String reason}) _parseAddress(
    String text,
  ) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      return (
        uri: null,
        normalized: null,
        error: 'Enter an http or https address.',
        reason: 'invalid',
      );
    }
    if (uri.userInfo.isNotEmpty) {
      return (
        uri: null,
        normalized: null,
        error: _userinfoError,
        reason: 'userinfo',
      );
    }
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final normalized = uri.replace(path: path);
    return (
      uri: normalized,
      normalized: normalized.toString(),
      error: null,
      reason: '',
    );
  }
}
