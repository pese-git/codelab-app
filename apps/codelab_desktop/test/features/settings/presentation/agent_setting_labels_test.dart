// Полнота подписей ключей блока «Agent defaults» (ревью change
// `add-app-general-page`; design.md D2): таблица `agentSettingLabelOf`
// обязана покрывать каждый ключ владельца `general`, английский текст равен
// реестру (подпись CLI и app не расходятся), русский — перевод, а не сам ключ.

import 'package:codelab_desktop/features/settings/application/agent_defaults_rows.dart';
import 'package:codelab_desktop/features/settings/presentation/agent_setting_labels.dart';
import 'package:codelab_desktop/l10n/app_localizations_en.dart';
import 'package:codelab_desktop/l10n/app_localizations_ru.dart';
import 'package:codelab_setup/codelab_setup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final general = [
    for (final d in SettingsRegistry.all)
      if (d.scope == SettingScope.shared &&
          settingsPageOwnerOf(d.key) == SettingsPageOwner.general)
        d,
  ];
  final en = AppLocalizationsEn();
  final ru = AppLocalizationsRu();

  test('ключей general 18: тест не проходит на пустом наборе', () {
    expect(general, hasLength(18));
  });

  test('английская подпись и описание равны реестру для каждого ключа', () {
    for (final d in general) {
      expect(agentSettingLabelOf(en, d.key), d.label, reason: d.key);
      expect(
        agentSettingDescriptionOf(en, d.key),
        d.description,
        reason: d.key,
      );
    }
  });

  test('русские подпись и описание есть и не равны ключу', () {
    for (final d in general) {
      final label = agentSettingLabelOf(ru, d.key);
      final description = agentSettingDescriptionOf(ru, d.key);
      expect(label, isNotNull, reason: d.key);
      expect(label, isNotEmpty, reason: d.key);
      expect(label, isNot(d.key), reason: d.key);
      expect(description, isNotNull, reason: d.key);
      expect(description, isNotEmpty, reason: d.key);
      expect(description, isNot(d.key), reason: d.key);
    }
  });

  test('ключ вне таблицы даёт null, а не подпись другого ключа', () {
    expect(agentSettingLabelOf(en, 'permissions.mode'), isNull);
    expect(agentSettingDescriptionOf(en, 'no.such.key'), isNull);
  });
}
