// Тесты проверки собранного сайта (tasks.md add-astro-site, 3.11; D2, D6, D7,
// D11, D14; project-site «Проверка внутренних ссылок собранного сайта»,
// «Сборка под подкаталог», «Нет сторонних запросов») на мини-`dist/` во
// временном каталоге, без сети.
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

function write(path: string, content: string): void {
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
