import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Строка настройки: заголовок, описание и элемент управления справа.
///
/// Почему: строки «Connect on start», «Restart agent», «Theme» и другие в
/// макете настроек (артборды `Connection`, `General`, класс `.f-sc`) имеют
/// одну вёрстку — карточка с необязательным значком, заголовком, описанием и
/// управляющим элементом. Без общего виджета каждая страница повторяла бы её
/// и расходилась с макетом (design.md change `add-app-settings-shell`, D16).
///
/// Для чего: только вёрстка; значение и реакцию на изменение хранит владелец
/// и передаёт готовый [trailing] (`ToggleSwitch`, кнопку, `ComboBox`). Виджет
/// не знает ни профилей, ни настроек (D16).
///
/// Как использовать: `CodeLabSettingsRow(title:, description:, trailing:)`.
/// Ключ теста передаётся обычным `key:`; [description] и [trailing] можно
/// опустить. Строки собирает [CodeLabSettingsSection].
///
/// Контракт [trailing] на узкой строке: ширина трейлинга ограничивается
/// (заголовку остаётся не менее [_minTextWidth]), поэтому элемент должен
/// переносить ограничение — `ComboBox` с `isExpanded: true`, поле ввода в
/// `SizedBox` с шириной не больше ограничения; жёстко широкий виджет
/// переполнит строку.
class CodeLabSettingsRow extends StatelessWidget {
  const CodeLabSettingsRow({
    required this.title,
    this.description,
    this.descriptionMaxLines = 2,
    this.leading,
    this.trailing,
    this.footer,
    super.key,
  });

  /// Заголовок строки.
  final String title;

  /// Пояснение под заголовком; число его строк задаёт [descriptionMaxLines].
  final String? description;

  /// Сколько строк занимает [description]: по умолчанию 2 (с многоточием), `null`
  /// — без ограничения, описание переносится целиком (change
  /// `add-app-general-page`, D17).
  ///
  /// Почему параметр: на узком окне многоточие съедало смысл описания
  /// («Применится при следующем запуске»); страница, которой важен весь текст,
  /// передаёт `null`, остальные страницы остаются на двух строках.
  final int? descriptionMaxLines;

  /// Значок слева.
  final IconData? leading;

  /// Элемент управления справа; состояние держит владелец.
  final Widget? trailing;

  /// Элемент под строкой заголовка и описания внутри той же карточки.
  ///
  /// Почему: в узкой области переключатель с длинной подписью не помещается
  /// справа, а отдельный блок под строкой выглядит оторванным от её фона и
  /// рамки (ручная проверка macOS, change `add-app-appearance-page`).
  ///
  /// Для чего: владелец кладёт сюда управляющий элемент, который переносится
  /// на ширину карточки (`Row` с `Expanded`-подписью); отступ сверху 8, боковые
  /// поля те же, что у заголовка. Без [footer] вёрстка прежняя.
  ///
  /// Как использовать: `footer: Row(children: [ToggleSwitch(...),
  /// SizedBox(width: 8), Expanded(child: Text(...))])`; можно вместе с
  /// [trailing], но тогда [footer] остаётся под обоими.
  final Widget? footer;

  static const _radius = 4.0;
  static const _gap = 16.0;
  static const _iconSize = 16.0;

  /// Минимум ширины заголовка: «Default model» и подобные заголовки
  /// страниц настроек в одну строку (~14 символов шрифта 14 pt, с запасом).
  static const _minTextWidth = 190.0;

  /// Минимум ширины трейлинга: переключатель или кнопка с короткой
  /// подписью; уже этого элемент управления теряет смысл.
  static const _minTrailingWidth = 96.0;

  @override
  Widget build(BuildContext context) {
    final resources = FluentTheme.of(context).resources;
    final description = this.description;
    final leading = this.leading;
    final trailing = this.trailing;
    final footer = this.footer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        border: Border.all(color: resources.cardStrokeColorDefault),
        borderRadius: BorderRadius.circular(_radius),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // Ширина строки без значка и промежутков вокруг трейлинга.
                  final free =
                      constraints.maxWidth -
                      (leading != null ? _iconSize + _gap : 0) -
                      _gap;
                  final trailingMax = free.isFinite
                      ? math.max(_minTrailingWidth, free - _minTextWidth)
                      : double.infinity;
                  return Row(
                    children: [
                      if (leading != null) ...[
                        Icon(leading, size: _iconSize),
                        const SizedBox(width: _gap),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CodeLabText(title),
                            if (description != null)
                              CodeLabText(
                                description,
                                role: CodeLabTextRole.caption,
                                maxLines: descriptionMaxLines,
                                overflow: descriptionMaxLines == null
                                    ? TextOverflow.clip
                                    : TextOverflow.ellipsis,
                                color: resources.textFillColorSecondary,
                              ),
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: _gap),
                        // Трейлинг фиксированной ширины (ComboBox 260 pt) на узкой
                        // строке вытеснял заголовок, и тот ломался по буквам: при
                        // окне 800 pt странице достаётся ~400 pt (окно
                        // по умолчанию, `MainMenu.xib`). Заголовку оставляем минимум
                        // [_minTextWidth], остальное — трейлингу, но не меньше
                        // [_minTrailingWidth]. На широкой строке предел не действует.
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: trailingMax),
                          child: trailing,
                        ),
                      ],
                    ],
                  );
                },
              ),
              if (footer != null)
                Padding(padding: const EdgeInsets.only(top: 8), child: footer),
            ],
          ),
        ),
      ),
    );
  }
}
