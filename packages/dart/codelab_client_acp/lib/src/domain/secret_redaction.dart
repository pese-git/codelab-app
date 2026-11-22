/// Значение, которым `SecretRedactor` заменяет скрытый секрет.
const redactedSecret = '<redacted>';

/// Секретные слова в имени ключа map (регистр не важен).
///
/// Почему `session` не стоит отдельной альтернативой: ACP `sessionId` /
/// `session_id` — обычный корреляционный идентификатор
/// (`docs/architecture/observability.md` §4), а не секрет, и шаблон скрывает
/// значение целиком. Совпадают только ключи, похожие на учётные данные
/// (`session_token`, `sessionCookie`, ...).
///
/// Признаки `key` (`OPENAI_KEY`, `openaiKey`, `AWS_ACCESS_KEY_ID`) сюда не
/// входят: им нужны конец имени и регистр, их проверяет `_isKeyLikeName`
/// (design change `extend-secret-name-redaction`, D1).
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

/// Слова учётных данных, из-за которых число под именем с `tokens` не счётчик.
///
/// Включая `key` (D2 change `extend-secret-name-redaction`): `key_tokens: 1`
/// и `tokens_key: 1` называют ключ, а не расход, поэтому скрываются. Сегмент
/// сравнивается целиком: `monkey_tokens: 5` остаётся видимым счётчиком.
final _credentialStopWords = {
  'key',
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

/// Признаки секретного имени с `key` (D1 change `extend-secret-name-redaction`,
/// требование spec `approval-safety` «Редактирование секретов»).
///
/// Почему три отдельных шаблона: camelCase-признак регистрозависим (иначе
/// `monkey` и `turnkey` совпали бы), остальные — нет, а флагов внутри одного
/// выражения Dart не поддерживает.
final _keySuffixPattern = RegExp(r'[_-]key$', caseSensitive: false);
final _accessKeyPattern = RegExp(r'access[_-]?key', caseSensitive: false);
final _camelKeySuffixPattern = RegExp(r'[a-z0-9]Key$');

/// Слова секретного имени в тексте-присваивании (без `auth`, `authorization`,
/// `bearer`: иначе `author: Bob` начал бы скрываться, а заголовок
/// авторизации уже закрывает `_authorizationPattern`).
final _assignmentWordPattern = RegExp(
  r'api[_-]?key|cookie|credential|jwt|pass(?:word)?|private[_-]?key|secret|session[_-]?(?:token|cookie|secret|key)|token',
  caseSensitive: false,
);

/// Имя с разделителем `=`/`:` в тексте (D3 change
/// `extend-secret-name-redaction`).
///
/// Почему так: lookbehind начинает совпадение только в начале непрерывной
/// последовательности символов имени, а проверка имени вынесена в код
/// (`_isSecretAssignmentName`). Прежний шаблон со словами внутри и хвостом
/// `[A-Za-z0-9_.-]*` давал квадратичное время на повторах слова и не мог
/// выразить регистрозависимый признак и конец имени. Здесь попытка внутри
/// последовательности отсекается за O(1), а в её начале — один проход, поэтому
/// время линейно по длине текста (D5).
final _assignmentNamePattern = RegExp(
  r'(?<![A-Za-z0-9_.-])([A-Za-z0-9_.-]+)\s*[:=]\s*',
);

/// Значение секретного присваивания: до пробела, запятой или `;`.
final _assignmentValuePattern = RegExp(r'[^\s,;]+');

/// Учётные данные адреса (userinfo): всё между `://` и последним `@`
/// авторитета (D4 change `extend-secret-name-redaction`).
///
/// Граница — первый `/`, `?`, `#`, пробел или символ, недопустимый в URI без
/// кодирования: адрес в JSON-строке не захватывает соседний текст, а пароль с
/// `@` скрывается целиком (жадный квантификатор). Совпадение начинается только
/// с литерала `://`, поэтому время линейно (D5).
final _urlUserinfoPattern = RegExp(r'://[^/?#\s"<>\\`]*@');

final _privateKeyPattern = RegExp(
  r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
);

/// Скрывает секреты в значениях, которые попадают в журналы и диагностику.
///
/// Почему: журнал и снимок диагностики пользователь прикладывает к
/// баг-репорту, поэтому безопасность выше наблюдаемости (`AGENTS.md` §2).
///
/// Для чего: единый редактор клиентской стороны — по имени ключа map
/// (`redact`, `redactMap`) и по тексту (`redactText`: PEM-блок, заголовок
/// авторизации, учётные данные адреса, присваивания `имя=значение`). Правила
/// описаны в spec `approval-safety` «Редактирование секретов» и в design.md
/// change `extend-secret-name-redaction` (D1–D5).
///
/// Как использовать: `const SecretRedactor()`, состояния нет. Публичный API
/// не менялся при расширении правил имён.
final class SecretRedactor {
  const SecretRedactor();

  /// Возвращает копию [value] со скрытыми секретами; [key] — имя поля map,
  /// под которым лежит значение (имя секретное — значение скрывается целиком).
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
      Map() => {
        for (final entry in value.entries)
          entry.key.toString(): redact(entry.value, key: entry.key.toString()),
      },
      Iterable() => [for (final item in value) redact(item)],
      _ => redactText(value.toString()),
    };
  }

  /// То же, что [redact], для map верхнего уровня.
  Map<String, Object?> redactMap(Map<String, Object?> value) {
    return {
      for (final entry in value.entries)
        entry.key: redact(entry.value, key: entry.key),
    };
  }

  /// Скрывает секреты внутри текста.
  ///
  /// Порядок важен: PEM-блок и заголовок авторизации, затем userinfo адреса
  /// (до присваиваний, чтобы работало и под несекретным именем вроде
  /// `DATABASE_URL`, D4), затем присваивания `имя=значение` (D3). Каждое
  /// правило работает за линейное время (D5).
  String redactText(String value) {
    final withoutUserinfo = value
        .replaceAll(_privateKeyPattern, redactedSecret)
        .replaceAllMapped(_authorizationPattern, (match) {
          return '${match.group(1)} $redactedSecret';
        })
        .replaceAll(_urlUserinfoPattern, '://$redactedSecret@');
    return _redactAssignments(withoutUserinfo);
  }

  /// Один проход по присваиваниям (D3).
  ///
  /// Совпадения внутри уже скрытого значения пропускаются; для несекретного
  /// имени проход продолжается сразу после разделителя, поэтому вложенное
  /// `url=https://h/x?access_token=abc` по-прежнему скрывается.
  String _redactAssignments(String text) {
    StringBuffer? out;
    var copied = 0; // до этого индекса text уже перенесён в out
    var skipUntil = 0; // конец последнего скрытого значения
    for (final match in _assignmentNamePattern.allMatches(text)) {
      if (match.start < skipUntil) continue;
      if (!_isSecretAssignmentName(match.group(1)!)) continue;
      final valueMatch = _assignmentValuePattern.matchAsPrefix(text, match.end);
      if (valueMatch == null) continue;
      (out ??= StringBuffer())
        ..write(text.substring(copied, match.end))
        ..write(redactedSecret);
      copied = skipUntil = valueMatch.end;
    }
    if (out == null) return text;
    return (out..write(text.substring(copied))).toString();
  }

  /// Имя-счётчик без секретного слова и стоп-слова вне части `tokens`.
  bool _isTokenCounterKey(String key) {
    if (!_tokenCounterKeyPattern.hasMatch(key)) return false;
    final rest = key.replaceFirst(_tokensPartPattern, '_');
    if (_isSensitiveKey(rest)) return false;
    final segments = rest.toLowerCase().split(RegExp(r'[_-]+'));
    return !segments.any(_credentialStopWords.contains);
  }

  /// Секретное имя ключа: секретное слово или признак `key` (D1).
  bool _isSensitiveKey(String? key) {
    return key != null &&
        (_sensitiveKeyPattern.hasMatch(key) || _isKeyLikeName(key));
  }

  /// Имя, похожее на ключ: последний сегмент `key`, `access_key` или
  /// camelCase `…Key` (D1).
  ///
  /// Голое `key`, `keyboard`, `monkey`, `key_count`, `KEY_ID` секретными не
  /// считаются; `cache_key` и `hotKey` скрываются осознанно (цена правила,
  /// Q4). Общий список признаков для имён map и для текста (D3).
  bool _isKeyLikeName(String name) {
    return _keySuffixPattern.hasMatch(name) ||
        _accessKeyPattern.hasMatch(name) ||
        _camelKeySuffixPattern.hasMatch(name);
  }

  /// Секретное имя в тексте-присваивании: слова текста или признак `key`.
  bool _isSecretAssignmentName(String name) {
    return _assignmentWordPattern.hasMatch(name) || _isKeyLikeName(name);
  }
}
