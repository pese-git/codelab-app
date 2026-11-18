import 'dart:async';

import 'package:codelab_ui/codelab_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/platform/usage_csv_saver.dart';
import '../../../l10n/l10n.dart';
import '../../workbench/application/shell_cubit.dart';
import '../application/usage_pane_data.dart';
import 'usage_pane_view.dart';

/// Панель Usage дока: расход сессии в фокусе (spec agent-workbench-ui
/// «Панель Usage»; design.md change `add-desktop-usage-pane`, D1, D2, D3, D5).
///
/// Почему виджет с состоянием: он сообщает фасаду, что панель показана (D3),
/// и держит заметку о сбое сохранения CSV — временное состояние просмотра,
/// которое не нужно ни Cubit-у, ни между запусками.
///
/// Для чего: только отображение. Данные — `CodeLabShellState.usage`
/// (собирает `ActiveSessionCubit`), решения «когда обновлять журнал» и
/// «доступна ли панель» принимает application. Виджет вызывает `Retry`,
/// `Rebuild from log` и `Export CSV` у фасада и ничего не пишет в файл сам.
///
/// Как использовать: слот `ToolPane.usage` в `CodeLabShell`; нужен
/// `BlocProvider<CodeLabShellCubit>`. Док монтирует только активную вкладку и
/// строится, только когда виден, поэтому «смонтирован» значит «показан»:
/// `initState` шлёт `usagePaneShown(true)`, `dispose` — `false`; фасад
/// считает экземпляры, поэтому пересборка дока с двумя экземплярами на миг
/// показ не гасит.
///
/// Тик блока `Turn budget` (D9): `Timer.periodic` раз в секунду перестраивает
/// панель, пока `UsageBudgetData.ticking` истинно; решение «тикать ли»
/// принимает application, виджет ему следует. Таймер живёт, только пока
/// панель смонтирована, и отменяется при смене условия и в `dispose`.
class WorkbenchUsagePane extends StatefulWidget {
  const WorkbenchUsagePane({this.clock, super.key});

  /// Часы блока `Turn budget` (D9): `null` — `DateTime.now`. Тесты внедряют
  /// один поддельный источник для часов kit (`receivedAt`) и виджета (`now`),
  /// как `WorkbenchAgentsPane.clock`.
  final DateTime Function()? clock;

  @override
  State<WorkbenchUsagePane> createState() => _WorkbenchUsagePaneState();
}

class _WorkbenchUsagePaneState extends State<WorkbenchUsagePane> {
  late final CodeLabShellCubit _cubit;

  /// Сохранение CSV не удалось: заметка `Couldn't save the file.` до
  /// следующего экспорта (отказ в диалоге заметки не даёт, D5).
  bool _saveFailed = false;

  /// Экспорт идёт: вторая кнопка не нужна, пока диалог открыт.
  bool _exporting = false;

  /// Тик Time блока `Turn budget`; `null` — не нужен (D9).
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _cubit = context.read<CodeLabShellCubit>();
    _cubit.usagePaneShown(true);
    _syncTicker(_cubit.state.usage.budget?.ticking ?? false);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _cubit.usagePaneShown(false);
    super.dispose();
  }

  /// Включает или отменяет таймер по признаку из данных; повторный вызов с тем
  /// же значением ничего не меняет, поэтому второго таймера не бывает.
  void _syncTicker(bool ticking) {
    if (ticking == (_ticker != null)) {
      return;
    }
    if (!ticking) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _export() async {
    final sessionId = _cubit.state.activeSessionId;
    setState(() {
      _exporting = true;
      _saveFailed = false;
    });
    final result = await _cubit.exportUsageCsv();
    if (!mounted) {
      return;
    }
    setState(() {
      _exporting = false;
      // Фокус ушёл на другую сессию, пока шёл диалог: заметка о файле чужой
      // сессии здесь не нужна.
      _saveFailed =
          result is UsageCsvFailed && _cubit.state.activeSessionId == sessionId;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Заметка о сбое записи относится к сессии, в фокусе которой был экспорт:
    // при смене сессии она сбрасывается.
    return MultiBlocListener(
      listeners: [
        BlocListener<CodeLabShellCubit, CodeLabShellState>(
          listenWhen: (previous, current) =>
              previous.activeSessionId != current.activeSessionId,
          listener: (context, state) => setState(() => _saveFailed = false),
        ),
        BlocListener<CodeLabShellCubit, CodeLabShellState>(
          listenWhen: (previous, current) =>
              previous.usage.budget?.ticking != current.usage.budget?.ticking,
          listener: (context, state) =>
              _syncTicker(state.usage.budget?.ticking ?? false),
        ),
      ],
      child: BlocBuilder<CodeLabShellCubit, CodeLabShellState>(
        buildWhen: (previous, current) => previous.usage != current.usage,
        builder: (context, state) {
          final data = state.usage;
          final l10n = context.l10n;
          return SingleChildScrollView(
            child: CodeLabUsagePane(
              title: l10n.usageTitle,
              cards: usageCardsOf(data, l10n),
              // Часы спрашиваются, только когда блок есть: без бюджета
              // панель от них не зависит.
              budget: data.budget == null
                  ? null
                  : usageBudgetViewOf(
                      data,
                      now: (widget.clock ?? DateTime.now)(),
                      l10n: l10n,
                    ),
              statusLine: usageLedgerStatusOf(data.ledgerLine, l10n),
              statusHint: usageLedgerHintOf(data.ledgerLine, l10n),
              turns: usageTurnRowsOf(data, l10n),
              models: usageModelRowsOf(data, l10n),
              loading: data.busy && data.ledger == null,
              refreshing: data.busy && data.ledger != null,
              notes: [
                switch (data.notice) {
                  UsagePaneNotice.ledgerFailed => CodeLabUsageNote(
                    text: l10n.usageNoteLedgerFailed,
                    hint: data.failureHint,
                    retryLabel: l10n.commonRetry,
                  ),
                  UsagePaneNotice.noLedger => CodeLabUsageNote(
                    text: l10n.usageNoteNoLedger,
                  ),
                  UsagePaneNotice.none => null,
                },
                if (_saveFailed)
                  CodeLabUsageNote(text: l10n.usageNoteSaveFailed),
              ].nonNulls.toList(),
              showRebuild: data.ledgerAvailable,
              showExport: data.canExport,
              onRebuild: data.canRebuild
                  ? () => unawaited(_cubit.rebuildUsageLedger())
                  : null,
              onExport: _exporting ? null : () => unawaited(_export()),
              onRetry: () => unawaited(_cubit.refreshUsageLedger()),
            ),
          );
        },
      ),
    );
  }
}
