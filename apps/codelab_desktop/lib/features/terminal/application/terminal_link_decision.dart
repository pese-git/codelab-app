/// Решение по адресу ссылки OSC 8: можно ли предлагать его открыть.
///
/// Почему: адрес приходит из вывода процесса и недоверенный; решение «опасно
/// ли» принадлежит application, а не виджету (`AGENTS.md` §10; D3 «Ссылки
/// OSC 8», Q14).
///
/// Для чего: диалог показывает кнопку «Open» только при [canOpen]; [scheme]
/// идёт в события `terminal.link_*` вместо адреса (D9).
///
/// Как использовать: `terminalLinkDecision(uri)`.
final class TerminalLinkDecision {
  const TerminalLinkDecision({required this.canOpen, required this.scheme});

  /// `true` — схема `http` или `https`.
  final bool canOpen;

  /// Схема в нижнем регистре; `null`, если адрес не разобрался.
  final String? scheme;
}

/// Разбирает [uri] (`Uri.tryParse`) и разрешает только `http`/`https` без
/// учёта регистра; прочие схемы, пустой и неразбираемый адрес отклоняются.
TerminalLinkDecision terminalLinkDecision(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) {
    return const TerminalLinkDecision(canOpen: false, scheme: null);
  }
  final scheme = parsed.scheme.toLowerCase();
  return TerminalLinkDecision(
    canOpen: scheme == 'http' || scheme == 'https',
    scheme: scheme,
  );
}
