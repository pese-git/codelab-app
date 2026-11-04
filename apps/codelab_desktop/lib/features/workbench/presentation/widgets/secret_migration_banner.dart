import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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
            title: const Text(secretsInConfigWarning),
            severity: InfoBarSeverity.warning,
            isLong: true,
            action: CodeLabButton(
              label: 'Migrate secrets',
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

/// Текст предупреждения (agent-workbench-ui «Перенос секретов встроенного
/// агента»).
const secretsInConfigWarning = 'Secrets are stored in the agent config file.';

/// Подсказка `Restart agent`, когда агент уже закрыт или сменился.
const restartAgentGone = 'The embedded agent is no longer connected.';

/// Подсказка недоступной `Restart agent`: ход ещё идёт.
const restartWaitsForTurn = 'Wait for the current turn to finish.';

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

  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<SecretMigrationCubit, SecretMigrationState>(
      listenWhen: (previous, current) =>
          current is SecretMigrationOffered || current is SecretMigrationHidden,
      listener: (context, state) => Navigator.of(context).maybePop(),
      builder: (context, state) {
        final cubit = context.read<SecretMigrationCubit>();
        Widget close(String label) =>
            CodeLabButton(label: label, onPressed: cubit.closeDialog);
        final (Widget body, List<Widget> actions) = switch (state) {
          SecretMigrationPlanning() => (
            const _Progress('Building the migration plan…'),
            [close('Close')],
          ),
          SecretMigrationApplying() => (
            const _Progress('Moving secrets…'),
            const <Widget>[],
          ),
          SecretMigrationPlanFailed(:final message) => (
            Text(message),
            [close('Close')],
          ),
          // Частичный сбой: часть файлов уже переписана — показываем
          // перенесённое и, как после успеха, предлагаем перезапуск.
          SecretMigrationApplyFailed(
            :final message,
            :final items,
            :final movedAny,
            :final canRestart,
            :final agentGone,
          ) =>
            (
              _PlanLines(items: items, lead: message),
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
                close('Close'),
              ],
            ),
          SecretMigrationPlanReady() => _planReady(state, cubit, close),
          SecretMigrationApplied(:final canRestart, :final agentGone) => (
            const Text(_movedText),
            [
              _RestartButton(
                canRestart: canRestart,
                agentGone: agentGone,
                onPressed: () {
                  onRestart();
                  cubit.closeDialog();
                },
              ),
              close('Close'),
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
            title: const Text('Migrate secrets'),
            content: body,
            actions: actions,
          ),
        );
      },
    );
  }

  /// Пустой план (`exitCode 0`, пунктов нет): объясняем, а не показываем
  /// пустое тело диалога.
  static const _nothingToMigrate = 'Nothing to migrate.';

  static const _movedText =
      'Secrets moved. Restart the embedded agent to use them.';

  (Widget, List<Widget>) _planReady(
    SecretMigrationPlanReady state,
    SecretMigrationCubit cubit,
    Widget Function(String) close,
  ) {
    final detail = state.detail;
    // Блокирующие случаи: объясняющий текст и только `Close`.
    if (state.readOnlyBackend && detail != null) {
      return (Text(detail), [close('Close')]);
    }
    if (state.nameConflict) {
      return (_PlanLines(items: state.items, lead: detail), [close('Close')]);
    }
    if (!state.canApply) {
      return (
        _PlanLines(items: state.items, empty: _nothingToMigrate),
        [close('Close')],
      );
    }
    return (
      _PlanLines(items: state.items),
      [
        CodeLabButton(
          label: 'Migrate',
          emphasis: CodeLabButtonEmphasis.primary,
          onPressed: cubit.migrate,
        ),
        close('Cancel'),
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
    final button = CodeLabButton(
      label: 'Restart agent',
      icon: FluentIcons.refresh,
      emphasis: CodeLabButtonEmphasis.primary,
      onPressed: canRestart ? onPressed : null,
    );
    return canRestart
        ? button
        : Tooltip(
            message: agentGone ? restartAgentGone : restartWaitsForTurn,
            child: button,
          );
  }
}
