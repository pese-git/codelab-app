import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/atomics.dart';

/// Стартовый экран панели сессии без сессии в фокусе.
///
/// Почему: ручного Connect больше нет — агент стартует сам от действий
/// пользователя (design.md change `require-project-folder`, D13, D18), и без
/// сессии панель должна подсказывать следующее действие: открыть проект или
/// начать сессию.
///
/// Для чего: виджет без логики. Хост передаёт [message] (`Open a project to
/// start a session.` или `Start a new session in app.`), подпись и
/// ключ единственного действия ([actionLabel], [actionKey]) и, пока агент
/// стартует, [busyLabel] (`Starting <profile>…`) — индикатор показывается
/// рядом с действием, а не вместо него.
///
/// Как использовать: `CodeLabStartScreen(message: …, actionLabel: …,
/// actionKey: …, onAction: …)`; решает, что показывать, и вызывает
/// действие хост (корневой `AGENTS.md` §10).
class CodeLabStartScreen extends StatelessWidget {
  const CodeLabStartScreen({
    required this.message,
    required this.actionLabel,
    this.actionKey,
    this.onAction,
    this.busyLabel,
    super.key,
  });

  final String message;
  final String actionLabel;

  /// Ключ кнопки действия (`start-open-project`, `start-new-session`).
  final Key? actionKey;
  final VoidCallback? onAction;

  /// Пока не `null`, агент стартует: показывается индикатор с этой подписью.
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    final busy = busyLabel;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CodeLabText(message, role: CodeLabTextRole.title),
            const SizedBox(height: 16),
            // Индикатор и действие вместе: повторные «New session» во время
            // старта — несколько намерений одного старта (D17).
            if (busy != null) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox.square(
                    dimension: 16,
                    child: ProgressRing(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  CodeLabText(busy, role: CodeLabTextRole.caption),
                ],
              ),
              const SizedBox(height: 12),
            ],
            CodeLabButton(
              key: actionKey,
              label: actionLabel,
              emphasis: CodeLabButtonEmphasis.primary,
              onPressed: onAction,
            ),
          ],
        ),
      ),
    );
  }
}
