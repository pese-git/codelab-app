/// Распознавание литеральных секретов в конфиге (CFG-9, пункты 1–3;
/// design.md change `add-config-literal-secrets-and-migrate`, D3).
///
/// Почему в ядре и в одном файле: находки нужны загрузке (предупреждение
/// `config.secret.in_file`, D4), писателю и маскированию вывода в
/// `codelab_agent_io` и будущему `secret migrate` (D5, D7). Две копии
/// шаблонов разошлись бы: загрузка предупредила бы о значении, которое запись
/// приняла бы молча, или наоборот. Правило пакета — `AGENTS.md` §5.
///
/// Для чего: [literalSecretTag] отвечает «похоже ли значение на секрет» и
/// возвращает короткую метку формата, [findInlineSecrets] обходит слой
/// конфига и возвращает находки с путём ключа, видом и участками. Ни метка,
/// ни находка не содержат значения или его части (CFG-2): их безопасно
/// печатать и писать в лог.
///
/// Источник шаблонов — таблица `agent-core-architecture` §12.4 («Шаблоны
/// известных форматов»), которую пишет CodeLab по публичным описаниям
/// форматов токенов (префиксы `sk-`, `ghp_`, `AKIA`, `AIza`, `xox…`, JWT,
/// PEM). Правила gitleaks, detect-secrets и trufflehog не копировались
/// (`AGENTS.md` §5); `THIRD_PARTY_NOTICES.md` не требуется.
///
/// Как использовать: `literalSecretTag(value) != null` — значение содержит
/// литеральный секрет. Подстановки `${…}` не считаются литералом: значение
/// режется по ним, и `Bearer ${secret:x}` проходит, а
/// `Bearer ghp_… ${X}` — нет. `findInlineSecrets(layer)` вызывают по слою
/// конфига: загрузка — по файловым слоям после правил доверия, писатель и
/// мигратор — по разобранному файлу.
library;

import '../secrets/secret_names.dart';
import 'config_issue.dart' show inlineSecretKeys;
import 'config_tree.dart';
import 'key_path.dart';

/// Вид находки CFG-9 (design.md change `add-config-literal-secrets-and-migrate`,
/// D3, D7): от него зависит, что делают с находкой загрузка и мигратор.
enum InlineSecretKind {
  /// Пункт 1: значение лежит в ключе из `inlineSecretKeys`
  /// (`providers.<id>.api_key`, `mcp.servers[x].token`). Участков нет —
  /// секрет весь лист.
  inlineKey,

  /// Пункт 2: литеральная часть значения `headers`/`env` по шаблону §12.4,
  /// в том числе смешанного `Bearer ghp_… ${X}`. Участки — секретные места
  /// значения.
  literalPart,

  /// Пункт 3: в `api_key_env`/`api_key_secret` вписан сам ключ вместо имени.
  /// Участков нет — секрет весь лист.
  nameLiteral,

  /// Пункт 3: в `${secret:<литерал>}` вписан сам ключ вместо имени секрета.
  /// Участок — литерал внутри скобок (без обёртки `${secret:` и `}`), чтобы
  /// замена на имя давала `${secret:<name>}`.
  referenceName,
}

/// Одна находка литерального секрета.
///
/// Почему без значения: находку печатают предупреждение, `config check` и
/// отчёт мигратора. [keyPath] называет место, [tag] — формат, [spans] — где
/// в значении секрет (для замены на ссылку); сам секрет читают по месту из
/// слоя, а не из находки.
final class InlineSecretFinding {
  const InlineSecretFinding({
    required this.keyPath,
    required this.kind,
    required this.tag,
    required this.suggestedSecretName,
    this.spans = const [],
    this.spansTruncated = false,
  });

  /// Путь ключа в формате `KeyPath`: `providers.lm.api_key`,
  /// `mcp.servers[gh].headers.Authorization`.
  final String keyPath;
  final InlineSecretKind kind;

  /// Метка формата (`sk`, `github`, `connection-string`, …) или `inline-key`
  /// для [InlineSecretKind.inlineKey]. Короткая и не зависит от значения.
  final String tag;

  /// Имя для подсказки `codelab secret set <name>`: `SecretNames.suggestFor`
  /// от [keyPath]. Проходит `SecretNames.problem`.
  final String suggestedSecretName;

  /// Участки секрета в значении как полуинтервалы `[начало, конец)` по
  /// кодовым единицам UTF-16, по возрастанию и без пересечений. Пусто, когда
  /// секрет — весь лист ([InlineSecretKind.inlineKey],
  /// [InlineSecretKind.nameLiteral]).
  final List<(int, int)> spans;

  /// Участков больше [_maxSpans]: список обрезан. Значение с десятками тысяч
  /// секретов — не конфиг человека, а враждебный ввод; обрезка держит поиск
  /// линейным.
  final bool spansTruncated;

  @override
  String toString() => 'InlineSecretFinding($keyPath, ${kind.name}, $tag)';
}

/// Метка первого совпавшего шаблона §12.4 в литеральных частях [value] либо
/// `null`, если литерала нет.
///
/// Порядок проверки — порядок таблицы §12.4 (`sk`, `github`, `aws`, `google`,
/// `slack`, `jwt`, `bearer`, `private-key`, `assignment`,
/// `connection-string`), поэтому у `Bearer ghp_…` метка `github`.
/// Встроенный белый список (`git_sha`, `uuid`, §12.4.1) отсекает участок,
/// который целиком совпал с записью: `API_KEY=<40 hex>` секретом не считается.
///
/// [asName] — [value] служит именем (переменной, секрета, `api_key_env`,
/// `api_key_secret`): `sk-` засчитывается только в начале значения, иначе имя
/// `codelab/sk-anthropic-production-key` стало бы «секретом» и ссылка не
/// разрешалась бы (L3).
///
/// Работает за время, линейное по длине значения: части имени «присваивания»
/// ограничены, JWT и PEM ищутся однопроходными поисками (`indexOf` от якоря:
/// `.eyJ`, заголовок `BEGIN`), а не регулярными выражениями с перебором от
/// каждой позиции — иначе враждебное значение дало бы квадратичный перебор.
String? literalSecretTag(String value, {bool asName = false}) {
  final matches = _scan(value, firstOnly: true, asName: asName).matches;
  return matches.isEmpty ? null : matches.first.pattern.tag;
}

/// Находки CFG-9, пункты 1–3, в одном слое конфига.
///
/// Обходит `providers.<id>` и элементы `mcp.servers`:
/// - ключи `inlineSecretKeys` с непустым значением — [InlineSecretKind.inlineKey];
/// - `api_key_env`, `api_key_secret` с литералом по шаблону —
///   [InlineSecretKind.nameLiteral];
/// - `api_key` провайдера, не ссылка (без `${…}`), — [InlineSecretKind.inlineKey];
///   со ссылкой (R8-8) — только находки её литеральных частей и токена вместо
///   имени, как у значений `headers`;
/// - значения `headers` провайдера, `headers` и `env` сервера — литеральные
///   части ([InlineSecretKind.literalPart]) и литералы в `${secret:…}`
///   ([InlineSecretKind.referenceName]).
///
/// Находки считаются по слою независимо от `enabled` элемента и от того,
/// перекрыт ли ключ слоем выше (D4). `url`, `base_url` и `args` не
/// проверяются: пароль в userinfo `url` не переносится (L5), а `args`
/// загрузка не проверяет (OQ3). Порядок — как в файле.
List<InlineSecretFinding> findInlineSecrets(ConfigTree layer) {
  final out = <InlineSecretFinding>[];
  final providers = layer.values['providers'];
  if (providers is Map<String, Object?>) {
    for (final MapEntry(key: id, value: body) in providers.entries) {
      if (body is Map<String, Object?>) {
        _provider(KeyPath('providers').child(id), body, out);
      }
    }
  }
  final mcp = layer.values['mcp'];
  final servers = mcp is Map<String, Object?> ? mcp['servers'] : null;
  if (servers is List<Object?>) {
    for (var i = 0; i < servers.length; i++) {
      final element = servers[i];
      if (element is! Map<String, Object?>) {
        continue;
      }
      final name = element['name'];
      _server(
        KeyPath('mcp.servers').at(name is String && name.isNotEmpty ? name : i),
        element,
        out,
      );
    }
  }
  return out;
}

void _provider(
  KeyPath at,
  Map<String, Object?> body,
  List<InlineSecretFinding> out,
) {
  for (final MapEntry(key: field, value: value) in body.entries) {
    final path = at.child(field);
    if (field == 'api_key' &&
        value is String &&
        _substitution.hasMatch(value)) {
      // R8-4/R8-8: `api_key: ${VAR}` и `${secret:x}` — ссылка, не литерал;
      // находки только у литеральных частей и у токена, вписанного вместо
      // имени.
      out.addAll(valueFindings(path, value));
    } else if (inlineSecretKeys.contains(field)) {
      _inlineKey(path, value, out);
    } else if ((field == 'api_key_env' || field == 'api_key_secret') &&
        value is String) {
      final tag = literalSecretTag(value, asName: true);
      if (tag != null) {
        out.add(_finding(path, InlineSecretKind.nameLiteral, tag));
      }
    } else if (field == 'headers' && value is Map<String, Object?>) {
      _stringMap(path, value, out);
    }
  }
}

void _server(
  KeyPath at,
  Map<String, Object?> element,
  List<InlineSecretFinding> out,
) {
  for (final MapEntry(key: field, value: value) in element.entries) {
    final path = at.child(field);
    if (inlineSecretKeys.contains(field)) {
      _inlineKey(path, value, out);
    } else if ((field == 'headers' || field == 'env') &&
        value is Map<String, Object?>) {
      _stringMap(path, value, out);
    }
  }
}

void _inlineKey(KeyPath path, Object? value, List<InlineSecretFinding> out) {
  // Пустая строка и `null` — не секрет: ключ задан, но значения нет.
  if (value == null || (value is String && value.isEmpty)) {
    return;
  }
  out.add(_finding(path, InlineSecretKind.inlineKey, 'inline-key'));
}

void _stringMap(
  KeyPath at,
  Map<String, Object?> map,
  List<InlineSecretFinding> out,
) {
  for (final MapEntry(key: name, value: value) in map.entries) {
    if (value is String) {
      out.addAll(valueFindings(at.child(name), value));
    }
  }
}

InlineSecretFinding _finding(
  KeyPath path,
  InlineSecretKind kind,
  String tag, {
  List<(int, int)> spans = const [],
  bool truncated = false,
}) => InlineSecretFinding(
  spansTruncated: truncated,
  keyPath: path.value,
  kind: kind,
  tag: tag,
  suggestedSecretName: SecretNames.suggestFor(path.value),
  spans: spans,
);

/// Находки одного строкового значения `headers`/`env` (и ссылочного
/// `api_key`) с ключом [path]: литеральные части и токены, вписанные вместо
/// имени в `${secret:…}` или `${NAME}`.
///
/// Внутренняя функция пакета (в публичный барель не входит): ею пользуются
/// [findInlineSecrets], [hasInlineSecret] и план перезагрузки. Наружу идёт
/// узкий предикат [hasInlineSecret].
/// Есть ли в строковом значении литеральный секрет: литеральная часть по
/// шаблону §12.4 либо токен, вписанный вместо имени в `${secret:…}` или
/// `${NAME}`. Ссылки без литералов (`${KEY}`, `Bearer ${secret:codelab/p}`)
/// секретом не считаются.
///
/// Почему отдельный предикат: маскеру `config get` и плану перезагрузки нужен
/// ответ «да/нет», а подробные находки ([valueFindings]) остаются
/// внутренностью распознавания.
bool hasInlineSecret(String value) =>
    valueFindings(KeyPath.root.child('x'), value).isNotEmpty;

List<InlineSecretFinding> valueFindings(KeyPath path, String value) {
  final out = <InlineSecretFinding>[];
  final scan = _scan(value);
  if (scan.matches.isNotEmpty) {
    final chosen = [...scan.matches]
      ..sort((a, b) => a.start.compareTo(b.start));
    out.add(
      _finding(
        path,
        InlineSecretKind.literalPart,
        // Метка — у совпадения с высшим приоритетом (первый шаблон таблицы).
        scan.matches.first.pattern.tag,
        spans: [for (final m in chosen) (m.start, m.end)],
        truncated: scan.truncated,
      ),
    );
  }
  final references = <(int, int)>[];
  String? firstTag;
  for (final match in [
    ..._secretReference.allMatches(value).map((m) => (m, 9)),
    ..._variableReference.allMatches(value).map((m) => (m, 2)),
  ]) {
    final (m, prefix) = match;
    final name = m.group(1)!;
    final tag = literalSecretTag(name, asName: true);
    if (tag != null) {
      firstTag ??= tag;
      references.add((m.start + prefix, m.start + prefix + name.length));
    }
  }
  references.sort((a, b) => a.$1.compareTo(b.$1));
  if (references.isNotEmpty) {
    out.add(
      _finding(
        path,
        InlineSecretKind.referenceName,
        firstTag!,
        spans: references,
      ),
    );
  }
  return out;
}

// ---- шаблоны §12.4 ---------------------------------------------------------

/// Подстановка `${…}`: `${VAR}` или `${secret:name}`. Тело без `$` и `}` и
/// не длиннее 200 символов: без границы строка из `${` дала бы квадратичный
/// перебор.
final _substitution = RegExp(r'\$\{[^}$]{0,200}\}');

/// `${NAME}` — имя переменной окружения; префикс `${` — 2 символа.
final _variableReference = RegExp(r'\$\{([A-Za-z_][A-Za-z0-9_]{0,199})\}');

/// `${secret:<name>}`; префикс `${secret:` — 9 символов (смещение участка).
final _secretReference = RegExp(r'\$\{secret:([^}$]{1,200})\}');

/// Шаблон: метка, выражение и номер группы, где лежит секрет (0 — всё
/// совпадение). Группа нужна белому списку и участкам: у `Bearer …` секрет —
/// токен без префикса, у присваивания — значение без имени.
final class _Pattern {
  const _Pattern(this.tag, this.regex, {this.group = 0, this.tail})
    : finder = null;

  /// Шаблон, который регулярное выражение не потянуло бы без квадратичного
  /// перебора: участки ищет [finder] за один проход.
  const _Pattern.custom(
    this.tag,
    Iterable<(int, int)> Function(String) this.finder,
  ) : regex = null,
      group = 0,
      tail = null;

  final String tag;
  final RegExp? regex;
  final Iterable<(int, int)> Function(String text)? finder;
  final int group;

  /// Группа, текст которой стоит после секрета до конца совпадения
  /// (закрывающая кавычка присваивания); `null` — секрет в конце.
  final int? tail;
}

/// Таблица §12.4 в порядке приоритета. `caseSensitive: false` заменяет
/// `(?i)`, которого в Dart нет. Верхние границы `{0,64}`, `{8,256}`, `{0,32}`
/// и `\s{0,16}` — защита от квадратичного перебора (см. [literalSecretTag]);
/// секретная группа каждого шаблона остаётся без верхней границы, поэтому
/// участок покрывает секрет целиком.
final _patterns = <_Pattern>[
  _Pattern('sk', RegExp(r'\bsk-(?:ant-|proj-)?[A-Za-z0-9_\-]{20,}')),
  _Pattern(
    'github',
    RegExp(r'\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{60,})'),
  ),
  _Pattern('aws', RegExp(r'\b(?:AKIA|ASIA)[0-9A-Z]{16}\b')),
  _Pattern('google', RegExp(r'\bAIza[0-9A-Za-z_\-]{35}\b')),
  _Pattern('slack', RegExp(r'\bxox[abposr]-[A-Za-z0-9\-]{10,}')),
  _Pattern.custom('jwt', _jwtSpans),
  _Pattern(
    'bearer',
    RegExp(r'\bbearer\s+([A-Za-z0-9._~+/\-]{12,}=*)', caseSensitive: false),
    group: 1,
  ),
  _Pattern.custom('private-key', _pemSpans),
  _Pattern(
    'assignment',
    RegExp(
      r'\b[A-Z0-9_]{0,64}(?:API_?KEY|TOKEN|SECRET|PASSWORD)[A-Z0-9_]{0,64}'
      r'\s{0,16}[:=]\s{0,16}(["\x27]?)([^\s"\x27]{8,})\1',
      caseSensitive: false,
    ),
    group: 2,
    tail: 1,
  ),
];

/// URL с паролем (слой `connection_strings`): ищется по всему значению, а не
/// по литеральным частям, чтобы увидеть пароль, разрезанный подстановкой
/// (`u:lit${X}@h`, L5). Пароль из одних подстановок секретом не считается.
/// Схема не длиннее 32 символов: без границы `[a-z0-9+.\-]*` на `eyJ-eyJ-…`
/// съедает остаток значения от каждого начала (квадратичный перебор).
final _urlWithPassword = RegExp(
  r'\b[a-z][a-z0-9+.\-]{0,31}://[^/\s:@]+:([^@\s/]+)@',
  caseSensitive: false,
);

/// Встроенный белый список `git_sha`, `uuid` (§12.4.1): участок, который
/// **целиком** совпал с записью, секретом не считается.
final _allowlist = <RegExp>[
  RegExp(r'^(?:[0-9a-f]{40}|[0-9a-f]{64})$'),
  RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$',
  ),
];

bool _allowlisted(String secret) => _allowlist.any((r) => r.hasMatch(secret));

/// Участки секрета шаблона [pattern] в [text] (смещения внутри [text]).
Iterable<(int, int)> _secretSpans(_Pattern pattern, String text) sync* {
  final finder = pattern.finder;
  if (finder != null) {
    yield* finder(text);
    return;
  }
  for (final m in pattern.regex!.allMatches(text)) {
    final secret = m.group(pattern.group)!;
    // `Match` не знает начала группы: секрет стоит в конце совпадения, за ним
    // может идти только закрывающая кавычка (`tail`).
    final tail = pattern.tail == null ? 0 : m.group(pattern.tail!)!.length;
    final end = m.end - tail;
    yield (end - secret.length, end);
  }
}

final _pemHeader = RegExp(r'-----BEGIN [A-Z ]{0,32}PRIVATE KEY-----');

/// Блок PEM: от заголовка `BEGIN … PRIVATE KEY` до `END … PRIVATE KEY-----`,
/// без `END` — до конца значения. Участок должен покрывать тело ключа, иначе
/// `secret migrate` оставил бы его в файле. Поиск конца — `indexOf` после
/// заголовка, а следующий заголовок ищется после найденного конца, поэтому
/// разбор линеен: без `END` первый же участок съедает остаток значения.
Iterable<(int, int)> _pemSpans(String text) sync* {
  var from = 0;
  while (from < text.length) {
    final header = _pemHeader.allMatches(text, from).firstOrNull;
    if (header == null) {
      return;
    }
    var end = text.length;
    final endMarker = text.indexOf('-----END ', header.end);
    if (endMarker >= 0) {
      final close = text.indexOf('PRIVATE KEY-----', endMarker);
      if (close >= 0) {
        end = close + 'PRIVATE KEY-----'.length;
      }
    }
    yield (header.start, end);
    from = end;
  }
}

bool _tokenChar(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    c == 0x5F ||
    c == 0x2D;

bool _wordChar(int c) => _tokenChar(c) && c != 0x2D;

/// JWT `eyJ<8+>.eyJ<8+>.<8+>` (символы `[A-Za-z0-9_-]`, заголовок до 256).
///
/// Почему не регулярное выражение: первый сегмент без точки может тянуться
/// до конца значения, и на `eyJ-eyJ-…` перебор по каждому началу квадратичен
/// (измерено: 1 МиБ — минуты). Здесь якорем служит `.eyJ`, а каждый сегмент
/// проходится не более раза, поэтому разбор линеен.
Iterable<(int, int)> _jwtSpans(String text) sync* {
  var from = 0;
  while (true) {
    final dot = text.indexOf('.eyJ', from);
    if (dot < 0) {
      return;
    }
    from = dot + 4;
    // Заголовок: максимальный отрезок класса символов, оканчивающийся точкой,
    // не длиннее 259 (`eyJ` + 256).
    var begin = dot;
    while (begin > 0 &&
        dot - begin < 259 &&
        _tokenChar(text.codeUnitAt(begin - 1))) {
      begin--;
    }
    var start = -1;
    for (var p = begin; p + 11 <= dot; p++) {
      if (text.startsWith('eyJ', p) &&
          (p == 0 || !_wordChar(text.codeUnitAt(p - 1)))) {
        start = p;
        break;
      }
    }
    if (start < 0) {
      continue;
    }
    var q = dot + 4;
    while (q < text.length && _tokenChar(text.codeUnitAt(q))) {
      q++;
    }
    if (q - (dot + 4) < 8 || q >= text.length || text[q] != '.') {
      continue;
    }
    var r = q + 1;
    while (r < text.length && _tokenChar(text.codeUnitAt(r))) {
      r++;
    }
    if (r - (q + 1) < 8) {
      continue;
    }
    yield (start, r);
    from = r;
  }
}

/// Совпадение шаблона: участок секрета `[start, end)` в исходном значении.
final class _Match {
  const _Match(this.pattern, this.start, this.end);

  final _Pattern pattern;
  final int start, end;
}

/// Больше участков в одном значении не собирается ([InlineSecretFinding.
/// spansTruncated]): проверка пересечений идёт по выбранным, и без границы
/// 50 тысяч совпадений дали бы квадрат.
const _maxSpans = 64;

typedef _Scan = ({List<_Match> matches, bool truncated});

final _urlPattern = _Pattern('connection-string', _urlWithPassword, group: 1);

/// Совпадения шаблонов в [value] по приоритету таблицы, без пересечений.
///
/// [firstOnly] — остановиться на первом найденном (для [literalSecretTag]).
/// Иначе возвращаются все участки; список упорядочен по приоритету шаблона,
/// затем по началу, участок с меньшим приоритетом, пересёкшийся с уже
/// выбранным, отбрасывается (`Bearer ghp_…` даёт один участок `github`).
_Scan _scan(String value, {bool firstOnly = false, bool asName = false}) {
  if (value.isEmpty) {
    return (matches: const [], truncated: false);
  }
  // Литеральные части между подстановками: `Bearer ${secret:x}` даёт часть
  // `Bearer `, и шаблоны порознь её не принимают.
  final parts = <(int, String)>[];
  var cursor = 0;
  for (final m in _substitution.allMatches(value)) {
    if (m.start > cursor) {
      parts.add((cursor, value.substring(cursor, m.start)));
    }
    cursor = m.end;
  }
  if (cursor < value.length) {
    parts.add((cursor, value.substring(cursor)));
  }

  final chosen = <_Match>[];
  bool free(int start, int end) =>
      chosen.every((c) => end <= c.start || start >= c.end);

  for (final pattern in _patterns) {
    for (final (offset, text) in parts) {
      for (final (from, to) in _secretSpans(pattern, text)) {
        if (_allowlisted(text.substring(from, to))) {
          continue;
        }
        final start = offset + from, end = offset + to;
        // Имя: `sk-` не в начале — часть слова (`codelab/sk-…`), не ключ (L3).
        if (asName && pattern.tag == 'sk' && start != 0) {
          continue;
        }
        if (free(start, end)) {
          if (chosen.length >= _maxSpans) {
            return (matches: chosen, truncated: true);
          }
          chosen.add(_Match(pattern, start, end));
          if (firstOnly) {
            return (matches: chosen, truncated: false);
          }
        }
      }
    }
  }

  for (final m in _urlWithPassword.allMatches(value)) {
    final password = m.group(1)!;
    final base = m.start + m.group(0)!.length - 1 - password.length;
    // Литеральные куски пароля: подстановки из них вырезаны.
    var from = 0;
    final chunks = <(int, int)>[];
    for (final s in _substitution.allMatches(password)) {
      if (s.start > from) {
        chunks.add((base + from, base + s.start));
      }
      from = s.end;
    }
    if (from < password.length) {
      chunks.add((base + from, base + password.length));
    }
    if (chunks.isEmpty) {
      continue;
    }
    for (final (start, end) in chunks) {
      if (free(start, end)) {
        if (chosen.length >= _maxSpans) {
          return (matches: chosen, truncated: true);
        }
        chosen.add(_Match(_urlPattern, start, end));
        if (firstOnly) {
          return (matches: chosen, truncated: false);
        }
      }
    }
  }
  return (matches: chosen, truncated: false);
}
