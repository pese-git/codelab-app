import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../features/settings/presentation/settings_shell.dart';
import '../features/workbench/application/shell_cubit.dart';
import '../features/workbench/presentation/workbench_shell.dart';
import 'app_scope.dart';
import 'navigation/app_destination.dart';
import 'navigation/navigation_cubit.dart';

class CodeLabApp extends StatelessWidget {
  const CodeLabApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = codeLabDependenciesOf(context);

    // BlocProvider wraps FluentApp (not `home`) so the cubit stays visible
    // to every route on FluentApp's Navigator, including the modal dialog
    // ConnectionSetupDialog pushes via showDialog — a route pushed by the
    // same Navigator sits as a sibling of `home`'s content in the element
    // tree, not a descendant of it, so a provider scoped inside `home`
    // would not be reachable from the dialog.
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: dependencies.shellCubit),
        // Тот же уровень, что у Cubit рабочего места: диалог переноса
        // секретов открывается маршрутом Navigator и видит его (D8).
        BlocProvider.value(value: dependencies.secretMigrationCubit),
        BlocProvider.value(value: dependencies.navigationCubit),
      ],
      child: const FluentApp(title: 'CodeLab', home: _CodeLabHome()),
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
  const _CodeLabHome();

  @override
  State<_CodeLabHome> createState() => _CodeLabHomeState();
}

class _CodeLabHomeState extends State<_CodeLabHome> {
  final _workbenchScope = FocusScopeNode(debugLabel: 'Workbench');

  /// Узел, державший фокус в момент ухода в настройки.
  FocusNode? _returnFocus;

  /// InfoBar одобрения уже записан в журнал для текущего показа.
  var _approvalLogged = false;

  /// Предыдущее назначение: `BlocListener` отдаёт только текущее.
  AppDestination _previous = const WorkbenchDestination();

  @override
  void dispose() {
    _workbenchScope.dispose();
    super.dispose();
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
                      child: const CodeLabShell(),
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
            ],
          );
        },
      ),
    );
  }
}
