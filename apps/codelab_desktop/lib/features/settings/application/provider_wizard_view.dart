import 'package:codelab_setup/codelab_setup.dart';

/// Подписи строки шагов мастера (артборд `Wizard`; design.md change
/// `add-provider-setup-ui`, D7, таблица «Шаги диалога app и ключи»).
const wizardStepLabels = <String>[
  'API type',
  'Base URL',
  'Key',
  'Check',
  'Model',
  'Review',
];

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
}) {
  switch (state) {
    case ChoosingPreset() || Cancelled():
      return const [];
    case EnteringBaseUrl(:final draft):
      return [_type(draft)];
    case ChoosingKey(:final draft):
      return [_type(draft), _address(draft)];
    case Checking(:final draft) ||
        CheckFailed(:final draft) ||
        ChoosingModel(:final draft) ||
        EnteringModelDetails(:final draft):
      return [_type(draft), _address(draft), _key(draft, backendId)];
    case Reviewing(:final plan) ||
        Saving(:final plan) ||
        SaveFailed(:final plan):
      return _plan(plan, backendId, access);
    case Done(:final plan):
      return _plan(plan, backendId, access);
  }
}

WizardSummaryRow _type(ProviderDraft draft) => WizardSummaryRow(
  'Type',
  draft.preset == null
      ? _kindLabel(draft.kind)
      // «Custom OpenAI-compatible endpoint» в списке, «Custom
      // OpenAI-compatible» в сводке артборда.
      : draft.preset!.label.replaceFirst(' endpoint', ''),
);

WizardSummaryRow _address(ProviderDraft draft) =>
    WizardSummaryRow('Base URL', draft.displayBaseUrl ?? '', mono: true);

WizardSummaryRow _key(ProviderDraft draft, String backendId) {
  final name = draft.secretName ?? 'codelab/${draft.providerId}';
  return WizardSummaryRow('Key', switch (draft.key) {
    StoreSecret() => 'Store in $backendId as $name',
    KeepStoredSecret() when draft.secretName != null =>
      'Use the stored key $name',
    KeepStoredSecret() => 'Keep the current key',
    UseEnvVar(:final name) => 'Read from environment variable ($name)',
    NoKey() || null => 'No key',
  }, mono: draft.key is StoreSecret);
}

List<WizardSummaryRow> _plan(
  ProviderSetupPlan plan,
  String backendId,
  EditableSettings access,
) {
  final url = _displayUrl(plan.baseUrl);
  return [
    WizardSummaryRow(
      'Provider',
      '${plan.providerId} (${plan.kind}${url == null ? '' : ', $url'})',
    ),
    WizardSummaryRow('Key', switch (plan.key) {
      StoreSecret() || KeepStoredSecret() when plan.secretName != null =>
        'secret "${plan.secretName}" ($backendId)',
      KeepStoredSecret() => 'kept as is',
      UseEnvVar(:final name) => 'environment variable $name',
      StoreSecret() || NoKey() => 'none',
    }),
    WizardSummaryRow('Model', '${plan.providerId}/${plan.model.id}'),
    WizardSummaryRow('File', _configFile(plan.target, access), mono: true),
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
String checkFailureTitle(CheckFailed state) {
  final status = state.failure.statusCode;
  return switch (state.failure.kind) {
    ProviderCheckFailureKind.unauthorized =>
      status == null ? 'Key rejected' : 'Key rejected ($status)',
    ProviderCheckFailureKind.notFound =>
      'Model list not found (${status ?? 404})',
    ProviderCheckFailureKind.unreachable => 'Server unreachable',
    ProviderCheckFailureKind.timeout =>
      'Timed out after ${defaultProviderCheckTimeout.inSeconds} s',
    ProviderCheckFailureKind.tlsError => 'TLS error',
    ProviderCheckFailureKind.badResponse =>
      status == null ? 'Unexpected response' : 'Unexpected response ($status)',
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
String? checkFailureNote(CheckFailed state) =>
    state.failure.kind == ProviderCheckFailureKind.notFound
    ? 'The server answered, but GET /models does not exist. '
          'OpenAI-compatible servers usually live under /v1.'
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
List<WizardKeyOption> wizardKeyOptions(ChoosingKey state) {
  final id = state.draft.providerId;
  final backend = state.backend.id;
  final env = state.suggestedEnvVar;
  return [
    if (state.existingSecret != null) ...[
      const WizardKeyOption(WizardKeyKind.keepStored, 'Use the stored key'),
      if (state.canStoreSecret)
        const WizardKeyOption(WizardKeyKind.replace, 'Replace it'),
    ] else ...[
      if (state.canKeepStored)
        const WizardKeyOption(WizardKeyKind.keepStored, 'Keep the current key'),
      if (state.canStoreSecret)
        WizardKeyOption(
          WizardKeyKind.store,
          'Store in $backend as "codelab/$id"',
        ),
    ],
    WizardKeyOption(
      WizardKeyKind.environment,
      env == null
          ? 'Read from environment variable'
          : 'Read from environment variable ($env)',
    ),
    const WizardKeyOption(WizardKeyKind.none, 'No key'),
  ];
}

/// Текст неудачной записи для `SaveFailed`: только вид исхода и имена (SETUP-1).
///
/// Текст исключения записи сюда не попадает: он мог процитировать значение, а
/// мост передаёт только имя типа (`errorType`, D9).
String wizardSaveFailureText(SaveFailed state) {
  final failure = state.failure;
  final secret = state.plan.secretName;
  final head = switch (failure.outcome) {
    ConfigRejected(:final issues) =>
      'The config was not saved: ${[for (final i in issues) i.key.isEmpty ? i.message : '${i.key}: ${i.message}'].join('; ')}',
    ConfigInlineSecret(:final key) =>
      'The config was not saved: $key must not hold a literal secret.',
    _ =>
      'The config was not saved'
          '${failure.errorType == null ? '' : ' (${failure.errorType})'}.',
  };
  return [
    head,
    if (failure.keyReplaced && secret != null)
      'The stored key $secret was already replaced.',
    if (failure.rollback == KeyRollback.failed && secret != null)
      'The new key $secret is still in the secret store. Delete it with: '
          'codelab secret delete $secret',
  ].join(' ');
}
