/**
 * Список публикуемых источников документации — allowlist сайта.
 *
 * Почему: публикация по denylist выложила бы любой новый внутренний каталог
 * (`docs/backlog/`, отчёты), пока его не исключат; allowlist публикует только
 * осознанно добавленное (design.md add-astro-site, D3, D11; `AGENTS.md` §2,
 * приоритет 1).
 *
 * Для чего: одна константа, которую читают загрузчик коллекции `docs`, плагин
 * `repoLinks` (D5) и `check-links` (D6): определение «опубликован ли файл»
 * существует в одном месте.
 *
 * Как использовать: `isPublished('docs/user/README.md')` — путь от корня
 * репозитория с прямыми слэшами. Новый источник — строка в константе и
 * строка в требовании `project-site` «Публикуемые источники документации».
 */

/**
 * Шаблоны glob публикуемых файлов от корня репозитория (D3).
 *
 * Шаблон с `!` исключает файлы: `AGENTS.md` — инструкции для агентов, а не
 * документация, и не публикуется даже внутри `doc/` (D3). Формат совместим с
 * загрузчиком `glob` Astro, поэтому константа передаётся ему как есть.
 */
export const publishPatterns: readonly string[] = [
  'docs/user/**/*.md',
  'docs/ops/**/*.md',
  'apps/*/README.md',
  'apps/*/doc/**/*.md',
  'packages/*/*/README.md',
  'packages/*/*/doc/**/*.md',
  '!**/AGENTS.md',
];

/**
 * Переводит шаблон glob в регулярное выражение.
 *
 * Почему свой разбор: шаблоны — узкое подмножество glob (звёздочка внутри
 * сегмента и двойная звёздочка для любой глубины каталогов), а библиотека
 * ради шести строк была бы лишней зависимостью (D2).
 */
function globToRegExp(pattern: string): RegExp {
  let source = '';
  for (let i = 0; i < pattern.length; i++) {
    const char = pattern[i]!;
    if (pattern.startsWith('**/', i)) {
      source += '(?:[^/]+/)*';
      i += 2;
    } else if (char === '*') {
      source += '[^/]*';
    } else {
      source += char.replace(/[\\^$.+?()[\]{}|]/g, '\\$&');
    }
  }
  return new RegExp(`^${source}$`);
}

const includes = publishPatterns.filter((p) => !p.startsWith('!')).map(globToRegExp);
const excludes = publishPatterns
  .filter((p) => p.startsWith('!'))
  .map((p) => globToRegExp(p.slice(1)));

/**
 * Опубликован ли файл [repoPath] (путь от корня репозитория).
 *
 * Путь с сегментами `.`, `..` или пустым — не опубликован: звёздочка шаблона
 * совпала бы с `..`, и `docs/user/../backlog/x.md` прошёл бы allowlist, хотя
 * ведёт в неопубликованный каталог (D3, D11). Вызывающие передают уже
 * нормализованный путь.
 */
export function isPublished(repoPath: string): boolean {
  if (repoPath.split('/').some((s) => s === '' || s === '.' || s === '..')) return false;
  return includes.some((re) => re.test(repoPath)) && !excludes.some((re) => re.test(repoPath));
}

/**
 * Каталоги, с которых начинаются шаблоны публикации (`docs/user`, `apps`, …).
 *
 * Для чего: `check-links` обходит только их, чтобы вывести список ожидаемых
 * страниц из allowlist, а не задавать его вручную (D14), и не сканировать
 * весь репозиторий.
 */
export function publishRoots(): string[] {
  const roots = publishPatterns
    .filter((p) => !p.startsWith('!'))
    .map((p) => {
      const segments = p.split('/');
      const firstGlob = segments.findIndex((s) => s.includes('*'));
      return segments.slice(0, firstGlob === -1 ? segments.length - 1 : firstGlob).join('/');
    });
  return [...new Set(roots)];
}
