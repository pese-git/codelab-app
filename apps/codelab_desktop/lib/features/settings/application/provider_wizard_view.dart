import 'package:codelab_setup/codelab_setup.dart';

import '../../../l10n/app_localizations.dart';
import 'provider_messages.dart';

/// Подписи строки шагов мастера (артборд `Wizard`; design.md change
/// `add-provider-setup-ui`, D7, таблица «Шаги диалога app и ключи») на языке
/// [l10n].
///
/// Почему функция, а не константа: подписи — текст app, язык меняется на ходу
/// (`add-desktop-localization`, D5); presentation вызывает её с `context.l10n`.
List<String> wizardStepLabelsOf(AppLocalizations l10n) => [
  l10n.wizardStepApiType,
  l10n.wizardStepBaseUrl,
  l10n.wizardStepKey,
  l10n.wizardStepCheck,
  l10n.wizardStepModel,
  l10n.wizardStepReview,
];

/// Подпись пресета в списке «API type» по его `id`, а не по английской
/// [ProviderPreset.label] моста.
///
/// Почему по `id`: `label` — текст моста для CLI, разбирать или обрезать его
/// нельзя (`add-desktop-localization`, D5 п. 5, D6 «Тексты моста настроек»).
/// `openai`, `anthropic`, `openrouter` — названия продуктов и остаются как
/// есть (D7); незнакомый `id` (свои пресеты) — `label` моста без перевода.
String wizardPresetLabel(AppLocalizations l10n, ProviderPreset preset) =>
    switch (preset.id) {
      'ollama' => l10n.wizardPresetOllama,
      'custom-openai' => l10n.wizardPresetCustomOpenAi,
      'custom-anthropic' => l10n.wizardPresetCustomAnthropic,
      _ => preset.label,
    };

/// Шаг строки шагов, которому соответствует состояние автомата.
///
/// Почему здесь, а не в `codelab_ui`: виджет строки шагов знает только
/// подписи и индекс, а отображение `ProviderSetupState` на шаг — решение
/// presentation приложения (D19, D7).
int wizardStepIndex(ProviderSetupState state) => switch (state) {
  ChoosingPreset() => 0,
  EnteringBaseUrl() => 1,
  ChoosingKey() => 2,
  Checking() || CheckFailed() => 3,
  ChoosingModel() || EnteringModelDetails() => 4,
  Reviewing() || Saving() || SaveFailed() || Done() || Cancelled() => 5,
};

/// Строка сводки пройденных шагов (`dl` артборда `Wizard`).
final class WizardSummaryRow {
  const WizardSummaryRow(this.label, this.value, {this.mono = false});

  final String label;
  final String value;

  /// Значение набирается моноширинным шрифтом (адрес, путь, имя секрета).
  final bool mono;

  @override
  String toString() => 'WizardSummaryRow($label)';
}

/// Сводка пройденных шагов над телом текущего (design.md D24: тот же каркас
/// для каждого шага). На «Review» — сводка плана `Provider / Key / Model /
/// File`, как в `CliSetup`.
///
/// В сводку не попадает значение ключа (SETUP-1): ключ описан способом
/// хранения, а адрес — через `displayBaseUrl` без userinfo, query и fragment.
List<WizardSummaryRow> wizardSummaryOf(
  ProviderSetupState state, {
  required String backendId,
  required EditableSettings access,
  required AppLocalizations l10n,
}) {
  switch (state) {
    case ChoosingPreset() || Cancelled():
      return const [];
    case EnteringBaseUrl(:final draft):
      return [_type(draft, l10n)];
    case ChoosingKey(:final draft):
      return [_type(draft, l10n), _address(draft, l10n)];
    case Checking(:final draft) ||
        CheckFailed(:final draft) ||
        ChoosingModel(:final draft) ||
        EnteringModelDetails(:final draft):
      return [
        _type(draft, l10n),
        _address(draft, l10n),
        _key(draft, backendId, l10n),
      ];
    case Reviewing(:final plan) ||
        Saving(:final plan) ||
        SaveFailed(:final plan):
      return _plan(plan, backendId, access, l10n);
    case Done(:final plan):
      return _plan(plan, backendId, access, l10n);
  }
}

/// Значение строки «Type» сводки: пресет — по `id` (а не обрезкой английской
/// подписи моста, D5 п. 5), без пресета — вид провайдера.
WizardSummaryRow _type(ProviderDraft draft, AppLocalizations l10n) {
  final preset = draft.preset;
  return WizardSummaryRow(
    l10n.wizardSummaryType,
    preset == null
        ? _kindLabel(draft.kind)
        : switch (preset.id) {
            // В списке «Custom OpenAI-compatible endpoint», в сводке
            // артборда — без слова «endpoint».
            'custom-openai' => l10n.wizardTypeCustomOpenAi,
            'custom-anthropic' => l10n.wizardTypeCustomAnthropic,
            _ => wizardPresetLabel(l10n, preset),
          },
  );
}

WizardSummaryRow _address(ProviderDraft draft, AppLocalizations l10n) =>
    WizardSummaryRow(
      l10n.wizardStepBaseUrl,
      draft.displayBaseUrl ?? '',
      mono: true,
    );

WizardSummaryRow _key(
  ProviderDraft draft,
  String backendId,
  AppLocalizations l10n,
) {
  final name = draft.secretName ?? 'codelab/${draft.providerId}';
  return WizardSummaryRow(l10n.wizardStepKey, switch (draft.key) {
    StoreSecret() => l10n.wizardSummaryKeyStore(backendId, name),
    KeepStoredSecret() when draft.secretName != null =>
      l10n.wizardSummaryKeyUseStored(name),
    KeepStoredSecret() => l10n.wizardKeepCurrentKey,
    UseEnvVar(:final name) => l10n.wizardSummaryKeyEnv(name),
    NoKey() || null => l10n.wizardKeyNone,
  }, mono: draft.key is StoreSecret);
}

List<WizardSummaryRow> _plan(
  ProviderSetupPlan plan,
  String backendId,
  EditableSettings access,
  AppLocalizations l10n,
) {
  final url = _displayUrl(plan.baseUrl);
  return [
    WizardSummaryRow(
      l10n.wizardSummaryProvider,
      '${plan.providerId} (${plan.kind}${url == null ? '' : ', $url'})',
    ),
    WizardSummaryRow(l10n.wizardStepKey, switch (plan.key) {
      StoreSecret() || KeepStoredSecret() when plan.secretName != null =>
        l10n.wizardPlanKeySecret(plan.secretName!, backendId),
      KeepStoredSecret() => l10n.wizardPlanKeyKept,
      UseEnvVar(:final name) => l10n.wizardPlanKeyEnv(name),
      StoreSecret() || NoKey() => l10n.wizardPlanKeyNone,
    }),
    WizardSummaryRow(
      l10n.wizardStepModel,
      '${plan.providerId}/${plan.model.id}',
    ),
    WizardSummaryRow(
      l10n.wizardSummaryFile,
      _configFile(plan.target, access),
      mono: true,
    ),
  ];
}

String _configFile(ConfigTarget target, EditableSettings access) =>
    target.layer == ConfigLayer.projectLocal
    ? '${access.paths.projectDir ?? ''}/.codelab/config.local.yaml'
    : '${access.paths.codelabHome}/config.yaml';

String _kindLabel(String kind) => switch (kind) {
  'openai-compatible' => 'OpenAI-compatible',
  'anthropic' => 'Anthropic',
  final other => other,
};

String? _displayUrl(String? raw) {
  final uri = raw == null ? null : Uri.tryParse(raw);
  if (uri == null || uri.host.isEmpty) {
    return null;
  }
  return Uri(
    scheme: uri.scheme,
    host: uri.host,
    port: uri.hasPort ? uri.port : null,
    path: uri.path,
  ).toString();
}

/// Заголовок отказа проверки (design.md D7, Q9 (а); образец — артборд
/// `Wizard`, `Model list not found (404)`).
String checkFailureTitle(CheckFailed state, {required AppLocalizations l10n}) {
  final status = state.failure.statusCode;
  return switch (state.failure.kind) {
    ProviderCheckFailureKind.unauthorized =>
      status == null
          ? l10n.wizardFailKeyRejected
          : l10n.wizardFailKeyRejectedStatus(status),
    ProviderCheckFailureKind.notFound => l10n.wizardFailNotFound(status ?? 404),
    ProviderCheckFailureKind.unreachable => l10n.wizardFailUnreachable,
    ProviderCheckFailureKind.timeout => l10n.wizardFailTimeout(
      defaultProviderCheckTimeout.inSeconds,
    ),
    ProviderCheckFailureKind.tlsError => l10n.wizardFailTls,
    ProviderCheckFailureKind.badResponse =>
      status == null
          ? l10n.wizardFailUnexpected
          : l10n.wizardFailUnexpectedStatus(status),
  };
}

/// Строка запроса `GET <url>/models → <код> · <n> ms`; без кода у
/// `unreachable`, `timeout`, `tlsError`. Адрес — без query и userinfo
/// (`CheckFailed.probeUrl`).
String checkRequestLine(CheckFailed state) {
  final status = state.failure.statusCode;
  return 'GET ${state.probeUrl}'
      '${status == null ? '' : ' → $status'}'
      ' · ${state.elapsed.inMilliseconds} ms';
}

/// Пояснение в одну строку — только у `notFound` (текст артборда `Wizard`).
String? checkFailureNote(CheckFailed state, {required AppLocalizations l10n}) =>
    state.failure.kind == ProviderCheckFailureKind.notFound
    ? l10n.wizardFailNotFoundNote
    : null;

/// Способ хранения ключа на шаге «API key source».
enum WizardKeyKind { store, keepStored, replace, environment, none }

/// Вариант шага ключа: подпись из `CliSetup` и вид.
final class WizardKeyOption {
  const WizardKeyOption(this.kind, this.label);

  final WizardKeyKind kind;
  final String label;

  @override
  String toString() => 'WizardKeyOption(${kind.name})';
}

/// Варианты шага ключа по состоянию автомата (D3, D7).
///
/// Вариант «Store in …» есть только при записываемом бэкенде; при существующем
/// секрете вместо него — «Use the stored key» и «Replace it» (SETUP-5); при
/// правке с ключом — «Keep the current key». Решение о допустимости остаётся
/// у автомата: виджет лишь показывает варианты.
List<WizardKeyOption> wizardKeyOptions(
  ChoosingKey state, {
  required AppLocalizations l10n,
}) {
  final id = state.draft.providerId;
  final backend = state.backend.id;
  final env = state.suggestedEnvVar;
  return [
    if (state.existingSecret != null) ...[
      WizardKeyOption(WizardKeyKind.keepStored, l10n.wizardKeyUseStored),
      if (state.canStoreSecret)
        WizardKeyOption(WizardKeyKind.replace, l10n.wizardKeyReplace),
    ] else ...[
      if (state.canKeepStored)
        WizardKeyOption(WizardKeyKind.keepStored, l10n.wizardKeepCurrentKey),
      if (state.canStoreSecret)
        WizardKeyOption(
          WizardKeyKind.store,
          l10n.wizardKeyStore(backend, 'codelab/$id'),
        ),
    ],
    WizardKeyOption(
      WizardKeyKind.environment,
      env == null ? l10n.wizardKeyEnv : l10n.wizardKeyEnvNamed(env),
    ),
    WizardKeyOption(WizardKeyKind.none, l10n.wizardKeyNone),
  ];
}

/// Текст неудачной записи для `SaveFailed`: только вид исхода и имена (SETUP-1).
///
/// Текст исключения записи сюда не попадает: он мог процитировать значение, а
/// мост передаёт только имя типа (`errorType`, D9).
String wizardSaveFailureText(
  SaveFailed state, {
  required AppLocalizations l10n,
}) {
  final failure = state.failure;
  final secret = state.plan.secretName;
  // Тексты проверки ядра агента (`ConfigIssue.message`) — как есть внутри
  // переведённой рамки (D6, D7); ключ конфигурации и имя секрета с командой
  // `codelab secret delete` — плейсхолдеры (сценарий «Команда в переведённой
  // фразе»).
  final head = switch (failure.outcome) {
    ConfigRejected(:final issues) => l10n.configNotSavedRejected(
      configIssuesText(issues),
    ),
    ConfigInlineSecret(:final key) => l10n.configNotSavedInlineSecret(key),
    _ =>
      failure.errorType == null
          ? l10n.configNotSavedPlain
          : l10n.configNotSavedErrorType(failure.errorType!),
  };
  return [
    head,
    if (failure.keyReplaced && secret != null)
      l10n.wizardSaveKeyReplaced(secret),
    if (failure.rollback == KeyRollback.failed && secret != null)
      l10n.wizardSaveKeyStillStored(secret),
  ].join(' ');
}

/// Текст ошибки или отказа текущего шага мастера; `null` — ошибки нет.
///
/// Почему по коду, а не по строке: `error` моста — английский текст для CLI, а
/// app строит текст по `errorCode`, `refusal`, `literalKeyInConfig` и
/// `notVerified` и не сравнивает готовые строки (`add-desktop-localization`,
/// D5 п. 5, D6 «Тексты моста настроек»). Аргументы берутся из полей состояния
/// (`existingSecret`, `backend`). Подсказка бэкенда (`readOnlyHint`,
/// `unavailableReason`) и причина хранилища при `keyNotStored` — текст без
/// типа, показывается как есть. Ошибка без кода (нарушение инварианта моста)
/// показывается как есть, чтобы пользователь не потерял сообщение.
String? wizardErrorText(ProviderSetupState state, AppLocalizations l10n) {
  final (error, code, refusal) = switch (state) {
    EnteringBaseUrl(:final error, :final errorCode) => (error, errorCode, null),
    ChoosingKey(:final error, :final errorCode) => (error, errorCode, null),
    EnteringModelDetails(:final error, :final errorCode) => (
      error,
      errorCode,
      null,
    ),
    Reviewing(:final error, :final errorCode, :final refusal) => (
      error,
      errorCode,
      refusal,
    ),
    _ => (null, null, null),
  };
  if (error == null) {
    return null;
  }
  if (refusal != null) {
    return switch (refusal) {
      PlanRefusal.providerExists => l10n.wizardRefusalProviderExists,
      PlanRefusal.providerMissing => l10n.wizardRefusalProviderMissing,
      PlanRefusal.notEditable => l10n.wizardRefusalNotEditable,
      PlanRefusal.multipleLayers => l10n.wizardRefusalSeveralFiles,
      PlanRefusal.layerUnreadable => l10n.wizardRefusalLayerUnreadable,
    };
  }
  return switch (code) {
    ProviderSetupErrorCode.addressInvalid => l10n.wizardErrorAddressInvalid,
    ProviderSetupErrorCode.addressHasUserinfo =>
      l10n.wizardErrorAddressUserInfo,
    ProviderSetupErrorCode.secretStoreReadOnly =>
      state is ChoosingKey
          ? (state.readOnlyHint ??
                state.backend.unavailableReason ??
                l10n.secretStoreReadOnly)
          : error,
    ProviderSetupErrorCode.keyEmpty => l10n.wizardErrorKeyEmpty,
    ProviderSetupErrorCode.keyAlreadyStored =>
      state is ChoosingKey && state.existingSecret != null
          ? l10n.wizardErrorKeyAlreadyStored(
              state.existingSecret!,
              state.backend.id,
            )
          : error,
    ProviderSetupErrorCode.nothingToKeep => l10n.wizardErrorNothingToKeep,
    ProviderSetupErrorCode.envVarEmpty => l10n.wizardErrorEnvVarEmpty,
    ProviderSetupErrorCode.keyNotStored => error,
    ProviderSetupErrorCode.contextWindowInvalid =>
      l10n.wizardErrorContextWindow,
    ProviderSetupErrorCode.maxOutputInvalid => l10n.wizardErrorMaxOutput,
    ProviderSetupErrorCode.providerIdInvalid => l10n.wizardErrorProviderId,
    ProviderSetupErrorCode.targetUnavailable =>
      l10n.wizardErrorTargetUnavailable,
    null => error,
  };
}

/// Ошибка шага ключа — дубль подписи существующего ключа: автомат выставляет
/// `keyAlreadyStored` только вместе с `existingSecret`, поэтому диалог не
/// показывает её отдельно, пока видна подпись (дедупликация по типу, а не по
/// равенству строк: D5 п. 5, D6).
bool isKeyAlreadyStoredError(ChoosingKey state) =>
    state.errorCode == ProviderSetupErrorCode.keyAlreadyStored &&
    state.existingSecret != null;

/// Пояснение шага ключа: ключ записан открытым текстом в `config.yaml`. По
/// признаку `literalKeyInConfig`, а не по `notice` моста.
String? wizardKeyNotice(ChoosingKey state, AppLocalizations l10n) =>
    state.literalKeyInConfig ? l10n.wizardKeyNoticeLiteral : null;

/// Предупреждения обзора: пока одно — «Not verified: …» по `notVerified`.
///
/// `unreachable` и `timeout` на `en` показываются значением провода, на `ru` —
/// словами; незнакомый вид — как есть (D6). `Reviewing.warnings` на экран не
/// выводятся.
List<String> wizardReviewWarnings(Reviewing state, AppLocalizations l10n) => [
  if (state.notVerified case final kind?)
    l10n.wizardNotVerified(switch (kind) {
      'unreachable' => l10n.wizardNotVerifiedUnreachable,
      'timeout' => l10n.wizardNotVerifiedTimeout,
      final other => other,
    }),
];
