import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart'
    show SecretRedactor, redactedSecret;

import 'subagent_views.dart';
import 'transcript_item.dart';

/// Строка вызова инструмента для отображения: метка, деталь, вторая строка.
///
/// Почему: клиентам нужна одна и та же короткая строка вызова — «Read
/// lib/a.dart», «Run npm test» — без сырого JSON `rawInput` и без имени вида
/// протокола (`dart-agent-and-clients` §12.1.6, VIEW-2).
///
/// Для чего: результат [ToolRowFormatter.format]; десктоп и CLI рисуют его
/// своими средствами. Времени вызова здесь нет — оно отложено (design D2
/// change `redesign-transcript-rows`).
///
/// Как использовать: строится форматтером по [ToolCallItem]; [detail] может
/// быть пустой строкой, [secondary] — `null`. Строка вызова `agent`
/// (`ToolCallView.subagentCall`, D28) дополнительно несёт [progress],
/// [report], [summary] и [summaryShort] (design.md change
/// `add-subagents-and-tasks`, D24, D27); у остальных вызовов они `null`.
final class ToolRowView {
  const ToolRowView({
    required this.label,
    this.detail = '',
    this.secondary,
    this.progress,
    this.report,
    this.summary,
    this.summaryShort,
    this.runningCounter,
  });

  /// Последняя строка прогресса, пока вызов `agent` идёт; иначе `null`.
  final String? progress;

  /// Текст отчёта субагента после завершения вызова (тело `content`);
  /// секреты маскируются, переводы строк сохраняются. Иначе `null`.
  final String? report;

  /// Строка итога `N tool calls · N.Nk tokens · <время>` из
  /// `subagentSummary`; `null` без итога.
  final String? summary;

  /// Сокращённый вид итога `N tool calls · N.Nk · <время>` (D27).
  final String? summaryShort;

  /// Счётчик работающего `agent` без токенов: `5 tool calls` / `1 tool call`
  /// (Q15, D25); формат как у [summaryShort]. `null` у завершённого вызова,
  /// у других вызовов и пока вызовов потомков нет. Хост показывает
  /// `summaryShort ?? runningCounter`.
  final String? runningCounter;

  /// Метка по виду вызова: `Read`, `Edit`, `Run`… или `title` у `other`;
  /// у `other` очищена и замаскирована, как деталь (D2 change
  /// `redact-tool-row-text`).
  final String label;

  /// Короткая деталь: путь, команда, шаблон поиска, адрес без query.
  final String detail;

  /// Причина ошибки у вызова в статусе `failed`; иначе `null`. Очищена,
  /// замаскирована и усечена до [ToolRowFormatter.maxDetailLength], как
  /// деталь (D1 change `redact-tool-row-text`); полный вывод — через
  /// [ToolRowFormatter.outputTail].
  final String? secondary;

  @override
  bool operator ==(Object other) =>
      other is ToolRowView &&
      other.label == label &&
      other.detail == detail &&
      other.secondary == secondary &&
      other.progress == progress &&
      other.report == report &&
      other.summary == summary &&
      other.summaryShort == summaryShort &&
      other.runningCounter == runningCounter;

  @override
  int get hashCode => Object.hash(
    label,
    detail,
    secondary,
    progress,
    report,
    summary,
    summaryShort,
    runningCounter,
  );

  @override
  String toString() =>
      'ToolRowView($label, $detail, $secondary, progress: $progress, '
      'report: $report, summary: $summary, summaryShort: $summaryShort, runningCounter: $runningCounter)';
}

/// Строит [ToolRowView] по вызову инструмента.
///
/// Почему: правила метки и детали (§12.1.6) общие для всех клиентов и
/// должны жить в ядре клиента, а не повторяться в каждом UI.
///
/// Для чего: чистая функция без состояния и без времени; секреты в детали
/// маскируются [SecretRedactor], у адреса `fetch` отбрасываются схема,
/// userinfo, query и фрагмент.
///
/// Как использовать: `ToolRowFormatter.format(item, cwd: session.cwd)` —
/// [cwd] нужен, чтобы показать путь внутри проекта относительным.
abstract final class ToolRowFormatter {
  /// Предел длины детали; дальнейшее усечение под ширину — у клиента.
  static const maxDetailLength = 160;

  static const _redactor = SecretRedactor();

  /// Хвост вывода вызова для раскрытой строки клиента: последние [maxLines]
  /// строк текстового вывода, замаскированные [SecretRedactor].
  ///
  /// Почему: хвост показывается под второй строкой ([ToolRowView.secondary])
  /// и раньше шёл сырым `textOutput`, то есть мимо маскировки (design.md
  /// change `redact-tool-row-text`, D7, VIEW-9). Решение о повторе со второй
  /// строкой принимается по очищенным значениям, а правило очистки `_clean`
  /// приватно в этом файле, поэтому и хвост строится здесь, а не в маппере
  /// или виджете.
  ///
  /// Для чего: число строк — параметр клиента (раскладка десктопа), поэтому
  /// это функция, а не поле [ToolRowView]; `format` за хвост не платит.
  /// Работа зависит от размера хвоста, а не от объёма вывода (D3: десктоп
  /// перестраивает ленту на каждый кадр): элементы обходятся с конца,
  /// внутри элемента строки ищутся `lastIndexOf('\n')` назад, и только
  /// хвост копируется `substring`. Переводы строк и пробелы сохраняются,
  /// меняются только маски.
  ///
  /// Граница хвоста и многострочные секреты: маскируется окно на одну строку
  /// больше хвоста ([maxLines] + 1), и только потом берутся последние
  /// [maxLines] строк результата. Так `Bearer` в конце строки границы и токен
  /// на следующей, или `password:` и значение под ним маскируются вместе.
  /// Маска может схлопнуть строки (PEM-блок целиком), поэтому строки
  /// отрезаются от уже замаскированного текста. Если в окне остался
  /// `-----END … PRIVATE KEY-----` без своего BEGIN (начало ключа выше окна),
  /// маскируется всё от начала окна до этой строки включительно; а если
  /// остался `BEGIN` без `END` (вывод оборван или ещё идёт), маскируется всё
  /// от него до конца окна, строки до него видны.
  ///
  /// Как использовать: `ToolRowFormatter.outputTail(call, maxLines: 20)`.
  /// `null` — показывать нечего: вывод пуст, это вызов `agent` (его тело —
  /// уже замаскированный `report`) либо весь вывод — одна строка, равная
  /// `secondary` и не усечённая до 160 символов; иначе вывод повторял бы её.
  /// Дедуп опирается на «одна строка в окне ⇒ весь вывод — эта строка».
  static String? outputTail(ToolCallItem item, {required int maxLines}) {
    final view = item.details;
    if (view == null || view.subagentCall != null || maxLines <= 0) {
      return null;
    }
    final window = _tailWindow(view.textOutput, maxLines + 1);
    if (window.isEmpty) {
      return null;
    }
    if (window.length == 1) {
      final secondary = _secondaryOf(view);
      if (secondary != null &&
          _cleanFull(window.single).length <= maxDetailLength &&
          _cleanFull(window.single) == secondary) {
        return null;
      }
    }
    var masked = _redactor.redactText(window.reversed.join('\n'));
    // Остаток `END` после `redactText` — осиротевший: полные пары уже
    // заменены. Прячем всё от начала окна до него (D7, остаток PEM).
    Match? orphan;
    for (final match in _privateKeyEnd.allMatches(masked)) {
      orphan = match;
    }
    if (orphan != null) {
      masked = '$redactedSecret${masked.substring(orphan.end)}';
    }
    // Остаток `BEGIN` — ключ без конца (`head -n 10 id_rsa`, поток ещё идёт):
    // всё от него до конца окна — тело ключа, строки до него остаются.
    final begin = _privateKeyBegin.firstMatch(masked);
    if (begin != null) {
      masked = '${masked.substring(0, begin.start)}$redactedSecret';
    }
    final lines = masked.split('\n');
    return lines.length <= maxLines
        ? masked
        : lines.sublist(lines.length - maxLines).join('\n');
  }

  static final _privateKeyBegin = RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----');
  static final _privateKeyEnd = RegExp(r'-----END [A-Z ]*PRIVATE KEY-----');

  /// До [limit] последних строк вывода в обратном порядке (последняя —
  /// первой); хвостовые пробельные символы всего вывода срезаны.
  ///
  /// Как у плитки десктопа: элементы склеены `\n`, пустой элемент посреди —
  /// пустая строка. Копируются только строки окна (D7).
  static List<String> _tailWindow(List<String> texts, int limit) {
    final lines = <String>[];
    for (var i = texts.length - 1; i >= 0; i--) {
      final text = texts[i];
      var end = text.length;
      if (lines.isEmpty) {
        while (end > 0 && _isTrimmedSpace(text.codeUnitAt(end - 1))) {
          end--;
        }
        if (end == 0) {
          continue;
        }
      }
      while (true) {
        final newline = end == 0 ? -1 : text.lastIndexOf('\n', end - 1);
        lines.add(text.substring(newline + 1, end));
        if (lines.length == limit) {
          return lines;
        }
        if (newline < 0) {
          break;
        }
        end = newline;
      }
    }
    return lines;
  }

  /// Пробельные символы `String.trimRight` (Unicode White_Space и BOM).
  static bool _isTrimmedSpace(int c) =>
      (c >= 0x09 && c <= 0x0D) ||
      c == 0x20 ||
      c == 0x85 ||
      c == 0xA0 ||
      c == 0x1680 ||
      (c >= 0x2000 && c <= 0x200A) ||
      c == 0x2028 ||
      c == 0x2029 ||
      c == 0x202F ||
      c == 0x205F ||
      c == 0x3000 ||
      c == 0xFEFF;

  static ToolRowView format(ToolCallItem item, {required String cwd}) {
    final view = item.details;
    if (view?.subagentCall case final call?) {
      return _agentRow(item, view!, call);
    }
    final kind = view?.kind ?? ToolKind.other;
    final label = _labelOf(kind, item.title);
    var detail = _clean(_detailOf(kind, view, item.title, cwd: cwd));
    // Пустая или повторяющая метку деталь заменяется заголовком агента —
    // без повторного слова метки (§12.1.6, шаг 3).
    // Сравниваются очищенные значения (D2): метка `other` уже очищена.
    if ((detail.isEmpty || detail == label) && _clean(item.title) != label) {
      detail = _clean(_withoutLeadingWord(item.title, label));
    }
    if (detail == label) {
      detail = '';
    }
    return ToolRowView(
      label: label,
      detail: detail,
      secondary: view == null ? null : _secondaryOf(view),
    );
  }

  /// Строка вызова `agent` (D28): заголовок `<type>: <description>` строится
  /// из структурированных полей, а не разбором `title`; описание — из
  /// `rawInput.description` (метка `Subagent`, деталь `<type>: <description>`).
  /// Без описания `title` показывается как есть целиком (метка — он сам,
  /// деталь пуста), без какой-либо проверки текста агента (D27, D33): тип при
  /// этом не дублируется, потому что `title` его уже несёт. Пустой `title` —
  /// метка `Subagent`, деталь `<type>`.
  static ToolRowView _agentRow(
    ToolCallItem item,
    ToolCallView view,
    SubagentCallView call,
  ) {
    final description = _string(view.rawInput?['description']);
    final title = item.title.trim();
    final byTitle = description == null && title.isNotEmpty;
    final running =
        view.status == ToolCallStatusView.queued ||
        view.status == ToolCallStatusView.running;
    final texts = [
      for (final text in view.textOutput)
        if (text.trim().isNotEmpty) text,
    ];
    return ToolRowView(
      label: byTitle ? _clean(title) : 'Subagent',
      detail: byTitle
          ? ''
          : _clean(
              description == null ? call.type : '${call.type}: $description',
            ),
      secondary: _secondaryOf(view),
      progress: running && texts.isNotEmpty ? _clean(texts.last) : null,
      report: !running && texts.isNotEmpty
          ? _redactor.redactText(texts.join('\n').trim())
          : null,
      summary: view.subagentSummary?.text,
      summaryShort: view.subagentSummary?.shortText,
      runningCounter: running && item.subtreeCalls > 0
          ? subagentCallsText(item.subtreeCalls)
          : null,
    );
  }

  static String _otherLabel(String title) {
    final cleaned = _clean(title);
    return cleaned.isEmpty ? 'Tool' : cleaned;
  }

  static String _labelOf(ToolKind kind, String title) => switch (kind) {
    ToolKind.read => 'Read',
    ToolKind.edit => 'Edit',
    ToolKind.delete => 'Delete',
    ToolKind.move => 'Move',
    ToolKind.search => 'Search',
    ToolKind.execute => 'Run',
    ToolKind.fetch => 'Fetch',
    ToolKind.think => 'Think',
    // Смена режима сессии (`switch_mode`, ACP `17-Schema.md`); wire-имя в
    // строку не попадает (D7 change `tolerate-unknown-tool-kind`).
    ToolKind.switchMode => 'Mode',
    // Заголовок вызова `other` — свободный текст агента (MCP, сторонний
    // агент, неизвестный вид), поэтому очищается как деталь (D2).
    ToolKind.other => _otherLabel(title),
  };

  static String _detailOf(
    ToolKind kind,
    ToolCallView? view,
    String title, {
    required String cwd,
  }) {
    final input = view?.rawInput ?? const <String, Object?>{};
    final paths = view?.paths ?? const <String>[];
    String? path() {
      final raw = paths.isNotEmpty ? paths.first : _string(input['path']);
      return raw == null ? null : _relative(raw, cwd);
    }

    switch (kind) {
      case ToolKind.execute:
        final command = input['command'];
        return switch (command) {
          String() => command,
          List() => command.whereType<String>().join(' '),
          // Без команды деталь берётся из `title` общим правилом ниже — без
          // повторного слова метки («Run build», а не «Run Run build»).
          _ => '',
        };
      case ToolKind.read:
        final base = path() ?? '';
        final offset = input['offset'];
        final limit = input['limit'];
        return base.isNotEmpty && offset is int && limit is int && limit > 0
            ? '$base:$offset-${offset + limit - 1}'
            : base;
      case ToolKind.edit || ToolKind.delete:
        final base = path() ?? '';
        return base.isNotEmpty && paths.length > 1
            ? '$base +${paths.length - 1}'
            : base;
      case ToolKind.move:
        final from = paths.isNotEmpty ? paths[0] : _string(input['source']);
        final to = paths.length > 1 ? paths[1] : _string(input['destination']);
        return from == null || to == null
            ? ''
            : '${_relative(from, cwd)} → ${_relative(to, cwd)}';
      case ToolKind.search:
        final pattern = _string(input['pattern']) ?? _string(input['query']);
        if (pattern == null) {
          return '';
        }
        final where = _string(input['path']);
        final glob = _string(input['glob']);
        return [
          '"$pattern"',
          if (where != null) ' in ${_relative(where, cwd)}',
          if (glob != null) ' ($glob)',
        ].join();
      case ToolKind.fetch:
        final url = _string(input['url']);
        return url == null ? '' : _hostAndPath(url);
      case ToolKind.think:
        final agent = _string(input['agent']);
        final description = _string(input['description']);
        return switch ((agent, description)) {
          (final a?, final d?) => '$a: $d',
          (_, final d?) => d,
          _ => '',
        };
      case ToolKind.switchMode:
        // Полей `rawInput` для `switch_mode` ACP не определяет, догадок об их
        // именах нет: деталь пуста, и общее правило §12.1.6 подставляет
        // `title` вызова (D7 change `tolerate-unknown-tool-kind`).
        return '';
      case ToolKind.other:
        for (final key in const [
          'command',
          'path',
          'file_path',
          'url',
          'query',
          'pattern',
          'description',
          'name',
        ]) {
          if (_string(input[key]) case final value?) {
            return value;
          }
        }
        return '';
    }
  }

  static String? _string(Object? value) =>
      value is String && value.trim().isNotEmpty ? value : null;

  /// Путь внутри [cwd] — относительно него; остальные — как есть.
  static String _relative(String path, String cwd) {
    final root = cwd.endsWith('/') ? cwd : '$cwd/';
    return cwd.isNotEmpty && path.startsWith(root)
        ? path.substring(root.length)
        : path;
  }

  /// Хост и путь адреса `fetch` — без схемы, userinfo, query и фрагмента.
  ///
  /// Почему: userinfo (`user:pass@`) и query несут учётные данные, а
  /// маскировка [SecretRedactor] узнаёт userinfo только по `://`, которого
  /// в детали уже нет. Поэтому учётные данные снимаются здесь, до
  /// маскировки, и не зависят от её правил (design.md change
  /// `strip-fetch-url-userinfo`, D1).
  ///
  /// Для чего: деталь строки `fetch` (§12.1.6, VIEW-9) — только куда идёт
  /// запрос.
  ///
  /// Как использовать: вызывает [ToolRowFormatter.format] для `rawInput.url`.
  /// Порядок D2 повторяет первые шаги парсера WHATWG, чтобы запись, которую
  /// внешний агент примет за адрес с userinfo, не прошла мимо:
  /// 1. удалить табы и переводы строк, обрезать пробелы (в том числе
  ///    юникодные и BOM) и управляющие символы по краям;
  /// 2. отрезать всё от `?`/`#` (там `@` не userinfo);
  /// 3. снять схему, если за ней идёт `/` или `\` (`localhost:8080` — не
  ///    схема), и все ведущие `/`, `\` и пробелы;
  /// 4. в authority (до первого `/`) отбросить всё по последний `@`
  ///    включительно, чтобы пароль с `@` не оставил хвоста. `\` границей не
  ///    считается: WHATWG видит в `https://h\a@b` путь, а RFC 3986 (Python,
  ///    `requests`) — userinfo `h\a`, и при расхождении показываем меньше.
  ///
  /// Только строки, без [Uri]: `user:pass@host` [Uri] принял бы за схему
  /// `user` (D1). `https://user:pass@example.com/x?t=1` → `example.com/x`;
  /// `//user:pass@host/x` → `host/x`; `https://example.com/a@b` — без
  /// изменений.
  static String _hostAndPath(String url) {
    final normalized = url
        .replaceAll(_tabOrNewline, '')
        .replaceAll(_edgeControlOrSpace, '');
    final withoutQuery = normalized.split(_queryOrFragment).first;
    final withoutScheme = withoutQuery.replaceFirst(_schemeAndSlashes, '');
    final slash = withoutScheme.indexOf('/');
    final authorityEnd = slash < 0 ? withoutScheme.length : slash;
    // Поиск только внутри authority: `@` в пути — часть пути, а не userinfo.
    final at = withoutScheme.substring(0, authorityEnd).lastIndexOf('@');
    return at < 0 ? withoutScheme : withoutScheme.substring(at + 1);
  }

  // Выражения [_hostAndPath] компилируются один раз, как в `SecretRedactor`.
  static final _tabOrNewline = RegExp('[\t\n\r]');
  // Одно выражение краёв, а не `trim()` плюс выражение: управляющие символы
  // вперемешку с юникодными пробелами срезаются за один проход.
  static final _edgeControlOrSpace = RegExp(
    r'^[\x00-\x20\s\uFEFF]+|[\x00-\x20\s\uFEFF]+$',
  );
  static final _queryOrFragment = RegExp('[?#]');
  static final _schemeAndSlashes = RegExp(
    r'^(?:[a-zA-Z][a-zA-Z0-9+.-]*:(?=[/\\]))?[/\\\s]*',
  );

  static String _withoutLeadingWord(String title, String label) {
    final trimmed = title.trim();
    final prefix = '${label.toLowerCase()} ';
    return trimmed.toLowerCase().startsWith(prefix)
        ? trimmed.substring(prefix.length)
        : trimmed;
  }

  /// Очищает текст агента для строки вызова: управляющие символы и
  /// ESC-последовательности — пробел, пробелы схлопываются, секреты
  /// маскируются, длина — не больше [maxDetailLength].
  ///
  /// Почему: одно правило для всех текстовых полей [ToolRowView] — детали,
  /// метки `other` и второй строки (design.md change `redact-tool-row-text`,
  /// D1, D2). Маскирование идёт до усечения: иначе усечение отрежет `@` у
  /// `https://user:pass@…` или `=` у присваивания, и видимая часть секрета
  /// пройдёт мимо шаблона.
  static String _clean(String value) {
    final redacted = _cleanFull(value);
    return redacted.length <= maxDetailLength
        ? redacted
        : '${redacted.substring(0, maxDetailLength - 1)}…';
  }

  /// [_clean] без усечения: нужен [outputTail], чтобы узнать, была ли строка
  /// длиннее предела (усечённая вторая строка от вывода отличается, D7).
  static String _cleanFull(String value) {
    final plain = value
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), ' ')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return _redactor.redactText(plain);
  }

  /// Вторая строка вызова: только у упавшего, иначе `null`. Единое правило
  /// для [format], строки `agent` и дедупа [outputTail] (§14).
  static String? _secondaryOf(ToolCallView view) =>
      view.status == ToolCallStatusView.failed
      ? _firstLine(view.textOutput)
      : null;

  /// Вторая строка: первая строка первого текстового элемента, непустая
  /// **после** очистки; `null`, если такой нет (D3).
  ///
  /// Почему выбор до очистки, а очистка одной строки: `format` вызывается на
  /// каждый кадр, и маскировать весь вывод каждого упавшего вызова — работа
  /// O(объём вывода) в UI isolate (§12). Строка из одних ESC-последовательностей
  /// пропускается, а не даёт пустую вторую строку.
  static String? _firstLine(List<String> texts) {
    if (texts.isEmpty) {
      return null;
    }
    for (final line in texts.first.split('\n')) {
      final cleaned = _clean(line);
      if (cleaned.isNotEmpty) {
        return cleaned;
      }
    }
    return null;
  }
}
