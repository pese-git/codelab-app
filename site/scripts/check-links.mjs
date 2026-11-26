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
// Правила витрины (design.md redesign-site-showcase, D2, D12) живут здесь же:
// не больше одного встроенного скрипта с одинаковым текстом, нет атрибутов
// `on*`, бюджет JavaScript демо, картинка для ссылок 1200×630. Это одна зона —
// безопасность и ресурсы сборки; второй проход по тегам был бы вторым разбором
// HTML.
//
// Как использовать: `checkDist({ dist, base, expectedPages, chunks })` возвращает
// список нарушений (пустой — всё в порядке). Запуск скриптом —
// `node scripts/check-links.mjs` из `site/` после `astro build`: `base` берётся
// из `SITE_BASE` так же, как в `astro.config.mjs`, ожидаемые страницы
// выводятся из allowlist по файлам репозитория (D14); код выхода 1 и список
// «файл: ссылка — описание» при нарушениях. Модули `.ts` импортируются
// напрямую: Node из `.nvmrc` снимает типы сам, без сборки.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { extname, join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { gzipSync } from 'node:zlib';

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

/** Атрибуты тега со ссылками: `href`, `src`, `srcset`, `data`, `action`, `poster`. */
const linkAttribute = /\s(href|src|srcset|data|action|poster)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi;

/**
 * Атрибуты, которые загружают ресурс только у своего элемента: `data` у
 * `object`, `action` у `form`, `poster` у `video`. Проверяются так же, как
 * `src` (D2, D6): у других элементов это не адрес.
 */
const attributeOwners = new Map([
  ['data', 'object'],
  ['action', 'form'],
  ['poster', 'video'],
]);

/**
 * Схемы, по которым читатель может перейти из `<a>`: остальные (`javascript:`,
 * `data:`, `vbscript:`, `file:` и прочие) выполняют код или открывают не
 * страницу, поэтому в собранном сайте это нарушение (D6, D11).
 */
const navigationSchemes = new Set(['http:', 'https:', 'mailto:']);

/**
 * Элементы, которым разрешён адрес `data:`: встроенное изображение не
 * обращается к чужому хосту. У `script`, `iframe`, `object`, `link` и других
 * `data:` — исполняемое или встраиваемое содержимое в обход проверок (D2, D8).
 */
const dataUrlTags = new Set(['img', 'source']);
const linkAttributeNames = new Set(['href', 'src', 'srcset', 'data', 'action', 'poster']);

/** Любой атрибут тега: имя и значение. */
const anyAttribute = /\s([^\s"'>/=]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/g;
const idAttribute = /\sid\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/gi;
const relAttribute = /\srel\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))/i;
// Теги целиком; значения атрибутов в кавычках могут содержать `>`.
const tagPattern = /<([A-Za-z][A-Za-z0-9-]*)((?:\s+[^\s"'>/=]+(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*)\s*\/?>/g;

/**
 * Ссылки `<link rel>`, которые указывают на сам сайт по абсолютному адресу и
 * браузер не загружает как ресурс: `canonical` появляется при `SITE_URL` (D12).
 */
const nonFetchingRel = new Set(['canonical', 'alternate', 'author', 'license', 'me']);

/** Бюджет JavaScript демо на странице после gzip, без темы и mermaid (D2 п. 8). */
const demoBudgetBytes = 12 * 1024;

/** Размер картинки для ссылок (D10, D12 п. 4). */
const ogImageSize = { width: 1200, height: 630 };

/** Адрес файла картинки для ссылок относительно `base` (D10). */
const ogImagePath = 'og.png';

/**
 * Исходники модулей, которые в бюджет демо не входят: тема и mermaid (D2 п. 8).
 * Определяются по исходным модулям чанка из манифеста сборки, а не по имени
 * чанка: хэш и имя файла меняются при любой правке (D12 п. 3).
 */
const excludedEntryModules = ['src/scripts/theme.ts', 'src/scripts/mermaid.ts'];
const excludedSharedModules = [...excludedEntryModules, 'src/scripts/theme-state.ts'];

/** Имя атрибута-обработчика события: `onclick`, `onerror`; `one` и `data-on…` — нет. */
const eventHandlerName = /^on[a-z]{3,}$/;

/** Встроенный и внешний `<script>`: атрибуты и текст до закрывающего тега. */
const scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;

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

/**
 * Адреса кандидатов `srcset`.
 *
 * Почему не разбиение по запятой: запятая есть внутри адреса `data:`
 * (`data:image/png;base64,…`). Как в алгоритме HTML: адрес — подряд идущие
 * непробельные символы; запятые на его конце — разделитель, иначе
 * дескрипторы (`1x`, `640w`) читаются до запятой.
 */
function srcsetUrls(value) {
  const urls = [];
  let i = 0;
  while (i < value.length) {
    while (i < value.length && /[\s,]/.test(value[i])) i++;
    if (i >= value.length) break;
    let end = i;
    while (end < value.length && !/\s/.test(value[end])) end++;
    let url = value.slice(i, end);
    i = end;
    if (/,+$/.test(url)) {
      url = url.replace(/,+$/, '');
    } else {
      while (i < value.length && value[i] !== ',') i++;
    }
    if (url !== '') urls.push(url);
  }
  return urls;
}

/** Значение атрибута из результата регулярного выражения с тремя видами кавычек. */
function attrValue(match, from) {
  return decodeEntities(match[from] ?? match[from + 1] ?? match[from + 2] ?? '');
}

/**
 * Манифест сборки [chunks] — чанк (путь от `dist/`) → его статические
 * импорты и исходные модули от корня репозитория; его пишет плагин
 * `astro.config.mjs` при сборке (D12 п. 3). Без манифеста бюджет считает все
 * модули страницы модулями демо.
 *
 * @typedef {Record<string, { imports: readonly string[], modules: readonly string[] }>} BuildChunks
 *
 * @param {{ dist: string, base: string, expectedPages?: readonly string[], chunks?: BuildChunks, requireOgImage?: boolean, requireSearchIndex?: boolean }} options
 * @returns {LinkProblem[]}
 */
export function checkDist({ dist, base, expectedPages = [], chunks, requireOgImage = false, requireSearchIndex = false }) {
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

      for (const attribute of attrs.matchAll(anyAttribute)) {
        const name = attribute[1].toLowerCase();
        if (eventHandlerName.test(name)) {
          problems.push({ file, message: `event handler attribute ${name} on <${tagName}> is not allowed (D2, D12)` });
        }
        const value = attrValue(attribute, 2).replace(/[\t\n\r ]/g, '').toLowerCase();
        // Схемы ссылок в `href`, `src` и подобных проверяет `checkLink` ниже.
        if (!eventHandlerName.test(name) && !linkAttributeNames.has(name) && value.startsWith('javascript:')) {
          problems.push({ file, message: `javascript: in attribute ${name} of <${tagName}> is not allowed (D2, D12)` });
        }
      }

      // Рантайм поиска грузится только по действию читателя, поэтому HTML не
      // должен подключать его статически (D8, D10 п. 2).
      const loadsResource =
        (tagName === 'script' && attrs !== '') ||
        (tagName === 'link' && rel.some((r) => r === 'modulepreload' || r === 'preload' || r === 'prefetch'));
      if (loadsResource) {
        const attribute = [...attrs.matchAll(anyAttribute)].find((m) => ['src', 'href'].includes(m[1].toLowerCase()));
        if (attribute !== undefined && refersToSearchRuntime(attrValue(attribute, 2).trim(), pageUrlOf, base)) {
          problems.push({
            file,
            link: attrValue(attribute, 2).trim(),
            message: 'static reference to the search runtime pagefind/ is not allowed: it loads on demand only, outside the page JavaScript budget (D8, D10)',
          });
        }
      }

      for (const attr of attrs.matchAll(linkAttribute)) {
        const name = attr[1].toLowerCase();
        const owner = attributeOwners.get(name);
        if (owner !== undefined && owner !== tagName) continue;
        const value = attrValue(attr, 2).trim();
        const links = name === 'srcset' ? srcsetUrls(value) : [value];
        for (const link of links) {
          const problem = checkLink({ tagName, rel, link, file, pageUrlOf });
          if (problem) problems.push({ file, link, message: problem });
        }
      }
    }
  }

  // Правила витрины, страница за страницей (D12 п. 1, 3).
  /** @type {Map<string, string>} текст встроенного скрипта → первая страница с ним */
  const inlineTexts = new Map();
  for (const [file, content] of html) {
    const modules = [];
    let inlineCount = 0;
    for (const script of content.matchAll(scriptPattern)) {
      const attrs = script[1];
      const src = [...attrs.matchAll(anyAttribute)].find((m) => m[1].toLowerCase() === 'src');
      if (src === undefined) {
        inlineCount++;
        if (!inlineTexts.has(script[2])) inlineTexts.set(script[2], file);
        continue;
      }
      const type = [...attrs.matchAll(anyAttribute)].find((m) => m[1].toLowerCase() === 'type');
      if (type !== undefined && attrValue(type, 2).toLowerCase() === 'module') modules.push(attrValue(src, 2));
    }
    if (inlineCount > 1) {
      problems.push({
        file,
        message: `${inlineCount} inline <script> elements: only the theme script may be inline (CSP hash, D2, D12)`,
      });
    }
    const size = demoBytes(modules, base, dist, chunks);
    if (size > demoBudgetBytes) {
      problems.push({
        file,
        message: `page JavaScript budget is 12 KB gzip without theme, mermaid and search runtime, the page has ${(size / 1024).toFixed(1)} KB (D2, D12; D7, D10 improve-docs-navigation)`,
      });
    }
  }
  if (inlineTexts.size > 1) {
    problems.push({
      file: [...inlineTexts.values()].join(', '),
      message: 'inline <script> text differs between pages: the CSP hash must be one (D2, D12)',
    });
  }

  checkOgImage({ html, base, dist, problems, requireOgImage });

  // Индекс поиска строит `pagefind --site dist` после `astro build` (D8, D10 п. 3).
  if (requireSearchIndex) {
    const hasDocPages = [...html.keys()].some(
      (file) => file.startsWith('docs/') && file.endsWith('/index.html') && file !== 'docs/index.html',
    );
    if (hasDocPages && !existsSync(join(dist, 'pagefind', 'pagefind.js'))) {
      problems.push({
        file: 'pagefind/pagefind.js',
        message: 'search index is missing: run pagefind after astro build (D8)',
      });
    }
  }

  /**
   * Проверка одной ссылки страницы; описание нарушения или `undefined`.
   */
  function checkLink({ tagName, rel, link, file, pageUrlOf }) {
    if (link === '') return undefined;
    // Браузер убирает табуляции и переводы строк из адреса: `java\tscript:`
    // для него — `javascript:`, поэтому схема ищется после той же очистки.
    const scheme = /^([A-Za-z][A-Za-z0-9+.-]*:)/.exec(link.replace(/[\t\n\r]/g, ''))?.[1]?.toLowerCase();
    const external = link.startsWith('//') || scheme !== undefined;
    if (external) {
      if (tagName === 'a') {
        // Переход по ссылке `<a>` — решение читателя, а не запрос страницы;
        // внешние адреса не запрашиваются (D6). Но только по схемам перехода.
        if (scheme === undefined || navigationSchemes.has(scheme)) return undefined;
        return `scheme "${scheme}" is not allowed in <a>: only http:, https:, mailto:, site and relative addresses (D6, D11)`;
      }
      if (scheme === 'data:') {
        if (dataUrlTags.has(tagName)) return undefined;
        return `scheme "data:" is not allowed in <${tagName}>: only <img> and <source> may embed data: (D2, D8)`;
      }
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

  // Обратная проверка D14: каждая страница `docs/` выведена из опубликованного
  // файла. Страница без такого файла — путь в обход allowlist (D3, D11).
  for (const file of html.keys()) {
    if (!file.startsWith('docs/') || !file.endsWith('/index.html') || file === 'docs/index.html') continue;
    if (sourceOfPage(file) === undefined) {
      problems.push({
        file,
        message: 'page under docs/ does not come from a file in the publish allowlist (D3, D14)',
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

/** Ссылка ведёт в каталог рантайма поиска `<base>pagefind/` (D10 п. 2). */
function refersToSearchRuntime(link, pageUrlOf, base) {
  if (link === '' || /^([A-Za-z][A-Za-z0-9+.-]*:|\/\/)/.test(link)) return false;
  try {
    return new URL(link, pageUrlOf).pathname.startsWith(`${base}pagefind/`);
  } catch {
    return false;
  }
}

/** Исходный модуль чанка без запроса Vite (`?astro&type=script…`) и с путём от `site/`. */
function moduleBase(id) {
  const path = id.split('?')[0];
  const at = path.indexOf('src/');
  return at === -1 ? path : path.slice(at);
}

/**
 * Байты gzip модулей демо страницы: статический импорт чанков входит в сумму,
 * тема и mermaid и чанки только из их исходников — нет (D2 п. 8, D12 п. 3).
 */
function demoBytes(moduleSrcs, base, dist, chunks) {
  const keyOf = (src) => {
    const path = src.split(/[?#]/)[0];
    return path.startsWith(base) ? path.slice(base.length) : path.replace(/^\//, '');
  };
  // Входной чанк исключается, только если в нём нет ничего, кроме темы и
  // mermaid: смешанный чанк с кодом демо — это код демо (D2 п. 8).
  const isEntryExcluded = (key) => {
    const modules = chunks?.[key]?.modules ?? [];
    return modules.length > 0 && modules.every((m) => excludedEntryModules.includes(moduleBase(m)));
  };
  const isSharedExcluded = (key) => {
    const modules = chunks?.[key]?.modules ?? [];
    return modules.length > 0 && modules.every((m) => excludedSharedModules.includes(moduleBase(m)));
  };

  const counted = new Set();
  const visit = (key) => {
    if (counted.has(key) || isSharedExcluded(key)) return;
    counted.add(key);
    for (const imported of chunks?.[key]?.imports ?? []) visit(imported);
  };
  for (const src of moduleSrcs) {
    const key = keyOf(src);
    if (!isEntryExcluded(key)) visit(key);
  }

  let total = 0;
  for (const key of counted) {
    const file = join(dist, key);
    if (existsSync(file) && statSync(file).isFile()) total += gzipSync(readFileSync(file)).length;
  }
  return total;
}

/**
 * Проверка картинки для ссылок (D10, D12 п. 4): `og:image` страницы указывает
 * на PNG 1200×630 внутри `base`; без `og:image` (нет `SITE_URL`) проверяется
 * сам файл по известному адресу, если он собран.
 */
function checkOgImage({ html, base, dist, problems, requireOgImage }) {
  /** @type {Map<string, string>} путь файла от `dist/` → страница, на которую он указан */
  const targets = new Map();
  for (const [file, content] of html) {
    for (const tag of content.matchAll(tagPattern)) {
      if (tag[1].toLowerCase() !== 'meta') continue;
      const attrs = Object.fromEntries(
        [...(tag[2] ?? '').matchAll(anyAttribute)].map((m) => [m[1].toLowerCase(), attrValue(m, 2)]),
      );
      if (attrs.property?.toLowerCase() !== 'og:image') continue;
      const content = attrs.content ?? '';
      let path;
      try {
        path = new URL(content).pathname;
      } catch {
        problems.push({ file, link: content, message: 'og:image must be an absolute address (D10)' });
        continue;
      }
      if (!path.startsWith(base)) {
        problems.push({ file, link: content, message: `og:image does not start with base ${base} (D10, D12)` });
        continue;
      }
      const target = safeDecode(path.slice(base.length));
      if (!existsSync(join(dist, target)) || !statSync(join(dist, target)).isFile()) {
        problems.push({ file, link: content, message: 'og:image target file does not exist in dist/ (D12)' });
        continue;
      }
      targets.set(target, file);
    }
  }
  if (targets.size === 0 && existsSync(join(dist, ogImagePath))) targets.set(ogImagePath, ogImagePath);
  // В CLI картинка обязана быть в сборке, даже когда `SITE_URL` не задан и
  // `og:image` на страницах нет: её отдаёт endpoint `og.png.ts` всегда (D10).
  if (requireOgImage && !existsSync(join(dist, ogImagePath))) {
    problems.push({ file: ogImagePath, message: `${ogImagePath} is missing in dist/: the og.png endpoint did not build (D10, D12)` });
  }

  for (const target of targets.keys()) {
    const bytes = readFileSync(join(dist, target));
    const isPng = bytes.length >= 24 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    if (!isPng) {
      problems.push({ file: target, message: 'og:image must be a PNG file (D10, D12)' });
      continue;
    }
    const width = bytes.readUInt32BE(16);
    const height = bytes.readUInt32BE(20);
    if (width !== ogImageSize.width || height !== ogImageSize.height) {
      problems.push({
        file: target,
        message: `og:image must be ${ogImageSize.width}×${ogImageSize.height}, the file is ${width}×${height} (D10, D12)`,
      });
    }
  }
}

/**
 * Опубликованный файл, из которого получена страница [file] `docs/…/index.html`;
 * `undefined`, если такого нет.
 *
 * Почему перебор кандидатов: `pageUrl` (D4) отбрасывает `.md` и `README`, а
 * источникам `docs/*` не добавляет второй `docs/`. Поэтому у страницы
 * `docs/<p>/` четыре возможных источника: `<p>.md`, `<p>/README.md`,
 * `docs/<p>.md`, `docs/<p>/README.md`. Источник засчитывается, только если он
 * в allowlist и `pageUrl` даёт ровно эту страницу.
 */
function sourceOfPage(file) {
  const page = file.slice(0, -'index.html'.length);
  const path = page.slice('docs/'.length, -1);
  const candidates = [`${path}.md`, `${path}/README.md`, `docs/${path}.md`, `docs/${path}/README.md`];
  return candidates.find((candidate) => isPublished(candidate) && pageUrl(candidate, '/') === `/${page}`);
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
  // Манифест чанков пишет плагин сборки; без него тема и mermaid попали бы в бюджет демо.
  const chunksFile = join(siteRoot, '.astro', 'build-chunks.json');
  if (!existsSync(chunksFile)) {
    console.error(`${relative(process.cwd(), chunksFile)}: not found, run astro build first (D12).`);
    process.exit(1);
  }
  const chunks = JSON.parse(readFileSync(chunksFile, 'utf8'));
  const problems = checkDist({ dist, base, expectedPages: expectedPagesFromRepo(repoRoot, base), chunks, requireOgImage: true, requireSearchIndex: true });
  if (problems.length > 0) {
    console.error(`dist/: ${problems.length} problem(s) (D6):`);
    for (const { file, link, message } of problems) {
      console.error(`  ${file.split(sep).join('/')}${link ? `: ${link}` : ''} — ${message}`);
    }
    process.exit(1);
  }
  console.log(`dist/: links, anchors and resources are valid (base ${base}).`);
}
