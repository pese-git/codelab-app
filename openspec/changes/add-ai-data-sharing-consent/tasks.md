> Метки исполнителей — по `CLAUDE.md`:
> - `[agent]` — `codelab_agent_core`, `codelab_setup`, `codelab_embedded` (`agent-core-engineer`);
> - `[desktop]` — `apps/codelab_desktop` (`desktop-engineer`);
> - `[client]` — задач на код нет: `codelab_client_core`, `codelab_client_io` и `apps/codelab_cli` не меняются (design.md, D7). Остаётся проверка 12.3;
> - `[protocol]` — задач нет: ACP не меняется.
>
> Документацию пакетов, приложения и политику пишет `docs-writer` — это отмечено в задаче.
>
> Задачи идут парами «тест → реализация», красный тест первым (`packages/dart/codelab_agent_core/AGENTS.md` §2). Красный тест коммитится отдельно до кода, но только по явной просьбе пользователя. Порядок разделов — порядок зависимостей: ядро → мосты → app.

## 0. Документы до кода

- [x] 0.1 `[agent]` `docs/architecture/proposals/agent-core/02-llm-contract.md` — §2.10.6 «Гейт передачи данных провайдеру» и инвариант LLM-17 (D4).
- [x] 0.2 `[desktop]` `docs/architecture/permissions.md` — §59 «Разрешение на передачу данных получателю» (D1–D11).
- [ ] 0.3 `[desktop]` `docs/architecture/l10n-glossary.md` — термины D12: «data sharing» → «передача данных», «Permission to send data» → «Разрешение на отправку данных», «Withdraw» → «Отозвать», «Not now» → «Не сейчас».

## 1. Ядро: декоратор гейта (D4; spec agent-llm «Гейт передачи данных провайдеру»)

- [ ] 1.1 `[agent]` Тест `packages/dart/codelab_agent_core/test/llm/sharing_gate_test.dart`: сценарии «Отказ без HTTP», «Разрешение пропускает поток», «Каждый запрос спрашивает гейт», «Отмена во время ожидания», «Исключение гейта — отказ», «Провайдер без адреса идёт мимо гейта». Плюс контракт LLM-1/LLM-2: поток возвращается синхронно, гейт не вызывается в той же микрозадаче, терминальное событие одно. `FakeClock` и `MockClient`. Красный.
- [ ] 1.2 `[agent]` `ProviderEndpoint` (+ `ProviderEndpoint.of`), `SharingGate`, `withSharingGate` в `lib/src/llm/decorators/sharing_gate.dart`; экспорт из `lib/codelab_agent_core.dart` (`show`); doc-комментарии по-русски (§15). 1.1 зелёный, `web-compile` зелёный.
- [ ] 1.3 `[agent]` Тест: декоратор поверх `withFallback` с цепочкой `a/m → b/m`. Гейт отвечает `true` для `a` и `false` для `b`, `a` отвечает 429 до вывода. Ожидание: гейт вызван для `b`, итог — `badRequest` отказа, HTTP к `b` нет (§2.10.6 п. 1). Красный, если порядок обёрток нарушен; иначе фиксирует поведение.

## 2. Мост настроек: адрес провайдера по умолчанию (spec client-agent-setup «Адрес провайдера модели по умолчанию»)

- [ ] 2.1 `[agent]` Тест `packages/dart/codelab_setup/test/provider/default_provider_endpoint_test.dart`: сценарии «Адрес по умолчанию» и «Нет модели». Снимки настоящего загрузчика во временном `CODELAB_HOME`, секреты не читаются (фейк хранилища без вызовов). Красный.
- [ ] 2.2 `[agent]` `defaultProviderEndpoint(snapshot)` в `lib/src/provider/`; реэкспорт `ProviderEndpoint`, `ProviderApi` из бареля. 2.1 зелёный.

## 3. Мост встроенного агента (spec embedded-agent «Гейт передачи данных встроенного агента»)

- [ ] 3.1 `[agent]` Тесты `packages/dart/codelab_embedded/test/sharing_gate_test.dart` на `scriptedEmbeddedAgentOpener` и тестовом ACP-клиенте: «Отказ гейта во встроенном агенте» (`-32603`, `errorClass: badRequest`, сценарий без вызовов), «Без гейта как раньше», разрешение пропускает ход. Отмена `session/cancel` во время ожидания гейта: ответ `cancelled`, `cancelled` гейта завершён. Красный.
- [ ] 3.2 `[agent]` Тест `embedded_config_reload_test.dart`: «Гейт после перезагрузки конфига» — `providerId: gw2` после перезагрузки; сессия другой папки (D21 `require-project-folder`) тоже идёт через гейт. Красный.
- [ ] 3.3 `[agent]` Поле `EmbeddedHostServices.sharingGate`, параметр `sharingGate` у `localEmbeddedAgentOpener` и `scriptedEmbeddedAgentOpener`. Обёртка в `modelsFor` (`createEmbeddedAgent`) и в сценарном открывателе, `endpointOf` по `CoreConfig` снимка. Реэкспорт `SharingGate`, `ProviderEndpoint`, `ProviderApi` из `lib/codelab_embedded.dart`. 3.1, 3.2 зелёные, `web-compile` и `guard` зелёные.
- [ ] 3.4 `[agent]` `packages/dart/codelab_embedded/AGENTS.md` §1 — поле `sharingGate` и реэкспорт; README пакета — `docs-writer`.

## 4. App: домен получателей (D2, D3, D9; spec app-data-sharing «Получатели и их идентичность», «Модель на этом компьютере без вопроса»)

- [ ] 4.1 `[desktop]` Тест `apps/codelab_desktop/test/features/data_sharing/domain/data_recipient_test.dart`. Нормализация: регистр хоста, порт по умолчанию и нестандартный, IPv6, userinfo, путь и query не входят, `ws`/`wss` — один получатель, stdio — команда как есть. `isLocal`: `localhost`, `127.0.0.1`, `127.5.5.5`, `[::1]` — да; `192.168.1.20`, `0.0.0.0`, `a.localhost` — нет. Внешний агент — никогда не локальный. Красный.
- [ ] 4.2 `[desktop]` Тест кодека документа `data_sharing_document_test.dart`. Круговой проход формата D9. Битый JSON, чужая `version`, не строка — «нет разрешений» с признаком `invalid`. Запись неизвестного вида и неполная запись пропускаются. `disclosure` ≠ `kDataSharingDisclosure` — запись не действует. Сценарий licensing-and-attribution «Разрешение без ссылки на редакцию документов». Красный.
- [ ] 4.3 `[desktop]` `lib/features/data_sharing/domain/`: `DataRecipient` (`provider`, `agent`), `DataSharingGrant`, `kDataSharingDisclosure = 1`, кодек. 4.1, 4.2 зелёные.

## 5. App: порт хранилища (D9; spec app-data-sharing «Хранение разрешений и версия раскрытия»)

- [ ] 5.1 `[desktop]` Тест `apps/codelab_desktop/test/core/platform/data_sharing_preferences_test.dart` по образцу `onboarding_preferences`: чтение без ключа, строка, не строка (`"yes"` не перезаписывается), исключение чтения — имя типа без текста; запись полного документа. Красный.
- [ ] 5.2 `[desktop]` `lib/core/platform/data_sharing_preferences.dart`: порт `DataSharingPreferences` и `SharedPreferencesDataSharingPreferences` (шов `open`). 5.1 зелёный.

## 6. App: `DataSharingCubit` (D8, D9, D11; spec app-data-sharing «Гейт встроенного агента app», «Вопрос, очередь и диалог», «Отмена ожидания вопроса», «Отзыв разрешения», «События журнала разрешений без адресов»)

- [ ] 6.1 `[desktop]` Тесты `test/features/data_sharing/application/data_sharing_cubit_test.dart`. Покрывают:
  - ожидание чтения хранилища (гейт не отвечает до конца чтения);
  - локальный провайдер — `true` без очереди;
  - действующее разрешение — `true`;
  - слияние двух запросов одного получателя — один вопрос, одно `data_sharing.requested`;
  - FIFO двух получателей;
  - `allow` → запись и `true` всем;
  - `deny` → `false` всем, без записи;
  - отмена одного из двух ожидающих — вопрос остаётся; отмена всех — `request_dropped`, поздний ответ игнорируется;
  - `close()` — `false` всем;
  - сбой чтения и битое значение — fail closed и события;
  - сбой записи выдачи — разрешение в памяти и `save_failed {op: grant}`;
  - отзыв — сразу в памяти, сбой записи — `WithdrawNotSaved` и повтор;
  - записи не накладываются;
  - смена `kDataSharingDisclosure` — повторный вопрос;
  - журнал без `*-marker` («Полный цикл без утечек»).

  Фейки хранилища и часов, синхронизация событиями. Красный.
- [ ] 6.2 `[desktop]` `lib/features/data_sharing/application/data_sharing_cubit.dart`: состояние D8 (закрытые иерархии, без россыпи `bool`), `requestProvider`, `requestAgent`, `allow`, `deny`, `withdraw`, `retrySave`, поток отзывов по получателю, логгер `codelab_desktop.data_sharing`. 6.1 зелёный.

## 7. App: гейт внешнего агента (D5; spec app-data-sharing «Гейт внешнего ACP-агента», «Отзыв разрешения»)

- [ ] 7.1 `[desktop]` Тест `test/features/data_sharing/application/sharing_gated_transport_resolver_test.dart`. Фабрики транспорта — фейки. Отказ — фабрика не вызвана, `DataSharingDeniedException`. Разрешение — транспорт открыт. `embedded` — обёртка не вмешивается. Отзыв получателя закрывает обёрнутый транспорт, отзыв другого получателя — нет. Через `ClientWorkspace` с `FakeAcpTransport`: отказ даёт `ConnectionFailed` с `Data sharing with this agent is not allowed.`, отзыв — `ConnectionLost`, `reconnect` снова спрашивает. Красный.
- [ ] 7.2 `[desktop]` `SharingGatedTransportResolver` и обёртка `AcpTransport`, `DataSharingDeniedException`. 7.1 зелёный.

## 8. App: проводка (D4, D5, D7)

- [ ] 8.1 `[desktop]` Тест `test/app/app_scope_data_sharing_test.dart`. App scope регистрирует один `DataSharingCubit` на процесс. `localEmbeddedAgentOpener` получает `sharingGate`, который зовёт Cubit. Резолвер профилей `stdio`/`webSocket` обёрнут, резолвер `embedded` — нет. Закрытие root scope закрывает Cubit после агента. Красный.
- [ ] 8.2 `[desktop]` Проводка в `lib/app/app_scope.dart` и `embedded_transport_resolver.dart` (cherrypick-модуль, генерация `*.cherrypick.g.dart`). 8.1 зелёный.
- [ ] 8.3 `[desktop]` Тестовая сборка app scope (`test/support/`) по умолчанию выдаёт разрешение на сценарного провайдера фейком хранилища. Существующие тесты рабочего места не видят диалога; тесты разделов 9–11 включают настоящий Cubit. Прогон `fvm flutter test` app зелёный.

## 9. App: диалог (D10, D12; spec app-data-sharing «Вопрос, очередь и диалог», «Гейт встроенного агента app»)

- [ ] 9.1 `[desktop]` Тесты виджета `test/features/data_sharing/presentation/data_sharing_dialog_test.dart`. Тексты провайдера и агента на `en` и `ru`. Фокус на `data-sharing-deny`, Esc — отказ, `Allow` — разрешение. Очередь двух получателей. Закрытие диалога при `request_dropped`. Диалог поверх настроек, нет диалога на onboarding. Красный.
- [ ] 9.2 `[desktop]` Интеграционный тест app на Dart VM (`scriptedEmbeddedAgentOpener`, настоящий Cubit). Сценарии «Первый промпт после onboarding без разрешения», «Разрешение и продолжение хода», «Отказ и повтор», «Субагент с другим провайдером», «Отмена хода во время диалога», «Провайдер без ключа не спрашивается», «Локальная модель». HTTP-клиент считает запросы. Красный.
- [ ] 9.3 `[desktop]` `lib/features/data_sharing/presentation/data_sharing_dialog.dart` и его хост уровня app (слушает очередь Cubit; решение — только вызов `allow`/`deny`). 9.1, 9.2 зелёные.

## 10. App: onboarding (D10; spec app-onboarding «Шаг «Privacy»», «Разрешение на передачу данных на шаге «Privacy»», «События журнала onboarding без секретов и путей»)

- [ ] 10.1 `[desktop]` Тест `test/app/onboarding_probe_test.dart`: `sharingCandidate()` — удалённый провайдер (через `defaultProviderEndpoint`), локальный, внешний профиль без чтения конфига, `NoCandidate` при пустом `CODELAB_HOME`, битом конфиге, таймауте. Красный.
- [ ] 10.2 `[desktop]` `OnboardingProbe.sharingCandidate()` и закрытая иерархия кандидатов. 10.1 зелёный.
- [ ] 10.3 `[desktop]` Тесты Cubit onboarding и виджета шага: все сценарии требования «Разрешение на передачу данных на шаге «Privacy»»; изменённые сценарии «Нечего принимать» и «Полный проход без утечек»; поле `sharing` в `onboarding.completed`; новый заголовок InfoBar; Enter под открытым документом не выдаёт разрешения. Красный.
- [ ] 10.4 `[desktop]` Карточка `onboarding-privacy-sharing` в `onboarding_steps.dart`, состояние кандидата в Cubit onboarding, вызов `DataSharingCubit.allow` с `from: onboarding`. 10.3 зелёный.

## 11. App: строка «Data sharing» в настройках (spec app-settings «Строка «Data sharing» страницы «General»», «Страница «General»: состав и порядок», «Страница «Legal»: видимость и вкладки»)

- [ ] 11.1 `[desktop]` Тесты страницы «General». Порядок блоков с `settings-general-data-sharing`. Сценарии «Список и отзыв», «Пусто», «Русский интерфейс», InfoBar `unreadable` и `not-saved` с «Try again». Обновление строки, когда разрешение выдано диалогом. Поиск `data sharing` / `передача данных`. На «Legal» нет переключателя разрешения. Красный.
- [ ] 11.2 `[desktop]` Строка в блоке «Privacy» страницы «General», ключевые слова поиска. 11.1 зелёный.

## 12. Локализация и проверки затронутого

- [ ] 12.1 `[desktop]` Строки D12 в `app_en.arb` и `app_ru.arb` (новое значение `onboardingNothingToAgreeTitle`), генерация `gen-l10n`; `melos run l10n:check` зелёный.
- [ ] 12.2 `[agent]` Проверки затронутого (AGENTS.md §21): `fvm dart format`, `fvm dart analyze` и `fvm dart test` в `codelab_agent_core`, `codelab_setup`, `codelab_embedded`; `melos run guard`, `melos run web-compile`, `melos run conformance:embedded`, `melos run conformance:agent`.
- [ ] 12.3 `[client]` Регрессия CLI без изменений кода: `melos run test:e2e:cli:embedded` и `melos run test:e2e:cli:dart-agent` зелёные (D7: CLI не передаёт гейт).
- [ ] 12.4 `[desktop]` `fvm dart format`, `fvm flutter analyze`, `fvm flutter test` в `apps/codelab_desktop`; `legal_assets_test.dart` зелёный после 13.1.
- [ ] 12.5 `openspec validate add-ai-data-sharing-consent --strict` зелёный.

## 13. Документация (`docs-writer`, D14)

- [ ] 13.1 `PRIVACY.md` и `PRIVACY.ru.md`: абзацы §3 и §6 по D14 и требованию licensing-and-attribution, новая дата редакции в обоих файлах, побайтные копии в `apps/codelab_desktop/assets/legal/`. Слов `I agree`, `accept these terms`, `Принимаю` нет. `fvm dart test test/legal_documents_test.dart` в `codelab_architecture_tests` и `legal_assets_test.dart` app зелёные.
- [ ] 13.2 README `packages/dart/codelab_embedded` и `packages/dart/codelab_setup` — `sharingGate`, `defaultProviderEndpoint`, реэкспорт.
- [ ] 13.3 `apps/codelab_desktop/README.md` и `doc/` — onboarding (карточка разрешения), диалог, строка «Data sharing», журнал `codelab_desktop.data_sharing`. Если опубликованные документы изменились и есть Node — `cd site && npm ci && npm run verify`.
