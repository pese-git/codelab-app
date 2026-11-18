Задачи с логикой идут парами «тест → реализация» (TDD, `packages/dart/codelab_agent_core/AGENTS.md` §2). Сначала красный тест, затем код. В скобках — требование спецификации `project-site` и сценарий или решение `design.md`. Красный тест коммитится отдельно до кода; коммит — только по просьбе пользователя. Страницы и оформление без ветвлений проверяются сборкой (`astro check`, `astro build`, `check:links`) и ручным чек-листом 4.9 (D14).

Метки исполнителей:
- `[site]` — `site-engineer`: `site/**`, джоб `site` в `.github/workflows/ci.yml`, ветка сайта в `tool/ci/ci_scope.dart` и `tool/ci/affected.dart` с тестами в `packages/dart/codelab_architecture_tests/test/ci_scope_test.dart`, строки `site/` в `.gitignore` и `analysis_options.yaml` (D15). Пока агента нет (группа 0), задачи `[site]` выполняет оркестратор через агента общего назначения по этому же описанию зоны;
- `[orchestrator]` — оркестратор сам: `.claude/`, `CLAUDE.md`, `AGENTS.md`, корневой `README.md`. Это вне зон исполнителей; правка `AGENTS.md` — только после одобрения пользователем этого change;
- `[docs-writer]` — правки опубликованных документов (`docs/user/`, `docs/ops/`, `apps/*/README.md`, `apps/*/doc/`);
- `[architect]` — `codelab-architect`: `docs/architecture/`;
- `[protocol]`, `[agent]`, `[client]`, `[desktop]` — задач нет: пакеты и приложения workspace, ACP и граф зависимостей не меняются.

Порядок: 0 → 1 и 2 параллельно → 3 → 4 → 5 → 6 → 7. Группа 6 частично может идти параллельно с 3–4. Один PR в `develop` из `feature/add-astro-site`.

Проверки — только затронутого (`AGENTS.md` §21):
- `npm run verify` в `site/`;
- `fvm dart format --set-exit-if-changed tool/ci/ci_scope.dart tool/ci/affected.dart packages/dart/codelab_architecture_tests/test/ci_scope_test.dart`;
- `fvm dart analyze tool/ci packages/dart/codelab_architecture_tests` из корня;
- `fvm dart test packages/dart/codelab_architecture_tests/test/ci_scope_test.dart`;
- `fvm dart run melos run guard` — меняются `analysis_options.yaml` и правила охвата;
- `openspec validate add-astro-site --strict`;
- conformance, `web-compile`, e2e CLI не нужны: Dart-код продуктов не меняется;
- `test:e2e:app:*` — не запускается. Полный `melos run check` — только по просьбе пользователя.

## 0. Команда и правила до реализации `[orchestrator]`

- [x] 0.1 `[orchestrator]` `.claude/skills/codelab-site/SKILL.md` по D15 (девять разделов). Токены D8 — с источником каждого значения (`docs/design/claude-design/fluent.css`, `Main.dc.html`, `Appearance.dc.html`, `codelab_ui/lib/src/atomics/codelab_text.dart`). Язык и проверка фактов — ссылкой на `codelab-docs` §4 и §8, без пересказа. Последний раздел — чек-лист ревью сайта.
- [x] 0.2 `[orchestrator]` `.claude/agents/site-engineer.md` по образцу `desktop-engineer.md`: описание с меткой `[site]`, зона и запреты D15, обязательное чтение (skill `codelab-site`, ADR-0003, этот change, `AGENTS.md` §2, §4, §5, §13, §19, §21), TDD (vitest и `ci_scope_test.dart`), проверка (`npm run verify`; `fvm dart test …/ci_scope_test.dart` при правке `tool/ci/`), отчёт без `git commit`. Bash: `npm ci`, `npm run …`, `npx astro …` в `site/`; запрещены `npm install <пакет>` без задачи `tasks.md`, `npm publish`, сетевые запросы, кроме реестра npm.
- [x] 0.3 `[orchestrator]` `CLAUDE.md`: строка `site-engineer` в таблице агентов (зона — `site/`, CI сайта; пишет код — да); в «Процесс» — метка `[site]` в списке меток. `.claude/commands/change.md` и `implement.md`: `[site]` → **site-engineer** в списках меток.
- [x] 0.4 `[orchestrator]` `.claude/agents/architecture-reviewer.md`: в чек-листе — пункт «Сайт: для изменений `site/**` — чек-лист `.claude/skills/codelab-site/SKILL.md`». `.claude/agents/check-runner.md`: шаг `npm run verify` в `site/` — если изменён `site/**`; если изменены опубликованные документы (D3) и установлен Node; иначе «НЕ ЗАПУСКАЛСЯ: нет Node» (D13).

## 1. Охват CI `[site]`

- [x] 1.1 `[site]` Красные тесты в `packages/dart/codelab_architecture_tests/test/ci_scope_test.dart` (project-site «Проверка сайта в CI», все сценарии; D13):
  - только `site/src/pages/index.astro` → `site == true`, `jobs` пусты, `full == false`;
  - только `site/.nvmrc` или `site/package-lock.json` → то же: не «вне пакетов»;
  - только `docs/user/configuration.md` → `site == true`, `jobs` пусты;
  - `apps/codelab_cli/doc/user-guide.md` → `site == true`, а матрица — как сейчас (файл пакета `codelab_cli`);
  - `packages/dart/codelab_setup/README.md` → `site == true`, `jobs` пусты;
  - только `packages/dart/codelab_agent_core/lib/src/…` → `site == false`, матрица прежняя;
  - только `openspec/specs/x/spec.md` или перенос `openspec/changes/<id>/…` в `openspec/changes/archive/…` → `site == true`, `jobs` пусты (D13, ответ на Q6);
  - только `.claude/agents/x.md` или корневой `CHANGELOG.md` → `site == false`, `jobs` пусты;
  - `fullReason` задан или файл вне пакетов (`.github/workflows/ci.yml`) → `site == true` и `fullJobs`.
- [x] 1.2 `[site]` `tool/ci/ci_scope.dart`: поле `CiScope.site`, функция `_affectsSite` рядом с `_isDocumentation`, префикс `site/` не попадает в `outside`. Doc-комментарии по `AGENTS.md` §15 со ссылкой на D13 и ADR-0003; doc-комментарий библиотеки и `ciScope` дополнены вторым измерением охвата. `tool/ci/affected.dart`: `site=<true|false>` в `$GITHUB_OUTPUT`, строка `site: yes/no` в summary. 1.1 зелёный.

## 2. Каркас `site/` `[site]`

- [x] 2.1 `[site]` `site/.nvmrc` (точная LTS), `.npmrc` (D1), `package.json` (`private`, `type: module`, `engines.node`, скрипты D1, точные версии D2), `package-lock.json`, `astro.config.mjs` (`SITE_URL`, `SITE_BASE`, `trailingSlash: 'always'`, `build.format: 'directory'`, `vite.server.fs.allow` на корень репозитория; D3, D4, D12), `tsconfig.json` (строгий профиль Astro), `src/site.config.ts` (`repoUrl`; `repoRef` — `SITE_GITHUB_REF`, иначе `GITHUB_SHA`, иначе `git rev-parse HEAD`, иначе ошибка сборки; D5). Лицензии прямых и транзитивных зависимостей проверены по D2; итог — в отчёте задачи.
- [x] 2.2 `[site]` Проверка `npm ci --ignore-scripts` + `npm run build` на пустом сайте (одна страница). Если зависимости нужен install-скрипт — исключение и причина в skill `codelab-site` (D2), шаг `npm rebuild <пакет>` — в задаче 5.1.
- [x] 2.3 `[site]` Проверка точных версий в `verify` (сценарий «Диапазон версии отклоняется»): красный тест vitest на функцию разбора `package.json` (диапазоны `^`, `~`, `*`, `x`, `>=`; теги `latest`), затем функция в `src/lib/` и вызов из `verify`.
- [x] 2.4 `[site]` Корень: `.gitignore` — `site/node_modules/`, `site/dist/`, `site/.astro/`; `analysis_options.yaml` — `site/**` в `analyzer.exclude` (D1). С установленным `site/node_modules` выполнить `fvm dart run melos run guard`, `fvm dart run melos run check-format`, `fvm dart analyze` из корня (project-site «Сайт вне pub workspace и Melos», сценарии «Сторож не видит сайт», «Dart-проверки не обходят сайт»). В отчёте — время `check-format` с `site/node_modules` и без (R9).

## 3. Логика сайта по TDD `[site]`

- [ ] 3.1 `[site]` Красные тесты `site/test/urls.test.ts`, `publish.test.ts`, `nav.test.ts` (project-site «Публикуемые источники документации» — все сценарии; «Разделы сайта» — «Документ попадает в группу по расположению»; «Конфигурация под будущий хостинг»; D3, D4, D9, D12): таблица D4 при `base` `/` и `/codelab-app/`; каждый шаблон allowlist, `AGENTS.md` в `doc/`, `docs/architecture/**`, `docs/backlog/**`, `openspec/**`, `docs/integrations/**`; группы D9 и неизвестный каталог приложения.
- [ ] 3.2 `[site]` `src/lib/urls.ts` (`pageUrl`, `withBase`), `src/lib/publish.ts` (allowlist — одна константа), `src/lib/nav.ts`. 3.1 зелёный.
- [ ] 3.3 `[site]` Красные тесты `site/test/repo-links.test.ts` (project-site «Перевод относительных ссылок документации», все сценарии; D5) на виртуальном репозитории во временном каталоге: опубликованный файл с якорем и без; `README.md` → адрес каталога; неопубликованный файл → `blob`; каталог → `tree`; изображение остаётся относительным; пустой `alt` → ошибка; несуществующий файл, выход за корень, `/abs`, `C:\…`, `file:` → ошибка с путём документа и строкой; другой регистр имени → ошибка; `http:`, `https:`, `mailto:`, `#якорь` не меняются; ссылки-определения (`[x]: path`) обрабатываются так же. Отдельно — выбор `repoRef` (сценарии «Ссылка на GitHub ведёт на коммит сборки», «Цель ссылок задана явно»): `SITE_GITHUB_REF` важнее `GITHUB_SHA`, `GITHUB_SHA` важнее `HEAD`, без всех трёх — ошибка.
- [ ] 3.4 `[site]` `src/plugins/repo-links.ts`. Комментарии — почему точный регистр и почему коммит сборки по умолчанию (D5). 3.3 зелёный.
- [ ] 3.5 `[site]` Красные тесты `site/test/mermaid-blocks.test.ts` (project-site «Mermaid-схемы в браузере», «Без JavaScript»; D7): блок `mermaid` → узел дерева (не сырой HTML) `pre.mermaid-source[data-mermaid]`, исходник — текстом внутри `pre`, в HTML экранированы `<`, `>`, `&`; блоки других языков и блок без языка не меняются.
- [ ] 3.6 `[site]` `src/plugins/mermaid-blocks.ts`. 3.5 зелёный.
- [ ] 3.7 `[site]` Красные тесты `site/test/raw-html-guard.test.ts` и `home-paths.test.ts` (project-site «Безопасность публикации», все сценарии; D11): `<script>`, `<iframe>`, `<style>`, `<img onerror>`, `<div>` → ошибка с позицией; `details`, `summary`, `br`, `kbd`, `sub`, `sup` без атрибутов и `<details open>` проходят; `<kbd onclick=…>`, `<details class=…>` → ошибка с позицией; блок mermaid после плагина 3.6 проходит; комментарий удалён; `/Users/alice/…`, `/home/bob/…`, `C:\Users\eve\…` в тексте и в блоке кода → ошибка; `/home/me/…`, `/Users/user/…`, `~/.codelab` проходят.
- [ ] 3.8 `[site]` `src/plugins/raw-html-guard.ts` и проверка путей (`src/plugins/home-paths.ts`; маски — константа в `src/lib/`). 3.7 зелёный.
- [ ] 3.9 `[site]` Красные тесты `site/test/news.test.ts` (project-site «Новости выпусков», сценарии «Повтор версии», «Новостей нет»; D10): дубликат версии → ошибка с обоими путями; порядок по дате и версии; пустой список.
- [ ] 3.10 `[site]` `src/lib/news.ts`. 3.9 зелёный.
- [ ] 3.11 `[site]` Красные тесты `site/test/check-links.test.ts` (project-site «Проверка внутренних ссылок собранного сайта», все сценарии; «Сборка под подкаталог»; «Нет сторонних запросов»; D6, D11, D14) на мини-`dist/` во временном каталоге: существующая страница; `…/` → `index.html`; отсутствующий файл; отсутствующий `id`; ссылка без `base` при непустом `base` → ошибка; внешняя `<a href="https://…">` не проверяется; `<script src="https://…">`, `<link href="https://…">`, `<img src="https://…">` → ошибка; личный путь в тексте → ошибка; ожидаемые страницы из allowlist отсутствуют → ошибка; код `elkjs` в файле `dist/` → ошибка с именем файла (D2, D7).
- [ ] 3.12 `[site]` `scripts/check-links.mjs` (только `node:` модули). 3.11 зелёный.

## 4. Коллекции, страницы, оформление `[site]`

- [ ] 4.1 `[site]` `src/content.config.ts`: коллекция `docs` (загрузчик `glob` с базой в корне репозитория, шаблоны из `src/lib/publish.ts`; заголовок — первый `#`, без него — ошибка с путём; описание — первый абзац; D3) и коллекция `news` со схемой D10. Конвейер unified задан явно: `@astrojs/markdown-remark` (точная версия, MIT; D2) и `markdown.processor: unified({ remarkPlugins, rehypePlugins })` с плагинами 3.x; предупреждений об устаревших `markdown.remarkPlugins` в сборке нет. `astro build` на настоящих документах проходит (project-site «Публикуемые источники документации», «Страница собирается из файла репозитория», «Документ без заголовка» — проверить, временно убрав заголовок у копии в тестовом каталоге, а не в репозитории).
- [ ] 4.2 `[site]` `src/styles/tokens.css` (D8, токены skill `codelab-site`), базовые стили, `shiki-light.json` и `shiki-dark.json` из `--syn-*` и `--code-*`, двойная тема Shiki в `astro.config.mjs`.
- [ ] 4.3 `[site]` Макет: шапка (логотип, меню «Возможности», «Установка», «Документация», «Новости», переключатель темы), подвал (лицензия MIT со ссылкой на `LICENSE` на GitHub, ссылка на репозиторий), ссылка «к содержанию», `lang="ru"`. Встроенный скрипт темы в `<head>` и `src/scripts/theme.ts` с событием `codelab-theme-change` (project-site «Оформление и темы»; D8).
- [ ] 4.4 `[site]` `src/scripts/mermaid.ts` (D7): ленивый `import('mermaid')` только при `[data-mermaid]`, `securityLevel: 'strict'`, перерисовка по `codelab-theme-change`, сообщение об ошибке синтаксиса. Раскладка ELK не регистрируется, чанк `elkjs` в `dist/` не попадает (при необходимости — заглушка в `vite.resolve.alias`; D2, D7).
- [ ] 4.5 `[site]` Страницы документации: `/docs/` — оглавление по группам D9; `/docs/[...path]/` — документ с навигацией группы, оглавлением страницы по `##` и ссылкой «Исходный файл на GitHub» (`blob/<repoRef>/<путь>`).
- [ ] 4.6 `[site]` Главная и `/features/app/`, `/features/cli/`, `/features/agent/` по D9 и skill `codelab-site`. Снимки — из `apps/codelab_desktop/doc/images/` через `astro:assets`, без копий. Для CLI — текстовые снимки нельзя копировать из документов («один факт — одно место»): страница возможностей ссылается на разделы руководства. Тексты — черновик для задачи 7.2.
- [ ] 4.7 `[site]` `/news/`, `/news/[version]/`, блок последних новостей на главной, пустое состояние (project-site «Новости выпусков»). Пример новости — только в фикстуре тестов, не в `src/content/news/`.
- [ ] 4.8 `[site]` `404.astro`. `npm run verify` проходит при `SITE_BASE=/` и `SITE_BASE=/codelab-app/`.
- [ ] 4.9 `[site]` Ручная проверка в Chrome и Safari (D14). Результат — в отчёте задачи, по пунктам: светлая и тёмная системная тема без вспышки; переключатель и его сохранение между страницами; схемы `apps/codelab_desktop/doc/development.md` в обеих темах и перерисовка при переключении; страница без схем не грузит чанк mermaid (вкладка Network); с отключённым JavaScript виден исходный текст схемы; во вкладке Network нет запросов к чужим хостам; навигация с клавиатуры и видимый фокус; контраст текста в обеих темах (DevTools). Проверку выполняет пользователь или оркестратор на машине с браузером; `site-engineer` даёт команду `npm run preview`.

## 5. Джоб CI `[site]`

- [ ] 5.1 `[site]` `.github/workflows/ci.yml`: выход `site` у джоба `scope` (`outputs.site: ${{ steps.scope.outputs.site }}`), джоб `site` по D13 (`working-directory: site`, `setup-node` с `node-version-file: site/.nvmrc` и кэшем по `site/package-lock.json`, `npm ci --ignore-scripts`, `npm run verify`, `SITE_BASE=/codelab-app/`, `ASTRO_TELEMETRY_DISABLED=1`, `timeout-minutes: 15`). Комментарий над джобом — как у соседних джобов: почему отдельный, почему без публикации, ссылка на ADR-0003 и D13.
- [ ] 5.2 `[site]` Проверка на pull request: правка только `site/` → только `scope`, `site`, `ci`; правка `docs/user/…` → то же; правка пакета без документации → `site` пропущен. В отчёте — время джоба `site` (R4).
- [ ] 5.3 `[site]` `site` в `needs` итогового джоба `ci`, проверка `success|skipped` и строка `site=…` в `echo`, как у `checks` (project-site «Проверка сайта в CI», сценарии «Красный site блокирует merge», «Пропущенный site не блокирует merge»; testing-quality «Непрерывная интеграция», «Сайт в CI»; D13). Комментарий над `ci` обновлён: обязательный статус по-прежнему один — `ci`. Проверка на pull request: красный `site` при зелёных Dart-джобах даёт красный `ci`.

## 6. Правила документации и выпуска `[orchestrator]`

- [ ] 6.1 `[orchestrator]` `.claude/skills/codelab-docs/SKILL.md`. В §3 правило ссылок вместо строки «Ссылки — относительные пути, проверяемые…»: только относительные пути к существующим файлам и каталогам с точным регистром; без абсолютных путей и адресов GitHub на файлы этого репозитория; якорь опубликованного документа существует; HTML — только `details`, `summary`, `br`, `kbd`, `sub`, `sup` без атрибутов (кроме `open` у `details`). Там же абзац: документы из allowlist (D3) публикуются на сайте, нарушение делает джоб `site` красным. В §7 — маски путей `user` и `me` (D11). В §9 — локальная проверка `npm run verify` в `site/`, если установлен Node.
- [ ] 6.2 `[orchestrator]` `.claude/agents/docs-writer.md`: зона записи + `site/src/content/news/**`; раздел «Новость выпуска» (когда — в `release/<version>` после раздела `CHANGELOG.md`; по skill `codelab-site` и D10; факты — раздел выпуска `CHANGELOG.md` и `proposal.md` архивированных changes выпуска; `CHANGELOG.md` агент читает, но не пишет); в «Порядок работы», п. 5 — правило ссылок 6.1.
- [ ] 6.3 `[orchestrator]` `AGENTS.md`:
  - §5 — `site/` в дереве; правило: «`site/` — сайт на Astro (ADR-0003), вне pub workspace и Melos; Node и npm — только в `site/`; сторож его не проверяет»;
  - §21 — пункт «`npm run verify` в `site/` — если изменён `site/**`; СЛЕДУЕТ — если изменены опубликованные документы»; уточнение «Изменение только документации…»: правка опубликованных документов проверяется ещё и джобом `site`;
  - §22 — в строке `release/<version>`: «версия, раздел выпуска в `CHANGELOG.md`, новость на сайте (`site/src/content/news/`), …»; пункт чек-листа выпуска: сначала раздел `CHANGELOG.md`, затем новость `docs-writer` из него и архива changes выпуска (D10).
- [ ] 6.4 `[orchestrator]` Корневой `README.md`: строка `site/` в таблице «Структура» («сайт CodeLab на Astro: главная, возможности, документация из `docs/` и `apps/*/doc/`, новости; вне pub workspace», ссылка на ADR-0003). Граф зависимостей не меняется. `README-claude-team.md`: число субагентов и `site-engineer` в списке моделей (`sonnet`).
- [ ] 6.5 `[orchestrator]` Корневой `CHANGELOG.md` (D10): заголовок и описание формата на русском — разделы `## <version> — YYYY-MM-DD` от нового к старому, подразделы «Добавлено», «Изменено», «Исправлено», «Удалено», «Безопасность» (пустые не пишутся), пункт — одна строка о видимом изменении со ссылкой на архив change; ведётся в `release/<version>`; на сайте не публикуется, новость ссылается на него. Разделов выпусков пока нет. Ссылка на `CHANGELOG.md` — в корневом `README.md` рядом с разделом «Лицензия».

## 7. Документы и тексты

- [ ] 7.1 `[docs-writer]` Исправить опубликованные документы, на которых падает `npm run verify` (D5, D11; R7). Только места, указанные сборкой; формулировки не переписываются. Если исправлять нечего — отметка в отчёте.
- [ ] 7.2 `[docs-writer]` Проверка фактов текстов главной и страниц возможностей (4.6) по `codelab-docs` §8 и тону skill `codelab-site`. Правки текстов в `site/src/pages/` — через `site-engineer` по отчёту `docs-writer`: зона `docs-writer` не включает страницы сайта.
- [ ] 7.3 `[architect]` `docs/architecture/testing.md` §74: строка `site` в схеме уровней CI, абзац о признаке `site` в `ci_scope.dart` и о том, что правка только `site/` не запускает Dart-джобы. Джоб обязательный: его ждёт итоговый `ci`; охват включает `openspec/**`.
- [ ] 7.4 `[orchestrator]` `openspec validate add-astro-site --strict`; сверка `tasks.md` с реализацией; вопросы этапа хостинга H1–H3 перенесены в proposal следующего change. После одобрения change пользователем — `Status: Accepted` в ADR-0003, в реестре `docs/architecture/adr/README.md` и в `technology-stack.md` §28.
