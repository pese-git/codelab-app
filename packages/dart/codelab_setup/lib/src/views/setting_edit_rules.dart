/// Правила «можно ли править строку настроек агента» (client-agent-setup
/// «Правила правки строк настроек агента»; design.md change
/// `add-app-general-page`, D6).
///
/// Почему в мосте: CLI (`/settings`, экран TUI) и страница «General» app
/// решают одно и то же — какие строки таблицы `key · value · source` клиент
/// не переписывает. Без общего правила второй клиент завёл бы своё и новый
/// секретный ключ мог бы стать редактируемым в одном из них (SETUP-3).
///
/// Для чего: мост отдаёт только причину отказа (ветку [SettingEditRefusal]) и
/// данные для текста (ключ, источник). Тексты и локализацию строит клиент:
/// CLI сохраняет свои английские строки, app берёт их из ARB.
///
/// Как использовать: до записи вызвать [settingKeyEditRefusalOf] (достаточно
/// ключа) и/или [settingEditRefusalOf] (строка со снимка); `null` — править
/// можно. Выбор слоя записи правило не затрагивает.
library;

import 'package:codelab_agent_core/codelab_agent_core.dart'
    show SettingScope, SettingType, SettingsRegistry;

import '../config/config_source_view.dart';
import 'setting_field_view.dart';

/// Причина, по которой строку настроек нельзя править из клиента (D6).
///
/// Ветки закрыты (`sealed`): клиент разбирает их `switch`-ом без `default`,
/// и новая ветка не пройдёт мимо экрана. Значений настроек в ветках нет
/// (SETUP-1, CFG-10): только ключ или источник.
sealed class SettingEditRefusal {
  const SettingEditRefusal();
}

/// Ключа нет в реестре или он не `scope: shared`.
final class UnknownSetting extends SettingEditRefusal {
  const UnknownSetting(this.key);

  /// Запрошенный ключ.
  final String key;

  @override
  String toString() => 'UnknownSetting($key)';
}

/// `trusted_projects` — граница доверия: клиент её показывает и не меняет.
final class TrustBoundarySetting extends SettingEditRefusal {
  const TrustBoundarySetting();

  @override
  String toString() => 'TrustBoundarySetting()';
}

/// Секрет: правится только через `codelab secret set <name>`.
final class SecretSetting extends SettingEditRefusal {
  const SecretSetting(this.key);

  /// Ключ, хранящий имя секрета.
  final String key;

  @override
  String toString() => 'SecretSetting($key)';
}

/// Значение задано `--config` или окружением: клиент эти источники не
/// переписывает.
final class ExternalSourceSetting extends SettingEditRefusal {
  const ExternalSourceSetting(this.key, this.source);

  /// Ключ строки (нужен тексту отказа: «key is set by source»).
  final String key;

  /// Источник значения: `extraFile` или `environment`.
  final ConfigSourceView source;

  @override
  String toString() => 'ExternalSourceSetting($key, ${source.kind.name})';
}

/// Значение замаскировано (литеральный секрет): его нельзя ни переписать, ни
/// сбросить вслепую.
final class MaskedSetting extends SettingEditRefusal {
  const MaskedSetting(this.key);

  /// Ключ замаскированной строки.
  final String key;

  @override
  String toString() => 'MaskedSetting($key)';
}

/// Отказ по самому ключу до чтения слоёв.
///
/// Порядок веток: неизвестный или не `shared`, граница доверия, секрет.
/// `null` — по ключу править можно.
SettingEditRefusal? settingKeyEditRefusalOf(String key) {
  final descriptor = SettingsRegistry.lookup(key);
  if (descriptor == null || descriptor.scope != SettingScope.shared) {
    return UnknownSetting(key);
  }
  if (key == 'trusted_projects') {
    return const TrustBoundarySetting();
  }
  if (descriptor.secret || descriptor.type == SettingType.secretName) {
    return SecretSetting(key);
  }
  return null;
}

/// Отказ по строке: сначала ключ ([settingKeyEditRefusalOf]), затем источник
/// `config`/`env`, затем маска. `null` — строку можно менять.
///
/// Порядок важен: секрет из окружения остаётся [SecretSetting] (текст «Use
/// codelab secret set»), а не [ExternalSourceSetting].
SettingEditRefusal? settingEditRefusalOf(SettingFieldView row) {
  if (settingKeyEditRefusalOf(row.key) case final refusal?) {
    return refusal;
  }
  final kind = row.source?.kind;
  if (kind == ConfigSourceKind.extraFile ||
      kind == ConfigSourceKind.environment) {
    return ExternalSourceSetting(row.key, row.source!);
  }
  if (row.masked) {
    return MaskedSetting(row.key);
  }
  return null;
}
