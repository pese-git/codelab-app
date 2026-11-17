import 'package:codelab_setup/codelab_setup.dart';

import '../../repl/picker_spec.dart';
import '../../setup/line_field.dart';
import '../../setup/settings_rows.dart';
import '../../setup/wizard_steps.dart';

/// Открытый поверх транскрипта экран: пикер, мастер провайдера или экран
/// настроек.
///
/// Почему закрытая иерархия: `TuiModel.overlay` был `PickerSpec?`, а двум
/// модальным экранам нужны своё состояние и своя маршрутизация клавиш;
/// `switch` по иерархии исчерпывающий (design.md change
/// `add-provider-setup-ui`, D17, «Сверка с кодом (подготовка итерации 4b)»).
///
/// Для чего: [PickerOverlay] — клавиши по-прежнему у адаптера (`ListModel`);
/// [ProviderWizardOverlay] и [SettingsOverlay] — модальные: их клавиши и
/// вставку обрабатывает `reduce` раньше зоны одобрения и композера (TUI-5).
sealed class TuiOverlay {
  const TuiOverlay();
}

/// Пикер команды без аргумента; клавиши ведёт адаптер.
final class PickerOverlay extends TuiOverlay {
  const PickerOverlay(this.spec);

  final PickerSpec spec;
}

/// Модальный ли оверлей: мастер или экран настроек. Под ним нет композера и
/// зоны одобрения, а клавиши получает только он.
bool isModalOverlay(TuiOverlay? overlay) =>
    overlay is ProviderWizardOverlay || overlay is SettingsOverlay;

// --- мастер провайдера -----------------------------------------------------

/// Вид ввода текущего шага мастера.
sealed class WizardMode {
  const WizardMode();
}

/// Шаг ждёт ответа автомата или порта: ввода нет.
final class WizardWaiting extends WizardMode {
  const WizardWaiting();
}

/// Идёт запись: Esc и Ctrl+C блокированы (D21).
final class WizardSaving extends WizardMode {
  const WizardSaving();
}

/// Список со стрелками.
final class WizardPick extends WizardMode {
  const WizardPick(this.selected);

  final int selected;
}

/// Выбор модели: фильтр по подстроке и пункт ручного ввода.
final class WizardFilter extends WizardMode {
  const WizardFilter({
    required this.ids,
    required this.filter,
    this.cursor = 0,
  });

  static const window = 8;
  static const manualLabel = 'Enter model id manually';

  final List<String> ids;
  final LineField filter;
  final int cursor;

  List<String> get matches => [
    for (final id in ids)
      if (id.toLowerCase().contains(filter.text.toLowerCase())) id,
  ];

  /// Строки списка: найденные модели и в конце ручной ввод.
  List<String> get rows => [...matches, manualLabel];

  WizardFilter copyWith({LineField? filter, int? cursor}) => WizardFilter(
    ids: ids,
    filter: filter ?? this.filter,
    cursor: cursor ?? this.cursor,
  );
}

/// Поле ввода шага: описание [def] и буфер [field].
final class WizardInput extends WizardMode {
  const WizardInput(this.def, this.field);

  final WizardField def;
  final LineField field;
}

/// Мастер `/provider add` как модальный экран.
///
/// Почему состояние автомата здесь только для показа: `ProviderSetupFlow`
/// держит поток и порты и в `TuiModel` не лежит; оверлей хранит последнее
/// [state], его [step] (тексты `wizardStepOf`) и вид ввода [mode]. События
/// автомату `reduce` отдаёт командами `WizardEventCmd`.
///
/// Для чего: [id] — номер оверлея, поздние состояния чужого номера
/// игнорируются; [message] — строка перед вводом (ошибка ввода, отказ ключа).
/// Значение ключа живёт только в буфере [WizardInput.field] (SETUP-1).
final class ProviderWizardOverlay extends TuiOverlay {
  const ProviderWizardOverlay({
    required this.id,
    required this.state,
    required this.step,
    required this.mode,
    this.pathOf,
    this.backend = '',
    this.message,
  });

  /// Оверлей на состоянии [state] со свежим видом ввода шага.
  factory ProviderWizardOverlay.of(
    int id,
    ProviderSetupState state, {
    String Function(ConfigTarget target)? pathOf,
    String backend = '',
  }) {
    final step = wizardStepOf(state, backend: backend, pathOf: pathOf);
    return ProviderWizardOverlay(
      id: id,
      state: state,
      step: step,
      mode: modeOf(step),
      pathOf: pathOf,
      backend: step.backend ?? backend,
    );
  }

  final int id;
  final ProviderSetupState state;
  final WizardStep step;
  final WizardMode mode;
  final String Function(ConfigTarget target)? pathOf;
  final String backend;
  final String? message;

  /// Шаг закончил мастер: запись, отмена или отказ записи.
  bool get finished =>
      step.cancelled || step.savedProviderId != null || step.failure != null;

  /// Вид ввода по описанию шага (приоритет как у построчного мастера).
  static WizardMode modeOf(WizardStep step) {
    if (step.saving) {
      return const WizardSaving();
    }
    if (step.waiting || step.progress != null) {
      return const WizardWaiting();
    }
    if (step.options.isNotEmpty) {
      return const WizardPick(0);
    }
    if (step.models case final ids?) {
      final current = step.currentModel;
      return WizardFilter(
        ids: ids,
        filter: const LineField(),
        cursor: current == null
            ? 0
            : ids.indexOf(current).clamp(0, ids.length - 1),
      );
    }
    if (step.field case final def?) {
      return WizardInput(
        def,
        LineField.initial(def.initial, hidden: def.hidden),
      );
    }
    return const WizardWaiting();
  }

  ProviderWizardOverlay copyWith({
    WizardMode? mode,
    String? Function()? message,
  }) => ProviderWizardOverlay(
    id: id,
    state: state,
    step: step,
    mode: mode ?? this.mode,
    pathOf: pathOf,
    backend: backend,
    message: message == null ? this.message : message(),
  );
}

// --- экран настроек --------------------------------------------------------

/// Вид ввода экрана настроек.
sealed class SettingsMode {
  const SettingsMode();
}

/// Таблица: ↑↓, Tab, Enter, `r`.
final class SettingsTable extends SettingsMode {
  const SettingsTable();
}

/// Выбор значения ←→ ([values], текущий [index]).
final class SettingsChoose extends SettingsMode {
  const SettingsChoose(this.values, this.index);

  final List<String> values;
  final int index;
}

/// Запись идёт: клавиши записи и Esc игнорируются до исхода (D21).
final class SettingsSaving extends SettingsMode {
  const SettingsSaving();
}

/// Поле правки значения.
final class SettingsEdit extends SettingsMode {
  const SettingsEdit(this.field);

  final LineField field;
}

/// Экран `/settings` (артборд `CliSettings`, D17).
///
/// Для чего: [access] — чьи настройки (для чужого агента — только чтение);
/// [snapshot] — снимок конфига: из него берутся строки и исходное значение
/// для правки (а не из `SettingFieldView.value`, оно замаскировано, D17);
/// [section] и [row] — выбранный раздел и строка в нём; [hint] — подсказка
/// о выбранной строке или исход последней записи.
final class SettingsOverlay extends TuiOverlay {
  SettingsOverlay._({
    required this.id,
    required this.access,
    required this.snapshot,
    required this.rows,
    required this.sections,
    this.section = 0,
    this.row = 0,
    this.mode = const SettingsTable(),
    this.hint = '',
  });

  factory SettingsOverlay.open(
    int id, {
    required SettingsAccess access,
    AgentConfigSnapshot? snapshot,
  }) {
    final rows = snapshot == null
        ? const <SettingFieldView>[]
        : settingRowsOf(snapshot);
    final sections = <String>[];
    for (final r in rows) {
      if (!sections.contains(r.descriptor.section)) {
        sections.add(r.descriptor.section);
      }
    }
    final overlay = SettingsOverlay._(
      id: id,
      access: access,
      snapshot: snapshot,
      rows: rows,
      sections: sections,
    );
    return overlay.copyWith(hint: overlay.hintForSelection());
  }

  final int id;
  final SettingsAccess access;
  final AgentConfigSnapshot? snapshot;
  final List<SettingFieldView> rows;
  final List<String> sections;
  final int section;
  final int row;
  final SettingsMode mode;
  final String hint;

  /// Строки текущего раздела.
  List<SettingFieldView> get sectionRows => sections.isEmpty
      ? const []
      : [
          for (final r in rows)
            if (r.descriptor.section == sections[section]) r,
        ];

  /// Выбранная строка или `null`.
  SettingFieldView? get selected {
    final list = sectionRows;
    return list.isEmpty ? null : list[row.clamp(0, list.length - 1)];
  }

  bool get editable => access is EditableSettings;

  SettingsOverlay copyWith({
    int? section,
    int? row,
    SettingsMode? mode,
    String? hint,
  }) => SettingsOverlay._(
    id: id,
    access: access,
    snapshot: snapshot,
    rows: rows,
    sections: sections,
    section: section ?? this.section,
    row: row ?? this.row,
    mode: mode ?? this.mode,
    hint: hint ?? this.hint,
  );

  /// Новый снимок после записи: выбор остаётся на том же ключе, [hint] —
  /// исход записи.
  SettingsOverlay withSnapshot(AgentConfigSnapshot next, String line) {
    final key = selected?.key;
    final fresh = SettingsOverlay.open(id, access: access, snapshot: next);
    var sectionIndex = 0;
    var rowIndex = 0;
    if (key != null) {
      final found = fresh.rows.where((r) => r.key == key).firstOrNull;
      if (found != null) {
        sectionIndex = fresh.sections.indexOf(found.descriptor.section);
        rowIndex = [
          for (final r in fresh.rows)
            if (r.descriptor.section == found.descriptor.section) r.key,
        ].indexOf(key);
      }
    }
    return fresh.copyWith(section: sectionIndex, row: rowIndex, hint: line);
  }

  /// Исход записи без нового снимка (его не удалось перечитать): выбор и
  /// снимок остаются, экран возвращается к таблице.
  SettingsOverlay withLine(String line) =>
      copyWith(mode: const SettingsTable(), hint: line);

  /// Подсказка о выбранной строке: ключ слоя 3 пишется в `local` (D17, D24).
  String hintForSelection() {
    final row = selected;
    final access = this.access;
    if (row == null || access is! EditableSettings) {
      return '';
    }
    if (row.source?.kind == ConfigSourceKind.project &&
        settingWriteLayerOf(row, access, toUser: false) ==
            ConfigLayer.projectLocal) {
      return '${row.key} is set by the project file; your choice is saved to '
          '.codelab/config.local.yaml. ctrl+u saves to user instead.';
    }
    return '';
  }
}
