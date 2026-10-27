## 1. Ядро клиента: строка инструмента

- [ ] 1.1 `ToolCallView`: поля `rawInput`, `paths`, `textOutput`; проекция в `TranscriptProjector` из `content` и `locations` вызова; свойство «инкрементально = с нуля» на корпусе фикстур остаётся зелёным
- [ ] 1.2 `ToolRowView` и `ToolRowFormatter.format(item, cwd:)` по §12.1.6 без времени (design D2): метки по виду, правила детали, относительный путь, URL без схемы и query, управляющие символы, `SecretRedactor`, 160 символов, `title` как запасная деталь, вторая строка у `failed`
- [ ] 1.3 Тесты форматтера: примеры из спецификации и таблицы §12.1.6 (кроме времени и `Task`), секрет в `command`, путь вне `cwd`, пустая деталь

## 2. codelab_ui: модель строк и виджеты

- [ ] 2.1 `CodeLabTranscriptRow` и наследники `CodeLabUserRow`, `CodeLabAgentTextRow`, `CodeLabThoughtRow`, `CodeLabToolCallRow`, `CodeLabNoticeRow` (design D1); `CodeLabTranscriptEntryAction` → `CodeLabTranscriptAction`; удалить `CodeLabTranscriptEntry` и `CodeLabTranscriptEntryKind`
- [ ] 2.2 `CodeLabTranscriptPanel` на строках: колонка по центру до 760 px без рамки, `ListView.builder` с `ValueKey(row.id)`, `expansionOverrides` и `onExpansionChanged`, раскрытие по умолчанию по таблице D3; следование за хвостом и автопрокрутка к одобрению без изменений
- [ ] 2.3 Пузырь пользователя (до 78 %, в `narrow`/`phone` до 90 %) и строка ответа агента без карточки
- [ ] 2.4 `CodeLabThoughtBlock`: «Thinking…» с `ProgressRing` во время стрима, «Thoughts» после, приглушённый текст как есть, раскрытие без анимации
- [ ] 2.5 `CodeLabToolCallRow`: значок статуса, метка, деталь, тег статуса и «Awaiting approval», шеврон; раскрытие — вторая строка и текстовый вывод моноширинным
- [ ] 2.6 Карточка одобрения по design D5: заголовок по виду, тег «Awaiting approval», риск тегом, терминальный блок команды с `cwd`, `allow_once` главной кнопкой; тег исхода после решения
- [ ] 2.7 `CodeLabNoticeRow` по design D6: InfoBar ошибки с Details и Retry, InfoBar предупреждения, нейтральная строка
- [ ] 2.8 Чип состояния хода в `CodeLabSessionPaneHeader`
- [ ] 2.9 Превью всех строк в светлой и тёмной теме; widget-тесты строк и раскрытия по таблице D3

## 3. Desktop: маппинг и состояние

- [ ] 3.1 Маппер строк в `ui_mappers.dart` вместо `transcriptEntriesOf`: строки из `TranscriptItem`, `ToolRowFormatter` с `cwd` сессии, «стримящиеся» мысли (design D4), «Awaiting approval», тяжесть заметок; тесты маппера
- [ ] 3.2 `TranscriptViewCubit`: `expansionOverrides` по сессиям, переключение строки; unit-тесты
- [ ] 3.3 `main_pane.dart`: лента на строках, пустая сессия при `connected` вместо `CodeLabConnectionScreen`, чип хода в шапке из `SessionView.status` и ожидающих одобрений

## 4. Перенос тестов

- [ ] 4.1 Widget-тесты `apps/codelab_desktop`: перевести поиск по «You»/«Agent» и ключам записей на ключи `transcript-row-<id>` и новые виджеты; ожидания поведения (одобрения, сочетания, автопрокрутка, Retry) не меняются
- [ ] 4.2 E2e `integration_test/`: те же замены; проверка компиляцией и `melos run check` (запуск на устройстве — только в `release/*`, §21)
- [ ] 4.3 Widget-тесты сценариев спецификации: переписка без подписей, колонка 760 px при 1200 px, мысли во время стрима и после, выбор пользователя переживает прокрутку, строки Read/Run, карточка «Run a command?», нейтральная заметка, пустая сессия при соединении, чип хода

## 5. Проверка

- [ ] 5.1 `fvm dart format`, `fvm exec melos analyze`
- [ ] 5.2 `fvm exec melos run check`
- [ ] 5.3 Ручная проверка сборки macOS на сценарии `--llm-script` с мыслями, ответом, чтением, командой с одобрением и сбоем хода; скриншоты рядом с артбордами Main и Turn в отчёте сверки
