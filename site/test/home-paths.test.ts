// Тесты проверки личных путей (tasks.md add-astro-site, 3.7; D11;
// project-site «Безопасность публикации», сценарии «Личный путь в документе»,
// «Замаскированный путь»; `codelab-docs` §7).
import remarkParse from 'remark-parse';
import { unified } from 'unified';
import { VFile } from 'vfile';
import { describe, expect, it } from 'vitest';

import { findHomePaths } from '../src/lib/home-paths';
import { remarkHomePaths } from '../src/plugins/home-paths';

const doc = '/repo/docs/user/configuration.md';

async function check(markdown: string): Promise<void> {
  const processor = unified().use(remarkParse).use(remarkHomePaths, { repoRoot: '/repo' });
  const file = new VFile({ path: doc, value: markdown });
  await processor.run(processor.parse(file), file);
}

describe('remarkHomePaths: личные пути — ошибка с путём файла и строкой', () => {
  it.each([
    ['текст, macOS', '# Настройка\n\nПроект в /Users/alice/projects/demo.\n', 3],
    ['текст, Linux', '# Настройка\n\nФайл /home/bob/.codelab/config.yaml.\n', 3],
    ['текст, Windows', '# Настройка\n\nПапка C:\\Users\\eve\\AppData\\codelab.\n', 3],
    ['инлайн-код', '# Настройка\n\nЗапустите `cat /home/bob/.codelab/config.yaml`.\n', 3],
    ['маска как префикс имени не спасает', '# Настройка\n\nПуть /home/meow/x.\n', 3],
  ])('%s', async (_name, markdown, line) => {
    await expect(check(markdown)).rejects.toMatchObject({ file: doc, line });
  });

  it.each([
    ['macOS', '/Users/alice/projects/demo'],
    ['Linux', '/home/bob/.codelab/config.yaml'],
    ['Windows', 'C:\\Users\\eve\\AppData\\codelab'],
  ])('блок кода, %s', async (_name, path) => {
    await expect(
      check(`# Настройка\n\n\`\`\`text\nConfig: ${path}\n\`\`\`\n`),
    ).rejects.toMatchObject({ file: doc, message: expect.stringContaining(path.slice(0, 12)) });
  });
});

describe('remarkHomePaths: маски и относительные пути проходят', () => {
  it.each([
    '/home/me/.codelab/config.yaml',
    '/Users/user/projects/demo',
    '/Users/me/projects/demo',
    '/home/user/.codelab',
    'C:\\Users\\user\\AppData\\codelab',
    '~/.codelab/config.yaml',
    '/usr/local/bin/codelab',
  ])('%s', async (path) => {
    await expect(
      check(`# Настройка\n\nТекст ${path}.\n\n\`${path}\`\n\n\`\`\`text\n${path}\n\`\`\`\n`),
    ).resolves.toBeUndefined();
  });
});

describe('remarkHomePaths: формат сообщения', () => {
  it('путь файла от корня репозитория и строка, без абсолютного пути', async () => {
    const error = await check('# Настройка\n\nПроект в /Users/alice/projects/demo.\n').catch((e: unknown) => e);
    expect((error as Error).message).toContain('in docs/user/configuration.md:3');
    expect((error as Error).message).not.toContain('/repo/');
  });
});

describe('findHomePaths: другие записи пути (D11)', () => {
  it.each([
    ['Windows, обратные слэши', 'C:\\Users\\alice\\AppData'],
    ['Windows, двойные обратные слэши (JSON, строки JS)', '"C:\\\\Users\\\\alice\\\\AppData"'],
    ['Windows, прямые слэши', 'C:/Users/alice/AppData'],
    ['Fedora Silverblue, /var/home', 'cd /var/home/alice/projects'],
    ['URL-кодированный /Users', 'path=%2FUsers%2Falice%2Fprojects'],
    ['URL-кодированный /home, строчные hex', 'path=%2fhome%2falice%2f.codelab'],
  ])('%s — найден', (_name, text) => {
    expect(findHomePaths(text)).toEqual([expect.objectContaining({ path: expect.stringContaining('alice') })]);
  });

  it.each([
    'C:\\\\Users\\\\user\\\\AppData',
    'C:/Users/me/AppData',
    '/var/home/me/projects',
    '%2FUsers%2Fuser%2Fprojects',
    '%2Fhome%2Fme%2F.codelab',
    '/var/lib/home/x',
  ])('маска или не домашний каталог %s — не найден', (text) => {
    expect(findHomePaths(text)).toEqual([]);
  });
});
