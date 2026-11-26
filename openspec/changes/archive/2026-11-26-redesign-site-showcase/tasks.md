Задачи с логикой идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2): сначала красный тест, затем код. В скобках — требование спецификации `project-site` и сценарий, решение design.md (D-n).

Метки исполнителей:
- `[site]` — `site-engineer`: `site/**`, ветка сайта в `tool/ci/ci_scope.dart` с тестами в `packages/dart/codelab_architecture_tests/test/ci_scope_test.dart`;
- `[docs-writer]` — проверка фактов витрины и правки опубликованных документов (`apps/*/doc/`, `docs/user/`);
- `[orchestrator]` — `.claude/skills/codelab-site/SKILL.md`, только после одобрения change;
- `[protocol]`, `[agent]`, `[client]`, `[desktop]` — задач нет: пакеты и приложения workspace, ACP и граф зависимостей не меняются.

Порядок: 1 → 2 → 3 → 4 → 5 → 6 → 7. Задача 1.3 идёт параллельно с 2–3. Один PR в `develop` из `feature/redesign-site-showcase`.

Проверки — только затронутого (`AGENTS.md` §21):
- `cd site && npm ci && npm run verify` и `SITE_BASE=/codelab-app/ npm run verify`; для D10 — ещё `SITE_URL=https://example.org SITE_BASE=/codelab-app/ npm run verify`;
- `fvm dart format --set-exit-if-changed tool/ci/ci_scope.dart packages/dart/codelab_architecture_tests/test/ci_scope_test.dart`;
- `fvm dart analyze tool/ci packages/dart/codelab_architecture_tests` из корня;
- `fvm dart test packages/dart/codelab_architecture_tests/test/ci_scope_test.dart`;
- `openspec validate redesign-site-showcase --strict`;
- conformance, `web-compile`, e2e CLI, `guard` не нужны: Dart-код продуктов, `pubspec.yaml` и импорты между пакетами не меняются;
- `test:e2e:app:*` не запускается. Полный `melos run check` — только по просьбе пользователя.

## 1. Источники витрины и охват CI

- [x] 1.1 `[site]` Красные тесты `site/test/sources.test.ts` (project-site «Правдивость витрины»: «Строка кнопки из каталога», «Удалённый ключ ломает сборку», «Переформулированный документ ломает сборку», «Источник вне списка»; D6) на фикстурах в `site/test/fixtures/showcase/`:
  - `ui(каталог, ключ)` — значение ключа;
  - нет ключа — ошибка с путём каталога и ключом; каталог вне `showcaseSources` — ошибка;
  - `quote(документ, текст)` — совпадение с нормализацией пробелов и переводов строк; нет совпадения — ошибка с путём и цитатой;
  - `snippet(документ#якорь, n)` — n-й блок кода раздела до следующего заголовка того же или более высокого уровня; нет раздела или блока — ошибка;
  - документ не из allowlist `publish.ts` — ошибка.
- [x] 1.2 `[site]` `site/src/lib/showcase/sources.ts`: константа `showcaseSources`, функции `ui`, `quote`, `snippet`. Разбор раздела — тем же `remark-parse`, что в тестах плагинов, без новой зависимости. Doc-комментарии по `AGENTS.md` §15 со ссылкой на D6: почему источники закрыты списком и почему Dart-исходники в него не входят. 1.1 зелёный.
- [x] 1.3 `[docs-writer]` Если вкладке `codelab` (D4) нужен вид блока одобрения: текстовый снимок блока одобрения построчного режима в `apps/codelab_cli/doc/user/02-repl.md#разрешения` на месте маркера `screenshot`. Снимок — с тестовой модели (`--llm-script`) или живого провайдера, маскировка по `codelab-docs` §7. Если снимок снять нельзя, вкладка остаётся на таблице клавиш (D4), а задача закрывается с причиной.
- [x] 1.4 `[site]` Красные тесты в `packages/dart/codelab_architecture_tests/test/ci_scope_test.dart` (project-site «Проверка сайта в CI»: «Изменение каталога локализации запускает джоб сайта», «Изменение бренда запускает джоб сайта»; D6):
  - только `packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_ru.arb` → `site == true`, матрица как сейчас;
  - только `apps/codelab_desktop/lib/l10n/app_ru.arb` → `site == true`, матрица как сейчас;
  - только `docs/design/brand/codelab-logo.svg` → `site == true`, `jobs` пусты;
  - только `packages/flutter/codelab_ui/lib/src/widgets/x.dart` → `site == false`.
- [x] 1.5 `[site]` `tool/ci/ci_scope.dart`: `_affectsSite` учитывает файлы `*.arb` в `codelab_ui` и `codelab_desktop` (константа `_siteL10nDirs`, без `_isL10nFile`: тот ловит ещё `pubspec.yaml`, `l10n.yaml` и сгенерированный код); `docs/design/brand/**` уже в охвате через `docs/**` (D6). Doc-комментарий — ссылка на D6 этого change. 1.4 зелёный.
- [x] 1.6 `[site]` Красный тест `site/test/ci-scope-sync.test.ts` (D6, «Охват CI»): каждый путь `showcaseSources`, кроме опубликованных документов, покрыт списком шаблонов охвата сайта. Список шаблонов в тесте — тот же, что проверяет Dart-тест из 1.4; комментарий в обоих тестах ссылается друг на друга. Затем — правка `showcaseSources`, если тест красный.

## 2. Проверка собранного сайта

- [x] 2.1 `[site]` Красные тесты в `site/test/check-links.test.ts` на мини-`dist/` (project-site «Интерактивные демо витрины»: «Второй встроенный скрипт ломает проверку», «Превышение бюджета»; «Мета-данные страниц и знак сайта»: «Картинка неверного размера»; D12):
  - два встроенных `<script>` на странице → ошибка; один, но разный текст на двух страницах → ошибка;
  - атрибут `onclick` у любого элемента → ошибка;
  - модули демо страницы больше 12 КБ gzip → ошибка с размером; модули темы и mermaid в сумму не входят;
  - `og:image` указывает на отсутствующий файл, не-PNG или PNG 1200×631 → ошибка; PNG 1200×630 → без ошибки.
- [x] 2.2 `[site]` `site/scripts/check-links.mjs`: правила D12 (только `node:` модули). Модули темы и mermaid — по манифесту чанков `site/.astro/build-chunks.json` от плагина `site/src/plugins/build-chunks.ts` (тест `site/test/build-chunks.test.ts`), а не по имени чанка; без файла CLI падает с просьбой собрать сайт (D12 п. 3). 2.1 зелёный.
- [x] 2.3 `[site]` `site/astro.config.mjs`: `vite.build.assetsInlineLimit` в форме функции — `0` для скриптов, прежний порог для остального (D2 п. 2). Комментарий — почему: хэш CSP одного встроенного скрипта. Проверка: `npm run build`, в `dist/index.html` один встроенный скрипт, `check-links` зелёный.

## 3. Автоматы демо

- [x] 3.1 `[site]` Красные тесты `site/test/workbench-demo.test.ts` (project-site «Интерактивные демо витрины»: «Посетитель разрешает правку», «Посетитель отклоняет правку», «Автопроигрывание не отвечает за посетителя», «Повторное нажатие после исхода», «Уменьшение движения»; D3, R4). Планировщик — фальшивый, время двигает тест:
  - автопроигрывание `idle → prompt → streaming → awaiting` и остановка на `awaiting` при любом прошедшем времени;
  - `allow` и `reject` из `awaiting` — свой исход; повторный ответ после исхода состояние не меняет;
  - `reduce` — переходы без промежуточных состояний печати и без таймеров;
  - пауза отменяет запланированный таймер; продолжение не дублирует его;
  - «Ещё раз» из `done` → `idle`, старые таймеры не срабатывают.
- [x] 3.2 `[site]` `site/src/lib/showcase/workbench-demo.ts` — без `document`, планировщик передаётся снаружи. 3.1 зелёный.
- [x] 3.3 `[site]` Красные тесты `site/test/steps.test.ts` («Ручной выбор шага останавливает автопроигрывание», «Уменьшение движения»; D5): шаг 6 секунд, по кругу; ручной выбор останавливает автопроигрывание; пауза и продолжение; невидимость останавливает; `reduce` — без автопроигрывания.
- [x] 3.4 `[site]` `site/src/lib/showcase/steps.ts` — автомат и данные четырёх шагов с `docRef` (D5). 3.3 зелёный.
- [x] 3.5 `[site]` Красные тесты `site/test/modes-demo.test.ts` («Переформулированный документ ломает сборку»; D5, D6): строки таблицы режимов из фикстуры → ячейки «без вопроса», «вопрос», «запрещена без вопроса»; неизвестный режим или изменённая строка → ошибка из `quote`.
- [x] 3.6 `[site]` `site/src/lib/showcase/modes-demo.ts` поверх `quote` из 1.2. 3.5 зелёный.
- [x] 3.7 `[site]` Красный тест `site/test/showcase-data.test.ts` («Шаг без ссылки на документ», «Пример помечен»; D6, D7): у каждого шага, факта и демо есть `docRef` на опубликованный документ (`isPublished`); каждый сценарий с `example` имеет подпись примера; в фактах нет слов из запретного списка skill §2.
- [x] 3.8 `[site]` `site/src/lib/showcase/scenarios.ts` (сценарий D3 и три представления D4) и `facts.ts` (D7, D8): строки — `ui`, `quote`, `snippet`, `example`; ограничения D8 — в тех же записях. 3.7 зелёный.

## 4. Компоненты и страницы

- [x] 4.1 `[site]` `site/src/components/showcase/Workbench.astro` и `src/scripts/showcase/workbench.ts` (D3): разметка без JavaScript — лента до карточки и оба исхода текстом, кнопки с `hidden`; скрипт ставит `data-live`, связывает автомат 3.2, `aria-live="polite"` для исхода, `IntersectionObserver`, пауза при наведении и фокусе, кнопка «Пауза» / «Продолжить». Каркас — по смыслу `Main.dc.html` и `Turn.dc.html`, свёрстан токенами; код артбордов не копируется. Подпись «Схема рабочего места; ответ модели и файл — пример».
- [x] 4.2 `[site]` `ClientSwitcher.astro` и скрипт (D4): вкладки WAI-ARIA (стрелки, Home, End), представления app, `codelab` и Zed. Без JavaScript — три представления подряд с заголовками. Вкладка Zed — схема без интерфейса Zed, ссылка на `docs/user/zed.md` и оговорка о непроверенном примере.
- [x] 4.3 `[site]` `HowItWorks.astro` и скрипт (D5): нумерованный список без JavaScript; вкладки и автопроигрывание поверх 3.4; иллюстрации — снимки `apps/codelab_desktop/doc/images/` через `astro:assets`.
- [x] 4.4 `[site]` `ModesDemo.astro`, `CliKeysDemo.astro` и скрипты (D5): без JavaScript — таблицы; с ним — вкладки режимов и кнопки `<kbd>`. Клавиши перехватываются только при фокусе внутри демо.
- [x] 4.5 `[site]` `Trust.astro` (D8): четыре пункта из `facts.ts` с ограничениями и ссылками. `Badges.astro` и плашка версии (D7): последняя новость из `src/lib/news.ts`; без новостей — ничего.
- [x] 4.6 `[site]` `Gallery.astro` (D9): вкладки «Приложение» и «Терминал». Снимки — через `astro:assets`, ниже первого экрана — `loading="lazy"`, ссылка на полный размер. Терминал — `snippet` текстом. Подпись о языке снимков. Без JavaScript — обе группы подряд.
- [x] 4.7 `[site]` `site/src/pages/index.astro` — секции D1 по порядку (project-site «Разделы сайта»: «Порядок секций главной», «Плашки версии нет без выпусков»). Текст первого экрана и возможностей — черновик для 6.1.
- [x] 4.8 `[site]` `features/app.astro` — макет 4.1 в начале страницы; `features/cli.astro` — 4.4 (клавиши); `features/agent.astro` — 4.4 (режимы). Список `Feature` сохраняется.
- [x] 4.9 `[site]` Стили демо — только токены `tokens.css`; новые пары цвет/фон проверены на контраст WCAG AA в обеих темах (skill §7). Анимации — только `opacity` и `transform`, под `@media (prefers-reduced-motion: no-preference)`.

## 5. Мета-данные и знак

- [x] 5.1 `[site]` `site/src/pages/og.png.ts` (D10): PNG 1200×630 из SVG бренда через `getImage` `astro:assets`. Если сервис изображений не растеризует SVG — запасной путь D10, с причиной в отчёте задачи. Проверка — правило 2.2 и сценарий «Картинка неверного размера». Сделано без запасного пути: `getImage` не растеризует SVG без `dangerouslyProcessSVG`, поэтому endpoint вызывает сервис изображений Astro (`getConfiguredImageService`) напрямую с этим флагом только для своих вызовов (`src/lib/raster-svg.ts`); `site/public/` не нужен.
- [x] 5.2 `[site]` `BaseLayout.astro`: мета-теги D10; `og:url`, `og:image`, `twitter:image` — только при `SITE_URL`; favicon из `docs/design/brand/launcher/web-favicon.svg`, `apple-touch-icon` 180×180 через `astro:assets`. `Header.astro`: логотип `codelab-logo.svg` и `codelab-logo-dark.svg` по теме вместо «CL». Сценарии «Мета-теги без SITE_URL», «Мета-теги с SITE_URL», «Favicon без копии» — сборкой при обоих вариантах окружения и просмотром `dist/`.
- [x] 5.3 `[site]` Тест `site/test/og-card.test.ts` («цвета плашки совпадают с токенами светлой темы»; D10): светлые значения `--mica` и `--accent` из `tokens.css` равны hex-константам `og-card.ts`; затем — экспорт констант `ogPlaqueColor`, `ogAccentColor` из `og-card.ts`, если тест красный.

## 6. Проверка фактов и ручная приёмка

- [x] 6.1 `[docs-writer]` Проверка фактов витрины по `codelab-docs` §8 (project-site «Разделы сайта», «Правдивость витрины», «Блок «Ваш код и ключи»»): каждый шаг, бейдж, факт и пункт доверия сверен с документом по `docRef`; ограничения D8 названы; пример не создаёт ложного впечатления; нет обещаний и оценочных слов. Отчёт — список правок; правки вносит `site-engineer` (6.3).
- [ ] 6.2 `[site]` Ручной чек-лист в Chrome и Safari, светлая и тёмная системные темы, широкий и узкий экран (project-site «Интерактивные демо витрины»: «Без JavaScript», «Клавиатура», «Уменьшение движения»; D13):
  - всё демо проходится клавиатурой, фокус виден;
  - VoiceOver объявляет исход разрешения и выбранный режим, но не каждый символ;
  - с `prefers-reduced-motion: reduce` нет автопроигрывания и печати;
  - без JavaScript видно полное состояние и нет мёртвых кнопок;
  - автопроигрывание останавливается вне экрана, при наведении и фокусе;
  - в инструментах разработчика нет запросов к чужим хостам.

  Результат — в описании PR.

  **Статус при архивации (2026-11-26): выполнена частично, change архивирован по решению пользователя.** Проверено во встроенном браузере (Chromium), светлая и тёмная темы, ширина 375 и 1280: клавиатура и вкладки, фокус после ответа и после «Ещё раз», объявление исхода через `aria-live`, остановка автопроигрывания при наведении и выборе шага, нет запросов к чужим хостам, нет атрибутов `on*`, один встроенный скрипт. Без JavaScript — исполнитель в headless Chrome. Не проверено: Safari (в том числе `aria-disabled` у «Пауза» и `light-dark()`), VoiceOver, `prefers-reduced-motion: reduce` вручную (покрыто тестами автоматов). Подробности — описание PR pese-git/codelab-app#543.
- [x] 6.3 `[site]` Правки по отчёту 6.1 и замечаниям 6.2; `npm run verify` при `SITE_BASE=/` и `/codelab-app/`, а также с `SITE_URL`.

## 7. Стандарт сайта

- [x] 7.1 `[orchestrator]` `.claude/skills/codelab-site/SKILL.md` после одобрения change (D14):
  - §1 — структура главной (D1);
  - §2 — таблица видов строк D6, подпись примера, ограничения рядом с гарантиями (D8), запрет изображать чужие интерфейсы (D4); пункт «снимки терминала не копируются» заменён правилом `snippet`;
  - §6 — правило скриптов D2 вместо «скриптов два», бюджет 12 КБ;
  - §7 — движение, вкладки, `aria-live`, без JavaScript;
  - §9 — пункты: источники демо и `showcaseSources`, синхронность с `_affectsSite`, проверки D12, ручной чек-лист 6.2.

  Ссылка на design.md этого change (после архивирования — путь архива).
