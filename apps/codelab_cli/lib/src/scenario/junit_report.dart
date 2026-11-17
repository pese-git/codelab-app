/// Результат одной фикстуры для JUnit-отчёта `codelab test-scenario --junit`.
///
/// Почему отдельный тип: запись отчёта — чистая функция без IO и без пакета
/// `xml` (design.md change `switch-default-agent-to-dart`, D8), поэтому ей
/// нужны только id, время и причина, а не внутренний итог драйвера.
///
/// Как использовать: [failure] и [skipped] — взаимоисключающие; обе `null` —
/// фикстура прошла (`PASS`). Тексты берутся из тех же строк, что stdout, а
/// значения аргументов stdio-профиля в них не попадают (D16).
final class JunitCase {
  const JunitCase({
    required this.id,
    required this.seconds,
    this.failure,
    this.skipped,
  }) : assert(failure == null || skipped == null);

  /// Id фикстуры, например `acp/prompt-streaming-text`.
  final String id;

  /// Время фикстуры в секундах.
  final double seconds;

  /// Причина и дифф `FAIL` целиком (многострочный текст).
  final String? failure;

  /// Причина `SKIP`.
  final String? skipped;
}

/// Рисует JUnit XML прогона (spec cli-scenario-driver «JUnit-отчёт
/// test-scenario»; D8).
///
/// Для чего: машинный отчёт для проверки доказательств матрицы целей
/// (`parity`): порядок `testcase` — порядок [cases] (как строки stdout), а
/// атрибуты `testsuite` совпадают с итоговой строкой драйвера.
///
/// Как использовать: вызывается один раз после последней фикстуры, [seconds]
/// — время всего прогона. Пустой [cases] даёт `testsuite` с `tests="0"`.
String renderJunitReport(List<JunitCase> cases, {required double seconds}) {
  final failures = cases.where((c) => c.failure != null).length;
  final skipped = cases.where((c) => c.skipped != null).length;
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<testsuites>')
    ..writeln(
      '<testsuite name="codelab test-scenario" tests="${cases.length}" '
      'failures="$failures" skipped="$skipped" time="${_time(seconds)}">',
    );
  for (final c in cases) {
    final head =
        '<testcase classname="${_classname(c.id)}" name="${_attr(c.id)}" '
        'time="${_time(c.seconds)}"';
    if (c.failure case final failure?) {
      out
        ..write('$head><failure message="${_attr(_firstLine(failure))}">')
        ..write(_text(failure))
        ..writeln('</failure></testcase>');
    } else if (c.skipped case final reason?) {
      out.writeln('$head><skipped message="${_attr(reason)}"/></testcase>');
    } else {
      out.writeln('$head/>');
    }
  }
  out
    ..writeln('</testsuite>')
    ..writeln('</testsuites>');
  return out.toString();
}

/// Группа фикстуры — часть id до первого `/` (`acp/x` → `acp`).
String _classname(String id) {
  final slash = id.indexOf('/');
  return _attr(slash < 0 ? id : id.substring(0, slash));
}

String _firstLine(String text) {
  final newline = text.indexOf('\n');
  return newline < 0 ? text : text.substring(0, newline);
}

/// Секунды без хвоста `.0` у целых (`0`, `1.5`), с точностью до миллисекунд.
String _time(double seconds) {
  final rounded = (seconds * 1000).round() / 1000;
  return rounded == rounded.truncateToDouble()
      ? rounded.toInt().toString()
      : rounded.toString();
}

String _attr(String value) => _escape(value, attribute: true);

String _text(String value) => _escape(value, attribute: false);

/// Экранирует `& < > " '` и заменяет символы, недопустимые в XML 1.0
/// (всё, кроме `\t \n \r`, `U+0020–U+D7FF`, `U+E000–U+FFFD`, `U+10000+`),
/// на `U+FFFD`. В значениях атрибутов `\t \n \r` пишутся ссылками: иначе
/// парсер XML нормализовал бы их в пробелы.
String _escape(String value, {required bool attribute}) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    switch (rune) {
      case 0x26:
        out.write('&amp;');
      case 0x3C:
        out.write('&lt;');
      case 0x3E:
        out.write('&gt;');
      case 0x22:
        out.write('&quot;');
      case 0x27:
        out.write('&apos;');
      case 0x09 || 0x0A || 0x0D:
        out.write(attribute ? '&#$rune;' : String.fromCharCode(rune));
      case _ when _isXmlChar(rune):
        out.writeCharCode(rune);
      default:
        out.write('\u{FFFD}');
    }
  }
  return out.toString();
}

bool _isXmlChar(int rune) =>
    (rune >= 0x20 && rune <= 0xD7FF) ||
    (rune >= 0xE000 && rune <= 0xFFFD) ||
    (rune >= 0x10000 && rune <= 0x10FFFF);
