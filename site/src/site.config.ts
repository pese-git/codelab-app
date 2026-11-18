/**
 * Настройки сайта, связанные с репозиторием: адрес на GitHub и ревизия ссылок.
 *
 * Почему: ссылки документов на неопубликованные файлы ведут на GitHub
 * (`blob`/`tree`), и им нужна ревизия. Цель ссылок в опубликованной сборке
 * выбирается вместе с хостингом (design.md add-astro-site, D5, Q2, H2), поэтому
 * она — параметр, а не константа.
 *
 * Для чего: единственное место, где определены `repoUrl` и правило выбора
 * `repoRef`; их читает плагин `repoLinks` (D5) и ссылка «Исходный файл на GitHub».
 *
 * Как использовать: `repoUrl` — константа; `resolveRepoRef()` вызывается при
 * сборке. Ревизия не вычисляется при импорте модуля, чтобы тесты могли
 * подставить окружение и чтение `HEAD`.
 */
import { execFileSync } from 'node:child_process';

/** Адрес репозитория на GitHub; совпадает с `origin` (D5). */
export const repoUrl = 'https://github.com/pese-git/codelab-app';

/** Ошибка сборки: ревизию для ссылок на GitHub определить нельзя (D5). */
export class RepoRefError extends Error {
  constructor() {
    super(
      'Cannot determine the git revision for GitHub links: set SITE_GITHUB_REF ' +
        '(or GITHUB_SHA), or build inside a git checkout.',
    );
    this.name = 'RepoRefError';
  }
}

/**
 * Читает `git rev-parse HEAD` в корне репозитория; `undefined`, если git
 * недоступен или каталог не в репозитории.
 */
export function readGitHead(): string | undefined {
  try {
    const out = execFileSync('git', ['rev-parse', 'HEAD'], {
      cwd: new URL('../..', import.meta.url),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    return out === '' ? undefined : out;
  } catch {
    return undefined;
  }
}

/**
 * Выбирает ревизию ссылок на GitHub.
 *
 * Порядок (D5): `SITE_GITHUB_REF` → `GITHUB_SHA` (CI) → `git rev-parse HEAD`.
 * По умолчанию — коммит сборки: ссылка ведёт ровно на ту версию файла, из
 * которой собран сайт. Если ничего нет — `RepoRefError`, а не молчаливая ветка.
 */
export function resolveRepoRef(
  env: Record<string, string | undefined> = process.env,
  readHead: () => string | undefined = readGitHead,
): string {
  const explicit = env.SITE_GITHUB_REF?.trim();
  if (explicit) return explicit;
  const ciSha = env.GITHUB_SHA?.trim();
  if (ciSha) return ciSha;
  const head = readHead();
  if (head) return head;
  throw new RepoRefError();
}
