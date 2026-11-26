/**
 * Манифест чанков клиентской сборки: какие исходные файлы вошли в какой чанк.
 *
 * Почему: бюджет JavaScript витрины (12 КБ gzip) не включает тему и mermaid
 * (design.md redesign-site-showcase, D2 п. 8). Имя чанка с хэшем менять при
 * любой правке, поэтому отличить модуль темы от модуля демо можно только по
 * исходному файлу. Манифест Vite (`build.manifest`) в статической сборке
 * Astro 7 не попадает в `dist/`, поэтому его заменяет этот: той же формы, что
 * нужна проверке, и без абсолютных путей машины сборки (D11 `add-astro-site`).
 *
 * Для чего: `check-links` (D12 п. 3) читает манифест и по нему исключает
 * модули темы и mermaid и считает статические импорты демо.
 *
 * Как использовать: `buildChunksPlugin(repoRoot, outFile)` в `vite.plugins`
 * `astro.config.mjs`; плагин пишет JSON только при клиентской сборке.
 * `chunksFromBundle` — чистая часть, её покрывает vitest.
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

/** Чанк пакета Rollup/Rolldown в части, которую читает манифест. */
interface BundleEntry {
  readonly type: string;
  readonly fileName: string;
  readonly imports?: readonly string[];
  readonly modules?: Readonly<Record<string, unknown>>;
}

/** Манифест: чанк (путь от `dist/`) → статические импорты и исходные модули. */
export type BuildChunks = Record<string, { imports: string[]; modules: string[] }>;

/**
 * Строит манифест из пакета сборки. Динамические импорты не входят: их
 * загружает код при действии посетителя, а не страница (mermaid, D7).
 * Модули зависимостей (`node_modules`), виртуальные (`\0…`) и вне
 * [repoRoot] пропускаются: проверке нужны только исходники сайта.
 */
export function chunksFromBundle(
  bundle: Readonly<Record<string, BundleEntry>>,
  repoRoot: string,
): BuildChunks {
  const prefix = repoRoot.replace(/\/+$/, '') + '/';
  const result: BuildChunks = {};
  for (const item of Object.values(bundle)) {
    if (item.type !== 'chunk') continue;
    const modules = Object.keys(item.modules ?? {})
      .filter((id) => id.startsWith(prefix) && !id.includes('/node_modules/'))
      .map((id) => id.slice(prefix.length));
    result[item.fileName] = { imports: [...(item.imports ?? [])], modules };
  }
  return result;
}

/**
 * Плагин Vite, пишущий манифест в [outFile] при клиентской сборке.
 *
 * Файл лежит в `site/.astro/` (каталог кэша Astro, он в `.gitignore`), а не в
 * `dist/`: манифест служебный и в опубликованный сайт не попадает.
 */
export function buildChunksPlugin(repoRoot: string, outFile: string) {
  return {
    name: 'codelab-build-chunks',
    generateBundle(
      this: { environment?: { name: string } },
      _options: unknown,
      bundle: Readonly<Record<string, BundleEntry>>,
    ) {
      // Серверная сборка страниц тоже вызывает хук; её чанки в `dist/` не уходят.
      if (this.environment !== undefined && this.environment.name !== 'client') return;
      mkdirSync(dirname(outFile), { recursive: true });
      writeFileSync(outFile, JSON.stringify(chunksFromBundle(bundle, repoRoot), null, 1));
    },
  };
}
