// Тесты заголовка и описания документа (tasks.md add-astro-site, 4.1; D3;
// project-site «Публикуемые источники документации», сценарии «Страница
// собирается из файла репозитория», «Документ без заголовка»).
import { describe, expect, it } from 'vitest';

import { DocTitleError, docMeta } from '../src/lib/doc-meta';

describe('docMeta', () => {
  it('заголовок — первый `#`, описание — первый абзац после него', () => {
    const meta = docMeta(
      '# Настройка агента\n\nВстроенный агент читает `config.yaml`.\n\n## Шаг 1\n\nТекст.\n',
      'docs/user/configuration.md',
    );
    expect(meta).toEqual({
      title: 'Настройка агента',
      description: 'Встроенный агент читает config.yaml.',
    });
  });

  it('заголовок с кодом и ссылкой — только текст', () => {
    const meta = docMeta('# Каталог `CODELAB_HOME`\n\n[Ссылка](a.md) и **жирный**.\n', 'docs/ops/codelab-home.md');
    expect(meta.title).toBe('Каталог CODELAB_HOME');
    expect(meta.description).toBe('Ссылка и жирный.');
  });

  it('пропускает изображения и блоки кода до первого абзаца', () => {
    const meta = docMeta(
      '# App\n\n```bash\nrun\n```\n\n![Снимок](images/a.png)\n\nПервый абзац.\n',
      'apps/x/README.md',
    );
    expect(meta.description).toBe('Первый абзац.');
  });

  it('`#` внутри блока кода — не заголовок', () => {
    expect(() => docMeta('```bash\n# comment\n```\n\nТекст.\n', 'apps/x/doc/a.md')).toThrow(
      DocTitleError,
    );
  });

  it('без заголовка первого уровня — ошибка с путём файла', () => {
    expect(() => docMeta('## Только второй уровень\n\nТекст.\n', 'docs/user/zed.md')).toThrow(
      /docs\/user\/zed\.md/,
    );
  });

  it('длинное описание обрезается по границе слова', () => {
    const words = Array.from({ length: 80 }, (_, i) => `слово${i}`).join(' ');
    const { description } = docMeta(`# T\n\n${words}\n`, 'docs/user/a.md');
    expect(description.length).toBeLessThanOrEqual(161);
    expect(description.endsWith('…')).toBe(true);
    expect(words.startsWith(description.slice(0, -1))).toBe(true);
    expect(description.slice(0, -1).endsWith(' ')).toBe(false);
  });

  it('без абзаца — пустое описание', () => {
    expect(docMeta('# T\n\n## Раздел\n', 'docs/user/a.md').description).toBe('');
  });
});
