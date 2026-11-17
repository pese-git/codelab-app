import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart' show setEquals;

/// Политика ссылок и изображений, которую app передаёт ленте.
///
/// Почему: решение «опасно ли открыть эту ссылку или загрузить это
/// изображение» принимает app, а не виджет (вложенный `AGENTS.md` пакета §2,
/// design.md `add-desktop-markdown` D2). Кит только рисует и сообщает о клике.
///
/// Для чего: `InheritedWidget` над лентой; builder'ы конфигурации читают
/// политику из `context`, поэтому смена политики не создаёт новую
/// `CodeLabMarkdownConfig` и не перестраивает закрытые блоки (D3).
///
/// Устойчивость: app передаёт функции верхнего уровня и tear-off методов
/// Cubit, а `shownImages` сравнивается по содержимому ([setEquals]): набор
/// пересоздаётся при каждом обновлении ленты, и сравнение по ссылке
/// перестраивало бы заглушки зря (DSK-3, D3).
///
/// Как использовать: app оборачивает ленту в `CodeLabMarkdownScope(...)`
/// (итерация 4). Без scope (превью, тесты кита) ссылки и изображения
/// неактивны — [maybeOf] возвращает `null`.
class CodeLabMarkdownScope extends InheritedWidget {
  const CodeLabMarkdownScope({
    required this.canOpenLink,
    required this.onOpenLink,
    required this.canLoadImage,
    required this.imageFor,
    required this.shownImages,
    required this.onShowImage,
    required this.onImageFailed,
    required super.child,
    super.key,
  });

  /// Можно ли сделать ссылку активной (`isOpenableLink` в app).
  final bool Function(Uri uri) canOpenLink;

  /// Клик по активной ссылке.
  final ValueChanged<Uri> onOpenLink;

  /// Можно ли предложить загрузку изображения (`isLoadableImage` в app).
  final bool Function(Uri uri) canLoadImage;

  /// Источник изображения после явного действия пользователя.
  final ImageProvider Function(Uri uri) imageFor;

  /// Ключи показанных изображений `<rowId>#image:<url>` (D6).
  final Set<String> shownImages;

  /// Нажата «Show image»; аргумент — ключ изображения.
  final ValueChanged<String> onShowImage;

  /// Загрузка показанного изображения не удалась: ключ и сама ошибка как есть.
  /// Кит ошибку не разбирает и журнала не знает: код причины и событие
  /// определяет app, которому известны свои типы ошибок (D6, D12).
  final void Function(String key, Object error) onImageFailed;

  /// Политика из ближайшего scope или `null`, если app её не передал.
  static CodeLabMarkdownScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CodeLabMarkdownScope>();

  @override
  bool updateShouldNotify(CodeLabMarkdownScope oldWidget) =>
      canOpenLink != oldWidget.canOpenLink ||
      onOpenLink != oldWidget.onOpenLink ||
      canLoadImage != oldWidget.canLoadImage ||
      imageFor != oldWidget.imageFor ||
      !setEquals(shownImages, oldWidget.shownImages) ||
      onShowImage != oldWidget.onShowImage ||
      onImageFailed != oldWidget.onImageFailed;
}
