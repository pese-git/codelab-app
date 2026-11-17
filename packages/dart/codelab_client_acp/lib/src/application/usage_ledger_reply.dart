/// Имя запроса журнала usage сессии (расширение CodeLab, change
/// `add-usage-ledger`, D6).
const usageLedgerMethod = '_codelab/session/usage/ledger';

/// Сырой ответ агента на `_codelab/session/usage/ledger`.
///
/// Почему: форма журнала (D6) разбирается одной реализацией в ядре клиента
/// (`UsageLedgerDecoder`, `codelab_client_core`, D10), а этот слой содержимое
/// не интерпретирует (D9; `codelab_client_core/AGENTS.md` §5).
///
/// Для чего: результат `AcpClientApplication.requestUsageLedger`.
/// [generation] — поколение соединения, на котором УШЁЛ запрос: потребитель
/// сравнивает его с текущим и отбрасывает ответ старого соединения
/// (`AGENTS.md` §9).
///
/// Как использовать: читать [result] как есть; не мутировать.
final class UsageLedgerReply {
  UsageLedgerReply({
    required Map<String, Object?> result,
    required this.generation,
  }) : result = Map.unmodifiable(result);

  /// Объект JSON из `result` ответа без разбора (неизменяемая копия).
  final Map<String, Object?> result;

  /// Поколение соединения на момент отправки запроса.
  final int generation;
}
