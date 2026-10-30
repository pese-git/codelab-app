import 'dart:collection';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:yaml/yaml.dart';

/// Результат [readYamlTree]: дерево слоя либо проблемы файла.
///
/// Инвариант: [tree] равно `null` тогда и только тогда, когда [issues] не
/// пусто. Так вызывающий не может получить дерево из файла с нарушением
/// профиля.
final class YamlReadResult {
  const YamlReadResult.tree(ConfigTree this.tree) : issues = const [];

  const YamlReadResult.issues(this.issues) : tree = null;

  final ConfigTree? tree;
  final List<ConfigIssue> issues;
}

const _profileMessage =
    'anchors, aliases, merge keys and tags are not supported';

/// Предел вложенности коллекций (`agent-core-architecture` §15.5, CFG-21).
///
/// Почему: `package:yaml` разбирает рекурсивно, и файл из тысяч `[` валит
/// процесс `StackOverflowError` ещё до проверки профиля; настоящему конфигу
/// глубже десятка уровней не нужно.
const maxYamlDepth = 64;

const _depthMessage = 'nesting is deeper than $maxYamlDepth levels';

/// Читает YAML в строгом профиле и строит [ConfigTree] с позициями ключей.
///
/// Почему в `codelab_agent_io`, а не в ядре: ядро не знает формата файла и не
/// импортирует `package:yaml` (CFG-5, PKG-2); мобильный и web-хосты передают
/// дерево из хранилища приложения. Профиль §15.5 (CFG-21) проверяется здесь,
/// до валидатора ядра, потому что только разборщик видит якоря, теги и типы
/// ключей (design.md change `add-agent-configuration`, D5; итог разведки
/// `package:yaml` записан там же).
///
/// Для чего: единственная точка, которая превращает текст в слой
/// конфигурации; тот же разбор позже нужен frontmatter определений агентов и
/// skills (§15.8), поэтому функция не знает путей конфига.
///
/// Как использовать: `readYamlTree(text, source: path, kind: …)`. Нарушения
/// профиля и синтаксис возвращаются списком [ConfigIssue] (`profile` и
/// `syntax`) с файлом, строкой и столбцом от 1, а не исключением: `config
/// check` показывает все проблемы сразу. Сообщения строятся из фиксированных
/// текстов разборщика и не содержат исходного текста файла — в нём может быть
/// секрет (CFG-2). Пустой файл и файл из комментариев — пустой слой.
///
/// [lineOffset] — сколько строк файла лежит выше [text] (frontmatter Markdown:
/// блок YAML начинается после строки `---`). Позиции проблем и дерева, в том
/// числе «first defined at» в тексте сообщения, строятся сразу в координатах
/// файла: перед разбором текст дополняется [lineOffset] пустыми строками, что
/// не меняет смысла YAML, и сдвиг не нужно применять к готовым сообщениям.
YamlReadResult readYamlTree(
  String text, {
  required String source,
  required ConfigLayerKind kind,
  int lineOffset = 0,
}) {
  // BOM сдвинул бы столбец первой строки на 1 (разведка D5), поэтому он
  // снимается до разбора.
  final unmarked = text.startsWith('﻿') ? text.substring(1) : text;
  final body = '\n' * lineOffset + unmarked;

  // До разбора: рекурсивный разборщик не должен видеть глубокое вложение.
  if (_flowDepthIssue(body, source) case final issue?) {
    return YamlReadResult.issues([issue]);
  }

  final List<YamlDocument> documents;
  try {
    documents = loadYamlDocuments(body);
  } on YamlException catch (error) {
    return YamlReadResult.issues([_parseIssue(error, body, source)]);
  } on StackOverflowError {
    // Вложение, которое не поймал лексический предел (`- - - …`).
    return YamlReadResult.issues([
      ConfigIssue(
        kind: ConfigIssueKind.syntax,
        key: '',
        source: source,
        message: 'the file is nested too deeply to be parsed',
      ),
    ]);
  }

  if (documents.length > 1) {
    final start = documents[1].contents.span.start;
    return YamlReadResult.issues([
      ConfigIssue(
        kind: ConfigIssueKind.profile,
        key: '',
        source: source,
        line: start.line + 1,
        column: start.column + 1,
        message: 'multiple YAML documents are not supported',
      ),
    ]);
  }

  final root = documents.isEmpty ? null : documents.single.contents;
  if (root == null || (root is YamlScalar && root.value == null)) {
    return YamlReadResult.tree(
      ConfigTree(kind: kind, source: source, values: const {}),
    );
  }
  if (root is! YamlMap) {
    final start = root.span.start;
    return YamlReadResult.issues([
      ConfigIssue(
        kind: ConfigIssueKind.profile,
        key: '',
        source: source,
        line: start.line + 1,
        column: start.column + 1,
        message: 'the top level must be a mapping',
      ),
    ]);
  }

  final walker = _Walker(source);
  // Тег или якорь на корневом отображении проверяет `_checkNode`, как и у
  // вложенных узлов: `mapping` его не вызывает.
  walker._checkNode(root, KeyPath.root, ConfigPosition(lineOffset + 1, 1));
  final values = walker.mapping(root, const [KeyPath.root], null, 1);
  if (walker.issues.isNotEmpty) {
    return YamlReadResult.issues(walker.issues);
  }
  return YamlReadResult.tree(
    ConfigTree(
      kind: kind,
      source: source,
      values: values,
      positions: walker.positions,
    ),
  );
}

/// Ошибка разборщика: повтор ключа — нарушение профиля с обеими позициями,
/// остальное — синтаксис.
ConfigIssue _parseIssue(YamlException error, String text, String source) {
  final start = error.span?.start;
  final line = start == null ? null : start.line + 1;
  final column = start == null ? null : start.column + 1;
  if (error.message == 'Duplicate mapping key.' && start != null) {
    final first = _firstKeyPosition(
      text,
      start.line,
      start.column,
      error.span!.text,
    );
    return ConfigIssue(
      kind: ConfigIssueKind.profile,
      key: '',
      source: source,
      line: line,
      column: column,
      message: first == null
          ? 'duplicate mapping key'
          : 'duplicate mapping key; first defined at $first',
    );
  }
  // Нестандартный тег: `message` разборщика называет сам тег, а имя тега
  // выбирает автор файла (секрет в нём маловероятен, но текст разборщика не
  // контролируем) — поэтому сообщение фиксированное (D5, CFG-2).
  if (error.message.startsWith('Undefined tag')) {
    return ConfigIssue(
      kind: ConfigIssueKind.profile,
      key: '',
      source: source,
      line: line,
      column: column,
      message: _profileMessage,
    );
  }
  // Только `message`: `toString()` исключения несёт фрагмент исходного текста.
  return ConfigIssue(
    kind: ConfigIssueKind.syntax,
    key: '',
    source: source,
    line: line,
    column: column,
    message: error.message,
  );
}

/// Лексическая проверка глубины flow-коллекций (`[` и `{`) до разбора.
///
/// Скобки в кавычках и комментариях не считаются. Кавычка открывает строку
/// только в начале скаляра (после `:`, `-`, `,`, `[`, `{` или в начале
/// строки): апостроф внутри простого скаляра (`don't`) не скрывает скобки.
/// Неточность допустима только в сторону пропуска: тогда разбор ловит
/// `StackOverflowError`.
ConfigIssue? _flowDepthIssue(String text, String source) {
  var depth = 0;
  var line = 1;
  var column = 0;
  String? quote;
  var comment = false;
  var previous = '\n'; // последний значимый символ перед текущим
  var previousSpace = true;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    column++;
    if (c == '\n') {
      line++;
      column = 0;
      comment = false;
      previous = '\n';
      previousSpace = true;
      // Многострочные строки допустимы: кавычка остаётся открытой.
      continue;
    }
    if (comment) {
      continue;
    }
    if (quote != null) {
      if (quote == '"' && c == '\\') {
        i++;
        column++;
      } else if (c == quote) {
        quote = null;
        previous = c;
        previousSpace = false;
      }
      continue;
    }
    if (c == ' ' || c == '\t' || c == '\r') {
      previousSpace = true;
      continue;
    }
    if (c == '#' && previousSpace) {
      comment = true;
      continue;
    }
    final startsScalar = previous == '\n' || ':-,[{'.contains(previous);
    if ((c == '"' || c == "'") && startsScalar) {
      quote = c;
    } else if (c == '[' || c == '{') {
      depth++;
      if (depth > maxYamlDepth) {
        return ConfigIssue(
          kind: ConfigIssueKind.profile,
          key: '',
          source: source,
          line: line,
          column: column,
          message: _depthMessage,
        );
      }
    } else if ((c == ']' || c == '}') && depth > 0) {
      depth--;
    }
    previous = c;
    previousSpace = false;
  }
  return null;
}

/// Позиция первого вхождения ключа, повторённого в [line0]:[column0]
/// (нумерация с 0), или `null`.
///
/// Почему лексически: после `Duplicate mapping key` дерева нет, а исключение
/// называет только второй ключ (разведка D5). Блочный стиль — вверх по строкам
/// с тем же отступом ключа (с учётом префикса `- `), flow-стиль — раньше в той
/// же строке.
ConfigPosition? _firstKeyPosition(
  String text,
  int line0,
  int column0,
  String rawKey,
) {
  final name = _unquote(rawKey);
  final escaped = RegExp.escape(name);
  final candidate = RegExp('^(?:"$escaped"|\'$escaped\'|$escaped)\\s*:');
  final lines = text.split(RegExp(r'\r?\n'));
  if (line0 >= lines.length) {
    return null;
  }

  final current = lines[line0];
  if (_keyColumn(current) != column0) {
    // Ключ не начинает строку: flow-отображение, ищем раньше в этой строке.
    final prefix = current.substring(0, column0.clamp(0, current.length));
    final flow = RegExp(
      '(?:^|[\\s{,])((?:"$escaped"|\'$escaped\'|$escaped))\\s*:',
    ).allMatches(prefix).lastOrNull;
    if (flow == null) {
      return null;
    }
    final offset = flow.start + flow.group(0)!.indexOf(flow.group(1)!);
    return ConfigPosition(line0 + 1, offset + 1);
  }

  for (var i = line0 - 1; i >= 0; i--) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }
    final column = _keyColumn(line);
    if (column < column0) {
      return null;
    }
    if (column == column0 && candidate.hasMatch(line.substring(column))) {
      return ConfigPosition(i + 1, column + 1);
    }
  }
  return null;
}

/// Столбец (с 0), с которого начинается ключ строки: после отступа и
/// префиксов блочного списка `- `.
int _keyColumn(String line) {
  var column = 0;
  while (column < line.length && line[column] == ' ') {
    column++;
  }
  while (column < line.length &&
      line[column] == '-' &&
      (column + 1 == line.length || line[column + 1] == ' ')) {
    column++;
    while (column < line.length && line[column] == ' ') {
      column++;
    }
  }
  return column;
}

String _unquote(String raw) =>
    raw.length >= 2 &&
        (raw.startsWith('"') && raw.endsWith('"') ||
            raw.startsWith("'") && raw.endsWith("'"))
    ? raw.substring(1, raw.length - 1)
    : raw;

/// Обход дерева `package:yaml`: проверка профиля и сбор значений и позиций.
final class _Walker {
  _Walker(this.source);

  final String source;
  final issues = <ConfigIssue>[];
  final positions = <String, ConfigPosition>{};

  /// Посещённые узлы: `package:yaml` отдаёт для ссылки `*x` тот же объект, что
  /// и для якоря `&x`, поэтому повторное посещение — это алиас (разведка D5).
  final _seen = HashSet<YamlNode>.identity();

  // Без имени типа `SourceLocation`: `source_span` не прямая зависимость.
  ConfigPosition _at(YamlNode node) =>
      ConfigPosition(node.span.start.line + 1, node.span.start.column + 1);

  void _issue(
    ConfigIssueKind kind,
    KeyPath path,
    ConfigPosition position,
    String message,
  ) => issues.add(
    ConfigIssue(
      kind: kind,
      key: path.value,
      source: source,
      line: position.line,
      column: position.column,
      message: message,
    ),
  );

  /// Узел не должен быть ссылкой и нести якорь или тег. Возвращает `false`,
  /// если вглубь идти не нужно (алиас).
  ///
  /// `span` узла с якорем или тегом начинается с индикатора, а у обычного
  /// узла `span.text` не может начинаться с `&` и `!` (разведка D5).
  bool _checkNode(YamlNode node, KeyPath path, ConfigPosition reference) {
    if (!_seen.add(node)) {
      _issue(ConfigIssueKind.profile, path, reference, _profileMessage);
      return false;
    }
    final text = node.span.text;
    if (text.startsWith('&') || text.startsWith('!')) {
      _issue(ConfigIssueKind.profile, path, _at(node), _profileMessage);
    }
    return true;
  }

  /// [paths] — адреса узла: основной и, у элемента списка с `name`, вторая
  /// форма (`[имя]` и `[индекс]`), чтобы позиция находилась по любой из них.
  /// [reference] — позиция, к которой привязывается проблема-ссылка.
  Object? node(
    YamlNode node,
    List<KeyPath> paths,
    ConfigPosition reference,
    int depth,
  ) {
    if (!_checkNode(node, paths.first, reference)) {
      return null;
    }
    if (depth > maxYamlDepth) {
      // Глубже не идём: рекурсия обхода тоже ограничена (D5).
      if (node is YamlMap || node is YamlList) {
        _issue(ConfigIssueKind.profile, paths.first, _at(node), _depthMessage);
        return null;
      }
    }
    return switch (node) {
      final YamlMap map => mapping(map, paths, reference, depth + 1),
      final YamlList list => _list(list, paths, depth + 1),
      final YamlScalar scalar => scalar.value,
      _ => null,
    };
  }

  Map<String, Object?> mapping(
    YamlMap map,
    List<KeyPath> paths,
    ConfigPosition? reference,
    int depth,
  ) {
    final out = <String, Object?>{};
    for (final MapEntry(key: rawKey, value: value) in map.nodes.entries) {
      final keyNode = rawKey as YamlNode;
      final keyPosition = _at(keyNode);
      if (keyNode is! YamlScalar || keyNode.value is! String) {
        _issue(
          ConfigIssueKind.profile,
          paths.first,
          keyPosition,
          'mapping keys must be strings',
        );
        continue;
      }
      final name = keyNode.value as String;
      final children = [for (final path in paths) path.child(name)];
      for (final child in children) {
        positions[child.value] = keyPosition;
      }
      if (name == '<<') {
        _issue(
          ConfigIssueKind.profile,
          children.first,
          keyPosition,
          _profileMessage,
        );
        continue;
      }
      // Якорь или тег на самом ключе (`&k a: 1`).
      final keyText = keyNode.span.text;
      if (keyText.startsWith('&') || keyText.startsWith('!')) {
        _issue(
          ConfigIssueKind.profile,
          children.first,
          keyPosition,
          _profileMessage,
        );
      }
      out[name] = node(value, children, keyPosition, depth);
    }
    return out;
  }

  List<Object?> _list(YamlList list, List<KeyPath> paths, int depth) {
    final listPosition = _at(list);
    final out = <Object?>[];
    for (var i = 0; i < list.nodes.length; i++) {
      final element = list.nodes[i];
      final name = _itemName(element);
      final itemPaths = [
        for (final path in paths) ...[
          if (name != null) path.at(name),
          path.at(i),
        ],
      ];
      final position = _at(element);
      for (final path in itemPaths) {
        positions[path.value] = position;
      }
      out.add(node(element, itemPaths, listPosition, depth));
    }
    return out;
  }

  /// `name` элемента-отображения: по нему элементы `mcp.servers` адресуются
  /// как `[имя]` (`KeyPath.at`, D3).
  String? _itemName(YamlNode element) {
    if (element is! YamlMap) {
      return null;
    }
    for (final MapEntry(:key, :value) in element.nodes.entries) {
      if (key is YamlScalar && key.value == 'name') {
        if (value is YamlScalar && value.value is String) {
          final name = value.value as String;
          return name.isEmpty ? null : name;
        }
      }
    }
    return null;
  }
}
