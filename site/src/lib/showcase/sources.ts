/**
 * Закрытый список источников витрины и чтение строк из них при сборке.
 *
 * Почему: демо, бейджи и факты показывают строки интерфейса и цитаты
 * документов. Набранные руками, они расходятся с продуктом без сигнала; взятые
 * из источника при сборке, они ломают сборку в том pull request, где источник
 * изменился (design.md redesign-site-showcase, D6; project-site «Правдивость
 * витрины»). Источники закрыты списком: исходники Dart (`lib/**\/*.dart`) в него
 * не входят — строки CLI собираются интерполяцией, и подстрока кода не то, что
 * видит пользователь; кроме того, это расширило бы охват джоба `site` на `lib/`
 * приложений. Строка, которой нет ни в каталоге, ни в документе, на витрину не
 * попадает: сначала её документирует `docs-writer`.
 *
 * Для чего: единственное место, где читаются файлы репозитория для витрины.
 * Модуль использует `node:fs`, поэтому его импортирует только frontmatter
 * страниц и компонентов Astro, а в клиентский бандл он не попадает (D11).
 * Клиентскому коду передаются уже готовые строки как данные разметки.
 *
 * Как использовать: `ui(каталог, ключ)`, `quote(документ, текст)`,
 * `snippet('документ#якорь', n)` из frontmatter; корень репозитория — родитель
 * рабочего каталога (`npm run build` запускается в `site/`). Тесты и другие
 * корни — `createShowcaseSources(корень)`. Любое нарушение — `ShowcaseSourceError`
 * с путём источника. Список путей, кроме документов, синхронизирован с охватом
 * CI проверкой `test/ci-scope-sync.test.ts` (D6).
 */
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import type { Code, Heading, Root, RootContent } from 'mdast';
import remarkParse from 'remark-parse';
import { unified } from 'unified';

import { isPublished } from '../publish';

/**
 * Источники витрины, кроме опубликованных документов (их определяет allowlist
 * `publish.ts`, D3).
 *
 * `catalogs` — каталоги локализации, из которых `ui` берёт строки;
 * `assets` — шаблоны изображений: снимки приложений и бренд (D10). Расширять
 * только по задаче, синхронно со спецификацией `project-site` и охватом CI
 * (`_affectsSite` в `tool/ci/ci_scope.dart`).
 */
export const showcaseSources = {
  catalogs: [
    'packages/flutter/codelab_ui/lib/src/l10n/codelab_ui_ru.arb',
    'apps/codelab_desktop/lib/l10n/app_ru.arb',
  ],
  assets: ['apps/*/doc/images/**', 'docs/design/brand/**'],
} as const;

/** Ошибка сборки: источник витрины недоступен, изменён или не входит в список (D6). */
export class ShowcaseSourceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ShowcaseSourceError';
  }
}

/** Строки, цитаты и снимки терминала из источников репозитория. */
export interface ShowcaseSources {
  /** Значение ключа [key] каталога [catalog] (D6, вид `ui`). */
  ui(catalog: string, key: string): string;
  /** Цитата [text] документа [document]; возвращает [text] как написано (вид `quote`). */
  quote(document: string, text: string): string;
  /** [n]-й блок кода (с 1) раздела `документ#якорь` (вид `snippet`). */
  snippet(reference: string, n: number): string;
}

/** Схлопывает любые пробельные подряд в один пробел: перенос строки не меняет смысл цитаты. */
function normalizeSpace(text: string): string {
  return text.replace(/\s+/g, ' ').trim();
}

/** Текст заголовка: обычный текст и код без разметки, как его видит читатель. */
function headingText(node: RootContent): string {
  if (node.type === 'text' || node.type === 'inlineCode') return node.value;
  return 'children' in node ? node.children.map((c) => headingText(c as RootContent)).join('') : '';
}

/**
 * Якорь заголовка по правилу GitHub: строчные буквы, пробелы в дефисы, знаки
 * препинания (кроме `-` и `_`) убраны. Так считают якоря документы
 * (`codelab-docs` §3), а Astro даёт заголовкам те же id (`smartypants: false`
 * в `astro.config.mjs`, D5). Своя функция вместо `github-slugger`: это
 * транзитивная зависимость, а новых в change нет (tasks.md).
 */
function slugOf(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^\p{L}\p{N}\p{M}_\- ]/gu, '')
    .replace(/ /g, '-');
}

/**
 * Создаёт функции чтения источников для корня репозитория [repoRoot].
 *
 * Почему фабрика: тесты работают на мини-репозитории фикстур, а сборка — на
 * настоящем корне (D13).
 */
export function createShowcaseSources(repoRoot: string): ShowcaseSources {
  const read = (path: string): string => {
    try {
      return readFileSync(resolve(repoRoot, path), 'utf8');
    } catch {
      throw new ShowcaseSourceError(`${path}: showcase source cannot be read (D6)`);
    }
  };

  const requireDocument = (path: string): void => {
    if (!isPublished(path)) {
      throw new ShowcaseSourceError(
        `${path}: not a published document, so it is outside showcaseSources (D6)`,
      );
    }
  };

  return {
    ui(catalog, key) {
      if (!(showcaseSources.catalogs as readonly string[]).includes(catalog)) {
        throw new ShowcaseSourceError(`${catalog}: catalog is outside showcaseSources (D6)`);
      }
      const entries = JSON.parse(read(catalog)) as Record<string, unknown>;
      const value = key.startsWith('@') ? undefined : entries[key];
      if (typeof value !== 'string') {
        throw new ShowcaseSourceError(`${catalog}: key ${key} is missing (D6)`);
      }
      return value;
    },

    quote(document, text) {
      requireDocument(document);
      if (!normalizeSpace(read(document)).includes(normalizeSpace(text))) {
        throw new ShowcaseSourceError(`${document}: quote not found: ${text} (D6)`);
      }
      return text;
    },

    snippet(reference, n) {
      const hash = reference.indexOf('#');
      const document = hash === -1 ? reference : reference.slice(0, hash);
      const anchor = hash === -1 ? '' : reference.slice(hash + 1);
      requireDocument(document);
      if (anchor === '') {
        throw new ShowcaseSourceError(`${document}: snippet reference needs an #anchor (D6)`);
      }
      const where = `${document}#${anchor}`;
      if (!Number.isInteger(n) || n < 1) {
        throw new ShowcaseSourceError(`${where}: block number must be 1 or more, got ${n} (D6)`);
      }

      const tree = unified().use(remarkParse).parse(read(document)) as Root;
      // Раздел — от заголовка с якорем до следующего заголовка того же или более
      // высокого уровня; подразделы входят в него (D6).
      const seen = new Map<string, number>();
      let depth: number | undefined;
      const blocks: Code[] = [];
      for (const node of tree.children) {
        if (node.type === 'heading') {
          const heading = node as Heading;
          if (depth !== undefined && heading.depth <= depth) break;
          const base = slugOf(heading.children.map((c) => headingText(c)).join(''));
          const count = seen.get(base) ?? 0;
          seen.set(base, count + 1);
          if (depth === undefined && (count === 0 ? base : `${base}-${count}`) === anchor) {
            depth = heading.depth;
          }
        } else if (depth !== undefined && node.type === 'code') {
          blocks.push(node);
        }
      }
      if (depth === undefined) {
        throw new ShowcaseSourceError(`${where}: section is missing (D6)`);
      }
      const block = blocks[n - 1];
      if (block === undefined) {
        throw new ShowcaseSourceError(
          `${where}: block ${n} is missing, the section has ${blocks.length} (D6)`,
        );
      }
      return block.value;
    },
  };
}

/** Источники настоящего репозитория: корень — родитель каталога `site/`, где идёт сборка. */
export const { ui, quote, snippet } = createShowcaseSources(resolve(process.cwd(), '..'));
