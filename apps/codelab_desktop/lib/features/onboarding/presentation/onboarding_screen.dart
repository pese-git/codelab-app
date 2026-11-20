import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart' show Done;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/l10n.dart';
import '../../settings/presentation/provider_wizard_dialog.dart';
import '../application/onboarding_cubit.dart';
import '../application/onboarding_state.dart';
import '../application/onboarding_wizard_opener.dart';
import 'onboarding_steps.dart';

/// Экран onboarding первого запуска: строка шагов, текущий шаг и кнопки
/// (design.md change `add-app-onboarding`, D4, D12, D14; артборды
/// `Onboarding*`).
///
/// Почему отдельный экран, а не маршрут: onboarding — назначение навигации
/// (`OnboardingDestination`), Esc его не закрывает, а выход из него — только
/// «Start using CodeLab» (spec app-onboarding «Шаги onboarding и переходы»).
///
/// Для чего: только отображение состояния `OnboardingCubit` и передача нажатий.
/// Что показать при `Skipped`, `Choose`, `Saved`, решает Cubit; тексты по
/// фактам собирает [OnboardingStepBody] по `context.l10n` (D9, D14).
///
/// Как использовать: над экраном стоит `BlocProvider<OnboardingCubit>`
/// (владелец — `CodeLabApp`); [openWizard] — порт composition root. При показе
/// шага фокус уходит на его заголовок (ключ `onboarding-title`), чтобы
/// экранный диктор его прочитал. Контент не шире 920 px и прокручивается
/// по вертикали в узком окне.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.openWizard, super.key});

  final OnboardingWizardOpener openWizard;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _titleFocus = FocusNode(debugLabel: 'OnboardingTitle');
  String? _selectedPreset;
  var _wizardOpen = false;

  @override
  void initState() {
    super.initState();
    _focusTitleAfterFrame();
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    super.dispose();
  }

  void _focusTitleAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _titleFocus.requestFocus();
      }
    });
  }

  /// Открывает мастер для [presetId]; повторное нажатие, пока диалог открыт,
  /// игнорируется. Итог `Done` передаётся Cubit-у, отмена шаг не меняет.
  Future<void> _openWizard(String presetId) async {
    if (_wizardOpen) {
      return;
    }
    _wizardOpen = true;
    final onboarding = context.read<OnboardingCubit>();
    try {
      final wizard = await widget.openWizard(presetId: presetId);
      if (wizard == null) {
        return;
      }
      if (!mounted) {
        await wizard.close();
        return;
      }
      await showProviderWizardDialog(context, wizard);
      final setup = wizard.state.setup;
      await wizard.close();
      if (setup is Done && !onboarding.isClosed) {
        onboarding.providerSaved(setup);
      }
    } finally {
      _wizardOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<OnboardingCubit>();
    return BlocConsumer<OnboardingCubit, OnboardingState>(
      listenWhen: (previous, current) => previous.step != current.step,
      listener: (context, state) => _focusTitleAfterFrame(),
      builder: (context, state) {
        final labels = [
          l10n.onboardingStepWelcome,
          l10n.onboardingStepPermissions,
          l10n.onboardingStepModel,
          l10n.onboardingStepPrivacy,
        ];
        final current = state.step.index;
        return ColoredBox(
          key: const ValueKey('onboarding-screen'),
          color: FluentTheme.of(context).scaffoldBackgroundColor,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: ConstrainedBox(
                key: const ValueKey('onboarding-content'),
                constraints: const BoxConstraints(maxWidth: 920),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CodeLabText(
                      l10n.onboardingHeader,
                      role: CodeLabTextRole.caption,
                    ),
                    const SizedBox(height: 12),
                    CodeLabSetupSteps(
                      key: const ValueKey('onboarding-steps'),
                      steps: labels,
                      current: current,
                      // Пропущенный шаг показывается отмеченным, как
                      // пройденный (D4).
                      done: {
                        for (var i = 0; i < current; i++) i,
                        if (state.model is ModelSkipped)
                          OnboardingStep.model.index,
                      },
                    ),
                    const SizedBox(height: 28),
                    OnboardingStepBody(
                      state: state,
                      titleFocus: _titleFocus,
                      selectedPreset: _selectedPreset,
                      onSelectPreset: (id) =>
                          setState(() => _selectedPreset = id),
                    ),
                    const SizedBox(height: 28),
                    OnboardingNavigation(
                      state: state,
                      selectedPreset: _selectedPreset,
                      onBack: cubit.back,
                      onNext: () => unawaited(cubit.next()),
                      onFinish: () => unawaited(cubit.finish()),
                      onLater: cubit.setUpLater,
                      onSetUp: _openWizard,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
