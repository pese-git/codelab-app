// Тесты проверки собранного сайта (tasks.md add-astro-site, 3.11; D2, D6, D7,
// D11, D14; project-site «Проверка внутренних ссылок собранного сайта»,
// «Сборка под подкаталог», «Нет сторонних запросов») на мини-`dist/` во
// временном каталоге, без сети.
import { randomBytes } from 'node:crypto';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { checkDist } from '../scripts/check-links.mjs';

const base = '/codelab-app/';
let dist: string;

beforeEach(() => {
  dist = mkdtempSync(join(tmpdir(), 'codelab-site-dist-'));
});

afterEach(() => {
  rmSync(dist, { recursive: true, force: true });
});

function write(path: string, content: string | Uint8Array): void {
  mkdirSync(dirname(join(dist, path)), { recursive: true });
  writeFileSync(join(dist, path), content);
}

function page(body: string, head = ''): string {
  return `<!DOCTYPE html><html lang="ru"><head><meta charset="utf-8">${head}</head><body>${body}</body></html>`;
}

/** Мини-сборка в стиле выхода Astro: каталоги с index.html, ресурсы в _astro/. */
function writeSite(): void {
  write(
    'index.html',
    page(
      '<a href="/codelab-app/docs/user/">Пользователю</a>',
      '<link rel="stylesheet" href="/codelab-app/_astro/index.abc123.css">' +
        '<script type="module" src="/codelab-app/_astro/page.def456.js"></script>',
    ),
  );
  write(
    'docs/user/index.html',
    page('<h1 id="пользователю">Пользователю</h1><a href="/codelab-app/docs/user/configuration/">Настройка</a>'),
  );
  write(
    'docs/user/configuration/index.html',
    page('<h1 id="настройка-агента">Настройка агента</h1><h2 id="шаг-2-задайте-ключ-api">Шаг 2</h2>'),
  );
  write('_astro/index.abc123.css', 'body{color:var(--text)}');
  write('_astro/page.def456.js', 'console.log(1)');
  write('_astro/command-palette.xyz.png', 'png');
}

describe('checkDist: внутренние ссылки', () => {
  it('существующие страницы и ресурсы с base — без нарушений', () => {
    writeSite();
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it('…/ ведёт на …/index.html, а якорь — на id целевой страницы', () => {
    writeSite();
    write(
      'docs/ops/index.html',
      page(
        '<a href="/codelab-app/docs/user/configuration/#шаг-2-задайте-ключ-api">Ключ</a>' +
          '<a href="/codelab-app/docs/user/configuration/index.html">Файл</a>' +
          '<img src="/codelab-app/_astro/command-palette.xyz.png" alt="Палитра">',
      ),
    );
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it('якорь в процентной кодировке сравнивается с id после декодирования', () => {
    writeSite();
    const encoded = encodeURIComponent('шаг-2-задайте-ключ-api');
    write('docs/ops/index.html', page(`<a href="/codelab-app/docs/user/configuration/#${encoded}">Ключ</a>`));
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it('отсутствующий файл — нарушение «страница → ссылка»', () => {
    writeSite();
    write('docs/ops/index.html', page('<a href="/codelab-app/docs/missing/">Нет</a>'));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', link: '/codelab-app/docs/missing/' }),
    ]);
  });

  it('отсутствующий ресурс src — нарушение', () => {
    writeSite();
    write('docs/ops/index.html', page('<img src="/codelab-app/_astro/missing.png" alt="Нет">'));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', link: '/codelab-app/_astro/missing.png' }),
    ]);
  });

  it('отсутствующий id — нарушение (сценарий «Ссылка на несуществующий якорь»)', () => {
    writeSite();
    write(
      'docs/ops/index.html',
      page('<a href="/codelab-app/docs/user/configuration/#нет-такого-раздела">Нет</a>'),
    );
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({
        file: 'docs/ops/index.html',
        link: '/codelab-app/docs/user/configuration/#нет-такого-раздела',
      }),
    ]);
  });

  it('ссылка без base при непустом base — нарушение, даже если файл есть', () => {
    writeSite();
    write('docs/user/index.html', page('<a href="/docs/user/configuration/">Без base</a>'));
    write('docs/user/configuration/index.html', page('<h1 id="x">x</h1>'));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/user/index.html', link: '/docs/user/configuration/' }),
    ]);
  });

  it('при base / проверяет те же ссылки от корня', () => {
    write('index.html', page('<a href="/docs/user/">Пользователю</a><a href="/docs/nope/">Нет</a>'));
    write('docs/user/index.html', page('<h1 id="x">x</h1>'));
    expect(checkDist({ dist, base: '/' })).toEqual([
      expect.objectContaining({ file: 'index.html', link: '/docs/nope/' }),
    ]);
  });
});

describe('checkDist: внешние адреса и сторонние ресурсы', () => {
  it('внешние ссылки <a> не проверяются и не запрашиваются', () => {
    writeSite();
    write(
      'docs/ops/index.html',
      page(
        '<a href="https://fvm.app">FVM</a>' +
          '<a href="https://github.com/pese-git/codelab-app/blob/abc/docs/architecture/testing.md">GitHub</a>' +
          '<a href="mailto:team@example.com">Почта</a>',
      ),
    );
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it.each([
    ['script', '<script src="https://cdn.example.com/lib.js"></script>', 'https://cdn.example.com/lib.js'],
    ['link', '<link rel="stylesheet" href="https://fonts.example.com/css">', 'https://fonts.example.com/css'],
    ['img', '<img src="https://example.com/a.png" alt="a">', 'https://example.com/a.png'],
    ['script без схемы', '<script src="//cdn.example.com/lib.js"></script>', '//cdn.example.com/lib.js'],
  ])('%s с чужого хоста — нарушение', (_name, html, link) => {
    writeSite();
    write('docs/ops/index.html', page(html));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', link }),
    ]);
  });
});

describe('checkDist: личные пути (D11, вторая линия)', () => {
  it.each([
    '/Users/alice/projects/demo',
    '/home/bob/.codelab/config.yaml',
    'C:\\Users\\eve\\AppData',
  ])('%s в тексте страницы — нарушение', (path) => {
    writeSite();
    write('docs/ops/index.html', page(`<p>Путь ${path}</p>`));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html' }),
    ]);
  });

  it('маски user и me проходят', () => {
    writeSite();
    write(
      'docs/ops/index.html',
      page('<pre>/home/me/.codelab/config.yaml /Users/user/demo C:\\Users\\user\\AppData</pre>'),
    );
    expect(checkDist({ dist, base })).toEqual([]);
  });
});

describe('checkDist: ожидаемые страницы и лицензии', () => {
  it('ожидаемая страница из allowlist отсутствует — нарушение с её адресом', () => {
    writeSite();
    const problems = checkDist({
      dist,
      base,
      expectedPages: ['/codelab-app/docs/user/', '/codelab-app/docs/apps/codelab_cli/'],
    });
    expect(problems).toEqual([
      expect.objectContaining({ message: expect.stringContaining('/codelab-app/docs/apps/codelab_cli/') }),
    ]);
  });

  it('все ожидаемые страницы есть — без нарушений', () => {
    writeSite();
    expect(
      checkDist({ dist, base, expectedPages: ['/codelab-app/docs/user/', '/codelab-app/docs/user/configuration/'] }),
    ).toEqual([]);
  });

  it('код elkjs в файле dist/ — нарушение с именем файла (D2, D7)', () => {
    writeSite();
    write(
      '_astro/chunk.q1w2e3.js',
      'var a={"org.eclipse.elk.algorithm":"org.eclipse.elk.layered"};export{a};',
    );
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({
        file: '_astro/chunk.q1w2e3.js',
        message: expect.stringContaining('elkjs'),
      }),
    ]);
  });
});

describe('checkDist: схемы ссылок <a> (D6, D11)', () => {
  it('http, https, mailto, внутренние, относительные и #якорь — без нарушений', () => {
    writeSite();
    write(
      'docs/ops/index.html',
      page(
        '<h2 id="раздел">Раздел</h2>' +
          '<a href="http://example.com/">http</a>' +
          '<a href="HTTPS://example.com/">https</a>' +
          '<a href="mailto:team@example.com">mailto</a>' +
          '<a href="/codelab-app/docs/user/">внутренняя</a>' +
          '<a href="../user/configuration/">относительная</a>' +
          '<a href="#раздел">якорь</a>',
      ),
    );
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it.each([
    ['javascript:', 'javascript:alert(1)'],
    ['JavaScript: в другом регистре', 'JavaScript:alert(1)'],
    ['javascript: с табуляцией внутри схемы', 'java&#9;script:alert(1)'],
    ['data:', 'data:text/html;base64,PHNjcmlwdD4='],
    ['vbscript:', 'vbscript:msgbox(1)'],
    ['file:', 'file:///etc/passwd'],
    ['ftp:', 'ftp://example.com/a'],
  ])('%s — нарушение', (_name, href) => {
    writeSite();
    write('docs/ops/index.html', page(`<a href="${href}">x</a>`));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('scheme') }),
    ]);
  });
});

describe('checkDist: data: и атрибуты ресурсов (D2, D6, D8)', () => {
  it('data: у img и source — без нарушений', () => {
    writeSite();
    write(
      'docs/ops/index.html',
      page(
        '<img src="data:image/png;base64,AAAA" alt="a">' +
          '<picture><source srcset="data:image/webp;base64,AAAA 1x"><img src="/codelab-app/_astro/command-palette.xyz.png" alt="b"></picture>',
      ),
    );
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it.each([
    ['script', '<script src="data:text/javascript,alert(1)"></script>', 'data:text/javascript,alert(1)'],
    ['iframe', '<iframe src="data:text/html,x"></iframe>', 'data:text/html,x'],
    ['link', '<link rel="stylesheet" href="data:text/css,body{}">', 'data:text/css,body{}'],
    ['object data', '<object data="data:text/html,x"></object>', 'data:text/html,x'],
  ])('data: у %s — нарушение', (_name, html, link) => {
    writeSite();
    write('docs/ops/index.html', page(html));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', link }),
    ]);
  });

  it.each([
    ['object data', '<object data="https://example.com/a.swf"></object>', 'https://example.com/a.swf'],
    ['form action', '<form action="https://example.com/collect"></form>', 'https://example.com/collect'],
    ['video poster', '<video poster="https://example.com/p.png"></video>', 'https://example.com/p.png'],
  ])('%s с чужого хоста — нарушение', (_name, html, link) => {
    writeSite();
    write('docs/ops/index.html', page(html));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', link }),
    ]);
  });

  it.each([
    ['object data', '<object data="/codelab-app/_astro/missing.svg"></object>', '/codelab-app/_astro/missing.svg'],
    ['video poster', '<video poster="/codelab-app/_astro/missing.png"></video>', '/codelab-app/_astro/missing.png'],
  ])('%s на несуществующий файл — нарушение', (_name, html, link) => {
    writeSite();
    write('docs/ops/index.html', page(html));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', link }),
    ]);
  });

  it('video poster на существующий файл — без нарушений', () => {
    writeSite();
    write('docs/ops/index.html', page('<video poster="/codelab-app/_astro/command-palette.xyz.png"></video>'));
    expect(checkDist({ dist, base })).toEqual([]);
  });
});

describe('checkDist: страницы docs/ только из allowlist (обратная проверка D14)', () => {
  it('страницы опубликованных файлов и оглавление /docs/ — без нарушений', () => {
    writeSite();
    write('docs/index.html', page('<h1 id="x">Документация</h1>'));
    write('docs/apps/codelab_cli/index.html', page('<h1 id="x">CLI</h1>'));
    write('docs/apps/codelab_cli/doc/user-guide/index.html', page('<h1 id="x">Руководство</h1>'));
    write('docs/packages/dart/codelab_setup/index.html', page('<h1 id="x">setup</h1>'));
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it.each([
    ['docs/architecture/testing/index.html', 'docs/architecture/'],
    ['docs/backlog/x/index.html', 'docs/backlog/'],
    ['docs/apps/codelab_cli/AGENTS/index.html', 'AGENTS.md'],
    ['docs/openspec/specs/x/spec/index.html', 'openspec/'],
  ])('лишняя страница %s — нарушение', (file) => {
    writeSite();
    write(file, page('<h1 id="x">Лишняя</h1>'));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file, message: expect.stringContaining('allowlist') }),
    ]);
  });
});

// Правила витрины (tasks.md redesign-site-showcase, 2.1; D2, D12; project-site
// «Интерактивные демо витрины»: «Второй встроенный скрипт ломает проверку»,
// «Превышение бюджета»; «Мета-данные страниц и знак сайта»: «Картинка неверного
// размера»).
describe('checkDist: встроенные скрипты (D12 п. 1)', () => {
  const themeScript = '<script>document.documentElement.dataset.t=1</script>';

  it('один одинаковый встроенный скрипт на каждой странице — без нарушений', () => {
    writeSite();
    write('docs/user/index.html', page(`${themeScript}<h1 id="x">x</h1>`));
    write('docs/user/configuration/index.html', page(`${themeScript}<h1 id="y">y</h1>`));
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it('второй встроенный скрипт на странице — нарушение со страницей', () => {
    writeSite();
    write('docs/ops/index.html', page(`${themeScript}${themeScript}`));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('inline') }),
    ]);
  });

  it('два одинаковых встроенных скрипта на странице — всё равно нарушение', () => {
    writeSite();
    write('docs/ops/index.html', page(`${themeScript}<script>document.documentElement.dataset.t=1</script>`));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('inline') }),
    ]);
  });

  it('текст встроенного скрипта на двух страницах различается — нарушение (хэш CSP)', () => {
    writeSite();
    write('docs/user/index.html', page(`${themeScript}<h1 id="x">x</h1>`));
    write('docs/ops/index.html', page('<script>document.documentElement.dataset.t=2</script>'));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ message: expect.stringContaining('differs') }),
    ]);
  });

  it('скрипт с src не считается встроенным', () => {
    writeSite();
    write('docs/ops/index.html', page('<script type="module" src="/codelab-app/_astro/page.def456.js"></script>'));
    expect(checkDist({ dist, base })).toEqual([]);
  });
});

describe('checkDist: обработчики событий (D12 п. 2)', () => {
  it.each(['onclick', 'onLoad', 'onerror'])('атрибут %s — нарушение', (attr) => {
    writeSite();
    write('docs/ops/index.html', page(`<img src="/codelab-app/_astro/command-palette.xyz.png" alt="x" ${attr}="f()">`));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining(attr.toLowerCase()) }),
    ]);
  });

  it('javascript: в атрибуте без ссылки — нарушение', () => {
    writeSite();
    write('docs/ops/index.html', page('<button formaction="javascript:f()">x</button>'));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('javascript:') }),
    ]);
  });

  it('data-атрибуты и атрибут «one» без ловушки on* — без нарушений', () => {
    writeSite();
    write('docs/ops/index.html', page('<div data-onclick="x" data-demo="workbench" one="1">x</div>'));
    expect(checkDist({ dist, base })).toEqual([]);
  });
});

describe('checkDist: бюджет JavaScript витрины (D2 п. 8, D12 п. 3)', () => {
  /** Несжимаемое содержимое: гарантированно больше порога после gzip. */
  const heavy = randomBytes(20_000).toString('base64');

  function moduleHtml(entries: string[]): string {
    return page(
      entries.map((e) => `<script type="module" src="/codelab-app/_astro/${e}"></script>`).join(''),
    );
  }

  /** Манифест сборки: чанк → его статические импорты и исходные модули (от корня репозитория). */
  const chunks = {
    '_astro/theme.js': { imports: ['_astro/shared.js'], modules: ['site/src/scripts/theme.ts'] },
    '_astro/mermaid.js': { imports: ['_astro/shared.js'], modules: ['site/src/scripts/mermaid.ts'] },
    '_astro/shared.js': { imports: [], modules: ['site/src/scripts/theme-state.ts'] },
    '_astro/demo.js': { imports: ['_astro/demo-lib.js'], modules: ['site/src/scripts/showcase/demo.ts'] },
    '_astro/demo-lib.js': { imports: [], modules: ['site/src/lib/showcase/x.ts'] },
  };

  it('модули демо в пределах бюджета — без нарушений', () => {
    writeSite();
    write('docs/ops/index.html', moduleHtml(['demo.js']));
    write('_astro/demo.js', 'import"./demo-lib.js";console.log(1)');
    write('_astro/demo-lib.js', 'export{}');
    expect(checkDist({ dist, base, chunks })).toEqual([]);
  });

  it('демо больше 12 КБ gzip — нарушение со страницей и размером', () => {
    writeSite();
    write('docs/ops/index.html', moduleHtml(['demo.js']));
    write('_astro/demo.js', `import"./demo-lib.js";var a="${heavy}"`);
    write('_astro/demo-lib.js', 'export{}');
    const problems = checkDist({ dist, base, chunks });
    expect(problems).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringMatching(/12 KB.*\d+(\.\d+)? KB/) }),
    ]);
  });

  it('статический импорт чанка входит в сумму модуля', () => {
    writeSite();
    write('docs/ops/index.html', moduleHtml(['demo.js']));
    write('_astro/demo.js', 'import"./demo-lib.js";console.log(1)');
    write('_astro/demo-lib.js', `export var a="${heavy}"`);
    expect(checkDist({ dist, base, chunks })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('12 KB') }),
    ]);
  });

  it('тема и mermaid в сумму не входят, даже когда они больше бюджета', () => {
    writeSite();
    write('docs/ops/index.html', moduleHtml(['theme.js', 'mermaid.js']));
    write('_astro/theme.js', `import"./shared.js";var a="${heavy}"`);
    write('_astro/mermaid.js', `import"./shared.js";var b="${heavy}"`);
    write('_astro/shared.js', 'export{}');
    expect(checkDist({ dist, base, chunks })).toEqual([]);
  });

  it('тема, определённая по манифесту, а не по имени файла', () => {
    writeSite();
    write('docs/ops/index.html', moduleHtml(['renamed.js']));
    write('_astro/renamed.js', `var a="${heavy}"`);
    const renamed = { '_astro/renamed.js': { imports: [], modules: ['site/src/scripts/theme.ts'] } };
    expect(checkDist({ dist, base, chunks: renamed })).toEqual([]);
  });

  it('смешанный входной чанк (тема и демо вместе) в бюджет входит', () => {
    writeSite();
    write('docs/ops/index.html', moduleHtml(['mixed.js']));
    write('_astro/mixed.js', `var a="${heavy}"`);
    const mixed = {
      '_astro/mixed.js': { imports: [], modules: ['site/src/scripts/theme.ts', 'site/src/scripts/showcase/demo.ts'] },
    };
    expect(checkDist({ dist, base, chunks: mixed })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('12 KB') }),
    ]);
  });

  it('модуль, которого нет в манифесте, считается модулем демо', () => {
    writeSite();
    write('docs/ops/index.html', moduleHtml(['unknown.js']));
    write('_astro/unknown.js', `var a="${heavy}"`);
    expect(checkDist({ dist, base, chunks })).toEqual([
      expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('12 KB') }),
    ]);
  });
});

describe('checkDist: картинка для ссылок (D10, D12 п. 4)', () => {
  /** PNG с заголовком IHDR нужного размера; остальное содержимое неважно. */
  function png(width: number, height: number): Buffer {
    const header = Buffer.alloc(33);
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).copy(header);
    header.writeUInt32BE(13, 8);
    header.write('IHDR', 12, 'latin1');
    header.writeUInt32BE(width, 16);
    header.writeUInt32BE(height, 20);
    return header;
  }

  function withOgImage(content: string | undefined): void {
    const meta = content === undefined ? '' : `<meta property="og:image" content="${content}">`;
    write('index.html', page('<h1 id="x">x</h1>', meta));
  }

  it('PNG 1200×630 по абсолютному адресу — без нарушений', () => {
    writeSite();
    withOgImage('https://example.org/codelab-app/og.png');
    write('og.png', png(1200, 630));
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it('PNG 1200×631 — нарушение с путём и размером', () => {
    writeSite();
    withOgImage('https://example.org/codelab-app/og.png');
    write('og.png', png(1200, 631));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'og.png', message: expect.stringContaining('1200×631') }),
    ]);
  });

  it('отсутствующий файл og:image — нарушение', () => {
    writeSite();
    withOgImage('https://example.org/codelab-app/og.png');
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'index.html', link: 'https://example.org/codelab-app/og.png' }),
    ]);
  });

  it('не PNG — нарушение', () => {
    writeSite();
    withOgImage('https://example.org/codelab-app/og.png');
    write('og.png', '<svg></svg>');
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'og.png', message: expect.stringContaining('PNG') }),
    ]);
  });

  it('og:image вне base — нарушение', () => {
    writeSite();
    withOgImage('https://example.org/other/og.png');
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'index.html', message: expect.stringContaining('base') }),
    ]);
  });

  it('без og:image (нет SITE_URL) файл картинки по известному адресу всё равно проверяется', () => {
    writeSite();
    withOgImage(undefined);
    write('og.png', png(1200, 600));
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({ file: 'og.png', message: expect.stringContaining('1200×600') }),
    ]);
  });

  it('без og:image и без файла картинки — без нарушений', () => {
    writeSite();
    withOgImage(undefined);
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it('requireOgImage: нет dist/og.png — нарушение, даже без og:image на страницах', () => {
    writeSite();
    withOgImage(undefined);
    expect(checkDist({ dist, base, requireOgImage: true })).toEqual([
      expect.objectContaining({ file: 'og.png', message: expect.stringContaining('og.png') }),
    ]);
  });

  it('requireOgImage: файл есть и верного размера — без нарушений', () => {
    writeSite();
    withOgImage(undefined);
    write('og.png', png(1200, 630));
    expect(checkDist({ dist, base, requireOgImage: true })).toEqual([]);
  });
});

describe('checkDist: рантайм поиска и индекс (D8, D10)', () => {
  const runtime = 'pagefind/pagefind.js';

  /** Страница документа без ссылок: годится для любого `base`. */
  function writeDocs(): void {
    write('index.html', page('<p>главная</p>'));
    write('docs/ops/index.html', page('<h1>Эксплуатация</h1>'));
  }

  function withIndex(): void {
    writeDocs();
    write(runtime, 'export{}');
  }

  for (const siteBase of ['/', '/codelab-app/']) {
    describe(`base ${siteBase}`, () => {
      const url = `${siteBase}${runtime}`;

      it.each([
        ['script src', `<script type="module" src="${url}"></script>`],
        ['modulepreload', `<link rel="modulepreload" href="${url}">`],
        ['preload', `<link rel="preload" as="script" href="${url}">`],
        ['prefetch', `<link rel="prefetch" href="${url}">`],
      ])('статическая ссылка (%s) на рантайм поиска — нарушение со страницей', (_name, tag) => {
        withIndex();
        write('docs/ops/index.html', page('', tag));
        const problems = checkDist({ dist, base: siteBase });
        expect(problems).toEqual([
          expect.objectContaining({ file: 'docs/ops/index.html', message: expect.stringContaining('search runtime') }),
        ]);
      });

      it('страницы документов с индексом и без ссылок на него — без нарушений', () => {
        withIndex();
        expect(checkDist({ dist, base: siteBase, requireSearchIndex: true })).toEqual([]);
      });

      it('страницы документов без индекса — ошибка об отсутствующем индексе', () => {
        writeDocs();
        const problems = checkDist({ dist, base: siteBase, requireSearchIndex: true });
        expect(problems).toEqual([
          expect.objectContaining({ file: runtime, message: expect.stringContaining('search index is missing') }),
        ]);
      });
    });
  }

  it('обычная ссылка <a> на pagefind/ не считается статической загрузкой рантайма', () => {
    withIndex();
    write('docs/ops/index.html', page(`<a href="${base}${runtime}">индекс</a>`));
    expect(checkDist({ dist, base })).toEqual([]);
  });

  it('без страниц документов индекс не требуется', () => {
    write('index.html', page('<p>главная</p>'));
    expect(checkDist({ dist, base, requireSearchIndex: true })).toEqual([]);
  });

  it('индекс по умолчанию не требуется: прежние сборки проверяются без него', () => {
    writeDocs();
    expect(checkDist({ dist, base })).toEqual([]);
  });
});

describe('checkDist: сообщение бюджета страницы (D7, D10)', () => {
  it('называет бюджет страницы и исключения', () => {
    writeSite();
    const heavy = randomBytes(20_000).toString('base64');
    write('docs/ops/index.html', page('', '<script type="module" src="/codelab-app/_astro/big.js"></script>'));
    write('_astro/big.js', `var a="${heavy}"`);
    expect(checkDist({ dist, base })).toEqual([
      expect.objectContaining({
        message: expect.stringContaining('page JavaScript budget is 12 KB gzip without theme, mermaid and search runtime'),
      }),
    ]);
  });
});
