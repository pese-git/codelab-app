import 'dart:async';

import 'package:codelab_setup/codelab_setup.dart' show Done;
import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../l10n/l10n.dart';
import '../../settings/application/legal_documents.dart' show LegalTab;
import '../../settings/presentation/legal_page.dart' show LegalPageHost;
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
  const OnboardingScreen({
    required this.openWizard,
    required this.appLogsLabel,
    super.key,
  });

  final OnboardingWizardOpener openWizard;

  /// Подпись каталога логов app для шага «Privacy» (composition root, D9).
  final String appLogsLabel;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _titleFocus = FocusNode(debugLabel: 'OnboardingTitle');
  final _backFocus = FocusNode(debugLabel: 'OnboardingDocumentBack');
  final _policyFocus = FocusNode(debugLabel: 'OnboardingPolicyLink');
  final _termsFocus = FocusNode(debugLabel: 'OnboardingTermsLink');

  /// Вкладка, которую открывали последней: туда возвращается фокус.
  LegalTab? _lastDocument;

  /// Просмотр, для которого фокус уже переведён.
  LegalTab? _handledDocument;
  String? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _focusTitleAfterFrame();
  }

  @override
  void dispose() {
    _titleFocus.dispose();
    _backFocus.dispose();
    _policyFocus.dispose();
    _termsFocus.dispose();
    super.dispose();
  }

  void _focusTitleAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _titleFocus.requestFocus();
      }
    });
  }

  /// Открывает документ [tab]: состояние держит Cubit, фокус уходит на кнопку
  /// «Back to setup» панели (D10).
  void _openDocument(LegalTab tab) {
    final cubit = context.read<OnboardingCubit>();
    if (cubit.openDocument(tab)) {
      _lastDocument = tab;
    }
  }

  /// Фокус после смены состояния просмотра: на кнопку панели при открытии, на
  /// ссылку, открывшую документ, при закрытии (D10).
  void _focusAfterDocumentChange(LegalTab? document) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (document != null) {
        _backFocus.requestFocus();
      } else {
        (_lastDocument == LegalTab.termsOfUse ? _termsFocus : _policyFocus)
            .requestFocus();
      }
    });
  }

  /// Открывает мастер для [presetId] по доступу из фактов шага.
  ///
  /// Фаза мастера принадлежит Cubit-у: `wizardStarted` блокирует навигацию шага
  /// на время асинхронного открытия и отвечает `false` на повторное нажатие
  /// (D8, ревью 2026-11-21, п. 6). Если к моменту готовности мастера шаг уже
  /// другой или onboarding закрыт, диалог не показывается, Cubit мастера
  /// закрывается. Итог `Done` передаётся Cubit-у, отмена шаг не меняет.
  Future<void> _openWizard(String presetId) async {
    final onboarding = context.read<OnboardingCubit>();
    final facts = onboarding.state.facts;
    final access = facts is FactsLoaded ? facts.facts.access : null;
    if (access == null || !onboarding.wizardStarted()) {
      return;
    }
    try {
      final wizard = await widget.openWizard(
        presetId: presetId,
        access: access,
      );
      if (wizard == null) {
        return;
      }
      if (!mounted ||
          onboarding.isClosed ||
          onboarding.state.step != OnboardingStep.model) {
        await wizard.close();
        return;
      }
      await showProviderWizardDialog(context, wizard);
      final setup = wizard.state.setup;
      // Итог и снятие блокировки — до `await close()`: закрытие мастера
      // ждёт отмену подписок и не должно держать навигацию шага.
      if (setup is Done) {
        onboarding.providerSaved(setup);
      }
      onboarding.wizardEnded();
      await wizard.close();
    } finally {
      // Снимает блокировку на путях выхода без диалога (мастер не открылся,
      // открывание отброшено, ошибка); повторный вызов безопасен: без активной
      // фазы и после `close()` `wizardEnded` ничего не делает.
      onboarding.wizardEnded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<OnboardingCubit>();
    return BlocConsumer<OnboardingCubit, OnboardingState>(
      listenWhen: (previous, current) =>
          previous.step != current.step ||
          previous.document != current.document,
      listener: (context, state) {
        // Смена просмотра документа важнее смены шага: фокус ведёт
        // `_focusAfterDocumentChange`, иначе — заголовок нового шага.
        if (state.document != _handledDocument) {
          _handledDocument = state.document;
          _focusAfterDocumentChange(state.document);
        } else {
          _focusTitleAfterFrame();
        }
      },
      builder: (context, state) {
        final labels = [
          l10n.onboardingStepWelcome,
          l10n.onboardingStepPermissions,
          l10n.onboardingStepModel,
          l10n.onboardingStepPrivacy,
        ];
        final current = state.step.index;
        final document = state.document;
        final theme = FluentTheme.of(context);
        final background = theme.scaffoldBackgroundColor;
        // Фон панели документа непрозрачный: `scaffoldBackgroundColor` у
        // Fluent полупрозрачный (под ним задумана слюда), и шаг просвечивал бы
        // сквозь документ (ручная проверка 2026-11-21).
        final panelBackground = theme.resources.solidBackgroundFillColorBase;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Под панелью документа шаг не получает ни фокуса, ни Enter (D10).
            ExcludeFocus(
              excluding: document != null,
              child: ColoredBox(
                key: const ValueKey('onboarding-screen'),
                color: background,
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
                            appLogsLabel: widget.appLogsLabel,
                            selectedPreset: _selectedPreset,
                            onSelectPreset: (id) =>
                                setState(() => _selectedPreset = id),
                            onOpenDocument: _openDocument,
                            policyLinkFocus: _policyFocus,
                            termsLinkFocus: _termsFocus,
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
              ),
            ),
            if (document != null)
              _DocumentPanel(
                tab: document,
                background: panelBackground,
                backFocus: _backFocus,
                onClose: context.read<OnboardingCubit>().closeDocument,
              ),
          ],
        );
      },
    );
  }
}

/// Панель правового документа поверх шага «Privacy» (design.md change
/// `add-app-onboarding`, D10 в редакции 2026-11-21).
///
/// Почему панель, а не переход в настройки: документ читают внутри экрана
/// onboarding, назначение навигации остаётся `OnboardingDestination` (D1), а
/// состояние шагов не теряется (D5). Тело — та же `LegalPage` страницы
/// настроек (`LegalPageHost(initialTab:)`): второго рендера правовых текстов
/// нет (§12.7.7а).
///
/// Для чего: шапка с кнопкой «Back to setup» (`onboarding-document-back`) и
/// страница «Legal» на вкладке [tab]. «Back to setup» и Esc закрывают панель
/// (`closeOverlay` каталога кита); при открытии фокус на кнопке.
///
/// Как использовать: экран показывает панель, пока `OnboardingState.document`
/// не `null`. `LegalPageCubit` создаёт и закрывает `LegalPageHost` вместе со
/// своим жизненным циклом (D7 `add-app-legal-page`), панель к этому отношения
/// не имеет.
class _DocumentPanel extends StatelessWidget {
  const _DocumentPanel({
    required this.tab,
    required this.background,
    required this.backFocus,
    required this.onClose,
  });

  final LegalTab tab;
  final Color background;
  final FocusNode backFocus;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: CodeLabShortcut.closeOverlay.bind(onClose),
    child: FocusScope(
      child: ColoredBox(
        key: const ValueKey('onboarding-document'),
        color: background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Button(
                  key: const ValueKey('onboarding-document-back'),
                  focusNode: backFocus,
                  onPressed: onClose,
                  child: Text(context.l10n.onboardingDocumentBack),
                ),
              ),
            ),
            // Та же прокручиваемая колонка, в которой `settings_shell` держит
            // страницы настроек: без неё `LegalPage` (колонка без ограничения
            // высоты) переполняет малое окно.
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(40, 0, 40, 40),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1000),
                    child: LegalPageHost(initialTab: tab),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
