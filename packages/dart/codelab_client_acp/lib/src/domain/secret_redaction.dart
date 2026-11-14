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
final _assignmentSecretPattern = RegExp(
  r'([A-Za-z0-9_.-]*(?:api[_-]?key|cookie|credential|jwt|pass(?:word)?|private[_-]?key|secret|session[_-]?(?:token|cookie|secret|key)|token)[A-Za-z0-9_.-]*\s*[:=]\s*)([^\s,;]+)',
  caseSensitive: false,
);
final _privateKeyPattern = RegExp(
  r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
);

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
      Map() => {
        for (final entry in value.entries)
          entry.key.toString(): redact(entry.value, key: entry.key.toString()),
      },
      Iterable() => [for (final item in value) redact(item)],
      _ => redactText(value.toString()),
    };
  }

  Map<String, Object?> redactMap(Map<String, Object?> value) {
    return {
      for (final entry in value.entries)
        entry.key: redact(entry.value, key: entry.key),
    };
  }

  String redactText(String value) {
    return value
        .replaceAll(_privateKeyPattern, redactedSecret)
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
