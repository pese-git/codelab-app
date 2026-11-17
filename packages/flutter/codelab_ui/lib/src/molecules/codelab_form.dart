import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Вид подписи под полем формы.
enum CodeLabFormNoteTone {
  /// Подсказка (`.ap-hint` макета): вторичный цвет.
  hint,

  /// Ошибка поля (`.ap-err`): критический цвет, объявляется как alert.
  error,

  /// Предупреждение, не блокирующее действие: цвет «внимание».
  warning,
}

/// Подпись под полем формы: подсказка, предупреждение или ошибка.
///
/// Почему: в макете диалога «Add connection profile» (`AddProfile`, классы
/// `.ap-hint` и `.ap-err`) под каждым полем стоят короткие подписи 12 px
/// трёх видов. Без общего виджета каждая форма повторяла бы размеры и цвета
/// и расходилась с макетом (design.md change `add-app-settings-shell`, D16).
///
/// Для чего: только вёрстка текста; что показывать и когда, решает владелец.
/// Ошибка объявляется программам чтения с экрана как живая область.
///
/// Как использовать: `CodeLabFormNote('Parsed like a shell…')` в списке
/// `notes` у [CodeLabFormRow]; ключ теста — обычный `key:`.
class CodeLabFormNote extends StatelessWidget {
  const CodeLabFormNote(
    this.text, {
    this.tone = CodeLabFormNoteTone.hint,
    super.key,
  });

  final String text;
  final CodeLabFormNoteTone tone;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final color = switch (tone) {
      CodeLabFormNoteTone.hint => resources.textFillColorSecondary,
      CodeLabFormNoteTone.error => resources.systemFillColorCritical,
      CodeLabFormNoteTone.warning => resources.systemFillColorCaution,
    };
    return Semantics(
      liveRegion: tone == CodeLabFormNoteTone.error,
      child: CodeLabText(text, role: CodeLabTextRole.caption, color: color),
    );
  }
}

/// Строка формы: подпись слева в колонке 132 px, поле справа.
///
/// Почему: сетка формы макета (`.ap-form`: колонки `132px 1fr`, промежуток
/// 14 px, подпись опущена на 6 px к середине поля) должна быть одной на все
/// формы настроек (design.md change `add-app-settings-shell`, D16).
///
/// Для чего: выравнивает подписи и поля по колонкам и складывает под полем
/// [notes] (подсказки, ошибки). Виджет ничего не знает о профилях и
/// валидации.
///
/// Как использовать: строки кладутся в [CodeLabForm]:
/// `CodeLabFormRow(label: 'Name', child: TextBox(...), notes: [...])`.
class CodeLabFormRow extends StatelessWidget {
  const CodeLabFormRow({
    required this.label,
    required this.child,
    this.notes = const [],
    super.key,
  });

  /// Подпись слева.
  final String label;

  /// Поле или группа управления.
  final Widget child;

  /// Подписи под полем сверху вниз.
  final List<Widget> notes;

  /// Ширина колонки подписей (`grid-template-columns: 132px`).
  static const labelWidth = 132.0;

  /// Промежуток между колонками.
  static const columnGap = 14.0;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: labelWidth,
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: CodeLabText(label, color: resources.textFillColorSecondary),
          ),
        ),
        const SizedBox(width: columnGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              child,
              for (final note in notes) ...[const SizedBox(height: 4), note],
            ],
          ),
        ),
      ],
    );
  }
}

/// Столбец строк формы с промежутком макета 10 px.
///
/// Как использовать: `CodeLabForm(children: [CodeLabFormRow(...), …])`.
class CodeLabForm extends StatelessWidget {
  const CodeLabForm({required this.children, super.key});

  final List<Widget> children;

  static const _rowGap = 10.0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: _rowGap),
          children[i],
        ],
      ],
    );
  }
}

/// Вариант [CodeLabSegmentedControl].
class CodeLabSegment<T> {
  const CodeLabSegment({required this.value, required this.label, this.key});

  final T value;
  final String label;

  /// Ключ теста кнопки варианта.
  final Key? key;
}

/// Переключатель из нескольких вариантов в одной плашке (`.ap-seg` макета):
/// «Local stdio» / «WebSocket».
///
/// Почему: `ToggleButton` и `RadioButton` Fluent не дают плашки с
/// выделенным вариантом, как в макете диалога; повторять её в каждой форме
/// не нужно (design.md change `add-app-settings-shell`, D16).
///
/// Для чего: выбор одного из нескольких вариантов; состояние держит
/// владелец ([value]), повторное нажатие на выбранный вариант [onChanged] не
/// вызывает.
///
/// Как использовать: `CodeLabSegmentedControl(options: …, value: …,
/// onChanged: …)`; тип значения `T` выводится из вариантов. Для программ
/// чтения с экрана варианты — группа взаимоисключающих кнопок с подписью
/// [semanticLabel].
class CodeLabSegmentedControl<T> extends StatelessWidget {
  const CodeLabSegmentedControl({
    required this.options,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
    super.key,
  });

  final List<CodeLabSegment<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    return Semantics(
      label: semanticLabel,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: resources.subtleFillColorSecondary,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < options.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _Segment<T>(
                  option: options[i],
                  selected: options[i].value == value,
                  onPressed: () {
                    if (options[i].value != value) {
                      onChanged(options[i].value);
                    }
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Segment<T> extends StatelessWidget {
  const _Segment({
    required this.option,
    required this.selected,
    required this.onPressed,
  });

  final CodeLabSegment<T> option;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    return Semantics(
      // Ключ — на узле семантики, чтобы тест видел состояние «выбран».
      key: option.key,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: HoverButton(
        onPressed: onPressed,
        builder: (context, states) => DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? resources.cardBackgroundFillColorDefault
                : (states.isHovered
                      ? resources.subtleFillColorSecondary
                      : const Color(0x00000000)),
            border: selected
                ? Border.all(color: resources.cardStrokeColorDefault)
                : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: CodeLabText(
              option.label,
              color: selected
                  ? resources.textFillColorPrimary
                  : resources.textFillColorSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
