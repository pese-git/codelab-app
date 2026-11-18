/**
 * Путь файла конвейера Markdown от корня репозитория.
 *
 * Почему: сообщения об ошибках сборки называют документ так, как его видит
 * автор в репозитории (`docs/user/guide.md:3`), а не абсолютным путём машины
 * сборки: абсолютный путь длинный и приносит в журнал CI имя каталога
 * пользователя (design.md add-astro-site, D5, D11).
 *
 * Для чего: одна функция для плагинов, которые пишут путь файла в сообщение
 * (`rawHtmlGuard`, `homePaths`, `newsBase`) или решают по нему, применяться ли.
 *
 * Как использовать: `repoPath(repoRoot, file.path)` — путь с прямыми слэшами;
 * файл без пути — `<unknown>`.
 */
import { relative, sep } from 'node:path';

export function repoPath(repoRoot: string, filePath: string | undefined): string {
  if (filePath === undefined) return '<unknown>';
  return relative(repoRoot, filePath).split(sep).join('/');
}
