import 'usage_ledger_models.dart';

/// Разбор ответа `_codelab/session/usage/ledger` версии 1 (change
/// `add-usage-ledger`, D6, D10).
///
/// ЗАГЛУШКА красных тестов 3.2: разбор — задача 3.9. Контракт тот же, что у
/// `UsageDecoder.decode`: без исключений; `null` — ответ отброшен (причина
/// уже в [onWarning]); на каждое неразобранное поле — вызов [onWarning] с
/// именем поля и короткой причиной, без сырого значения.
final class UsageLedgerDecoder {
  const UsageLedgerDecoder();

  UsageLedgerView? decode(
    Map<String, Object?> result, {
    required void Function(String field, String reason) onWarning,
  }) => throw UnimplementedError('add-usage-ledger, задача 3.9');
}
