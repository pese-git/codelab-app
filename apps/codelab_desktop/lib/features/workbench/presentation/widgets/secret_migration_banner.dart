import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../l10n/l10n.dart';
import '../../application/secret_migration_cubit.dart';

/// Предупреждение «секреты лежат в файле конфига» и вход в диалог переноса.
///
/// Почему: с R8-4 агент со секретами в файле стартует, и пользователю нужен
/// путь, как их убрать, не уходя в CLI (design.md change
/// `add-config-literal-secrets-and-migrate`, D8, п. 5; agent-workbench-ui
/// «Перенос секретов встроенного агента»).
///
/// Для чего: Fluent `InfoBar` уровня `warning` над транскриптом — тот же
/// способ, что у `CodeLabConnectionBanner`. Показывается только в состоянии
/// `offered`; подключение и работа агента не блокируются. Крестик скрывает
/// его до следующего подключения (`SecretMigrationCubit.dismiss`).
///
/// Как использовать: кладётся в колонку главной панели рядом с баннером
/// соединения; нужен `BlocProvider<SecretMigrationCubit>` выше по дереву
/// (`CodeLabApp`). [onRestart] — повторное подключение тем же профилем
/// (`CodeLabShellCubit.reconnect`); виджет сам ничего не подключает и не
/// трогает файлы или хранилище (`AGENTS.md` §6).
class SecretMigrationBanner extends StatelessWidget {
  const SecretMigrationBanner({required this.onRestart, super.key});

  /// Перезапуск встроенного агента после переноса: повторное подключение тем
  /// же профилем (D8, п. 5). Передаётся в диалог; вызывается по `Restart agent`,
  /// когда ход не идёт. Само подключение выполняет владелец колбэка.
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SecretMigrationCubit, SecretMigrationState>(
      buildWhen: (previous, current) =>
          (previous is SecretMigrationOffered) !=
          (current is SecretMigrationOffered),
      builder: (context, state) {
        if (state is! SecretMigrationOffered) {
          return const SizedBox.shrink();
        }
        final cubit = context.read<SecretMigrationCubit>();
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InfoBar(
            // Предупреждение безопасности (D14): секреты лежат в файле.
            title: Text(context.l10n.secretMigrationWarning),
            severity: InfoBarSeverity.warning,
            isLong: true,
            action: CodeLabButton(
              label: context.l10n.secretMigrationMigrateSecrets,
              icon: FluentIcons.permissions,
              emphasis: CodeLabButtonEmphasis.primary,
              onPressed: () => _openDialog(context, cubit),
            ),
            onClose: cubit.dismiss,
          ),
        );
      },
    );
  }

  /// Диалог открывается до `openPlan`: после перехода в `planning`
  /// предупреждение исчезает, а контекст кнопки перестаёт быть смонтированным.
  /// Любое закрытие маршрута (Esc, барьер) сообщает Cubit-у, иначе поздний
  /// результат плана вернул бы диалог (спецификация «Поздний результат»).
  void _openDialog(BuildContext context, SecretMigrationCubit cubit) {
    final result = showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: SecretMigrationDialog(onRestart: onRestart),
      ),
    );
    cubit.openPlan();
    result.whenComplete(cubit.closeDialog);
  }
}

/// Диалог переноса секретов: план, перенос и итог.
///
/// Почему: состав кнопок зависит от плана (бэкенд `env`, конфликт имени,
/// находки только в `CODELAB_CONFIG` — только `Close`; иначе `Migrate` и
/// `Cancel`), а *какой* это случай, решает Cubit по отчёту порта; виджет
/// только отображает (`AGENTS.md` §10).
///
/// Для чего: единственный экран переноса; сам закрывается, когда Cubit
/// вернулся в `offered` или `hidden` (закрытие кнопкой, отключение агента).
///
/// Как использовать: открывается `SecretMigrationBanner`; [onRestart] — как у
/// баннера. После нажатия `Restart agent` диалог закрывается.
class SecretMigrationDialog extends StatelessWidget {
  const SecretMigrationDialog({required this.onRestart, super.key});

  /// Перезапуск агента по `Restart agent` (после успешного или частичного
  /// переноса); тот же колбэк, что у `SecretMigrationBanner.onRestart`. После
  /// вызова диалог закрывается через `SecretMigrationCubit.closeDialog`.
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SecretMigrationCubit, SecretMigrationState>(
      listenWhen: (previous, current) =>
          current is SecretMigrationOffered || current is SecretMigrationHidden,
      listener: (context, state) => Navigator.of(context).maybePop(),
      builder: (context, state) {
        final cubit = context.read<SecretMigrationCubit>();
        final l10n = context.l10n;
        Widget close(String label) =>
            CodeLabButton(label: label, onPressed: cubit.closeDialog);
        final (Widget body, List<Widget> actions) = switch (state) {
          SecretMigrationPlanning() => (
            _Progress(l10n.secretMigrationPlanning),
            [close(l10n.commonClose)],
          ),
          SecretMigrationApplying() => (
            _Progress(l10n.secretMigrationApplying),
            const <Widget>[],
          ),
          SecretMigrationPlanFailed(:final failure) => (
            Text(_failureText(failure, l10n.secretMigrationPlanFailed, l10n)),
            [close(l10n.commonClose)],
          ),
          // Частичный сбой: часть файлов уже переписана — показываем
          // перенесённое и, как после успеха, предлагаем перезапуск.
          SecretMigrationApplyFailed(
            :final failure,
            :final items,
            :final movedAny,
            :final canRestart,
            :final agentGone,
          ) =>
            (
              _PlanLines(
                items: items,
                lead: _failureText(
                  failure,
                  l10n.secretMigrationApplyFailed,
                  l10n,
                ),
              ),
              [
                if (movedAny)
                  _RestartButton(
                    canRestart: canRestart,
                    agentGone: agentGone,
                    onPressed: () {
                      onRestart();
                      cubit.closeDialog();
                    },
                  ),
                close(l10n.commonClose),
              ],
            ),
          SecretMigrationPlanReady() => _planReady(state, cubit, close, l10n),
          SecretMigrationApplied(:final canRestart, :final agentGone) => (
            Text(l10n.secretMigrationMoved),
            [
              _RestartButton(
                canRestart: canRestart,
                agentGone: agentGone,
                onPressed: () {
                  onRestart();
                  cubit.closeDialog();
                },
              ),
              close(l10n.commonClose),
            ],
          ),
          // Диалог закрывается слушателем; пустой кадр до его срабатывания.
          SecretMigrationHidden() || SecretMigrationOffered() => (
            const SizedBox.shrink(),
            const <Widget>[],
          ),
        };
        // Пока идёт запись, маршрут не закрывается ни Esc, ни барьером:
        // итог переноса нельзя потерять (`Cubit.closeDialog` в `applying` —
        // тоже no-op).
        return PopScope(
          canPop: state is! SecretMigrationApplying,
          child: ContentDialog(
            constraints: const BoxConstraints(maxWidth: 640, maxHeight: 480),
            title: Text(l10n.secretMigrationMigrateSecrets),
            content: body,
            actions: actions,
          ),
        );
      },
    );
  }

  /// Пустой план (`exitCode 0`, пунктов нет): объясняем, а не показываем
  /// пустое тело диалога.
  /// Текст сбоя: отчёт порта — как есть (D7), непредвиденное исключение —
  /// сообщение каталога с именем типа ([withClass], D5).
  static String _failureText(
    SecretMigrationFailure failure,
    String Function(String errorClass) withClass,
    AppLocalizations l10n,
  ) => switch (failure) {
    SecretMigrationPortProblem(:final text) => text,
    SecretMigrationUnexpected(:final errorClass) => withClass(errorClass),
  };

  (Widget, List<Widget>) _planReady(
    SecretMigrationPlanReady state,
    SecretMigrationCubit cubit,
    Widget Function(String) close,
    AppLocalizations l10n,
  ) {
    final detail = state.detail;
    // Блокирующие случаи: объясняющий текст и только `Close`.
    if (state.readOnlyBackend && detail != null) {
      return (Text(detail), [close(l10n.commonClose)]);
    }
    if (state.nameConflict) {
      return (
        _PlanLines(items: state.items, lead: detail),
        [close(l10n.commonClose)],
      );
    }
    if (!state.canApply) {
      return (
        _PlanLines(items: state.items, empty: l10n.secretMigrationNothing),
        [close(l10n.commonClose)],
      );
    }
    return (
      _PlanLines(items: state.items),
      [
        CodeLabButton(
          label: l10n.secretMigrationMigrate,
          emphasis: CodeLabButtonEmphasis.primary,
          onPressed: cubit.migrate,
        ),
        close(l10n.commonCancel),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox.square(dimension: 16, child: ProgressRing(strokeWidth: 2)),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

/// Строки плана (`describe()` пунктов, без значений секретов); [lead] —
/// пояснение над ними, например текст конфликта имени.
class _PlanLines extends StatelessWidget {
  const _PlanLines({required this.items, this.lead, this.empty});

  final List<String> items;
  final String? lead;

  /// Текст при пустом списке [items] и отсутствии [lead].
  final String? empty;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lead != null) ...[Text(lead!), const SizedBox(height: 8)],
          if (items.isEmpty && lead == null && empty != null) Text(empty!),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(item),
            ),
        ],
      ),
    );
  }
}

/// `Restart agent`: недоступна, пока идёт ход, — повторное подключение
/// закрыло бы работающий ход (D8, п. 5).
class _RestartButton extends StatelessWidget {
  const _RestartButton({
    required this.canRestart,
    required this.agentGone,
    required this.onPressed,
  });

  final bool canRestart;

  /// Агент, для которого шёл перенос, уже закрыт или сменился.
  final bool agentGone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final button = CodeLabButton(
      label: l10n.commonRestartAgent,
      icon: FluentIcons.refresh,
      emphasis: CodeLabButtonEmphasis.primary,
      onPressed: canRestart ? onPressed : null,
    );
    return canRestart
        ? button
        : Tooltip(
            message: agentGone
                ? l10n.secretMigrationAgentGone
                : l10n.secretMigrationWaitForTurn,
            child: button,
          );
  }
}
