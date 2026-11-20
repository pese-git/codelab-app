import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Строка шагов многошагового экрана: кружок с номером или `✓` и подпись.
///
/// Почему: onboarding первого запуска (и позже onboarding смартфона и
/// планшета, этап 10) показывает все шаги сразу: пройденные с отметкой,
/// текущий выделен (артборды `Onboarding*`; design.md change
/// `add-app-onboarding`, D12). Это не [CodeLabStepBreadcrumb]: тот — строка
/// текста с `›` для диалога мастера.
///
/// Для чего: только отображение. Какой шаг текущий, какие пройдены или
/// пропущены (пропущенный шаг тоже отмечен, D4) и как называются шаги,
/// решает приложение; логики onboarding здесь нет (AGENTS.md §5).
///
/// Как использовать: `CodeLabSetupSteps(steps: [...], current: 1, done: {0})`.
/// [done] — индексы шагов с `✓`; остальные показывают номер. Текущий шаг —
/// полужирная подпись основного цвета и кружок с рамкой акцента. Индекс вне
/// диапазона не выделяет ни одного шага. Строка переносится по ширине.
/// Текущий шаг объявляется экранному диктору как выбранный (`aria-current`
/// артборда).
class CodeLabSetupSteps extends StatelessWidget {
  const CodeLabSetupSteps({
    required this.steps,
    required this.current,
    this.done = const {},
    super.key,
  });

  /// Подписи шагов по порядку.
  final List<String> steps;

  /// Индекс текущего шага в [steps].
  final int current;

  /// Индексы шагов с отметкой `✓` (пройденные и пропущенные).
  final Set<int> done;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final base =
        CodeLabText.styleOf(context, CodeLabTextRole.caption) ??
        const TextStyle();

    return Wrap(
      spacing: 20,
      runSpacing: 8,
      children: [
        for (var i = 0; i < steps.length; i++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: done.contains(i) ? theme.accentColor.normal : null,
                  border: Border.all(
                    color: i == current
                        ? theme.accentColor.normal
                        : resources.controlStrokeColorDefault,
                    width: 2,
                  ),
                ),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Center(
                    child: Text(
                      done.contains(i) ? '✓' : '${i + 1}',
                      style: base.copyWith(
                        fontWeight: FontWeight.w600,
                        color: done.contains(i)
                            ? Colors.white
                            : resources.textFillColorSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                selected: i == current,
                child: Text(
                  steps[i],
                  softWrap: false,
                  style: base.copyWith(
                    color: i == current
                        ? resources.textFillColorPrimary
                        : resources.textFillColorSecondary,
                    fontWeight: i == current
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}
