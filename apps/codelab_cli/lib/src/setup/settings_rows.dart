import 'package:codelab_setup/codelab_setup.dart';

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

/// Записывает или сбрасывает [key] в слое [layer] и возвращает строку исхода
/// (design.md change `add-provider-setup-ui`, D17, Q15).
///
/// Почему одна функция: REPL (`/settings`) и оверлей TUI проверяют и пишут
/// одинаково, своих текстов у оверлея нет (SETUP-3, SETUP-6).
///
/// Как использовать: [raw] — введённая строка (`null` — сброс); слой выбирает
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
}) async {
  if (settingKeyRefusal(key) case final refusal?) {
    return refusal;
  }
  final descriptor = editableDescriptorOf(key)!;
  final row = settingRowsOf(snapshot).where((r) => r.key == key).firstOrNull;
  if (isExternalSource(row)) {
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
/// `toUser` (Ctrl+U) — всегда `user`. Иначе: источник `local` — `projectLocal`;
/// `project` — `projectLocal`, если у [access] есть такая цель, иначе `user`
/// (слой 3 не пишется, SETUP-3); `default`/`user` — `user`; `config`/`env` —
/// `null` (ключ задан извне). Ключи слоя `project` правятся, хотя
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
    ConfigSourceKind.projectLocal || ConfigSourceKind.project =>
      hasLocal ? ConfigLayer.projectLocal : ConfigLayer.user,
    ConfigSourceKind.user || null => ConfigLayer.user,
  };
}
