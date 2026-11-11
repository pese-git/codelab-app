# Third-party notices

Реестр фрагментов, которые близко воспроизводят внешний алгоритм, список или таблицу (`docs/architecture/proposals/dart-agent-and-clients/07-decision-sources.md` §7а). Сторонний код в репозиторий не копируется; запись нужна, когда реализация повторяет конкретный внешний фрагмент. Ссылка на публичную спецификацию (ACP, JSON-RPC 2.0, MCP, SSE, API провайдеров) записи не требует.

Зависимости с pub.dev сюда не вносятся: их лицензии проверяются при добавлении (`AGENTS.md` §4). Исключение — шрифты, которые зависимость кладёт в сборку приложения с собственной лицензией, отличной от лицензии пакета: для них запись обязательна (`openspec/changes/add-desktop-markdown/design.md`, D10).

## Формат записи

```markdown
### <Название источника>

- **URL:** <ссылка на исходный код или документ>
- **Лицензия:** <SPDX-идентификатор, например MIT, BSD-3-Clause, Apache-2.0>
- **Что воспроизведено:** <алгоритм, список или таблица — одной строкой>
- **Файлы:** `<путь>`, `<путь>`
- **Уведомление:**

  > <текст уведомления об авторском праве из источника>
```

Лицензия источника должна быть совместима с MIT (MIT, BSD, Apache-2.0); copyleft-код (GPL, AGPL, LGPL) и код без подтверждённой лицензии не воспроизводятся.

## Записи

### JetBrains Mono (шрифт в пакете `gpt_markdown`)

- **URL:** https://github.com/JetBrains/JetBrainsMono
- **Лицензия:** OFL-1.1 (SIL Open Font License, Version 1.1; https://scripts.sil.org/OFL)
- **Что воспроизведено:** шрифт `JetBrainsMono-Regular.ttf` (версия 2.304) распространяется в сборке desktop без изменений как ресурс пакета `gpt_markdown` 1.4.1 (`lib/fonts/`); код блоков и встроенного кода в ленте использует его как запасной моноширинный. Файла лицензии в пакете нет, лицензия подтверждена записью `name` (ID 13) самого файла шрифта.
- **Файлы:** ресурс пакета `gpt_markdown` (в репозиторий не копируется), в сборке — `packages/flutter/codelab_ui`, `apps/codelab_desktop`
- **Уведомление:**

  > Copyright 2020 The JetBrains Mono Project Authors (https://github.com/JetBrains/JetBrainsMono)
  >
  > This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is available with a FAQ at: https://scripts.sil.org/OFL

### Latin Modern (шрифты в пакете `val_latex_flutter`)

- **URL:** http://www.gust.org.pl/projects/e-foundry/latin-modern
- **Лицензия:** GUST Font License (на основе LaTeX Project Public License 1.3c; http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt)
- **Что воспроизведено:** шрифты `lmroman10`, `lmsans10`, `lmmono10`, `lmromancaps10` (OTF) распространяются в сборке desktop без изменений как ресурс пакета `val_latex_flutter` 0.1.4 (`fonts/latin-modern/`) для `\text{…}` в формулах LaTeX. Полный текст лицензии лежит в пакете (`GUST-FONT-LICENSE.txt`).
- **Файлы:** ресурс пакета `val_latex_flutter` (в репозиторий не копируется), в сборке — `packages/flutter/codelab_ui`, `apps/codelab_desktop`
- **Уведомление:**

  > Copyright 2003, 2009 B. Jackowski and J. M. Nowacki (on behalf of TeX users groups). This work is released under the GUST Font License -- see http://tug.org/fonts/licenses/GUST-FONT-LICENSE.txt for details.
