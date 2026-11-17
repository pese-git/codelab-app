import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/shell_cubit.dart';
import '../../application/ui_mappers.dart' show agentCountsOf, agentRowsOf;

/// Панель Agents дока: строки субагентов сессии в фокусе и дерево шагов
/// выбранной строки (spec agent-workbench-ui «Панель Agents v1»; design.md
/// change `add-subagents-and-tasks`, D33, D49 Т9–Т11, D50 п. 2).
///
/// Почему виджет с состоянием: время работающей строки растёт, а данных,
/// которые менялись бы раз в секунду, нет — kit не вызывает `DateTime.now` в
/// проекции (D49 Т3). Поэтому тик живёт здесь: `Timer.periodic` раз в секунду
/// перестраивает панель, а строку времени считает маппер (`agentRowsOf`) по
/// часам [clock].
///
/// Для чего: только отображение. Строки, счётчики и дерево шагов берутся из
/// `CodeLabShellState`; выбор строки, «Show in transcript» и «Go to approval»
/// — вызовы фасада. Решения («Allow»/«Reject») в панели нет: оно принимается
/// только в блоке ленты (PERM-4).
///
/// Как использовать: слот `ToolPane.agents` в `CodeLabShell`, нужен
/// `BlocProvider<CodeLabShellCubit>` выше по дереву. Док монтирует только
/// активную вкладку, а сам док строится, только когда он виден, — поэтому
/// «вкладка активна и док виден» совпадает с «виджет смонтирован». Таймер
/// идёт, пока сессия занята (`running`/`cancelling`) и есть работающая строка;
/// отменяется при смене условия и в `dispose` (D49 Т9). [clock] — часы
/// виджета: по умолчанию `DateTime.now`, widget-тесты внедряют свои.
class WorkbenchAgentsPane extends StatefulWidget {
  const WorkbenchAgentsPane({this.clock, super.key});

  /// Часы виджета; `null` — `DateTime.now`.
  final DateTime Function()? clock;

  @override
  State<WorkbenchAgentsPane> createState() => _WorkbenchAgentsPaneState();
}

class _WorkbenchAgentsPaneState extends State<WorkbenchAgentsPane> {
  static const _tick = Duration(seconds: 1);

  late final StreamSubscription<CodeLabShellState> _subscription;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    final cubit = context.read<CodeLabShellCubit>();
    _subscription = cubit.stream.listen(_syncTimer);
    _syncTimer(cubit.state);
  }

  /// Таймер нужен, только пока есть что обновлять: сессия занята и есть
  /// работающая строка. У строки в незанятой сессии времени нет (D50 п. 2).
  void _syncTimer(CodeLabShellState state) {
    final needed = state.agents.busy && state.agents.hasRunning;
    if (needed && _timer == null) {
      _timer = Timer.periodic(_tick, (_) {
        if (mounted) {
          setState(() {});
        }
      });
    } else if (!needed) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CodeLabShellCubit>();
    return BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
      builder: (context, state) {
        final rows = agentRowsOf(
          state.agents,
          now: (widget.clock ?? DateTime.now)(),
        );
        final selected = state.selectedAgentId;
        return CodeLabAgentsPane(
          rows: rows,
          counts: agentCountsOf(state.agents),
          selectedId: selected,
          steps: selected == null
              ? const []
              : state.agents.stepsOf(selected, state.transcriptRows),
          onSelect: cubit.selectAgent,
          onGoToApproval: cubit.goToAgentApproval,
          onStepGoToApproval: cubit.goToAgentStepApproval,
          onShowInTranscript: cubit.showAgentInTranscript,
        );
      },
    );
  }
}
