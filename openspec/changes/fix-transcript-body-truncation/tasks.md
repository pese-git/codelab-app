## 1. AcpTranscriptPanel

- [ ] 1.1 В `_AcpTranscriptEntryRow` (`packages/flutter/acp_ui/lib/src/organisms/acp_transcript_panel.dart`) применять `maxLines: _bodyMaxLines`/`overflow: TextOverflow.ellipsis` к `entry.body` только для `AcpTranscriptEntryKind.toolCall`; для `user`/`agent`/`approval`/`diagnostic` рендерить `body` без ограничения по числу строк
- [ ] 1.2 Убедиться, что `title`/`timestampLabel` продолжают обрезаться (`maxLines: 1`/`ellipsis`) без изменений — это метки, не содержательный текст
- [ ] 1.3 Убедиться, что детализация `AcpToolCallSummary`/`_toolCallForMode` по `viewMode` не затронута

## 2. Тесты

- [ ] 2.1 Widget-тест в `packages/flutter/acp_ui/test/acp_organisms_test.dart`: длинный `body` у записи `kind: agent` (много строк, превышающих текущий `_bodyMaxLines` в normal/summary/verbose режимах) рендерится полностью, без `TextOverflow.ellipsis`
- [ ] 2.2 Widget-тест: то же для `kind: user`, `kind: approval`, `kind: diagnostic`
- [ ] 2.3 Widget-тест: запись `kind: toolCall` с длинным `body` по-прежнему обрезается по `_bodyMaxLines` (регрессионная проверка на то, что мы сузили исключение только до нужных kind, а не убрали ограничение полностью)
- [ ] 2.4 Прогнать существующие тесты `acp_organisms_test.dart` и `apps/codelab_app/test/widget_test.dart` — убедиться, что ни один не полагался на прежнее усечение

## 3. Проверка

- [ ] 3.1 `fvm dart run melos run format`
- [ ] 3.2 `fvm dart run melos run analyze`
- [ ] 3.3 `fvm dart run melos run test`
