const redactedSecret = '<redacted>';

final _sensitiveKeyPattern = RegExp(
  r'(api[_-]?key|auth|authorization|bearer|cookie|credential|jwt|pass(word)?|private[_-]?key|secret|session|token)',
  caseSensitive: false,
);
final _authorizationPattern = RegExp(
  r'\b(Basic|Bearer|Digest|Token)\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);
final _assignmentSecretPattern = RegExp(
  r'([A-Za-z0-9_.-]*(?:api[_-]?key|cookie|credential|jwt|pass(?:word)?|private[_-]?key|secret|session|token)[A-Za-z0-9_.-]*\s*[:=]\s*)([^\s,;]+)',
  caseSensitive: false,
);
final _privateKeyPattern = RegExp(
  r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
);

final class SecretRedactor {
  const SecretRedactor();

  Object? redact(Object? value, {String? key}) {
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

  bool _isSensitiveKey(String? key) {
    return key != null && _sensitiveKeyPattern.hasMatch(key);
  }
}
