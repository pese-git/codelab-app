import 'package:fluent_ui/fluent_ui.dart';

import '../../application/connection_cubit.dart' show RestartConfirmation;
import '../../application/shell_cubit.dart';

/// Диалог подтверждения «Restart agent» при работающих сессиях (D22).
///
/// Почему: перезапуск обрывает ходы; что сессии «в работе» и что нужен вопрос,
/// решает `ConnectionCubit` (`pendingRestart`), а виджет только показывает
/// текст и возвращает ответ (корневой `AGENTS.md` §10). Диалог рисуется по
/// состоянию, поэтому его видно и над рабочим местом, и над настройками
/// (design.md change `require-project-folder`, D18, D22).
///
/// Как использовать: `CodeLabApp` кладёт его поверх `Stack` рабочего места и
/// настроек, пока `CodeLabShellState.pendingRestart != null`. «Restart agent» —
/// `confirmRestart`, «Cancel» — `cancelRestart` (ничего не меняет).
class RestartConfirmationDialog extends StatelessWidget {
  const RestartConfirmationDialog({
    required this.pending,
    required this.cubit,
    super.key,
  });

  final RestartConfirmation pending;
  final CodeLabShellCubit cubit;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withAlpha(60),
        child: Center(
          child: ContentDialog(
            key: const ValueKey('restart-agent-dialog'),
            title: const Text('Restart agent?'),
            content: Text(pending.message),
            actions: [
              FilledButton(
                key: const ValueKey('restart-agent-confirm'),
                onPressed: () => cubit.confirmRestart(),
                child: const Text('Restart agent'),
              ),
              Button(
                key: const ValueKey('restart-agent-cancel'),
                onPressed: cubit.cancelRestart,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
