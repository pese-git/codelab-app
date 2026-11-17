import 'dart:math';

import 'package:codelab_setup/codelab_setup.dart';

import '../../render/sanitize.dart';
import '../../setup/settings_access.dart';
import 'frame.dart';
import 'tui_overlay.dart';

/// Строка клавиш экрана настроек (артборд `CliSettings`).
const settingsKeyBar =
    '↑↓ move · enter edit · ←→ choose · tab section · r reset · esc close';

/// Строки модального экрана [overlay] по ширине [width] и высоте [rows]
/// терминала (без статус-строки). Все тексты проходят `sanitizeTerminalText`
/// (TUI-11); значение ключа — только маска `*` (кроме показа по Ctrl+R).
///
/// Почему отдельная функция без модели: высота экрана нужна и кадру, и
/// расчёту окна транскрипта, а `TuiModel` не должен зависеть от рендера.
List<String> overlayLinesOf(
  TuiOverlay overlay, {
  required int width,
  required int rows,
}) {
  final lines = switch (overlay) {
    ProviderWizardOverlay() => _wizardLines(overlay),
    SettingsOverlay() => _settingsLines(overlay, width, rows - 1),
    PickerOverlay() => const <String>[],
  };
  final limit = max(0, rows - 1);
  return lines.length > limit ? lines.sublist(0, limit) : lines;
}

/// Строка и столбец курсора в [overlayLinesOf] или `null`.
(int, int)? overlayCursorOf(TuiOverlay overlay) {
  if (overlay is! ProviderWizardOverlay) {
    return null;
  }
  final mode = overlay.mode;
  if (mode is! WizardInput) {
    return null;
  }
  final lines = _wizardLines(overlay);
  final column = displayWidth(
    sanitizeTerminalText('${mode.def.prompt}${mode.field.shown}'),
  );
  return (lines.length - 1, column);
}

// --- мастер ---------------------------------------------------------------

List<String> _wizardLines(ProviderWizardOverlay overlay) {
  final step = overlay.step;
  final out = <String>[
    for (final note in step.notes) sanitizeTerminalText(note),
    if (overlay.message case final message?) sanitizeTerminalText(message),
  ];
  switch (overlay.mode) {
    case WizardWaiting() || WizardSaving():
      if (step.progress case final progress?) {
        out.add(sanitizeTerminalText(progress));
      }
    case WizardPick(:final selected):
      out.add('? ${sanitizeTerminalText(step.title ?? '')}');
      for (final (i, option) in step.options.indexed) {
        out.add(
          '${i == selected ? '  › ' : '    '}'
          '${sanitizeTerminalText(option.label)}',
        );
      }
    case final WizardFilter filter:
      out.add(
        '? Model (type to filter) › ${sanitizeTerminalText(filter.filter.text)}',
      );
      final rows = filter.rows;
      final cursor = filter.cursor.clamp(0, rows.length - 1);
      final start = (cursor - WizardFilter.window + 1).clamp(0, rows.length);
      final end = min(start + WizardFilter.window, rows.length);
      for (var i = start; i < end; i++) {
        out.add(
          '${i == cursor ? '  › ' : '    '}${sanitizeTerminalText(rows[i])}',
        );
      }
    case WizardInput(:final def, :final field):
      out.add(sanitizeTerminalText('${def.prompt}${field.shown}'));
  }
  return out;
}

// --- настройки ------------------------------------------------------------

List<String> _settingsLines(SettingsOverlay overlay, int width, int rows) {
  final user = overlay.snapshot?.layers[ConfigLayer.user]?.path ?? '';
  final project =
      overlay.snapshot?.layers[ConfigLayer.projectLocal]?.path ??
      overlay.snapshot?.layers[ConfigLayer.project]?.path ??
      '';
  final out = <String>[
    sanitizeTerminalText(
      'Settings · /settings · user $user · project $project'.trimRight(),
    ),
    '',
  ];
  final access = overlay.access;
  if (readOnlyLineOf(access) case final line?) {
    out.add(sanitizeTerminalText(line));
    return out;
  }
  const sectionWidth = 14;
  final sectionRows = overlay.sectionRows;
  // Низ экрана: пустая строка, подсказка (может переноситься) и полоса клавиш;
  // шапка и заголовок таблицы — сверху. Остаток отдан таблице: строки
  // прокручиваются окном вокруг выбранной (как список моделей мастера), а
  // шапка, подсказка и полоса клавиш не обрезаются.
  final footer = switch (overlay.mode) {
    SettingsTable() => wrapLine(sanitizeTerminalText(overlay.hint), width),
    SettingsSaving() => const ['Saving…'],
    _ => const [''],
  };
  final tableHeight = max(1, rows - (out.length + 1) - 1 - footer.length - 1);
  out.add('${''.padRight(sectionWidth + 3)}  key · value · source');
  final int selected = overlay.row.clamp(0, max(0, sectionRows.length - 1));
  final rowStart = _windowStart(selected, sectionRows.length, tableHeight);
  final sectionStart = _windowStart(
    overlay.section,
    overlay.sections.length,
    tableHeight,
  );
  final height = max(
    min(overlay.sections.length - sectionStart, tableHeight),
    min(sectionRows.length - rowStart, tableHeight),
  );
  for (var i = 0; i < height; i++) {
    final s = sectionStart + i;
    final r = rowStart + i;
    final left = s < overlay.sections.length
        ? '${s == overlay.section ? '› ' : '  '}${overlay.sections[s]}'
        : '';
    var right = '';
    if (r < sectionRows.length) {
      final row = sectionRows[r];
      final restart = row.restartRequired ? ' (applies after restart)' : '';
      right =
          '${r == selected ? '› ' : '  '}${row.key}  ${row.displayValue}  '
          '${row.sourceName}$restart';
    }
    out.add(
      sanitizeTerminalText(
        '${left.padRight(sectionWidth)} │ $right'.trimRight(),
      ),
    );
  }
  out.add('');
  switch (overlay.mode) {
    case SettingsEdit(:final field):
      out.add(
        sanitizeTerminalText(
          '${overlay.selected?.key ?? ''} › ${field.shown}  '
          '(enter save · ctrl+u save to user · esc cancel)',
        ),
      );
    case SettingsChoose(:final values, :final index):
      out.add(
        sanitizeTerminalText(
          '${overlay.selected?.key ?? ''} ‹ ${values[index]} ›  '
          '(enter save · ctrl+u save to user · esc cancel)',
        ),
      );
    case SettingsTable() || SettingsSaving():
      out.addAll(footer);
  }
  out.add(settingsKeyBar);
  return out;
}

/// Первая видимая строка окна высотой [height] вокруг [selected] из [total].
int _windowStart(int selected, int total, int height) {
  if (total <= height) {
    return 0;
  }
  final start = selected - height + 1;
  return start < 0 ? 0 : min(start, total - height);
}
