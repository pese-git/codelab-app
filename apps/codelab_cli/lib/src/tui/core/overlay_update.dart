import 'dart:convert';

import 'package:codelab_setup/codelab_setup.dart';

import '../../input/key_decoder.dart';
import '../../setup/line_field.dart';
import '../../setup/settings_rows.dart';
import '../../setup/wizard_steps.dart';
import 'tui_cmd.dart';
import 'tui_model.dart';
import 'tui_overlay.dart';

/// Клавиша под модальным экраном (design.md change `add-provider-setup-ui`,
/// D17): её получает только он — до зоны одобрения и композера.
(TuiModel, List<TuiCmd>) overlayKey(
  TuiModel model,
  TuiOverlay overlay,
  KeyEvent event,
) => switch (overlay) {
  ProviderWizardOverlay() => _wizardKey(model, overlay, event),
  SettingsOverlay() => _settingsKey(model, overlay, event),
  PickerOverlay() => (model, const []),
};

/// Вставка под модальным экраном: в поле (мастера или правки значения).
(TuiModel, List<TuiCmd>) overlayPaste(
  TuiModel model,
  TuiOverlay overlay,
  String text,
) {
  switch (overlay) {
    case ProviderWizardOverlay(:final mode) when mode is WizardInput:
      return _wizardField(model, overlay, mode, mode.field.pasted(text));
    case ProviderWizardOverlay(:final mode) when mode is WizardFilter:
      return (
        model.copyWith(
          overlay: () => overlay.copyWith(
            mode: mode.copyWith(filter: mode.filter.pasted(text), cursor: 0),
          ),
        ),
        const [],
      );
    case SettingsOverlay(:final mode) when mode is SettingsEdit:
      return (
        model.copyWith(
          overlay: () =>
              overlay.copyWith(mode: SettingsEdit(mode.field.pasted(text))),
        ),
        const [],
      );
    default:
      return (model, const []);
  }
}

// --- мастер ---------------------------------------------------------------

TuiModel _setWizard(TuiModel model, ProviderWizardOverlay overlay) =>
    model.copyWith(overlay: () => overlay);

(TuiModel, List<TuiCmd>) _wizardKey(
  TuiModel model,
  ProviderWizardOverlay overlay,
  KeyEvent event,
) {
  final mode = overlay.mode;
  // Запись идёт: Esc и Ctrl+C блокированы, остальное не нужно (D21).
  if (mode is WizardSaving) {
    return (model, const []);
  }
  if (event case SpecialKey(key: Key.ctrlC || Key.escape)) {
    return _cancel(model, overlay);
  }
  switch (mode) {
    case WizardWaiting() || WizardSaving():
      return (model, const []);
    case final WizardPick pick:
      return _pickKey(model, overlay, pick, event);
    case final WizardFilter filter:
      return _filterKey(model, overlay, filter, event);
    case final WizardInput input:
      return _inputKey(model, overlay, input, event);
  }
}

/// Отмена: буфер поля очищается в той же `reduce`, автомату уходит `Cancel`;
/// оверлей закроет `Cancelled` от автомата (одна точка правды, D17).
(TuiModel, List<TuiCmd>) _cancel(
  TuiModel model,
  ProviderWizardOverlay overlay,
) {
  final mode = overlay.mode;
  final wiped = mode is WizardInput
      ? overlay.copyWith(mode: WizardInput(mode.def, mode.field.cleared()))
      : overlay;
  return (
    _setWizard(model, wiped),
    [WizardEventCmd(const Cancel(), overlayId: overlay.id)],
  );
}

(TuiModel, List<TuiCmd>) _pickKey(
  TuiModel model,
  ProviderWizardOverlay overlay,
  WizardPick pick,
  KeyEvent event,
) {
  final options = overlay.step.options;
  if (event is! SpecialKey) {
    return (model, const []);
  }
  switch (event.key) {
    case Key.up:
      return (
        _setWizard(
          model,
          overlay.copyWith(
            mode: WizardPick((pick.selected - 1).clamp(0, options.length - 1)),
          ),
        ),
        const [],
      );
    case Key.down:
      return (
        _setWizard(
          model,
          overlay.copyWith(
            mode: WizardPick((pick.selected + 1).clamp(0, options.length - 1)),
          ),
        ),
        const [],
      );
    case Key.enter:
      return _perform(model, overlay, options[pick.selected].action);
    case _:
      return (model, const []);
  }
}

(TuiModel, List<TuiCmd>) _filterKey(
  TuiModel model,
  ProviderWizardOverlay overlay,
  WizardFilter filter,
  KeyEvent event,
) {
  (TuiModel, List<TuiCmd>) set(WizardFilter next) =>
      (_setWizard(model, overlay.copyWith(mode: next)), const []);
  final rows = filter.rows;
  switch (event) {
    case TextKey(:final text):
      return set(
        filter.copyWith(filter: filter.filter.pasted(text), cursor: 0),
      );
    case SpecialKey(:final key):
      switch (key) {
        case Key.up:
          return set(
            filter.copyWith(
              cursor: (filter.cursor - 1).clamp(0, rows.length - 1),
            ),
          );
        case Key.down:
          return set(
            filter.copyWith(
              cursor: (filter.cursor + 1).clamp(0, rows.length - 1),
            ),
          );
        case Key.backspace:
          return set(
            filter.copyWith(filter: filter.filter.backspace(), cursor: 0),
          );
        case Key.ctrlU:
          return set(
            filter.copyWith(filter: filter.filter.cleared(), cursor: 0),
          );
        case Key.enter:
          final index = filter.cursor.clamp(0, rows.length - 1);
          if (index == rows.length - 1) {
            return _perform(model, overlay, const AskModelId());
          }
          return _perform(model, overlay, SendEvent(ModelChosen(rows[index])));
        case _:
          return (model, const []);
      }
  }
}

(TuiModel, List<TuiCmd>) _inputKey(
  TuiModel model,
  ProviderWizardOverlay overlay,
  WizardInput input,
  KeyEvent event,
) {
  final (next, key) = applyFieldKey(input.field, event);
  switch (key) {
    case LineKey.edited:
      return _wizardField(model, overlay, input, next);
    case LineKey.multiline:
      // Вставка нескольких строк и слишком длинный ключ: без значения и без
      // его длины, поле пусто (D14).
      return (
        _setWizard(
          model,
          overlay.copyWith(
            mode: WizardInput(input.def, next.cleared()),
            message: () => keyRejectedLine,
          ),
        ),
        const [],
      );
    case LineKey.cancel:
      return _cancel(model, overlay);
    case LineKey.ignored:
      return (model, const []);
    case LineKey.submit:
      final text = input.field.text;
      // Буфер очищается до обработки значения: дальше оно живёт только в
      // событии автомата (SETUP-1).
      final cleared = overlay.copyWith(
        mode: WizardInput(input.def, input.field.cleared()),
        message: () => null,
      );
      return _perform(model, cleared, input.def.submit(text));
  }
}

(TuiModel, List<TuiCmd>) _wizardField(
  TuiModel model,
  ProviderWizardOverlay overlay,
  WizardInput input,
  LineField next,
) {
  if (next.rejected) {
    return (
      _setWizard(
        model,
        overlay.copyWith(
          mode: WizardInput(input.def, next.cleared()),
          message: () => keyRejectedLine,
        ),
      ),
      const [],
    );
  }
  return (
    _setWizard(
      model,
      overlay.copyWith(mode: WizardInput(input.def, next), message: () => null),
    ),
    const [],
  );
}

/// Исполняет действие шага: событие автомату или открытие поля.
(TuiModel, List<TuiCmd>) _perform(
  TuiModel model,
  ProviderWizardOverlay overlay,
  WizardAction action,
) {
  switch (action) {
    case SendEvent(:final event):
      // После события шаг ждёт ответа автомата: двойной Enter не нужен.
      return (
        _setWizard(
          model,
          overlay.copyWith(mode: const WizardWaiting(), message: () => null),
        ),
        [WizardEventCmd(event, overlayId: overlay.id)],
      );
    case Reask(:final message):
      final mode = overlay.mode;
      return (
        _setWizard(
          model,
          overlay.copyWith(
            mode: mode is WizardInput
                ? WizardInput(mode.def, mode.field.cleared())
                : mode,
            message: () => message,
          ),
        ),
        const [],
      );
    case AskSecret() || AskEnvName() || AskModelId() || AskField():
      final def = fieldOfAction(action)!;
      return (
        _setWizard(
          model,
          overlay.copyWith(
            mode: WizardInput(
              def,
              LineField.initial(def.initial, hidden: def.hidden),
            ),
            message: () => null,
          ),
        ),
        const [],
      );
  }
}

/// Состояние автомата для открытого мастера [overlay] с тем же номером.
TuiOverlay? wizardStateOverlay(
  ProviderWizardOverlay overlay,
  ProviderSetupState state,
) {
  final next = ProviderWizardOverlay.of(
    overlay.id,
    state,
    pathOf: overlay.pathOf,
    backend: overlay.backend,
  );
  return next.finished ? null : next;
}

// --- экран настроек ------------------------------------------------------

(TuiModel, List<TuiCmd>) _settingsKey(
  TuiModel model,
  SettingsOverlay overlay,
  KeyEvent event,
) {
  TuiModel set(SettingsOverlay next) => model.copyWith(overlay: () => next);
  final mode = overlay.mode;

  // Запись идёт: клавиши записи и Esc игнорируются до исхода (D21).
  if (mode is SettingsSaving) {
    return (model, const []);
  }
  // Esc: из выбора и поля — к таблице, из таблицы — закрыть.
  if (event case SpecialKey(key: Key.escape || Key.ctrlC)) {
    if (mode is SettingsTable || !overlay.editable) {
      return (model.copyWith(overlay: () => null), const []);
    }
    return (set(overlay.copyWith(mode: const SettingsTable())), const []);
  }
  if (!overlay.editable) {
    // Только чтение: клавиши ничего не делают, кроме закрытия.
    return (model, const []);
  }
  final row = overlay.selected;
  switch (mode) {
    case SettingsSaving():
      return (model, const []);
    case SettingsTable():
      return _tableKey(model, overlay, row, event);
    case SettingsChoose(:final values, :final index):
      if (event is! SpecialKey || row == null) {
        return (model, const []);
      }
      switch (event.key) {
        case Key.left:
          return (
            set(
              overlay.copyWith(
                mode: SettingsChoose(
                  values,
                  (index - 1).clamp(0, values.length - 1),
                ),
              ),
            ),
            const [],
          );
        case Key.right:
          return (
            set(
              overlay.copyWith(
                mode: SettingsChoose(
                  values,
                  (index + 1).clamp(0, values.length - 1),
                ),
              ),
            ),
            const [],
          );
        case Key.enter:
          return _apply(model, overlay, row, values[index], toUser: false);
        case Key.ctrlU:
          return _apply(model, overlay, row, values[index], toUser: true);
        case _:
          return (model, const []);
      }
    case SettingsEdit(:final field):
      if (row == null) {
        return (model, const []);
      }
      if (event case SpecialKey(key: Key.ctrlU)) {
        // В поле правки Ctrl+U — «сохранить в user» (артборд), очистка — на
        // Backspace (D17).
        return _apply(model, overlay, row, field.text, toUser: true);
      }
      final (next, key) = applyFieldKey(field, event);
      switch (key) {
        case LineKey.submit:
          return _apply(model, overlay, row, field.text, toUser: false);
        case LineKey.edited:
          return (set(overlay.copyWith(mode: SettingsEdit(next))), const []);
        case LineKey.multiline || LineKey.cancel || LineKey.ignored:
          return (model, const []);
      }
  }
}

(TuiModel, List<TuiCmd>) _tableKey(
  TuiModel model,
  SettingsOverlay overlay,
  SettingFieldView? row,
  KeyEvent event,
) {
  TuiModel set(SettingsOverlay next) => model.copyWith(overlay: () => next);
  SettingsOverlay moved(int section, int index) {
    final next = overlay.copyWith(section: section, row: index);
    return next.copyWith(hint: next.hintForSelection());
  }

  if (event case TextKey(:final text) when text == 'r') {
    return _reset(model, overlay, row);
  }
  if (event is! SpecialKey) {
    return (model, const []);
  }
  final rows = overlay.sectionRows;
  switch (event.key) {
    case Key.up:
      return (
        set(
          moved(
            overlay.section,
            (overlay.row - 1).clamp(0, rows.isEmpty ? 0 : rows.length - 1),
          ),
        ),
        const [],
      );
    case Key.down:
      return (
        set(
          moved(
            overlay.section,
            (overlay.row + 1).clamp(0, rows.isEmpty ? 0 : rows.length - 1),
          ),
        ),
        const [],
      );
    case Key.tab:
      if (overlay.sections.isEmpty) {
        return (model, const []);
      }
      return (
        set(moved((overlay.section + 1) % overlay.sections.length, 0)),
        const [],
      );
    case Key.enter:
      return row == null ? (model, const []) : _open(model, overlay, row);
    case _:
      return (model, const []);
  }
}

/// Отказ по строке без записи: подсказка (D17, Q15, Q16). Правила — общие с
/// `applySetting` (`settingRowRefusal`), своей копии нет.
String? _rowRefusal(SettingFieldView row) => settingRowRefusal(row);

(TuiModel, List<TuiCmd>) _open(
  TuiModel model,
  SettingsOverlay overlay,
  SettingFieldView row,
) {
  TuiModel hint(String text) =>
      model.copyWith(overlay: () => overlay.copyWith(hint: text));
  if (_rowRefusal(row) case final refusal?) {
    return (hint(refusal), const []);
  }
  if (row.entryCount != null) {
    // Карты и списки отображений только для чтения (Q16 (а)).
    return (
      hint(
        row.key == 'mcp.servers'
            ? 'Edit with codelab mcp add'
            : 'Edit ${row.key} in the config file or with codelab config set',
      ),
      const [],
    );
  }
  final descriptor = row.descriptor;
  final values = switch (descriptor.type) {
    SettingType.enumeration => descriptor.enumValues ?? const <String>[],
    SettingType.bool => const ['true', 'false'],
    _ => null,
  };
  if (values != null && values.isNotEmpty) {
    final current = row.effectiveValue?.toString();
    final index = current == null
        ? 0
        : values.indexOf(current).clamp(0, values.length - 1);
    return (
      model.copyWith(
        overlay: () => overlay.copyWith(mode: SettingsChoose(values, index)),
      ),
      const [],
    );
  }
  return (
    model.copyWith(
      overlay: () => overlay.copyWith(
        mode: SettingsEdit(LineField.initial(_editValue(overlay, row))),
      ),
    ),
    const [],
  );
}

/// Исходное значение для правки — из снимка, а не из замаскированного
/// `SettingFieldView.value` (D17).
String _editValue(SettingsOverlay overlay, SettingFieldView row) {
  final leaf = overlay.snapshot?.leaves[row.key] ?? row.descriptor.defaultValue;
  return switch (leaf) {
    null => '',
    final List<Object?> list => jsonEncode(list),
    final Map<Object?, Object?> map => jsonEncode(map),
    final other => '$other',
  };
}

(TuiModel, List<TuiCmd>) _reset(
  TuiModel model,
  SettingsOverlay overlay,
  SettingFieldView? row,
) {
  if (row == null) {
    return (model, const []);
  }
  if (_rowRefusal(row) case final refusal?) {
    return (
      model.copyWith(overlay: () => overlay.copyWith(hint: refusal)),
      const [],
    );
  }
  return _apply(model, overlay, row, null, toUser: false);
}

(TuiModel, List<TuiCmd>) _apply(
  TuiModel model,
  SettingsOverlay overlay,
  SettingFieldView row,
  String? raw, {
  required bool toUser,
}) {
  final layer = settingWriteLayerOf(
    row,
    overlay.access as EditableSettings,
    toUser: toUser,
  );
  if (layer == null) {
    return (
      model.copyWith(
        overlay: () => overlay.copyWith(
          mode: const SettingsTable(),
          hint:
              '${row.key} is set by ${row.sourceName}; it cannot be changed here.',
        ),
      ),
      const [],
    );
  }
  return (
    model.copyWith(
      overlay: () => overlay.copyWith(mode: const SettingsSaving(), hint: ''),
    ),
    [
      ApplySettingCmd(
        overlay.id,
        row.key,
        raw: raw,
        layer: layer,
        explicitLayer: toUser,
      ),
    ],
  );
}
