/// Разбор файла пользовательской темы (spec `client-themes`, D2, D3).
///
/// Почему: формат общий для app и CLI, поэтому разбор — одна чистая функция
/// без `dart:io` в web-безопасном ядре клиента; «строгость» — правило
/// потребителя: app применяет тему с предупреждениями, CLI считает любую
/// проблему ошибкой.
///
/// Как использовать: `ThemeFile.parse(имяФайла, текст)` или `parseBytes`
/// для сырых байт; результат — [ThemeLoaded] либо [ThemeRejected].
library;

import 'dart:convert';

import 'json_spans.dart';
import 'theme_color.dart';
import 'theme_issue.dart';
import 'theme_role.dart';

/// Предел размера файла темы, байт (64 КиБ): больше — `tooLarge`.
///
/// Почему: файл читается целиком в память и показывается в просмотре; предел
/// общий для разбора и адаптеров каталога (читают `themeFileMaxBytes + 1`).
const themeFileMaxBytes = 64 * 1024;

/// Допустимые значения `extends`: база, из которой берутся незаданные роли.
///
/// Почему: `auto` — выбор темы, а не набор цветов, `mono` нечем изобразить
/// в app (D2); поэтому набор закрыт. [jsonName] — значение в файле.
enum ThemeBase {
  light('light'),
  dark('dark'),
  highContrast('high-contrast');

  const ThemeBase(this.jsonName);

  final String jsonName;
}

/// Разобранная тема с полным набором ролей: не заданные файлом (или `default`,
/// или терминальный цвет, который app не применяет) — [DefaultColor].
///
/// Почему: потребителю нужен ответ на любую роль без проверки на `null`;
/// «из базы» — явное значение, а не отсутствие.
///
/// Как использовать: создаётся только разбором [ThemeFile.parse]; хост
/// заменяет [DefaultColor] ролью темы [base] своего режима.
final class ThemeFile {
  const ThemeFile({
    required this.name,
    required this.base,
    required this.roles,
  });

  /// Разбирает [text]; [fileName] — имя файла с `.json`, `null` — не сверять
  /// `name` с файлом (импорт, D9). Текст больше [themeFileMaxBytes] в UTF-8 —
  /// `tooLarge`.
  static ThemeParseResult parse(String? fileName, String text) {
    // Короткий путь: 3 байта на code unit — верхняя граница UTF-8.
    if (text.length * 3 > themeFileMaxBytes &&
        utf8.encode(text).length > themeFileMaxBytes) {
      return const ThemeRejected(
        ThemeIssue(ThemeIssueCode.tooLarge, line: 1, column: 1),
      );
    }
    return _ThemeParser(fileName, text).run();
  }

  /// То же для сырых байт: не UTF-8 — `notUtf8`.
  static ThemeParseResult parseBytes(String? fileName, List<int> bytes) {
    if (bytes.length > themeFileMaxBytes) {
      return const ThemeRejected(
        ThemeIssue(ThemeIssueCode.tooLarge, line: 1, column: 1),
      );
    }
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return const ThemeRejected(
        ThemeIssue(ThemeIssueCode.notUtf8, line: 1, column: 1),
      );
    }
    return _ThemeParser(fileName, text).run();
  }

  final String name;
  final ThemeBase base;

  /// Значения всех [ThemeRole.values].
  final Map<ThemeRole, ThemeColorValue> roles;
}

/// Результат разбора: тема ([ThemeLoaded]) либо отказ ([ThemeRejected]).
///
/// Почему: ошибка разбора — ожидаемый исход, а не исключение; «строгость»
/// решает потребитель (D2).
sealed class ThemeParseResult {
  const ThemeParseResult();
}

/// Тема загружена, возможно, с предупреждениями.
///
/// Как использовать: app применяет [theme] и показывает [warnings]; CLI
/// считает любое предупреждение ошибкой. [unsetRoles] — справка о ролях,
/// взятых из базы, не предупреждение.
final class ThemeLoaded extends ThemeParseResult {
  const ThemeLoaded(this.theme, this.warnings, this.unsetRoles);

  final ThemeFile theme;
  final List<ThemeIssue> warnings;

  /// Роли, которых файл не задал (справка, не предупреждение).
  final List<ThemeRole> unsetRoles;
}

/// Тема не загружается: клиент применяет запасную (у app — встроенную тему
/// режима, у CLI — `extends` файла или `dark`).
///
/// Как использовать: [issue] — единственная, первая по порядку проверок
/// ошибка с кодом и позицией; текст строит клиент.
final class ThemeRejected extends ThemeParseResult {
  const ThemeRejected(this.issue);

  final ThemeIssue issue;
}

/// Имена встроенных тем: файл с таким `name` не загружается (`reservedName`).
const _reservedNames = {'auto', 'dark', 'light', 'high-contrast', 'mono'};

final _namePattern = RegExp(r'^[a-z0-9-]{1,32}$');

/// Имя темы подходит под шаблон `[a-z0-9-]{1,32}` (spec `client-themes`).
///
/// Порты каталога проверяют им имя до обращения к файловой системе: путь
/// строится только из такого имени и не выходит за каталог тем.
bool isValidThemeName(String name) => _namePattern.hasMatch(name);

/// Расстояние редактирования Левенштейна — для подсказки `unknownKey`.
int _distance(String a, String b) {
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = [
        prev[j] + 1,
        cur[j - 1] + 1,
        prev[j - 1] + cost,
      ].reduce((x, y) => x < y ? x : y);
    }
    prev = cur;
  }
  return prev[b.length];
}

/// Подсказка: ближайший ключ области на расстоянии не больше 2 или `null`.
String? _hintFor(String key, Iterable<String> areaKeys) {
  String? best;
  var bestDistance = 3;
  for (final candidate in areaKeys) {
    final d = _distance(key, candidate);
    if (d < bestDistance) {
      best = candidate;
      bestDistance = d;
    }
  }
  return best;
}

/// Ошибка, прерывающая разбор: тема не загружается.
final class _Reject implements Exception {
  _Reject(this.issue);
  final ThemeIssue issue;
}

final class _ThemeParser {
  _ThemeParser(this._fileName, this._text);

  final String? _fileName;
  final String _text;
  final _warnings = <ThemeIssue>[];
  final _roles = <ThemeRole, ThemeColorValue>{
    for (final r in ThemeRole.values) r: const DefaultColor(),
  };

  ThemeParseResult run() {
    try {
      return _run();
    } on _Reject catch (e) {
      return ThemeRejected(e.issue);
    }
  }

  _Reject _reject(
    ThemeIssueCode code,
    JsonPosition at, {
    String? key,
    String? value,
  }) => _Reject(
    ThemeIssue(code, line: at.line, column: at.column, key: key, value: value),
  );

  ThemeParseResult _run() {
    final JsonNode root;
    try {
      root = parseJsonSpans(_text);
    } on FormatException catch (e) {
      final at = positionAtOffset(_text, e.offset ?? 0);
      throw _reject(ThemeIssueCode.invalidJson, at);
    } on JsonDepthException catch (e) {
      throw _reject(ThemeIssueCode.invalidJson, e.start);
    }
    if (root is! JsonObjectNode) {
      throw _reject(ThemeIssueCode.notAnObject, root.start);
    }

    final top = _effective(root, const {'name', 'extends', 'colors'}, null);

    final name = _name(root, top['name']);
    final base = _base(top['extends']);
    final colors = top['colors'];
    if (colors != null) _colors(colors);

    final unset = [
      for (final r in ThemeRole.values)
        if (_roles[r] is DefaultColor) r,
    ];
    return ThemeLoaded(
      ThemeFile(name: name, base: base, roles: Map.unmodifiable(_roles)),
      List.unmodifiable(_warnings),
      unset,
    );
  }

  /// Последние вхождения ключей объекта; повторы и неизвестные ключи дают
  /// предупреждения (`duplicateKey`, `unknownKey`). [prefix] — префикс ключа
  /// в проблемах (`code.`); [known] — допустимые ключи области.
  Map<String, JsonMember> _effective(
    JsonObjectNode node,
    Set<String> known,
    String? prefix, {
    Iterable<String>? hintKeys,
  }) {
    final result = <String, JsonMember>{};
    for (final m in node.members) {
      final shown = '${prefix ?? ''}${m.key}';
      if (result.containsKey(m.key)) {
        _warnings.add(
          ThemeIssue(
            ThemeIssueCode.duplicateKey,
            line: m.keyStart.line,
            column: m.keyStart.column,
            key: shown,
          ),
        );
      }
      if (!known.contains(m.key)) {
        // Подсказка только для областей с ролями: у верхнего уровня её нет.
        _warnings.add(
          ThemeIssue(
            ThemeIssueCode.unknownKey,
            line: m.keyStart.line,
            column: m.keyStart.column,
            key: m.key,
            hint: hintKeys == null ? null : _hintFor(m.key, hintKeys),
          ),
        );
        continue;
      }
      result[m.key] = m;
    }
    return {for (final e in result.entries) e.key: e.value};
  }

  String _name(JsonObjectNode root, JsonMember? member) {
    if (member == null) {
      throw _reject(ThemeIssueCode.missingName, root.start);
    }
    final node = member.value;
    final value = node is JsonScalarNode ? node.value : null;
    if (value is! String) {
      throw _reject(ThemeIssueCode.invalidName, node.start, key: 'name');
    }
    if (!isValidThemeName(value)) {
      throw _reject(
        ThemeIssueCode.invalidName,
        node.start,
        key: 'name',
        value: value,
      );
    }
    final file = _fileName;
    if (file != null) {
      final stem = file.endsWith('.json')
          ? file.substring(0, file.length - 5)
          : file;
      if (stem != value) {
        throw _reject(
          ThemeIssueCode.nameMismatch,
          node.start,
          key: 'name',
          value: value,
        );
      }
    }
    if (_reservedNames.contains(value)) {
      throw _reject(
        ThemeIssueCode.reservedName,
        node.start,
        key: 'name',
        value: value,
      );
    }
    return value;
  }

  ThemeBase _base(JsonMember? member) {
    if (member == null) return ThemeBase.dark;
    final node = member.value;
    final value = node is JsonScalarNode ? node.value : null;
    for (final b in ThemeBase.values) {
      if (b.jsonName == value) return b;
    }
    throw _reject(
      ThemeIssueCode.invalidExtends,
      node.start,
      key: 'extends',
      value: value is String ? value : null,
    );
  }

  void _colors(JsonMember member) {
    final node = member.value;
    if (node is! JsonObjectNode) {
      throw _reject(ThemeIssueCode.invalidValue, node.start, key: 'colors');
    }
    final plain = {
      for (final r in ThemeRole.values)
        if (!r.isCode) r.key: r,
    };
    final entries = _effective(
      node,
      {...plain.keys, 'code'},
      null,
      hintKeys: [...plain.keys, 'code'],
    );
    for (final e in entries.entries) {
      if (e.key == 'code') {
        _code(e.value);
      } else {
        _apply(plain[e.key]!, e.value, e.key);
      }
    }
  }

  void _code(JsonMember member) {
    final node = member.value;
    if (node is! JsonObjectNode) {
      throw _reject(ThemeIssueCode.invalidValue, node.start, key: 'code');
    }
    final code = {
      for (final r in ThemeRole.values)
        if (r.isCode) r.key: r,
    };
    final entries = _effective(
      node,
      code.keys.toSet(),
      'code.',
      hintKeys: code.keys,
    );
    for (final e in entries.entries) {
      _apply(code[e.key]!, e.value, 'code.${e.key}');
    }
  }

  /// Разбирает значение роли. Терминальный цвет (ANSI, `256:<n>`) формат
  /// допускает, но app его не применяет: предупреждение `terminalColor`,
  /// роль остаётся из `extends`.
  void _apply(ThemeRole role, JsonMember member, String shownKey) {
    final node = member.value;
    final raw = node is JsonScalarNode ? node.value : null;
    final parsed = raw is String ? ThemeColorValue.tryParse(raw) : null;
    if (parsed == null) {
      throw _reject(
        ThemeIssueCode.invalidValue,
        node.start,
        key: shownKey,
        value: raw is String ? raw : null,
      );
    }
    switch (parsed) {
      case Rgb():
        _roles[role] = parsed;
      case DefaultColor():
        break;
      case AnsiColor() || IndexedColor():
        _warnings.add(
          ThemeIssue(
            ThemeIssueCode.terminalColor,
            line: node.start.line,
            column: node.start.column,
            key: shownKey,
            value: raw as String,
          ),
        );
    }
  }
}
