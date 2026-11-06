import 'package:codelab_setup/codelab_setup.dart';

import '../repl/picker_spec.dart';

/// Строки `/settings`: ключи реестра со `scope: shared` (design.md change
/// `add-provider-setup-ui`, D17, Q15). `trusted_projects` показывается, но не
/// правится ([isTrustBoundary]).
///
/// Почему отдельный файл без `dart_tui`: те же строки нужны REPL и экрану
/// настроек TUI (4b), а выбор слоя записи и отказы — общие правила.
List<SettingFieldView> settingRowsOf(AgentConfigSnapshot snapshot) =>
    settingFieldsOf(snapshot);

/// Граница доверия: клиент её показывает и не меняет (решение пользователя).
bool isTrustBoundary(String key) => key == 'trusted_projects';

const trustBoundaryLine =
    'trusted_projects is a trust boundary; it cannot be changed here.';

/// Дескриптор ключа реестра со `scope: shared`; `null` — ключа нет в реестре
/// или он не `shared` («Unknown setting»). `trusted_projects` дескриптор
/// имеет, но команда его не правит ([isTrustBoundary]).
SettingDescriptor? editableDescriptorOf(String key) {
  final descriptor = SettingsRegistry.lookup(key);
  if (descriptor == null || descriptor.scope != SettingScope.shared) {
    return null;
  }
  return descriptor;
}

/// Ключ хранит имя секрета: правка — только `codelab secret set`.
bool isSecretKey(SettingDescriptor descriptor) =>
    descriptor.secret || descriptor.type == SettingType.secretName;

/// Источник, который клиент не переписывает: `--config` и окружение.
bool isExternalSource(SettingFieldView? row) =>
    row != null &&
    (row.source?.kind == ConfigSourceKind.extraFile ||
        row.source?.kind == ConfigSourceKind.environment);

/// Формат значения [descriptor] для подсказки: текст `ConfigValueException`
/// на заведомо неверном вводе; `null`, если пустая строка допустима.
String? expectedFormatOf(SettingDescriptor descriptor) {
  try {
    SettingsRegistry.parseCliValue(descriptor, '');
  } on ConfigValueException catch (error) {
    return error.expected;
  }
  return null;
}

/// Отказ по самому ключу (до чтения слоёв): неизвестный или не `shared`,
/// граница доверия, секретный ключ; `null` — ключ можно менять.
String? settingKeyRefusal(String key) {
  final descriptor = editableDescriptorOf(key);
  if (descriptor == null) {
    return 'Unknown setting $key. Run /settings to list them.';
  }
  if (isTrustBoundary(key)) {
    return trustBoundaryLine;
  }
  if (isSecretKey(descriptor)) {
    return 'Use codelab secret set <name>';
  }
  return null;
}

/// Отказ по строке [row] (до записи): ключ ([settingKeyRefusal]), источник
/// `config`/`env`, замаскированное значение; `null` — строку можно менять.
///
/// Единое место для `applySetting` и экрана настроек TUI: замаскированное
/// значение (литеральный секрет, в том числе элемент списка) нельзя ни
/// переписать, ни сбросить вслепую (D17, D20).
String? settingRowRefusal(SettingFieldView row) {
  if (settingKeyRefusal(row.key) case final refusal?) {
    return refusal;
  }
  if (isExternalSource(row)) {
    return '${row.key} is set by ${row.sourceName}; it cannot be changed here.';
  }
  if (row.masked) {
    return 'Use codelab secret set <name>';
  }
  return null;
}

/// Записывает или сбрасывает [key] в слое [layer] и возвращает строку исхода
/// (design.md change `add-provider-setup-ui`, D17, Q15).
///
/// Почему одна функция: REPL (`/settings`) и оверлей TUI проверяют и пишут
/// одинаково, своих текстов у оверлея нет (SETUP-3, SETUP-6).
///
/// Как использовать: [access] (если передан) нужен для правила «ключ слоя
/// `local` или `project` без цели `projectLocal` не пишется в `user` по
/// умолчанию»; [explicitLayer] (явный выбор слоя, ctrl+u) это правило снимает
/// — пользователь сам выбрал `user`, но источники `config`/`env` и маска
/// остаются отказом. [raw] — введённая строка (`null` — сброс); слой выбирает
/// вызывающий (`user`, `projectLocal`; слой 3 не пишется никогда). Цепочка:
/// отказ по ключу ([settingKeyRefusal]), источник `config`/`env`, нечитаемый
/// слой, разбор `parseCliValue`, `apply`. Значение в текст не попадает
/// (CFG-10). Конфликт записи — строка без автоповтора.
Future<String> applySetting(
  AgentConfigStore store,
  AgentConfigSnapshot snapshot,
  String key, {
  String? raw,
  required ConfigLayer layer,
  EditableSettings? access,
  bool explicitLayer = false,
}) async {
  if (settingKeyRefusal(key) case final refusal?) {
    return refusal;
  }
  final descriptor = editableDescriptorOf(key)!;
  final row = settingRowsOf(snapshot).where((r) => r.key == key).firstOrNull;
  if (row != null) {
    if (settingRowRefusal(row) case final refusal?) {
      return refusal;
    }
  }
  // Ключ слоя `local` или `project`, а цели `projectLocal` нет: запись в
  // `user` перекрыта значением того слоя — не пишем молча (решения
  // пользователя, ревью 4b).
  final kind = row?.source?.kind;
  if (access != null &&
      (kind == ConfigSourceKind.projectLocal ||
          kind == ConfigSourceKind.project) &&
      layer != ConfigLayer.projectLocal &&
      !explicitLayer &&
      !access.targets.any((t) => t.layer == ConfigLayer.projectLocal)) {
    return '$key is set by ${row!.sourceName}; it cannot be changed here.';
  }
  final base = snapshot.layers[layer];
  if (base == null) {
    final name = switch (layer) {
      ConfigLayer.user => 'user',
      ConfigLayer.projectLocal => 'local',
      ConfigLayer.project => 'project',
    };
    return 'Cannot read the $name config file; run "codelab config check".';
  }
  final ConfigEdit edit;
  if (raw == null) {
    if (base.get(key) == null) {
      return '$key is not set in ${base.path}';
    }
    edit = UnsetValue(key);
  } else {
    try {
      edit = SetValue(key, SettingsRegistry.parseCliValue(descriptor, raw));
    } on ConfigValueException catch (error) {
      // Значение в текст не попадает: оно могло быть секретом (CFG-10).
      return '$key: expected ${error.expected}';
    }
  }
  final outcome = await store.apply(base, [edit]);
  switch (outcome) {
    case ConfigSaved(:final restartRequiredKeys):
      final restart = restartRequiredKeys.contains(key)
          ? ' (applies after restart)'
          : '';
      return raw == null
          ? 'Removed $key from ${base.path}$restart'
          : 'Updated $key in ${base.path}$restart';
    case ConfigConflict():
      return 'The config file changed; run the command again.';
    case ConfigRejected(:final issues):
      return 'codelab: $key: ${issues.first.message}';
    case ConfigInlineSecret(:final suggestedSecretName):
      return 'Use codelab secret set $suggestedSecretName';
  }
}

/// Слой записи для строки [row] экрана настроек (D17, D24).
///
/// Ключ слоя `local` или `project` без цели `projectLocal` у [access] даёт
/// `null` (`<key> is set by local|project; it cannot be changed here.`).
///
/// `toUser` (Ctrl+U) — всегда `user`. Иначе: источник `local` или `project` —
/// `projectLocal`, если у [access] есть такая цель, иначе отказ (`null`; слой 3
/// не пишется, SETUP-3, и молча в `user` не пишем); `default`/`user` — `user`;
/// `config`/`env` — `null` (ключ задан извне). Ключи слоя `project` правятся, хотя
/// `SettingFieldView.editable` у них `false`: он говорит «этот файл не
/// пишется», а не «ключ нельзя менять».
ConfigLayer? settingWriteLayerOf(
  SettingFieldView row,
  EditableSettings access, {
  required bool toUser,
}) {
  if (toUser) {
    return ConfigLayer.user;
  }
  final hasLocal = access.targets.any(
    (t) => t.layer == ConfigLayer.projectLocal,
  );
  return switch (row.source?.kind) {
    ConfigSourceKind.extraFile || ConfigSourceKind.environment => null,
    // Ключ слоя `local`, а цели нет: молча писать в `user` нельзя — значение
    // слоя `local` его перекроет (отказ, как у `config`/`env`).
    ConfigSourceKind.projectLocal => hasLocal ? ConfigLayer.projectLocal : null,
    // Слой 3 пишется в `projectLocal`; цели нет — молча в `user` не пишем.
    ConfigSourceKind.project => hasLocal ? ConfigLayer.projectLocal : null,
    ConfigSourceKind.user || null => ConfigLayer.user,
  };
}

/// Список `/settings` для REPL: по строке `key value source` на ключ, пункт
/// запускает `/settings <key>`.
PickerSpec settingsPickerOf(AgentConfigSnapshot snapshot) => PickerSpec(
  title: 'Settings (key, value, source):',
  items: [
    for (final row in settingRowsOf(snapshot))
      PickerItem(
        label: '${row.key}  ${row.displayValue}  ${row.sourceName}',
        line: '/settings ${row.key}',
      ),
  ],
);
