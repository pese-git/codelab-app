import 'package:fluent_ui/fluent_ui.dart';

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
