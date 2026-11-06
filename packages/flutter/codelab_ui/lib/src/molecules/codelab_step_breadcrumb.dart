import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Строка шагов мастера: `API type › Base URL › Key › Check › Model › Review`.
///
/// Почему: мастер «Add provider» показывает, на каком из шагов пользователь
/// (артборд `Wizard`, класс `.st`; design.md change `add-provider-setup-ui`,
/// D19). Строка нужна и приложению, и другим многошаговым диалогам, поэтому
/// это отдельная молекула, а не вёрстка внутри диалога.
///
/// Для чего: только отображение. Знания о состояниях мастера у виджета нет:
/// какой `ProviderSetupState` соответствует какому шагу, решает presentation
/// приложения и передаёт готовые подписи [steps] и индекс [current].
/// Текущий шаг — полужирный, основным цветом; остальные (пройденные и
/// будущие) — вторичным; после каждого шага, кроме последнего, стоит `›`.
///
/// Как использовать: `CodeLabStepBreadcrumb(steps: [...], current: 3)`.
/// Индекс вне диапазона не выделяет ни одного шага. Строка переносится на
/// следующую линию, если не помещается по ширине.
class CodeLabStepBreadcrumb extends StatelessWidget {
  const CodeLabStepBreadcrumb({
    required this.steps,
    required this.current,
    super.key,
  });

  /// Подписи шагов по порядку, без разделителя.
  final List<String> steps;

  /// Индекс текущего шага в [steps].
  final int current;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final base = CodeLabText.styleOf(context, CodeLabTextRole.caption);

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var i = 0; i < steps.length; i++)
          Semantics(
            selected: i == current,
            child: Text(
              i < steps.length - 1 ? '${steps[i]} ›' : steps[i],
              softWrap: false,
              style: (base ?? const TextStyle()).copyWith(
                color: i == current
                    ? resources.textFillColorPrimary
                    : resources.textFillColorSecondary,
                fontWeight: i == current ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
      ],
    );
  }
}
