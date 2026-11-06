import 'package:codelab_setup/codelab_setup.dart';

/// Что делает выбранный вариант или отправленное поле шага мастера.
///
/// Почему закрытая иерархия: построчный мастер и оверлей `--ui tui`
/// исполняют действия по-разному (печать в `StringSink` или сообщения ядра
/// экрана), но набор действий один (design.md change `add-provider-setup-ui`,
/// D17, «Общая логика без второй копии»).
sealed class WizardAction {
  const WizardAction();
}

/// Отдать событие автомату: выбор в списке, подтверждение адреса
/// (`InsecureAddressConfirmed`), записи (`ConfirmSave`) и отмену (`Cancel`)
/// исполняет автомат, поэтому отдельных действий для них нет.
final class SendEvent extends WizardAction {
  const SendEvent(this.event);

  final ProviderSetupEvent event;
}

/// Открыть скрытое поле ключа; [replace] — заменить существующий секрет.
final class AskSecret extends WizardAction {
  const AskSecret({required this.replace});

  final bool replace;
}

/// Открыть поле имени переменной окружения.
final class AskEnvName extends WizardAction {
  const AskEnvName();
}

/// Открыть поле id модели (ручной ввод).
final class AskModelId extends WizardAction {
  const AskModelId();
}

/// Открыть произвольное поле (адрес после отказа подтвердить `http://`).
final class AskField extends WizardAction {
  const AskField(this.field);

  final WizardField field;
}

/// Перерисовать то же поле; [message] — строка перед ним (ошибка ввода).
final class Reask extends WizardAction {
  const Reask([this.message]);

  final String? message;
}

/// Вариант списка: [label] и его [action].
final class WizardOption {
  const WizardOption(this.label, this.action);

  final String label;
  final WizardAction action;
}

/// Описание поля ввода шага.
///
/// [prompt] — начало строки (`? Base URL › `), [initial] — начальное
/// значение, [hidden] — поле ключа. [submit] превращает отправленный текст в
/// действие. Отказ вставки у скрытого поля (`keyRejectedLine`) исполняет
/// вид: строка и то же поле заново.
final class WizardField {
  const WizardField({
    required this.prompt,
    required this.submit,
    this.initial = '',
    this.hidden = false,
  });

  final String prompt;
  final String initial;
  final bool hidden;
  final WizardAction Function(String text) submit;
}

WizardField _baseUrlField(String initial) => WizardField(
  prompt: '? Base URL › ',
  initial: initial,
  submit: (text) => SendEvent(BaseUrlSubmitted(text)),
);

/// Поле ключа: пустое значение — `Enter the API key.`, иначе `KeySubmitted`.
WizardField secretField({required bool replace}) => WizardField(
  prompt: '? API key › ',
  hidden: true,
  submit: (text) => text.isEmpty
      ? const Reask('Enter the API key.')
      : SendEvent(
          KeySubmitted(
            StoreSecret(SecretValue(text)),
            replaceExisting: replace,
          ),
        ),
);

/// Поле имени переменной окружения.
WizardField envNameField() => WizardField(
  prompt: '? Environment variable › ',
  submit: (text) => SendEvent(KeySubmitted(UseEnvVar(text.trim()))),
);

/// Поле id модели; пустое значение — шаг заново.
WizardField modelIdField() => WizardField(
  prompt: '? Model id › ',
  submit: (text) => text.trim().isEmpty
      ? const Reask()
      : SendEvent(ModelEnteredManually(text.trim())),
);

/// Поле для действия «открыть поле» ([AskSecret], [AskEnvName],
/// [AskModelId]); для остальных действий — `null`.
WizardField? fieldOfAction(WizardAction action) => switch (action) {
  AskSecret(:final replace) => secretField(replace: replace),
  AskEnvName() => envNameField(),
  AskModelId() => modelIdField(),
  AskField(:final field) => field,
  _ => null,
};

/// Что показать на шаге [state] мастера: заголовок, строки пояснений,
/// варианты, поле, строку прогресса.
///
/// Почему данные, а не печать: построчный мастер и оверлей TUI рисуют один и
/// тот же шаг; тексты `CliSetup` живут только здесь (D17).
final class WizardStep {
  const WizardStep({
    this.title,
    this.notes = const [],
    this.options = const [],
    this.field,
    this.models,
    this.currentModel,
    this.progress,
    this.waiting = false,
    this.saving = false,
    this.savedProviderId,
    this.failure,
    this.cancelled = false,
    this.backend,
  });

  /// Заголовок списка (`API type`) или `null`.
  final String? title;

  /// Строки перед вводом: ошибка шага, `notice`, причина read-only бэкенда.
  final List<String> notes;

  /// Варианты списка со стрелками.
  final List<WizardOption> options;

  /// Поле ввода шага.
  final WizardField? field;

  /// Id моделей для списка с фильтром (`? Model (type to filter) ›`); пункт
  /// ручного ввода добавляет вид.
  final List<String>? models;

  /// Модель, на которой стоит курсор списка.
  final String? currentModel;

  /// Строка без перевода строки (`Checking <url> … `).
  final String? progress;

  /// Шаг ждёт ответа порта: ввода нет.
  final bool waiting;

  /// Идёт запись: Esc и Ctrl+C блокированы (D21).
  final bool saving;

  /// Мастер закончен записью провайдера с этим id.
  final String? savedProviderId;

  /// Мастер закончен отказом записи: строка для человека.
  final String? failure;

  /// Мастер отменён.
  final bool cancelled;

  /// Хранилище секретов шага ключа (для сводки).
  final String? backend;
}

/// Заголовок отказа проверки `/models` (Q9, D7).
String checkFailureTitle(ProviderCheckFailure failure) =>
    switch (failure.kind) {
      ProviderCheckFailureKind.unauthorized =>
        'Key rejected (${failure.statusCode ?? 401})',
      ProviderCheckFailureKind.unreachable => 'Server unreachable',
      ProviderCheckFailureKind.timeout => 'Timed out after 10 s',
      ProviderCheckFailureKind.tlsError => 'TLS error',
      ProviderCheckFailureKind.notFound =>
        'Model list not found (${failure.statusCode ?? 404})',
      ProviderCheckFailureKind.badResponse =>
        'Unexpected response (${failure.statusCode ?? '?'})',
    };

/// Сводка плана перед записью (артборд `CliSetup`): провайдер, источник
/// ключа, модель и файл. [backend] — хранилище секретов, [path] — файл слоя.
/// Значение ключа в сводку не попадает (SETUP-1), адрес — без userinfo,
/// query и fragment.
List<String> reviewSummary(
  ProviderSetupPlan plan, {
  required String backend,
  String? path,
}) {
  final keyText = switch (plan.key) {
    StoreSecret() ||
    KeepStoredSecret() => 'secret "${plan.secretName}" ($backend)',
    UseEnvVar(:final name) => 'env $name',
    NoKey() => 'none',
  };
  return [
    'Provider "${plan.providerId}"',
    '  (${plan.kind}${plan.baseUrl == null ? '' : ', ${displayBaseUrl(plan.baseUrl) ?? ''}'})',
    '  key    $keyText',
    '  model  ${plan.providerId}/${plan.model.id}'
        '${plan.makeDefault ? ' (default)' : ''}',
    if (path != null) '  file   $path',
  ];
}

/// Строка об отказе записи без значений секретов (D9).
String saveFailureText(ProviderConfigNotSaved failure) =>
    switch (failure.outcome) {
      ConfigConflict() => 'The config file changed; run the command again.',
      ConfigRejected(:final issues) =>
        'The config was rejected: ${issues.map((i) => i.message).join('; ')}',
      ConfigInlineSecret() => 'The config does not accept a literal key.',
      _ => 'Could not save the provider (${failure.errorType ?? 'error'}).',
    };

/// Шаг мастера по состоянию автомата [state].
///
/// [backend] — идентификатор хранилища секретов (запоминается с шага ключа),
/// [pathOf] — путь файла слоя для сводки. Функция чистая: без портов,
/// терминала и `dart:io`.
WizardStep wizardStepOf(
  ProviderSetupState state, {
  String backend = '',
  String Function(ConfigTarget target)? pathOf,
}) {
  switch (state) {
    case ChoosingPreset(:final presets):
      return WizardStep(
        title: 'API type',
        options: [
          for (final p in presets)
            WizardOption(p.label, SendEvent(PresetChosen(p.id))),
        ],
      );
    case EnteringBaseUrl(:final draft, :final error, :final insecureHost):
      return WizardStep(
        notes: [?(error == null ? null : '  $error')],
        field: insecureHost != null
            ? WizardField(
                prompt: '? Send the key unencrypted to $insecureHost? [y/N] ',
                submit: (text) => text.trim().toLowerCase() == 'y'
                    ? SendEvent(InsecureAddressConfirmed(draft.baseUrl ?? ''))
                    // Автомат остаётся на шаге адреса: спросить адрес заново.
                    : AskField(_baseUrlField(draft.baseUrl ?? '')),
              )
            : _baseUrlField(draft.baseUrl ?? ''),
      );
    case final ChoosingKey key:
      return _keyStep(key);
    case Checking(:final probeUrl):
      return WizardStep(progress: 'Checking $probeUrl … ');
    case CheckFailed(:final failure, :final canUseV1, :final canSkip):
      return WizardStep(
        title: 'The check failed',
        notes: ['failed: ${checkFailureTitle(failure)}'],
        options: [
          const WizardOption('Retry', SendEvent(RetryCheck())),
          if (canUseV1)
            const WizardOption(
              'Use the address with /v1',
              SendEvent(UseV1Address()),
            ),
          if (failure.kind == ProviderCheckFailureKind.notFound)
            const WizardOption('Enter model id manually', AskModelId()),
          if (canSkip)
            const WizardOption(
              'Continue without checking',
              SendEvent(SkipCheck(confirmed: true)),
            ),
          const WizardOption('Back', SendEvent(Back())),
        ],
      );
    case ChoosingModel(:final models, :final checked, :final currentModel):
      final note = checked
          ? 'ok, ${models.length} models'
          : 'not verified; the model list is unknown';
      return models.isEmpty
          ? WizardStep(notes: [note], field: modelIdField())
          : WizardStep(
              notes: [note],
              models: [for (final m in models) m.id],
              currentModel: currentModel,
            );
    case EnteringModelDetails(
      :final modelId,
      :final suggestedContextWindow,
      :final error,
    ):
      return WizardStep(
        notes: [?(error == null ? null : '  $error')],
        field: WizardField(
          prompt: '? Context window for $modelId (tokens) › ',
          initial: '$suggestedContextWindow',
          // Проверка значения — у автомата (его ошибка покажется на шаге).
          submit: (text) => SendEvent(
            ModelDetailsSubmitted(
              contextWindow: int.tryParse(text.trim()) ?? 0,
            ),
          ),
        ),
      );
    case Reviewing(:final plan, :final warnings, :final error, :final refusal):
      return WizardStep(
        notes: [
          ...reviewSummary(
            plan,
            backend: backend,
            path: pathOf?.call(plan.target),
          ),
          for (final w in warnings) '  $w',
          ?(error == null ? null : '  $error'),
        ],
        failure: error != null && refusal != null ? error : null,
        field: WizardField(
          prompt: '? Save? [Y/n] ',
          submit: (text) => switch (text.trim().toLowerCase()) {
            '' || 'y' || 'yes' => const SendEvent(ConfirmSave()),
            'n' || 'no' => const SendEvent(Cancel()),
            _ => const Reask(),
          },
        ),
      );
    case Saving():
      return const WizardStep(notes: ['Saving…'], saving: true);
    case SaveFailed(:final failure):
      final text = saveFailureText(failure);
      return WizardStep(notes: [text], failure: text);
    case Done(:final plan):
      return WizardStep(savedProviderId: plan.providerId);
    case Cancelled():
      return const WizardStep(cancelled: true);
  }
}

WizardStep _keyStep(ChoosingKey state) {
  if (!state.ready) {
    return const WizardStep(waiting: true);
  }
  final backend = state.backend.id;
  final secret = 'codelab/${state.draft.providerId}';
  final notes = <String>[
    ?state.notice,
    ?(state.error == null ? null : '  ${state.error}'),
  ];
  final options = <WizardOption>[];
  if (state.canStoreSecret) {
    if (state.existingSecret case final existing?) {
      notes.add('A stored key $existing already exists in $backend.');
      if (state.canKeepStored) {
        options.add(
          const WizardOption(
            'Use the stored key',
            SendEvent(KeySubmitted(KeepStoredSecret())),
          ),
        );
      }
      options.add(const WizardOption('Replace it', AskSecret(replace: true)));
    } else {
      options.add(
        WizardOption(
          'Store in $backend as "$secret"',
          const AskSecret(replace: false),
        ),
      );
    }
  } else {
    // Причина read-only бэкенда (D3) вместо варианта «Store…».
    notes.add(
      state.readOnlyHint ??
          state.backend.unavailableReason ??
          'The secret store is read-only.',
    );
  }
  final env = state.suggestedEnvVar;
  options.add(
    env == null
        ? const WizardOption('Read from an environment variable', AskEnvName())
        : WizardOption(
            'Read from environment variable ($env)',
            SendEvent(KeySubmitted(UseEnvVar(env))),
          ),
  );
  options.add(const WizardOption('No key', SendEvent(KeySubmitted(NoKey()))));
  return WizardStep(
    title: 'API key source',
    notes: notes,
    options: options,
    backend: backend,
  );
}
