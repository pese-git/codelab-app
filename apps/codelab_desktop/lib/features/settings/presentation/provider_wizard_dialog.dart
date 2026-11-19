import 'package:codelab_setup/codelab_setup.dart';
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/l10n.dart';
import '../application/provider_wizard_cubit.dart';

/// Открывает мастер провайдера поверх [context] и возвращает будущее, которое
/// завершается закрытием диалога.
///
/// Почему функция: диалог — модальное окно над страницей «Providers» или над
/// рабочим местом (баннер соединения), артборд `Wizard` (`ContentDialog`;
/// design.md change `add-provider-setup-ui`, D7, D24). Cubit [cubit] создаёт и
/// закрывает владелец (страница или баннер), чтобы закрытие диалога любым
/// способом отменяло идущую проверку и сбрасывало ключ.
///
/// Для чего: Esc и «Cancel» закрывают мастер без записи, кроме состояния
/// `Saving` (D21). Щелчок по фону диалог не закрывает: случайное нажатие не
/// должно терять введённое. Диалог закрывает себя сам по `Done` и `Cancelled`.
///
/// Как использовать: `await showProviderWizardDialog(context, cubit)`; после
/// возврата владелец читает `cubit.savedBanner` и вызывает `cubit.close()`.
Future<void> showProviderWizardDialog(
  BuildContext context,
  ProviderWizardCubit cubit,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => BlocProvider<ProviderWizardCubit>.value(
      value: cubit,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): cubit.cancel,
        },
        // Без узла фокуса внутри диалога Esc после щелчка по флажку не дошёл
        // бы до привязки.
        child: const Focus(autofocus: true, child: ProviderWizardDialog()),
      ),
    ),
  );
}

/// Ширина диалога артборда `Wizard` (`max-width: 560px`).
const _dialogMaxWidth = 560.0;

/// Минимальная высота содержимого: вмещает самые короткие шаги без скачка.
const _contentMinHeight = 300.0;

/// Содержимое диалога «Add provider» / «Edit provider [id]» (артборд
/// `docs/design/claude-design/Wizard.dc.html`; расхождения — design.md change
/// `add-provider-setup-ui`, D24: тот же каркас для каждого шага).
///
/// Почему: пять шагов с отказами проверки и записью — отдельный модальный
/// сценарий, а не часть страницы (spec app-settings «Мастер провайдера в
/// app»).
///
/// Для чего: только отображение `ProviderWizardState`. Что допустимо на шаге,
/// какие тексты ошибок и какой порядок записи, решает автомат моста; виджет
/// передаёт ввод и нажатия событиями и не знает ни файлов, ни ACP, ни хранилища
/// секретов (AGENTS.md §6, §7, §10). Значение ключа вводится в скрытое поле
/// (`PasswordBox`, без «глазка») и сразу уходит в автомат в `SecretValue`;
/// контроллер поля очищается при закрытии шага (SETUP-1).
///
/// Как использовать: под `BlocProvider<ProviderWizardCubit>`; открывает его
/// [showProviderWizardDialog]. Ключи тела шагов — по таблице D7:
/// `provider-wizard-type`, `-base-url`, `-key`, `-check`, `-model`, `-review`.
class ProviderWizardDialog extends StatelessWidget {
  const ProviderWizardDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProviderWizardCubit, ProviderWizardState>(
      listenWhen: (previous, current) =>
          previous.setup != current.setup &&
          (current.setup is Done || current.setup is Cancelled),
      listener: (context, state) {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        }
      },
      builder: (context, state) => switch (state.setup) {
        final ChoosingPreset setup => _PresetStep(state: state, setup: setup),
        final EnteringBaseUrl setup => _BaseUrlStep(state: state, setup: setup),
        final ChoosingKey setup => _KeyStep(state: state, setup: setup),
        Checking() || CheckFailed() => _CheckStep(state: state),
        final ChoosingModel setup => _ModelStep(state: state, setup: setup),
        final EnteringModelDetails setup => _DetailsStep(
          state: state,
          setup: setup,
        ),
        Reviewing() ||
        Saving() ||
        SaveFailed() ||
        Done() => _ReviewStep(state: state),
        Cancelled() => const SizedBox.shrink(),
      },
    );
  }
}

/// Каркас артборда: заголовок, строка шагов, индикатор шага, сводка пройденных
/// шагов, тело и кнопки внизу.
class _Frame extends StatelessWidget {
  const _Frame({
    required this.state,
    required this.bodyKey,
    required this.body,
    required this.actions,
    this.showSummary = true,
  });

  final ProviderWizardState state;
  final Key bodyKey;
  final Widget body;
  final List<Widget> actions;
  final bool showSummary;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final stepLabels = wizardStepLabelsOf(context.l10n);
    final entries = [
      for (final row in state.summary)
        CodeLabKeyValueEntry(
          label: row.label,
          value: row.mono ? null : row.value,
          monoValue: row.mono ? row.value : null,
        ),
    ];
    // Пока идёт запись, диалог не закрывается (Esc, «Cancel», системный
    // возврат): иначе владелец не узнал бы о записи, а пользователь решил бы,
    // что отменил её (D21).
    return PopScope(
      canPop: cubit.canDismiss,
      child: ContentDialog(
        key: const ValueKey('provider-wizard'),
        constraints: const BoxConstraints(maxWidth: _dialogMaxWidth),
        title: CodeLabDialogTitle(cubit.title),
        // Фиксированный минимум высоты: диалог в артборде `Wizard` стоит по
        // центру окна, и без минимума он прыгал бы по вертикали между шагами
        // разной длины (ручная проверка macOS, D24).
        content: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _contentMinHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                CodeLabStepBreadcrumb(
                  steps: stepLabels,
                  current: state.stepIndex,
                ),
                const SizedBox(height: 8),
                ProgressBar(
                  value: (state.stepIndex + 1) / stepLabels.length * 100,
                ),
                if (showSummary && entries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  CodeLabKeyValueList(entries: entries),
                ],
                const SizedBox(height: 14),
                KeyedSubtree(key: bodyKey, child: body),
              ],
            ),
          ),
        ),
        actions: actions,
      ),
    );
  }
}

CodeLabButton _button(
  String key,
  String label,
  VoidCallback? onPressed, {
  bool primary = false,
  bool loading = false,
}) => CodeLabButton(
  key: ValueKey(key),
  label: label,
  emphasis: primary
      ? CodeLabButtonEmphasis.primary
      : CodeLabButtonEmphasis.secondary,
  isLoading: loading,
  onPressed: onPressed,
);

/// Кнопка «Cancel» (закрывает мастер, кроме `Saving`).
Widget _cancel(BuildContext context, {bool enabled = true}) => _button(
  'provider-wizard-cancel',
  context.l10n.commonCancel,
  enabled ? context.read<ProviderWizardCubit>().cancel : null,
);

Widget _back(BuildContext context, {bool enabled = true}) => _button(
  'provider-wizard-back',
  context.l10n.commonBack,
  enabled
      ? () => context.read<ProviderWizardCubit>().dispatch(const Back())
      : null,
);

Widget _error(String text, {Key? key}) => Padding(
  padding: const EdgeInsets.only(top: 8),
  child: InfoBar(
    key: key,
    title: Text(text),
    severity: InfoBarSeverity.error,
    isLong: true,
  ),
);

Widget _label(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: CodeLabText(text, role: CodeLabTextRole.strong),
);

// --- API type ---------------------------------------------------------------

class _PresetStep extends StatefulWidget {
  const _PresetStep({required this.state, required this.setup});

  final ProviderWizardState state;
  final ChoosingPreset setup;

  @override
  State<_PresetStep> createState() => _PresetStepState();
}

class _PresetStepState extends State<_PresetStep> {
  late String _selected = widget.setup.presets.first.id;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final l10n = context.l10n;
    return _Frame(
      state: widget.state,
      bodyKey: const ValueKey('provider-wizard-type'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(l10n.wizardStepApiType),
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (id) => setState(() => _selected = id ?? _selected),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final preset in widget.setup.presets)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioButton<String>(
                      key: ValueKey('provider-wizard-preset-${preset.id}'),
                      value: preset.id,
                      // Подпись пресета — по `id`, а не по английской строке
                      // моста (D5 п. 5, D6).
                      content: Text(wizardPresetLabel(l10n, preset)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        _button(
          'provider-wizard-next',
          l10n.commonNext,
          () => cubit.dispatch(PresetChosen(_selected)),
          primary: true,
        ),
        _cancel(context),
      ],
    );
  }
}

// --- Base URL ---------------------------------------------------------------

class _BaseUrlStep extends StatefulWidget {
  const _BaseUrlStep({required this.state, required this.setup});

  final ProviderWizardState state;
  final EnteringBaseUrl setup;

  @override
  State<_BaseUrlStep> createState() => _BaseUrlStepState();
}

class _BaseUrlStepState extends State<_BaseUrlStep> {
  late final _controller = TextEditingController(
    text: widget.setup.draft.baseUrl ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final l10n = context.l10n;
    final insecure = widget.setup.insecureHost;
    return _Frame(
      state: widget.state,
      bodyKey: const ValueKey('provider-wizard-base-url'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(l10n.wizardStepBaseUrl),
          TextBox(
            key: const ValueKey('provider-wizard-base-url-field'),
            controller: _controller,
            autofocus: true,
            onSubmitted: (text) => cubit.dispatch(BaseUrlSubmitted(text)),
          ),
          if (wizardErrorText(widget.setup, l10n) case final error?)
            _error(error),
          if (insecure != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InfoBar(
                key: const ValueKey('provider-wizard-insecure'),
                title: Text(l10n.settingsKeyUnencryptedToHost(insecure)),
                severity: InfoBarSeverity.warning,
                isLong: true,
                action: _button(
                  'provider-wizard-insecure-confirm',
                  l10n.wizardInsecureConfirm,
                  () => cubit.dispatch(
                    InsecureAddressConfirmed(_controller.text),
                  ),
                ),
              ),
            ),
        ],
      ),
      actions: [
        _button(
          'provider-wizard-next',
          l10n.commonNext,
          () => cubit.dispatch(BaseUrlSubmitted(_controller.text)),
          primary: true,
        ),
        if (!cubit.editing) _back(context),
        _cancel(context),
      ],
    );
  }
}

// --- API key source ---------------------------------------------------------

class _KeyStep extends StatefulWidget {
  const _KeyStep({required this.state, required this.setup});

  final ProviderWizardState state;
  final ChoosingKey setup;

  @override
  State<_KeyStep> createState() => _KeyStepState();
}

class _KeyStepState extends State<_KeyStep> {
  final _secret = TextEditingController();
  late final _env = TextEditingController(
    text: widget.setup.suggestedEnvVar ?? '',
  );
  WizardKeyKind? _selected;

  @override
  void dispose() {
    // Ссылку на значение ключа не держим дольше шага (SETUP-1).
    _secret.clear();
    _secret.dispose();
    _env.dispose();
    super.dispose();
  }

  static String _suffix(WizardKeyKind kind) => switch (kind) {
    WizardKeyKind.store => 'store',
    WizardKeyKind.keepStored => 'keep',
    WizardKeyKind.replace => 'replace',
    WizardKeyKind.environment => 'env',
    WizardKeyKind.none => 'none',
  };

  WizardKeyKind _defaultKind(List<WizardKeyOption> options) {
    if (widget.setup.draft.preset?.key == KeyRequirement.none &&
        options.any((o) => o.kind == WizardKeyKind.none)) {
      return WizardKeyKind.none;
    }
    return options.first.kind;
  }

  KeySubmitted _submission(WizardKeyKind kind) => switch (kind) {
    WizardKeyKind.store => KeySubmitted(StoreSecret(SecretValue(_secret.text))),
    WizardKeyKind.replace => KeySubmitted(
      StoreSecret(SecretValue(_secret.text)),
      replaceExisting: true,
    ),
    WizardKeyKind.keepStored => const KeySubmitted(KeepStoredSecret()),
    WizardKeyKind.environment => KeySubmitted(UseEnvVar(_env.text.trim())),
    WizardKeyKind.none => const KeySubmitted(NoKey()),
  };

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final l10n = context.l10n;
    final setup = widget.setup;
    final options = wizardKeyOptions(setup, l10n: l10n);
    final selected = options.any((o) => o.kind == _selected)
        ? _selected!
        : _defaultKind(options);
    // Подпись существующего ключа и ошибка `keyAlreadyStored` строятся из
    // одного сообщения; дубль скрывается по типу, а не сравнением строк
    // (D5 п. 5, D6 «Дедупликация в диалоге»).
    final existingNote = setup.existingSecret == null
        ? null
        : l10n.wizardErrorKeyAlreadyStored(
            setup.existingSecret!,
            setup.backend.id,
          );
    final readOnly = !setup.canStoreSecret;
    final readOnlyDetail = wizardReadOnlyDetail(setup);
    return _Frame(
      state: widget.state,
      bodyKey: const ValueKey('provider-wizard-key'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(l10n.wizardKeySourceLabel),
          if (wizardKeyNotice(setup, l10n) case final notice?)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InfoBar(
                key: const ValueKey('provider-wizard-key-notice'),
                title: Text(notice),
                severity: InfoBarSeverity.info,
                isLong: true,
              ),
            ),
          if (existingNote != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CodeLabText(existingNote, role: CodeLabTextRole.caption),
            ),
          if (readOnly)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // Заголовок из каталога (security), подсказка хранилища — как
              // есть под ним (D6).
              child: InfoBar(
                key: const ValueKey('provider-wizard-key-readonly'),
                title: Text(l10n.secretStoreReadOnly),
                content: readOnlyDetail == null ? null : Text(readOnlyDetail),
                severity: InfoBarSeverity.warning,
                isLong: true,
              ),
            ),
          RadioGroup<WizardKeyKind>(
            groupValue: selected,
            onChanged: (kind) => setState(() => _selected = kind),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final option in options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioButton<WizardKeyKind>(
                      key: ValueKey(
                        'provider-wizard-key-${_suffix(option.kind)}',
                      ),
                      value: option.kind,
                      enabled: setup.ready,
                      content: Text(option.label),
                    ),
                  ),
              ],
            ),
          ),
          if (selected == WizardKeyKind.store ||
              selected == WizardKeyKind.replace) ...[
            const SizedBox(height: 4),
            _label(l10n.wizardKeyFieldLabel),
            PasswordBox(
              key: const ValueKey('provider-wizard-key-field'),
              controller: _secret,
              // Без «глазка»: значение ключа на экран не выводится (SETUP-1).
              revealMode: PasswordRevealMode.hidden,
            ),
          ],
          if (selected == WizardKeyKind.environment) ...[
            const SizedBox(height: 4),
            _label(l10n.wizardKeyEnvFieldLabel),
            TextBox(
              key: const ValueKey('provider-wizard-env-field'),
              controller: _env,
            ),
          ],
          if (!isKeyAlreadyStoredError(setup) &&
              !isSecretStoreReadOnlyError(setup))
            if (wizardErrorText(setup, l10n) case final error?) _error(error),
          if (!setup.ready)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: SizedBox.square(dimension: 16, child: ProgressRing()),
            ),
        ],
      ),
      actions: [
        _button(
          'provider-wizard-next',
          l10n.commonNext,
          setup.ready ? () => cubit.dispatch(_submission(selected)) : null,
          primary: true,
        ),
        _back(context),
        _cancel(context),
      ],
    );
  }
}

// --- Check ------------------------------------------------------------------

class _CheckStep extends StatefulWidget {
  const _CheckStep({required this.state});

  final ProviderWizardState state;

  @override
  State<_CheckStep> createState() => _CheckStepState();
}

enum _Continue { useV1, manual }

class _CheckStepState extends State<_CheckStep> {
  _Continue? _choice;
  var _confirmSkip = false;
  final _model = TextEditingController();

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final l10n = context.l10n;
    final setup = widget.state.setup;
    if (setup is Checking) {
      return _Frame(
        state: widget.state,
        bodyKey: const ValueKey('provider-wizard-check'),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox.square(dimension: 16, child: ProgressRing()),
                const SizedBox(width: 10),
                CodeLabText(l10n.wizardChecking),
              ],
            ),
            const SizedBox(height: 8),
            CodeLabText('GET ${setup.probeUrl}', role: CodeLabTextRole.mono),
          ],
        ),
        actions: [_back(context), _cancel(context)],
      );
    }
    final failed = setup as CheckFailed;
    final choice = _choice ?? (failed.canUseV1 ? _Continue.useV1 : null);
    final base = failed.draft.displayBaseUrl ?? '';
    final note = checkFailureNote(failed, l10n: l10n);
    final notFound = failed.failure.kind == ProviderCheckFailureKind.notFound;
    return _Frame(
      state: widget.state,
      bodyKey: const ValueKey('provider-wizard-check'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoBar(
            key: const ValueKey('provider-wizard-check-failure'),
            title: Text(checkFailureTitle(failed, l10n: l10n)),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (note != null) Text(note),
                CodeLabText(
                  checkRequestLine(failed),
                  role: CodeLabTextRole.mono,
                ),
              ],
            ),
            severity: InfoBarSeverity.warning,
            isLong: true,
          ),
          if (notFound) ...[
            const SizedBox(height: 12),
            _label(l10n.wizardContinueQuestion),
            RadioGroup<_Continue>(
              groupValue: choice,
              onChanged: (value) => setState(() => _choice = value),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (failed.canUseV1)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: RadioButton<_Continue>(
                        key: const ValueKey('provider-wizard-use-v1'),
                        value: _Continue.useV1,
                        content: Text(l10n.wizardUseAddress('$base/v1')),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: RadioButton<_Continue>(
                      key: const ValueKey('provider-wizard-manual-model'),
                      value: _Continue.manual,
                      content: Text(l10n.wizardEnterModelManually),
                    ),
                  ),
                ],
              ),
            ),
            if (choice == _Continue.manual)
              TextBox(
                key: const ValueKey('provider-wizard-manual-model-field'),
                controller: _model,
                placeholder: l10n.wizardModelId,
              ),
          ],
          if (_confirmSkip)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: InfoBar(
                key: const ValueKey('provider-wizard-skip-warning'),
                title: Text(l10n.wizardSkipWarning),
                severity: InfoBarSeverity.warning,
                isLong: true,
                action: _button(
                  'provider-wizard-skip-confirm',
                  l10n.wizardSkipConfirm,
                  () => cubit.dispatch(const SkipCheck(confirmed: true)),
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (notFound && choice == _Continue.manual)
          _button(
            'provider-wizard-next',
            l10n.commonContinue,
            () => cubit.dispatch(ModelEnteredManually(_model.text)),
            primary: true,
          )
        else
          _button(
            'provider-wizard-retry',
            l10n.commonRetry,
            () => cubit.dispatch(
              choice == _Continue.useV1 && failed.canUseV1
                  ? const UseV1Address()
                  : const RetryCheck(),
            ),
            primary: true,
          ),
        if (failed.canSkip && !_confirmSkip)
          _button(
            'provider-wizard-skip-check',
            l10n.wizardSaveWithoutCheck,
            () => setState(() => _confirmSkip = true),
          ),
        _back(context),
        _cancel(context),
      ],
    );
  }
}

// --- Model ------------------------------------------------------------------

class _ModelStep extends StatefulWidget {
  const _ModelStep({required this.state, required this.setup});

  final ProviderWizardState state;
  final ChoosingModel setup;

  @override
  State<_ModelStep> createState() => _ModelStepState();
}

class _ModelStepState extends State<_ModelStep> {
  final _filter = TextEditingController();
  final _manual = TextEditingController();
  late bool _manualMode = widget.setup.models.isEmpty;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final l10n = context.l10n;
    final needle = _filter.text.trim().toLowerCase();
    final models = [
      for (final model in widget.setup.models)
        if (needle.isEmpty || model.id.toLowerCase().contains(needle)) model,
    ];
    return _Frame(
      state: widget.state,
      bodyKey: const ValueKey('provider-wizard-model'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.setup.checked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CodeLabText(
                l10n.wizardModelNotChecked,
                role: CodeLabTextRole.caption,
              ),
            ),
          if (widget.setup.models.isNotEmpty) ...[
            _label(l10n.wizardModelFilter),
            TextBox(
              key: const ValueKey('provider-wizard-model-filter'),
              controller: _filter,
              autofocus: true,
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final model in models)
                    ListTile(
                      key: ValueKey('provider-wizard-model-${model.id}'),
                      title: Text(model.id),
                      // При правке текущая модель отмечена (`currentModel`).
                      trailing: model.id == widget.setup.currentModel
                          ? const Icon(
                              FluentIcons.accept,
                              key: ValueKey('provider-wizard-model-current'),
                              size: 14,
                            )
                          : null,
                      onPressed: () => cubit.dispatch(ModelChosen(model.id)),
                    ),
                  ListTile(
                    key: const ValueKey('provider-wizard-model-manual'),
                    title: Text(l10n.wizardModelManual),
                    onPressed: () => setState(() => _manualMode = true),
                  ),
                ],
              ),
            ),
          ],
          if (_manualMode) ...[
            const SizedBox(height: 8),
            if (widget.setup.models.isEmpty) _label(l10n.wizardModelId),
            TextBox(
              key: const ValueKey('provider-wizard-model-manual-field'),
              controller: _manual,
              placeholder: l10n.wizardModelId,
            ),
          ],
        ],
      ),
      actions: [
        if (_manualMode)
          _button(
            'provider-wizard-next',
            l10n.commonNext,
            () => cubit.dispatch(ModelEnteredManually(_manual.text)),
            primary: true,
          ),
        _back(context),
        _cancel(context),
      ],
    );
  }
}

class _DetailsStep extends StatefulWidget {
  const _DetailsStep({required this.state, required this.setup});

  final ProviderWizardState state;
  final EnteringModelDetails setup;

  @override
  State<_DetailsStep> createState() => _DetailsStepState();
}

class _DetailsStepState extends State<_DetailsStep> {
  late final _window = TextEditingController(
    text: '${widget.setup.suggestedContextWindow}',
  );
  final _output = TextEditingController();

  @override
  void dispose() {
    _window.dispose();
    _output.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final l10n = context.l10n;
    return _Frame(
      state: widget.state,
      bodyKey: const ValueKey('provider-wizard-model'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabText(
            l10n.wizardLimitsOf(widget.setup.modelId),
            role: CodeLabTextRole.strong,
          ),
          const SizedBox(height: 8),
          _label(l10n.wizardContextWindow),
          TextBox(
            key: const ValueKey('provider-wizard-context-window'),
            controller: _window,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: 8),
          _label(l10n.wizardMaxOutputTokens),
          TextBox(
            key: const ValueKey('provider-wizard-max-output'),
            controller: _output,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          if (wizardErrorText(widget.setup, l10n) case final error?)
            _error(error),
        ],
      ),
      actions: [
        _button(
          'provider-wizard-next',
          l10n.commonNext,
          () => cubit.dispatch(
            ModelDetailsSubmitted(
              contextWindow: int.tryParse(_window.text) ?? 0,
              maxOutputTokens: int.tryParse(_output.text),
            ),
          ),
          primary: true,
        ),
        _back(context),
        _cancel(context),
      ],
    );
  }
}

// --- Review -----------------------------------------------------------------

class _ReviewStep extends StatelessWidget {
  const _ReviewStep({required this.state});

  final ProviderWizardState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProviderWizardCubit>();
    final l10n = context.l10n;
    final setup = state.setup;
    final saving = setup is Saving;
    final plan = switch (setup) {
      Reviewing(:final plan) ||
      Saving(:final plan) ||
      SaveFailed(:final plan) ||
      Done(:final plan) => plan,
      _ => null,
    };
    final reviewing = setup is Reviewing ? setup : null;
    return _Frame(
      state: state,
      showSummary: false,
      bodyKey: const ValueKey('provider-wizard-review'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CodeLabKeyValueList(
            entries: [
              for (final row in state.summary)
                CodeLabKeyValueEntry(
                  label: row.label,
                  value: row.mono ? null : row.value,
                  monoValue: row.mono ? row.value : null,
                ),
            ],
          ),
          // `Reviewing.warnings` моста на экран не выводятся: предупреждение
          // строится по `notVerified` (D6).
          for (final warning
              in reviewing == null
                  ? const <String>[]
                  : wizardReviewWarnings(reviewing, l10n))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InfoBar(
                title: Text(warning),
                severity: InfoBarSeverity.warning,
                isLong: true,
              ),
            ),
          if (state.reviewNotice case final notice?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: InfoBar(
                key: const ValueKey('provider-wizard-review-notice'),
                title: Text(notice),
                severity: InfoBarSeverity.warning,
                isLong: true,
              ),
            ),
          // Текст строится по `errorCode` (правка) или `refusal` (отказ записи
          // плана), а не по `Reviewing.error` (D5 п. 5, D6); `refusal` ещё
          // помечает блок и гасит «Save».
          if (reviewing != null)
            if (wizardErrorText(reviewing, l10n) case final error?)
              _error(
                error,
                key: reviewing.refusal == null
                    ? null
                    : const ValueKey('provider-wizard-refusal'),
              ),
          if (setup is SaveFailed)
            _error(
              wizardSaveFailureText(setup, l10n: l10n),
              key: const ValueKey('provider-wizard-save-failed'),
            ),
          if (plan != null) ...[
            const SizedBox(height: 12),
            Checkbox(
              key: const ValueKey('provider-wizard-make-default'),
              checked: plan.makeDefault,
              content: Flexible(child: Text(l10n.wizardMakeDefault)),
              onChanged: reviewing == null || cubit.forceDefault
                  ? null
                  : (value) => cubit.dispatch(
                      ReviewEdited(makeDefault: value ?? false),
                    ),
            ),
            if (cubit.projectOnlyAvailable) ...[
              const SizedBox(height: 8),
              Checkbox(
                key: const ValueKey('provider-wizard-project-only'),
                checked: plan.target.layer == ConfigLayer.projectLocal,
                content: Flexible(child: Text(l10n.wizardProjectOnly)),
                onChanged: reviewing == null
                    ? null
                    : (value) => cubit.dispatch(
                        ReviewEdited(
                          target: value ?? false
                              ? cubit.projectTarget
                              : const ConfigTarget.user(),
                        ),
                      ),
              ),
            ],
          ],
          if (saving)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  const SizedBox.square(dimension: 16, child: ProgressRing()),
                  const SizedBox(width: 10),
                  CodeLabText(l10n.wizardSaving),
                ],
              ),
            ),
        ],
      ),
      actions: [
        _button(
          'provider-wizard-save',
          l10n.commonSave,
          // Отказ записи плана (`refusal`) делает «Save» неактивной.
          reviewing == null || reviewing.refusal != null
              ? null
              : () => cubit.dispatch(const ConfirmSave()),
          primary: true,
          loading: saving,
        ),
        _back(context, enabled: !saving && setup is! Done),
        _cancel(context, enabled: !saving),
      ],
    );
  }
}
