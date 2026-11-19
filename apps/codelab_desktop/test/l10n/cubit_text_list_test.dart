// Сверка списка Cubit-ов с текстом в состоянии с кодом (задача 6.1 change
// `add-desktop-localization`; design.md D12, уточнение итерации 5).
//
// Почему тест по исходникам: список из D12 («подписаны на `AppStrings`») живёт
// в design.md и `AGENTS.md`, и без проверки расходится с кодом молча:
// Cubit, у которого появился производный текст, остаётся без подписки и
// показывает прежний язык (R1). Тест читает `lib/features/**/application` и
// сравнивает фактические зависимости от `AppStrings` с эталонным списком.
//
// Как менять: Cubit с текстом в состоянии добавляется в [_withText] вместе с
// тестом смены языка (D9); Cubit, переставший хранить текст, убирается из
// списка и из кода одновременно. Комментарии не считаются: упоминание
// `AppStrings` в `///` не зависимость.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Файлы `application/`, которые зависят от `AppStrings` (D12): восемь Cubit-ов
/// с текстом. `shell_cubit.dart` — фасад: своей подписки нет, он берёт каталог
/// из `parts.strings.current` при пересчёте за частями (уточнение итерации 3).
const _withText = {
  'features/workbench/application/connection_cubit.dart',
  'features/workbench/application/active_session_cubit.dart',
  'features/workbench/application/sessions_cubit.dart',
  'features/workbench/application/shell_cubit.dart',
  'features/settings/application/connection_settings_cubit.dart',
  'features/settings/application/add_profile_cubit.dart',
  'features/settings/application/provider_settings_cubit.dart',
  'features/settings/application/provider_wizard_cubit.dart',
};

/// Из этих файлов подписки на `AppStrings.changes` нет по решению D12.
const _noOwnSubscription = {'features/workbench/application/shell_cubit.dart'};

/// Код файла без комментариев `//` и `///`.
String _code(File file) => file
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

Map<String, String> _applicationSources() {
  final root = Directory('lib/features');
  return {
    for (final entity in root.listSync(recursive: true))
      if (entity is File &&
          entity.path.endsWith('.dart') &&
          entity.path.contains('/application/'))
        entity.path.substring('lib/'.length): _code(entity),
  };
}

void main() {
  final sources = _applicationSources();

  test('AppStrings в application/ только у Cubit-ов из списка D12', () {
    final actual = {
      for (final entry in sources.entries)
        if (entry.value.contains('AppStrings')) entry.key,
    };
    expect(actual, _withText);
  });

  test('каждый Cubit из списка, кроме фасада, подписан на смену языка', () {
    for (final path in _withText.difference(_noOwnSubscription)) {
      expect(
        sources[path],
        contains('strings.changes.listen('),
        reason: '$path: Cubit с текстом без подписки на AppStrings.changes',
      );
    }
  });

  test(
    'Cubit-ы страниц II и диалог переноса секретов без AppStrings (D5, D12)',
    () {
      for (final name in const [
        'features/settings/application/mcp_settings_cubit.dart',
        'features/settings/application/agents_modes_cubit.dart',
        'features/settings/application/skills_settings_cubit.dart',
        'features/workbench/application/secret_migration_cubit.dart',
      ]) {
        expect(sources[name], isNotNull, reason: '$name не найден');
        expect(sources[name], isNot(contains('AppStrings')), reason: name);
      }
    },
  );
}
