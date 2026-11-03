import 'dart:convert';

import 'package:codelab_agent_core/codelab_agent_core.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import 'config_loader.dart' show configLayerKindOf;
import 'yaml_reader.dart';

/// Проблема правки без значений: только путь файла, ключ и фиксированный текст.
ConfigIssue configEditIssue(String path, String message, {String key = ''}) =>
    ConfigIssue(
      kind: ConfigIssueKind.semantic,
      key: key,
      source: path,
      message: message,
    );

/// Пути ключей, затронутых правками (для сообщений и сопоставления с
/// предупреждениями загрузки).
List<String> touchedKeys(List<ConfigEdit> edits) => [
  for (final edit in edits)
    switch (edit) {
      SetValue(:final key) => key,
      UnsetValue(:final key) => key,
      RemoveTable(:final key) => key,
      UpsertMcpServer() || RemoveMcpServer() => 'mcp.servers',
    },
];

/// Правка текста `config.yaml` через `YamlEditor` (design.md change
/// `add-config-writer-and-reload`, D2, D5; `agent-core-architecture` §17.5.5,
/// «Правка с сохранением формата»).
///
/// Почему отдельный класс: `ConfigWriter` отвечает за lock, проверку и
/// атомарную замену файла, а работа с деревом документа (путь ключа →
/// узел `yaml_edit`, кавычки, создание недостающих предков, удаление пустых
/// родителей) не знает о файлах и тестируется на строках.
///
/// Как использовать: `const ConfigDocumentEditor().apply(original, edits,
/// path, layer)` возвращает новый текст либо бросает [ConfigException] с
/// `cannot edit <key> automatically; edit the file manually`. Значения правок
/// в тексты ошибок не попадают.
final class ConfigDocumentEditor {
  const ConfigDocumentEditor();

  /// Применяет правки по одной к тексту файла через `YamlEditor`. Всё вне
  /// изменённых узлов остаётся побайтово тем же (комментарии, порядок,
  /// стиль, перевод строк).
  String apply(
    String original,
    List<ConfigEdit> edits,
    String path,
    ConfigLayer layer,
  ) {
    ConfigException cannotEdit(String key) => ConfigException([
      configEditIssue(
        path,
        'cannot edit $key automatically; edit the file manually',
        key: key,
      ),
    ]);

    var text = original;
    if (original.trim().isNotEmpty &&
        readYamlTree(
              original,
              source: path,
              kind: configLayerKindOf(layer),
            ).tree ==
            null) {
      // Якоря, теги, повторные ключи и прочее нарушение профиля §15.5:
      // `YamlEditor` не гарантирует сохранность структуры (D5, п. 6).
      throw cannotEdit(touchedKeys(edits).firstOrNull ?? '');
    }
    for (final edit in edits) {
      final key = touchedKeys([edit]).single;
      try {
        text = switch (edit) {
          SetValue(:final key, :final value) => _set(text, key, value, path),
          UnsetValue(:final key) => _remove(text, key, path),
          RemoveTable(:final key) => _remove(text, key, path),
          UpsertMcpServer(:final server) => _upsertServer(text, server, path),
          // Только по `name`: `mcp remove 0` не должен удалить первый
          // сервер по номеру (ревью итерации 4, safety M).
          RemoveMcpServer(:final name) => _remove(
            text,
            'mcp.servers[$name]',
            path,
            byNumber: false,
          ),
        };
      } on ConfigException {
        rethrow;
      } on Object catch (error) {
        // Отказы `YamlEditor` (`PathError`, `AliasException`, ...). Ошибки
        // программиста (`TypeError`) не маскируются.
        if (error is ArgumentError ||
            error is StateError ||
            error is UnsupportedError ||
            error is YamlException ||
            error is AliasException) {
          throw cannotEdit(key);
        }
        rethrow;
      }
    }
    return text;
  }

  /// Значение для `YamlEditor`: строка, которую YAML 1.1 прочитал бы как
  /// булево или null (`off`, `yes`), и строка с `${…}` — в двойных кавычках;
  /// остальное решает `yaml_edit` (§17.5.5, п. 5).
  Object? _wrap(Object? value) => switch (value) {
    final String s when _needsQuotes(s) => wrapAsYamlNode(
      s,
      scalarStyle: ScalarStyle.DOUBLE_QUOTED,
    ),
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) '$key': _wrap(value),
    },
    final List<Object?> list => [for (final item in list) _wrap(item)],
    _ => value,
  };

  static final _ambiguousWord = RegExp(
    r'^(y|n|yes|no|on|off|true|false|null|~)$',
    caseSensitive: false,
  );

  bool _needsQuotes(String s) =>
      _ambiguousWord.hasMatch(s) || s.contains(r'${');

  String _set(String text, String key, Object value, String path) {
    final segments = splitKeyPath(key)!;
    final wrapped = _wrap(value);
    final editor = YamlEditor(text);
    final r = _resolve(editor, segments);
    if (r.resolved == segments.length) {
      if (_same(r.node, value)) {
        return text;
      }
      editor.update(r.path, wrapped);
      return editor.toString();
    }
    final segment = segments[r.resolved];
    final rest = segments.sublist(r.resolved + 1);
    if (segment.isElement || rest.any((s) => s.isElement)) {
      throw ConfigException([
        configEditIssue(
          path,
          'no such list element on the way to $key',
          key: key,
        ),
      ]);
    }
    final node = r.node;
    if (node is YamlMap && !_isEmptyFlow(node)) {
      editor.update([...r.path, segment.value], _nest(rest, wrapped));
      return editor.toString();
    }
    final whole = _nest(segments.sublist(r.resolved), wrapped);
    if ((node is YamlScalar && node.value == null) || _isEmptyFlow(node)) {
      if (r.path.isEmpty && node is YamlScalar) {
        // Пустой документ или одни комментарии: `update([])` стёр бы
        // комментарии, поэтому блок дописывается после них.
        return _appendRoot(text, whole);
      }
      editor.update(r.path, whole);
      return editor.toString();
    }
    throw ConfigException([
      configEditIssue(
        path,
        'cannot edit $key automatically; edit the file manually',
        key: key,
      ),
    ]);
  }

  bool _isEmptyFlow(YamlNode node) =>
      node is YamlMap && node.isEmpty && node.style == CollectionStyle.FLOW;

  /// Вложенные отображения для хвоста пути, которого в документе нет.
  Object? _nest(List<KeyPathSegment> segments, Object? value) {
    Object? out = value;
    for (final segment in segments.reversed) {
      out = {segment.value: out};
    }
    return out;
  }

  String _appendRoot(String text, Object? block) {
    final newline = text.contains('\r\n') ? '\r\n' : '\n';
    final editor = YamlEditor('')..update(const [], block);
    var rendered = editor.toString().replaceAll('\r\n', '\n');
    if (!rendered.endsWith('\n')) {
      rendered = '$rendered\n';
    }
    final head = text.isEmpty || text.endsWith('\n') ? text : '$text$newline';
    return '$head${rendered.replaceAll('\n', newline)}';
  }

  String _remove(String text, String key, String path, {bool byNumber = true}) {
    final segments = splitKeyPath(key)!;
    final editor = YamlEditor(text);
    final r = _resolve(editor, segments, byNumber: byNumber);
    if (r.resolved != segments.length || r.path.isEmpty) {
      throw ConfigException([
        configEditIssue(path, 'not present in $path', key: key),
      ]);
    }
    editor.remove(r.path);
    _pruneEmptyParents(editor, r.path);
    return editor.toString();
  }

  /// Опустевшее отображение или список без комментариев удаляется вместе с
  /// ключом (§17.5.5, п. 3); корень документа остаётся.
  void _pruneEmptyParents(YamlEditor editor, List<Object> removed) {
    var path = removed.sublist(0, removed.length - 1);
    while (path.isNotEmpty) {
      final node = editor.parseAt(path);
      final empty =
          (node is YamlMap && node.isEmpty) ||
          (node is YamlList && node.isEmpty);
      if (!empty || node.span.text.contains('#')) {
        return;
      }
      editor.remove(path);
      path = path.sublist(0, path.length - 1);
    }
  }

  String _upsertServer(String text, Map<String, Object?> server, String path) {
    final name = server['name']! as String;
    final wrapped = _wrap(server)! as Map<Object?, Object?>;
    final editor = YamlEditor(text);
    final r = _resolve(editor, const [
      (value: 'mcp', isElement: false),
      (value: 'servers', isElement: false),
    ]);
    final node = r.node;
    if (r.resolved == 2 && node is YamlList && node.isNotEmpty) {
      final index = _elementIndex(node, name, byNumber: false);
      if (index == null) {
        editor.appendToList(r.path, wrapped);
        return editor.toString();
      }
      final element = node.nodes[index];
      final at = [...r.path, index];
      if (element is YamlMap) {
        for (final key in [for (final k in element.keys) '$k']) {
          if (!wrapped.containsKey(key)) {
            editor.remove([...at, key]);
          }
        }
      }
      for (final MapEntry(:key, :value) in wrapped.entries) {
        final existing = element is YamlMap ? element.nodes[key] : null;
        if (existing != null && _same(existing, server[key])) {
          continue;
        }
        editor.update([...at, key], value);
      }
      return editor.toString();
    }
    return _set(text, 'mcp.servers', [server], path);
  }

  /// Одинаковы ли значение узла документа и значение правки (по JSON):
  /// тогда `update` не нужен, и байты узла не перезаписываются.
  bool _same(YamlNode node, Object? value) {
    try {
      return jsonEncode(node.value) == jsonEncode(value);
    } on Object {
      return false;
    }
  }

  /// Идёт по документу сегментами пути и возвращает путь `YamlEditor` до
  /// последнего найденного узла, число найденных сегментов и сам узел.
  ({List<Object> path, int resolved, YamlNode node}) _resolve(
    YamlEditor editor,
    List<KeyPathSegment> segments, {
    bool byNumber = true,
  }) {
    var node = editor.parseAt(const []);
    final path = <Object>[];
    var resolved = 0;
    for (final segment in segments) {
      if (segment.isElement) {
        if (node is! YamlList) {
          break;
        }
        final index = _elementIndex(node, segment.value, byNumber: byNumber);
        if (index == null) {
          break;
        }
        path.add(index);
        node = node.nodes[index];
      } else {
        if (node is! YamlMap) {
          break;
        }
        final next = node.nodes[segment.value];
        if (next == null) {
          break;
        }
        path.add(segment.value);
        node = next;
      }
      resolved++;
    }
    return (path: path, resolved: resolved, node: node);
  }

  /// Сначала по полю `name`, и только если такого элемента нет и селектор —
  /// число, по номеру: сервер, названный `0`, не перекрывается первым
  /// элементом (как `ConfigSnapshot.get`).
  int? _elementIndex(YamlList list, String selector, {bool byNumber = true}) {
    for (var i = 0; i < list.length; i++) {
      final item = list.nodes[i];
      if (item is YamlMap && item['name'] == selector) {
        return i;
      }
    }
    final index = byNumber ? int.tryParse(selector) : null;
    return index != null && index >= 0 && index < list.length ? index : null;
  }
}
