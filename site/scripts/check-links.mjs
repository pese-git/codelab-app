// Проверка собранного сайта: внутренние ссылки, якоря, сторонние ресурсы,
// личные пути и код `elkjs` в `dist/`.
//
// Почему: плагин `repoLinks` не видит якорей других документов и ссылок
// страниц сайта, а сетевые проверки недетерминированы (design.md
// add-astro-site, D6). Вторая линия защиты D11 (личные пути) и проверка
// лицензий D2 (`elkjs` не попадает в `dist/`) — здесь же.
//
// Для чего: последний шаг проверки после `astro build`; только модули `node:`
// и собственные модули сайта из `src/lib/` (allowlist и маски личных путей
// существуют в одном месте, D3, D11).
//
// Как использовать: `checkDist({ dist, base, expectedPages })` возвращает
// список нарушений (пустой — всё в порядке). Запуск скриптом —
// `node scripts/check-links.mjs` из `site/` после `astro build`: `base` берётся
// из `SITE_BASE` так же, как в `astro.config.mjs`, ожидаемые страницы
// выводятся из allowlist по файлам репозитория (D14); код выхода 1 и список
// «файл: ссылка — описание» при нарушениях. Модули `.ts` импортируются
// напрямую: Node из `.nvmrc` снимает типы сам, без сборки.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

import { findHomePaths } from '../src/lib/home-paths.ts';
import { isPublished, publishRoots } from '../src/lib/publish.ts';
import { pageUrl } from '../src/lib/urls.ts';

/**
 * Нарушение проверки: файл сборки (путь от `dist/`), ссылка, если есть, и
 * описание.
 *
 * @typedef {{ file: string, link?: string, message: string }} LinkProblem
 */

/** Текстовые файлы сборки, в которых ищутся личные пути и код `elkjs`. */
const textExtensions = new Set(['.html', '.js', '.mjs', '.css', '.json', '.txt', '.xml', '.svg', '.map']);

/**
 * Признак кода `elkjs`: идентификаторы алгоритмов ELK есть в каждой сборке
 * библиотеки и не встречаются в `mermaid` без раскладки ELK (D2, D7).
 */
const elkMarker = 'org.eclipse.elk';

/** Атрибуты тега со ссылками: `href`, `src`, `srcset`. */
const linkAttribute = /\s(href|src|srcset)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi;
const idAttribute = /\sid\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi;
const relAttribute = /\srel\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/i;
// Теги целиком; значения атрибутов в кавычках могут содержать `>`.
const tagPattern = /<([A-Za-z][A-Za-z0-9-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*\/?>/g;

/**
 * Ссылки `<link rel>`, которые указывают на сам сайт по абсолютному адресу и
 * браузер не загружает как ресурс: `canonical` появляется при `SITE_URL` (D12).
 */
const nonFetchingRel = new Set(['canonical', 'alternate', 'author', 'license', 'me']);

/** Декодирует ссылки на символы HTML, которые Astro пишет в атрибутах. */
function decodeEntities(value) {
  return value
    .replace(/&#x([0-9a-f]+);/gi, (_, hex) => String.fromCodePoint(parseInt(hex, 16)))
    .replace(/&#(\d+);/g, (_, dec) => String.fromCodePoint(Number(dec)))
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');
}

function safeDecode(value) {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

/** Все файлы каталога [dir] рекурсивно, пути от [dir] с прямыми слэшами. */
function walk(dir, prefix = '') {
  const result = [];
  for (const entry of readdirSync(join(dir, prefix), { withFileTypes: true })) {
    const path = prefix === '' ? entry.name : `${prefix}/${entry.name}`;
    if (entry.isDirectory()) result.push(...walk(dir, path));
    else if (entry.isFile()) result.push(path);
  }
  return result;
}

/** Значение атрибута из результата регулярного выражения с тремя видами кавычек. */
function attrValue(match, from) {
  return decodeEntities(match[from] ?? match[from + 1] ?? match[from + 2] ?? '');
}

/**
 * @param {{ dist: string, base: string, expectedPages?: readonly string[] }} options
 * @returns {LinkProblem[]}
 */
export function checkDist({ dist, base, expectedPages = [] }) {
  /** @type {LinkProblem[]} */
  const problems = [];
  const files = walk(dist).sort();
  /** @type {Map<string, string>} */
  const html = new Map();
  for (const file of files) {
    if (extname(file) === '.html') html.set(file, readFileSync(join(dist, file), 'utf8'));
  }
  /** @type {Map<string, Set<string>>} */
  const idsCache = new Map();
  const idsOf = (file) => {
    let ids = idsCache.get(file);
    if (!ids) {
      const content = html.get(file) ?? '';
      ids = new Set([...content.matchAll(idAttribute)].map((m) => attrValue(m, 1)));
      idsCache.set(file, ids);
    }
    return ids;
  };

  /** Файл `dist/` по пути адреса после `base`; `undefined`, если его нет. */
  const resolveFile = (sitePath) => {
    const path = sitePath === '' || sitePath.endsWith('/') ? `${sitePath}index.html` : sitePath;
    const full = join(dist, path);
    return existsSync(full) && statSync(full).isFile() ? path : undefined;
  };

  for (const [file, content] of html) {
    // Адрес страницы нужен, чтобы разрешать относительные ссылки так же, как браузер.
    const pageDir = file.includes('/') ? file.slice(0, file.lastIndexOf('/') + 1) : '';
    const pageUrlOf = `http://site.invalid${base}${pageDir}`;

    for (const tag of content.matchAll(tagPattern)) {
      const tagName = tag[1].toLowerCase();
      const attrs = tag[2] ?? '';
      const relMatch = relAttribute.exec(attrs);
      const rel = relMatch ? attrValue(relMatch, 1).toLowerCase().split(/\s+/) : [];

      for (const attr of attrs.matchAll(linkAttribute)) {
        const name = attr[1].toLowerCase();
        const value = attrValue(attr, 2).trim();
        const links =
          name === 'srcset'
            ? value.split(',').map((candidate) => candidate.trim().split(/\s+/)[0] ?? '').filter(Boolean)
            : [value];
        for (const link of links) {
          const problem = checkLink({ tagName, rel, link, file, pageUrlOf });
          if (problem) problems.push({ file, link, message: problem });
        }
      }
    }
  }

  /**
   * Проверка одной ссылки страницы; описание нарушения или `undefined`.
   */
  function checkLink({ tagName, rel, link, file, pageUrlOf }) {
    if (link === '') return undefined;
    const external = link.startsWith('//') || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(link);
    if (external) {
      // Переход по ссылке `<a>` — решение читателя, а не запрос страницы;
      // внешние адреса не запрашиваются (D6).
      if (tagName === 'a') return undefined;
      if (link.startsWith('data:')) return undefined;
      if (tagName === 'link' && rel.some((r) => nonFetchingRel.has(r))) return undefined;
      return `third-party resource <${tagName}> is not allowed: the site must not request other hosts (D2, D8)`;
    }
    if (link.startsWith('#')) {
      const anchor = safeDecode(link.slice(1));
      if (anchor !== '' && !idsOf(file).has(anchor)) return `anchor #${anchor} is missing on the page`;
      return undefined;
    }

    const url = new URL(link, pageUrlOf);
    if (!url.pathname.startsWith(base)) {
      return `internal link does not start with base ${base}: build it with withBase() (D12)`;
    }
    const sitePath = safeDecode(url.pathname.slice(base.length));
    const target = resolveFile(sitePath);
    if (target === undefined) return 'target file does not exist in dist/';
    const anchor = safeDecode(url.hash.slice(1));
    if (anchor !== '' && extname(target) === '.html' && !idsOf(target).has(anchor)) {
      return `anchor #${anchor} is missing on the target page`;
    }
    return undefined;
  }

  for (const page of expectedPages) {
    const sitePath = page.startsWith(base) ? page.slice(base.length) : page;
    const target = resolveFile(safeDecode(sitePath));
    if (target === undefined) {
      problems.push({
        file: sitePath === '' || sitePath.endsWith('/') ? `${sitePath}index.html` : sitePath,
        message: `expected page ${page} from the publish allowlist is missing (D3, D14)`,
      });
    }
  }

  for (const file of files) {
    if (!textExtensions.has(extname(file))) continue;
    const content = html.get(file) ?? readFileSync(join(dist, file), 'utf8');
    for (const found of findHomePaths(content)) {
      problems.push({
        file,
        message: `personal home directory path "${found.path}": mask the user name as "user" or "me" (D11)`,
      });
    }
    if (content.includes(elkMarker)) {
      problems.push({
        file,
        message: 'elkjs code found: its license (EPL-2.0 OR GPL-3.0) is not allowed in dist/ (D2, D7)',
      });
    }
  }

  return problems;
}

/** Приводит `SITE_BASE` к виду `/…/` — так же, как `astro.config.mjs` (D12). */
function normalizeBase(raw) {
  const trimmed = (raw ?? '').trim().replace(/^\/+|\/+$/g, '');
  return trimmed === '' ? '/' : `/${trimmed}/`;
}

/** Каталоги, которые не содержат документов и не обходятся. */
const skippedDirs = new Set(['node_modules', '.dart_tool', 'build', '.git', '.fvm']);

/**
 * Адреса страниц всех опубликованных документов репозитория: обходятся только
 * корни шаблонов allowlist, отбор — `isPublished` (D3, D14).
 */
export function expectedPagesFromRepo(repoRoot, base) {
  const pages = [];
  const visitDir = (dir) => {
    for (const entry of readdirSync(join(repoRoot, dir), { withFileTypes: true })) {
      const path = `${dir}/${entry.name}`;
      if (entry.isDirectory()) {
        if (!skippedDirs.has(entry.name)) visitDir(path);
      } else if (entry.isFile() && isPublished(path)) {
        pages.push(pageUrl(path, base));
      }
    }
  };
  for (const root of publishRoots()) {
    if (existsSync(join(repoRoot, root))) visitDir(root);
  }
  return pages.sort();
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const siteRoot = fileURLToPath(new URL('..', import.meta.url));
  const repoRoot = join(siteRoot, '..');
  const dist = join(siteRoot, 'dist');
  const base = normalizeBase(process.env.SITE_BASE);
  if (!existsSync(dist)) {
    console.error(`${relative(process.cwd(), dist) || 'dist'}: not found, run astro build first.`);
    process.exit(1);
  }
  const problems = checkDist({ dist, base, expectedPages: expectedPagesFromRepo(repoRoot, base) });
  if (problems.length > 0) {
    console.error(`dist/: ${problems.length} problem(s) (D6):`);
    for (const { file, link, message } of problems) {
      console.error(`  ${file.split(sep).join('/')}${link ? `: ${link}` : ''} — ${message}`);
    }
    process.exit(1);
  }
  console.log(`dist/: links, anchors and resources are valid (base ${base}).`);
}
