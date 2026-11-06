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
