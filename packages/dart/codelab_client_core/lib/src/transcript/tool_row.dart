import 'package:codelab_acp_protocol/codelab_acp_protocol.dart';
import 'package:codelab_client_acp/codelab_client_acp.dart' show SecretRedactor;

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
/// быть пустой строкой, [secondary] — `null`.
final class ToolRowView {
  const ToolRowView({required this.label, this.detail = '', this.secondary});

  /// Метка по виду вызова: `Read`, `Edit`, `Run`… или `title` у `other`.
  final String label;

  /// Короткая деталь: путь, команда, шаблон поиска, адрес без query.
  final String detail;

  /// Причина ошибки у вызова в статусе `failed`; иначе `null`.
  final String? secondary;

  @override
  bool operator ==(Object other) =>
      other is ToolRowView &&
      other.label == label &&
      other.detail == detail &&
      other.secondary == secondary;

  @override
  int get hashCode => Object.hash(label, detail, secondary);

  @override
  String toString() => 'ToolRowView($label, $detail, $secondary)';
}

/// Строит [ToolRowView] по вызову инструмента.
///
/// Почему: правила метки и детали (§12.1.6) общие для всех клиентов и
/// должны жить в ядре клиента, а не повторяться в каждом UI.
///
/// Для чего: чистая функция без состояния и без времени; секреты в детали
/// маскируются [SecretRedactor], query-строка адреса отбрасывается.
///
/// Как использовать: `ToolRowFormatter.format(item, cwd: session.cwd)` —
/// [cwd] нужен, чтобы показать путь внутри проекта относительным.
abstract final class ToolRowFormatter {
  /// Предел длины детали; дальнейшее усечение под ширину — у клиента.
  static const maxDetailLength = 160;

  static const _redactor = SecretRedactor();

  static ToolRowView format(ToolCallItem item, {required String cwd}) {
    final view = item.details;
    final kind = view?.kind ?? ToolKind.other;
    final label = _labelOf(kind, item.title);
    var detail = _clean(_detailOf(kind, view, item.title, cwd: cwd));
    // Пустая или повторяющая метку деталь заменяется заголовком агента —
    // без повторного слова метки (§12.1.6, шаг 3).
    if ((detail.isEmpty || detail == label) && item.title.trim() != label) {
      detail = _clean(_withoutLeadingWord(item.title, label));
    }
    if (detail == label) {
      detail = '';
    }
    return ToolRowView(
      label: label,
      detail: detail,
      secondary: view?.status == ToolCallStatusView.failed
          ? _firstLine(view!.textOutput)
          : null,
    );
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
    ToolKind.other => title.trim().isEmpty ? 'Tool' : title.trim(),
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
        return url == null ? '' : _withoutSchemeAndQuery(url);
      case ToolKind.think:
        final agent = _string(input['agent']);
        final description = _string(input['description']);
        return switch ((agent, description)) {
          (final a?, final d?) => '$a: $d',
          (_, final d?) => d,
          _ => '',
        };
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

  /// Схема, query и фрагмент отбрасываются: query может нести секрет.
  static String _withoutSchemeAndQuery(String url) {
    final withoutScheme = url.replaceFirst(
      RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://'),
      '',
    );
    return withoutScheme.split(RegExp('[?#]')).first;
  }

  static String _withoutLeadingWord(String title, String label) {
    final trimmed = title.trim();
    final prefix = '${label.toLowerCase()} ';
    return trimmed.toLowerCase().startsWith(prefix)
        ? trimmed.substring(prefix.length)
        : trimmed;
  }

  /// Управляющие символы и ESC-последовательности — пробел, пробелы
  /// схлопываются, секреты маскируются, длина — не больше
  /// [maxDetailLength].
  static String _clean(String value) {
    final plain = value
        .replaceAll(RegExp(r'\x1B\[[0-9;?]*[ -/]*[@-~]'), ' ')
        .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final redacted = _redactor.redactText(plain);
    return redacted.length <= maxDetailLength
        ? redacted
        : '${redacted.substring(0, maxDetailLength - 1)}…';
  }

  static String? _firstLine(List<String> texts) {
    if (texts.isEmpty) {
      return null;
    }
    for (final line in texts.first.split('\n')) {
      if (line.trim().isNotEmpty) {
        return line.trim();
      }
    }
    return null;
  }
}
