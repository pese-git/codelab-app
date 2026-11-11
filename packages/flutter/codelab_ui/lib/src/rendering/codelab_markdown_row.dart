import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/gestures.dart';

import '../atomics/atomics.dart';
import 'escape_for_display.dart';

/// Огороженный блок кода, найденный в тексте ответа.
///
/// Почему: builder блока кода получает от пакета язык и код, но не номер
/// блока в ответе, а ключу `code-copy-<id>-<n>` он нужен.
///
/// Для чего: запись результата [scanFencedBlocks] — язык, код без ограды и
/// признак «ограда закрыта».
///
/// Как использовать: создаёт только [scanFencedBlocks]; читает
/// [CodeLabMarkdownRowModel.indexOf].
class CodeLabFencedBlock {
  const CodeLabFencedBlock({
    required this.language,
    required this.code,
    required this.closed,
  });

  final String language;
  final String code;
  final bool closed;
}

/// Находит огороженные блоки кода в [text] в порядке появления.
///
/// Почему: builder блока кода получает от пакета только язык, код и признак
/// «закрыт», а ключу кнопки `code-copy-<id>-<n>` и счётчикам нужен порядковый
/// номер блока в ответе (D4, D13).
///
/// Для чего: единственное место, где кит разбирает ограды сам, и только ради
/// номера; разбор markdown для отрисовки остаётся за пакетом (DSK-2). Правила
/// упрощены: ограда из трёх и более `` ` `` или `~` с любым отступом (блок в
/// списке) и маркерами цитаты `>` перед ней закрывается строкой из того же
/// символа не короче открывающей.
List<CodeLabFencedBlock> scanFencedBlocks(String text) {
  final blocks = <CodeLabFencedBlock>[];
  final open = RegExp(r'^((?:[ \t]*>)*)([ \t]*)(`{3,}|~{3,})(.*)$');
  final quotes = RegExp(r'^(?:[ \t]*>[ ]?)*');
  String? marker;
  var indent = 0;
  var language = '';
  final buffer = <String>[];
  for (final line in text.split('\n')) {
    if (marker == null) {
      final match = open.firstMatch(line);
      if (match == null) continue;
      final fence = match.group(3)!;
      final info = match.group(4)!.trim();
      indent = match.group(2)!.length;
      if (fence.startsWith('`') && info.contains('`')) continue;
      marker = fence;
      language = info.split(RegExp(r'\s+')).first;
      buffer.clear();
      continue;
    }
    // Снимаются маркеры цитаты и отступ самой ограды; отступы внутри кода
    // остаются.
    var body = line.substring(quotes.firstMatch(line)!.end);
    var cut = 0;
    while (cut < indent && cut < body.length && body[cut] == ' ') {
      cut++;
    }
    body = body.substring(cut);
    final trimmed = body.trim();
    if (trimmed.length >= marker.length &&
        trimmed.split('').every((c) => c == marker![0])) {
      blocks.add(
        CodeLabFencedBlock(
          language: language,
          code: buffer.join('\n'),
          closed: true,
        ),
      );
      marker = null;
      continue;
    }
    buffer.add(body);
  }
  if (marker != null) {
    blocks.add(
      CodeLabFencedBlock(
        language: language,
        code: buffer.join('\n'),
        closed: false,
      ),
    );
  }
  return blocks;
}

/// Изменяемая модель строки, общая для builder'ов конфигурации.
///
/// Почему: конфигурация одна на все строки ленты (D3), а id строки и номера
/// блоков нужны builder'ам, которые пакет вызывает без этих сведений.
///
/// Для чего: хранит id, найденные ограды и занятые номера блоков, чтобы два
/// одинаковых блока различались по порядку монтирования.
///
/// Как использовать: `CodeLabMarkdown` вызывает [update] перед каждой сборкой;
/// `State` блока кода берёт номер [claim] в `initState` и возвращает его
/// [release] в `dispose`. Номер живёт в `State`, а не в builder'е: пакет
/// вызывает builder повторно при пересборке сегмента (смена темы, новый
/// текст), а `State` при этом сохраняется и номер не меняется. Привязка к
/// `BuildContext` builder'а не годится: он общий для всех блоков документа.
class CodeLabMarkdownRowModel {
  String id = '';
  List<CodeLabFencedBlock> blocks = const [];

  /// Занятые номера блоков.
  final Set<int> _occupied = {};

  /// Обновляет модель перед сборкой.
  void update({required String id, required List<CodeLabFencedBlock> blocks}) {
    this.id = id;
    this.blocks = blocks;
  }

  /// Занимает номер блока кода, смонтированного с данными аргументами.
  ///
  /// Закрытый блок ищется по языку и коду, одинаковые блоки получают номера
  /// по порядку монтирования (то есть по порядку в тексте). Незакрытый — это
  /// последняя незакрытая ограда в тексте. Блок, которого сканер не нашёл
  /// (нетипичная вложенность), получает свободный номер за пределами
  /// найденных, поэтому ключи разных блоков не совпадают.
  int claim(String language, String code, bool closed) {
    final lang = language.trim();
    final trimmed = code.trimRight();
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final matches = closed
          ? b.closed && b.language == lang && b.code.trimRight() == trimmed
          : !b.closed && i == blocks.lastIndexWhere((x) => !x.closed);
      if (matches && _occupied.add(i)) return i;
    }
    var fallback = blocks.length + 1;
    while (!_occupied.add(fallback)) {
      fallback++;
    }
    return fallback;
  }

  /// Освобождает номер, когда блок размонтирован.
  void release(int index) => _occupied.remove(index);

  /// Контекст хоста (`CodeLabMarkdown`) для оверлея подсказки; `null` после
  /// размонтирования.
  BuildContext? host;

  /// Позиция прокрутки ближайшего `Scrollable` хоста: берётся при сборке
  /// хоста, а не в обработчике наведения, где контекст может быть устаревшим;
  /// подсказка закрывается при её изменении.
  ScrollPosition? scroll;
  String? _tooltipUrl;

  final Map<String, TapGestureRecognizer> _recognizers = {};
  OverlayEntry? _tooltip;
  ScrollPosition? _watchedScroll;

  /// Распознаватель клика по ссылке [url]: один на адрес, чтобы пересборка
  /// хвоста при стриме не копила объекты; обработчик обновляется всегда.
  TapGestureRecognizer recognizerFor(String url, VoidCallback onTap) {
    final recognizer = _recognizers.putIfAbsent(url, TapGestureRecognizer.new);
    recognizer.onTap = onTap;
    return recognizer;
  }

  /// Показывает подсказку с полным адресом у курсора (D5): свой оверлей в
  /// стиле Fluent, а не Material `Tooltip`. Закрывается при уходе курсора,
  /// прокрутке и [dispose].
  void showTooltip(String url, Offset pointer) {
    hideTooltip();
    final context = host;
    if (context == null || !context.mounted) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final message = displayAddress(url);
    _tooltip = OverlayEntry(
      builder: (overlayContext) {
        final theme = FluentTheme.of(overlayContext);
        return IgnorePointer(
          child: CustomSingleChildLayout(
            delegate: _TooltipLayout(pointer + const Offset(12, 18)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: theme.menuColor,
                border: Border.all(
                  color: theme.resources.cardStrokeColorDefault,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: CodeLabText(message, role: CodeLabTextRole.caption),
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_tooltip!);
    _tooltipUrl = url;
    _watchedScroll = scroll?..addListener(hideTooltip);
  }

  /// Убирает подсказку, если она показана.
  void hideTooltip() {
    _tooltipUrl = null;
    _watchedScroll?.removeListener(hideTooltip);
    _watchedScroll = null;
    _tooltip?.remove();
    _tooltip?.dispose();
    _tooltip = null;
  }

  /// Строка обновилась: подсказка адреса, которого в новом тексте нет, или
  /// подсказка другой строки гаснет сама — `onExit` старого спана не придёт.
  void hideTooltipIfStale({required bool sameRow, required String text}) {
    final url = _tooltipUrl;
    if (url != null && (!sameRow || !text.contains(url))) hideTooltip();
  }

  /// Освобождает распознаватели и подсказку при размонтировании строки.
  void dispose() {
    hideTooltip();
    host = null;
    for (final recognizer in _recognizers.values) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }
}

/// Раскладка подсказки: левый верхний угол у курсора, целиком в оверлее.
class _TooltipLayout extends SingleChildLayoutDelegate {
  const _TooltipLayout(this.anchor);

  final Offset anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    anchor.dx.clamp(0.0, (size.width - childSize.width).clamp(0.0, size.width)),
    anchor.dy.clamp(
      0.0,
      (size.height - childSize.height).clamp(0.0, size.height),
    ),
  );

  @override
  bool shouldRelayout(_TooltipLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

/// Передаёт [CodeLabMarkdownRowModel] builder'ам без подписки на изменения.
///
/// Builder читает модель через `getInheritedWidgetOfExactType`: подписка
/// перестраивала бы все закрытые блоки на каждой дельте (DSK-3).
class CodeLabMarkdownRowScope extends InheritedWidget {
  const CodeLabMarkdownRowScope({
    required this.model,
    required super.child,
    super.key,
  });

  final CodeLabMarkdownRowModel model;

  static CodeLabMarkdownRowModel of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CodeLabMarkdownRowScope>()?.model ??
      CodeLabMarkdownRowModel();

  @override
  bool updateShouldNotify(CodeLabMarkdownRowScope oldWidget) => false;
}
