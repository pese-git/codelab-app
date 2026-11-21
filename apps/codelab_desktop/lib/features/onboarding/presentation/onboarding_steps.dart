import 'package:codelab_setup/codelab_setup.dart'
    show
        KeyRequirement,
        ProviderKeyMissing,
        ProviderPreset,
        ProviderPresets,
        ConfigBroken;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';

import '../../../l10n/l10n.dart';
import '../../settings/application/provider_wizard_view.dart'
    show wizardPresetLabel;
import '../application/onboarding_probe.dart';
import '../application/onboarding_state.dart';

/// Текущий шаг onboarding по состоянию Cubit-а (design.md change
/// `add-app-onboarding`, D4, D7–D10).
///
/// Почему отдельный виджет: тексты шагов 2–4 строятся «по фактам» (режим,
/// бэкенд секретов, пути) функциями «(факты, язык)», а не лежат в состоянии
/// Cubit-а, поэтому смена языка их пересобирает (D14).
///
/// Для чего: заголовок шага (с узлом фокуса, ключ `onboarding-title`) и
/// содержимое. Решений о том, пропускать ли шаг, здесь нет: их принимает
/// `OnboardingCubit`.
///
/// Как использовать: `OnboardingScreen` передаёт состояние, узел фокуса
/// заголовка и выбранную карточку пресета; выбор карточки — состояние
/// presentation (D8).
class OnboardingStepBody extends StatelessWidget {
  const OnboardingStepBody({
    required this.state,
    required this.titleFocus,
    required this.appLogsLabel,
    required this.selectedPreset,
    required this.onSelectPreset,
    super.key,
  });

  final OnboardingState state;
  final FocusNode titleFocus;

  /// Подпись каталога логов app из composition root: известна без фактов
  /// (design.md D9, ревью 2026-11-21, п. 4).
  final String appLogsLabel;
  final String? selectedPreset;
  final ValueChanged<String> onSelectPreset;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (title, body) = switch (state.step) {
      OnboardingStep.welcome => (
        l10n.onboardingWelcomeTitle,
        _Welcome(l10n: l10n),
      ),
      OnboardingStep.permissions => (
        l10n.onboardingPermissionsTitle,
        _Permissions(l10n: l10n, facts: state.facts),
      ),
      OnboardingStep.model => (
        l10n.onboardingModelTitle,
        _Model(
          l10n: l10n,
          state: state,
          selectedPreset: selectedPreset,
          onSelectPreset: onSelectPreset,
        ),
      ),
      OnboardingStep.privacy => (
        l10n.onboardingPrivacyTitle,
        _Privacy(l10n: l10n, facts: state.facts, appLogsLabel: appLogsLabel),
      ),
    };
    return Column(
      key: ValueKey('onboarding-step-${state.step.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Фокус на заголовке при показе шага: экранный диктор читает его
        // первым (D14).
        Focus(
          key: const ValueKey('onboarding-title'),
          focusNode: titleFocus,
          child: CodeLabText(title, role: CodeLabTextRole.title),
        ),
        const SizedBox(height: 12),
        body,
      ],
    );
  }
}

/// Кнопки под шагом: «Back», «Next», «Set up…», «Set up later»,
/// «Start using CodeLab» (D4, D8).
class OnboardingNavigation extends StatelessWidget {
  const OnboardingNavigation({
    required this.state,
    required this.selectedPreset,
    required this.onBack,
    required this.onNext,
    required this.onFinish,
    required this.onLater,
    required this.onSetUp,
    super.key,
  });

  final OnboardingState state;
  final String? selectedPreset;
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onFinish;
  final VoidCallback onLater;
  final ValueChanged<String> onSetUp;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final model = state.model;
    // Пока мастер открывается или открыт, навигация шага неактивна (D8, ревью
    // 2026-11-21, п. 6): Cubit игнорирует нажатия, кнопки это показывают.
    final busy = _wizardActive(model);
    final actions = <Widget>[];
    switch (state.step) {
      case OnboardingStep.welcome || OnboardingStep.permissions:
        actions.add(
          FilledButton(
            key: const ValueKey('onboarding-next'),
            onPressed: onNext,
            child: _nextLabel(l10n),
          ),
        );
      case OnboardingStep.model:
        final saved = model is ModelSaved;
        if (!saved) {
          actions.add(
            Button(
              key: const ValueKey('onboarding-model-later'),
              onPressed: busy ? null : onLater,
              child: Text(l10n.onboardingSetUpLater),
            ),
          );
        }
        final blocked = busy || _wizardBlocked(model);
        final selected = selectedPreset;
        actions.add(
          saved
              ? Button(
                  key: const ValueKey('onboarding-model-again'),
                  // Без выбранной карточки «Set up again…» неактивна: id пресета
                  // не придумывается.
                  onPressed: blocked || selected == null
                      ? null
                      : () => onSetUp(selected),
                  child: Text(l10n.onboardingSetUpAgain),
                )
              : FilledButton(
                  key: const ValueKey('onboarding-model-setup'),
                  onPressed: blocked || selected == null
                      ? null
                      : () => onSetUp(selected),
                  child: Text(
                    selected == null
                        ? l10n.onboardingSetUp
                        : l10n.onboardingSetUpPreset(
                            wizardPresetLabel(l10n, _presetOf(selected)),
                          ),
                  ),
                ),
        );
        if (saved) {
          actions.add(
            FilledButton(
              key: const ValueKey('onboarding-next'),
              onPressed: busy ? null : onNext,
              child: Text(l10n.onboardingNext),
            ),
          );
        }
      case OnboardingStep.privacy:
        actions.add(
          FilledButton(
            key: const ValueKey('onboarding-finish'),
            onPressed: onFinish,
            child: Text(l10n.onboardingFinish),
          ),
        );
    }
    return Row(
      children: [
        if (state.step != OnboardingStep.welcome)
          Button(
            key: const ValueKey('onboarding-back'),
            onPressed: busy ? null : onBack,
            child: Text(l10n.onboardingBack),
          ),
        const Spacer(),
        Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }

  /// «Next» на шаге «Permissions» ждёт итога чтения фактов: пока он не
  /// известен, на кнопке индикатор (D4).
  Widget _nextLabel(AppLocalizations l10n) =>
      state.step == OnboardingStep.permissions && state.facts is FactsLoading
      ? const SizedBox(
          width: 16,
          height: 16,
          child: ProgressRing(strokeWidth: 2),
        )
      : Text(l10n.onboardingNext);
}

/// Мастер недоступен: битый конфиг, сбой чтения, готовность ещё не известна
/// (D8: мастер не пишет поверх битого файла).
bool _wizardBlocked(OnboardingModelStep model) => switch (model) {
  ModelChoose(:final notice) =>
    notice == ModelNotice.configBroken || notice == ModelNotice.unavailable,
  ModelPending() || ModelSkipped() => true,
  ModelSaved() => false,
};

/// Мастер открывается или открыт: навигация шага заблокирована.
bool _wizardActive(OnboardingModelStep model) => switch (model) {
  ModelChoose(:final wizard) => wizard == ModelWizard.active,
  ModelSaved(:final wizard) => wizard == ModelWizard.active,
  _ => false,
};

ProviderPreset _presetOf(String id) => ProviderPresets.all.firstWhere(
  (preset) => preset.id == id,
  orElse: () => ProviderPresets.all.first,
);

/// Шаг 1: карточки возможностей (артборд `OnboardingWelcome`).
class _Welcome extends StatelessWidget {
  const _Welcome({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final cards = [
      (l10n.onboardingCardFolderTitle, l10n.onboardingCardFolderBody, false),
      (l10n.onboardingCardApproveTitle, l10n.onboardingCardApproveBody, false),
      (l10n.onboardingCardKeyTitle, l10n.onboardingCardKeyBody, false),
      (l10n.onboardingCardBuiltInTitle, l10n.onboardingCardBuiltInBody, true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabText(l10n.onboardingWelcomeIntro),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 620
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (title, body, tag) in cards)
                  SizedBox(
                    width: width,
                    child: _Card(
                      title: title,
                      body: body,
                      tag: tag ? l10n.onboardingBuiltInTag : null,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        CodeLabText(
          l10n.onboardingWelcomeFootnote,
          role: CodeLabTextRole.caption,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.body, this.tag});

  final String title;
  final String body;
  final String? tag;

  @override
  Widget build(BuildContext context) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(child: CodeLabText(title, role: CodeLabTextRole.strong)),
            if (tag != null) ...[
              const SizedBox(width: 8),
              CodeLabBadge(label: tag!),
            ],
          ],
        ),
        const SizedBox(height: 4),
        CodeLabText(body, role: CodeLabTextRole.caption),
      ],
    ),
  );
}

/// Шаг 2: таблица режима `standard` и честный InfoBar о действующем режиме
/// (D7; артборд `Onboarding`).
class _Permissions extends StatelessWidget {
  const _Permissions({required this.l10n, required this.facts});

  final AppLocalizations l10n;
  final OnboardingFactsState facts;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (
        l10n.onboardingPermReadLabel,
        l10n.onboardingPermReadHint,
        l10n.onboardingPermNoPrompt,
      ),
      (
        l10n.onboardingPermEditLabel,
        l10n.onboardingPermEditHint,
        l10n.onboardingPermAsks,
      ),
      (
        l10n.onboardingPermRunLabel,
        l10n.onboardingPermRunHint,
        l10n.onboardingPermAsks,
      ),
      (
        l10n.onboardingPermOutsideLabel,
        l10n.onboardingPermOutsideHint,
        l10n.onboardingPermBlocked,
      ),
    ];
    // Режим называется только по прочитанным фактам (design.md D7, ревью
    // 2026-11-21, п. 1): до чтения — индикатор, при сбое — нейтральный текст;
    // «standard» неизвестному не приписывается (AGENTS.md §2).
    final Widget mode = switch (facts) {
      FactsLoading() => Row(
        key: const ValueKey('onboarding-permissions-loading'),
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: ProgressRing(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          CodeLabText(l10n.onboardingPermissionsLoading),
        ],
      ),
      FactsUnavailable() => InfoBar(
        key: const ValueKey('onboarding-permissions-mode'),
        title: Text(l10n.onboardingModeUnavailable),
        severity: InfoBarSeverity.warning,
        isLong: true,
      ),
      FactsLoaded(:final facts) when facts.isExternal => InfoBar(
        key: const ValueKey('onboarding-permissions-mode'),
        title: Text(l10n.onboardingModeExternal),
        isLong: true,
      ),
      FactsLoaded(:final facts) => InfoBar(
        key: const ValueKey('onboarding-permissions-mode'),
        title: Text(l10n.onboardingModeTitle(facts.mode ?? 'standard')),
        content: Text(
          (facts.mode ?? 'standard') == 'standard'
              ? l10n.onboardingModeStandardBody
              : l10n.onboardingModeOtherBody,
        ),
        isLong: true,
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabText(l10n.onboardingPermissionsIntro),
        const SizedBox(height: 16),
        for (final (label, hint, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CodeLabText(label, role: CodeLabTextRole.strong),
                      CodeLabText(hint, role: CodeLabTextRole.caption),
                    ],
                  ),
                ),
                CodeLabText(value, role: CodeLabTextRole.strong),
              ],
            ),
          ),
        const SizedBox(height: 16),
        mode,
      ],
    );
  }
}

/// Шаг 3: карточки пресетов, пояснение и сводка сохранённого провайдера (D8;
/// артборды `OnboardingModel`, `OnboardingModelDone`).
class _Model extends StatelessWidget {
  const _Model({
    required this.l10n,
    required this.state,
    required this.selectedPreset,
    required this.onSelectPreset,
  });

  final AppLocalizations l10n;
  final OnboardingState state;
  final String? selectedPreset;
  final ValueChanged<String> onSelectPreset;

  @override
  Widget build(BuildContext context) {
    final model = state.model;
    final blocked = _wizardActive(model) || _wizardBlocked(model);
    final loaded = state.facts is FactsLoaded
        ? (state.facts as FactsLoaded).facts
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabText(l10n.onboardingModelIntro),
        const SizedBox(height: 16),
        if (model is ModelChoose && model.notice != ModelNotice.none) ...[
          _notice(model.notice, loaded),
          const SizedBox(height: 12),
        ],
        CodeLabText(
          l10n.onboardingModelProviderLabel,
          role: CodeLabTextRole.strong,
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 620
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final preset in ProviderPresets.all)
                  SizedBox(
                    width: width,
                    child: _PresetCard(
                      preset: preset,
                      label: wizardPresetLabel(l10n, preset),
                      subtitle: _subtitle(preset),
                      selected: selectedPreset == preset.id,
                      onPressed: blocked
                          ? null
                          : () => onSelectPreset(preset.id),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (model is ModelSaved) ...[
          _Connected(l10n: l10n, summary: model.summary),
          const SizedBox(height: 8),
          CodeLabText(
            l10n.onboardingConnectedAgainNote,
            role: CodeLabTextRole.caption,
          ),
        ] else ...[
          InfoBar(
            key: const ValueKey('onboarding-model-wizard-hint'),
            title: Text(l10n.onboardingModelWizardHintTitle),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.onboardingModelWizardHintBody),
                Text(
                  loaded?.backendWritable == true
                      ? l10n.onboardingModelWizardHintStored(loaded!.backendId!)
                      : l10n.onboardingModelWizardHintEnvOnly,
                ),
              ],
            ),
            isLong: true,
          ),
          const SizedBox(height: 8),
          CodeLabText(
            l10n.onboardingModelSkippedNote,
            role: CodeLabTextRole.caption,
          ),
        ],
      ],
    );
  }

  String _subtitle(ProviderPreset preset) {
    final url = preset.baseUrl;
    final host = url == null ? null : Uri.tryParse(url)?.host;
    if (host == null || host.isEmpty) {
      return l10n.onboardingPresetCustomUrl;
    }
    return switch (preset.key) {
      KeyRequirement.required => l10n.onboardingPresetHostKey(host),
      KeyRequirement.optional => l10n.onboardingPresetHostOptionalKey(host),
      KeyRequirement.none => l10n.onboardingPresetLocalNoKey,
    };
  }

  Widget _notice(ModelNotice notice, OnboardingFacts? facts) {
    final readiness = facts?.readiness;
    final text = switch (notice) {
      ModelNotice.keyMissing when readiness is ProviderKeyMissing =>
        readiness.reference.startsWith('secret ')
            ? l10n.onboardingNoticeKeySecret(
                readiness.providerId,
                readiness.reference.substring('secret '.length),
                readiness.backend.id,
              )
            : l10n.onboardingNoticeKeyEnv(
                readiness.providerId,
                readiness.reference.replaceFirst('env ', ''),
              ),
      ModelNotice.configBroken when readiness is ConfigBroken =>
        l10n.onboardingNoticeConfigBroken(readiness.issues.length),
      _ => l10n.onboardingNoticeUnavailable,
    };
    return InfoBar(
      key: const ValueKey('onboarding-model-notice'),
      title: Text(text),
      severity: InfoBarSeverity.warning,
      isLong: true,
    );
  }
}

class _PresetCard extends StatelessWidget {
  const _PresetCard({
    required this.preset,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
  });

  final ProviderPreset preset;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: selected
              ? theme.accentColor.normal
              : theme.resources.controlStrokeColorDefault,
          width: selected ? 2 : 1,
        ),
      ),
      child: Button(
        key: ValueKey('onboarding-preset-${preset.id}'),
        onPressed: onPressed,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CodeLabText(label, role: CodeLabTextRole.strong),
              CodeLabText(subtitle, role: CodeLabTextRole.caption),
            ],
          ),
        ),
      ),
    );
  }
}

/// Сводка сохранённого провайдера (артборд 07c.5): без значения ключа
/// (SETUP-1), только способ хранения.
class _Connected extends StatelessWidget {
  const _Connected({required this.l10n, required this.summary});

  final AppLocalizations l10n;
  final OnboardingSavedSummary summary;

  @override
  Widget build(BuildContext context) {
    final body = switch (summary.keyStorage) {
      SecretKeyStorage(:final name, :final backendId) =>
        l10n.onboardingConnectedSecret(summary.model, backendId, name),
      EnvKeyStorage(:final variable) => l10n.onboardingConnectedEnv(
        summary.model,
        variable,
      ),
      NoKeyStorage() => l10n.onboardingConnectedNoKey(summary.model),
    };
    return Column(
      key: const ValueKey('onboarding-model-connected'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabText(
          l10n.onboardingConnectedTitle(summary.providerId),
          role: CodeLabTextRole.strong,
        ),
        CodeLabText(body),
      ],
    );
  }
}

/// Шаг 4: что уходит с компьютера; строка «Stays here» — по фактам сборки, а
/// не по артборду (D9); согласия и ссылок на документы нет (D10, D-29).
class _Privacy extends StatelessWidget {
  const _Privacy({
    required this.l10n,
    required this.facts,
    required this.appLogsLabel,
  });

  final AppLocalizations l10n;
  final OnboardingFactsState facts;
  final String appLogsLabel;

  String _stays() {
    final loaded = facts is FactsLoaded ? (facts as FactsLoaded).facts : null;
    final logs = appLogsLabel;
    if (loaded == null) {
      return l10n.onboardingStaysUnavailable(logs);
    }
    if (loaded.isExternal) {
      return l10n.onboardingStaysExternal(logs);
    }
    final home = loaded.homeLabel!;
    final id = loaded.backendId!;
    return switch (id) {
      'env' => l10n.onboardingStaysEnv(home, logs),
      'file' => l10n.onboardingStaysFile(home, logs, '$home/secrets.yaml'),
      'secret-service' ||
      'wincred' => l10n.onboardingStaysKeychain(home, logs, id),
      _ when id.startsWith('keychain') => l10n.onboardingStaysKeychain(
        home,
        logs,
        id,
      ),
      _ => l10n.onboardingStaysOther(home, logs, id),
    };
  }

  @override
  Widget build(BuildContext context) {
    final rows = [
      (
        l10n.onboardingPrivacyProviderLabel,
        l10n.onboardingPrivacyProviderBody,
        l10n.onboardingPrivacyProviderTag,
        null,
      ),
      (
        l10n.onboardingPrivacyToolsLabel,
        l10n.onboardingPrivacyToolsBody,
        l10n.onboardingPrivacyToolsTag,
        null,
      ),
      (
        l10n.onboardingPrivacyTelemetryLabel,
        l10n.onboardingPrivacyTelemetryBody,
        l10n.onboardingPrivacyTelemetryTag,
        null,
      ),
      (
        l10n.onboardingPrivacyStaysLabel,
        _stays(),
        l10n.onboardingPrivacyStaysTag,
        const ValueKey('onboarding-privacy-stays'),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CodeLabText(l10n.onboardingPrivacyIntro),
        const SizedBox(height: 16),
        for (final (label, body, tag, key) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CodeLabText(label, role: CodeLabTextRole.strong),
                      // Ключ стоит на обёртке: поиск по тексту внутри неё.
                      KeyedSubtree(
                        key: key,
                        child: CodeLabText(body, role: CodeLabTextRole.caption),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                CodeLabBadge(label: tag),
              ],
            ),
          ),
        const SizedBox(height: 16),
        InfoBar(
          key: const ValueKey('onboarding-privacy-nothing-to-agree'),
          title: Text(l10n.onboardingNothingToAgreeTitle),
          content: Text(l10n.onboardingNothingToAgreeBody),
          isLong: true,
        ),
      ],
    );
  }
}
