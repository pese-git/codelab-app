/**
 * Логика поиска по документации: разбор фрагмента результата и автомат запроса.
 *
 * Почему: рантайм Pagefind отдаёт фрагмент как HTML-строку с `<mark>`, а
 * скрипты сайта не используют `innerHTML` (design.md improve-docs-navigation,
 * D8; D2 п. 6 redesign-site-showcase). Ответы поиска приходят асинхронно и
 * могут обогнать друг друга — устаревший ответ не должен затереть актуальный
 * (R7; `AGENTS.md` §9, §12).
 *
 * Для чего: чистые функции и автомат без `document` и без Pagefind: движок
 * и таймеры приходят снаружи (`Scheduler`, `load`), поэтому тест подставляет
 * поддельные. DOM-слой — `scripts/doc-page/search.ts`.
 *
 * Как использовать: `excerptParts` превращает фрагмент в части для
 * `createElement`/`textContent`. `createSearch({ scheduler, load })` держит
 * состояние: `activate()` — по первому `focus` (грузит рантайм), `input(q)` —
 * ввод, `clear()` — Esc; `subscribe` отдаёт снимки для отрисовки.
 */
import type { Scheduler } from '../showcase/scheduler';

/** Часть фрагмента: текст и признак выделения (`<mark>`). */
export interface ExcerptPart {
  readonly text: string;
  readonly mark: boolean;
}

// Pagefind 1.6.0 экранирует во фрагменте только `<` и `>`: буквальные `&amp;`
// и `&quot;` из документа должны показываться как написаны, а не искажаться.
const decoded: Readonly<Record<string, string>> = {
  '&lt;': '<',
  '&gt;': '>',
};

const token = /<mark>|<\/mark>|&(?:lt|gt);/g;

/**
 * Разбирает фрагмент Pagefind. Распознаются только `<mark>`, `</mark>`,
 * `&lt;` и `&gt;`; всё остальное, включая `<script>` и прочие теги, — обычный текст,
 * поэтому разметка из индекса не может стать элементом страницы (D8).
 */
export function excerptParts(html: string): ExcerptPart[] {
  const parts: ExcerptPart[] = [];
  let mark = false;
  let buffer = '';

  const flush = (): void => {
    if (buffer === '') return;
    const last = parts[parts.length - 1];
    if (last !== undefined && last.mark === mark) parts[parts.length - 1] = { text: last.text + buffer, mark };
    else parts.push({ text: buffer, mark });
    buffer = '';
  };

  let position = 0;
  for (const match of html.matchAll(token)) {
    buffer += html.slice(position, match.index);
    position = match.index + match[0].length;
    if (match[0] === '<mark>') {
      flush();
      mark = true;
    } else if (match[0] === '</mark>') {
      flush();
      mark = false;
    } else {
      buffer += decoded[match[0]];
    }
  }
  buffer += html.slice(position);
  flush();
  return parts;
}

/** Результат поиска, уже приведённый DOM-слоем к виду, не зависящему от Pagefind. */
export interface SearchHit {
  readonly url: string;
  readonly title: string;
  /** Группа документа (`data-pagefind-meta`) для подписи; может быть пустой. */
  readonly group: string;
  /** Фрагмент как HTML-строка Pagefind; разбирается `excerptParts`. */
  readonly excerpt: string;
}

export interface SearchEngine {
  search(query: string): Promise<readonly SearchHit[]>;
}

export type SearchStatus = 'idle' | 'loading' | 'results' | 'empty' | 'unavailable';

export interface SearchSnapshot {
  readonly status: SearchStatus;
  readonly hits: readonly SearchHit[];
  /** Фраза для `aria-live`; пусто, если объявлять нечего. */
  readonly announcement: string;
}

export interface Search {
  snapshot(): SearchSnapshot;
  subscribe(listener: (snapshot: SearchSnapshot) => void): () => void;
  /** Начинает загрузку рантайма (первый `focus`); повторные вызовы безопасны. */
  activate(): void;
  /** Новый текст запроса; поиск стартует через задержку. */
  input(query: string): void;
  /** Esc: очищает результаты и делает устаревшими отправленные запросы. */
  clear(): void;
}

/** Текст при сбое поиска; слово «Документация» скрипт превращает в ссылку на оглавление. */
export const unavailableText = 'Поиск недоступен. Откройте оглавление «Документация».';

const idle: SearchSnapshot = { status: 'idle', hits: [], announcement: '' };

export function createSearch(options: {
  scheduler: Scheduler;
  load: () => Promise<SearchEngine>;
  delayMs?: number;
}): Search {
  const { scheduler, load, delayMs = 200 } = options;
  let current = idle;
  let latest = 0;
  let timer: unknown;
  let engine: Promise<SearchEngine> | undefined;
  const listeners = new Set<(snapshot: SearchSnapshot) => void>();

  const set = (next: SearchSnapshot): void => {
    current = next;
    for (const listener of [...listeners]) listener(next);
  };

  const ensureEngine = (): Promise<SearchEngine> => {
    if (engine === undefined) {
      const loading = load();
      engine = loading;
      // Неудачная загрузка не кэшируется: следующий ввод пробует снова.
      loading.catch(() => {
        if (engine === loading) engine = undefined;
      });
    }
    return engine;
  };

  const run = async (query: string, request: number): Promise<void> => {
    set({ status: 'loading', hits: current.hits, announcement: '' });
    try {
      const hits = await (await ensureEngine()).search(query);
      if (request !== latest) return;
      set(
        hits.length > 0
          ? { status: 'results', hits, announcement: `Найдено: ${hits.length}` }
          : { status: 'empty', hits: [], announcement: 'Ничего не найдено' },
      );
    } catch {
      if (request !== latest) return;
      set({ status: 'unavailable', hits: [], announcement: unavailableText });
    }
  };

  return {
    snapshot: () => current,
    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    activate() {
      // Ошибка загрузки покажется при первом запросе; здесь её не глотаем молча,
      // а откладываем до `run`, где она станет состоянием `unavailable`.
      ensureEngine().catch(() => undefined);
    },
    input(query) {
      latest += 1;
      const request = latest;
      scheduler.clear(timer);
      const trimmed = query.trim();
      if (trimmed === '') {
        if (current !== idle) set(idle);
        return;
      }
      ensureEngine().catch(() => undefined);
      timer = scheduler.set(() => void run(trimmed, request), delayMs);
    },
    clear() {
      latest += 1;
      scheduler.clear(timer);
      if (current !== idle) set(idle);
    },
  };
}
