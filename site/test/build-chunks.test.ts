// Тесты манифеста чанков сборки (tasks.md redesign-site-showcase, 2.2; D12 п. 3).
// Манифест нужен `check-links`, чтобы отличить модули темы и mermaid от модулей
// демо по исходным файлам, а не по имени чанка с хэшем.
import { describe, expect, it } from 'vitest';

import { chunksFromBundle } from '../src/plugins/build-chunks';

const root = '/work/repo';

describe('chunksFromBundle', () => {
  it('чанк → статические импорты и исходные модули от корня репозитория', () => {
    const bundle = {
      '_astro/a.js': {
        type: 'chunk',
        fileName: '_astro/a.js',
        imports: ['_astro/b.js'],
        dynamicImports: ['_astro/lazy.js'],
        modules: {
          [`${root}/site/src/scripts/theme.ts`]: {},
          [`${root}/site/src/components/Header.astro?astro&type=script&index=0&lang.ts`]: {},
          [`${root}/site/node_modules/mermaid/dist/x.mjs`]: {},
          '\0rolldown/runtime.js': {},
        },
      },
      '_astro/style.css': { type: 'asset', fileName: '_astro/style.css' },
    };

    expect(chunksFromBundle(bundle, root)).toEqual({
      '_astro/a.js': {
        imports: ['_astro/b.js'],
        modules: [
          'site/src/scripts/theme.ts',
          'site/src/components/Header.astro?astro&type=script&index=0&lang.ts',
        ],
      },
    });
  });

  it('модуль вне корня репозитория остаётся без абсолютного пути в манифесте', () => {
    const bundle = {
      'x.js': { type: 'chunk', fileName: 'x.js', imports: [], modules: { '/other/place/y.ts': {} } },
    };
    expect(chunksFromBundle(bundle, root)['x.js']!.modules).toEqual([]);
  });
});
