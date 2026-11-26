/**
 * Поле поиска по документации: связь разметки `DocSearch.astro` с автоматом
 * `lib/doc-page/search.ts` и рантаймом Pagefind.
 *
 * Почему: рантайм (JavaScript, WebAssembly, фрагменты индекса) — десятки
 * килобайт и больше, поэтому он не подключается из HTML и не проходит через
 * Vite: грузится динамическим `import()` по первому `focus` или `input`
 * (design.md improve-docs-navigation, D8; R3). `check-links` запрещает
 * статические ссылки на `pagefind/` (D10).
 *
 * Для чего: показывает `form[data-doc-search]` (в разметке она `hidden` — без
 * JavaScript поля нет), передаёт ввод автомату, рисует результаты узлами
 * `createElement` и `textContent` (без `innerHTML`) и пишет итог в область
 * `aria-live`. Esc очищает поле и результаты. Фокус скриптом не переносится.
 *
 * Как использовать: подключается компонентом `DocSearch.astro`; адрес
 * рантайма строится `withBase` из `data-base` формы, он же передаётся
 * `pagefind.options({ baseUrl })`, чтобы ссылки результатов учитывали
 * `SITE_BASE`.
 */
import { createSearch, excerptParts, type SearchEngine, type SearchHit, type SearchSnapshot } from '../../lib/doc-page/search';
import { browserScheduler } from '../../lib/showcase/scheduler';
import { withBase } from '../../lib/urls';

/** Сколько результатов показывается: остальные читателю не нужны, а данные грузятся по одному. */
const maxHits = 10;

interface PagefindResult {
  data(): Promise<{ url: string; excerpt: string; meta: Record<string, string | undefined> }>;
}

interface PagefindRuntime {
  options(options: { baseUrl: string }): Promise<void>;
  init(): Promise<void>;
  search(query: string): Promise<{ results: PagefindResult[] }>;
}

function loadEngine(base: string): () => Promise<SearchEngine> {
  return async () => {
    // @vite-ignore: рантайм лежит в `dist/pagefind/` и строится после сборки Vite.
    const runtime = (await import(/* @vite-ignore */ withBase('pagefind/pagefind.js', base))) as PagefindRuntime;
    await runtime.options({ baseUrl: base });
    await runtime.init();
    return {
      async search(query: string): Promise<SearchHit[]> {
        const found = await runtime.search(query);
        const data = await Promise.all(found.results.slice(0, maxHits).map((result) => result.data()));
        return data.map((item) => ({
          url: item.url,
          title: item.meta.title ?? item.url,
          group: item.meta.group ?? '',
          excerpt: item.excerpt,
        }));
      },
    };
  };
}

function renderHit(hit: SearchHit): HTMLLIElement {
  const item = document.createElement('li');
  const link = document.createElement('a');
  link.href = hit.url;
  link.textContent = hit.title;
  item.append(link);
  if (hit.group !== '') {
    const group = document.createElement('span');
    group.className = 'doc-search-group t2';
    group.textContent = ` — ${hit.group}`;
    item.append(group);
  }
  const excerpt = document.createElement('p');
  excerpt.className = 'doc-search-excerpt t2';
  for (const part of excerptParts(hit.excerpt)) {
    if (part.mark) {
      const mark = document.createElement('mark');
      mark.textContent = part.text;
      excerpt.append(mark);
    } else {
      excerpt.append(document.createTextNode(part.text));
    }
  }
  item.append(excerpt);
  return item;
}

/**
 * Пишет сообщение в область статуса; при сбое поиска слово «Документация»
 * становится ссылкой на оглавление, чтобы у читателя был путь дальше без поиска.
 */
function renderStatus(status: HTMLElement, snapshot: SearchSnapshot, toc: string | undefined): void {
  const word = 'Документация';
  const at = snapshot.announcement.indexOf(word);
  if (snapshot.status !== 'unavailable' || toc === undefined || at === -1) {
    status.textContent = snapshot.announcement;
    return;
  }
  const link = document.createElement('a');
  link.href = toc;
  link.textContent = word;
  status.replaceChildren(
    document.createTextNode(snapshot.announcement.slice(0, at)),
    link,
    document.createTextNode(snapshot.announcement.slice(at + word.length)),
  );
}

function init(form: HTMLFormElement): void {
  const input = form.querySelector<HTMLInputElement>('input');
  const status = form.querySelector<HTMLElement>('[data-search-status]');
  const results = form.querySelector<HTMLOListElement>('[data-search-results]');
  if (!input || !status || !results) return;

  const search = createSearch({ scheduler: browserScheduler, load: loadEngine(form.dataset.base ?? '/') });

  search.subscribe((snapshot: SearchSnapshot) => {
    results.replaceChildren(...snapshot.hits.map(renderHit));
    results.hidden = snapshot.hits.length === 0;
    renderStatus(status, snapshot, form.dataset.toc);
  });

  input.addEventListener('focus', () => search.activate());
  input.addEventListener('input', () => search.input(input.value));
  input.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape') return;
    input.value = '';
    search.clear();
  });
  // Поле не отправляет форму: результаты обновляются по вводу.
  form.addEventListener('submit', (event) => event.preventDefault());

  form.hidden = false;
}

for (const form of document.querySelectorAll<HTMLFormElement>('form[data-doc-search]')) init(form);
