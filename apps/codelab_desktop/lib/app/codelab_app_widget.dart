import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart' show CodeLabLocalizations;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/app_localizations.dart';
import 'language/app_language_cubit.dart';
import '../features/settings/presentation/settings_shell.dart';
import '../features/workbench/application/shell_cubit.dart';
import '../features/workbench/presentation/widgets/restart_confirmation_dialog.dart';
import '../features/workbench/application/approval_focus_return.dart';
import '../features/workbench/presentation/workbench_focus.dart';
import '../features/workbench/presentation/workbench_shell.dart';
import 'app_scope.dart';
import 'navigation/app_destination.dart';
import 'navigation/navigation_cubit.dart';

/// Корневой виджет приложения.
///
/// [startOnLaunch] — вызывать ли триггер запуска агента (D19, change
/// `require-project-folder`) после первого кадра. В приложении всегда `true`;
/// виджет-тесты страниц, которым старт агента при восстановленном проекте
/// мешает, передают `false` и стартуют агента сами (D20).
class CodeLabApp extends StatelessWidget {
  const CodeLabApp({this.startOnLaunch = true, super.key});

  final bool startOnLaunch;

  @override
  Widget build(BuildContext context) {
    final dependencies = codeLabDependenciesOf(context);

    // BlocProvider оборачивает FluentApp, а не `home`: Cubit должен быть
    // виден каждому маршруту Navigator-а FluentApp, в том числе модальным
    // диалогам `showDialog` (перенос секретов, удаление профиля). Маршрут
    // того же Navigator-а в дереве — сосед содержимого `home`, а не его
    // потомок, поэтому provider внутри `home` диалогу не виден.
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: dependencies.shellCubit),
        // Тот же уровень, что у Cubit рабочего места: диалог переноса
        // секретов открывается маршрутом Navigator и видит его (D8).
        BlocProvider.value(value: dependencies.secretMigrationCubit),
        BlocProvider.value(value: dependencies.navigationCubit),
        // Панель Terminal дока читает вкладки сессии (D3).
        BlocProvider.value(value: dependencies.terminalTabsCubit),
        BlocProvider.value(value: dependencies.languageCubit),
      ],
      // Язык читает только этот BlocBuilder, и меняется только `locale`:
      // `FluentApp` не пересоздаётся, поэтому State виджетов (ввод
      // композера, фокус, прокрутка) сохраняется (add-desktop-localization,
      // D2, R6). Остальные виджеты получают язык через `Localizations`.
      child: BlocBuilder<AppLanguageCubit, AppLanguageState>(
        buildWhen: (previous, current) => previous.locale != current.locale,
        builder: (context, language) => FluentApp(
          title: 'CodeLab',
          locale: language.locale,
          // Делегат кита рядом с делегатами app: тексты `codelab_ui` берутся из
          // его каталога, а без делегата кит остался бы на английском (D4).
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            CodeLabLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: _CodeLabHome(startOnLaunch: startOnLaunch),
        ),
      ),
    );
  }
}

/// Рисует экран по состоянию `NavigationCubit`.
///
/// Почему рабочее место остаётся в дереве: текст композера, прокрутка ленты и
/// раскрытые блоки не должны теряться при уходе в настройки (spec
/// app-settings «Переход в настройки и обратно»; design.md change
/// `add-app-settings-shell`, D2). Под настройками оно скрыто `Offstage`,
/// не тикает и исключено из фокуса (`ExcludeFocus`): иначе Tab из настроек
/// увёл бы фокус в невидимую карточку одобрения, и Space/Enter ответили бы
/// агенту без контекста tool call (H1 ревью итерации 1; AGENTS.md §10).
///
/// Для чего: единственное место, где `AppDestination` превращается в экран, и
/// где запоминается фокус рабочего места. Как использовать: `home`
/// приложения; логики перехода здесь нет — только чтение состояния и
/// передача колбэков в `NavigationCubit`. Фокус при уходе запоминается, при
/// возврате восстанавливается в тот же узел, а если его уже нет — в первый
/// фокусируемый узел рабочего места (композер).
class _CodeLabHome extends StatefulWidget {
  const _CodeLabHome({required this.startOnLaunch});

  final bool startOnLaunch;

  @override
  State<_CodeLabHome> createState() => _CodeLabHomeState();
}

class _CodeLabHomeState extends State<_CodeLabHome> {
  final _workbenchScope = FocusScopeNode(debugLabel: 'Workbench');

  /// Узел поля композера: принадлежит `State` рабочего места, чтобы после
  /// ухода полосы одобрения вернуть в него фокус (`fix-approval-focus`, D5).
  final _composerFocus = FocusNode(debugLabel: 'Composer');

  /// Узел, державший фокус в момент ухода в настройки.
  FocusNode? _returnFocus;

  /// InfoBar одобрения уже записан в журнал для текущего показа.
  var _approvalLogged = false;

  /// Предыдущее назначение: `BlocListener` отдаёт только текущее.
  AppDestination _previous = const WorkbenchDestination();

  @override
  void initState() {
    super.initState();
    // Триггер запуска (D19): после первого кадра, а не в `initState`, чтобы
    // старт агента не блокировал отрисовку окна (D-15). Восстановленный проект
    // стартует агента в его папке; без проекта агент не стартует.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.startOnLaunch) {
        unawaited(context.read<CodeLabShellCubit>().startOnLaunch());
      }
    });
  }

  @override
  void dispose() {
    _workbenchScope.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  /// Полоса одобрения с клавиатурным фокусом ушла из ленты (ответ, отмена
  /// хода, снятие запроса, смена сессии): возвращает фокус в композер, иначе на
  /// рабочее место (`fix-approval-focus`, D5).
  ///
  /// Вызывается из `dispose` полосы, поэтому дерево не трогает. Микротаск
  /// после освобождения записывает узел, которому Flutter сам отдал фокус; в
  /// следующем кадре фокус возвращается, только если он всё ещё на этом узле,
  /// то есть никто его за это время не взял (§12: устаревший результат не
  /// отбирает фокус у пользователя).
  void _onApprovalFocusReleased() {
    scheduleMicrotask(() {
      final settled = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance
        ..addPostFrameCallback((_) {
          if (!mounted) {
            return;
          }
          final shell = context.read<CodeLabShellCubit>();
          final target = approvalFocusReturnOf(
            hasComposer: _composerFocus.context != null,
            composerEnabled: shell.state.isPromptEnabled,
            focusTaken: FocusManager.instance.primaryFocus != settled,
          );
          switch (target) {
            case ApprovalFocusReturn.composer:
              _composerFocus.requestFocus();
            case ApprovalFocusReturn.workbench:
              _workbenchScope.requestFocus();
            case ApprovalFocusReturn.none:
              break;
          }
        })
        ..scheduleFrame();
    });
  }

  void _onNavigation(AppDestination current) {
    final previous = _previous;
    _previous = current;
    if (current is SettingsDestination && previous is! SettingsDestination) {
      _returnFocus = FocusManager.instance.primaryFocus;
      _syncApprovalLog();
      return;
    }
    if (current is! SettingsDestination && previous is SettingsDestination) {
      _approvalLogged = false;
      final saved = _returnFocus;
      _returnFocus = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        if (saved != null && saved.context != null && saved.canRequestFocus) {
          saved.requestFocus();
        } else {
          _workbenchScope.requestFocus();
        }
      });
    }
  }

  /// Пишет `settings.pending_approval_shown` один раз при появлении InfoBar
  /// и сбрасывает признак, когда запросов не осталось (D17).
  void _syncApprovalLog() {
    final navigation = context.read<NavigationCubit>();
    final waiting = context
        .read<CodeLabShellCubit>()
        .sessionIdsWithPendingApproval;
    if (navigation.state is! SettingsDestination || waiting.isEmpty) {
      _approvalLogged = false;
    } else if (!_approvalLogged) {
      _approvalLogged = true;
      navigation.pendingApprovalShown(sessions: waiting.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = codeLabDependenciesOf(context);
    final navigation = context.read<NavigationCubit>();
    final shell = context.read<CodeLabShellCubit>();
    // Диалог D22 рисуется по состоянию `ConnectionCubit` и над рабочим местом,
    // и над настройками: «Restart agent» нажимают и там, и там.
    final pendingRestart = context.select(
      (CodeLabShellCubit cubit) => cubit.state.pendingRestart,
    );

    return MultiBlocListener(
      listeners: [
        BlocListener<NavigationCubit, AppDestination>(
          listener: (context, destination) => _onNavigation(destination),
        ),
        BlocListener<CodeLabShellCubit, CodeLabShellState>(
          listener: (context, _) => _syncApprovalLog(),
        ),
      ],
      child: BlocBuilder<NavigationCubit, AppDestination>(
        builder: (context, destination) {
          final settings = destination is SettingsDestination
              ? destination
              : null;
          return Stack(
            fit: StackFit.expand,
            children: [
              Offstage(
                offstage: settings != null,
                child: TickerMode(
                  enabled: settings == null,
                  child: ExcludeFocus(
                    excluding: settings != null,
                    child: FocusScope(
                      node: _workbenchScope,
                      child: WorkbenchFocus(
                        composerNode: _composerFocus,
                        onApprovalFocusReleased: _onApprovalFocusReleased,
                        child: const CodeLabShell(),
                      ),
                    ),
                  ),
                ),
              ),
              if (settings != null)
                BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
                  builder: (context, _) {
                    final waiting = shell.sessionIdsWithPendingApproval;
                    final target = shell.sessionIdForPendingApproval;
                    return SettingsShell(
                      pages: dependencies.settingsPages,
                      selected: settings.page,
                      onSelected: (page) =>
                          unawaited(navigation.selectSettingsPage(page)),
                      onBack: navigation.back,
                      pendingApprovalSessions: waiting.length,
                      onBackToApproval: target == null
                          ? null
                          : () => navigation.back(toSession: target),
                    );
                  },
                ),
              if (pendingRestart != null)
                RestartConfirmationDialog(
                  pending: pendingRestart,
                  cubit: shell,
                ),
            ],
          );
        },
      ),
    );
  }
}
