/**
 * Поиск абсолютных путей домашних каталогов с личным именем пользователя.
 *
 * Почему: снимки вывода в документах легко приносят личное имя
 * (`/Users/alice/…`), а `codelab-docs` §7 требует масок `user` и `me`
 * (design.md add-astro-site, D11; project-site «Безопасность публикации»).
 *
 * Для чего: одна константа масок и одна функция поиска для двух рубежей —
 * remark-плагина `remarkHomePaths` (документы) и `scripts/check-links.mjs`
 * (весь `dist/`, D6). Список масок нельзя расширить в одном месте и забыть в
 * другом.
 *
 * Как использовать: `findHomePaths(text)` — найденные пути с позицией в
 * строке; пустой список — личных путей нет.
 */

/** Разрешённые маски имени пользователя (`codelab-docs` §7, D11). */
export const homePathMasks: readonly string[] = ['user', 'me'];

/** Найденный личный путь: смещение в строке и сам путь до пробела или кавычки. */
export interface HomePathMatch {
  readonly index: number;
  readonly path: string;
}

/**
 * `/Users/<имя>`, `/home/<имя>`, `/var/home/<имя>` (Fedora Silverblue и
 * другие системы с `/home` в `/var`) и их URL-кодировка (`%2FUsers%2F<имя>` в
 * query-строке); `C:\Users\<имя>` с одинарными, двойными (тот же путь внутри
 * строки JSON или JS) или прямыми слэшами и с `%5C`. За именем идёт
 * разделитель или конец имени. Слева — не часть другого слова, чтобы
 * `/usr/home/x` или `foo/Users/x` не считались домашним каталогом. Группа
 * `name` — имя пользователя, весь матч продолжается до конца пути.
 */
const homePath =
  /(?<![\p{L}\p{N}._-])(?:(?:\/|%2[Ff])(?:var(?:\/|%2[Ff]))?(?:Users|home)(?:\/|%2[Ff])|[A-Za-z]:(?:\\{1,2}|\/|%5[Cc]|%2[Ff])[Uu]sers(?:\\{1,2}|\/|%5[Cc]|%2[Ff]))(?<name>[\p{L}\p{N}._-]+)(?![\p{L}\p{N}._-])[^\s"'<>`)]*/gu;

/** Личные пути домашних каталогов в [text]; маски `user` и `me` пропускаются. */
export function findHomePaths(text: string): HomePathMatch[] {
  const result: HomePathMatch[] = [];
  for (const match of text.matchAll(homePath)) {
    if (homePathMasks.includes(match.groups!.name!)) continue;
    result.push({ index: match.index, path: match[0] });
  }
  return result;
}
