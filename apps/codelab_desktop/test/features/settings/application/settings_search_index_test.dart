// Ключевые слова поиска настроек в ARB (задача 6.4 change
// `add-app-general-page`; решение пользователя 2026-11-19, design.md D15;
// spec app-settings «Навигация настроек» change `add-desktop-localization`).
//
// Реализация — задача 6.5: слова живут в каталогах, статического списка в
// `SettingsSearchIndex` нет.
//
// Правило: слова языка интерфейса и английские находят страницу, слова другого
// языка — нет. Слова читаются из файлов каталогов (см.
// `test/support/settings_search.dart`), а поиск — той же функцией
// `SettingsSearchIndex.search`, что вызывает оболочка.

import 'package:codelab_desktop/app/default_settings_pages.dart';
import 'package:codelab_desktop/app/navigation/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/settings_search.dart';

/// Прежние английские слова страниц (до переноса в ARB): они обязаны находить
/// свою страницу на обоих языках интерфейса.
const _english = <SettingsPage, List<String>>{
  SettingsPage.connection: [
    'profile',
    'stdio',
    'websocket',
    'token',
    'restart',
  ],
  SettingsPage.providers: [
    'provider',
    'model',
    'api key',
    'key storage',
    'base url',
  ],
  SettingsPage.mcpServers: ['mcp', 'server', 'tools', 'headers'],
  SettingsPage.agentsAndModes: [
    'mode',
    'permission',
    'bypass',
    'plan',
    'effort',
    'reasoning',
    'agent',
    'definition',
    'subagent',
  ],
  SettingsPage.skillsAndExtensions: [
    'skill',
    'agents.md',
    'context',
    'template',
    'prompt',
    'extension',
  ],
  SettingsPage.general: [
    'language',
    'budget',
    'steps',
    'compaction',
    'subagent',
    'log level',
    'startup',
    'reopen',
    'ignored',
    'about',
    'version',
    'license',
    'diagnostics',
  ],
};

final _visible = defaultSettingsPages.visible;

bool _cyrillic(String word) => RegExp(r'[А-Яа-яЁё]').hasMatch(word);

void main() {
  group('сообщения в каталогах', () {
    for (final locale in ['en', 'ru']) {
      for (final page in _visible) {
        test('settingsSearchKeywords${settingsKeywordsSuffixOf(page)} '
            'есть в app_$locale.arb, слов не меньше одного, пустых нет', () {
          final message = settingsKeywordsMessageOf(locale, page);

          expect(message, isNotNull, reason: '${page.slug} в app_$locale.arb');
          final words = settingsKeywordsOf(locale, page);
          expect(words, isNotEmpty, reason: page.slug);
          for (final word in words) {
            expect(word, isNotEmpty, reason: '${page.slug}: пустое слово');
          }
        });
      }
    }

    test('русские слова — кириллица, английские — без неё', () {
      for (final page in _visible) {
        final ru = settingsKeywordsOf('ru', page);
        final en = settingsKeywordsOf('en', page);
        expect(ru, isNotEmpty, reason: page.slug);
        expect(en, isNotEmpty, reason: page.slug);
        expect(ru.where(_cyrillic), isNotEmpty, reason: page.slug);
        expect(en.where(_cyrillic), isEmpty, reason: page.slug);
      }
    });
  });

  group('английские слова на обоих языках интерфейса', () {
    _english.forEach((page, words) {
      for (final word in words) {
        for (final locale in ['en', 'ru']) {
          test('«$word» при $locale находит ${page.slug}', () {
            expect(
              searchSettings(_visible, word, locale: locale),
              contains(page),
            );
          });
        }
      }
    });

    test('слова одной страницы не находят General: restart, token, '
        'profile', () {
      for (final locale in ['en', 'ru']) {
        for (final word in ['restart', 'token', 'profile']) {
          expect(
            searchSettings(_visible, word, locale: locale),
            isNot(contains(SettingsPage.general)),
            reason: '$word при $locale',
          );
        }
      }
    });
  });

  group('русские слова только на русском интерфейсе', () {
    test('при русском интерфейсе каждое русское слово находит свою '
        'страницу', () {
      for (final page in _visible) {
        expect(settingsKeywordsOf('ru', page), isNotEmpty, reason: page.slug);
        for (final word in settingsKeywordsOf('ru', page).where(_cyrillic)) {
          expect(
            searchSettings(_visible, word, locale: 'ru'),
            contains(page),
            reason: '«$word» → ${page.slug}',
          );
        }
      }
    });

    test('при английском интерфейсе ни одно русское слово страницу не '
        'находит', () {
      for (final page in _visible) {
        expect(settingsKeywordsOf('ru', page), isNotEmpty, reason: page.slug);
        for (final word in settingsKeywordsOf('ru', page).where(_cyrillic)) {
          expect(
            searchSettings(_visible, word, locale: 'en'),
            isEmpty,
            reason: '«$word» (${page.slug}) при английском интерфейсе',
          );
        }
      }
    });

    test('сценарии spec: токен и сжатие', () {
      expect(searchSettings(_visible, 'токен', locale: 'ru'), [
        SettingsPage.connection,
      ]);
      expect(searchSettings(_visible, 'token', locale: 'ru'), [
        SettingsPage.connection,
      ]);
      expect(searchSettings(_visible, 'токен', locale: 'en'), isEmpty);
      expect(searchSettings(_visible, 'сжатие', locale: 'ru'), [
        SettingsPage.general,
      ]);
      expect(searchSettings(_visible, 'сжатие', locale: 'en'), isEmpty);
    });
  });
}
