const redactedSecret = '<redacted>';

// `session` alone is intentionally NOT a bare alternative here — ACP's
// `sessionId`/`session_id` is a plain correlation identifier
// (`docs/architecture/observability.md` §4), not a secret, and this
// pattern is used to redact values wholesale. Only session keys shaped
// like an actual credential (session_token, sessionCookie, ...) match.
final _sensitiveKeyPattern = RegExp(
  r'(api[_-]?key|auth|authorization|bearer|cookie|credential|jwt|pass(word)?|private[_-]?key|secret|session[_-]?(?:token|cookie|secret|key)|token)',
  caseSensitive: false,
);

/// Имя счётчика токенов LLM: `tokens`, `tokens_in`, `input_tokens`.
///
/// Почему: статистика расхода (`tokens_in: 900`) — не секрет, а общее
/// правило «`token` в имени» скрывало её (design.md D41 п. 7, дельта
/// approval-safety «Редактирование секретов»).
///
/// Как применять: только к значению типа `num` и только если имя после
/// вырезания части `tokens` не подпадает под правила секретных имён
/// (`secret_tokens`, `tokens_api_key`, `auth_tokens` остаются скрытыми) и
/// не содержит стоп-слов учётных данных (`access`, `refresh`, `id`, `csrf`,
/// `otp`, `pin`, `session`) как целого сегмента, разделённого `_`/`-` (любое
/// число разделителей). Почему: `access_tokens`, `id_tokens`, `session__tokens`
/// — множественное число учётных данных, а не статистика; сегмент целый,
/// поэтому `input_tokens` и `ids` не задеваются.
final _tokenCounterKeyPattern = RegExp(
  r'^(?:tokens(?:[_-].*)?|.*[_-]tokens)$',
  caseSensitive: false,
);
final _tokensPartPattern = RegExp(
  r'(^|[_-])tokens([_-]|$)',
  caseSensitive: false,
);
final _credentialStopWords = {
  'access',
  'refresh',
  'id',
  'csrf',
  'otp',
  'pin',
  'session',
};
final _authorizationPattern = RegExp(
  r'\b(Basic|Bearer|Digest|Token)\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);
// Начало совпадения — само секретное слово, без ведущего `[A-Za-z0-9_.-]*`:
// ведущий префикс не влияет на результат (замена сохраняет `group(1)` как есть,
// а текст перед совпадением остаётся нетронутым), но заставлял движок на
// каждой позиции длинной строки без разделителей (base64, содержимое файла)
// сканировать её до конца — минуты на 40 тыс. символов (design.md change
// `redesign-protocol-pane`, D3: payload кадров маскируется до 256 KiB).
final _assignmentSecretPattern = RegExp(
  r'((?:api[_-]?key|cookie|credential|jwt|pass(?:word)?|private[_-]?key|secret|session[_-]?(?:token|cookie|secret|key)|token)[A-Za-z0-9_.-]{0,64}\s*[:=]\s*)([^\s,;]+)',
  caseSensitive: false,
);
// Границы блока ключа ищутся двумя отдельными шаблонами, а не одним с ленивым
// `[\s\S]*?`: на повторах `-----BEGIN … PRIVATE KEY-----` без `END` один
// шаблон перебирал хвост от каждого BEGIN — квадратичное время (ревью change
// `redesign-protocol-pane`). Хвост имени после секретного слова выше ограничен
// 64 символами по той же причине.
final _privateKeyBegin = RegExp(r'-----BEGIN [A-Z ]{0,40}PRIVATE KEY-----');
final _privateKeyEnd = RegExp(r'-----END [A-Z ]{0,40}PRIVATE KEY-----');

/// Заменяет блоки `BEGIN … END PRIVATE KEY` на [redactedSecret] за линейное
/// время; BEGIN без END остаётся как есть (как и у прежнего одного шаблона).
String _redactPrivateKeyBlocks(String text) {
  final out = StringBuffer();
  var cursor = 0;
  for (final begin in _privateKeyBegin.allMatches(text)) {
    if (begin.start < cursor) continue;
    // Поиск от позиции без копирования хвоста: `substring` на каждом BEGIN
    // давал квадратичное копирование на тексте из множества блоков.
    final end = _privateKeyEnd.allMatches(text, begin.end).firstOrNull;
    if (end == null) {
      // Дальше END нет ни у одного BEGIN: перебирать остальные не нужно.
      break;
    }
    out
      ..write(text.substring(cursor, begin.start))
      ..write(redactedSecret);
    cursor = end.end;
  }
  out.write(text.substring(cursor));
  return out.toString();
}

final class SecretRedactor {
  const SecretRedactor();

  Object? redact(Object? value, {String? key}) {
    // Узкое исключение (design.md D41 п. 7, approval-safety «Редактирование
    // секретов»): ЧИСЛО под именем-счётчиком — это статистика, а не секрет.
    // Строки под тем же именем и любые значения под `token`/`access_token`
    // скрываются как прежде.
    if (value is num && key != null && _isTokenCounterKey(key)) {
      return value;
    }
    if (_isSensitiveKey(key)) {
      return redactedSecret;
    }

    return switch (value) {
      null || num() || bool() => value,
      String() => redactText(value),
      Map() => _redactMap(value),
      Iterable() => [for (final item in value) redact(item)],
      _ => redactText(value.toString()),
    };
  }

  /// Маскирует объект; пара `{name, value}` с секретным `name` теряет `value`.
  ///
  /// Почему: `HttpHeader` и `EnvVariable` ACP (`17-Schema.md`) несут секрет
  /// не под ключом, а в значении `value` при секретном `name`
  /// (`Authorization`, `GITHUB_TOKEN`); правило по ключу этого не видит
  /// (design.md change `redesign-protocol-pane`, D4; approval-safety «Секрет в
  /// паре name/value»).
  ///
  /// Как работает: расширение того же правила имён (`_sensitiveKeyPattern` с
  /// исключением счётчиков токенов), отдельного набора правил нет. `name`
  /// остаётся как есть, прочие поля объекта обрабатываются прежними правилами.
  Map<String, Object?> _redactMap(Map<Object?, Object?> value) {
    final name = value['name'];
    final secretPair =
        name is String &&
        value.containsKey('value') &&
        _isSensitiveKey(name) &&
        // Исключение счётчиков токенов то же, что у правила по ключу: числовое
        // значение под именем-счётчиком — статистика.
        !(value['value'] is num && _isTokenCounterKey(name));
    return {
      for (final entry in value.entries)
        entry.key.toString(): secretPair && entry.key == 'value'
            ? redactedSecret
            : redact(entry.value, key: entry.key.toString()),
    };
  }

  Map<String, Object?> redactMap(Map<String, Object?> value) {
    return {
      for (final entry in value.entries)
        entry.key: redact(entry.value, key: entry.key),
    };
  }

  String redactText(String value) {
    return _redactPrivateKeyBlocks(value)
        .replaceAllMapped(_authorizationPattern, (match) {
          return '${match.group(1)} $redactedSecret';
        })
        .replaceAllMapped(_assignmentSecretPattern, (match) {
          return '${match.group(1)}$redactedSecret';
        });
  }

  /// Имя-счётчик без секретного слова вне части `tokens`.
  bool _isTokenCounterKey(String key) {
    if (!_tokenCounterKeyPattern.hasMatch(key)) return false;
    final rest = key.replaceFirst(_tokensPartPattern, '_');
    if (_isSensitiveKey(rest)) return false;
    final segments = rest.toLowerCase().split(RegExp(r'[_-]+'));
    return !segments.any(_credentialStopWords.contains);
  }

  bool _isSensitiveKey(String? key) {
    return key != null && _sensitiveKeyPattern.hasMatch(key);
  }
}
