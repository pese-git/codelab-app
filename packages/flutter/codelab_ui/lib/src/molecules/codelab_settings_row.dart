import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart';

import '../atomics/codelab_text.dart';

/// Строка настройки: заголовок, описание и элемент управления справа.
///
/// Почему: строки «Connect on start», «Restart agent», «Theme» и другие в
/// макете настроек (артборды `Connection`, `General`, класс `.f-sc`) имеют
/// одну вёрстку — карточка с необязательным значком, двумя строками текста и
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
    this.leading,
    this.trailing,
    super.key,
  });

  /// Заголовок строки.
  final String title;

  /// Пояснение под заголовком, до двух строк.
  final String? description;

  /// Значок слева.
  final IconData? leading;

  /// Элемент управления справа; состояние держит владелец.
  final Widget? trailing;

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
          child: LayoutBuilder(
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
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
        ),
      ),
    );
  }
}
