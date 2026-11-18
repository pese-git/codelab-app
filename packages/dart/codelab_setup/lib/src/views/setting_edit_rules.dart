/// ЗАГЛУШКА красного теста 1.1 change `add-app-general-page` (D6): правила
/// «можно ли править строку настроек агента». Реализация — задача 1.2.
library;

import 'setting_field_view.dart';
import '../config/config_source_view.dart';

/// Причина, по которой строку настроек нельзя править из клиента (D6).
sealed class SettingEditRefusal {
  const SettingEditRefusal();
}

/// Ключа нет в реестре или он не `scope: shared`.
final class UnknownSetting extends SettingEditRefusal {
  const UnknownSetting(this.key);
  final String key;
}

/// `trusted_projects` — граница доверия.
final class TrustBoundarySetting extends SettingEditRefusal {
  const TrustBoundarySetting();
}

/// Секрет: правится только через `codelab secret set`.
final class SecretSetting extends SettingEditRefusal {
  const SecretSetting(this.key);
  final String key;
}

/// Значение задано `--config` или окружением.
final class ExternalSourceSetting extends SettingEditRefusal {
  const ExternalSourceSetting(this.source);
  final ConfigSourceView source;
}

/// Значение замаскировано (литеральный секрет).
final class MaskedSetting extends SettingEditRefusal {
  const MaskedSetting(this.key);
  final String key;
}

/// Отказ по самому ключу до чтения слоёв. Заглушка: всегда «можно».
SettingEditRefusal? settingKeyEditRefusalOf(String key) => null;

/// Отказ по строке: ключ, источник, маска. Заглушка: всегда «можно».
SettingEditRefusal? settingEditRefusalOf(SettingFieldView row) => null;
