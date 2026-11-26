// Разбор фрагмента результата и автомат запроса поиска (design.md
// improve-docs-navigation, D8, R7): время двигает FakeScheduler, рантайм
// Pagefind заменён поддельным движком.
import { describe, expect, it } from 'vitest';

import { createSearch, excerptParts, type SearchEngine, type SearchHit } from '../src/lib/doc-page/search';
import { FakeScheduler } from './support/fake-scheduler';

describe('excerptParts (D8)', () => {
  it('обычный текст — одна часть без выделения', () => {
    expect(excerptParts('разрешение на запись')).toEqual([{ text: 'разрешение на запись', mark: false }]);
  });

  it('<mark>…</mark> — выделенная часть', () => {
    expect(excerptParts('до <mark>слово</mark> после')).toEqual([
      { text: 'до ', mark: false },
      { text: 'слово', mark: true },
      { text: ' после', mark: false },
    ]);
  });

  it('декодируются только &lt; и &gt;: Pagefind экранирует лишь их', () => {
    expect(excerptParts('&lt;a&gt;')).toEqual([{ text: '<a>', mark: false }]);
  });

  it('буквальные &amp;, &quot; и &#39; из документа остаются как есть', () => {
    expect(excerptParts('a &amp; b &quot;x&quot; &#39;y&#39;')).toEqual([
      { text: 'a &amp; b &quot;x&quot; &#39;y&#39;', mark: false },
    ]);
  });

  it('прочие теги — текст, а не разметка', () => {
    expect(excerptParts('<script>alert(1)</script><b>x</b>')).toEqual([
      { text: '<script>alert(1)</script><b>x</b>', mark: false },
    ]);
  });

  it('сущность не раскрывается дважды', () => {
    expect(excerptParts('&amp;lt;mark&amp;gt;')).toEqual([{ text: '&amp;lt;mark&amp;gt;', mark: false }]);
  });

  it('незакрытый <mark> выделяет остаток', () => {
    expect(excerptParts('a <mark>b c')).toEqual([
      { text: 'a ', mark: false },
      { text: 'b c', mark: true },
    ]);
  });

  it('лишний </mark> и пустые выделения игнорируются', () => {
    expect(excerptParts('a</mark>b<mark></mark>c')).toEqual([{ text: 'abc', mark: false }]);
  });

  it('пустая строка — нет частей', () => {
    expect(excerptParts('')).toEqual([]);
  });
});

function hit(n: number): SearchHit {
  return { url: `/docs/${n}/`, title: `Документ ${n}`, group: 'Руководство', excerpt: `<mark>q</mark> ${n}` };
}

/** Движок, ответы которого завершает тест. */
function manualEngine() {
  const pending: { query: string; resolve: (hits: SearchHit[]) => void; reject: (e: unknown) => void }[] = [];
  const engine: SearchEngine = {
    search: (query) => new Promise((resolve, reject) => pending.push({ query, resolve, reject })),
  };
  return { engine, pending };
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

function setup(loadImpl?: () => Promise<SearchEngine>) {
  const scheduler = new FakeScheduler();
  const manual = manualEngine();
  let loads = 0;
  const search = createSearch({
    scheduler,
    load: () => {
      loads += 1;
      return loadImpl ? loadImpl() : Promise.resolve(manual.engine);
    },
  });
  return { scheduler, manual, search, loads: () => loads };
}

describe('createSearch (D8, R7)', () => {
  it('начинает в покое; рантайм не грузится без действия', () => {
    const { search, loads } = setup();
    expect(search.snapshot()).toMatchObject({ status: 'idle', hits: [], announcement: '' });
    expect(loads()).toBe(0);
  });

  it('activate грузит рантайм один раз', async () => {
    const { search, loads } = setup();
    search.activate();
    search.activate();
    search.input('разрешение');
    await flush();
    expect(loads()).toBe(1);
  });

  it('запрос уходит через 200 мс, не раньше; ввод сбрасывает задержку', async () => {
    const { search, scheduler, manual } = setup();
    search.input('раз');
    scheduler.advance(150);
    search.input('разр');
    scheduler.advance(150);
    await flush();
    expect(manual.pending).toHaveLength(0);
    scheduler.advance(50);
    await flush();
    expect(manual.pending.map((p) => p.query)).toEqual(['разр']);
  });

  it('ответ отрисовывается: «Найдено: N»', async () => {
    const { search, scheduler, manual } = setup();
    search.input('q');
    scheduler.advance(200);
    await flush();
    manual.pending[0].resolve([hit(1), hit(2)]);
    await flush();
    expect(search.snapshot()).toMatchObject({ status: 'results', announcement: 'Найдено: 2' });
    expect(search.snapshot().hits).toHaveLength(2);
  });

  it('пустой ответ — «Ничего не найдено»', async () => {
    const { search, scheduler, manual } = setup();
    search.input('zzz');
    scheduler.advance(200);
    await flush();
    manual.pending[0].resolve([]);
    await flush();
    expect(search.snapshot()).toMatchObject({ status: 'empty', hits: [], announcement: 'Ничего не найдено' });
  });

  it('ответ старого запроса не отрисовывается', async () => {
    const { search, scheduler, manual } = setup();
    search.input('a');
    scheduler.advance(200);
    await flush();
    search.input('ab');
    scheduler.advance(200);
    await flush();
    expect(manual.pending.map((p) => p.query)).toEqual(['a', 'ab']);
    manual.pending[1].resolve([hit(2)]);
    await flush();
    manual.pending[0].resolve([hit(1), hit(3)]);
    await flush();
    expect(search.snapshot().hits).toEqual([hit(2)]);
    expect(search.snapshot().announcement).toBe('Найдено: 1');
  });

  it('ввод после отправки запроса делает его ответ устаревшим, даже без нового запроса', async () => {
    const { search, scheduler, manual } = setup();
    search.input('a');
    scheduler.advance(200);
    await flush();
    search.input('ab'); // новый запрос ещё ждёт задержку
    manual.pending[0].resolve([hit(1)]);
    await flush();
    expect(search.snapshot().status).not.toBe('results');
  });

  it('ошибка загрузки рантайма — «Поиск недоступен»', async () => {
    const { search, scheduler } = setup(() => Promise.reject(new Error('404')));
    search.input('q');
    scheduler.advance(200);
    await flush();
    expect(search.snapshot()).toMatchObject({ status: 'unavailable', announcement: 'Поиск недоступен. Откройте оглавление «Документация».' });
  });

  it('ошибка самого запроса — «Поиск недоступен»', async () => {
    const { search, scheduler, manual } = setup();
    search.input('q');
    scheduler.advance(200);
    await flush();
    manual.pending[0].reject(new Error('boom'));
    await flush();
    expect(search.snapshot().status).toBe('unavailable');
  });

  it('пустой ввод — покой, запрос не отправляется', async () => {
    const { search, scheduler, manual } = setup();
    search.input('   ');
    scheduler.advance(500);
    await flush();
    expect(manual.pending).toHaveLength(0);
    expect(search.snapshot().status).toBe('idle');
  });

  it('Esc (clear) очищает результаты и отменяет ожидающий запрос', async () => {
    const { search, scheduler, manual } = setup();
    search.input('q');
    scheduler.advance(200);
    await flush();
    manual.pending[0].resolve([hit(1)]);
    await flush();
    search.input('qq');
    search.clear();
    scheduler.advance(500);
    await flush();
    expect(manual.pending).toHaveLength(1);
    expect(search.snapshot()).toMatchObject({ status: 'idle', hits: [], announcement: '' });
  });

  it('clear делает устаревшим уже отправленный запрос', async () => {
    const { search, scheduler, manual } = setup();
    search.input('q');
    scheduler.advance(200);
    await flush();
    search.clear();
    manual.pending[0].resolve([hit(1)]);
    await flush();
    expect(search.snapshot().status).toBe('idle');
  });

  it('подписчик получает изменения; отписка работает', async () => {
    const { search, scheduler, manual } = setup();
    const seen: string[] = [];
    const off = search.subscribe((s) => seen.push(s.status));
    search.input('q');
    scheduler.advance(200);
    await flush();
    manual.pending[0].resolve([hit(1)]);
    await flush();
    off();
    search.clear();
    expect(seen.at(-1)).toBe('results');
  });
});
