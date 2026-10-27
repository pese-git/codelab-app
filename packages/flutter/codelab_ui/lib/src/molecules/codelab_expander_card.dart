import 'package:fluent_ui/fluent_ui.dart';

/// Раскрывающийся блок ленты: карточка с шапкой и телом под ней.
///
/// Почему: строка вызова в макете — Fluent Expander (артборд Main,
/// `.f-exp`): шапка не ниже 48 px с полями 6 6 6 16, промежутками 12 и
/// шевроном в зоне 32×32, тело с полями 16 на фоне чуть темнее карточки.
/// Собственная вёрстка строки расходилась с макетом. `Expander` из
/// `fluent_ui` не подходит: раскрытие здесь решает лента (design D3 change
/// `redesign-transcript-rows`), а он держит его в своём состоянии и читает
/// `PageStorage`. Блок мыслей в макете тоже Expander, но у нас он
/// намеренно легче — строка с чертой слева, без карточки: мысли не должны
/// весить в ленте столько же, сколько вызовы.
///
/// Для чего: только вёрстка и нажатие на шапку; что раскрыто, решает
/// владелец.
///
/// Как использовать: `CodeLabExpanderCard(leading:, title:, trailing:,
/// expanded:, onToggle:, body:)`. [onToggle] `null` — шапка не нажимается и
/// шеврона нет (строка без подробностей или с ожидающим одобрением).
/// [body] рисуется, только когда передан: показывать ли его, решает
/// владелец.
class CodeLabExpanderCard extends StatelessWidget {
  const CodeLabExpanderCard({
    required this.leading,
    required this.title,
    required this.expanded,
    this.trailing,
    this.onToggle,
    this.body,
    this.bodyPadding = const EdgeInsets.all(16),
    this.headerKey,
    this.semanticLabel,
    super.key,
  });

  /// Значок слева, в квадрате 16 px.
  final Widget leading;
  final Widget title;

  /// Теги справа от заголовка, до шеврона.
  final Widget? trailing;
  final bool expanded;
  final ValueChanged<bool>? onToggle;
  final Widget? body;
  final EdgeInsetsGeometry bodyPadding;
  final Key? headerKey;

  /// Подпись шапки для экранного диктора, если заголовок — не просто текст.
  final String? semanticLabel;

  static const _headerMinHeight = 48.0;
  static const _gap = 12.0;
  static const _radius = 4.0;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final resources = theme.resources;
    final onToggle = this.onToggle;
    final trailing = this.trailing;
    final body = this.body;

    final header = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _headerMinHeight),
      child: Padding(
        // Справа 6, когда последним стоит шеврон в зоне 32 px, — как в
        // макете; без шеврона тег отступает от края так же, как значок.
        padding: EdgeInsets.fromLTRB(16, 6, onToggle == null ? 16 : 6, 6),
        child: Row(
          children: [
            SizedBox.square(dimension: 16, child: Center(child: leading)),
            const SizedBox(width: _gap),
            Expanded(child: title),
            if (trailing != null) ...[const SizedBox(width: _gap), trailing],
            if (onToggle != null) ...[
              const SizedBox(width: _gap),
              SizedBox.square(
                dimension: 32,
                child: Center(
                  child: Icon(
                    expanded
                        ? FluentIcons.chevron_up_small
                        : FluentIcons.chevron_down_small,
                    size: 12,
                    color: resources.textFillColorPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        border: Border.all(color: resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: ClipRRect(
        // Фон тела не должен выступать за скругление карточки.
        borderRadius: BorderRadius.circular(_radius - 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onToggle != null)
              Semantics(
                button: true,
                expanded: expanded,
                label: semanticLabel,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    key: headerKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onToggle(!expanded),
                    child: header,
                  ),
                ),
              )
            else
              Semantics(
                label: semanticLabel,
                child: KeyedSubtree(key: headerKey, child: header),
              ),
            if (body != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: resources.cardBackgroundFillColorSecondary,
                  border: Border(
                    top: BorderSide(color: resources.cardStrokeColorDefault),
                  ),
                ),
                child: Padding(padding: bodyPadding, child: body),
              ),
          ],
        ),
      ),
    );
  }
}
