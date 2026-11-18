// Тесты проверки личных путей (tasks.md add-astro-site, 3.7; D11;
// project-site «Безопасность публикации», сценарии «Личный путь в документе»,
// «Замаскированный путь»; `codelab-docs` §7).
import remarkParse from 'remark-parse';
import { unified } from 'unified';
import { VFile } from 'vfile';
import { describe, expect, it } from 'vitest';

import { remarkHomePaths } from '../src/plugins/home-paths';

const doc = '/repo/docs/user/configuration.md';

async function check(markdown: string): Promise<void> {
  const processor = unified().use(remarkParse).use(remarkHomePaths);
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
