/// Поверхность вывода REPL.
///
/// Почему: один и тот же ход печатается в терминал с цветом, в терминал без
/// цвета и в pipe, где stdout — данные для скриптов (§12.2.1; spec
/// codelab-cli «Поверхности вывода»). `tui` в MVP нет (design.md change
/// `add-codelab-cli`, D6).
///
/// Для чего: [raw] — ответ байт в байт, без ANSI, без мыслей, строки
/// инструментов в stderr; [plain] — без SGR; [ansi] — с атрибутами.
enum OutputSurface { raw, plain, ansi }

/// Выбирает поверхность один раз при старте по первому подходящему условию
/// §12.2.1: stdout не TTY → [OutputSurface.raw]; `TERM=dumb`, непустой
/// `NO_COLOR` или `--no-color` ([noColor]) → [OutputSurface.plain]; иначе
/// [OutputSurface.ansi].
OutputSurface selectOutputSurface({
  required bool stdoutIsTerminal,
  required Map<String, String> environment,
  bool noColor = false,
}) {
  if (!stdoutIsTerminal) {
    return OutputSurface.raw;
  }
  if (environment['TERM'] == 'dumb' ||
      (environment['NO_COLOR'] ?? '').isNotEmpty ||
      noColor) {
    return OutputSurface.plain;
  }
  return OutputSurface.ansi;
}

/// Понимает ли терминал UTF-8: решает первая непустая переменная из
/// `LC_ALL`, `LC_CTYPE`, `LANG` (порядок POSIX). Без локали терминал
/// считается ASCII — значки инструментов заменяются ASCII (§12.2.4).
bool supportsUnicode(Map<String, String> environment) {
  for (final name in const ['LC_ALL', 'LC_CTYPE', 'LANG']) {
    final value = environment[name];
    if (value != null && value.isNotEmpty) {
      final lower = value.toLowerCase();
      return lower.contains('utf-8') || lower.contains('utf8');
    }
  }
  return false;
}
